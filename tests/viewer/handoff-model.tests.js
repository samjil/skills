// 인수인계 방향 표시(모델명)와 자동 이어가기 상태 문구 순수 함수 테스트.
//   node tests/viewer/handoff-model.tests.js
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

const names = ["escapeHtml", "dirParty", "formatModelName", "handoffLatestModels", "handoffLabelParts", "dirLabelHtml", "handoffAutoText"];
const make = new Function(
  "handoffChannels",
  names.map(extractFunction).join("\n") +
  "\nreturn { formatModelName, handoffLatestModels, handoffLabelParts, dirLabelHtml, handoffAutoText };"
);

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\n        기대: " + e + "\n        실제: " + a); }
}

const api = make({});
const f = api.formatModelName;

console.log("formatModelName: 모델 ID -> 사람이 읽는 이름");
eq("claude-opus-4-5-20251101", "Claude Opus 4.5", f("claude-opus-4-5-20251101"));
eq("날짜 없는 claude-sonnet-5-5", "Claude Sonnet 5.5", f("claude-sonnet-5-5"));
eq("버전이 하나뿐인 claude-opus-4-20250514", "Claude Opus 4", f("claude-opus-4-20250514"));
eq("claude-fable-5-1", "Claude Fable 5.1", f("claude-fable-5-1"));
eq("꼬리표 [1m] 는 뗀다", "Claude Opus 4.5", f("claude-opus-4-5[1m]"));
eq("예전 모양 claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet", f("claude-3-5-sonnet-20241022"));
eq("gemini-3.8-flash-high", "Gemini 3.8 Flash (High)", f("gemini-3.8-flash-high"));
eq("gemini-3.1-pro-high", "Gemini 3.1 Pro (High)", f("gemini-3.1-pro-high"));
eq("단계가 없는 gemini-3.8-flash", "Gemini 3.8 Flash", f("gemini-3.8-flash"));
eq("이미 사람이 쓴 이름은 그대로", "Claude Opus 5.5", f("Claude Opus 5.5"));
eq("  공백이 든 이름도 그대로", "gemini 3 flash", f("gemini 3 flash"));
eq("모르는 모양은 추측하지 않고 그대로", "some-new-model-x", f("some-new-model-x"));
eq("빈 값·null·undefined 는 빈 문자열", ["", "", ""], [f(""), f(null), f(undefined)]);

console.log("\nhandoffLatestModels: 두 쪽이 가장 최근에 쓴 모델");
const msgs = [
  { num: "0001", dir: "c2a", model: "claude-opus-4-5" },
  { num: "0002", dir: "a2c", model: "gemini-3.1-pro-high" },
  { num: "0003", dir: "c2a", model: "" },
  { num: "0004", dir: "a2c", model: "gemini-3.8-flash-high", replyTo: "0003" }
];
eq("가장 최근 것이 이긴다 (모델이 빈 메시지는 건너뜀)", { claude: "claude-opus-4-5", agy: "gemini-3.8-flash-high" }, api.handoffLatestModels(msgs));
eq("메시지가 없으면 둘 다 빈 값", { claude: "", agy: "" }, api.handoffLatestModels([]));
eq("배열이 아니어도 오류 없이 빈 값", { claude: "", agy: "" }, api.handoffLatestModels(null));

console.log("\nhandoffLabelParts: 보낸 쪽 → 받는 쪽 이름");
let p = api.handoffLabelParts(msgs[0], msgs);
eq("모델이 있는 c2a: 보낸 쪽은 자기 모델", "Claude Opus 4.5", p.sender);
eq("  받는 쪽: 아직 답이 없는 0001 -> agy 의 가장 최근 모델(추정 표시)", ["Gemini 3.8 Flash (High)", true], [p.receiver, p.inferred]);
p = api.handoffLabelParts(msgs[2], msgs);
eq("모델 기록이 없는 c2a(0003): 보낸 쪽은 Claude 라고만", "Claude", p.sender);
eq("  받는 쪽: 0003 에 답한 0004 의 모델(실제로 받은 쪽, 추정 아님)", ["Gemini 3.8 Flash (High)", false], [p.receiver, p.inferred]);
p = api.handoffLabelParts(msgs[3], msgs);
eq("a2c 회신(0004): 보낸 쪽은 agy 모델, 방향 색은 agy", ["Gemini 3.8 Flash (High)", "agy", "claude"], [p.sender, p.senderParty, p.receiverParty]);
eq("  받는 쪽: 이 회신에 답한 게 없으면 Claude 의 가장 최근 모델(추정)", ["Claude Opus 4.5", true], [p.receiver, p.inferred]);
p = api.handoffLabelParts({ num: "0009", dir: "c2a" }, []);
eq("아무 기록도 없으면 Claude → agy", ["Claude", "agy", false], [p.sender, p.receiver, p.inferred]);
eq("방향을 모르는 메시지는 null", null, api.handoffLabelParts({ num: "1", dir: "?" }, msgs));
p = api.handoffLabelParts({ num: "0001", dir: "c2a" }, msgs);
eq("프로젝트 목록 API 의 가벼운 메시지(model 필드 없음)는 전체 목록에서 번호로 찾아 쓴다", "Claude Opus 4.5", p.sender);

console.log("\ndirLabelHtml: 화면에 들어가는 HTML");
const api2 = make({ "my-app": { messages: msgs } });
eq("모델명 + 보낸 쪽 색 클래스", '<span class="who-claude">Claude Opus 4.5</span> → <span title="이 메시지에 답한 기록이 아직 없어, 그 쪽이 가장 최근에 쓴 모델로 표시했습니다">Gemini 3.8 Flash (High)</span>', api2.dirLabelHtml("c2a", msgs[0], "my-app"));
eq("답이 확인된 메시지는 추정 안내(title)가 없다", '<span class="who-claude">Claude</span> → <span>Gemini 3.8 Flash (High)</span>', api2.dirLabelHtml("c2a", msgs[2], "my-app"));
eq("채널 정보가 없으면 예전 표시(c2a)", '<span class="who-claude">Claude</span> → agy', api.dirLabelHtml("c2a"));
eq("  예전 표시(a2c)", '<span class="who-agy">agy</span> → Claude', api.dirLabelHtml("a2c"));
eq("HTML 을 깨는 모델 이름은 이스케이프한다", '<span class="who-claude">&lt;b&gt;x&lt;/b&gt;</span> → <span>agy</span>', make({ c: { messages: [] } }).dirLabelHtml("c2a", { num: "1", dir: "c2a", model: "<b>x</b>" }, "c"));

console.log("\nhandoffAutoText: 자동 이어가기 상태 줄");
const base = { enabled: true, halted: false, haltedReason: "", rounds: 2, maxRounds: 6, windowMinutes: 60, inFlight: [] };
const now = Date.parse("2026-10-16T10:30:00");
eq("auto 정보가 없으면 줄을 숨긴다(null)", null, api.handoffAutoText(null, now));
eq("꺼짐", "off", api.handoffAutoText(Object.assign({}, base, { enabled: false }), now).kind);
let t = api.handoffAutoText(Object.assign({}, base, { halted: true, haltedReason: "한도(6회/60분)에 도달" }), now);
eq("멈춤: 사용자 확인 필요 + 사유", ["halted", true, "한도(6회/60분)에 도달"], [t.kind, t.state.indexOf("사용자 확인 필요") >= 0, t.detail]);
t = api.handoffAutoText(Object.assign({}, base, { inFlight: [{ num: "0042", taskId: "t", at: "2026-10-16 10:25:00" }] }), now);
eq("agy 처리 중: 번호·경과 분·왕복", ["busy", "#0042 · 5분 경과 · 왕복 2/6"], [t.kind, t.detail]);
t = api.handoffAutoText(Object.assign({}, base), now);
eq("평상시 켜짐: 왕복 2/6 (최근 60분)", ["on", true], [t.kind, t.detail.indexOf("왕복 2/6 (최근 60분)") >= 0]);
t = api.handoffAutoText(Object.assign({}, base, { inFlight: [{ num: "0042", at: "형식이 이상함" }] }), now);
eq("경과 시간을 못 읽으면 경과 없이 번호만", "#0042 · 왕복 2/6", t.detail);
eq("멈춤이 꺼짐보다 먼저가 아니다: 꺼짐이면 멈춤 표시 없이 꺼짐", "off", api.handoffAutoText(Object.assign({}, base, { enabled: false, halted: true }), now).kind);

console.log("\n통과 " + passed + " / 실패 " + failed);
if (failed > 0) {
  process.exit(1);
}
