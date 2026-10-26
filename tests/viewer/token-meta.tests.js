// 위임 카드의 토큰 표시 테스트: 끝난 카드의 토큰 줄(총 · 누적 입력 · 누적 출력 · 현재 컨텍스트)과 진행 중 카드의 세부 문구.
//   node tests/viewer/token-meta.tests.js
// runtime/viewer/web/app.js 에서 함수 원문을 꺼내 그대로 실행합니다. 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다.
// 약속: 총 토큰 = 누적 입력 + 누적 출력. 출력에는 사고 토큰이 이미 들어 있어 "응답 · 사고"로 나눠 보이고 총에 다시 더하지 않는다.

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

const names = ["tokenShort", "recordLastStep", "recordContextKey", "tokenMetaItems", "liveTokenDetail", "liveTokenTitle"];
const make = new Function(
  "var recordContexts = {};\n" +
  names.map(extractFunction).join("\n") +
  "\nreturn { tokenMetaItems, recordLastStep, recordContextKey, liveTokenDetail, liveTokenTitle, recordContexts };"
);

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "  (기대: " + e + " / 실제: " + a + ")"); }
}
const texts = (items) => items.map((i) => i.text);

console.log("끝난 카드의 토큰 줄");
let api = make();
const r = { session_id: "conv-1", total_tokens: "313205", input_tokens: "239129", output_tokens: "74076", thinking_tokens: "47013", process: [{ n: 1 }, { n: 3 }, { n: 88 }] };
eq("캐시·컨텍스트를 받기 전: 총 · 누적 입력 · 누적 출력(응답 · 사고)", ["총 토큰 313,205", "누적 입력 239,129", "누적 출력 74,076 (응답 27,063 · 사고 47,013)"], texts(api.tokenMetaItems(r)));
eq("총 = 입력 + 출력 (사고를 더 더하지 않는다)", 313205, 239129 + 74076);
eq("응답 + 사고 = 출력", 74076, 27063 + 47013);
eq("한 호출의 마지막 단계 = 과정의 마지막 도구 호출 + 2(그 결과, 최종 응답)", 90, api.recordLastStep(r));
eq("과정이 없으면 0(전체)", 0, api.recordLastStep({ process: [] }));
eq("컨텍스트 요청 키는 대화 id | 마지막 단계", "conv-1|90", api.recordContextKey(r));
eq("대화 id 가 없으면 키가 없다", "", api.recordContextKey({ total_tokens: "1" }));
api.recordContexts["conv-1|90"] = { cache: 3544584, context: 68600 };
eq("받은 뒤: 누적 입력에 (캐시 X), 맨 끝에 현재 컨텍스트", ["총 토큰 313,205", "누적 입력 239,129 (캐시 3,544,584)", "누적 출력 74,076 (응답 27,063 · 사고 47,013)", "현재 컨텍스트 68,600"], texts(api.tokenMetaItems(r)));
api.recordContexts["conv-1|90"] = { cache: 0, context: 0 };
eq("캐시가 0 이면 괄호를 붙이지 않고, 컨텍스트가 0 이면 줄을 만들지 않는다", ["총 토큰 313,205", "누적 입력 239,129", "누적 출력 74,076 (응답 27,063 · 사고 47,013)"], texts(api.tokenMetaItems(r)));
eq("사고 토큰이 없으면 출력만", "누적 출력 500", texts(api.tokenMetaItems({ total_tokens: "1500", input_tokens: "1000", output_tokens: "500", thinking_tokens: "0" }))[2]);
eq("사고가 출력보다 커도(이상한 값) 응답은 음수가 되지 않는다", "누적 출력 100 (응답 0 · 사고 150)", texts(api.tokenMetaItems({ total_tokens: "300", input_tokens: "200", output_tokens: "100", thinking_tokens: "150" }))[2]);
eq("토큰 값이 하나도 없으면 빈 목록", [], api.tokenMetaItems({ total_tokens: "", input_tokens: "", output_tokens: "" }));

console.log("\n진행 중 카드의 세부");
const live = { input: 12000, output: 3000, total: 15000, cache: 480000, context: 68600, turns: 27 };
eq("입력 (캐시) · 출력 · 현재 컨텍스트", "입력 1.2만 (캐시 48.0만) · 출력 3,000 · 현재 컨텍스트 6.9만", api.liveTokenDetail(live));
eq("캐시와 컨텍스트가 없으면 입력 · 출력만", "입력 900 · 출력 110", api.liveTokenDetail({ input: 900, output: 110, total: 1010, cache: 0, context: 0 }));
const title = api.liveTokenTitle(live);
eq("설명에 총 = 입력 + 출력, 캐시는 총에 넣지 않는다는 것, 응답 횟수가 있다", true, /15,000 = 입력 12,000 \+ 출력 3,000/.test(title) && /총에 넣지 않/.test(title) && /모델 응답 27번/.test(title));

console.log("\n통과 " + passed + " / 실패 " + failed);
process.exit(failed ? 1 : 0);
