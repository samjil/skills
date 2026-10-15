// 위임 카드의 질문/답변 미리보기 텍스트 정리(cleanTextForPreview, extractQuestionKeyword, extractAnswerKeyword) 테스트.
//   node tests/viewer/preview-text.tests.js
// runtime/viewer/web/app.js 에서 함수 원문을 꺼내 그대로 실행합니다(복사본이 아니라서 앱 코드와 어긋나지 않음).
// 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다.

"use strict";
const fs = require("fs");
const path = require("path");

const appJs = fs.readFileSync(path.join(__dirname, "..", "..", "runtime", "viewer", "web", "app.js"), "utf8");

// "function NAME(" 부터 짝이 맞는 닫는 중괄호까지를 꺼낸다(문자열/정규식 안의 중괄호는 없다고 가정: 이 함수들에는 없음).
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

global.window = {
  marked: { parse: s => s },
  katex: { renderToString: math => `<katex>${math}</katex>` },
  DOMPurify: { sanitize: s => s }
};

const names = ["stripEmphasis", "cleanTextForPreview", "extractQuestionKeyword", "extractAnswerKeyword", "claudeTreeKeyOf", "pendingKeyOf", "renderMarkdownWithMath"];
const api = new Function(names.map(extractFunction).join("\n") + "\nreturn { stripEmphasis, cleanTextForPreview, extractQuestionKeyword, extractAnswerKeyword, claudeTreeKeyOf, pendingKeyOf, renderMarkdownWithMath };")();

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  if (expected === actual) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\n        기대: " + JSON.stringify(expected) + "\n        실제: " + JSON.stringify(actual)); }
}
function ok(name, cond) { eq(name, true, Boolean(cond)); }

const clean = api.cleanTextForPreview;

console.log("cleanTextForPreview: 글자로 쓰인 _ * ~ 는 지키고 마크다운 표시만 벗긴다");
eq("snake_case 식별자(merge_intervals)를 그대로 둔다", "Python 함수 merge_intervals 에는 버그가 있다", clean("Python 함수 merge_intervals 에는 버그가 있다"));
eq("여러 밑줄 식별자도 그대로", "snake_case_name 과 my_var_2", clean("snake_case_name 과 my_var_2"));
eq("이중 밑줄 식별자(__init__.py)는 식별자로 보고 둔다", "__init__.py 파일", clean("__init__.py 파일"));
eq("~ 로 시작하는 경로(~/.samjil)를 그대로 둔다", "~/.samjil 폴더", clean("~/.samjil 폴더"));
eq("글롭의 * (src/*.ts)를 그대로 둔다", "src/*.ts 와 lib/*.js", clean("src/*.ts 와 lib/*.js"));
eq("곱셈의 * (2 * 3 * 4)를 그대로 둔다", "2 * 3 * 4", clean("2 * 3 * 4"));
eq("**굵게**, *기울임*, _기울임_, ~~취소~~ 표시는 벗긴다", "굵게 기울임 기울임 취소", clean("**굵게** *기울임* _기울임_ ~~취소~~"));
eq("한글 조사가 붙은 **굵게**를 벗긴다", "굵게를 확인", clean("**굵게**를 확인"));
eq("인라인 코드는 백틱만 벗긴다", "merge_intervals 호출", clean("`merge_intervals` 호출"));
eq("인라인 코드 안의 * 는 강조로 보지 않는다", "a*b*c 코드", clean("`a*b*c` 코드"));
eq("인라인 코드 바깥의 강조는 벗긴다", "a*b*c 와 굵게", clean("`a*b*c` 와 **굵게**"));
eq("짝 없는 백틱은 지운다", "its 확인", clean("it`s 확인"));
eq("제목 표시(#)를 벗긴다", "제목", clean("# 제목"));
eq("링크는 글자만 남긴다", "링크 와 태그", clean("[링크](http://x.y) 와 <b>태그</b>"));
eq("공백을 하나로 줄인다", "가 나 다", clean("  가   나\t다  "));
eq("빈 값", "", clean(""));
eq("null", "", clean(null));
eq("밑줄 기울임 뒤에 글자가 붙으면 식별자로 본다(_id 와 _name)", "_id 와 _name 필드", clean("_id 와 _name 필드"));

console.log("extractQuestionKeyword: 지시어 줄은 질문이 아니다");
const q1 = api.extractQuestionKeyword("@model: gemini-3.8-flash-medium\n아래 Python 함수 merge_intervals 에는 버그가 있다. 명세와 코드를 읽고 버그를 찾아 고쳐 줘.\n\n명세:");
ok("@model 줄을 건너뛴다", q1.indexOf("@model") === -1 && q1.indexOf("gemini") === -1);
ok("본문의 merge_intervals 가 밑줄 그대로 보인다", q1.indexOf("merge_intervals") >= 0);
eq("본문 첫 줄로 시작한다", "아래 Python 함수 merge_intervals 에는 버그가 있다. 명세와 코드를 읽고 버그를 찾아 고쳐 줘.", q1.slice(0, 66));

const q2 = api.extractQuestionKeyword("@cwd: C:\\proj\n@session: 작업-1\n@model: gemini-3.8-flash-low\n파일 목록을 정리해 줘");
eq("@cwd, @session, @model 이 섞여 있어도 모두 건너뛴다", "파일 목록을 정리해 줘", q2);

const q3 = api.extractQuestionKeyword("\ufeff@model: gemini-3.8-flash-low\n질문입니다");
eq("맨 앞 BOM 이 있어도 지시어를 건너뛴다", "질문입니다", q3);

const q4 = api.extractQuestionKeyword("@MODEL: gemini-3.8-flash-low\n대소문자 다른 지시어");
eq("지시어 이름의 대소문자는 구분하지 않는다", "대소문자 다른 지시어", q4);

const q5 = api.extractQuestionKeyword("모델을 @model: 로 지정하는 방법을 설명해 줘");
ok("문장 중간에 나온 @model: 은 지시어가 아니다(건너뛰지 않는다)", q5.indexOf("@model:") >= 0);

// 펜스 표시(```) 줄만 건너뛰고 그 안의 줄은 남긴다. 이번 수정과 무관한 기존 동작이라 바뀌지 않았는지만 확인한다.
const q6 = api.extractQuestionKeyword("```python\ncode\n```\n실제 질문");
eq("코드 펜스 표시 줄만 건너뛴다(기존 동작 유지)", "code 실제 질문", q6);

eq("빈 값", "", api.extractQuestionKeyword(""));

console.log("extractAnswerKeyword");
const a1 = api.extractAnswerKeyword("### 버그\n1. merge_intervals 에서 정렬을 하지 않음");
ok("답변 미리보기도 snake_case 를 지킨다", a1.indexOf("merge_intervals") >= 0);
eq("표 답변은 항목: 값 으로 요약한다(기존 동작)", "파일: ~/.samjil/x · 개수: 3", api.extractAnswerKeyword("| 항목 | 값 |\n|---|---|\n| 파일 | ~/.samjil/x |\n| 개수 | 3 |"));

console.log("claudeTreeKeyOf: 세션 내용 및 링크 변경 감지");
const baseTree = {
  projects: [{ id: "p1", name: "프로젝트1", sessions: [{ id: "s1", title: "제목1", cwd: "C:/a", lastActivity: "2026-10-15 10:00:00", archived: false }] }],
  ungrouped: [],
  taskLinks: { t1: "s1" },
  handoffLinks: { h1: "s1" }
};
const baseKey = api.claudeTreeKeyOf(baseTree);
ok("기본 트리 키 생성됨", baseKey.length > 0);

const treeTitleChanged = JSON.parse(JSON.stringify(baseTree));
treeTitleChanged.projects[0].sessions[0].title = "제목 변경";
ok("세션 title 변경 시 키 변경", api.claudeTreeKeyOf(treeTitleChanged) !== baseKey);

const treeActivityChanged = JSON.parse(JSON.stringify(baseTree));
treeActivityChanged.projects[0].sessions[0].lastActivity = "2026-10-15 11:00:00";
ok("세션 lastActivity 변경 시 키 변경", api.claudeTreeKeyOf(treeActivityChanged) !== baseKey);

const treeArchivedChanged = JSON.parse(JSON.stringify(baseTree));
treeArchivedChanged.projects[0].sessions[0].archived = true;
ok("세션 archived 변경 시 키 변경", api.claudeTreeKeyOf(treeArchivedChanged) !== baseKey);

const treeTaskLinkChanged = JSON.parse(JSON.stringify(baseTree));
treeTaskLinkChanged.taskLinks.t1 = "s2";
ok("taskLinks 매핑 세션 변경 시 키 변경", api.claudeTreeKeyOf(treeTaskLinkChanged) !== baseKey);

console.log("pendingKeyOf: 진행 단계 및 누적 토큰 변경 감지");
const basePending = [{ task_id: "task-1", state: "running", model: "m1", started_at: "2026-10-15 10:00:00", progress: { step: 1, last_activity_ms: 1000, tokens: { total: 100 } } }];
const basePKey = api.pendingKeyOf(basePending);
ok("기본 pending 키 생성됨", basePKey.length > 0);

const pStepChanged = JSON.parse(JSON.stringify(basePending));
pStepChanged[0].progress.step = 2;
ok("progress.step 변경 시 키 변경", api.pendingKeyOf(pStepChanged) !== basePKey);

const pTokChanged = JSON.parse(JSON.stringify(basePending));
pTokChanged[0].progress.tokens.total = 150;
ok("progress.tokens.total 변경 시 키 변경", api.pendingKeyOf(pTokChanged) !== basePKey);

console.log("renderMarkdownWithMath: PowerShell 변수/금액 보존 및 수식 렌더링");
const rMath = api.renderMarkdownWithMath;
const psText = "변수 $env:USERPROFILE 및 $PSScriptRoot 확인";
const psRendered = rMath(psText);
ok("PowerShell 변수는 수식으로 치환되지 않음", psRendered.indexOf("katex") === -1 && psRendered.indexOf("$env:USERPROFILE") >= 0);

const priceText = "가격은 $5 ~ $10 사이입니다";
const priceRendered = rMath(priceText);
ok("금액 표기는 수식으로 치환되지 않음", priceRendered.indexOf("katex") === -1);

const mathText = "수식 $x^2 + y^2 = z^2$ 입니다";
const mathRendered = rMath(mathText);
ok("정상 인라인 수식은 katex 렌더링됨", mathRendered.indexOf("<katex>") >= 0 && mathRendered.indexOf("x^2 + y^2 = z^2") >= 0);

const parenMathText = "답은 \\(\\text{정답}\\) 입니다";
const parenRendered = rMath(parenMathText);
ok("\\(...\\) 수식은 katex 렌더링됨", parenRendered.indexOf("<katex>") >= 0 && parenRendered.indexOf("\\text{정답}") >= 0);

console.log("\n통과 " + passed + " / 실패 " + failed);
process.exit(failed > 0 ? 1 : 0);
