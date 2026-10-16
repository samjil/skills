// 핸드오프 회신 카드의 토큰 사용량 계산(순수 함수) 테스트.
//   node tests/viewer/handoff-usage.tests.js
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

const names = ["handoffSafeName", "tokenShort", "handoffUsageIndex", "handoffUsageText", "claudeUsageText"];
const api = new Function(names.map(extractFunction).join("\n") + "\nreturn { handoffSafeName, tokenShort, handoffUsageIndex, handoffUsageText, claudeUsageText };")();

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\n        기대: " + e + "\n        실제: " + a); }
}

console.log("handoffSafeName: 워처의 ConvertTo-HandoffSafeName 와 같은 규칙");
eq("영문·숫자·하이픈은 그대로", "skills--handoff-test", api.handoffSafeName("skills--handoff-test"));
eq("공백·슬래시는 -", "a-b-c", api.handoffSafeName("a b/c"));
eq("앞뒤 -는 뗀다", "abc", api.handoffSafeName("--abc--"));
eq("한글은 남긴다", "프로젝트-가", api.handoffSafeName("프로젝트 가"));
eq("빈 이름은 channel", "channel", api.handoffSafeName(""));
eq("40자까지만(끝에 - 가 남지 않게)", "a".repeat(39), api.handoffSafeName("a".repeat(39) + "-" + "b".repeat(10)));

console.log("tokenShort");
eq("1만 미만은 쉼표", "9,999", api.tokenShort(9999));
eq("1만 이상은 만 단위 한 자리", "2.8만", api.tokenShort(27851));
eq("0 과 잘못된 값", "0", api.tokenShort("abc"));

// 실제 usage 기록(2026-10-16, skills--handoff-test 채널)의 값. 같은 agy 대화의 누적값이다.
const CH = "skills--handoff-test";
const SID = "1c140738-a18b-45d5-bff2-0ac69ddbd513";
function rec(num, ts, input, output, thinking, total, extra) {
  return Object.assign({
    task_id: "handoff_" + CH + "_" + num + "_" + ts.replace(/\D/g, "").slice(8),
    timestamp: ts, model: "gemini-3.8-flash-high", session: "handoff-" + CH, session_id: SID,
    input_tokens: String(input), output_tokens: String(output), thinking_tokens: String(thinking), total_tokens: String(total), status: "OK"
  }, extra || {});
}
const real = [
  rec("0001", "2026-10-16 11:45:20", 25386, 2465, 1882, 27851),
  rec("0003", "2026-10-16 12:28:10", 68480, 6573, 3948, 75053),
  rec("0005", "2026-10-16 13:37:46", 107760, 9080, 5465, 116840)
];

console.log("handoffUsageIndex: 누적값 -> 이번 호출이 쓴 양");
let idx = api.handoffUsageIndex(CH, real);
eq("번호(c2a)로 찾는다", ["0001", "0003", "0005"], Object.keys(idx).sort());
eq("첫 호출은 누적값이 곧 이번 호출(baseline)", { total: 27851, input: 25386, output: 2465, thinking: 1882, baseline: true }, { total: idx["0001"].delta.total, input: idx["0001"].delta.input, output: idx["0001"].delta.output, thinking: idx["0001"].delta.thinking, baseline: idx["0001"].baseline });
eq("0003 = 75053-27851, 입력 68480-25386, 출력 6573-2465, 사고 3948-1882", { total: 47202, input: 43094, output: 4108, thinking: 2066, baseline: false }, { total: idx["0003"].delta.total, input: idx["0003"].delta.input, output: idx["0003"].delta.output, thinking: idx["0003"].delta.thinking, baseline: idx["0003"].baseline });
eq("0005 = 116840-75053", 41787, idx["0005"].delta.total);
eq("누적값도 함께 보관", 116840, idx["0005"].cumulative.total);
eq("모델", "gemini-3.8-flash-high", idx["0005"].model);

console.log("  입력 순서·종류가 달라도");
idx = api.handoffUsageIndex(CH, [real[2], real[0], real[1]]);
eq("시각 순으로 정렬해 계산한다(입력이 섞여 있어도 같은 결과)", 47202, idx["0003"].delta.total);
idx = api.handoffUsageIndex(CH, real.concat([rec("0001", "2026-10-16 11:00:00", 100, 10, 5, 115, { task_id: "handoff_other-channel_0001_110000" })]));
eq("다른 채널의 기록은 섞지 않는다", ["0001", "0003", "0005"], Object.keys(idx).sort());
idx = api.handoffUsageIndex(CH, real.concat([{ task_id: "claude_1792055726_21862_a", timestamp: "2026-10-16 11:50:00", total_tokens: "999" }, rec("0007", "2026-10-16 13:38:00", 1, 1, 1, 0)]));
eq("핸드오프가 아닌 작업과 총 토큰 0 인 기록은 건너뛴다", ["0001", "0003", "0005"], Object.keys(idx).sort());
eq("채널 이름이 다른 채널 이름의 앞부분이어도(a / a_0001) 섞이지 않는다", [], Object.keys(api.handoffUsageIndex("a", [rec("0001", "2026-10-16 11:00:00", 1, 1, 1, 3, { task_id: "handoff_a_0001_0003_110000" })])));

console.log("  대화가 바뀐 경우");
const reset = real.concat([rec("0007", "2026-10-16 14:00:00", 9000, 800, 400, 10200)]);   // 앞 호출보다 줄었다 -> 새 대화
idx = api.handoffUsageIndex(CH, reset);
eq("누적값이 앞 호출보다 줄면 새 대화로 보고 그 값을 이번 호출로 본다", { total: 10200, baseline: true }, { total: idx["0007"].delta.total, baseline: idx["0007"].baseline });
const other = real.concat([rec("0007", "2026-10-16 14:00:00", 200000, 20000, 10000, 230000, { session_id: "other-conversation" })]);
idx = api.handoffUsageIndex(CH, other);
eq("session_id 가 다르면 서로 빼지 않는다", { total: 230000, baseline: true }, { total: idx["0007"].delta.total, baseline: idx["0007"].baseline });
idx = api.handoffUsageIndex(CH, [rec("0001", "2026-10-16 11:45:20", 25386, 2465, 1882, 27851, { session_id: "" })]);
eq("session_id 가 비면 session 이름으로 묶는다", true, idx["0001"].baseline);
eq("레코드가 없거나 배열이 아니면 빈 결과", [0, 0], [Object.keys(api.handoffUsageIndex(CH, [])).length, Object.keys(api.handoffUsageIndex(CH, null)).length]);

console.log("handoffUsageText: 머리줄 칩과 설명");
let t = api.handoffUsageText(api.handoffUsageIndex(CH, real)["0003"]);
eq("증가분은 + 를 붙인 칩", "+4.7만 토큰", t.chip);
eq("설명에 세부 값과 누적이 있다", true, /총 \+47,202 · 입력 \+43,094 · 출력 \+4,108 · 사고 \+2,066/.test(t.title) && /대화 누적 총 75,053 토큰/.test(t.title) && /증가분/.test(t.title));
t = api.handoffUsageText(api.handoffUsageIndex(CH, real)["0001"]);
eq("첫 호출 칩은 + 가 없고 설명이 첫 호출이라고 말한다", ["2.8만 토큰", true], [t.chip, /첫 호출/.test(t.title) && !/\+27,851/.test(t.title)]);
eq("값이 없으면 null", [null, null], [api.handoffUsageText(undefined), api.handoffUsageText({})]);

console.log("claudeUsageText: Claude 가 보낸 c2a 카드의 칩과 설명(근사치)");
// 실제 기록의 값(0011 을 만든 호출): 출력 1,622 / 새 입력 2,806 / 캐시에서 다시 읽은 입력 531,696
const cu = api.claudeUsageText({ at: "2026-10-16T05:36:14Z", model: "claude-sonnet-5-5", output: 1622, newInput: 2806, cacheRead: 531696, front: 4428, context: 534502 });
eq("칩은 ≈ 와 출력+새 입력(맥락이 아니다)", "≈4,428 토큰", cu.chip);
eq("설명 첫 줄에 근사치라고 밝힌다", true, /근사치/.test(cu.title.split("\n")[0]));
eq("  산식: 출력 1,622 + 새 입력 2,806 = 4,428 토큰", true, /출력 1,622 \+ 새 입력 2,806 = 4,428 토큰/.test(cu.title));
eq("  맥락 크기는 따로 적고 비용이 아니라고 밝힌다", true, /대화 맥락 534,502 토큰/.test(cu.title) && /531,696/.test(cu.title) && /이 메시지에 든 양이 아닙니다/.test(cu.title));
eq("  근사치인 이유(호출을 시각으로 짐작·다른 호출은 빠짐)를 적는다", true, /파일이 생긴 시각 바로 앞의 호출로 짐작/.test(cu.title) && /다른 호출은 빠졌습니다/.test(cu.title));
eq("  모델이 설명에 있다", true, /모델 claude-sonnet-5-5/.test(cu.title));
eq("  앞에 두는 값과 맥락 값이 따로 담긴다", [4428, 534502], [cu.front, cu.context]);
eq("1만 이상이면 만 단위 칩", "≈1.2만 토큰", api.claudeUsageText({ output: 5000, newInput: 7000, cacheRead: 1, front: 12000, context: 7001 }).chip);
eq("값이 없거나 front 가 숫자가 아니면 null", [null, null, null], [api.claudeUsageText(null), api.claudeUsageText({}), api.claudeUsageText({ front: "4428" })]);

console.log("");
console.log("통과 " + passed + " / 실패 " + failed);
process.exit(failed > 0 ? 1 : 0);
