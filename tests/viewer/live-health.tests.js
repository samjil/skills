// 진행 상태 판정(진행 중 / 조용함 / 멈춘 것으로 보임 / 중단 / 대기 / 끝남)과 핸드오프 메시지의 진행 줄, 진행 중 과정 따라가기 테스트.
//   node tests/viewer/live-health.tests.js
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
function extractNumber(name) {
  const m = appJs.match(new RegExp("var\\s+" + name + "\\s*=\\s*(\\d+)\\s*;"));
  if (!m) throw new Error(name + " 상수를 app.js 에서 찾지 못했습니다.");
  return Number(m[1]);
}

const names = ["pad2", "escapeHtml", "formatDuration", "healthStallMinutes", "delegateRunHealth", "handoffDispatchOf", "handoffSafeChannelName", "handoffTaskIdOf", "handoffFinishedTaskId", "handoffLiveOf", "healthInnerHtml", "healthBadgeClass", "syncLiveProcess", "fetchLiveProcess", "pendingProcessOpts"];
const fetchLog = [];
const make = new Function(
  "fetchJson", "renderProcessDialog", "updateProcessButtons", "cwdListOf",
  "var PROGRESS_QUIET_SEC = " + extractNumber("PROGRESS_QUIET_SEC") + ";\n" +
  "var HEALTH_STALL_DEFAULT_SEC = " + extractNumber("HEALTH_STALL_DEFAULT_SEC") + ";\n" +
  "var liveProc = {};\n" +
  names.map(extractFunction).join("\n") +
  "\nreturn { delegateRunHealth, handoffDispatchOf, handoffSafeChannelName, handoffTaskIdOf, handoffFinishedTaskId, handoffLiveOf, healthInnerHtml, healthBadgeClass, syncLiveProcess, pendingProcessOpts, liveProc, formatDuration };"
);

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\n        기대: " + e + "\n        실제: " + a); }
}

// 가짜 서버: 단계 번호 1,3,5,... 를 가진 기록. since 를 받으면 그 뒤 것만 돌려준다.
let serverSteps = [];
let serverReset = false;
function fakeFetchJson(url) {
  fetchLog.push(url);
  const since = (url.match(/since=(-?\d+)/) || [])[1];
  const steps = since == null || serverReset ? serverSteps : serverSteps.filter(s => s.n > Number(since));
  return Promise.resolve({ id: "c1", found: true, steps: steps, total: serverSteps.length, reset: serverReset });
}
let dialogRenders = 0;
const api = make(fakeFetchJson, function () { dialogRenders++; }, function () {}, function (c) { return Array.isArray(c) ? c : (c ? [c] : []); });

const NOW = Date.parse("2026-10-16T12:00:00");
const sec = (s) => NOW - s * 1000;
const proc = (idleSec, extra) => Object.assign({
  task_id: "t1", state: "processing", started_at: "2026-10-16 11:00:00",
  progress: { last_activity_ms: sec(idleSec), stall_seconds: 300, step: 12 }
}, extra || {});

console.log("delegateRunHealth: 작업 하나의 상태");
let h = api.delegateRunHealth(proc(10), NOW, true);
eq("방금 활동이 있으면 진행 중(설명은 진행 줄과 겹치지 않게 비워 둔다)", ["running", "진행 중", ""], [h.kind, h.label, h.detail]);
h = api.delegateRunHealth(proc(119), NOW, true);
eq("119초 전이면 아직 진행 중", "running", h.kind);
h = api.delegateRunHealth(proc(120), NOW, true);
eq("120초 이상 조용하면 조용함", ["quiet", "조용함"], [h.kind, h.label]);
eq("  마지막 활동과 멈춤 기준을 알려 준다", "마지막 활동 2분 00초 전 · 5분 넘게 조용하면 멈춘 것으로 봅니다", h.detail);
h = api.delegateRunHealth(proc(299), NOW, true);
eq("299초는 아직 조용함", "quiet", h.kind);
h = api.delegateRunHealth(proc(300), NOW, true);
eq("기준(300초)에 닿으면 멈춘 것으로 보임", ["stalled", "멈춘 것으로 보임"], [h.kind, h.label]);
eq("  이유", "마지막 활동 5분 00초 전 · 5분 넘게 새 단계가 없습니다", h.detail);
h = api.delegateRunHealth(proc(400, { progress: { last_activity_ms: sec(400), stall_seconds: 300, waiting_background: true } }), NOW, true);
eq("오래 걸리는 명령을 기다리는 중이면 멈춘 것이 아니다", ["running", "오래 걸리는 명령이 끝나기를 기다리는 중 · 마지막 활동 6분 40초 전"], [h.kind, h.detail]);
h = api.delegateRunHealth(proc(30, { progress: { last_activity_ms: sec(30), stall_seconds: 90 } }), NOW, true);
eq("서버가 준 멈춤 기준(90초)을 따른다: 30초는 진행 중", "running", h.kind);
h = api.delegateRunHealth(proc(100, { progress: { last_activity_ms: sec(100), stall_seconds: 90 } }), NOW, true);
eq("  100초는 이미 멈춘 것으로 보임", ["stalled", "마지막 활동 1분 40초 전 · 1.5분 넘게 새 단계가 없습니다"], [h.kind, h.detail]);
h = api.delegateRunHealth(proc(70), NOW, false);
eq("워처가 꺼져 있고 60초 넘게 조용하면 멈춘 것으로 보임", ["stalled", "워처가 꺼져 있습니다 · 마지막 활동 1분 10초 전"], [h.kind, h.detail]);
h = api.delegateRunHealth(proc(10), NOW, false);
eq("워처가 꺼졌어도 방금까지 활동했으면 아직 진행 중으로 본다", "running", h.kind);
h = api.delegateRunHealth(proc(10), NOW, null);
eq("워처 상태를 아직 모르면(null) 워처 때문에 멈춤으로 보지 않는다", "running", h.kind);
h = api.delegateRunHealth({ task_id: "t2", state: "processing", started_at: "2026-10-16 11:56:00" }, NOW, true);
eq("진행 정보가 없으면 시작 시각부터 센다(4분 → 조용함)", "quiet", h.kind);
h = api.delegateRunHealth({ task_id: "t3", state: "queued" }, NOW, true);
eq("대기 중", ["queued", "대기 중", ""], [h.kind, h.label, h.detail]);
h = api.delegateRunHealth({ task_id: "t3", state: "queued" }, NOW, false);
eq("워처가 꺼져 있으면 대기 중이라고만 하지 않고 이유를 말한다", "워처가 꺼져 있어 시작하지 못하고 있습니다", h.detail);
h = api.delegateRunHealth({ task_id: "t4", state: "queued", interrupted: true, progress: { last_activity_ms: sec(600) } }, NOW, true);
eq("실행 표시만 남은 작업은 중단된 것으로 보임", ["stalled", "중단된 것으로 보임", "작업자 프로세스가 사라졌습니다 · 마지막 활동 10분 00초 전"], [h.kind, h.label, h.detail]);

console.log("\nhealthInnerHtml / healthBadgeClass");
eq("글자는 이스케이프한다", true, api.healthInnerHtml({ label: "<b>", detail: "a&b" }).indexOf("&lt;b&gt;") > 0 && api.healthInnerHtml({ label: "x", detail: "a&b" }).indexOf("a&amp;b") > 0);
eq("설명이 없으면 설명 칸을 만들지 않는다", false, api.healthInnerHtml({ label: "진행 중", detail: "" }).indexOf("live-detail") >= 0);
eq("배지 클래스", ["status-pending-processing", "status-pending-quiet", "status-pending-stalled", "status-pending-queued"],
  ["running", "quiet", "stalled", "queued"].map(api.healthBadgeClass));

console.log("\nhandoffLiveOf: 핸드오프 메시지(Claude → agy)의 진행 줄");
const chan = (auto) => ({ name: "ch", auto: Object.assign({ enabled: true, halted: false, dispatches: [] }, auto || {}) });
const c2a = (num, status) => ({ num: num, dir: "c2a", status: status });
let live = api.handoffLiveOf(chan(), c2a("0005", "보냄"), [], [], true, NOW);
eq("보냄 + 워처 켜짐: agy 가 가져가기를 기다림", ["queued", "agy 가 가져가기를 기다림", false], [live.kind, live.label, live.canOpen]);
live = api.handoffLiveOf(chan(), c2a("0005", "보냄"), [], [], false, NOW);
eq("보냄 + 워처 꺼짐: 가져가지 못함(멈춤 색)", ["stalled", "가져가지 못함"], [live.kind, live.label]);
live = api.handoffLiveOf(chan({ enabled: false }), c2a("0005", "보냄"), [], [], true, NOW);
eq("보냄 + 자동 이어가기 꺼짐: 안 넘어감", "아직 안 넘어감", live.label);
live = api.handoffLiveOf(chan({ halted: true }), c2a("0005", "보냄"), [], [], true, NOW);
eq("보냄 + 자동 이어가기 멈춤", ["stalled", "멈춤"], [live.kind, live.label]);

const disp = [{ num: "0007", taskId: "handoff_ch_0007_100000", at: "2026-10-16 10:00:00", done: false }];
const running = proc(20, { task_id: "handoff_ch_0007_100000" });
live = api.handoffLiveOf(chan({ dispatches: disp }), c2a("0007", "읽음"), [running], [], true, NOW);
eq("읽음 + 위임 작업 진행 중", ["running", "진행 중", "handoff_ch_0007_100000", true], [live.kind, live.label, live.taskId, live.canOpen]);
eq("  진행 중인 위임 항목을 같이 돌려준다(지금 하는 일을 보이려고)", running, live.pending);
live = api.handoffLiveOf(chan({ dispatches: disp }), c2a("0007", "읽음"), [proc(400, { task_id: "handoff_ch_0007_100000" })], [], true, NOW);
eq("읽음 + 5분 넘게 새 단계 없음: 멈춘 것으로 보임", ["stalled", "멈춘 것으로 보임"], [live.kind, live.label]);
live = api.handoffLiveOf(chan({ dispatches: disp }), c2a("0007", "읽음"), [], [{ task_id: "handoff_ch_0007_100000", status: "OK" }], true, NOW);
eq("읽음 + 작업은 끝났고 회신을 정리하는 중", ["done", "agy 작업 끝남", true], [live.kind, live.label, live.canOpen]);
live = api.handoffLiveOf(chan({ dispatches: disp }), c2a("0007", "읽음"), [], [{ task_id: "handoff_ch_0007_100000", status: "ERROR" }], true, NOW);
eq("읽음 + 작업이 실패로 끝남", ["failed", "agy 작업 실패"], [live.kind, live.label]);
live = api.handoffLiveOf(chan({ dispatches: disp }), c2a("0007", "읽음"), [], [], true, NOW);
eq("읽음 + 대기열에도 기록에도 없음: 상태 확인 중", ["queued", "상태 확인 중", false], [live.kind, live.label, live.canOpen]);
live = api.handoffLiveOf(chan({ dispatches: disp }), c2a("0007", "읽음"), [], [], false, NOW);
eq("  워처가 꺼져 있으면 멈춘 것으로 보임", "stalled", live.kind);
eq("읽음인데 위임 기록이 없으면(손으로 바꾼 것) 줄을 만들지 않는다", null, api.handoffLiveOf(chan(), c2a("0009", "읽음"), [], [], true, NOW));
eq("처리됨은 줄을 만들지 않는다", null, api.handoffLiveOf(chan({ dispatches: disp }), c2a("0007", "처리됨"), [running], [], true, NOW));
eq("agy → Claude 메시지(a2c)는 줄을 만들지 않는다", null, api.handoffLiveOf(chan(), { num: "0006", dir: "a2c", status: "보냄" }, [], [], true, NOW));
const twice = [
  { num: "0007", taskId: "old", at: "x", done: true },
  { num: "0007", taskId: "new", at: "y", done: false },
  { num: "0008", taskId: "other", at: "z", done: false }
];
eq("같은 메시지를 두 번 위임했으면 안 끝난 쪽을 쓴다", "new", api.handoffDispatchOf(chan({ dispatches: twice }), "0007").taskId);
eq("모두 끝났으면 나중 것", "b", api.handoffDispatchOf(chan({ dispatches: [{ num: "1", taskId: "a", done: true }, { num: "1", taskId: "b", done: true }] }), "1").taskId);
eq("위임 기록이 없으면 null", null, api.handoffDispatchOf(chan(), "0007"));

console.log("\n진행 중 과정 따라가기(syncLiveProcess): 늘어난 단계만 since 로 받아 이어 붙인다");
const step = (n) => ({ n: n, at: "12:00:00", tool: "view_file", detail: "f" + n, label: "", think: "" });
const pend = (count, extra) => Object.assign({ task_id: "t1", state: "processing", conversation_id: "c1", progress: { step_count: count } }, extra || {});
serverSteps = [step(1), step(3)];
api.syncLiveProcess([pend(2)]);
const tick = () => new Promise(r => setTimeout(r, 5));
(async function () {
  await tick();
  eq("처음에는 since 없이 전부 받는다", ["/api/delegate/process?id=c1"], fetchLog.slice());
  eq("  단계 2개를 기억한다", [1, 3], api.liveProc.c1.steps.map(s => s.n));
  eq("  창과 버튼을 다시 그린다", true, dialogRenders >= 1);

  api.syncLiveProcess([pend(2)]);
  await tick();
  eq("단계 수가 그대로면 요청하지 않는다", 1, fetchLog.length);

  serverSteps = [step(1), step(3), step(5), step(7)];
  api.syncLiveProcess([pend(4)]);
  await tick();
  eq("단계 수가 늘면 마지막 번호(3) 뒤만 요청한다", "/api/delegate/process?id=c1&since=3", fetchLog[1]);
  eq("  새 단계만 이어 붙는다(중복 없음)", [1, 3, 5, 7], api.liveProc.c1.steps.map(s => s.n));

  serverSteps = [step(2)]; serverReset = true;
  api.syncLiveProcess([pend(1)]);
  await tick();
  api.syncLiveProcess([pend(9)]);
  await tick();
  eq("서버가 reset 을 알리면(기록이 새로 만들어짐) 처음부터 다시 채운다", [2], api.liveProc.c1.steps.map(s => s.n));
  serverReset = false;

  api.syncLiveProcess([pend(0, { state: "queued", conversation_id: "" })]);
  eq("끝나거나 사라진 작업의 기억은 비운다", {}, api.liveProc);

  console.log("\npendingProcessOpts: 과정 창에 넘기는 단계");
  serverSteps = [step(1)];
  api.syncLiveProcess([pend(1)]);
  await tick();
  let o = api.pendingProcessOpts(pend(1), ["C:\\w"]);
  eq("진행 중이면 따라가며 모은 단계를 쓴다", [[1], true, false, "c1"], [o.steps.map(s => s.n), o.live, o.waiting, o.convId]);
  o = api.pendingProcessOpts({ task_id: "t9", state: "processing", conversation_id: "c9", progress: { step_count: 0 } }, []);
  eq("아직 따라가기 전이면 빈 목록(아직 도구를 부르지 않았습니다)", [[], true], [o.steps, o.live]);
  o = api.pendingProcessOpts({ task_id: "t9", state: "queued" }, []);
  eq("대기 중이면 단계 없음 · 시작 전", [null, false, true, ""], [o.steps, o.live, o.waiting, o.convId]);
  o = api.pendingProcessOpts({ task_id: "t9", state: "queued", interrupted: true, conversation_id: "c1" }, []);
  eq("중단된 작업도 마지막까지의 과정을 볼 수 있다", [true, false, "c1"], [Array.isArray(o.steps), o.waiting, o.convId]);

  console.log("\n끝난 핸드오프 메시지의 과정 버튼 (handoffFinishedTaskId)");
  eq("채널 이름 -> 작업 ID 용 이름(펌프 규칙)", ["healthketch-webview", "my-app", "channel", 40], [api.handoffSafeChannelName("healthketch-webview"), api.handoffSafeChannelName("my app!"), api.handoffSafeChannelName("!!!"), api.handoffSafeChannelName("a".repeat(60)).length]);
  eq("  한글 채널 이름은 그대로", "건협-웹뷰", api.handoffSafeChannelName("건협-웹뷰"));
  const chD = { auto: { dispatches: [{ num: "0084", taskId: "handoff_healthketch-webview_0084_154100", done: true }] } };
  const recsD = [
    { task_id: "handoff_healthketch-webview_0086_160000", status: "OK" },
    { task_id: "handoff_healthketch-webview_0084_154100", status: "OK" },
    { task_id: "handoff_healthketch-webview_0082_153200", status: "OK" },
    { task_id: "handoff_other_0082_120000", status: "OK" }
  ];
  eq("위임 연결(dispatches)이 있으면 그 작업 ID", "handoff_healthketch-webview_0084_154100", api.handoffTaskIdOf(chD, "healthketch-webview", "0084", recsD));
  eq("  연결이 밀려났으면 위임 기록에서 작업 ID 모양으로 찾는다(다른 채널 것은 안 섞임)", "handoff_healthketch-webview_0082_153200", api.handoffTaskIdOf(chD, "healthketch-webview", "0082", recsD));
  eq("  어디에도 없거나 번호가 비면 빈 글자", ["", ""], [api.handoffTaskIdOf(chD, "healthketch-webview", "0999", recsD), api.handoffTaskIdOf(chD, "healthketch-webview", "", recsD)]);
  const f = (m) => api.handoffFinishedTaskId(chD, "healthketch-webview", m, recsD);
  eq("처리됨 c2a 는 그 메시지의 위임", "handoff_healthketch-webview_0084_154100", f({ num: "0084", dir: "c2a", status: "처리됨" }));
  eq("  확인함·보류도 같다", [true, true], [f({ num: "0084", dir: "c2a", status: "확인함" }) !== "", f({ num: "0084", dir: "c2a", status: "보류" }) !== ""]);
  eq("  보냄·읽음 c2a 는 진행 줄이 맡으니 없다", ["", ""], [f({ num: "0084", dir: "c2a", status: "보냄" }), f({ num: "0084", dir: "c2a", status: "읽음" })]);
  eq("agy 회신(a2c)은 답한 메시지(답장대상)의 위임", "handoff_healthketch-webview_0084_154100", f({ num: "0085", dir: "a2c", status: "확인함", replyTo: "0084" }));
  eq("  답장대상이 없는 회신(agy 가 직접 쓴 것)은 없다", "", f({ num: "0085", dir: "a2c", status: "확인함", replyTo: "" }));
  eq("  위임 연결은 있지만 위임 기록이 없으면 버튼을 만들지 않는다", "", api.handoffFinishedTaskId(chD, "healthketch-webview", { num: "0084", dir: "c2a", status: "처리됨" }, []));
  eq("  메시지가 null 이면 없다", "", f(null));

  console.log("\n통과 " + passed + " / 실패 " + failed);
  if (failed > 0) process.exit(1);
})();
