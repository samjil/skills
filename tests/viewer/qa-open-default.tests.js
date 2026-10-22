// 위임 기록 카드의 답변 구역을 기본으로 펼칠지 정하는 규칙(qaDefaultAnswerOpen) 테스트.
//   node tests/viewer/qa-open-default.tests.js
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

const qaDefaultAnswerOpen = new Function(extractFunction("qaDefaultAnswerOpen") + "; return qaDefaultAnswerOpen;")();

let passed = 0, failed = 0;
function assertEqual(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "  (기대: " + e + " / 실제: " + a + ")"); }
}

console.log("답변 구역의 기본 펼침");
assertEqual("맨 위 카드의 답변은 펼친다(예전 규칙 그대로)", true, qaDefaultAnswerOpen({ isFirst: true, isAnswer: true, isProcessing: false }));
assertEqual("  맨 위가 아닌 끝난 카드의 답변은 접는다", false, qaDefaultAnswerOpen({ isFirst: false, isAnswer: true, isProcessing: false }));
assertEqual("지금 실행 중인 카드는 맨 위가 아니어도 답변을 펼친다(두 작업이 같이 돌면 둘 다 진행 화면)", true, qaDefaultAnswerOpen({ isFirst: false, isAnswer: true, isProcessing: true }));
assertEqual("  실행 중이고 맨 위여도 펼친다", true, qaDefaultAnswerOpen({ isFirst: true, isAnswer: true, isProcessing: true }));
assertEqual("질문 구역은 실행 중이어도 접는다", false, qaDefaultAnswerOpen({ isFirst: false, isAnswer: false, isProcessing: true }));
assertEqual("  맨 위 카드의 질문도 접는다(예전 규칙 그대로)", false, qaDefaultAnswerOpen({ isFirst: true, isAnswer: false, isProcessing: false }));
assertEqual("값이 빠져도 오류 없이 접는다", false, qaDefaultAnswerOpen({}));

console.log("");
console.log("통과 " + passed + " / 실패 " + failed);
process.exit(failed ? 1 : 0);
