# agy-rules.ps1(코딩 위임에 표준 규칙을 자동으로 붙이는 헬퍼) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-rules.tests.ps1
# 순수 함수만 부릅니다(agy 도 워처도 띄우지 않습니다). 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-rules.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

Write-Host "붙이는 경우: @cwd 가 있고 @raw 가 아닐 때"
$r = Add-AgyStandardRules "src/app.js 의 로그인 함수에 입력 검증을 추가해 줘." $true $false
Assert-Equal "네 규칙이 모두 붙는다" "no-commit,foreground,touch-only,korean" (@($r.Added) -join ",")
Assert-Equal "  본문은 그대로 앞에 있다" $true ($r.Text.StartsWith("src/app.js 의 로그인 함수에 입력 검증을 추가해 줘."))
Assert-Equal "  DO NOT COMMIT · FOREGROUND · 한글 답변 문장이 들어 있다" $true (($r.Text -match "DO NOT COMMIT") -and ($r.Text -match "FOREGROUND") -and ($r.Text -match "in Korean") -and ($r.Text -match "Touch only"))
Assert-Equal "  'Rules (added automatically' 머리말이 있다" $true ($r.Text -match "Rules \(added automatically by the watcher\):")
Assert-Equal "  끝은 줄바꿈 하나" $true ($r.Text.EndsWith("raw error text as is).`n") -and -not $r.Text.EndsWith("`n`n"))

Write-Host "붙이지 않는 경우"
$r = Add-AgyStandardRules "번역해 줘" $false $false
Assert-Equal "@cwd 가 없으면 아무것도 붙이지 않는다(번역·데이터 변환의 결과 언어와 충돌하지 않게)" "0|번역해 줘" ("{0}|{1}" -f @($r.Added).Count, $r.Text)
$r = Add-AgyStandardRules "고쳐 줘" $true $true
Assert-Equal "@raw: true 면 붙이지 않는다" "0|고쳐 줘" ("{0}|{1}" -f @($r.Added).Count, $r.Text)

Write-Host "이미 있는 규칙은 건너뛴다 (규칙마다 따로)"
$manual = "고쳐 줘.`n`nRules:`n- DO NOT COMMIT. Do not run git add.`n- Run every command in the FOREGROUND and wait.`nFinal reply in Korean."
$r = Add-AgyStandardRules $manual $true $false
Assert-Equal "Claude 가 직접 쓴 세 규칙은 건너뛰고 빠진 touch-only 만 붙인다" "touch-only" (@($r.Added) -join ",")
Assert-Equal "  직접 쓴 DO NOT COMMIT 이 두 번 나오지 않는다" 1 ([regex]::Matches($r.Text, "DO NOT COMMIT")).Count
$full = "고쳐 줘`nDO NOT COMMIT`nFOREGROUND 로 실행`nTouch only the files this task needs.`n최종 답변과 보고서는 한글로 작성한다."
$r = Add-AgyStandardRules $full $true $false
Assert-Equal "모든 규칙이 이미 있으면 본문 그대로(붙일 것 없음)" "0|True" ("{0}|{1}" -f @($r.Added).Count, ($r.Text -ceq $full))
$r = Add-AgyStandardRules "커밋하지 마. 한글로 보고해." $true $false
Assert-Equal "한글 문장으로 쓴 규칙('커밋하지 마', '한글로 보고')도 인식한다" "foreground,touch-only" (@($r.Added) -join ",")

Write-Host "지시어 값"
foreach ($v in @("true", "TRUE", " yes ", "1", "on", "예")) { Assert-Equal "  [$v] 는 참" $true (ConvertTo-AgyDirectiveFlag $v) }
foreach ($v in @("false", "no", "0", "off", "", "maybe")) { Assert-Equal "  [$v] 는 거짓" $false (ConvertTo-AgyDirectiveFlag $v) }

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
