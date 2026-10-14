// 위임 실행 기록 프로젝트 단위 묶기 순수 함수 테스트.
//   node tests/viewer/qa-project.tests.js
// runtime/viewer/web/app.js 에서 함수 원문을 꺼내 그대로 실행합니다.
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

const names = [
  "cwdListOf",
  "leadingCwds",
  "qaProjectNameFromPath",
  "qaProjectOf",
  "groupQaProjects",
  "groupQaSessionsOfProject",
  "qaProjectKeyOfSession"
];

const api = new Function(names.map(extractFunction).join("\n") +
  "\nreturn { cwdListOf, leadingCwds, qaProjectNameFromPath, qaProjectOf, groupQaProjects, groupQaSessionsOfProject, qaProjectKeyOfSession };")();

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\n        기대: " + e + "\n        실제: " + a); }
}
function ok(name, cond) { eq(name, true, Boolean(cond)); }

console.log("qaProjectNameFromPath: 경로에서 프로젝트 이름 추출");
eq("일반 윈도우 경로", "healthketch-webview", api.qaProjectNameFromPath("D:\\a\\b\\healthketch-webview"));
eq("끝에 \\ 가 있는 윈도우 경로", "healthketch-webview", api.qaProjectNameFromPath("D:\\a\\b\\healthketch-webview\\"));
eq("끝에 \\ 여러 개", "healthketch-webview", api.qaProjectNameFromPath("D:\\a\\b\\healthketch-webview\\\\\\"));
eq("/ 경로", "healthketch-webview", api.qaProjectNameFromPath("/repos/src/healthketch-webview"));
eq("끝에 / 가 있는 / 경로", "healthketch-webview", api.qaProjectNameFromPath("/repos/src/healthketch-webview/"));
eq("드라이브 루트 D:\\", "D:", api.qaProjectNameFromPath("D:\\"));
eq("드라이브 루트 D:/", "D:", api.qaProjectNameFromPath("D:/"));
eq("드라이브 문자 D:", "D:", api.qaProjectNameFromPath("D:"));
eq("빈 문자열", "", api.qaProjectNameFromPath(""));
eq("null", "", api.qaProjectNameFromPath(null));
eq("undefined", "", api.qaProjectNameFromPath(undefined));
eq("공백만 있는 문자열", "", api.qaProjectNameFromPath("   "));
eq("앞뒤 공백이 있는 경로", "proj", api.qaProjectNameFromPath("   D:\\a\\proj   "));
eq("루트 / 만 있는 경우", "", api.qaProjectNameFromPath("/"));
eq("루트 \\ 만 있는 경우", "", api.qaProjectNameFromPath("\\"));

console.log("\nqaProjectOf: 완료/대기 항목의 프로젝트 정보 판별 및 캐싱");
const recWithCwds = {
  question: "@cwd: D:\\Sources\\healthketch-webview\n@cwd: D:\\Sources\\other\n지시어 뒤 본문",
  cwd: undefined
};
eq("완료 기록: question 맨 위 @cwd 중 첫 폴더 기준", { key: "healthketch-webview", name: "healthketch-webview" }, api.qaProjectOf(recWithCwds));

const pendingItem = {
  question: "지시어 없는 순수 본문",
  cwd: ["D:\\Sources\\x\\my-service", "D:\\Sources\\other"]
};
eq("대기 작업: cwd 배열 기준", { key: "my-service", name: "my-service" }, api.qaProjectOf(pendingItem));

const noCwdItem = {
  question: "폴더 지정이 없는 질문",
  cwd: []
};
eq("@cwd 없음: __none__ / 프로젝트 없음", { key: "__none__", name: "프로젝트 없음" }, api.qaProjectOf(noCwdItem));

const itemCase1 = { cwd: ["D:\\repos\\MyProject"] };
const itemCase2 = { cwd: ["D:\\repos\\myproject"] };
eq("대소문자 다른 폴더는 같은 key", true, api.qaProjectOf(itemCase1).key === api.qaProjectOf(itemCase2).key);
eq("대소문자 다른 폴더의 원래 표기 유지", "MyProject", api.qaProjectOf(itemCase1).name);
eq("소문자 폴더의 원래 표기 유지", "myproject", api.qaProjectOf(itemCase2).name);

const cacheTarget = { cwd: ["D:\\repo\\sample"] };
const res1 = api.qaProjectOf(cacheTarget);
const res2 = api.qaProjectOf(cacheTarget);
ok("동일 객체 재호출 시 _qaProject 캐시 객체 반환", res1 === res2);
eq("캐시된 값 검증", { key: "sample", name: "sample" }, res1);

eq("null 항목은 __none__", { key: "__none__", name: "프로젝트 없음" }, api.qaProjectOf(null));
eq("객체가 아닌 항목은 __none__", { key: "__none__", name: "프로젝트 없음" }, api.qaProjectOf("invalid"));

console.log("\ngroupQaProjects: 프로젝트별 완료/대기/오류 집계 및 최신순 정렬");
const fakeRecords = [
  { cwd: ["D:\\repos\\Alpha"], status: "OK", timestamp: "2026-10-10 10:00:00" },
  { cwd: ["D:\\repos\\alpha"], status: "ERROR", timestamp: "2026-10-12 12:00:00" },
  { cwd: ["D:\\repos\\Beta"], status: "OK", timestamp: "2026-10-11 09:00:00" },
  null
];
const fakePendings = [
  { cwd: ["D:\\repos\\Alpha"], created: "2026-10-13 08:00:00" },
  { question: "폴더 없음", cwd: [], created: "2026-10-09 00:00:00" },
  null
];

const projects = api.groupQaProjects(fakeRecords, fakePendings);
eq("프로젝트 수 (Alpha, Beta, __none__)", 3, projects.length);
eq("1위는 최신 활동(2026-10-13)이 있는 alpha", "alpha", projects[0].key);
eq("alpha 집계: total=2, pending=1, errors=1", { total: 2, pending: 1, errors: 1 }, {
  total: projects[0].total,
  pending: projects[0].pending,
  errors: projects[0].errors
});
eq("alpha latestTime", "2026-10-13 08:00:00", projects[0].latestTime);

eq("2위는 Beta (2026-10-11)", "beta", projects[1].key);
eq("Beta 집계: total=1, pending=0, errors=0", { total: 1, pending: 0, errors: 0 }, {
  total: projects[1].total,
  pending: projects[1].pending,
  errors: projects[1].errors
});

eq("3위는 __none__ (2026-10-09)", "__none__", projects[2].key);
eq("__none__ 집계: total=0, pending=1, errors=0", { total: 0, pending: 1, errors: 0 }, {
  total: projects[2].total,
  pending: projects[2].pending,
  errors: projects[2].errors
});

// 이름 최신 표기 검증
const nameTestRecs = [
  { cwd: ["D:\\repos\\projNameLower"], timestamp: "2026-10-01 10:00:00" },
  { cwd: ["D:\\repos\\ProjNameUpper"], timestamp: "2026-10-05 10:00:00" }
];
const nameGroup = api.groupQaProjects(nameTestRecs, []);
eq("더 최신 항목의 이름 표기(ProjNameUpper) 적용", "ProjNameUpper", nameGroup[0].name);

const nameTestReverse = [
  { cwd: ["D:\\repos\\ProjNameUpper"], timestamp: "2026-10-05 10:00:00" },
  { cwd: ["D:\\repos\\projNameLower"], timestamp: "2026-10-01 10:00:00" }
];
const nameGroupReverse = api.groupQaProjects(nameTestReverse, []);
eq("순서가 반대여도 더 최신 항목의 이름 표기 유지", "ProjNameUpper", nameGroupReverse[0].name);

// 동일 시각 정렬 검증 (name 오름차순)
const sameTimeRecs = [
  { cwd: ["D:\\repos\\zebra"], timestamp: "2026-10-10 10:00:00" },
  { cwd: ["D:\\repos\\apple"], timestamp: "2026-10-10 10:00:00" }
];
const sameTimeGroup = api.groupQaProjects(sameTimeRecs, []);
eq("동일 시각이면 name 오름차순: apple이 앞", "apple", sameTimeGroup[0].name);
eq("동일 시각이면 name 오름차순: zebra가 뒤", "zebra", sameTimeGroup[1].name);

eq("null records 및 pendings 처리", [], api.groupQaProjects(null, null));

console.log("\ngroupQaSessionsOfProject: 특정 프로젝트의 세션 그룹 집계");
const sessionRecs = [
  { cwd: ["D:\\repos\\Alpha"], session: "sess-1", status: "OK", timestamp: "2026-10-10 10:00:00" },
  { cwd: ["D:\\repos\\Alpha"], session: "sess-1", status: "ERROR", timestamp: "2026-10-11 10:00:00" },
  { cwd: ["D:\\repos\\Alpha"], session: "sess-2", status: "OK", timestamp: "2026-10-09 10:00:00" },
  { cwd: ["D:\\repos\\Alpha"], session: "", status: "OK", timestamp: "2026-10-08 10:00:00" },
  { cwd: ["D:\\repos\\Beta"], session: "sess-1", status: "OK", timestamp: "2026-10-12 10:00:00" }
];
const sessionPends = [
  { cwd: ["D:\\repos\\Alpha"], session: "sess-2", created: "2026-10-12 11:00:00" },
  { cwd: ["D:\\repos\\Beta"], session: "sess-2", created: "2026-10-13 11:00:00" }
];

const alphaSessions = api.groupQaSessionsOfProject(sessionRecs, sessionPends, "alpha");
eq("alpha 프로젝트의 세션 수 (sess-2, sess-1, __none__)", 3, alphaSessions.length);
eq("가장 최신(2026-10-12 11:00)인 sess-2 가 첫 번째", "sess-2", alphaSessions[0].name);
eq("sess-2 집계: total=1, pending=1, errors=0", { total: 1, pending: 1, errors: 0 }, {
  total: alphaSessions[0].total,
  pending: alphaSessions[0].pending,
  errors: alphaSessions[0].errors
});
eq("두 번째 최신인 sess-1", "sess-1", alphaSessions[1].name);
eq("sess-1 집계: total=2, pending=0, errors=1", { total: 2, pending: 0, errors: 1 }, {
  total: alphaSessions[1].total,
  pending: alphaSessions[1].pending,
  errors: alphaSessions[1].errors
});
eq("세션 없는 항목은 __none__", "__none__", alphaSessions[2].name);
eq("__none__ 집계: total=1, pending=0, errors=0", { total: 1, pending: 0, errors: 0 }, {
  total: alphaSessions[2].total,
  pending: alphaSessions[2].pending,
  errors: alphaSessions[2].errors
});

eq("존재하지 않는 프로젝트 키 조회 시 빈 배열", [], api.groupQaSessionsOfProject(sessionRecs, sessionPends, "nonexistent"));
eq("null 인자 처리", [], api.groupQaSessionsOfProject(null, null, "alpha"));

console.log("\nqaProjectKeyOfSession: 세션의 가장 최근 프로젝트 키 판별");
const keyRecs = [
  { cwd: ["D:\\repos\\OldProj"], session: "feature-login", timestamp: "2026-10-01 10:00:00" },
  { cwd: ["D:\\repos\\NewProj"], session: "feature-login", timestamp: "2026-10-10 10:00:00" },
  { cwd: ["D:\\repos\\OtherProj"], session: "feature-logout", timestamp: "2026-10-05 10:00:00" }
];
const keyPends = [
  { cwd: ["D:\\repos\\PendingProj"], session: "feature-login", created: "2026-10-15 10:00:00" }
];

eq("대기 작업이 더 최신인 세션의 프로젝트 키", "pendingproj", api.qaProjectKeyOfSession(keyRecs, keyPends, "feature-login"));
eq("완료 작업만 있는 세션의 프로젝트 키", "otherproj", api.qaProjectKeyOfSession(keyRecs, [], "feature-logout"));
eq("완료 작업 중 더 최신 것 선택", "newproj", api.qaProjectKeyOfSession(keyRecs, [], "feature-login"));
eq("존재하지 않는 세션은 빈 문자열", "", api.qaProjectKeyOfSession(keyRecs, keyPends, "no-such-session"));
eq("빈 세션 이름은 빈 문자열", "", api.qaProjectKeyOfSession(keyRecs, keyPends, ""));
eq("null 세션 이름은 빈 문자열", "", api.qaProjectKeyOfSession(keyRecs, keyPends, null));
eq("null records/pendings 처리", "", api.qaProjectKeyOfSession(null, null, "feature-login"));

console.log("\n통과 " + passed + " / 실패 " + failed);
process.exit(failed > 0 ? 1 : 0);
