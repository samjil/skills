# agy 에 지시문을 넘기는 방식(인라인 / @파일 참조) 결정 규칙 시험. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\prompt-delivery.tests.ps1
# 같은 질문을 두 방식으로 보냈을 때 답은 같았고 인라인이 호출마다 약 2,500토큰 쌌다(실측). 인라인은 아래 조건을 모두 만족할 때만 쓴다.
# 워처 본체는 실행하지 않고 watch-agy.ps1 에서 함수만 꺼내 돌립니다. 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$watch = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\watch-agy.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($watch, [ref]$tokens, [ref]$errs)
Assert-Equal "watch-agy.ps1 에 문법 오류가 없다" 0 @($errs).Count
foreach ($name in @("Get-AgyPromptMarker", "Get-AgyPromptDelivery", "Get-OtherRunningMarkers")) {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name 를 watch-agy.ps1 에서 찾지 못했습니다." }
    Invoke-Expression $fn.Extent.Text
}
$InlinePromptMaxChars = 8000

Write-Host "표식: 지시문 첫 줄(따옴표·역슬래시 앞까지, 12자 이상일 때만, 60자까지)"
Assert-Equal "12자 이상이면 첫 줄이 표식" "3 곱하기 7 은 얼마인지" (Get-AgyPromptMarker "3 곱하기 7 은 얼마인지`n둘째 줄")
Assert-Equal "  12자 미만이면 표식 없음" "" (Get-AgyPromptMarker "짧은 질문")
Assert-Equal "  따옴표 앞에서 끊는다" "그는 오늘 아침에 이렇게 말했다 " (Get-AgyPromptMarker '그는 오늘 아침에 이렇게 말했다 "안녕" 하고')
Assert-Equal "  역슬래시 앞에서 끊는다" "다음 경로의 파일을 읽는다 C:" (Get-AgyPromptMarker '다음 경로의 파일을 읽는다 C:\Users\x')
Assert-Equal "  60자에서 자른다" 60 (Get-AgyPromptMarker ("가" * 100)).Length

Write-Host "전달 방식 결정"
$d = Get-AgyPromptDelivery "3 곱하기 7 은 얼마인지 숫자 하나로만 답한다." @() 0
Assert-Equal "짧고 겹치지 않으면 인라인" "inline" $d.Mode
Assert-Equal "  표식이 따라온다" "3 곱하기 7 은 얼마인지 숫자 하나로만 답한다." $d.Marker
Assert-Equal "8000자까지는 인라인" "inline" (Get-AgyPromptDelivery (("가" * 7999) + "나") @() 0).Mode
Assert-Equal "8001자부터는 파일 참조" "file" (Get-AgyPromptDelivery ("가" * 8001) @() 0).Mode
Assert-Equal "  이유: 길다" "long" (Get-AgyPromptDelivery ("가" * 8001) @() 0).Reason
Assert-Equal "@ 로 시작하면 파일 참조(agy 가 실제 파일 경로로 읽을 수 있다)" "file|at" ("{0}|{1}" -f (Get-AgyPromptDelivery "@C:\x\a.txt 이 파일을 요약한다" @() 0).Mode, (Get-AgyPromptDelivery "@C:\x\a.txt 이 파일을 요약한다" @() 0).Reason)
Assert-Equal "  앞 공백 뒤의 @ 도 같다" "file" (Get-AgyPromptDelivery "  `n@a.txt 요약" @() 0).Mode
Assert-Equal "  @ 가 중간에 있으면 상관없다" "inline" (Get-AgyPromptDelivery "메일 주소는 a@b.com 입니다 그대로 답한다" @() 0).Mode
Assert-Equal "다른 작업이 같은 표식이면 파일 참조(대화를 가려내려고)" "file|marker" ("{0}|{1}" -f (Get-AgyPromptDelivery "3 곱하기 7 은 얼마인지 숫자 하나로만 답한다." @("3 곱하기 7 은 얼마인지 숫자 하나로만 답한다.") 1).Mode, (Get-AgyPromptDelivery "3 곱하기 7 은 얼마인지 숫자 하나로만 답한다." @("3 곱하기 7 은 얼마인지 숫자 하나로만 답한다.") 1).Reason)
Assert-Equal "  한쪽이 다른 쪽을 품어도 같다(대화 기록 맨 앞에 들어 있는지 포함 검사라서)" "file" (Get-AgyPromptDelivery "3 곱하기 7 은 얼마인지 숫자 하나로만 답한다." @("3 곱하기 7 은 얼마인지") 1).Mode
Assert-Equal "  표식이 다르면 인라인" "inline" (Get-AgyPromptDelivery "3 곱하기 7 은 얼마인지 숫자 하나로만 답한다." @("해시 테이블에서 충돌이 생기는 이유") 1).Mode
Assert-Equal "표식이 없는(첫 줄이 짧은) 지시는 다른 작업이 돌고 있으면 파일 참조" "file|no-marker" ("{0}|{1}" -f (Get-AgyPromptDelivery "2+3=?" @() 1).Mode, (Get-AgyPromptDelivery "2+3=?" @() 1).Reason)
Assert-Equal "  혼자 돌고 있으면 인라인" "inline" (Get-AgyPromptDelivery "2+3=?" @() 0).Mode

Write-Host "다른 작업의 표식 읽기(Get-OtherRunningMarkers)"
$work = Join-Path ([IO.Path]::GetTempPath()) ("prompt-delivery-test-" + [Guid]::NewGuid().ToString("N"))
$RunningDir = Join-Path $work "running"
New-Item -ItemType Directory -Force -Path $RunningDir | Out-Null
function Read-RunningClaim([string]$Path) { try { return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null } }
[IO.File]::WriteAllText((Join-Path $RunningDir "t1.json"), '{"task_id":"t1","marker":"첫 번째 작업의 표식 글자","pid":1}', (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $RunningDir "t2.json"), '{"task_id":"t2","pid":2}', (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $RunningDir "t3.json"), '{"task_id":"t3","marker":"세 번째 작업의 표식 글자","pid":3}', (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $RunningDir "broken.json"), '{ 깨진', (New-Object Text.UTF8Encoding($false)))
$o = Get-OtherRunningMarkers "t3"
Assert-Equal "자기 것은 빼고 표식이 있는 다른 작업의 것만" "첫 번째 작업의 표식 글자" (@($o.Markers) -join "|")
Assert-Equal "  다른 작업 수(읽을 수 있는 표시 파일 중 자기 것 제외)" 2 $o.Total
Assert-Equal "  폴더가 없으면 0" 0 (& { $RunningDir = Join-Path $work "없음"; (Get-OtherRunningMarkers "x").Total })

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
