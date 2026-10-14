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

const names = ["escapeHtml", "progressToolLabel", "summarizeProcess", "shortenPathsForCwd", "buildNarrationHtml", "buildProcessRowsHtml", "resolveProcessState",
  "hasHangul", "needsTranslation", "applyProcessTranslation", "procItemCount", "procTrViewOf", "procTrItemsFor", "buildTranslateToolsHtml",
  "browserTranslatorSupported", "protectCodeSpans", "restoreCodeSpans", "translateStepsWithBrowser"];
// resolveProcessState 는 옛 위임을 읽어 온 결과(processFetchCache)를 본다. 테스트에서는 이 객체를 직접 채운다.
// 상태 변수(옛 위임을 읽어 온 결과, agy 번역·브라우저 번역 결과, 보기 선택)는 테스트에서 직접 채운다.
const api = new Function("var processFetchCache = {}; var procTr = {}; var procTrB = {}; var procTrView = {};\n" + names.map(extractFunction).join("\n") +
  "\nreturn { summarizeProcess, shortenPathsForCwd, buildNarrationHtml, buildProcessRowsHtml, resolveProcessState, processFetchCache," +
  " hasHangul, needsTranslation, applyProcessTranslation, procItemCount, procTrViewOf, procTrItemsFor, buildTranslateToolsHtml," +
  " protectCodeSpans, restoreCodeSpans, translateStepsWithBrowser, procTr, procTrB, procTrView };")();

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

console.log("resolveProcessState: 카드의 한 줄과 과정 창이 함께 쓰는 상태");
const two = [S("run_command"), S("view_file")];
let st = api.resolveProcessState({ steps: two, convId: "c1" });
eq("기록에 단계가 있으면 그것과 요약", "도구 호출 2번 · 명령 실행 1 · 파일 읽기 1", st.summary);
ok("  읽어 올 것이 없다", st.steps === two && st.fetchId === "" && st.error === false);
st = api.resolveProcessState({ steps: [], live: true });
eq("진행 중인데 아직 호출이 없으면", "아직 도구를 부르지 않았습니다", st.summary);
ok("  빈 목록도 '단계가 있는 상태'(steps 가 빈 배열)", Array.isArray(st.steps) && st.steps.length === 0);
eq("대기 중인 작업", "아직 시작하지 않았습니다", api.resolveProcessState({ steps: null, waiting: true }).summary);
eq("대화 id 도 단계도 없으면", "과정이 기록되지 않았습니다", api.resolveProcessState({ steps: null }).summary);
st = api.resolveProcessState({ steps: null, convId: "c-old" });
ok("저장 안 된 옛 위임: 누르면 읽어 온다는 안내와 읽어 올 대화 id", st.summary.indexOf("누르면 agy 대화 기록에서 읽어 옵니다") >= 0 && st.fetchId === "c-old" && st.steps === null);
api.processFetchCache["c-old"] = { state: "loading" };
st = api.resolveProcessState({ steps: null, convId: "c-old" });
ok("읽는 중이면 안내만(다시 읽지 않는다)", st.summary === "agy 대화 기록에서 읽어 오는 중입니다" && st.fetchId === "");
api.processFetchCache["c-old"] = { state: "done", found: true, steps: two };
st = api.resolveProcessState({ steps: null, convId: "c-old" });
ok("읽어 온 단계가 있으면 그것을 쓴다", st.steps === two && st.summary.indexOf("도구 호출 2번") === 0 && st.fetchId === "");
api.processFetchCache["c-old"] = { state: "done", found: false, steps: [] };
eq("대화 기록이 정리된 경우", "agy 대화 기록이 남아 있지 않아 과정을 볼 수 없습니다", api.resolveProcessState({ steps: null, convId: "c-old" }).summary);
api.processFetchCache["c-old"] = { state: "error" };
st = api.resolveProcessState({ steps: null, convId: "c-old" });
ok("읽기 실패: error 표시와 다시 읽을 대화 id(창의 '다시 시도'가 쓴다)", st.error === true && st.fetchId === "c-old" && st.summary === "과정을 불러오지 못했습니다");
ok("기록에 단계가 있으면 읽어 온 결과보다 우선한다", api.resolveProcessState({ steps: two, convId: "c-old" }).steps === two);

console.log("resolveProcessState: 버튼의 단계 수(count)와 누를 수 있는지(openable)");
delete api.processFetchCache["c-old"];
let r2 = api.resolveProcessState({ steps: two });
ok("단계가 있으면 개수를 보이고 누를 수 있다", r2.count === 2 && r2.openable === true);
r2 = api.resolveProcessState({ steps: [], live: false });
ok("도구를 안 쓴 완료 작업은 0단계이고 누를 수 없다(볼 것이 없다)", r2.count === 0 && r2.openable === false);
r2 = api.resolveProcessState({ steps: [], live: true });
ok("진행 중이면 아직 0단계여도 누를 수 있다(곧 쌓인다)", r2.count === 0 && r2.openable === true);
r2 = api.resolveProcessState({ steps: null, waiting: true });
ok("대기 중인 작업은 누를 수 없다", r2.count === null && r2.openable === false);
r2 = api.resolveProcessState({ steps: null });
ok("과정이 기록되지 않았고 대화 id 도 없으면 누를 수 없다", r2.count === null && r2.openable === false);
r2 = api.resolveProcessState({ steps: null, convId: "c-new" });
ok("저장 안 된 옛 위임은 개수를 모르지만 누를 수 있다(누르면 읽어 온다)", r2.count === null && r2.openable === true);
api.processFetchCache["c-new"] = { state: "done", found: false, steps: [] };
ok("대화 기록이 정리됐으면 누를 수 없다", api.resolveProcessState({ steps: null, convId: "c-new" }).openable === false);
api.processFetchCache["c-new"] = { state: "error" };
ok("읽기에 실패했으면 다시 누를 수 있다", api.resolveProcessState({ steps: null, convId: "c-new" }).openable === true);
api.processFetchCache["c-new"] = { state: "done", found: true, steps: two };
r2 = api.resolveProcessState({ steps: null, convId: "c-new" });
ok("읽어 온 뒤에는 개수가 나온다", r2.count === 2 && r2.openable === true);

console.log("hasHangul / needsTranslation");
ok("한글이 있으면 true", api.hasHangul("폴더 확인") === true && api.hasHangul("Reading 파일") === true);
ok("영어·빈 글·null 은 false", api.hasHangul("Reading a.md") === false && api.hasHangul("") === false && api.hasHangul(null) === false);
ok("영어 라벨이 있으면 번역이 필요하다", api.needsTranslation([S("view_file", { label: "Reading a.md" })]) === true);
ok("영어 생각만 있어도, 영어 설명만 있어도", api.needsTranslation([S("a", { think: "Think." })]) === true && api.needsTranslation([S("a", { say: "I started." })]) === true);
ok("라벨·생각·설명이 모두 한글이거나 비어 있으면 필요 없다", api.needsTranslation([S("a", { label: "파일 읽기", think: "생각", say: "" }), S("b", {})]) === false);
ok("한글과 영어 단계가 섞이면 필요하다", api.needsTranslation([S("a", { label: "파일 읽기" }), S("b", { label: "Running tests" })]) === true);
ok("단계가 없거나 null 이면 필요 없다", api.needsTranslation([]) === false && api.needsTranslation(null) === false);

console.log("applyProcessTranslation: 번역본으로 글 바꾸기");
const orig = [S("view_file", { n: 1, label: "Reading a.md", think: "Read it." }), S("run_command", { n: 3, label: "Running tests", say: "I started." }), S("list_dir", { n: 5, label: "Listing" })];
const tr1 = api.applyProcessTranslation(orig, { "0": { label: "a.md 읽는 중", think: "읽는다." }, "1": { say: "시작했다." } });
ok("번역해 둔 칸만 바뀐다(0번 라벨·생각, 1번 설명)", tr1[0].label === "a.md 읽는 중" && tr1[0].think === "읽는다." && tr1[1].say === "시작했다.");
ok("  번역이 없는 칸은 원문 그대로(1번 라벨)", tr1[1].label === "Running tests");
ok("  번역이 없는 단계(2번)는 같은 객체", tr1[2] === orig[2]);
ok("  원본은 바뀌지 않는다", orig[0].label === "Reading a.md" && orig[1].say === "I started.");
ok("  번호·도구 같은 다른 칸은 그대로 복사된다", tr1[0].n === 1 && tr1[0].tool === "view_file");
ok("items 가 없으면 같은 목록", api.applyProcessTranslation(orig, null) === orig);
ok("빈 문자열 번역은 무시하고 원문을 둔다", api.applyProcessTranslation(orig, { "0": { label: "", think: "" } })[0].label === "Reading a.md");

console.log("buildTranslateToolsHtml: 번역 줄(agy 번역·브라우저 번역·보기 전환)");
const eng = [S("view_file", { label: "Reading a.md" })];
const kor = [S("view_file", { label: "파일 읽기" })];
function resetTr() {
  for (const m of [api.procTr, api.procTrB, api.procTrView]) for (const k of Object.keys(m)) delete m[k];
}
resetTr();
// 버튼의 글자를 꺼낸다(버튼에는 title 같은 속성이 더 붙어 있다)
const btn = (h, act) => { const m = h.match(new RegExp('data-act="' + act + '"[^>]*>([^<]*)<')); return m ? m[1] : null; };
eq("대화 id 가 없으면 줄이 없다", "", api.buildTranslateToolsHtml("", eng));
eq("단계가 없으면 줄이 없다", "", api.buildTranslateToolsHtml("c1", []));
eq("이미 한글이고 번역해 둔 것도 없으면 줄이 없다", "", api.buildTranslateToolsHtml("c1", kor));

// 이 테스트 환경(node)에는 Translator 가 없다: 브라우저 번역 버튼은 나오지 않는다
ok("Translator 가 없으면 브라우저 번역 버튼은 없고 agy 번역 버튼만", (function () {
  const h = api.buildTranslateToolsHtml("c1", eng);
  return btn(h, "translate") === "agy로 번역" && h.indexOf("translate-browser") === -1;
})());
globalThis.Translator = {};   // 지원하는 브라우저인 척
let th = api.buildTranslateToolsHtml("c1", eng);
ok("Translator 가 있으면 두 버튼(agy로 번역 / 브라우저로 번역)이 나란히", btn(th, "translate") === "agy로 번역" && btn(th, "translate-browser") === "브라우저로 번역");
ok("  아직 번역본이 없으니 보기 전환은 없다", th.indexOf('data-act="view"') === -1);
ok("  각 버튼에 비용·특징이 title 로 적혀 있다", th.indexOf("agy 사용량을 씁니다") >= 0 && th.indexOf("무료이고 빠르지만") >= 0);

api.procTr.c1 = { state: "running", message: "", items: {} };
th = api.buildTranslateToolsHtml("c1", eng);
ok("agy 번역 중이면 그 버튼만 눌 수 없고, 브라우저 버튼은 그대로 누를 수 있다", th.indexOf("agy 번역 중") >= 0 && th.indexOf("disabled") >= 0 && th.indexOf('data-act="translate-browser"') >= 0 && th.indexOf('data-act="translate">') === -1);
api.procTr.c1 = { state: "done", message: "", items: { "0": { label: "a.md 읽는 중" } }, model: "gemini-3.8-flash-low" };
th = api.buildTranslateToolsHtml("c1", eng);
ok("agy 번역이 끝났으면 보기 전환(원문 / agy 번역)이 생기고 agy 번역 버튼은 사라진다", th.indexOf('data-view="orig"') >= 0 && th.indexOf('data-view="agy"') >= 0 && th.indexOf('data-view="browser"') === -1 && th.indexOf('data-act="translate">') === -1);
ok("  지금 보는 것(agy 번역)이 눌린 모양(aria-pressed=true)", th.indexOf('data-view="agy" aria-pressed="true"') >= 0 && th.indexOf('data-view="orig" aria-pressed="false"') >= 0);
ok("  agy 번역을 보는 중이라는 안내와 모델 이름", th.indexOf("gemini-3.8-flash-low") >= 0 && th.indexOf("가 번역한 글입니다") >= 0);
ok("  브라우저로 번역하기는 아직 가능하다", btn(th, "translate-browser") === "브라우저로 번역");

api.procTrView.c1 = "orig";
th = api.buildTranslateToolsHtml("c1", eng);
ok("원문을 고르면 원문이 눌린 모양이고 번역 안내는 없다", th.indexOf('data-view="orig" aria-pressed="true"') >= 0 && th.indexOf("가 번역한 글입니다") === -1);
eq("원문을 고르면 보기는 orig", "orig", api.procTrViewOf("c1"));
delete api.procTrView.c1;

api.procTrB.c1 = { state: "done", message: "", items: { "0": { label: "브라우저 번역" } }, progress: null };
th = api.buildTranslateToolsHtml("c1", eng);
ok("브라우저 번역도 있으면 세 가지 보기(원문 / agy 번역 / 브라우저 번역)", th.indexOf('data-view="orig"') >= 0 && th.indexOf('data-view="agy"') >= 0 && th.indexOf('data-view="browser"') >= 0);
eq("둘 다 있고 고르지 않았으면 agy 번역을 먼저 보인다", "agy", api.procTrViewOf("c1"));
api.procTrView.c1 = "browser";
eq("브라우저 번역을 고르면 그것을 본다", "browser", api.procTrViewOf("c1"));
ok("  브라우저 번역 안내", api.buildTranslateToolsHtml("c1", eng).indexOf("브라우저 내장 번역 결과입니다") >= 0);
eq("  보기에 쓰는 글 묶음도 브라우저 것", "브라우저 번역", api.procTrItemsFor("c1", "browser")["0"].label);
eq("  원문 보기는 묶음이 없다", null, api.procTrItemsFor("c1", "orig"));
delete api.procTr.c1;
eq("고른 번역본이 없어졌으면 있는 것으로 물러난다(agy 번역 없음 -> 브라우저)", "browser", api.procTrViewOf("c1"));
api.procTrView.c1 = "agy";
eq("없는 번역본(agy)을 골라 둬도 있는 번역본으로 물러난다", "browser", api.procTrViewOf("c1"));
delete api.procTrView.c1; delete api.procTrB.c1;
eq("번역본이 하나도 없으면 원문", "orig", api.procTrViewOf("c1"));

api.procTrB.c1 = { state: "running", message: "", items: {}, progress: { done: 3, total: 20, download: -1 } };
th = api.buildTranslateToolsHtml("c1", eng);
ok("브라우저 번역 중이면 진행(3/20)을 보이고 그 버튼은 눌 수 없다", th.indexOf("브라우저 번역 중… 3/20") >= 0 && th.indexOf('data-act="translate-browser"') === -1);
api.procTrB.c1 = { state: "running", message: "", items: {}, progress: { done: 0, total: 0, download: 40 } };
ok("언어 팩을 내려받는 중이면 진행률", api.buildTranslateToolsHtml("c1", eng).indexOf("언어 팩 내려받는 중 40%") >= 0);
api.procTrB.c1 = { state: "error", message: "이 브라우저는 영어→한국어 번역을 지원하지 않습니다", items: {}, progress: null };
th = api.buildTranslateToolsHtml("c1", eng);
ok("브라우저 번역 실패: 이유와 '브라우저로 다시 시도'", th.indexOf("브라우저 번역 실패: 이 브라우저는 영어→한국어") >= 0 && btn(th, "translate-browser") === "브라우저로 다시 시도");
api.procTrB.c1 = { state: "done", message: "2칸은 번역을 쓸 수 없어 원문으로 두었습니다", items: { "0": { label: "x" } }, progress: null };
ok("일부 칸을 못 썼으면 그 사실을 알린다", api.buildTranslateToolsHtml("c1", eng).indexOf("2칸은 번역을 쓸 수 없어 원문으로 두었습니다.") >= 0);
delete api.procTrB.c1;

api.procTr.c1 = { state: "none", message: "", items: { "0": { label: "a.md 읽는 중" } }, model: "m" };
th = api.buildTranslateToolsHtml("c1", [S("view_file", { label: "Reading a.md" }), S("run_command", { label: "Running tests" })]);
ok("새 단계가 생겨 일부만 번역됐으면 'agy로 새 단계 번역'", btn(th, "translate") === "agy로 새 단계 번역");
api.procTr.c1 = { state: "error", message: "agy 번역 호출이 170 초를 넘겨 중단했습니다", items: {}, model: "" };
th = api.buildTranslateToolsHtml("c1", eng);
ok("agy 번역 실패: 이유와 'agy로 다시 시도'", th.indexOf("agy 번역 실패: agy 번역 호출이 170 초") >= 0 && btn(th, "translate") === "agy로 다시 시도");
api.procTr.c1 = { state: "unavailable", message: "agy 대화 기록이 남아 있지 않아 번역할 수 없습니다", items: {} };
th = api.buildTranslateToolsHtml("c1", eng);
ok("agy 로 번역할 수 없으면 그 버튼 없이 이유만(브라우저 번역은 가능)", th.indexOf("남아 있지 않아") >= 0 && th.indexOf('data-act="translate">') === -1 && th.indexOf("translate-browser") >= 0);
ok("서버가 준 문구는 HTML 이스케이프된다", (api.procTr.c1 = { state: "error", message: "<img src=x onerror=1>", items: {} }, api.buildTranslateToolsHtml("c1", eng).indexOf("<img") === -1));
resetTr();
delete globalThis.Translator;

console.log("needsTranslation(steps, items): 이미 번역한 칸은 뺀다");
ok("items 에 라벨이 있으면 그 칸은 필요 없다", api.needsTranslation([S("a", { label: "Reading" })], { "0": { label: "읽는 중" } }) === false);
ok("다른 칸이 남았으면 필요하다(생각)", api.needsTranslation([S("a", { label: "Reading", think: "Think." })], { "0": { label: "읽는 중" } }) === true);
ok("items 를 안 주면 전부 대상", api.needsTranslation([S("a", { label: "Reading" })]) === true);

console.log("protectCodeSpans / restoreCodeSpans: 코드는 번역에서 지킨다");
const pr = api.protectCodeSpans("Create `lru_ttl.py` and `test_lru_ttl.py` now. No code here.");
eq("백틱 안의 코드는 자리표시자로 바뀐다", "Create XQ1X and XQ2X now. No code here.", pr.text);
eq("  코드는 따로 보관(백틱 포함)", "`lru_ttl.py`|`test_lru_ttl.py`", pr.codes.join("|"));
eq("번역 뒤 되돌리면 원래 코드가 들어간다(어순이 바뀌어도)", "지금 `test_lru_ttl.py` 와 `lru_ttl.py` 를 만든다.", api.restoreCodeSpans("지금 XQ2X 와 XQ1X 를 만든다.", pr.codes));
eq("자리표시자가 하나라도 없으면 null(번역을 쓰지 않는다)", null, api.restoreCodeSpans("지금 XQ1X 만 만든다.", pr.codes));
eq("모델이 만든 적 없는 자리표시자가 있으면 null", null, api.restoreCodeSpans("XQ1X XQ2X XQ3X", pr.codes));
eq("코드가 없는 글은 그대로", "코드 없음", api.restoreCodeSpans("코드 없음", []));
eq("코드 안에 $ 가 있어도 그대로 되돌린다", "값은 `$&` 이다", api.restoreCodeSpans("값은 XQ1X 이다", ["`$&`"]));
eq("백틱이 없는 글은 보호할 것이 없다", "plain text", api.protectCodeSpans("plain text").text);
eq("null 도 오류 없이 빈 글", "", api.protectCodeSpans(null).text);
eq("줄바꿈이 낀 백틱은 코드로 보지 않는다", "a `b\nc` d", api.protectCodeSpans("a `b\nc` d").text);

console.log("translateStepsWithBrowser: 가짜 번역기로");

console.log("HTML 이스케이프");
const evil = api.buildProcessRowsHtml([S("run_command", { detail: 'echo "<script>alert(1)</script>" & dir', label: "<b>x</b>", think: 'a"b' })]);
ok("<script> 가 태그로 살아 있지 않다", evil.indexOf("<script>") === -1);
ok("이스케이프된 글자로 보인다", evil.indexOf("&lt;script&gt;") >= 0);
ok("title 속성이 따옴표로 깨지지 않는다", (evil.match(/"/g) || []).length % 2 === 0);
eq("빈 목록은 빈 <ol>", '<ol class="proc-list"></ol>', api.buildProcessRowsHtml([]));

(async () => {
  const fake = { translate: async (t) => "KO:" + t };
  const steps = [
    S("view_file", { label: "Reading `a.md`", think: "Open `a.md` first." }),
    S("run_command", { label: "파일 읽기", think: "" }),
    S("write_to_file", { say: "Done." })
  ];
  const seen = [];
  let res = await api.translateStepsWithBrowser(steps, {}, fake, (d, t) => seen.push(d + "/" + t));
  eq("한글이 아닌 3칸만 번역(라벨·생각·설명)", 3, res.total);
  eq("  실패 없음", 0, res.failed);
  eq("  코드(백틱)는 원문 그대로 들어간다", "KO:Reading `a.md`|KO:Open `a.md` first.", res.items["0"].label + "|" + res.items["0"].think);
  eq("  설명은 2번째 단계 칸에", "KO:Done.", res.items["2"].say);
  eq("  이미 한글인 단계(1번)는 건드리지 않는다", false, Object.prototype.hasOwnProperty.call(res.items, "1"));
  eq("  진행은 칸마다 한 번씩 순서대로", "1/3,2/3,3/3", seen.join(","));

  const existing = { "0": { label: "이미 번역함" } };
  const calls = [];
  const spy = { translate: async (t) => { calls.push(t); return "KO:" + t; } };
  res = await api.translateStepsWithBrowser(steps, existing, spy, null);
  eq("이미 번역한 칸은 다시 번역하지 않는다(2칸만 번역기로)", 2, calls.length);
  eq("  이미 번역한 값은 그대로", "이미 번역함", res.items["0"].label);
  eq("  넘겨 준 existing 객체는 바뀌지 않는다", "이미 번역함|undefined", existing["0"].label + "|" + existing["0"].think);
  eq("  새로 번역한 칸이 합쳐진다", "KO:Open `a.md` first.", res.items["0"].think);

  const lossy = { translate: async (t) => (t.indexOf("XQ") >= 0 ? "코드를 잃어버린 번역" : "KO:" + t) };
  res = await api.translateStepsWithBrowser(steps, {}, lossy, null);
  eq("코드가 사라진 번역은 쓰지 않는다(2칸 실패, 코드 없는 설명 1칸은 성공)", "2/3", res.failed + "/" + res.total);
  eq("  쓰지 못한 칸은 items 에 없다(원문으로 남는다)", false, Boolean(res.items["0"]));
  eq("  성공한 칸은 들어간다", "KO:Done.", res.items["2"].say);

  const boom = { translate: async () => { throw new Error("번역기 오류"); } };
  res = await api.translateStepsWithBrowser(steps, {}, boom, null);
  eq("번역기가 계속 오류를 내면 전부 실패로 센다", "3/3", res.failed + "/" + res.total);
  eq("  items 는 비어 있다", 0, Object.keys(res.items).length);

  const empty = { translate: async () => "   " };
  res = await api.translateStepsWithBrowser(steps, {}, empty, null);
  eq("빈 번역은 실패로 센다", 3, res.failed);

  res = await api.translateStepsWithBrowser([S("a", { label: "파일 읽기" })], {}, fake, null);
  eq("번역할 칸이 없으면 번역기를 부르지 않고 0칸", "0/0", res.failed + "/" + res.total);

  const sync = { translate: (t) => "KO:" + t };   // Promise 를 안 돌려주는 번역기도 받는다
  res = await api.translateStepsWithBrowser([S("a", { label: "Reading" })], {}, sync, null);
  eq("동기 번역기도 된다", "KO:Reading", res.items["0"].label);
})().then(() => {
  console.log("\n통과 " + passed + " / 실패 " + failed);
  process.exit(failed > 0 ? 1 : 0);
});
