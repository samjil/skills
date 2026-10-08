# watch-agy.ps1 의 Invoke-AgyOnce(기다리는 루프)를 가짜 agy 로 끝까지 돌려 보는 통합 테스트.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\invoke-agy-once.tests.ps1
# 마감/멈춤 기준을 초 단위로 줄여서 돌리므로 전체 약 1~2분 걸립니다.
# 가짜 agy(agy.exe 로 복사한 powershell)를 임시 폴더에 두고 PATH 맨 앞에 둡니다. 실제 agy 는 건드리지 않습니다:
# 종료 대상은 이 테스트 프로세스의 자손 agy 뿐입니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$subDir   = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub"
. (Join-Path $subDir "agy-progress.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}
function Assert-True($name, $cond) { Assert-Equal $name $true ([bool]$cond) }

# watch-agy.ps1 에서 Invoke-AgyOnce 함수 정의만 꺼내 옵니다(워처 본체는 실행하지 않음).
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $subDir "watch-agy.ps1"), [ref]$tokens, [ref]$errs)
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq "Invoke-AgyOnce" }, $true)
if (-not $fn) { throw "Invoke-AgyOnce 를 watch-agy.ps1 에서 찾지 못했습니다." }
Invoke-Expression $fn.Extent.Text

$script:LogLines = @()
function Log($msg) { $script:LogLines += $msg }

# 테스트용으로 줄인 값 (실제: 1800 / 300 / 30 / 600 / 120)
$AgyTimeoutSeconds = 24
$AgyStallSeconds = 8
$AgyPollSeconds = 2
$AgyProgressLogSeconds = 600
$AgyConversationWindowSeconds = 5

# 가짜 agy: 모드에 따라 대화 파일을 만들고 갱신한다.
$work = Join-Path ([IO.Path]::GetTempPath()) ("invoke-agy-once-test-" + [Guid]::NewGuid().ToString("N"))
$fakeBin = Join-Path $work "bin"
$env:AGY_HOME = Join-Path $work "agyhome"
New-Item -ItemType Directory -Force -Path $fakeBin, (Join-Path $env:AGY_HOME "conversations") | Out-Null
Set-Content -Path (Join-Path $fakeBin "fake-agy.ps1") -Encoding UTF8 -Value @'
$mode = $env:FAKE_AGY_MODE
$id = [Guid]::NewGuid().ToString()
$db = Join-Path $env:AGY_HOME "conversations\$id.db"
$tr = Join-Path $env:AGY_HOME "brain\$id\.system_generated\logs\transcript_full.jsonl"
function Touch { Set-Content -LiteralPath $db -Value (Get-Date).Ticks; Set-Content -LiteralPath $tr -Value (Get-Date).Ticks }
if ($mode -ne "no-conversation") {
    New-Item -ItemType Directory -Force -Path (Split-Path $tr) | Out-Null
    Touch
}
switch ($mode) {
    "work-then-finish" { for ($i = 0; $i -lt 7; $i++) { Start-Sleep 2; Touch }; '{"status":"SUCCESS","response":"done","conversation_id":"' + $id + '"}' }
    "work-then-silent" { for ($i = 0; $i -lt 2; $i++) { Start-Sleep 2; Touch }; Start-Sleep 60 }
    "work-forever"     { for ($i = 0; $i -lt 30; $i++) { Start-Sleep 2; Touch } }
    "no-conversation"  { Start-Sleep 60 }
}
'@
# 실제 agy 와 같은 프로세스 이름(agy.exe)이어야 워처의 종료 경로(자손 agy 찾기)를 그대로 탄다.
Copy-Item -LiteralPath (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") -Destination (Join-Path $fakeBin "agy.exe")
$env:PATH = "$fakeBin;$env:PATH"

function Run-Fake($mode) {
    $env:FAKE_AGY_MODE = $mode
    $script:LogLines = @()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $fakeArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $fakeBin 'fake-agy.ps1'))
    $r = Invoke-AgyOnce $fakeArgs (Join-Path $work "err.log") $work
    $sw.Stop()
    return @{ Result = $r; Seconds = $sw.Elapsed.TotalSeconds }
}

Write-Host "A) 14초 동안 계속 일하다 끝남 (멈춤 기준 8초보다 오래 걸려도 끊기면 안 됨)"
$a = Run-Fake "work-then-finish"
Assert-Equal "  타임아웃 아님" $false $a.Result.TimedOut
Assert-True  "  결과(JSON)를 받음" ($a.Result.Raw -match "SUCCESS")
Assert-True  "  기준(8초)보다 오래 걸렸음 ($([int]$a.Seconds)초)" ($a.Seconds -gt 12)

Write-Host "B) 4초 일하고 멈춤 -> 멈춤 판정으로 중단"
$b = Run-Fake "work-then-silent"
Assert-Equal "  타임아웃" $true $b.Result.TimedOut
Assert-Equal "  사유는 stall" "stall" $b.Result.Reason
Assert-True  "  마감(24초)보다 훨씬 일찍 중단 ($([int]$b.Seconds)초)" ($b.Seconds -lt 20)
Assert-True  "  대화 ID를 기록" ([bool]$b.Result.ConversationId)
Assert-True  "  멈춤 시간이 기준 이상 ($([int]$b.Result.IdleSeconds)초)" ($b.Result.IdleSeconds -ge 8)

Write-Host "C) 계속 일하지만 절대 마감(24초)을 넘김 -> 마감으로 중단"
$c = Run-Fake "work-forever"
Assert-Equal "  타임아웃" $true $c.Result.TimedOut
Assert-Equal "  사유는 cap" "cap" $c.Result.Reason
Assert-True  "  마감 근처에서 중단 ($([int]$c.Seconds)초)" ($c.Seconds -ge 23 -and $c.Seconds -lt 32)

Write-Host "D) 새 대화가 아예 안 보임 -> 멈춤 점검 없이 절대 마감만 적용"
$d = Run-Fake "no-conversation"
Assert-Equal "  사유는 cap (멈춤으로 오판하지 않음)" "cap" $d.Result.Reason
Assert-True  "  '멈춤 점검 불가' 로그를 남김" (($script:LogLines -join "`n") -match "멈춤 점검 불가")

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
