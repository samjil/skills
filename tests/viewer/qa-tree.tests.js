// Claude Desktop 프로젝트 -> 세션 펼침 트리 순수 함수 테스트.
//   node tests/viewer/qa-tree.tests.js
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
const TREE_SORT_MODES = extractConstant("TREE_SORT_MODES");
const TREE_SORT_DEFAULT = extractConstant("TREE_SORT_DEFAULT");

const names = [
  "qaCwdKey",
  "qaGuessSessionByCwd",
  "qaNodeOf",
  "buildQaTree",
  "qaFilterTree",
  "qaItemMatchesSelection",
  "qaItemMatchesAgy",
  "qaAgySessionsOf",
  "normalizeTreeSortMode",
  "sortTreeNodes"
];

const api = new Function(
  "var QA_UNGROUPED = " + JSON.stringify(QA_UNGROUPED) + ";\n" +
  "var QA_UNLINKED = " + JSON.stringify(QA_UNLINKED) + ";\n" +
  "var TREE_SORT_MODES = " + JSON.stringify(TREE_SORT_MODES) + ";\n" +
  "var TREE_SORT_DEFAULT = " + JSON.stringify(TREE_SORT_DEFAULT) + ";\n" +
  names.map(extractFunction).join("\n") +
  "\nreturn { qaNodeOf, buildQaTree, qaFilterTree, qaItemMatchesSelection, qaItemMatchesAgy, qaAgySessionsOf, normalizeTreeSortMode, sortTreeNodes, QA_UNGROUPED, QA_UNLINKED, TREE_SORT_MODES, TREE_SORT_DEFAULT };"
)();

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\n        기대: " + e + "\n        실제: " + a); }
}
function ok(name, cond) { eq(name, true, Boolean(cond)); }

console.log("상수 확인");
eq("QA_UNGROUPED 상수 값", "__ungrouped__", QA_UNGROUPED);
eq("QA_UNLINKED 상수 값", "__unlinked__", QA_UNLINKED);

console.log("\nqaNodeOf: 위임 항목의 프로젝트/세션 노드 판별");
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
  taskLinks: {
    "task-grp": "cli-sess-1",
    "task-ungrp": "cli-sess-u1",
    "task-deadlink": "cli-sess-deleted",
    "task-empty-title": "cli-sess-empty-title-123456"
  }
};

eq("링크 있음 -> 그룹 세션", {
  projectId: "cg-1",
  projectName: "ma::healthketch-webview",
  sessionId: "cli-sess-1",
  sessionTitle: "건협-kahp"
}, api.qaNodeOf({ task_id: "task-grp", session: "old-session" }, mockTree));

eq("링크 있음 -> 그룹 없는 세션", {
  projectId: QA_UNGROUPED,
  projectName: "그룹 없음",
  sessionId: "cli-sess-u1",
  sessionTitle: "단독세션A"
}, api.qaNodeOf({ task_id: "task-ungrp", session: "old-session" }, mockTree));

eq("링크 있으나 세션이 사라짐 -> 연결 안 됨", {
  projectId: QA_UNLINKED,
  projectName: "연결 안 됨",
  sessionId: "u:saved-session",
  sessionTitle: "saved-session"
}, api.qaNodeOf({ task_id: "task-deadlink", session: "saved-session" }, mockTree));

eq("링크 없음 + @session 이름 -> 연결 안 됨", {
  projectId: QA_UNLINKED,
  projectName: "연결 안 됨",
  sessionId: "u:legacy-sess",
  sessionTitle: "legacy-sess"
}, api.qaNodeOf({ task_id: "unknown-task", session: "legacy-sess" }, mockTree));

eq("단발성 (세션 없음) -> 연결 안 됨", {
  projectId: QA_UNLINKED,
  projectName: "연결 안 됨",
  sessionId: "u:__none__",
  sessionTitle: "단발성 (세션 없음)"
}, api.qaNodeOf({ task_id: "unknown-task" }, mockTree));

eq("tree 가 null 인 경우 -> 연결 안 됨", {
  projectId: QA_UNLINKED,
  projectName: "연결 안 됨",
  sessionId: "u:my-sess",
  sessionTitle: "my-sess"
}, api.qaNodeOf({ task_id: "task-grp", session: "my-sess" }, null));

eq("세션 제목이 비어 있으면 id 앞 8자리", {
  projectId: "cg-1",
  projectName: "ma::healthketch-webview",
  sessionId: "cli-sess-empty-title-123456",
  sessionTitle: "cli-sess"
}, api.qaNodeOf({ task_id: "task-empty-title" }, mockTree));

console.log("\nbuildQaTree: 프로젝트 및 세션 트리 구성과 집계");
const treeData = {
  projects: [
    {
      id: "cg-1",
      name: "ma::proj-alpha",
      sessions: [
        { id: "s1", title: "세션 1", cwd: "D:\\a", lastActivity: "2026-10-14 10:00:00", archived: false },
        { id: "s2", title: "세션 2", cwd: "D:\\b", lastActivity: "2026-10-14 12:00:00", archived: false },
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
  taskLinks: {
    "t1": "s1",
    "t2": "s1",
    "t3": "s-arch-active",
    "t4": "u1"
  }
};

const records = [
  { task_id: "t1", status: "OK", timestamp: "2026-10-14 13:00:00" },
  { task_id: "t2", status: "ERROR", timestamp: "2026-10-14 14:00:00" },
  { task_id: "t3", status: "OK", timestamp: "2026-10-14 15:00:00" },
  { task_id: "unlinked-rec", session: "단독작업", status: "OK", timestamp: "2026-10-14 16:00:00" }
];

const pendings = [
  { task_id: "t4", created: "2026-10-14 16:30:00" },
  { task_id: "unlinked-pend", session: "단독작업", created: "2026-10-14 17:00:00" }
];

const treeRes = api.buildQaTree(records, pendings, treeData);

eq("프로젝트 노드 개수: 그룹1, 그룹2, 그룹 없음, 연결 안 됨 총 4개", 4, treeRes.length);
eq("프로젝트 순서: tree.projects 순서 -> 그룹 없음 -> 연결 안 됨",
  ["cg-1", "cg-2", QA_UNGROUPED, QA_UNLINKED],
  treeRes.map(p => p.id));

const p1 = treeRes[0];
eq("cg-1 이름 유지", "ma::proj-alpha", p1.name);
eq("cg-1 total 집계 (t1 OK + t2 ERROR + t3 OK = 3)", 3, p1.total);
eq("cg-1 errors 집계 (t2 ERROR = 1)", 1, p1.errors);
eq("cg-1 pending 집계 (0)", 0, p1.pending);
eq("cg-1 latestTime (t3의 15:00:00)", "2026-10-14 15:00:00", p1.latestTime);

eq("cg-1 세션 수: 기록 0건인 s2는 나오고, 기록 없는 보관세션은 제외되어 3개", 3, p1.sessions.length);
eq("cg-1 세션 순서 정렬: 최신 시각(latestTime 또는 lastActivity) 내림차순",
  ["s-arch-active", "s1", "s2"],
  p1.sessions.map(s => s.id));

const sArch = p1.sessions.find(s => s.id === "s-arch-active");
ok("보관된 세션은 archived: true 속성 유지", sArch && sArch.archived);

const p2 = treeRes[1];
eq("기록이 0건인 프로젝트(cg-2)도 세션과 함께 유지", { id: "cg-2", total: 0, pending: 0, sessCount: 1 }, {
  id: p2.id,
  total: p2.total,
  pending: p2.pending,
  sessCount: p2.sessions.length
});

const pUngrouped = treeRes[2];
eq("그룹 없음 프로젝트 id 및 이름", { id: QA_UNGROUPED, name: "그룹 없음" }, { id: pUngrouped.id, name: pUngrouped.name });
eq("그룹 없음 pending 집계", 1, pUngrouped.pending);

const pUnlinked = treeRes[3];
eq("연결 안 됨 프로젝트 id 및 이름", { id: QA_UNLINKED, name: "연결 안 됨" }, { id: pUnlinked.id, name: pUnlinked.name });
eq("연결 안 됨 total(1) 및 pending(1)", { total: 1, pending: 1 }, { total: pUnlinked.total, pending: pUnlinked.pending });
eq("연결 안 됨 세션 id 접두어 u:", "u:단독작업", pUnlinked.sessions[0].id);

// 그룹 없음 세션이 없을 때는 그룹 없음 노드가 빠지는지 검증
const treeNoUngrouped = api.buildQaTree([], [], { projects: [], ungrouped: [] });
eq("그룹 없음 세션이 없으면 그룹 없음 노드 제외", false, treeNoUngrouped.some(p => p.id === QA_UNGROUPED));

// 연결 안 됨 기록이 없을 때는 연결 안 됨 노드가 빠지는지 검증
eq("기록이 없으면 연결 안 됨 노드 제외", false, treeNoUngrouped.some(p => p.id === QA_UNLINKED));

// tree 가 null 일 때 기록이 있으면 연결 안 됨 노드만 반환
const treeNullRes = api.buildQaTree([{ session: "s", timestamp: "2026-10-14 10:00:00" }], [], null);
eq("tree null 시 연결 안 됨 노드만 1개", [QA_UNLINKED], treeNullRes.map(p => p.id));

// null 및 빈 입력에 대한 방어
eq("records 및 pendings 가 null 이어도 정상 동작", [], api.buildQaTree(null, null, null));
eq("배열 안에 null 항목이 있어도 안전하게 처리", true, Array.isArray(api.buildQaTree([null], [null], null)));

console.log("\nqaFilterTree: 검색어로 트리 필터링");
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

eq("빈 검색어는 전체 노드 그대로 반환", 2, api.qaFilterTree(sampleNodes, "").length);
eq("공백만 있는 검색어도 전체 반환", 2, api.qaFilterTree(sampleNodes, "   ").length);

const projMatch = api.qaFilterTree(sampleNodes, "Frontend");
eq("프로젝트 이름 일치 시 그 프로젝트의 세션 전부 유지", 1, projMatch.length);
eq("  유지된 세션 수", 2, projMatch[0].sessions.length);

const sessMatch = api.qaFilterTree(sampleNodes, "auth");
eq("세션 제목 일치 시 해당 프로젝트 포함 및 일치 세션만 남김", 1, sessMatch.length);
eq("  일치한 프로젝트 id", "p2", sessMatch[0].id);
eq("  일치한 세션 목록", ["s3"], sessMatch[0].sessions.map(s => s.id));

const noneMatch = api.qaFilterTree(sampleNodes, "xyz-not-found");
eq("불일치 검색어는 모든 프로젝트 제외", 0, noneMatch.length);

const caseMatch = api.qaFilterTree(sampleNodes, "  PAYMENT  ");
eq("검색어 앞뒤 공백 및 대소문자 무시", 1, caseMatch.length);
eq("  일치 세션", ["s4"], caseMatch[0].sessions.map(s => s.id));

console.log("\nqaItemMatchesSelection: 선택 조건 일치 여부 확인");
const testTree = {
  projects: [
    {
      id: "proj-1",
      name: "Project One",
      sessions: [{ id: "sess-1", title: "Session 1" }]
    }
  ],
  ungrouped: [],
  taskLinks: {
    "task-1": "sess-1"
  }
};

const matchItem = { task_id: "task-1", session: "sess-1" };
const otherItem = { task_id: "task-2", session: "other-sess" };

eq("전체 선택 (projectId 비어있음): 항상 true", true, api.qaItemMatchesSelection(matchItem, testTree, "", ""));
eq("프로젝트만 선택 (projectId 일치): true", true, api.qaItemMatchesSelection(matchItem, testTree, "proj-1", ""));
eq("프로젝트만 선택 (projectId 불일치): false", false, api.qaItemMatchesSelection(matchItem, testTree, "proj-other", ""));
eq("프로젝트 + 세션 모두 일치: true", true, api.qaItemMatchesSelection(matchItem, testTree, "proj-1", "sess-1"));
eq("프로젝트 일치하나 세션 불일치: false", false, api.qaItemMatchesSelection(matchItem, testTree, "proj-1", "sess-other"));
eq("다른 프로젝트의 항목: false", false, api.qaItemMatchesSelection(otherItem, testTree, "proj-1", ""));

console.log("\nqaItemMatchesAgy: agy 세션 필터 조건 확인");
eq("빈 값: 빈 agy 세션 이름은 항상 true", true, api.qaItemMatchesAgy({ session: "sess1" }, ""));
eq("빈 값: 빈 item.session 과 빈 agy", true, api.qaItemMatchesAgy({ session: "" }, ""));
eq("빈 값: null item 과 빈 agy", true, api.qaItemMatchesAgy(null, ""));
eq("단발성: item.session 이 비어있음", true, api.qaItemMatchesAgy({ session: "" }, "__none__"));
eq("단발성: item.session 이 null", true, api.qaItemMatchesAgy({ session: null }, "__none__"));
eq("단발성: item.session 이 공백만 있음", true, api.qaItemMatchesAgy({ session: "   " }, "__none__"));
eq("단발성: 세션이 있는 경우 false", false, api.qaItemMatchesAgy({ session: "sess1" }, "__none__"));
eq("단발성: item 이 null 인 경우 true", true, api.qaItemMatchesAgy(null, "__none__"));
eq("이름 일치: 같은 이름일 때 true", true, api.qaItemMatchesAgy({ session: "sess1" }, "sess1"));
eq("이름 불일치: 다른 이름일 때 false", false, api.qaItemMatchesAgy({ session: "sess2" }, "sess1"));
eq("공백 처리: session 값 앞뒤 공백 제거 후 일치", true, api.qaItemMatchesAgy({ session: "  sess1  " }, "sess1"));
eq("공백 처리: agy 에 공백이 있으면 false", false, api.qaItemMatchesAgy({ session: "sess1" }, "  sess1  "));

console.log("\nqaAgySessionsOf: 범위 내 agy 세션 집계 및 정렬");
const agyTestTree = {
  projects: [
    {
      id: "p1",
      name: "Proj 1",
      sessions: [
        { id: "s1", title: "Sess 1" },
        { id: "s2", title: "Sess 2" }
      ]
    },
    {
      id: "p2",
      name: "Proj 2",
      sessions: [{ id: "s3", title: "Sess 3" }]
    }
  ],
  ungrouped: [],
  taskLinks: {
    "t1": "s1",
    "t2": "s1",
    "t3": "s1",
    "t4": "s2",
    "t5": "s3",
    "t-pend": "s1"
  }
};

const agyRecords = [
  { task_id: "t1", session: "main-fix", status: "OK", timestamp: "2026-10-14 10:00:00" },
  { task_id: "t2", session: "main-fix", status: "ERROR", timestamp: "2026-10-14 11:00:00" },
  { task_id: "t3", session: "ui-tune", status: "OK", timestamp: "2026-10-14 12:00:00" },
  { task_id: "t4", session: "", status: "OK", timestamp: "2026-10-14 09:00:00" },
  { task_id: "t5", session: "other-proj-sess", status: "OK", timestamp: "2026-10-14 13:00:00" },
  { task_id: "t-dead", session: "unlinked-sess", status: "OK", timestamp: "2026-10-14 14:00:00" },
  { task_id: "t1", session: "   ", status: "OK", timestamp: "2026-10-14 08:00:00" }
];

const agyPendings = [
  { task_id: "t-pend", session: "main-fix", created: "2026-10-14 15:00:00" }
];

const allAgy = api.qaAgySessionsOf(agyRecords, agyPendings, agyTestTree, "", "");
eq("범위 전체: 집계된 세션 수", 5, allAgy.length);
eq("범위 전체: 최신순 정렬 첫 번째", "main-fix", allAgy[0].name);

const p1Agy = api.qaAgySessionsOf(agyRecords, agyPendings, agyTestTree, "p1", "");
eq("프로젝트만: 세션 수", 3, p1Agy.length);
eq("프로젝트만: 포함된 세션 이름들", ["main-fix", "ui-tune", "__none__"], p1Agy.map(s => s.name));

const s1Agy = api.qaAgySessionsOf(agyRecords, agyPendings, agyTestTree, "p1", "s1");
eq("프로젝트+세션: s1 세션 수", 3, s1Agy.length);

const noneEntry = allAgy.find(s => s.name === "__none__");
ok("단발성은 __none__ 키로 집계", noneEntry);
eq("단발성 total 집계 (빈 문자열 1 + 공백뿐 1 = 2)", 2, noneEntry.total);

const mainFixEntry = allAgy.find(s => s.name === "main-fix");
ok("main-fix 존재", mainFixEntry);
eq("main-fix total (t1 OK + t2 ERROR = 2)", 2, mainFixEntry.total);
eq("main-fix pending (t-pend = 1)", 1, mainFixEntry.pending);
eq("main-fix errors (t2 ERROR = 1)", 1, mainFixEntry.errors);
eq("main-fix latestTime (pending의 15:00:00)", "2026-10-14 15:00:00", mainFixEntry.latestTime);

const sameTimeRecs = [
  { task_id: "t1", session: "beta", status: "OK", timestamp: "2026-10-14 10:00:00" },
  { task_id: "t1", session: "alpha", status: "OK", timestamp: "2026-10-14 10:00:00" }
];
const sameTimeRes = api.qaAgySessionsOf(sameTimeRecs, [], agyTestTree, "", "");
eq("시각 같으면 name 오름차순: alpha가 앞", "alpha", sameTimeRes[0].name);
eq("시각 같으면 name 오름차순: beta가 뒤", "beta", sameTimeRes[1].name);

eq("null 입력 시 빈 배열", [], api.qaAgySessionsOf(null, null, null, "", ""));
eq("배열 내 null 항목 안전 처리", [], api.qaAgySessionsOf([null], [null], null, "", ""));

const nullTreeRes = api.qaAgySessionsOf(
  [{ task_id: "x", session: "foo", timestamp: "2026-10-14 10:00:00" }],
  [],
  null,
  QA_UNLINKED,
  ""
);
eq("tree null 시 연결 안 됨 범위에 포함", 1, nullTreeRes.length);
eq("tree null 세션 이름", "foo", nullTreeRes[0].name);

console.log("\nnormalizeTreeSortMode: 정렬 모드 정규화");
eq("정상 모드 유지: recent-desc", "recent-desc", api.normalizeTreeSortMode("recent-desc"));
eq("정상 모드 유지: recent-asc", "recent-asc", api.normalizeTreeSortMode("recent-asc"));
eq("정상 모드 유지: name-asc", "name-asc", api.normalizeTreeSortMode("name-asc"));
eq("정상 모드 유지: name-desc", "name-desc", api.normalizeTreeSortMode("name-desc"));
eq("정상 모드 유지: desktop", "desktop", api.normalizeTreeSortMode("desktop"));
eq("없는 값 -> 기본값(recent-desc)", "recent-desc", api.normalizeTreeSortMode("invalid-mode"));
eq("null -> 기본값(recent-desc)", "recent-desc", api.normalizeTreeSortMode(null));
eq("undefined -> 기본값(recent-desc)", "recent-desc", api.normalizeTreeSortMode(undefined));
eq("빈 문자열 -> 기본값(recent-desc)", "recent-desc", api.normalizeTreeSortMode(""));

console.log("\nsortTreeNodes: 프로젝트 및 세션 정렬");
const sortSampleNodes = [
  {
    id: "pA",
    name: "나 프로젝트",
    latestTime: "2026-10-14 10:00:00",
    sessions: [
      { id: "sA1", title: "b세션", latestTime: "2026-10-14 09:00:00", lastActivity: "2026-10-14 15:00:00" },
      { id: "sA2", title: "a세션", latestTime: "2026-10-14 08:00:00", lastActivity: "" }
    ]
  },
  {
    id: "pB",
    name: "가 프로젝트 10",
    latestTime: "2026-10-14 12:00:00",
    sessions: [
      { id: "sB1", title: "세션 2", latestTime: "2026-10-14 11:00:00", lastActivity: "" },
      { id: "sB2", title: "세션 10", latestTime: "2026-10-14 10:00:00", lastActivity: "" }
    ]
  },
  {
    id: "pC",
    name: "가 프로젝트 2",
    latestTime: "",
    sessions: []
  },
  {
    id: QA_UNGROUPED,
    name: "그룹 없음",
    latestTime: "2026-10-14 20:00:00",
    sessions: []
  },
  {
    id: QA_UNLINKED,
    name: "연결 안 됨",
    latestTime: "2026-10-14 21:00:00",
    sessions: []
  }
];

const sortRecentDesc = api.sortTreeNodes(sortSampleNodes, "recent-desc");
eq("날짜 최신순: 세션 lastActivity 가 더 늦은 pA 가 앞", "pA", sortRecentDesc[0].id);
eq("날짜 최신순: 두 번째 pB", "pB", sortRecentDesc[1].id);
eq("날짜 최신순: 세 번째 pC (날짜 없음)", "pC", sortRecentDesc[2].id);
eq("날짜 최신순: 특별 노드 그룹 없음 뒤", QA_UNGROUPED, sortRecentDesc[3].id);
eq("날짜 최신순: 특별 노드 연결 안 됨 맨 뒤", QA_UNLINKED, sortRecentDesc[4].id);
eq("날짜 최신순: pA 내부 세션도 최신순(sA1 앞)", ["sA1", "sA2"], sortRecentDesc[0].sessions.map(s => s.id));

const sortRecentAsc = api.sortTreeNodes(sortSampleNodes, "recent-asc");
eq("날짜 오래된순: 날짜 없는 pC 가 가장 앞", "pC", sortRecentAsc[0].id);
eq("날짜 오래된순: 두 번째 pB", "pB", sortRecentAsc[1].id);
eq("날짜 오래된순: 세 번째 pA", "pA", sortRecentAsc[2].id);
eq("날짜 오래된순: 특별 노드는 여전히 맨 뒤 (그룹 없음)", QA_UNGROUPED, sortRecentAsc[3].id);
eq("날짜 오래된순: 특별 노드는 여전히 맨 뒤 (연결 안 됨)", QA_UNLINKED, sortRecentAsc[4].id);

const sortNameAsc = api.sortTreeNodes(sortSampleNodes, "name-asc");
eq("이름순: 자연수 정렬 '가 프로젝트 2' 앞", "pC", sortNameAsc[0].id);
eq("이름순: '가 프로젝트 10' 두 번째", "pB", sortNameAsc[1].id);
eq("이름순: '나 프로젝트' 세 번째", "pA", sortNameAsc[2].id);
eq("이름순: 특별 노드는 맨 뒤", [QA_UNGROUPED, QA_UNLINKED], [sortNameAsc[3].id, sortNameAsc[4].id]);
eq("이름순: 세션 자연수 정렬('세션 2' 앞)", ["sB1", "sB2"], sortNameAsc[1].sessions.map(s => s.id));

const sortNameDesc = api.sortTreeNodes(sortSampleNodes, "name-desc");
eq("이름 역순: '나 프로젝트' 앞", "pA", sortNameDesc[0].id);
eq("이름 역순: '가 프로젝트 10' 두 번째", "pB", sortNameDesc[1].id);
eq("이름 역순: '가 프로젝트 2' 세 번째", "pC", sortNameDesc[2].id);
eq("이름 역순: 특별 노드는 맨 뒤", [QA_UNGROUPED, QA_UNLINKED], [sortNameDesc[3].id, sortNameDesc[4].id]);

const desktopInput = [sortSampleNodes[1], sortSampleNodes[0], sortSampleNodes[2], sortSampleNodes[3], sortSampleNodes[4]];
const sortDesktop = api.sortTreeNodes(desktopInput, "desktop");
eq("desktop: 프로젝트는 입력 순서 유지 (pB, pA, pC)", ["pB", "pA", "pC"], [sortDesktop[0].id, sortDesktop[1].id, sortDesktop[2].id]);
eq("desktop: 세션은 날짜 최신순 정렬", ["sA1", "sA2"], sortDesktop[1].sessions.map(s => s.id));

const origSessions0 = sortSampleNodes[0].sessions;
const sortResForImmutability = api.sortTreeNodes(sortSampleNodes, "name-asc");
eq("원본 불변: 반환 배열은 원본과 다른 객체", false, sortSampleNodes === sortResForImmutability);
eq("원본 불변: 노드 안의 sessions 도 새 배열", false, sortSampleNodes[0].sessions === sortResForImmutability[2].sessions);
eq("원본 불변: 원본 세션 순서 유지", origSessions0, sortSampleNodes[0].sessions);

const stableNodes = [
  { id: "x1", name: "동일이름", latestTime: "2026-10-14 10:00:00", sessions: [] },
  { id: "x2", name: "동일이름", latestTime: "2026-10-14 10:00:00", sessions: [] },
  { id: "x3", name: "동일이름", latestTime: "2026-10-14 10:00:00", sessions: [] }
];
const stableRes = api.sortTreeNodes(stableNodes, "name-asc");
eq("같은 키일 때 안정적 순서 유지", ["x1", "x2", "x3"], stableRes.map(n => n.id));

eq("빈 배열 정렬", [], api.sortTreeNodes([], "recent-desc"));
eq("null 입력 정렬", [], api.sortTreeNodes(null, "recent-desc"));
eq("배열 내 null 항목 안전 처리", [], api.sortTreeNodes([null], "recent-desc"));

console.log("\nsortTreeNodes: dateSource=records (에이전트 위임 화면: agy 작업 시각만 기준)");
const recNodes = [
  { id: "p-active", name: "활동만 있는 프로젝트", latestTime: "", sessions: [{ id: "s1", title: "진행중 세션", latestTime: "", lastActivity: "2026-10-14 20:00:00" }] },
  { id: "p-old", name: "예전 위임", latestTime: "2026-10-10 09:00:00", sessions: [{ id: "s2", title: "예전", latestTime: "2026-10-10 09:00:00", lastActivity: "2026-10-10 09:30:00" }] },
  { id: "p-new", name: "최근 위임", latestTime: "2026-10-14 10:00:00", sessions: [{ id: "s3", title: "최근", latestTime: "2026-10-14 10:00:00", lastActivity: "2026-10-14 10:05:00" }] },
  { id: "p-idle", name: "기록도 활동도 없음", latestTime: "", sessions: [{ id: "s4", title: "빈 세션", latestTime: "", lastActivity: "" }] }
];
const idsOf = (list) => list.map((n) => n.id).join(",");
eq("기본(Desktop 활동 포함): 최근 활동이 있는 프로젝트가 앞", "p-active,p-new,p-old,p-idle", idsOf(api.sortTreeNodes(recNodes, "recent-desc")));
eq("records: 위임 기록이 최근인 프로젝트가 앞, 기록 없는 것은 Desktop 활동순으로 뒤", "p-new,p-old,p-active,p-idle", idsOf(api.sortTreeNodes(recNodes, "recent-desc", { dateSource: "records" })));
eq("records 오래된순: 기록 없는 것이 앞(보조 기준도 오래된순)", "p-idle,p-active,p-old,p-new", idsOf(api.sortTreeNodes(recNodes, "recent-asc", { dateSource: "records" })));
const recSessions = [{ id: "a", title: "A", latestTime: "", lastActivity: "2026-10-14 20:00:00" }, { id: "b", title: "B", latestTime: "2026-10-14 08:00:00", lastActivity: "2026-10-14 08:00:00" }, { id: "c", title: "C", latestTime: "2026-10-13 08:00:00", lastActivity: "2026-10-14 21:00:00" }];
eq("records: 세션도 위임 시각 우선(기록 없는 세션은 뒤)", "b,c,a", api.sortTreeNodes([{ id: "p", name: "P", latestTime: "", sessions: recSessions }], "recent-desc", { dateSource: "records" })[0].sessions.map((x) => x.id).join(","));
eq("옵션이 없으면 예전 동작과 같다(기록·Desktop 활동 중 늦은 쪽: c 21시 > a 20시 > b 8시)", "c,a,b", api.sortTreeNodes([{ id: "p", name: "P", latestTime: "", sessions: recSessions }], "recent-desc")[0].sessions.map((x) => x.id).join(","));
eq("records 모드여도 이름순은 영향 없음", "p-idle,p-active,p-old,p-new".split(",").length, api.sortTreeNodes(recNodes, "name-asc", { dateSource: "records" }).length);

console.log("\nbuildQaTree: latestDone(완료 시각)은 끝난 기록만");
const doneTree = { projects: [{ id: "g1", name: "G1", sessions: [{ id: "sA", title: "A", lastActivity: "2026-10-14 23:00:00" }, { id: "sB", title: "B", lastActivity: "" }] }], ungrouped: [], taskLinks: { t1: "sA", t2: "sA", t3: "sB" }, handoffLinks: {} };
const doneRecs = [{ task_id: "t1", status: "OK", timestamp: "2026-10-14 10:00:00" }, { task_id: "t2", status: "ERROR", timestamp: "2026-10-14 12:00:00" }];
const donePend = [{ task_id: "t3", created: "2026-10-14 22:00:00", state: "processing" }];
const doneNodes = api.buildQaTree(doneRecs, donePend, doneTree);
const gNode = doneNodes[0];
const sNodeA = gNode.sessions.filter((x) => x.id === "sA")[0];
const sNodeB = gNode.sessions.filter((x) => x.id === "sB")[0];
eq("세션 A: 완료 시각은 끝난 기록 중 가장 늦은 것(실패 기록도 완료)", "2026-10-14 12:00:00", sNodeA.latestDone);
eq("세션 B: 진행 중인 작업만 있으면 완료 시각이 없다(latestTime 에는 시작 시각)", "|2026-10-14 22:00:00", (sNodeB.latestDone || "") + "|" + sNodeB.latestTime);
eq("프로젝트의 완료 시각은 세션들의 완료 시각 중 가장 늦은 것", "2026-10-14 12:00:00", gNode.latestDone);
const doneSorted = api.sortTreeNodes([
  { id: "p-run", name: "진행만", latestTime: "2026-10-14 22:00:00", latestDone: "", sessions: [] },
  { id: "p-fin", name: "완료됨", latestTime: "2026-10-14 12:00:00", latestDone: "2026-10-14 12:00:00", sessions: [] }
], "recent-desc", { dateSource: "records" });
eq("records 정렬은 완료 시각 기준: 진행 중이던 프로젝트도 완료 시각이 없으면 뒤", "p-fin,p-run", doneSorted.map((n) => n.id).join(","));

console.log("\nqaNodeOf: 대기·진행 중 작업은 작업 폴더로 세션을 짐작한다");
const guessTree = {
  projects: [{ id: "g1", name: "sh::q", sessions: [
    { id: "s-old", title: "예전 세션", cwd: "D:\\Repos\\q", lastActivity: "2026-10-14 10:00:00", archived: false },
    { id: "s-new", title: "[문진추적]", cwd: "d:/repos/q/", lastActivity: "2026-10-14 22:00:00", archived: false },
    { id: "s-arch", title: "보관됨", cwd: "D:\\Repos\\q", lastActivity: "2026-10-14 23:00:00", archived: true },
    { id: "s-other", title: "다른 폴더", cwd: "D:\\Repos\\other", lastActivity: "2026-10-14 23:30:00", archived: false }
  ] }],
  ungrouped: [{ id: "s-free", title: "그룹 없는 세션", cwd: "E:\\x", lastActivity: "2026-10-14 21:00:00", archived: false }],
  taskLinks: { "t-done": "s-old" }, handoffLinks: {}
};
const pendingGuess = { task_id: "t-run", state: "processing", created: "2026-10-14 22:10:00", cwd: ["D:\\Repos\\q"], session: "문진-세션" };
const guessNode = api.qaNodeOf(pendingGuess, guessTree);
eq("진행 중 작업: 같은 폴더의 세션 중 가장 최근에 쓴 보관 안 된 세션(대소문자·슬래시 무시)", "g1|sh::q|s-new|[문진추적]", [guessNode.projectId, guessNode.projectName, guessNode.sessionId, guessNode.sessionTitle].join("|"));
eq("그룹 없는 세션도 짐작 대상", "__ungrouped__|s-free", (function () { const n = api.qaNodeOf({ task_id: "t2", state: "queued", cwd: ["E:\\x"] }, guessTree); return n.projectId + "|" + n.sessionId; })());
eq("폴더가 어느 세션과도 안 맞으면 연결 안 됨(예전 @session 이름)", "__unlinked__|u:문진-세션", (function () { const n = api.qaNodeOf({ task_id: "t3", state: "processing", cwd: ["D:\\nowhere"], session: "문진-세션" }, guessTree); return n.projectId + "|" + n.sessionId; })());
eq("폴더가 없는 진행 중 작업은 짐작하지 않는다", "__unlinked__", api.qaNodeOf({ task_id: "t4", state: "processing", cwd: [] }, guessTree).projectId);
eq("완료 기록(timestamp 있음)은 짐작하지 않고 링크만 본다", "__unlinked__", api.qaNodeOf({ task_id: "t5", timestamp: "2026-10-14 10:00:00", status: "OK", cwd: ["D:\\Repos\\q"] }, guessTree).projectId);
eq("링크가 있으면 짐작보다 링크가 먼저", "s-old", api.qaNodeOf({ task_id: "t-done", state: "processing", cwd: ["D:\\Repos\\q"] }, guessTree).sessionId);
eq("tree 가 null 이면 짐작 없이 연결 안 됨", "__unlinked__", api.qaNodeOf(pendingGuess, null).projectId);

console.log("\n통과 " + passed + " / 실패 " + failed);
if (failed > 0) {
  process.exit(1);
}
