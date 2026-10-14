// 화면의 @cwd 여러 폴더 처리(cwdListOf, leadingCwds, extractImagesFromText, shortenPathsForCwd, 과정 창 옵션) 테스트.
//   node tests/viewer/cwd-list.tests.js
// runtime/viewer/web/app.js 에서 함수 원문을 꺼내 그대로 실행합니다(복사본이 아니라서 앱 코드와 어긋나지 않음).
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

const names = ["escapeHtml", "progressToolLabel", "buildNarrationHtml", "cwdListOf", "leadingCwds", "extractImagesFromText",
  "shortenPathsForCwd", "buildProcessRowsHtml", "recordProcessOpts", "pendingProcessOpts"];
const api = new Function(names.map(extractFunction).join("\n") +
  "\nreturn { cwdListOf, leadingCwds, extractImagesFromText, shortenPathsForCwd, buildProcessRowsHtml, recordProcessOpts, pendingProcessOpts };")();

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\n        기대: " + e + "\n        실제: " + a); }
}
function ok(name, cond) { eq(name, true, Boolean(cond)); }

console.log("cwdListOf: 문자열·배열·없음을 폴더 배열로");
eq("문자열 하나(예전 서버·예전 기록)", ["D:\\a"], api.cwdListOf("D:\\a"));
eq("배열", ["D:\\a", "D:\\b"], api.cwdListOf(["D:\\a", "D:\\b"]));
eq("null·undefined·빈 문자열·빈 배열은 빈 배열", [[], [], [], []], [api.cwdListOf(null), api.cwdListOf(undefined), api.cwdListOf(""), api.cwdListOf([])]);
eq("앞뒤 공백을 지우고 빈 값은 뺀다", ["D:\\a", "D:\\b"], api.cwdListOf(["  D:\\a  ", "", "   ", null, "D:\\b"]));
eq("중복은 대소문자와 끝의 \\ 또는 / 를 무시하고 처음 것만", ["D:\\Repo", "D:\\other"], api.cwdListOf(["D:\\Repo", "d:\\repo\\", "D:\\REPO/", "D:\\other"]));
eq("순서는 그대로", ["D:\\z", "D:\\a"], api.cwdListOf(["D:\\z", "D:\\a"]));

console.log("leadingCwds / extractImagesFromText: 질문 맨 위의 @cwd 줄들");
eq("@cwd 두 줄", ["D:\\a\\repo", "D:\\b\\docs"], api.leadingCwds("@cwd: D:\\a\\repo\n@cwd: D:\\b\\docs\n@model: gemini-3.8-flash-medium\n본문"));
eq("다른 지시어 사이에 끼어 있어도, 빈 줄과 CRLF 가 있어도", ["D:\\a", "D:\\b"], api.leadingCwds("@cwd: D:\\a\r\n\r\n@session: s\r\n@cwd: D:\\b\r\n본문"));
eq("BOM 이 맨 앞에 있어도", ["D:\\a"], api.leadingCwds("\ufeff@cwd: D:\\a\n본문"));
eq("본문이 시작된 뒤의 @cwd 는 읽지 않는다", [], api.leadingCwds("첫 줄은 본문\n@cwd: D:\\late"));
const info = api.extractImagesFromText("@cwd: D:\\a\\repo\n@cwd: D:\\b\\docs\n`shot.png` 를 보세요");
eq("extractImagesFromText: cwds 는 목록, cwd 는 첫 번째", ["D:\\a\\repo", "D:\\b\\docs", "D:\\a\\repo"], [...info.cwds, info.cwd]);
eq("  이미지도 여전히 찾는다", ["shot.png"], info.images);
const one = api.extractImagesFromText("@cwd: D:\\only\n질문");
eq("한 줄짜리(예전 형식)는 폴더 하나, cwd 도 그 폴더", ["D:\\only", "D:\\only"], [...one.cwds, one.cwd]);
const none = api.extractImagesFromText("폴더 없는 질문");
eq("@cwd 가 없으면 cwd 는 빈 글, cwds 는 빈 배열", ["", 0], [none.cwd, none.cwds.length]);
const mid = api.extractImagesFromText("앞에 글이 있고\n@cwd: D:\\mid\n끝");
eq("예전 동작 호환: 본문 중간의 @cwd 한 줄은 읽는다", ["D:\\mid"], mid.cwds);
eq("빈 글은 빈 결과", { cwd: "", cwds: [], images: [] }, api.extractImagesFromText(""));

console.log("shortenPathsForCwd: 폴더가 여러 개면 폴더 이름부터");
const two = ["C:\\a\\repo", "D:\\b\\docs"];
eq("첫 폴더 아래 파일은 폴더 이름부터", "repo\\src\\x.cs", api.shortenPathsForCwd("C:\\a\\repo\\src\\x.cs", two));
eq("둘째 폴더 아래 파일도", "docs\\ops.md (1~20행)", api.shortenPathsForCwd("D:\\b\\docs\\ops.md (1~20행)", two));
eq("폴더 자체는 폴더 이름", "repo", api.shortenPathsForCwd("C:\\a\\repo", two));
eq("두 폴더가 한 명령에 함께 나와도 각각 줄인다", "copy repo\\a.txt docs\\a.txt", api.shortenPathsForCwd("copy C:\\a\\repo\\a.txt D:\\b\\docs\\a.txt", two));
eq("폴더 밖 경로는 그대로", "E:\\x\\y.py", api.shortenPathsForCwd("E:\\x\\y.py", two));
eq("이름만 비슷한 폴더는 건드리지 않는다", "C:\\a\\repo2\\x", api.shortenPathsForCwd("C:\\a\\repo2\\x", two));
eq("폴더가 하나면 예전처럼 폴더 이름까지 뺀다(문자열)", "src\\a.py", api.shortenPathsForCwd("C:\\w\\p\\src\\a.py", "C:\\w\\p"));
eq("  배열 하나도 같다", "src\\a.py", api.shortenPathsForCwd("C:\\w\\p\\src\\a.py", ["C:\\w\\p"]));
eq("  폴더 자체는 .", ".", api.shortenPathsForCwd("C:\\w\\p", ["C:\\w\\p"]));
eq("한 폴더가 다른 폴더 안에 있으면 더 구체적인 폴더 기준으로 줄인다", "sub\\f.py", api.shortenPathsForCwd("D:\\a\\sub\\f.py", ["D:\\a", "D:\\a\\sub"]));
eq("폴더 목록이 비었으면 그대로", "C:\\x\\y", api.shortenPathsForCwd("C:\\x\\y", []));
eq("대소문자·슬래시 방향이 달라도", "repo/src/x.cs", api.shortenPathsForCwd("c:/A/REPO/src/x.cs", two));

console.log("과정 목록 툴팁과 과정 창 옵션");
const rows = api.buildProcessRowsHtml([{ n: 1, at: "10:00:00", tool: "view_file", detail: "C:\\a\\repo\\src\\x.cs", label: "", think: "" }], two);
ok("여러 폴더: 목록에는 폴더 이름부터, title 에는 전체 경로와 폴더 목록", rows.indexOf('<span class="proc-detail">repo\\src\\x.cs</span>') >= 0 &&
  rows.indexOf("대상: C:\\a\\repo\\src\\x.cs") >= 0 && rows.indexOf("작업 폴더(@cwd): C:\\a\\repo, D:\\b\\docs") >= 0 && rows.indexOf("폴더 이름부터") >= 0);
const rows1 = api.buildProcessRowsHtml([{ n: 1, at: "", tool: "view_file", detail: "C:\\w\\p\\a.py", label: "", think: "" }], "C:\\w\\p");
ok("한 폴더(문자열): 예전과 같은 안내", rows1.indexOf('<span class="proc-detail">a.py</span>') >= 0 && rows1.indexOf("이 폴더 아래 경로만 줄여 보입니다") >= 0);
eq("recordProcessOpts: 질문 맨 위의 @cwd 줄들을 폴더 배열로", ["D:\\a", "D:\\b"], api.recordProcessOpts({ process: [], session_id: "c", question: "@cwd: D:\\a\n@cwd: D:\\b\n질문" }).cwd);
eq("  폴더를 직접 넘기면 그대로", ["D:\\x"], api.recordProcessOpts({ process: null, question: "@cwd: D:\\a\n질문" }, ["D:\\x"]).cwd);
const pend = (p) => api.pendingProcessOpts(Object.assign({ state: "processing", question: "" }, p)).cwd;
eq("pendingProcessOpts: 서버가 폴더 배열을 주면 그것을", ["D:\\a", "D:\\b"], pend({ cwd: ["D:\\a", "D:\\b"] }));
eq("  옛 서버의 문자열 하나도 읽는다", ["D:\\old"], pend({ cwd: "D:\\old" }));
eq("  서버가 빈 배열이면 질문 맨 위의 @cwd 로 물러난다([] 는 참이라 빠지기 쉬운 곳)", ["D:\\fromq"], pend({ cwd: [], question: "@cwd: D:\\fromq\n질문" }));
eq("  서버 값도 질문도 없으면 빈 배열", [], pend({ cwd: "" }));

console.log("\n통과 " + passed + " / 실패 " + failed);
process.exit(failed > 0 ? 1 : 0);
