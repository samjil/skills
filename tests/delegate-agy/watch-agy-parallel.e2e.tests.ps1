# watch-agy.ps1 이 작업을 동시에 돌리는지 확인하는 종단 시험.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\watch-agy-parallel.e2e.tests.ps1
# 임시 런타임 폴더(-RuntimeDir)와 가짜 agy(agy.cmd, PATH 맨 앞)만 씁니다. 이 PC에 진짜 워처가 떠 있어도 건드리지 않습니다.
# 가짜 agy 는 지시문의 "TAG:<이름> SLEEP:<초>" 를 읽어 그만큼 자고, 시작·끝 시각을 파일에 남깁니다. 약 2분 걸립니다.
#
# 확인하는 규칙: 같은 @session 이면서 @cwd 가 겹치는 작업끼리만 차례로 하고, 나머지(세션이 다르거나, 같은 세션이어도 폴더가 다르면)는
# 함께 돌린다. 동시에 도는 수는 -MaxParallel(기본 3)까지.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$watcher  = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\watch-agy.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("watch-agy-parallel-e2e-" + [Guid]::NewGuid().ToString("N"))
$rt = Join-Path $work "runtime"
$fakeBin = Join-Path $work "bin"
$timesDir = Join-Path $work "times"
foreach ($d in @("inbox", "outbox", "processed", "logs", "logs\data", "logs\heartbeat")) { New-Item -ItemType Directory -Force -Path (Join-Path $rt $d) | Out-Null }
New-Item -ItemType Directory -Force -Path $fakeBin, $timesDir, (Join-Path $work "agyhome\conversations") | Out-Null
$dirA = Join-Path $work "space-a"; $dirB = Join-Path $work "space-b"
New-Item -ItemType Directory -Force -Path $dirA, $dirB | Out-Null

Set-Content -Path (Join-Path $fakeBin "fake-agy.ps1") -Encoding ASCII -Value @'
$a = @($args)
$pi = [Array]::IndexOf([string[]]$a, '-p')
$prompt = [string]$a[$pi + 1]
if ($prompt.StartsWith('@')) { $prompt = [System.IO.File]::ReadAllText($prompt.Substring(1)) }
$tag = 'x'; if ($prompt -match 'TAG:(\S+)') { $tag = $Matches[1] }
$sec = 1; if ($prompt -match 'SLEEP:(\d+)') { $sec = [int]$Matches[1] }
if ($prompt -match 'NOISE') { [Console]::Error.WriteLine('stderr-noise-from-agy') }   # 성공했는데 agy 가 표준오류에 잡음을 남기는 경우
[System.IO.File]::WriteAllText((Join-Path $env:FAKE_TIMES_DIR "$tag.prompt"), $prompt)
[System.IO.File]::WriteAllText((Join-Path $env:FAKE_TIMES_DIR "$tag.start"), [string][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
Start-Sleep -Seconds $sec
[System.IO.File]::WriteAllText((Join-Path $env:FAKE_TIMES_DIR "$tag.end"), [string][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
'{"status":"SUCCESS","response":"done ' + $tag + '","conversation_id":"conv-' + $tag + '","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}'
'@
Set-Content -Path (Join-Path $fakeBin "agy.cmd") -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake-agy.ps1`" %*"

$env:PATH = "$fakeBin;$env:PATH"
$env:AGY_HOME = Join-Path $work "agyhome"
$env:FAKE_TIMES_DIR = $timesDir

function Send-Task([string]$name, [string]$tagSleep, [string]$session = "", [string]$cwd = "", [string]$bodyPrefix = "") {
    $head = ""
    if ($session) { $head += "@session: $session`n" }
    if ($cwd) { $head += "@cwd: $cwd`n" }
    [System.IO.File]::WriteAllText((Join-Path $rt "inbox\$name.md"), ($head + $bodyPrefix + "TAG:$name $tagSleep"), (New-Object System.Text.UTF8Encoding($false)))
}
function Wait-Done([string[]]$names, [int]$seconds = 90) {
    $until = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $until) {
        $left = @($names | Where-Object { -not (Test-Path (Join-Path $rt "outbox\$_.response.md")) -and -not (Test-Path (Join-Path $rt "processed\$_.md")) })
        if ($left.Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}
function Wait-ClaimGone([string[]]$names, [int]$seconds = 30) {
    $until = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $until) {
        $left = @($names | Where-Object { Test-Path (Join-Path $rt "logs\running\$_.json") })
        if ($left.Count -eq 0) { return }
        Start-Sleep -Milliseconds 300
    }
}
function Get-Time([string]$tag, [string]$kind) {
    $f = Join-Path $timesDir "$tag.$kind"
    if (Test-Path $f) { return [long]([System.IO.File]::ReadAllText($f).Trim()) } else { return $null }
}
function Test-Overlap([string]$a, [string]$b) {
    $sa = Get-Time $a "start"; $ea = Get-Time $a "end"; $sb = Get-Time $b "start"; $eb = Get-Time $b "end"
    if ($null -in @($sa, $ea, $sb, $eb)) { return $false }
    return ($sa -lt $eb -and $sb -lt $ea)
}
function Get-MaxConcurrent([string[]]$tags) {
    $events = @()
    foreach ($t in $tags) {
        $s = Get-Time $t "start"; $e = Get-Time $t "end"
        if ($null -ne $s -and $null -ne $e) { $events += [pscustomobject]@{ T = $s; D = 1 }; $events += [pscustomobject]@{ T = $e; D = -1 } }
    }
    $cur = 0; $max = 0
    foreach ($ev in ($events | Sort-Object T, D)) { $cur += $ev.D; if ($cur -gt $max) { $max = $cur } }
    return $max
}

$proc = $null
try {
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$watcher`"", "-RuntimeDir", "`"$rt`"", "-MaxParallel", "3") -WindowStyle Hidden -PassThru
    $lock = Join-Path $rt ("logs\watcher_{0}.lock" -f $env:COMPUTERNAME)
    $until = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $until -and -not (Test-Path $lock)) { Start-Sleep -Milliseconds 300 }
    Assert-Equal "워처가 떴다(잠금 파일)" $true (Test-Path $lock)

    Write-Host "세션이 없는 작업끼리는 함께 돈다"
    Send-Task "a1" "SLEEP:6"; Send-Task "a2" "SLEEP:6"
    # 도는 동안 표시 파일(logs\running\<작업 ID>.json)이 있고 PID 가 살아 있다
    $claim = $null
    $until = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $until -and $null -eq $claim) {
        $cf = Join-Path $rt "logs\running\a1.json"
        if ((Test-Path $cf) -and $null -ne (Get-Time "a1" "start")) { try { $claim = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($cf, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)) } catch {} }
        Start-Sleep -Milliseconds 300
    }
    Assert-Equal "  도는 동안 표시 파일이 있고 작업자 PID 가 살아 있다" $true ($null -ne $claim -and [int]$claim.pid -gt 0 -and $null -ne (Get-Process -Id ([int]$claim.pid) -ErrorAction SilentlyContinue))
    Assert-Equal "  표시 파일에 모델이 적힌다" $true ($null -ne $claim -and [bool]$claim.model)
    Assert-Equal "  둘 다 끝난다" $true (Wait-Done @("a1", "a2"))
    Assert-Equal "  두 작업의 실행 시간이 겹친다(동시에 돌았다)" $true (Test-Overlap "a1" "a2")
    # 답변 파일이 먼저 생기고 기록 갱신 뒤에 표시 파일이 지워지므로 잠깐 기다린다
    Wait-ClaimGone @("a1", "a2")
    Assert-Equal "  끝나면 표시 파일이 사라진다" $false ((Test-Path (Join-Path $rt "logs\running\a1.json")) -or (Test-Path (Join-Path $rt "logs\running\a2.json")))
    Assert-Equal "  답변 파일에 각자의 답이 들어 있다" "done a1|done a2" ((Get-Content -Raw -Encoding UTF8 (Join-Path $rt "outbox\a1.response.md")).Trim([char]0xFEFF, " ", "`r", "`n") + "|" + (Get-Content -Raw -Encoding UTF8 (Join-Path $rt "outbox\a2.response.md")).Trim([char]0xFEFF, " ", "`r", "`n"))

    Write-Host "같은 세션이고 폴더도 같으면 차례로 한다"
    Send-Task "b1" "SLEEP:5" "sess-b" $dirA; Start-Sleep -Milliseconds 1200; Send-Task "b2" "SLEEP:2" "sess-b" $dirA   # 파일 수정 시각이 달라야 "먼저 보낸 것"이 분명하다
    Assert-Equal "  둘 다 끝난다" $true (Wait-Done @("b1", "b2"))
    Assert-Equal "  겹치지 않는다" $false (Test-Overlap "b1" "b2")
    Assert-Equal "  먼저 보낸 b1 이 먼저 끝나고 b2 가 그 뒤에 시작한다" $true ((Get-Time "b2" "start") -ge (Get-Time "b1" "end"))

    Write-Host "같은 세션이어도 폴더가 다르면 함께 돈다"
    Send-Task "c1" "SLEEP:6" "sess-c" $dirA; Send-Task "c2" "SLEEP:6" "sess-c" $dirB
    Assert-Equal "  둘 다 끝난다" $true (Wait-Done @("c1", "c2"))
    Assert-Equal "  실행 시간이 겹친다" $true (Test-Overlap "c1" "c2")
    Wait-ClaimGone @("c1", "c2")
    $logC = Get-Content -Raw -Encoding UTF8 (Join-Path $rt "logs\watcher.log")
    Assert-Equal "  같은 세션을 다른 폴더에서 함께 돌리면 '맥락이 섞일 수 있다'는 주의가 로그에 한 번 남는다" 1 ([regex]::Matches($logC, "주의: 세션 'sess-c'").Count)

    Write-Host "세션이 다르면 같은 폴더여도 함께 돈다"
    Send-Task "d1" "SLEEP:6" "sess-d1" $dirA; Send-Task "d2" "SLEEP:6" "sess-d2" $dirA
    Assert-Equal "  둘 다 끝난다" $true (Wait-Done @("d1", "d2"))
    Assert-Equal "  실행 시간이 겹친다" $true (Test-Overlap "d1" "d2")
    Wait-ClaimGone @("d1", "d2")
    $logD = Get-Content -Raw -Encoding UTF8 (Join-Path $rt "logs\watcher.log")
    Assert-Equal "  세션이 다르면 주의를 남기지 않는다" 0 ([regex]::Matches($logD, "주의: 세션 'sess-d").Count)

    Write-Host "한 폴더가 다른 폴더의 상위이면 겹치는 것으로 본다(같은 세션이면 차례로)"
    $sub = Join-Path $dirA "sub"; New-Item -ItemType Directory -Force -Path $sub | Out-Null
    Send-Task "e1" "SLEEP:5" "sess-e" $dirA; Send-Task "e2" "SLEEP:2" "sess-e" $sub
    Assert-Equal "  둘 다 끝난다" $true (Wait-Done @("e1", "e2"))
    Assert-Equal "  겹치지 않는다" $false (Test-Overlap "e1" "e2")

    Write-Host "agy 가 표준오류에 잡음을 남겨도 응답 파일이 먼저 생긴다(점검 루프가 비어 있지 않은 error.log 를 먼저 보고 오류로 끝내지 않게)"
    Send-Task "n1" "SLEEP:1 NOISE"
    Assert-Equal "  처리된다" $true (Wait-Done @("n1"))
    Wait-ClaimGone @("n1")
    $respN = Join-Path $rt "outbox\n1.response.md"; $errN = Join-Path $rt "outbox\n1.error.log"
    Assert-Equal "  응답 파일이 있다" $true (Test-Path $respN)
    Assert-Equal "  error.log 에 agy 의 표준오류가 담긴다" $true ((Test-Path $errN) -and ([System.IO.File]::ReadAllText($errN) -like "*stderr-noise-from-agy*"))
    Assert-Equal "  응답 파일이 error.log 보다 먼저(또는 같은 때) 써진다" $true ((Test-Path $respN) -and (Test-Path $errN) -and ((Get-Item $respN).LastWriteTimeUtc -le (Get-Item $errN).LastWriteTimeUtc))

    Write-Host "지시문 맨 앞의 언어 규칙 문단은 agy 에 넘기지 않고 지시파일에서도 뺀다"
    $ruleText = "[언어 규칙 — 가장 먼저 지킨다] 너의 내부 생각(thinking)과 모든 도구 호출 설명, 답변을 처음부터 끝까지 한국어로 쓴다. (코드·경로·명령어·식별자만 원문 그대로)`n"
    Send-Task "r1" "SLEEP:1" "" $dirA $ruleText
    Assert-Equal "  처리된다" $true (Wait-Done @("r1"))
    Wait-ClaimGone @("r1")   # 응답 파일이 먼저 생기고 지시파일은 그 직후에 processed 로 옮겨진다
    $promptR1 = if (Test-Path (Join-Path $timesDir "r1.prompt")) { [System.IO.File]::ReadAllText((Join-Path $timesDir "r1.prompt")) } else { "" }
    Assert-Equal "  agy 가 받은 질문에 언어 규칙 문단이 없다" $false (($promptR1 -like "*언어 규칙*") -or ($promptR1 -like "*(thinking)*"))
    Assert-Equal "  본문(TAG 줄)은 그대로 전달된다" $true ($promptR1 -like "*TAG:r1*")
    $processedR1 = Join-Path $rt "processed\r1.md"
    Assert-Equal "  처리된 지시파일에도 문단이 없다(뷰어에 안 보인다)" $false ((Test-Path $processedR1) -and ([System.IO.File]::ReadAllText($processedR1) -like "*언어 규칙*"))
    Assert-Equal "  @cwd 줄은 그대로 남는다" $true ((Test-Path $processedR1) -and ([System.IO.File]::ReadAllText($processedR1) -like "*@cwd:*"))

    Write-Host "동시에 도는 수는 -MaxParallel(3)까지"
    $tags = @("f1", "f2", "f3", "f4", "f5")
    foreach ($t in $tags) { Send-Task $t "SLEEP:5" }
    Assert-Equal "  모두 끝난다" $true (Wait-Done $tags 120)
    Assert-Equal "  한꺼번에 도는 최대 수가 3 이다" 3 (Get-MaxConcurrent $tags)

    Write-Host "작업자가 끝내지 못하고 사라지면 실패로 남기고 다시 시도하지 않는다"
    $deadClaim = Join-Path $rt "logs\running\g1.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $deadClaim) | Out-Null
    [System.IO.File]::WriteAllText($deadClaim, '{"task_id":"g1","pid":999999,"session":"","cwds":[],"started":"2026-10-14 00:00:00"}', (New-Object System.Text.UTF8Encoding($false)))
    Send-Task "g1" "SLEEP:1"
    Assert-Equal "  실패 처리되어 processed 로 옮겨진다" $true (Wait-Done @("g1") 40)
    $g1 = Join-Path $rt "outbox\g1.response.md"
    Assert-Equal "  오류 답변이 남는다" $true ((Test-Path $g1) -and ((Get-Content -Raw -Encoding UTF8 $g1) -like "*사라졌습니다*"))
    Assert-Equal "  agy 는 부르지 않았다" $null (Get-Time "g1" "start")
    Wait-ClaimGone @("g1")
    Assert-Equal "  표시 파일이 지워진다" $false (Test-Path $deadClaim)

    Write-Host "정지 신호: 도는 작업은 끝까지 기다렸다가 끝난다"
    Send-Task "h1" "SLEEP:8"
    $until = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $until -and $null -eq (Get-Time "h1" "start")) { Start-Sleep -Milliseconds 300 }
    "stop" | Set-Content -Path (Join-Path $rt "logs\stop.signal") -Encoding UTF8
    Start-Sleep -Seconds 3
    Assert-Equal "  작업이 도는 동안에는 워처가 살아 있다" $false $proc.HasExited
    Assert-Equal "  작업이 끝나고" $true (Wait-Done @("h1") 40)
    $proc.WaitForExit(30000) | Out-Null
    Assert-Equal "  워처가 종료된다" $true $proc.HasExited
    $log = Get-Content -Raw -Encoding UTF8 (Join-Path $rt "logs\watcher.log")
    Assert-Equal "  로그에 정지 신호 감지가 남는다" $true ($log -like "*정지 신호 파일 감지*")
    Assert-Equal "  로그 줄에 작업 ID 표시가 붙는다" $true ($log -like "*[h1] *")
}
finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    # 남은 작업자 프로세스(임시 런타임 것)를 정리한다
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*agy-task-worker.ps1*" -and $_.CommandLine -like "*$work*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
