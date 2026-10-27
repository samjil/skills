// Claude 토큰 절약(예상) 계산 테스트.
//   node tests/viewer/saved-tokens.tests.js
// runtime/viewer/web/app.js 에서 함수 원문을 꺼내 그대로 실행합니다. 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다.
// 계산은 agy 의 토큰 수를 쓰지 않고, agy 가 남긴 과정(읽은 파일 · 쓴 파일 · 명령 · 생각)에서 "Claude 가 직접 했다면" 쓸 분량을 어림한다.

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
function extractVarLines(prefix) {
  return appJs.split("\n").filter((l) => l.trim().startsWith("var " + prefix)).map((l) => l.replace(/\s\/\/.*$/, "")).join("\n");
}

const names = ["pendingProcessOpts", "liveSavedOf", "tokenShort", "isOkStatus", "estimateTextTokens", "bytesToTokens", "tokenRecordKey", "savedLooksLikePath", "savedIsInternalPath", "savedNormPath",
  "analyzeSavedWork", "estimateDirectTokens", "savedMissingPaths", "savedTokensOf", "sumSavedTokens", "savedTokenShort", "savedTokensText"];
const make = new Function(
  extractVarLines("SAVED_") + "\n" +
  "var savedFileSizes = {}; var savedSizeRequested = {};\n" +
  "var liveProc = {}; function cwdListOf(c) { return Array.isArray(c) ? c : (c ? [c] : []); } function extractImagesFromText() { return { cwds: [] }; }\n" +
  names.map(extractFunction).join("\n") +
  "\nreturn { estimateTextTokens, bytesToTokens, savedLooksLikePath, savedIsInternalPath, analyzeSavedWork, estimateDirectTokens, savedMissingPaths, savedTokensOf, sumSavedTokens, savedTokenShort, savedTokensText, liveSavedOf, liveProc, sizes: savedFileSizes };"
);

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "  (기대: " + e + " / 실제: " + a + ")"); }
}
const step = (tool, detail, think) => ({ n: 1, at: "10:00:00", tool: tool, detail: detail, label: "", think: think || "" });
const rec = (o) => Object.assign({ status: "OK", task_id: "t1", question: "", answer: "", process: [] }, o);

console.log("글자·바이트를 토큰으로 어림");
let api = make();
eq("영문 8자는 2토큰, 한글 3자는 2토큰, 섞이면 합산해 올림", [2, 2, 3, 0], [api.estimateTextTokens("abcdefgh"), api.estimateTextTokens("안녕하"), api.estimateTextTokens("abcd안녕하"), api.estimateTextTokens(null)]);
eq("3200바이트는 1000토큰", 1000, api.bytesToTokens(3200));

console.log("\n경로 판별");
eq("절대 경로만 경로로 본다(윈도우 · 유닉스, 슬래시 · 역슬래시)", [true, true, true, false, false, false],
  [api.savedLooksLikePath("D:/a/b.html"), api.savedLooksLikePath("C:\\x\\y.js"), api.savedLooksLikePath("/home/u/f.py"), api.savedLooksLikePath("function f() { return 1 }"), api.savedLooksLikePath("a/b.html"), api.savedLooksLikePath("D:/a\nb")]);
eq("agy 자신의 작업 파일은 일의 분량에서 뺀다", [true, true, true, false],
  [api.savedIsInternalPath("C:\\Users\\u\\.gemini\\antigravity-cli\\brain\\x.md"), api.savedIsInternalPath("C:/Users/u/.samjil/delegate-agy/runtime/logs/prompts/p.md"), api.savedIsInternalPath("D:/Repos/delegate-agy/runtime/x"), api.savedIsInternalPath("D:/Repos/app/static/index.html")]);

console.log("\n과정 분석: analyzeSavedWork");
eq("과정이 없으면 null", null, api.analyzeSavedWork(rec({})));
const proc = [
  step("view_file", "D:/app/index.html", "abcdefgh"),
  step("read_file", "D:\\app\\index.html"),                       // 같은 파일(역슬래시)은 한 번만
  step("view_file", "C:\\Users\\u\\.samjil\\delegate-agy\\runtime\\logs\\prompts\\p.md"),   // 내부 파일은 뺀다
  step("write_to_file", "D:/app/new.js"),
  step("write_file", "console.log(1)"),                            // 경로가 아닌 본문
  step("replace_file_content", "D:/app/index.html"),
  step("edit_file", "C:/Users/u/.gemini/antigravity-cli/brain/n.md"),   // 내부 파일 수정은 뺀다
  step("run_command", "python -m unittest"),
  step("manage_task", "list"),                                    // 관리 호출은 세지 않는다
  step("schedule", "5초 대기")
];
const w = api.analyzeSavedWork(rec({ process: proc }));
eq("읽은 파일: 고유 경로 하나(슬래시로 통일)", ["D:/app/index.html"], w.reads);
eq("쓴 파일: 경로 있는 것 하나 + 본문만 있는 것 하나", [["D:/app/new.js"], 1], [w.writes, w.writesNoPath]);
eq("고친 곳: 내부 파일 수정은 뺀 1곳", 1, w.edits);
eq("명령: 1회", ["python -m unittest"], w.commands);
eq("단계 수: 읽기 3 + 쓰기 2 + 고침 2 + 명령 1 (관리·대기 제외)", 8, w.steps);

console.log("\n토큰 어림: estimateDirectTokens");
const w2 = { reads: ["D:/a.html", "D:/b.html", "D:/missing.html"], writes: ["D:/new.js"], writesNoPath: 1, edits: 2, commands: ["ls"], thinkChars: 400, steps: 10 };
const d = api.estimateDirectTokens(w2, { "D:/a.html": 3200, "D:/b.html": 32000000, "D:/missing.html": -1, "D:/new.js": 6400 });
eq("읽기: 3200B=1000 + 큰 파일은 상한 30000 + 없는 파일은 기본 2500", 33500, d.read);
eq("쓰기: 6400B=2000 + 본문만 있는 쓰기 기본 1500", 3500, d.write);
eq("고침 2곳 = 1200, 명령 = 글자 1토큰 + 출력 300, 생각 400자 = 200, 단계 10 = 800", [1200, 301, 200, 800], [d.edit, d.cmd, d.think, d.steps]);
eq("합계는 부분의 합", 33500 + 3500 + 1200 + 301 + 200 + 800, d.total);
eq("크기를 모르는 경로(지도에 없음)도 기본값으로 센다", 2500, api.estimateDirectTokens({ reads: ["D:/x"], writes: [], writesNoPath: 0, edits: 0, commands: [], thinkChars: 0, steps: 0 }, {}).read);

console.log("\n한 건과 합계");
api = make();
api.sizes["D:/app/index.html"] = 32000;     // 10000토큰
api.sizes["D:/app/new.js"] = 3200;          // 1000토큰
const r1 = rec({ task_id: "a", question: "가".repeat(300), process: proc });   // 질문 200토큰
const sv = api.savedTokensOf(r1);
eq("직접 했다면 - 질문: (읽기 10000 + 쓰기 1000+1500 + 고침 600 + 명령 305 + 생각 4 + 단계 640) - 200", [10000 + 2500 + 600 + 305 + 4 + 640, 200], [sv.direct, sv.asked]);
eq("절약 토큰 = 직접 했다면 - 질문", sv.direct - 200, sv.saved);
eq("agy 가 쓴 토큰 수는 계산에 쓰지 않는다(값이 달라도 같다)", sv.saved, api.savedTokensOf(Object.assign({}, r1, { total_tokens: "9999999", input_tokens: "9", output_tokens: "9" })).saved);
eq("실패한 위임은 null", null, api.savedTokensOf(Object.assign({}, r1, { status: "ERROR" })));
eq("과정이 없는 기록(MCP 호출 등)은 null", null, api.savedTokensOf(rec({ process: [] })));
eq("질문이 더 크면 0 으로 막는다", 0, api.savedTokensOf(rec({ question: "가".repeat(30000), process: [step("run_command", "ls")] })).saved);
const items = [r1, rec({ task_id: "b", process: [step("run_command", "ls")] }), Object.assign({}, r1, { task_id: "c", status: "ERROR" }), rec({ task_id: "d" })];
const sum = api.sumSavedTokens(items);
eq("합계는 성공 + 과정 있는 기록만 센다(2건)", 2, sum.count);
eq("빈 목록은 0", [0, 0], (function () { const x = api.sumSavedTokens([]); return [x.saved, x.count]; })());

console.log("\n크기를 물을 경로 고르기: savedMissingPaths");
api = make();
const miss1 = api.savedMissingPaths([r1, rec({ task_id: "x", status: "ERROR", process: [step("view_file", "D:/err.html")] })]);
eq("성공한 위임의 읽은·쓴 파일만, 중복 없이", ["D:/app/index.html", "D:/app/new.js"], miss1);
eq("이미 물은 경로는 다시 묻지 않는다", [], api.savedMissingPaths([r1]));

console.log("\n진행 중인 위임: liveSavedOf");
api = make();
api.sizes["D:/app/index.html"] = 32000;     // 10000토큰
const pend = (o) => Object.assign({ task_id: "claude_1_2", state: "processing", conversation_id: "conv-live", question: "가".repeat(300), cwd: [] }, o);
eq("과정(단계)이 아직 없으면 null", null, api.liveSavedOf(pend({})));
api.liveProc["conv-live"] = { steps: [step("view_file", "D:/app/index.html"), step("run_command", "ls")], lastN: 3, busy: false };
const lv = api.liveSavedOf(pend({}));
eq("단계가 모이면 끝난 카드와 같은 계산: 읽기 10000 + 명령 301 + 도구 호출 160 - 질문 200", [10000 + 301 + 160, 200, 10000 + 301 + 160 - 200], [lv.direct, lv.asked, lv.saved]);
api.liveProc["conv-live"].steps.push(step("write_to_file", "D:/app/out.js"));
eq("단계가 늘면 값도 는다(쓴 파일은 크기를 모르면 기본 1500 + 도구 호출 80)", lv.saved + 1500 + 80, api.liveSavedOf(pend({})).saved);
eq("대화 ID 가 없는 작업(대기 중)은 null", null, api.liveSavedOf(pend({ state: "queued", conversation_id: "" })));
eq("작업이 null 이면 null", null, api.liveSavedOf(null));

console.log("\n표시 글자");
eq("큰 합계는 단위를 키운다(9,999 / 2.4만 / 1,676만 / 1.68억)", ["9,999", "2.4만", "1,676만", "1.68억"], [api.savedTokenShort(9999), api.savedTokenShort(24000), api.savedTokenShort(16760000), api.savedTokenShort(168000000)]);
eq("표시 글자: ≈ 와 (예상)이 붙는다", "Claude 토큰 절약 ≈ 2.1만 (예상)", api.savedTokensText(21000));

console.log("\n통과 " + passed + " / 실패 " + failed);
process.exit(failed ? 1 : 0);
