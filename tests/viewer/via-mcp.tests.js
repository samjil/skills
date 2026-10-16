// 위임 경로 판별(viaMcp) 순수 함수 테스트: source 가 mcp 인 기록만 MCP 로 보고, bridge·옛 기록(필드 없음)은 표시하지 않는다.
//   node tests/viewer/via-mcp.tests.js
// runtime/viewer/web/app.js 에서 함수 원문을 꺼내 그대로 실행합니다. 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다.

"use strict";
const fs = require("fs");
const path = require("path");

const appJs = fs.readFileSync(path.join(__dirname, "..", "..", "runtime", "viewer", "web", "app.js"), "utf8");

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

const api = new Function(extractFunction("viaMcp") + "\nreturn { viaMcp };")();

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\n        기대: " + e + "\n        실제: " + a); }
}

console.log("viaMcp: 위임 경로");
eq("source 가 mcp 이면 MCP", true, api.viaMcp({ source: "mcp" }));
eq("  대소문자·공백은 무시", [true, true], [api.viaMcp({ source: "MCP" }), api.viaMcp({ source: " mcp " })]);
eq("bridge 는 표시하지 않는다", false, api.viaMcp({ source: "bridge" }));
eq("source 필드가 없는 옛 기록은 bridge 로 본다", [false, false, false], [api.viaMcp({}), api.viaMcp({ source: "" }), api.viaMcp({ source: null })]);
eq("모르는 값도 표시하지 않는다", false, api.viaMcp({ source: "other" }));
eq("레코드가 없어도 오류 없이 false", [false, false], [api.viaMcp(null), api.viaMcp(undefined)]);

// 화면 코드에 bridge 글자를 다시 박지 않았는지(대기·진행 카드 포함)
const hardcoded = (appJs.match(/metaItem\([^)]*"bridge"/g) || []).length;
eq("app.js 에 \"bridge\" 를 칩 글자로 직접 쓰는 곳이 없다", 0, hardcoded);

console.log("");
console.log("통과 " + passed + " / 실패 " + failed);
process.exit(failed > 0 ? 1 : 0);
