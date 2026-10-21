// 위임 기록 증분 합치기(mergeQaRecords) 테스트.
//   node tests/viewer/qa-records-merge.tests.js
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

const mergeQaRecords = new Function(extractFunction("mergeQaRecords") + "; return mergeQaRecords;")();

let passed = 0, failed = 0;
function assertEqual(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "  (기대: " + e + " / 실제: " + a + ")"); }
}

const base = [{ task_id: "a", answer: "1" }, { task_id: "b", answer: "2" }];
const incoming = [{ task_id: "b", answer: "2-new" }, { task_id: "c", answer: "3" }];
const merged = mergeQaRecords(base, incoming);

assertEqual("새 기록은 더해지고 같은 task_id 는 새것으로 바뀐다", ["a:1", "b:2-new", "c:3"],
  merged.slice().sort(function (x, y) { return x.task_id < y.task_id ? -1 : 1; }).map(function (r) { return r.task_id + ":" + r.answer; }));
assertEqual("원본 배열은 바뀌지 않는다", [{ task_id: "a", answer: "1" }, { task_id: "b", answer: "2" }], base);
assertEqual("들어온 기록이 없으면 같은 내용", 2, mergeQaRecords(base, []).length);
assertEqual("기본 배열이 비어 있으면 들어온 것만", ["c"], mergeQaRecords([], [{ task_id: "c" }]).map(function (r) { return r.task_id; }));

console.log("");
console.log("통과 " + passed + " / 실패 " + failed);
process.exit(failed ? 1 : 0);
