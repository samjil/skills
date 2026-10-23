// 화면 테마(시스템 따라가기 / 라이트 / 다크) 테스트.
//   node tests/viewer/theme.tests.js
// 확인하는 것: (1) 테마 결정 규칙(app.js 의 resolveTheme)과 index.html 머리의 첫 그리기 전 스크립트가 같은 결과를 내는지,
// (2) 그 스크립트가 스타일시트보다 먼저 도는지(늦으면 어두운 화면이 번쩍 보인다), (3) 밝은 테마가 어두운 테마의 색 토큰을 빠짐없이 다시 정의했는지,
// (4) 밝은 테마의 모든 글자색이 각 면 위에서 WCAG 대비 4.5 이상인지(어두운 테마도 같은 쌍을 본다).
// 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다.

"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const webDir = path.join(__dirname, "..", "..", "runtime", "viewer", "web");
const appJs = fs.readFileSync(path.join(webDir, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(webDir, "index.html"), "utf8");
const css = fs.readFileSync(path.join(webDir, "style.css"), "utf8");

let passed = 0, failed = 0;
function assertEqual(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "  (기대: " + e + " / 실제: " + a + ")"); }
}

function extractFunction(name) {
  const start = appJs.indexOf("function " + name + "(");
  if (start < 0) throw new Error(name + " 를 app.js 에서 찾지 못했습니다.");
  let i = appJs.indexOf("{", start), depth = 0;
  for (; i < appJs.length; i++) {
    if (appJs[i] === "{") depth++;
    else if (appJs[i] === "}") { depth--; if (depth === 0) return appJs.slice(start, i + 1); }
  }
  throw new Error(name + " 의 끝을 찾지 못했습니다.");
}

// ---------------------------------------------------------------- (1) 결정 규칙
console.log("테마 결정 규칙 (app.js)");
const api = new Function(extractFunction("normalizeThemePref") + "\n" + extractFunction("resolveTheme") + "\nreturn { normalizeThemePref, resolveTheme };")();
assertEqual("저장된 값이 없거나 이상하면 '시스템'", ["system", "system", "system", "system"], [api.normalizeThemePref(undefined), api.normalizeThemePref(null), api.normalizeThemePref(""), api.normalizeThemePref("blue")]);
assertEqual("  light / dark 는 그대로", ["light", "dark"], [api.normalizeThemePref("light"), api.normalizeThemePref("dark")]);
assertEqual("시스템: 기기가 라이트면 라이트, 아니면 다크", ["light", "dark"], [api.resolveTheme("system", true), api.resolveTheme("system", false)]);
assertEqual("직접 고른 것은 기기 설정과 무관", ["light", "light", "dark", "dark"], [api.resolveTheme("light", true), api.resolveTheme("light", false), api.resolveTheme("dark", true), api.resolveTheme("dark", false)]);
assertEqual("  이상한 값은 시스템처럼", ["light", "dark"], [api.resolveTheme("x", true), api.resolveTheme("x", false)]);

// ---------------------------------------------------------------- (2) 머리 스크립트
console.log("첫 그리기 전 스크립트 (index.html)");
const initMatch = /<script id="theme-init">([\s\S]*?)<\/script>/.exec(indexHtml);
assertEqual("theme-init 스크립트가 있다", true, Boolean(initMatch));

function runInit(opts) {
  const attrs = {};
  const links = { "hljs-dark": { disabled: false }, "hljs-light": { disabled: true } };
  const sandbox = {
    document: { documentElement: { setAttribute: (k, v) => { attrs[k] = v; } }, getElementById: (id) => links[id] },
    localStorage: opts.storageThrows ? { getItem() { throw new Error("blocked"); } } : { getItem: () => (opts.stored === undefined ? null : opts.stored) },
    window: {}
  };
  if (opts.noMatchMedia) { sandbox.window = {}; }
  else { sandbox.window = { matchMedia: (q) => ({ matches: q === "(prefers-color-scheme: light)" ? Boolean(opts.systemLight) : false }) }; }
  vm.runInNewContext(initMatch[1], sandbox);
  return { theme: attrs["data-theme"], pref: attrs["data-theme-pref"], darkCss: !links["hljs-dark"].disabled, lightCss: !links["hljs-light"].disabled };
}
const cases = [
  [{ systemLight: true }, "light", "system"],
  [{ systemLight: false }, "dark", "system"],
  [{ stored: "light", systemLight: false }, "light", "light"],
  [{ stored: "dark", systemLight: true }, "dark", "dark"],
  [{ stored: "system", systemLight: true }, "light", "system"],
  [{ stored: "garbage", systemLight: true }, "light", "system"],
  [{ storageThrows: true, systemLight: true }, "light", "system"],
  [{ noMatchMedia: true }, "dark", "system"]
];
cases.forEach(function (c) {
  const r = runInit(c[0]);
  assertEqual("  " + JSON.stringify(c[0]) + " -> " + c[1] + " (선택 " + c[2] + ")", [c[1], c[2]], [r.theme, r.pref]);
  // app.js 의 규칙과 같은 결과인지(저장값이 이상하면 시스템으로 본다)
  const stored = c[0].storageThrows ? undefined : c[0].stored;
  assertEqual("    app.js 규칙과 같다", api.resolveTheme(stored, Boolean(c[0].systemLight) && !c[0].noMatchMedia), r.theme);
});
const rl = runInit({ systemLight: true });
assertEqual("라이트면 라이트 코드 스타일만 켠다", [false, true], [rl.darkCss, rl.lightCss]);
const rd = runInit({ systemLight: false });
assertEqual("다크면 다크 코드 스타일만 켠다", [true, false], [rd.darkCss, rd.lightCss]);

const initPos = indexHtml.indexOf('<script id="theme-init">');
const cssPos = indexHtml.indexOf('href="style.css');
const hljsPos = indexHtml.indexOf('id="hljs-light"');
assertEqual("스크립트는 코드 스타일 링크 뒤, style.css 앞이다(첫 그리기 전에 정하고, 링크는 이미 읽힌 뒤여야 켜고 끌 수 있다)", true, hljsPos > 0 && hljsPos < initPos && initPos < cssPos);
assertEqual("color-scheme 메타가 두 테마를 알린다", true, /<meta name="color-scheme" content="dark light">/.test(indexHtml));
assertEqual("선택 버튼이 셋(시스템·라이트·다크)이고 기본은 시스템이 눌려 있다", [3, true], [(indexHtml.match(/data-theme-pref="(system|light|dark)"/g) || []).length, /data-theme-pref="system" aria-pressed="true"/.test(indexHtml)]);

// ---------------------------------------------------------------- (3) 토큰 짝
console.log("색 토큰 (style.css)");
function blockOf(selectorRe) {
  const m = selectorRe.exec(css);
  if (!m) throw new Error("블록을 찾지 못했습니다: " + selectorRe);
  let i = css.indexOf("{", m.index), depth = 0;
  for (let j = i; j < css.length; j++) {
    if (css[j] === "{") depth++;
    else if (css[j] === "}") { depth--; if (depth === 0) return css.slice(i + 1, j); }
  }
  throw new Error("블록 끝을 찾지 못했습니다");
}
function tokensOf(block) {
  const out = {};
  const re = /(--[a-z0-9-]+):\s*([^;]+);/g;
  let m;
  while ((m = re.exec(block))) { out[m[1]] = m[2].trim(); }
  return out;
}
const dark = tokensOf(blockOf(/(^|\n):root\s*\{/));
const light = tokensOf(blockOf(/:root\[data-theme="light"\]\s*\{/));
const isColorToken = (v) => /^#[0-9a-fA-F]{3,8}$/.test(v) || /^rgba?\(/.test(v) || /^\d+,\s*\d+,\s*\d+$/.test(v);
const colorTokens = Object.keys(dark).filter((k) => isColorToken(dark[k]) || k.startsWith("--shadow") || k === "--backdrop");
assertEqual("어두운 테마에 색 토큰이 충분히 있다(35개 이상)", true, colorTokens.length >= 35);
const missing = colorTokens.filter((k) => !(k in light));
assertEqual("밝은 테마가 어두운 테마의 색 토큰을 하나도 빠뜨리지 않고 다시 정의한다", [], missing);
assertEqual("밝은 테마는 color-scheme: light 를 알린다", true, /color-scheme:\s*light/.test(blockOf(/:root\[data-theme="light"\]\s*\{/)));

// ---------------------------------------------------------------- (4) 대비
console.log("글자 대비 (WCAG, 4.5 이상)");
function rgbOf(v) {
  let m = /^#([0-9a-fA-F]{6})$/.exec(v);
  if (m) { const n = parseInt(m[1], 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
  m = /^#([0-9a-fA-F]{3})$/.exec(v);
  if (m) { return m[1].split("").map((c) => parseInt(c + c, 16)); }
  throw new Error("색을 읽지 못했습니다: " + v);
}
function lum(rgb) {
  const l = rgb.map((c) => { const s = c / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); });
  return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2];
}
function contrast(fg, bg) {
  const a = lum(rgbOf(fg)), b = lum(rgbOf(bg));
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}
const textTokens = ["--ink", "--ink-2", "--ink-3", "--claude", "--agy", "--ok", "--err", "--warn", "--link", "--err-text", "--alert-note", "--alert-tip", "--alert-important", "--alert-warning", "--alert-caution"];
const surfaces = ["--bg", "--surface", "--raised", "--sunken", "--code-bg"];
function checkTheme(label, tokens, skip) {
  const low = [];
  textTokens.forEach(function (t) {
    surfaces.forEach(function (s) {
      if (skip && skip.indexOf(t + "|" + s) >= 0) return;
      // 색 글자(황토·청록·알림 색)는 코드 바탕 위에 쓰지 않으므로, 본문 글자 토큰만 코드 바탕과 짝지어 본다
      if (s === "--code-bg" && ["--ink", "--ink-2", "--err-text", "--link"].indexOf(t) < 0) return;
      if (!tokens[t] || !tokens[s]) return;
      const c = contrast(tokens[t], tokens[s]);
      if (c < 4.5) low.push(t + " 위 " + s + " = " + c.toFixed(2));
    });
  });
  assertEqual(label, [], low);
}
checkTheme("밝은 테마: 글자 토큰이 모든 면 위에서 4.5 이상", light);
// 어두운 테마는 이 시험이 생기기 전부터 있던 값이라, 4.5 에 못 미치는 기존 쌍은 목록으로 남겨 두고 새 쌍이 생기면 실패한다
checkTheme("어두운 테마: 기존 값 그대로(회귀 확인)", dark, ["--ink-3|--raised", "--ink-3|--surface", "--ink-3|--sunken", "--ink-2|--code-bg", "--err|--raised", "--alert-warning|--raised", "--alert-note|--raised", "--alert-caution|--raised", "--alert-important|--raised", "--alert-tip|--raised"]);

console.log("");
console.log("통과 " + passed + " / 실패 " + failed);
process.exit(failed ? 1 : 0);
