// 진행 중인 위임 카드의 "지금:" 줄(buildProgressActionHtml, buildProgressHtml, progressToolLabel) 테스트.
//   node tests/viewer/progress-text.tests.js
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

const names = ["escapeHtml", "formatDuration", "progressToolLabel", "shortenPathsForCwd", "buildNarrationHtml", "buildProgressActionHtml", "buildProgressHtml"];
const api = new Function(names.map(extractFunction).join("\n") + "\nreturn { progressToolLabel, buildProgressActionHtml, buildProgressHtml };")();

let passed = 0, failed = 0;
function eq(name, expected, actual) {
  if (expected === actual) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "\n        기대: " + JSON.stringify(expected) + "\n        실제: " + JSON.stringify(actual)); }
}
function ok(name, cond) { eq(name, true, Boolean(cond)); }
const text = (html) => html.replace(/<[^>]*>/g, "");   // 태그를 벗겨 화면에 보이는 글자만

console.log("progressToolLabel: 도구 이름 -> 한글 설명");
const known = { run_command: "명령 실행", view_file: "파일 읽기", write_to_file: "파일 쓰기", replace_file_content: "파일 일부 수정", list_dir: "폴더 목록 보기", find_by_name: "파일 이름 찾기", grep_search: "파일 내용 검색", search_web: "웹 검색", read_url_content: "웹 페이지 읽기", manage_task: "작업 관리", schedule: "잠시 대기", generate_image: "이미지 생성" };
Object.keys(known).forEach(function (k) { eq(k + " -> " + known[k], known[k], api.progressToolLabel(k)); });
eq("모르는 도구는 이름을 그대로", "brand_new_tool", api.progressToolLabel("brand_new_tool"));
eq("Object 기본 속성 이름(constructor)을 도구로 착각하지 않는다", "constructor", api.progressToolLabel("constructor"));
eq("빈 이름은 빈 값", "", api.progressToolLabel(""));
eq("undefined 는 빈 값", "", api.progressToolLabel(undefined));

console.log("buildProgressActionHtml: 실제 사례 17단계 'Checking target directory'");
const real = { step: 17, tool: "run_command", detail: "Get-Location", cwd: "C:\\work\\agy-high-test", background: false, action: "Checking target directory", thinking: "폴더를 확인한다" };
const h = api.buildProgressActionHtml(real);
eq("화면에 보이는 글: 한글 설명 + 명령 + 영어 라벨(그 아래 줄에 agy 의 생각)", "지금: 명령 실행 Get-Location · Checking target directory생각 폴더를 확인한다", text(h));
ok("'지금:' 줄 자체에는 생각이 섞이지 않는다", text(h.slice(0, h.indexOf("</div>") + 6)) === "지금: 명령 실행 Get-Location · Checking target directory");
ok("도구 설명을 굵게(pg-tool)", h.indexOf('<span class="pg-tool">명령 실행</span>') >= 0);
ok("대상을 별도 요소(pg-detail)로", h.indexOf('<span class="pg-detail">Get-Location</span>') >= 0);
ok("영어 라벨은 흐리게(pg-label)", h.indexOf('<span class="pg-label">· Checking target directory</span>') >= 0);
ok("마우스를 올리면 도구 이름·대상·실행 폴더·라벨을 전부 보여 준다",
  h.indexOf("도구: run_command") >= 0 && h.indexOf("대상: Get-Location") >= 0 && h.indexOf("실행 폴더: C:\\work\\agy-high-test") >= 0 &&
  h.indexOf("agy 가 붙인 설명: Checking target directory") >= 0);

console.log("buildProgressActionHtml: 변형");
eq("백그라운드 명령은 표시한다", "지금: 명령 실행 (백그라운드) npm run build · Building",
  text(api.buildProgressActionHtml({ tool: "run_command", detail: "npm run build", background: true, action: "Building" })));
eq("파일 읽기", "지금: 파일 읽기 C:\\a\\b.md (1~100행) · Reading b.md",
  text(api.buildProgressActionHtml({ tool: "view_file", detail: "C:\\a\\b.md (1~100행)", action: "Reading b.md" })));
eq("대상이 없는 도구는 설명과 라벨만", "지금: 폴더 목록 보기 · Listing", text(api.buildProgressActionHtml({ tool: "list_dir", detail: "", action: "Listing" })));
eq("옛 서버(tool/detail 없음)는 영어 라벨만 — 기존 동작", "지금: Checking target directory", text(api.buildProgressActionHtml({ action: "Checking target directory" })));
eq("아무 정보도 없으면 줄을 만들지 않는다", "", api.buildProgressActionHtml({}));
eq("작업 폴더 아래 파일은 상대 경로로(전체 경로는 title 에 남는다)", "지금: 파일 읽기 src\\a.py (1~10행) · Reading a.py",
  text(api.buildProgressActionHtml({ tool: "view_file", detail: "C:\\w\\p\\src\\a.py (1~10행)", cwd: "C:\\w\\p", action: "Reading a.py" })));
ok("title 의 대상은 전체 경로 그대로", api.buildProgressActionHtml({ tool: "view_file", detail: "C:\\w\\p\\src\\a.py", cwd: "C:\\w\\p" }).indexOf("대상: C:\\w\\p\\src\\a.py") >= 0);
ok("지금 줄 아래에 agy 의 생각이 보인다(pg-think)", api.buildProgressActionHtml({ tool: "run_command", detail: "Get-Location", action: "Checking", thinking: "Check the folder first." }).indexOf('<span class="pg-think"><b>생각</b> Check the folder first.</span>') >= 0);
ok("진행 설명(say)도 보인다", api.buildProgressActionHtml({ tool: "run_command", detail: "x", say: "Waiting for lint." }).indexOf('<span class="pg-say"><b>설명</b> Waiting for lint.</span>') >= 0);
ok("생각이 없으면 pg-think 를 만들지 않는다", api.buildProgressActionHtml({ tool: "run_command", detail: "x" }).indexOf("pg-think") === -1);
ok("도구 정보 없이 생각만 있어도 줄이 나온다", api.buildProgressActionHtml({ thinking: "Only thinking." }).indexOf("Only thinking.") >= 0);
eq("작업 폴더를 인자로 주면 그 기준으로 줄인다(진행 정보의 cwd 는 명령 실행 폴더라 대신 쓰지 않는다)", "지금: 파일 읽기 a.py",
  text(api.buildProgressActionHtml({ tool: "view_file", detail: "C:\\w\\p\\a.py", cwd: "D:\\elsewhere" }, "C:\\w\\p")));
eq("라벨 없이 도구 이름만 있어도 보인다", "지금: 웹 검색 agy login", text(api.buildProgressActionHtml({ tool: "search_web", detail: "agy login" })));

console.log("HTML 이스케이프(명령에 <, >, &, 따옴표가 있어도 화면이 깨지거나 주입되지 않는다)");
const evil = api.buildProgressActionHtml({ tool: "run_command", detail: "echo \"<script>alert(1)</script>\" & dir", cwd: "C:\\a\"b", action: "<b>x</b>" });
ok("<script> 가 태그로 살아 있지 않다", evil.indexOf("<script>") === -1);
ok("본문에는 이스케이프된 글자로 보인다", evil.indexOf("&lt;script&gt;") >= 0);
ok("속성(title)이 따옴표로 깨지지 않는다", (evil.match(/"/g) || []).length % 2 === 0);

console.log("buildProgressHtml: 단계 설명과 전체 구성");
const full = api.buildProgressHtml(real);
ok("'17단계 진행' 이 보인다", text(full).indexOf("17단계 진행") >= 0);
ok("'N단계'가 무엇을 세는 번호인지 설명(title)한다", full.indexOf("도구를 부르는 것과 그 결과가 각각 한 단계") >= 0);
ok("지금 줄이 들어 있다", text(full).indexOf("지금: 명령 실행 Get-Location · Checking target directory") >= 0);
eq("진행 정보가 없으면 빈 값", "", api.buildProgressHtml(null));
ok("마지막 활동 시간(pg-idle)은 그대로 있다", api.buildProgressHtml({ step: 3, last_activity_ms: Date.now() - 5000, action: "x" }).indexOf('class="pg-idle"') >= 0);

console.log("\n통과 " + passed + " / 실패 " + failed);
process.exit(failed > 0 ? 1 : 0);
