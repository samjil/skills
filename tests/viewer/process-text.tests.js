// 위임 카드의 "과정" 구역(summarizeProcess, shortenPathsForCwd, buildProcessRowsHtml) 테스트.
//   node tests/viewer/process-text.tests.js
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

const names = ["escapeHtml", "progressToolLabel", "summarizeProcess", "shortenPathsForCwd", "buildNarrationHtml", "buildProcessRowsHtml"];
const api = new Function(names.map(extractFunction).join("\n") + "\nreturn { summarizeProcess, shortenPathsForCwd, buildNarrationHtml, buildProcessRowsHtml };")();

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  if (expected === actual) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\n        기대: " + JSON.stringify(expected) + "\n        실제: " + JSON.stringify(actual)); }
}
function ok(name, cond) { eq(name, true, Boolean(cond)); }
const text = (html) => html.replace(/<[^>]*>/g, "");

const S = (tool, extra) => Object.assign({ n: 1, at: "16:48:57", tool: tool, detail: "", label: "", think: "" }, extra || {});

console.log("summarizeProcess: 한 줄 요약");
eq("도구를 안 쓴 완료 작업", "도구를 쓰지 않고 바로 답했습니다", api.summarizeProcess([], false));
eq("null 도 같은 문구", "도구를 쓰지 않고 바로 답했습니다", api.summarizeProcess(null, false));
eq("진행 중인데 아직 호출이 없으면", "아직 도구를 부르지 않았습니다", api.summarizeProcess([], true));
eq("호출 횟수와 도구별 개수(많은 순)", "도구 호출 6번 · 명령 실행 3 · 파일 읽기 2 · 파일 쓰기 1",
  api.summarizeProcess([S("run_command"), S("view_file"), S("run_command"), S("write_to_file"), S("view_file"), S("run_command")], false));
eq("3종을 넘으면 '외 N종'", "도구 호출 5번 · 명령 실행 2 · 파일 읽기 1 · 파일 쓰기 1 외 1종",
  api.summarizeProcess([S("run_command"), S("run_command"), S("view_file"), S("write_to_file"), S("list_dir")], false));
eq("모르는 도구는 이름 그대로", "도구 호출 1번 · brand_new_tool 1", api.summarizeProcess([S("brand_new_tool")], false));
eq("도구 이름이 비어 있으면 '기타'", "도구 호출 1번 · 기타 1", api.summarizeProcess([S("")], false));
eq("개수가 같으면 먼저 나온 도구가 앞", "도구 호출 2번 · 파일 읽기 1 · 명령 실행 1", api.summarizeProcess([S("view_file"), S("run_command")], false));

console.log("buildProcessRowsHtml: 과정 목록");
const rows = api.buildProcessRowsHtml([
  S("run_command", { n: 17, at: "16:48:57", detail: "Get-Location", label: "Checking target directory", think: "폴더를 확인한다" }),
  S("run_command", { n: 19, at: "16:49:51", detail: "npm run build", label: "Building", bg: true }),
  S("view_file", { n: 21, detail: "C:\\a.md (1~45행)" })
]);
ok("<ol class=proc-list> 로 감싼다", rows.indexOf('<ol class="proc-list">') === 0);
eq("행이 3개", 3, (rows.match(/<li class="proc-row"/g) || []).length);
// 칸(span)마다 따로 놓이는 값이라 칸 사이에 공백을 두고 태그를 벗겨 "화면에 보이는 순서"를 비교한다
const firstRow = "<li" + rows.split("<li")[1];
eq("첫 행에 보이는 글: 번호, 시각, 한글 도구, 대상, 영어 라벨, 생각", "17 16:48:57 명령 실행 Get-Location · Checking target directory 생각 폴더를 확인한다",
  text(firstRow.replace(/<\/span><span/g, "</span> <span")).replace(/\s+/g, " ").trim());
ok("대상은 고정폭 요소(proc-detail)", rows.indexOf('<span class="proc-detail">Get-Location</span>') >= 0);
ok("영어 라벨은 흐린 요소(proc-label)", rows.indexOf('<span class="proc-label">· Checking target directory</span>') >= 0);
ok("마우스를 올리면 도구·대상·라벨이 보인다", rows.indexOf("도구: run_command") >= 0 && rows.indexOf("대상: Get-Location") >= 0 &&
  rows.indexOf("agy 가 붙인 설명: Checking target directory") >= 0);
ok("생각은 마우스를 올리지 않아도 보인다(proc-think)", rows.indexOf('<span class="proc-think"><b>생각</b> 폴더를 확인한다</span>') >= 0);
ok("백그라운드 명령 표시", rows.indexOf("명령 실행 (백그라운드)") >= 0);
ok("라벨이 없으면 라벨 요소를 만들지 않는다", rows.split("<li")[3].indexOf("proc-label") === -1);
ok("401개가 아니라 3개이므로 '400번까지' 안내는 없다", rows.indexOf("proc-note") === -1);

const many = [];
for (let i = 0; i < 400; i++) many.push(S("view_file", { n: i }));
ok("400개면 '처음 400번까지만 남깁니다' 안내", api.buildProcessRowsHtml(many).indexOf("처음 400번까지만 남깁니다") >= 0);

console.log("shortenPathsForCwd: 작업 폴더 아래 경로를 상대 경로로");
const W = "C:\\work\\proj";
eq("폴더 아래 파일은 폴더 이름을 뺀다", "src\\a.py", api.shortenPathsForCwd("C:\\work\\proj\\src\\a.py", W));
eq("읽은 줄 범위 꼬리표는 그대로", "spec.md (1~45행)", api.shortenPathsForCwd("C:\\work\\proj\\spec.md (1~45행)", W));
eq("슬래시와 역슬래시를 가리지 않는다", "src/a.py", api.shortenPathsForCwd("C:/work/proj/src/a.py", W));
eq("대소문자가 달라도 같은 폴더(윈도우)", "a.py", api.shortenPathsForCwd("c:\\WORK\\Proj\\a.py", W));
eq("@cwd 끝에 구분자가 붙어 있어도 같다", "a.py", api.shortenPathsForCwd("C:\\work\\proj\\a.py", W + "\\"));
eq("폴더 자체는 '.'", ".", api.shortenPathsForCwd("C:\\work\\proj", W));
eq("폴더 자체(끝에 구분자)도 '.'", ".", api.shortenPathsForCwd("C:\\work\\proj\\", W));
eq("검색 줄: 질의와 폴더가 함께 있을 때", "TODO (src)", api.shortenPathsForCwd("TODO (C:\\work\\proj\\src)", W));
eq("검색 줄: 폴더 자체는 '.'", "*.py (.)", api.shortenPathsForCwd("*.py (C:\\work\\proj)", W));
eq("명령 안의 경로도 줄인다", "python src\\a.py --out \"out\\r.txt\"", api.shortenPathsForCwd("python C:\\work\\proj\\src\\a.py --out \"C:\\work\\proj\\out\\r.txt\"", W));
eq("이름만 비슷한 다른 폴더는 건드리지 않는다", "C:\\work\\proj2\\a.py", api.shortenPathsForCwd("C:\\work\\proj2\\a.py", W));
eq("폴더 밖 경로는 그대로", "D:\\other\\a.py", api.shortenPathsForCwd("D:\\other\\a.py", W));
eq("글 중간에 붙은 경로는 건드리지 않는다", "xC:\\work\\proj\\a.py", api.shortenPathsForCwd("xC:\\work\\proj\\a.py", W));
eq("작업 폴더가 없으면 그대로", "C:\\work\\proj\\a.py", api.shortenPathsForCwd("C:\\work\\proj\\a.py", ""));
eq("작업 폴더가 null 이어도 그대로", "C:\\work\\proj\\a.py", api.shortenPathsForCwd("C:\\work\\proj\\a.py", null));
eq("대상이 비어 있으면 빈 글", "", api.shortenPathsForCwd("", W));
eq("정규식 특수문자가 든 폴더도 안전하다", "a.py", api.shortenPathsForCwd("C:\\my (app)+v1.0\\a.py", "C:\\my (app)+v1.0"));
eq("리눅스식 폴더", "src/a.py", api.shortenPathsForCwd("/home/u/proj/src/a.py", "/home/u/proj"));

console.log("buildProcessRowsHtml: 작업 폴더를 주면 경로가 줄어 보인다");
const relRows = api.buildProcessRowsHtml([S("view_file", { n: 1, detail: "C:\\work\\proj\\spec.md (1~45행)", label: "Reading spec" })], W);
ok("목록에는 상대 경로", relRows.indexOf('<span class="proc-detail">spec.md (1~45행)</span>') >= 0);
ok("마우스를 올리면 전체 경로와 작업 폴더가 보인다", relRows.indexOf("대상: C:\\work\\proj\\spec.md (1~45행)") >= 0 && relRows.indexOf("작업 폴더(@cwd): C:\\work\\proj") >= 0);
const noCwdRows = api.buildProcessRowsHtml([S("view_file", { n: 1, detail: "C:\\work\\proj\\spec.md" })]);
ok("작업 폴더가 없으면 전체 경로 그대로", noCwdRows.indexOf('<span class="proc-detail">C:\\work\\proj\\spec.md</span>') >= 0 && noCwdRows.indexOf("작업 폴더(@cwd)") === -1);
const outRows = api.buildProcessRowsHtml([S("run_command", { n: 1, detail: "Get-Location" })], W);
ok("줄일 게 없는 대상에는 '작업 폴더' 안내를 붙이지 않는다", outRows.indexOf("작업 폴더(@cwd)") === -1);

console.log("agy 가 적은 말: 설명(say)과 생각(think)을 단계마다 보인다");
const narr = api.buildProcessRowsHtml([
  S("run_command", { n: 1, detail: "npm run build", say: "I have launched `npm run build` and will wait for it to finish.", think: "Build first, then lint." }),
  S("view_file", { n: 3, detail: "a.md", think: "Only a thought." }),
  S("view_file", { n: 5, detail: "b.md", say: "Only a note." }),
  S("view_file", { n: 7, detail: "c.md" })
]);
const nrows = narr.split("<li").slice(1);
ok("설명과 생각이 둘 다 있으면 설명, 생각 순서", nrows[0].indexOf('<span class="proc-say"><b>설명</b> I have launched') >= 0 &&
  nrows[0].indexOf("proc-say") < nrows[0].indexOf("proc-think") && nrows[0].indexOf('<span class="proc-think"><b>생각</b> Build first, then lint.</span>') >= 0);
ok("생각만 있는 단계에는 설명 요소가 없다", nrows[1].indexOf("proc-think") >= 0 && nrows[1].indexOf("proc-say") === -1);
ok("설명만 있는 단계에는 생각 요소가 없다", nrows[2].indexOf("proc-say") >= 0 && nrows[2].indexOf("proc-think") === -1);
ok("둘 다 없으면 둘 다 만들지 않는다", nrows[3].indexOf("proc-say") === -1 && nrows[3].indexOf("proc-think") === -1);
ok("말은 도구·대상 칸과 같은 칸(proc-text) 안, 대상 뒤에 놓인다", nrows[0].indexOf("proc-detail") < nrows[0].indexOf("proc-say") && nrows[0].lastIndexOf("</span></li>") > nrows[0].indexOf("proc-think"));
eq("접두어를 바꿔 진행 카드용 클래스를 만든다", '<span class="pg-think"><b>생각</b> x</span>', api.buildNarrationHtml("pg", "", "x"));
eq("둘 다 비면 빈 글", "", api.buildNarrationHtml("pg", "", ""));
ok("말의 HTML 은 이스케이프된다", api.buildNarrationHtml("proc", "<img src=x onerror=alert(1)>", "a&b").indexOf("<img") === -1 && api.buildNarrationHtml("proc", "", "a&b").indexOf("a&amp;b") >= 0);

console.log("HTML 이스케이프");
const evil = api.buildProcessRowsHtml([S("run_command", { detail: 'echo "<script>alert(1)</script>" & dir', label: "<b>x</b>", think: 'a"b' })]);
ok("<script> 가 태그로 살아 있지 않다", evil.indexOf("<script>") === -1);
ok("이스케이프된 글자로 보인다", evil.indexOf("&lt;script&gt;") >= 0);
ok("title 속성이 따옴표로 깨지지 않는다", (evil.match(/"/g) || []).length % 2 === 0);
eq("빈 목록은 빈 <ol>", '<ol class="proc-list"></ol>', api.buildProcessRowsHtml([]));

console.log("\n통과 " + passed + " / 실패 " + failed);
process.exit(failed > 0 ? 1 : 0);
