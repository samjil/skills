# agy-brief-lint.ps1 시험: 지시문(브리프)의 흔한 빠짐을 경고로 알려 주는지 확인한다. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-brief-lint.tests.ps1
# 경고만 하고 지시문을 바꾸거나 막지 않는 것이 약속이다. 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-brief-lint.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}
function Has([string[]]$Warnings, [string]$Pattern) { return (@($Warnings | Where-Object { $_ -match $Pattern }).Count -gt 0) }

# 4단을 다 갖춘 좋은 브리프
$good = @"
@cwd: C:\project
@model: gemini-3.8-flash-medium
[1. 목표 및 작업 모드]
- 작업 목적: 로그인 버튼 색을 바꾼다(파일 수정).

[2. 대상 파일 및 상세 명세]
- 대상 경로: src/login.css:12
- 구현/수정 내용: .btn { color: #888 } -> .btn { color: #0a84ff }

[3. 프로젝트 규칙 및 범위 제한 (Non-Goals)]
- 핵심 규칙: 색은 토큰 변수만 쓴다.
- 접근 금지: 다른 화면의 스타일은 건드리지 말 것.
- 모호함: 정할 수 없으면 [확인 필요] 로 시작해 멈출 것.

[4. 검증 및 답변 형식 (DIGEST)]
- 검증 명령: npm test
- 보고 형식: [상태 · 변경 파일:줄 · 검증 한 줄 · 우려]
"@

Write-Host "좋은 브리프"
$w = @(Get-AgyBriefWarnings $good)
Assert-Equal "4단을 갖춘 @cwd 브리프는 경고가 없다" 0 $w.Count

Write-Host "@cwd 작업의 빠짐"
$w = @(Get-AgyBriefWarnings "@cwd: C:\project`n버튼 색 좀 바꿔 줘.")
Assert-Equal "너무 짧으면 알린다" $true (Has $w "매우 짧습니다")
Assert-Equal "  검증 방법이 없다고 알린다" $true (Has $w "검증 방법")
Assert-Equal "  범위 제한이 없다고 알린다" $true (Has $w "범위 제한")
Assert-Equal "  대상 파일 경로가 없다고 알린다" $true (Has $w "대상 파일 경로")
$noVerify = $good -replace "(?s)\[4\..*$", ""
$w = @(Get-AgyBriefWarnings $noVerify)
Assert-Equal "[4단]만 빠지면 검증 경고 하나만 난다" "1|True" ("{0}|{1}" -f $w.Count, (Has $w "검증 방법"))
$noScope = $good -replace "(?m)^- 접근 금지.*\r?\n", ""
$w = @(Get-AgyBriefWarnings $noScope)
Assert-Equal "접근 금지 줄만 빠져도 [3.] 표시와 '건드리지' 가 남아 있으면 경고하지 않는다" 0 $w.Count
$noScopeAtAll = ("@cwd: C:\project`n" + ("src/login.css:12 의 .btn 색을 #0a84ff 로 바꾸고 npm test 로 확인한 뒤 결과만 알려 주세요. 다른 설명은 필요 없습니다. " * 3))
$w = @(Get-AgyBriefWarnings $noScopeAtAll)
Assert-Equal "검증 · 파일은 있고 범위 제한만 없으면 그 경고만 난다" "1|True" ("{0}|{1}" -f $w.Count, (Has $w "범위 제한"))
$w = @(Get-AgyBriefWarnings ($good -replace "src/login\.css:12", "로그인 버튼" -replace "\[2\. ", "[둘. "))
Assert-Equal "대상 파일 경로·[2.] 표시가 모두 없으면 알린다" $true (Has $w "대상 파일 경로")

Write-Host "모든 위임에 보는 항목"
$long = "@cwd: C:\project`n" + ("src/a.js 를 npm test 로 검증하고 다른 파일은 건드리지 말 것. " * 200)
$w = @(Get-AgyBriefWarnings $long)
Assert-Equal "6000자를 넘으면 길다고 알린다" $true (Has $w "지시문이 깁니다")
$fence = '```' + "`n" + ((1..100 | ForEach-Object { "line $_" }) -join "`n") + "`n" + '```'
$w = @(Get-AgyBriefWarnings ($good + "`n" + $fence))
Assert-Equal "코드 블록이 80줄을 넘으면 파일 본문 붙여넣기로 본다" $true (Has $w "코드 블록이 100줄")
$shortFence = '```' + "`n" + ((1..10 | ForEach-Object { "line $_" }) -join "`n") + "`n" + '```'
$w = @(Get-AgyBriefWarnings ($good + "`n" + $shortFence))
Assert-Equal "  짧은 코드 블록(AS-IS/TO-BE)은 괜찮다" 0 $w.Count
$w = @(Get-AgyBriefWarnings ($good + "`n- 브라우저를 열지 마라."))
Assert-Equal "'브라우저를 열지 마라' 같은 능력 추측 금지를 알린다" $true (Has $w "능력을 추측")
$w = @(Get-AgyBriefWarnings ($good + "`n- Do not open a browser."))
Assert-Equal "  영어 표현도 잡는다" $true (Has $w "능력을 추측")
$w = @(Get-AgyBriefWarnings ($good + "`n- 커밋하지 마라. 다른 폴더는 수정하지 마라."))
Assert-Equal "  실제로 위험한 것의 금지(커밋 · 수정)는 경고하지 않는다" 0 $w.Count

Write-Host "@cwd 없는 위임"
$w = @(Get-AgyBriefWarnings "아래 문장을 영어로 번역해 줘.`n안녕하세요.")
Assert-Equal "한글 답변 문장이 없으면 알린다" $true (Has $w "한글로 답")
Assert-Equal "  @cwd 전용 항목(검증·범위·파일)은 묻지 않는다" 1 $w.Count
$w = @(Get-AgyBriefWarnings "서울의 영문 도시 이름만 답해. 최종 답변은 한글로.")
Assert-Equal "한글 답변 문장이 있으면 경고가 없다" 0 $w.Count

Write-Host "끄기"
$w = @(Get-AgyBriefWarnings "@raw: true`n@cwd: C:\project`n짧음")
Assert-Equal "@raw: true 면 점검하지 않는다" 0 $w.Count
$env:AGY_BRIEF_LINT = "off"
Assert-Equal "AGY_BRIEF_LINT=off 면 꺼짐으로 본다" $false (Test-AgyBriefLintEnabled)
$env:AGY_BRIEF_LINT = "on"
Assert-Equal "  그 밖의 값이면 켜짐" $true (Test-AgyBriefLintEnabled)
Remove-Item Env:\AGY_BRIEF_LINT -ErrorAction SilentlyContinue
Assert-Equal "  값이 없으면 켜짐" $true (Test-AgyBriefLintEnabled)
$p = Split-AgyBriefDirectives "@cwd: A`n@cwd: B`n@model: m`n본문 첫 줄`n@cwd: 본문 중간"
Assert-Equal "지시어 해석: 맨 위의 @ 줄만 지시어(두 개의 @cwd), 본문 중간의 @cwd 는 본문" "2|본문 첫 줄" ("{0}|{1}" -f $p.Directives["cwd"].Count, ($p.Body -split "`n")[0])

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
