# agy-autotier.ps1(요청 난이도로 모델 노력 단계 자동 선택)와 핸드오프 지시문의 모델·세션 이름 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-autotier.tests.ps1
# 순수 함수만 부릅니다(agy 도 워처도 띄우지 않습니다). 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-autotier.ps1")
. (Join-Path $repoRoot "runtime\handoff\scripts\handoff-lib.ps1")
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\handoff-pump.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}
function Tier([string]$text, [bool]$folder = $false) { return (Get-AgyAutoTier $text $folder).Tier }

$savedAuto = $env:AGY_AUTO_MODEL
try {
    Write-Host "켜짐 / 끄기 (AGY_AUTO_MODEL)"
    Remove-Item Env:\AGY_AUTO_MODEL -ErrorAction SilentlyContinue
    Assert-Equal "기본은 켜짐" $true (Test-AgyAutoTierEnabled)
    foreach ($v in @("off", "OFF", "0", "false", "No")) { $env:AGY_AUTO_MODEL = $v; Assert-Equal "  AGY_AUTO_MODEL=$v 는 꺼짐" $false (Test-AgyAutoTierEnabled) }
    foreach ($v in @("on", "1", "")) { $env:AGY_AUTO_MODEL = $v; Assert-Equal "  AGY_AUTO_MODEL=[$v] 는 켜짐" $true (Test-AgyAutoTierEnabled) }
    Remove-Item Env:\AGY_AUTO_MODEL -ErrorAction SilentlyContinue

    Write-Host "low: 분명히 쉬운 일"
    Assert-Equal "짧은 질문" "low" (Tier "1부터 20까지 소수를 나열해 줘.")
    Assert-Equal "  번역" "low" (Tier "'멀티 테스트'를 영어, 일본어, 중국어로 번역해 줘.")
    Assert-Equal "  짧은 확인 답장(폴더가 열려 있어도)" "low" (Tier "확인했습니다. 다음으로 넘어가요." $true)
    Assert-Equal "  읽기만 한다고 밝힌 조회(쓰기 단어가 있어도 무시)" "low" (Tier "README 첫 줄을 읽고 한 줄로 요약해 줘. 읽기 전용이다. 파일을 만들거나 고치지 않는다." $true)
    Assert-Equal "  줄 수 세기(읽기 전용)" "low" (Tier "tests 폴더의 파일별 줄 수를 세어 표로 알려 줘. 파일을 만들거나 고치지 않고, git 명령을 쓰지 않는다(읽기 전용)." $true)

    Write-Host "medium: 생각은 필요하지만 파일을 바꾸지 않는 일"
    Assert-Equal "분석(왜)" "medium" (Tier "이 코드가 왜 느린지 알려 줘" $true)
    Assert-Equal "  검토" "medium" (Tier "이 설정 파일을 검토해 줘" $true)
    Assert-Equal "  설명" "medium" (Tier "이 정규식이 하는 일을 설명해 줘")
    Assert-Equal "  폴더 없이 만들거나 고치는 일(텍스트로 답함)" "medium" (Tier "이 문장을 자연스럽게 고쳐 줘")
    Assert-Equal "  중간 길이(1200자 넘음)" "medium" (Tier ("가나다 " * 450))
    Assert-Equal "  코드 블록 하나" "medium" (Tier "이 값을 알려 줘`n``````js`nvar a = 1;`n``````")

    Write-Host "high: 어렵거나 파일을 바꾸거나 긴 일"
    Assert-Equal "설계 단어" "high" (Tier "결제 모듈 구조를 설계해 줘")
    Assert-Equal "  최적화 단어" "high" (Tier "이 쿼리를 최적화해 줘")
    Assert-Equal "  영어 단어(refactor)" "high" (Tier "refactor this function")
    Assert-Equal "  버그 단어" "high" (Tier "버그 있는지 봐 줘")
    Assert-Equal "  폴더의 파일을 바꾸는 일" "high" (Tier "로그인 화면의 버튼 색을 바꿔 줘" $true)
    Assert-Equal "  구현" "high" (Tier "목록 정렬 기능을 구현해 줘" $true)
    Assert-Equal "  어려운 단어는 읽기 전용이라고 해도 high" "high" (Tier "읽기 전용으로 보안 문제를 찾아 줘" $true)
    Assert-Equal "  긴 요청(2500자 넘음)" "high" (Tier ("가나다 " * 900))
    Assert-Equal "  단계가 5개 이상" "high" (Tier "1. 가`n2. 나`n3. 다`n4. 라`n5. 마")
    Assert-Equal "  코드 블록 둘 이상" "high" (Tier "``````a`n``````그리고`n``````b`n``````")
    Assert-Equal "  빈 요청은 low(할 일이 없다)" "low" (Tier "")

    Write-Host "반환값"
    $r = Get-AgyAutoTier "1부터 20까지 소수를 나열해 줘."
    Assert-Equal "low 의 모델 ID" "gemini-3.8-flash-low" $r.Model
    Assert-Equal "  이유가 한 줄로 온다" $true (($r.Reason -match "짧고") -and ($r.Reason -notmatch "`n"))
    Assert-Equal "medium 의 모델 ID" "gemini-3.8-flash-medium" (Get-AgyAutoTier "이 설정을 검토해 줘").Model
    Assert-Equal "high 의 모델 ID" "gemini-3.8-flash-high" (Get-AgyAutoTier "결제 구조를 설계해 줘").Model
    Assert-Equal "  이유에 걸린 단어가 있다" $true ((Get-AgyAutoTier "결제 구조를 설계해 줘").Reason -match "결제")

    Write-Host "핸드오프: 세션 이름과 지시문(@model)"
    $row = [pscustomobject]@{ Num = "0003"; Title = "시험" }
    $low = @{ Tier = "low"; Model = "gemini-3.8-flash-low"; Reason = "x" }
    $med = @{ Tier = "medium"; Model = "gemini-3.8-flash-medium"; Reason = "x" }
    $high = @{ Tier = "high"; Model = "gemini-3.8-flash-high"; Reason = "x" }
    Assert-Equal "high 는 예전과 같은 대화 이름" "handoff-my-app" (Get-HandoffSessionName "my-app" $high)
    Assert-Equal "  자동 선택이 없으면(꺼짐·실패) 예전과 같다" "handoff-my-app" (Get-HandoffSessionName "my-app" $null)
    Assert-Equal "  low 는 단계를 붙인 대화" "handoff-my-app-low" (Get-HandoffSessionName "my-app" $low)
    Assert-Equal "  medium 도" "handoff-my-app-medium" (Get-HandoffSessionName "my-app" $med)
    Assert-Equal "  기록된 단계 문자열로도 같은 이름(완료 처리에서 씀)" "handoff-my-app-low" (Get-HandoffSessionName "my-app" $null "low")
    Assert-Equal "  빈 단계는 예전 이름" "handoff-my-app" (Get-HandoffSessionName "my-app" $null "")
    $tLow = New-HandoffDispatchText "my-app" "C:\ch\my-app" "C:\code\my-app" $row "C:\ch\my-app\msg\0003-c2a-x.md" "## 요약`n- 확인 부탁" $low
    $tMed = New-HandoffDispatchText "my-app" "C:\ch\my-app" "C:\code\my-app" $row "C:\ch\my-app\msg\0003-c2a-x.md" "## 요약`n- 검토 부탁" $med
    $tHigh = New-HandoffDispatchText "my-app" "C:\ch\my-app" "C:\code\my-app" $row "C:\ch\my-app\msg\0003-c2a-x.md" "## 요약`n- 설계 부탁" $high
    $tNone = New-HandoffDispatchText "my-app" "C:\ch\my-app" "C:\code\my-app" $row "C:\ch\my-app\msg\0003-c2a-x.md" "## 요약`n- 부탁"
    $first = { param($t, $n) (($t -split "`n") | Select-Object -First $n) -join "|" }
    Assert-Equal "low: @session 과 @model 이 맨 위에 있다" "@session: handoff-my-app-low|@model: gemini-3.8-flash-low|@cwd: C:\ch\my-app|@cwd: C:\code\my-app" (& $first $tLow 4)
    Assert-Equal "  medium" "@session: handoff-my-app-medium|@model: gemini-3.8-flash-medium" (& $first $tMed 2)
    Assert-Equal "  high: @model 은 쓰지 않는다(기본 우선순위로 폴백 가능)" "@session: handoff-my-app|@cwd: C:\ch\my-app|@cwd: C:\code\my-app" (& $first $tHigh 3)
    Assert-Equal "  자동 선택 없음(null): 예전과 같은 첫 줄들" "@session: handoff-my-app|@cwd: C:\ch\my-app" (& $first $tNone 2)
    Assert-Equal "  지시문 본문(처리 방법)은 단계와 상관없이 같다" $true (($tLow -match "## 처리 방법") -and ($tHigh -match "## 처리 방법"))
    Assert-Equal "  @model 줄은 한 번만" 1 @(($tLow -split "`n") | Where-Object { $_ -like "@model:*" }).Count

    Write-Host "AUTO.json 의 위임 기록에 단계가 남는다"
    $work = Join-Path ([IO.Path]::GetTempPath()) ("autotier-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        $st = Read-HandoffAutoState $work
        $st.dispatches = @(@{ num = "0003"; task_id = "handoff_my-app_0003_101010"; at = "2026-10-16 10:10:10"; done = $false; tier = "low" }, @{ num = "0004"; task_id = "handoff_my-app_0004_101011"; at = "2026-10-16 10:10:11"; done = $true })
        Write-HandoffAutoState $work $st
        $back = Read-HandoffAutoState $work
        Assert-Equal "쓰고 다시 읽어도 tier 가 남는다" "low" ([string]$back.dispatches[0].tier)
        Assert-Equal "  tier 가 없던 옛 기록은 빈 문자열" "" ([string]$back.dispatches[1].tier)
    } finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
finally {
    if ($null -ne $savedAuto) { $env:AGY_AUTO_MODEL = $savedAuto } else { Remove-Item Env:\AGY_AUTO_MODEL -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
