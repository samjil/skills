// 길어서 잘린 기록의 안내 문구를 원본 파일 링크로 바꾸는 규칙(splitTruncationNote, qaSourceUrl, qaTruncationLinkOf) 테스트.
//   node tests/viewer/qa-truncation.tests.js
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
function extractVar(name) {
  const m = new RegExp("var " + name + " = [^;]+;").exec(appJs);
  if (!m) throw new Error(name + " 를 app.js 에서 찾지 못했습니다.");
  return m[0];
}

// viaMcp 는 기록의 출처가 MCP 인지 본다. 시험에서는 source 만 보는 간단한 대용품을 쓴다(실제 함수의 규칙은 via-mcp.tests.js 가 본다).
const api = new Function(
  "function viaMcp(r) { return Boolean(r && r.source === 'mcp'); }\n" +
  extractVar("TRUNCATION_NOTE_RE") + "\n" +
  extractFunction("splitTruncationNote") + "\n" +
  extractFunction("qaSourceUrl") + "\n" +
  extractFunction("qaTruncationLinkOf") + "\n" +
  extractVar("QA_SOURCE_RENDER_MAX") + "\n" +
  extractVar("QA_PREVIEW_ANSWER_MAX") + "\n" + extractVar("QA_PREVIEW_QUESTION_MAX") + "\n" + extractVar("QA_PREVIEW_MAX_LINES") + "\n" +
  extractVar("QA_PREVIEW_SLACK_CHARS") + "\n" + extractVar("QA_PREVIEW_SLACK_LINES") + "\n" +
  extractFunction("qaPreviewLimitOf") + "\n" + extractFunction("qaPreviewOf") + "\n" +
  extractFunction("qaSourceDefaultView") + "\n" +
  extractFunction("qaSourceTitle") + "\n" +
  "return { splitTruncationNote, qaSourceUrl, qaTruncationLinkOf, qaSourceDefaultView, qaSourceTitle, QA_SOURCE_RENDER_MAX, qaPreviewLimitOf, qaPreviewOf };"
)();

let passed = 0, failed = 0;
function assertEqual(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "  (기대: " + e + " / 실제: " + a + ")"); }
}

const NOTE = "\n... (내용이 길어 일부 생략됨 - 전체 내용은 outbox/processed 폴더의 원본 파일 참고)";

console.log("splitTruncationNote: 끝에 붙은 잘림 안내를 떼어 낸다");
const cut = api.splitTruncationNote("앞 내용\n```html\n<div>" + NOTE);
assertEqual("안내를 떼어 내고 잘렸다고 알린다", [true, "앞 내용\n```html\n<div>"], [cut.truncated, cut.text]);
assertEqual("  열린 코드 블록은 그대로 둔다(안내가 코드 블록 안에 섞이지 않게 하려고 떼는 것이다)", true, cut.text.indexOf("```html") >= 0);
assertEqual("안내가 없으면 그대로", [false, "그냥 글"], (function () { const r = api.splitTruncationNote("그냥 글"); return [r.truncated, r.text]; })());
assertEqual("본문 중간에 같은 문구가 있어도 끝이 아니면 건드리지 않는다", false, api.splitTruncationNote("... (내용이 길어 일부 생략됨 - 설명) 그리고 계속되는 글").truncated);
assertEqual("끝의 공백·줄바꿈이 있어도 읽는다", true, api.splitTruncationNote("글" + NOTE + "\r\n").truncated);
assertEqual("null·undefined 도 오류 없이 빈 글", ["", false], (function () { const r = api.splitTruncationNote(null); return [r.text, r.truncated]; })());

console.log("qaSourceUrl");
assertEqual("작업 ID 는 주소용으로 인코딩한다", "/api/qa/source?task=claude_%ED%95%9C%EA%B8%80_1&kind=answer", api.qaSourceUrl("claude_한글_1", "answer"));

console.log("qaTruncationLinkOf: 링크를 만들 수 있는 기록인가");
assertEqual("작업 ID 가 있는 워처 기록(질문)은 링크가 있다", "/api/qa/source?task=t1&kind=question", (api.qaTruncationLinkOf({ task_id: "t1" }, "question") || {}).url);
assertEqual("  답변도 같다", "/api/qa/source?task=t1&kind=answer", (api.qaTruncationLinkOf({ task_id: "t1" }, "answer") || {}).url);
assertEqual("  이름표: 질문은 지시 원본, 답변은 답변 원본", ["지시 원본 전체 보기", "답변 원본 전체 보기"], [api.qaTruncationLinkOf({ task_id: "t1" }, "question").label, api.qaTruncationLinkOf({ task_id: "t1" }, "answer").label]);
assertEqual("MCP 로 직접 부른 기록은 원본 파일이 런타임 폴더에 없어 링크가 없다", null, api.qaTruncationLinkOf({ task_id: "t1", source: "mcp" }, "answer"));
assertEqual("작업 ID 가 없으면 링크가 없다", null, api.qaTruncationLinkOf({}, "answer"));

console.log("qaPreviewOf: 카드에는 일반적인 답변 길이만 미리 보인다");
const lim = api.qaPreviewLimitOf("answer");
assertEqual("답변 한도: 2000자·40줄, 질문 한도: 3000자·40줄", [[2000, 40], [3000, 40]], [[lim.chars, lim.lines], [api.qaPreviewLimitOf("question").chars, api.qaPreviewLimitOf("question").lines]]);
const short = "짧은 답입니다.\n두 번째 줄";
assertEqual("한도 안이면 그대로(자르지 않는다)", [false, short], (function () { const p = api.qaPreviewOf(short, 2000, 40); return [p.cut, p.text]; })());
assertEqual("  한도를 조금(여유 400자) 넘는 정도면 그냥 다 보인다(몇 줄 숨기려고 접는 건 번거롭다)", false, api.qaPreviewOf("가".repeat(2300), 2000, 40).cut);
const long1 = Array.from({ length: 100 }, (_, i) => "줄 " + i + " " + "나".repeat(40)).join("\n");
const p1 = api.qaPreviewOf(long1, 2000, 40);
assertEqual("길면 줄 단위로 자른다(줄 중간에서 끊지 않는다)", true, p1.cut && p1.text.split("\n").every((l) => /^줄 \d+ 나{40}$/.test(l)));
assertEqual("  글자 수 한도 안에 들어간다", true, p1.text.length <= 2000);
assertEqual("  전체 길이와 보인 길이를 알려 준다", [long1.length, p1.text.length], [p1.total, p1.shown]);
const tall = Array.from({ length: 120 }, (_, i) => "행" + i).join("\n");
const p2 = api.qaPreviewOf(tall, 2000, 40);
assertEqual("줄 수가 많으면 줄 수 한도(40줄)에서 자른다", [true, 40], [p2.cut, p2.text.split("\n").length]);
const fenced = "설명\n```html\n" + Array.from({ length: 90 }, (_, i) => "<p>" + i + "</p>").join("\n") + "\n```\n끝";
const p3 = api.qaPreviewOf(fenced, 2000, 40);
assertEqual("코드 블록 한가운데서 자르면 블록을 닫아 준다(뒤 글이 코드로 번지지 않게)", [true, 0], [p3.cut, (p3.text.match(/```/g) || []).length % 2]);
assertEqual("  코드 블록이 이미 닫힌 곳에서 자르면 닫는 줄을 더하지 않는다", 2, (api.qaPreviewOf("```js\nx\n```\n" + Array.from({ length: 80 }, (_, i) => "글 " + i).join("\n"), 2000, 40).text.match(/```/g) || []).length);
const headed = Array.from({ length: 30 }, (_, i) => "문단 " + i + " " + "다".repeat(50)).join("\n") + "\n## 마지막 제목\n" + Array.from({ length: 60 }, (_, i) => "뒷글 " + i).join("\n");
const pHead = api.qaPreviewOf(headed, 2000, 31);
assertEqual("제목 줄에서 끝나면 그 제목은 뺀다(뒤 문단이 잘려 제목만 덩그러니 남지 않게)", [true, false], [pHead.cut, /^#{1,6}\s/.test(pHead.text.split("\n").pop())]);
const oneLine = "가".repeat(5000);
assertEqual("줄바꿈 없이 아주 긴 한 줄도 한도에서 자른다", [true, 2000], (function () { const p = api.qaPreviewOf(oneLine, 2000, 40); return [p.cut, p.text.length]; })());
assertEqual("null 도 오류 없이", [false, ""], (function () { const p = api.qaPreviewOf(null, 2000, 40); return [p.cut, p.text]; })());
console.log("qaSourceDefaultView: 원본 창의 기본 보기");
assertEqual("보통 크기는 답변과 같은 스타일로 렌더링해서 보인다", "rendered", api.qaSourceDefaultView(20000));
assertEqual("  경계(한도 그대로)까지는 렌더링", "rendered", api.qaSourceDefaultView(api.QA_SOURCE_RENDER_MAX));
assertEqual("  한도를 넘는 아주 큰 파일은 기본을 Raw 로(렌더링이 브라우저를 멈추게 하지 않도록)", "raw", api.qaSourceDefaultView(api.QA_SOURCE_RENDER_MAX + 1));
assertEqual("  길이를 모르면 렌더링", "rendered", api.qaSourceDefaultView(undefined));

console.log("qaSourceTitle");
assertEqual("질문은 지시 원본, 답변은 답변 원본", ["지시 원본", "답변 원본"], [api.qaSourceTitle("question"), api.qaSourceTitle("answer")]);
assertEqual("기록에 저장된 글을 보는 창은 질문 전체 / 답변 전체", ["질문 전체", "답변 전체"], [api.qaSourceTitle("question", true), api.qaSourceTitle("answer", true)]);

console.log("");
console.log("통과 " + passed + " / 실패 " + failed);
process.exit(failed ? 1 : 0);
