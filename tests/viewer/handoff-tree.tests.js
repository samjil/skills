// Claude Desktop 프로젝트 -> 세션 펼침 트리 순수 함수 테스트 (에이전트 인수인계).
//   node tests/viewer/handoff-tree.tests.js
// runtime/viewer/web/app.js 에서 함수 원문과 상수를 꺼내 그대로 실행합니다.
// 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다.

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

function extractConstant(name) {
  const match = appJs.match(new RegExp("var\\s+" + name + "\\s*=\\s*([^;]+);"));
  if (!match) throw new Error(name + " 상수를 app.js 에서 찾지 못했습니다.");
  return JSON.parse(match[1].trim());
}

const QA_UNGROUPED = extractConstant("QA_UNGROUPED");
const QA_UNLINKED = extractConstant("QA_UNLINKED");

const testChannels = {};
const names = [
  "handoffMsgFileOf",
  "handoffLinkOf",
  "handoffNodeOf",
  "buildHandoffTree",
  "handoffFilterTree",
  "handoffMessagesOf"
];

const api = new Function(
  "handoffChannels",
  "var QA_UNGROUPED = " + JSON.stringify(QA_UNGROUPED) + ";\r\n" +
  "var QA_UNLINKED = " + JSON.stringify(QA_UNLINKED) + ";\r\n" +
  names.map(extractFunction).join("\r\n") +
  "\r\nreturn { handoffMsgFileOf, handoffLinkOf, handoffNodeOf, buildHandoffTree, handoffFilterTree, handoffMessagesOf, QA_UNGROUPED, QA_UNLINKED };"
)(testChannels);

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\r\n        기대: " + e + "\r\n        실제: " + a); }
}
function ok(name, cond) { eq(name, true, Boolean(cond)); }

console.log("상수 확인");
eq("QA_UNGROUPED 상수 값", "__ungrouped__", QA_UNGROUPED);
eq("QA_UNLINKED 상수 값", "__unlinked__", QA_UNLINKED);

console.log("\nhandoffMsgFileOf: 메시지 번호로 파일 이름 찾기");
const sampleChannelData = {
  name: "channel-alpha",
  files: ["0001-c2a-first.md", "0002-a2c-second.md", "0010-c2a-tenth.md"],
  messages: []
};
eq("파일 찾음", "0001-c2a-first.md", api.handoffMsgFileOf({ num: "0001" }, sampleChannelData));
eq("두 자리 번호 파일 찾음", "0010-c2a-tenth.md", api.handoffMsgFileOf({ num: "0010" }, sampleChannelData));
eq("없는 번호 -> 빈 문자열", "", api.handoffMsgFileOf({ num: "0003" }, sampleChannelData));
eq("files 목록 없음 -> 빈 문자열", "", api.handoffMsgFileOf({ num: "0001" }, {}));
eq("channelData 없음 -> 빈 문자열", "", api.handoffMsgFileOf({ num: "0001" }, null));
eq("msg 없음 -> 빈 문자열", "", api.handoffMsgFileOf(null, sampleChannelData));
eq("num 없음 -> 빈 문자열", "", api.handoffMsgFileOf({}, sampleChannelData));

console.log("\nhandoffNodeOf: 인수인계 메시지의 프로젝트/세션 노드 판별");
const mockTree = {
  available: true,
  scanning: false,
  projects: [
    {
      id: "cg-1",
      name: "ma::healthketch-webview",
      sessions: [
        { id: "cli-sess-1", title: "건협-kahp", cwd: "D:\\a", created: "2026-10-14 09:00:00", lastActivity: "2026-10-14 17:00:00", archived: false },
        { id: "cli-sess-empty-title-123456", title: "", cwd: "D:\\b", created: "2026-10-14 09:00:00", lastActivity: "2026-10-14 10:00:00", archived: false }
      ]
    }
  ],
  ungrouped: [
    { id: "cli-sess-u1", title: "단독세션A", cwd: "D:\\c", created: "2026-10-14 10:00:00", lastActivity: "2026-10-14 11:00:00", archived: false }
  ],
  handoffLinks: {
    "0001-c2a-first.md": "cli-sess-1",
    "0002-a2c-second.md": "cli-sess-u1",
    "0003-c2a-dead.md": "cli-sess-deleted",
    "0004-a2c-empty.md": "cli-sess-empty-title-123456"
  }
};

const cData = {
  name: "channel-x",
  files: ["0001-c2a-first.md", "0002-a2c-second.md", "0003-c2a-dead.md", "0004-a2c-empty.md", "0005-c2a-nolink.md"]
};

eq("링크 있음 -> 그룹 세션", {
  projectId: "cg-1",
  projectName: "ma::healthketch-webview",
  sessionId: "cli-sess-1",
  sessionTitle: "건협-kahp"
}, api.handoffNodeOf("channel-x", { num: "0001" }, cData, mockTree));

eq("링크 있음 -> 그룹 없는 세션", {
  projectId: QA_UNGROUPED,
  projectName: "그룹 없음",
  sessionId: "cli-sess-u1",
  sessionTitle: "단독세션A"
}, api.handoffNodeOf("channel-x", { num: "0002" }, cData, mockTree));

eq("링크 있으나 세션이 사라짐 -> 연결 안 됨 c:<채널>", {
  projectId: QA_UNLINKED,
  projectName: "연결 안 됨",
  sessionId: "c:channel-x",
  sessionTitle: "channel-x"
}, api.handoffNodeOf("channel-x", { num: "0003" }, cData, mockTree));

eq("링크 없음 -> 연결 안 됨 c:<채널>", {
  projectId: QA_UNLINKED,
  projectName: "연결 안 됨",
  sessionId: "c:channel-x",
  sessionTitle: "channel-x"
}, api.handoffNodeOf("channel-x", { num: "0005" }, cData, mockTree));

eq("tree 가 null 인 경우 -> 연결 안 됨 c:<채널>", {
  projectId: QA_UNLINKED,
  projectName: "연결 안 됨",
  sessionId: "c:channel-x",
  sessionTitle: "channel-x"
}, api.handoffNodeOf("channel-x", { num: "0001" }, cData, null));

eq("세션 제목이 비어 있으면 id 앞 8자리", {
  projectId: "cg-1",
  projectName: "ma::healthketch-webview",
  sessionId: "cli-sess-empty-title-123456",
  sessionTitle: "cli-sess"
}, api.handoffNodeOf("channel-x", { num: "0004" }, cData, mockTree));

console.log("\nbuildHandoffTree: 인수인계 트리 구성과 집계");
const treeData = {
  projects: [
    {
      id: "cg-1",
      name: "ma::proj-alpha",
      sessions: [
        { id: "s1", title: "세션 1", cwd: "D:\\a", lastActivity: "2026-10-14 10:00:00", archived: false },
        { id: "s2", title: "세션 2 (기록 없음)", cwd: "D:\\b", lastActivity: "2026-10-14 12:00:00", archived: false },
        { id: "s-arch-empty", title: "보관 세션 (기록 없음)", cwd: "D:\\c", lastActivity: "2026-10-14 08:00:00", archived: true },
        { id: "s-arch-active", title: "보관 세션 (기록 있음)", cwd: "D:\\d", lastActivity: "2026-10-14 09:00:00", archived: true }
      ]
    },
    {
      id: "cg-2",
      name: "sh::proj-beta",
      sessions: [
        { id: "s3", title: "세션 3", cwd: "D:\\e", lastActivity: "2026-10-14 11:00:00", archived: false }
      ]
    }
  ],
  ungrouped: [
    { id: "u1", title: "그룹외 세션", cwd: "D:\\f", lastActivity: "2026-10-14 09:30:00", archived: false }
  ],
  handoffLinks: {
    "0001-c2a-a1.md": "s1",
    "0002-a2c-a2.md": "s1",
    "0003-c2a-a3.md": "s-arch-active",
    "0001-c2a-b1.md": "u1",
    "0002-c2a-b2.md": "s1"
  }
};

const channelsData = {
  "ch-alpha": {
    name: "ch-alpha",
    files: ["0001-c2a-a1.md", "0002-a2c-a2.md", "0003-c2a-a3.md", "0004-c2a-unlinked.md"],
    messages: [
      { num: "0001", status: "보냄", time: "2026-10-14 13:00:00" },
      { num: "0002", status: "처리됨", time: "2026-10-14 14:00:00" },
      { num: "0003", status: "읽음", time: "2026-10-14 15:00:00" },
      { num: "0004", status: "보냄", time: "2026-10-14 16:00:00" }
    ]
  },
  "ch-beta": {
    name: "ch-beta",
    files: ["0001-c2a-b1.md", "0002-c2a-b2.md"],
    messages: [
      { num: "0001", status: "확인함", time: "2026-10-14 16:30:00" },
      { num: "0002", status: "보냄", time: "2026-10-14 17:00:00" }
    ]
  }
};

const hTreeRes = api.buildHandoffTree(channelsData, treeData);

eq("프로젝트 노드 개수: 그룹1, 그룹2, 그룹 없음, 연결 안 됨 총 4개", 4, hTreeRes.length);
eq("프로젝트 순서: tree.projects 순서 -> 그룹 없음 -> 연결 안 됨",
  ["cg-1", "cg-2", QA_UNGROUPED, QA_UNLINKED],
  hTreeRes.map(p => p.id));

const hp1 = hTreeRes[0];
eq("cg-1 이름 유지", "ma::proj-alpha", hp1.name);
eq("cg-1 total 집계 (s1의 3개 + s-arch-active의 1개 = 4)", 4, hp1.total);
eq("cg-1 waiting 집계 (보냄 2 + 읽음 1 = 3)", 3, hp1.waiting);
eq("cg-1 latestTime (ch-beta 메시지인 17:00:00)", "2026-10-14 17:00:00", hp1.latestTime);

eq("cg-1 세션 수: 기록 0건인 s2는 나오고, 기록 없는 보관세션은 제외되어 3개", 3, hp1.sessions.length);
eq("cg-1 세션 순서 정렬: 최신 시각 내림차순",
  ["s1", "s-arch-active", "s2"],
  hp1.sessions.map(s => s.id));

const hs1 = hp1.sessions.find(s => s.id === "s1");
eq("두 채널의 메시지가 한 세션(s1)에 모임: total 3, waiting 2", { total: 3, waiting: 2 }, { total: hs1.total, waiting: hs1.waiting });

const hsArch = hp1.sessions.find(s => s.id === "s-arch-active");
ok("보관된 세션은 archived: true 속성 유지", hsArch && hsArch.archived);

const hp2 = hTreeRes[1];
eq("기록이 0건인 프로젝트(cg-2)도 세션과 함께 유지", { id: "cg-2", total: 0, waiting: 0, sessCount: 1 }, {
  id: hp2.id,
  total: hp2.total,
  waiting: hp2.waiting,
  sessCount: hp2.sessions.length
});

const hpUngrouped = hTreeRes[2];
eq("그룹 없음 프로젝트 id 및 이름", { id: QA_UNGROUPED, name: "그룹 없음" }, { id: hpUngrouped.id, name: hpUngrouped.name });
eq("그룹 없음 total 및 waiting (확인함 상태라 waiting은 0)", { total: 1, waiting: 0 }, { total: hpUngrouped.total, waiting: hpUngrouped.waiting });

const hpUnlinked = hTreeRes[3];
eq("연결 안 됨 프로젝트 id 및 이름", { id: QA_UNLINKED, name: "연결 안 됨" }, { id: hpUnlinked.id, name: hpUnlinked.name });
eq("연결 안 됨 total(1) 및 waiting(1: 보냄 상태)", { total: 1, waiting: 1 }, { total: hpUnlinked.total, waiting: hpUnlinked.waiting });
eq("연결 안 됨 세션 id 접두어 c:", "c:ch-alpha", hpUnlinked.sessions[0].id);
eq("연결 안 됨 세션 제목은 채널 이름", "ch-alpha", hpUnlinked.sessions[0].title);

// 그룹 없음 세션이 없을 때는 그룹 없음 노드가 빠지는지 검증
const treeNoUngrouped = api.buildHandoffTree({}, { projects: [], ungrouped: [] });
eq("그룹 없음 세션이 없으면 그룹 없음 노드 제외", false, treeNoUngrouped.some(p => p.id === QA_UNGROUPED));

// 연결 안 됨 기록이 없을 때는 연결 안 됨 노드가 빠지는지 검증
eq("메시지가 없으면 연결 안 됨 노드 제외", false, treeNoUngrouped.some(p => p.id === QA_UNLINKED));

// tree 가 null 일 때 메시지가 있으면 연결 안 됨 노드만 반환
const treeNullRes = api.buildHandoffTree(channelsData, null);
eq("tree null 시 연결 안 됨 노드만 1개", [QA_UNLINKED], treeNullRes.map(p => p.id));

// null 및 빈 입력에 대한 방어
eq("channels 및 tree 가 null 이어도 정상 동작", [], api.buildHandoffTree(null, null));

console.log("\nhandoffFilterTree: 검색어로 트리 필터링");
const sampleNodes = [
  {
    id: "p1",
    name: "Frontend Service",
    sessions: [
      { id: "s1", title: "Login Page" },
      { id: "s2", title: "Dashboard Page" }
    ]
  },
  {
    id: "p2",
    name: "Backend API",
    sessions: [
      { id: "s3", title: "User Auth" },
      { id: "s4", title: "Payment Gateway" }
    ]
  }
];

eq("빈 검색어는 전체 노드 그대로 반환", 2, api.handoffFilterTree(sampleNodes, "").length);
eq("공백만 있는 검색어도 전체 반환", 2, api.handoffFilterTree(sampleNodes, "   ").length);

const projMatch = api.handoffFilterTree(sampleNodes, "Frontend");
eq("프로젝트 이름 일치 시 그 프로젝트의 세션 전부 유지", 1, projMatch.length);
eq("  유지된 세션 수", 2, projMatch[0].sessions.length);

const sessMatch = api.handoffFilterTree(sampleNodes, "auth");
eq("세션 제목 일치 시 해당 프로젝트 포함 및 일치 세션만 남김", 1, sessMatch.length);
eq("  일치한 프로젝트 id", "p2", sessMatch[0].id);
eq("  일치한 세션 목록", ["s3"], sessMatch[0].sessions.map(s => s.id));

const noneMatch = api.handoffFilterTree(sampleNodes, "xyz-not-found");
eq("불일치 검색어는 모든 프로젝트 제외", 0, noneMatch.length);

const caseMatch = api.handoffFilterTree(sampleNodes, "  PAYMENT  ");
eq("검색어 앞뒤 공백 및 대소문자 무시", 1, caseMatch.length);
eq("  일치 세션", ["s4"], caseMatch[0].sessions.map(s => s.id));

console.log("\nhandoffMessagesOf: 선택 조건에 따른 메시지 추출");
const allMsgs = api.handoffMessagesOf(channelsData, treeData, "", "");
eq("전체 선택 시 모든 채널의 메시지 (4 + 2 = 6개)", 6, allMsgs.length);
eq("두 채널이 섞였을 때 시간 오름차순 정렬",
  ["2026-10-14 13:00:00", "2026-10-14 14:00:00", "2026-10-14 15:00:00", "2026-10-14 16:00:00", "2026-10-14 16:30:00", "2026-10-14 17:00:00"],
  allMsgs.map(it => it.msg.time));

const cg1Msgs = api.handoffMessagesOf(channelsData, treeData, "cg-1", "");
eq("프로젝트(cg-1) 선택 시 해당 세션들(s1, s-arch-active)의 메시지 4건", 4, cg1Msgs.length);
eq("cg-1에 두 채널 메시지가 섞여도 시간 오름차순",
  ["2026-10-14 13:00:00", "2026-10-14 14:00:00", "2026-10-14 15:00:00", "2026-10-14 17:00:00"],
  cg1Msgs.map(it => it.msg.time));

const s1Msgs = api.handoffMessagesOf(channelsData, treeData, "cg-1", "s1");
eq("세션(s1) 선택 시 s1 메시지만 3건", 3, s1Msgs.length);
eq("s1 메시지 채널 구성 (ch-alpha 2건 + ch-beta 1건)",
  ["ch-alpha", "ch-alpha", "ch-beta"],
  s1Msgs.map(it => it.channel));

const unlinkedMsgs = api.handoffMessagesOf(channelsData, treeData, QA_UNLINKED, "c:ch-alpha");
eq("연결 안 됨 세션(c:ch-alpha) 선택 시 해당 메시지 1건", 1, unlinkedMsgs.length);
eq("연결 안 됨 메시지 번호", "0004", unlinkedMsgs[0].msg.num);
eq("메시지 객체에 file 속성 포함", "0004-c2a-unlinked.md", unlinkedMsgs[0].file);

// 단일 채널인 경우 채널 원래 순서 유지 검증
const singleChannelData = {
  "ch-single": {
    name: "ch-single",
    files: ["0002-c2a-two.md", "0001-c2a-one.md"],
    messages: [
      { num: "0002", time: "2026-10-14 15:00:00" },
      { num: "0001", time: "2026-10-14 10:00:00" }
    ]
  }
};
const singleMsgs = api.handoffMessagesOf(singleChannelData, null, "", "");
eq("단일 채널 선택 시 원래 배열 순서 유지 (0002, 0001)", ["0002", "0001"], singleMsgs.map(it => it.msg.num));

console.log("\nhandoffLinkOf: 채널 이름이 붙은 연결을 우선하고, 이름이 겹치는 파일은 파일명 연결을 쓰지 않는다");
const dupTree = { handoffLinks: {
  "ch-a/0001-c2a-open.md": "sess-a",
  "0001-c2a-open.md": "sess-z",
  "0002-c2a-only-in-a.md": "sess-b"
} };
testChannels["ch-a"] = { files: ["0001-c2a-open.md", "0002-c2a-only-in-a.md"] };
testChannels["ch-b"] = { files: ["0001-c2a-open.md"] };
eq("채널 이름이 붙은 연결이 있으면 그 세션", "sess-a", api.handoffLinkOf(dupTree, "ch-a", "0001-c2a-open.md"));
eq("다른 채널(ch-b)의 같은 이름 메시지는 파일명 연결로 붙지 않음", null, api.handoffLinkOf(dupTree, "ch-b", "0001-c2a-open.md"));
eq("이름이 겹치지 않는 파일은 파일명 연결 사용", "sess-b", api.handoffLinkOf(dupTree, "ch-a", "0002-c2a-only-in-a.md"));
eq("연결 없음", null, api.handoffLinkOf(dupTree, "ch-a", "0009-c2a-none.md"));
delete testChannels["ch-a"]; delete testChannels["ch-b"];

console.log("\n통과 " + passed + " / 실패 " + failed);
if (failed > 0) {
  process.exit(1);
}
