# watcher-health.ps1 의 판정 로직 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\watcher-health.tests.ps1
# 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다. 실제 워처/뷰어는 건드리지 않습니다(임시 폴더만 사용).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\viewer\watcher-health.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("watcher-health-test-" + [Guid]::NewGuid().ToString("N"))
$computer = "TESTPC"
function New-Runtime {
    $rt = Join-Path $work ([Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path (Join-Path $rt "heartbeat"), (Join-Path $rt "logs\data") | Out-Null
    return $rt
}
function Set-Lock($rt, $pidValue, $written) {
    $f = Join-Path $rt "watcher_$computer.lock"
    "$pidValue" | Set-Content -Path $f -Encoding UTF8
    if ($written) { (Get-Item $f).LastWriteTime = $written }
}
function Set-Heartbeat($rt, [datetime]$written) {
    $f = Join-Path $rt "heartbeat\hb_$computer.txt"
    "x" | Set-Content -Path $f -Encoding UTF8
    (Get-Item $f).LastWriteTime = $written
}
$noProcs   = { @() }
$someProcs = { @([pscustomobject]@{ ProcessId = 1 }) }

Write-Host "Get-WatcherRuntimeDir"
Assert-Equal "데이터 폴더 옆의 runtime 이 런타임 폴더" "C:\x\runtime" (Get-WatcherRuntimeDir "C:\x\data")

Write-Host "Test-WatcherAlive: 잠금 파일"
$rt = New-Runtime
$r = Test-WatcherAlive -RuntimeDir $rt -ComputerName $computer -GetWatcherProcesses $noProcs
Assert-Equal "아무 흔적도 없으면 꺼짐" $false $r.Alive

Set-Lock $rt $PID (Get-Date)
$r = Test-WatcherAlive -RuntimeDir $rt -ComputerName $computer -GetWatcherProcesses $noProcs
Assert-Equal "잠금 PID가 살아 있는 powershell 이면 켜짐" $true $r.Alive
Assert-Equal "  근거는 lock" "lock" $r.Source
Assert-Equal "  PID를 돌려줌" $PID $r.Pid

$gone = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-Command", "exit 0" -WindowStyle Hidden -PassThru
$gone.WaitForExit()
Set-Lock $rt $gone.Id (Get-Date)
$r = Test-WatcherAlive -RuntimeDir $rt -ComputerName $computer -GetWatcherProcesses $noProcs
Assert-Equal "잠금 PID의 프로세스가 이미 끝났으면 꺼짐" $false $r.Alive

$other = Start-Process -FilePath "ping.exe" -ArgumentList "-n", "20", "127.0.0.1" -WindowStyle Hidden -PassThru
try {
    Set-Lock $rt $other.Id (Get-Date)
    $r = Test-WatcherAlive -RuntimeDir $rt -ComputerName $computer -GetWatcherProcesses $noProcs
    Assert-Equal "잠금 PID가 powershell 이 아닌 프로세스(PID 재사용)면 꺼짐" $false $r.Alive
} finally { Stop-Process -Id $other.Id -Force -ErrorAction SilentlyContinue }

$myStart = (Get-Process -Id $PID).StartTime
Set-Lock $rt $PID $myStart.AddHours(-1)
$r = Test-WatcherAlive -RuntimeDir $rt -ComputerName $computer -GetWatcherProcesses $noProcs
Assert-Equal "PID가 같은 powershell 이어도 잠금 파일보다 늦게 시작했으면(PID 재사용) 꺼짐" $false $r.Alive

Write-Host "Test-WatcherAlive: 하트비트와의 관계"
$rt = New-Runtime
Set-Lock $rt $PID (Get-Date)
Set-Heartbeat $rt (Get-Date).AddMinutes(-30)
$r = Test-WatcherAlive -RuntimeDir $rt -ComputerName $computer -GetWatcherProcesses $noProcs
Assert-Equal "agy 를 기다리느라 하트비트가 30분 낡았어도 잠금 PID가 살아 있으면 켜짐" $true $r.Alive

$rt = New-Runtime
Set-Heartbeat $rt (Get-Date).AddSeconds(-10)
$r = Test-WatcherAlive -RuntimeDir $rt -ComputerName $computer -GetWatcherProcesses $noProcs
Assert-Equal "잠금 없음 + 하트비트 최근 + 워처 프로세스 없음 = 꺼짐 (죽은 직후 하트비트 잔존)" $false $r.Alive
$r = Test-WatcherAlive -RuntimeDir $rt -ComputerName $computer -GetWatcherProcesses $someProcs
Assert-Equal "잠금 없음 + 하트비트 최근 + 워처 프로세스 있음 = 켜짐" $true $r.Alive
Assert-Equal "  근거는 process+heartbeat" "process+heartbeat" $r.Source

$rt = New-Runtime
Set-Heartbeat $rt (Get-Date).AddMinutes(-10)
$r = Test-WatcherAlive -RuntimeDir $rt -ComputerName $computer -GetWatcherProcesses $someProcs
Assert-Equal "잠금 없음 + 하트비트 10분 전 = 프로세스가 보여도 꺼짐" $false $r.Alive

Write-Host "Test-WatcherManualStop"
$rt = New-Runtime
Assert-Equal "플래그 없으면 false" $false (Test-WatcherManualStop $rt)
"x" | Set-Content (Join-Path $rt "manual_stop.flag")
Assert-Equal "manual_stop.flag 있으면 true" $true (Test-WatcherManualStop $rt)

Write-Host "Get-WatcherAutoStartDecision"
Assert-Equal "살아 있으면 ok" "ok" (Get-WatcherAutoStartDecision $true $false $true $false)
Assert-Equal "살아 있으면 수동 정지 플래그가 있어도 ok (정지 중)" "ok" (Get-WatcherAutoStartDecision $true $true $true $false)
Assert-Equal "죽었고 수동 정지면 manual-stop" "manual-stop" (Get-WatcherAutoStartDecision $false $true $true $false)
Assert-Equal "죽었고 스크립트가 없으면 no-script" "no-script" (Get-WatcherAutoStartDecision $false $false $false $false)
Assert-Equal "죽었고 이전 ensure 가 아직 돌면 ensure-running" "ensure-running" (Get-WatcherAutoStartDecision $false $false $true $true)
Assert-Equal "죽었고 아무 제약이 없으면 restart" "restart" (Get-WatcherAutoStartDecision $false $false $true $false)

Write-Host "serve-viewer.ps1 기본값"
$vt = $null; $ve = $null
$vast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"), [ref]$vt, [ref]$ve)
$vparam = $vast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "WatcherCheckSeconds" }
Assert-Equal "-WatcherCheckSeconds 기본값은 60초" "60" ($vparam.DefaultValue.Extent.Text)

Write-Host "Invoke-WatcherHealthTick"
$script:Launched = @()
$launcher = { param($s, $r) $script:Launched += ,@($s, $r); return [pscustomobject]@{ HasExited = $false } }
$t0 = [datetime]"2026-10-12 12:00:00"
$rt = New-Runtime
$st = New-WatcherHealthState -RuntimeDir $rt -EnsureScript "C:\fake\ensure.ps1" -IntervalSeconds 300 -Now $t0 -GetWatcherProcesses $noProcs -ComputerName $computer

Assert-Equal "주기가 안 됐으면 점검하지 않는다 (`$null)" $true ($null -eq (Invoke-WatcherHealthTick $st $t0.AddSeconds(299) $launcher))
Assert-Equal "  실행도 없음" 0 $script:Launched.Count

# 죽은 상태(잠금/하트비트 없음)에서 주기가 되면 재시작
$d = Invoke-WatcherHealthTick $st $t0.AddSeconds(300) $launcher
Assert-Equal "주기가 되고 죽어 있으면 restart" "restart" $d
Assert-Equal "  ensure 를 한 번 띄움" 1 $script:Launched.Count
Assert-Equal "  ensure 스크립트 경로를 넘김" "C:\fake\ensure.ps1" $script:Launched[0][0]
Assert-Equal "  런타임 폴더를 넘김" $rt $script:Launched[0][1]
Assert-Equal "  실행 횟수 기록" 1 $st.LaunchCount

Assert-Equal "방금 점검했으니 바로 다음 호출은 점검하지 않는다" $true ($null -eq (Invoke-WatcherHealthTick $st $t0.AddSeconds(301) $launcher))

# 이전 ensure 가 아직 도는 중이면(HasExited=false) 두 번째로 띄우지 않는다
$d = Invoke-WatcherHealthTick $st $t0.AddSeconds(600) $launcher
Assert-Equal "이전 ensure 가 아직 돌면 ensure-running" "ensure-running" $d
Assert-Equal "  추가 실행 없음" 1 $script:Launched.Count

# ensure 가 끝났는데도 여전히 죽어 있으면 다시 시도
$st.EnsureProcess = [pscustomobject]@{ HasExited = $true }
$d = Invoke-WatcherHealthTick $st $t0.AddSeconds(900) $launcher
Assert-Equal "ensure 가 끝났는데 여전히 죽어 있으면 다시 restart" "restart" $d
Assert-Equal "  실행 2회" 2 $script:Launched.Count

# 살아 있으면 아무것도 안 함
Set-Lock $rt $PID (Get-Date)
$d = Invoke-WatcherHealthTick $st $t0.AddSeconds(1200) $launcher
Assert-Equal "살아 있으면 ok" "ok" $d
Assert-Equal "  추가 실행 없음" 2 $script:Launched.Count
Remove-Item (Join-Path $rt "watcher_$computer.lock") -Force

# 수동 정지
"x" | Set-Content (Join-Path $rt "manual_stop.flag")
$st.EnsureProcess = $null
$d = Invoke-WatcherHealthTick $st $t0.AddSeconds(1500) $launcher
Assert-Equal "수동 정지 중이면 manual-stop" "manual-stop" $d
Assert-Equal "  추가 실행 없음" 2 $script:Launched.Count
Remove-Item (Join-Path $rt "manual_stop.flag") -Force

# 스크립트를 못 찾음
$st2 = New-WatcherHealthState -RuntimeDir $rt -EnsureScript "" -IntervalSeconds 60 -Now $t0 -GetWatcherProcesses $noProcs -ComputerName $computer
$d = Invoke-WatcherHealthTick $st2 $t0.AddSeconds(60) $launcher
Assert-Equal "ensure 스크립트가 없으면 no-script" "no-script" $d
Assert-Equal "  추가 실행 없음" 2 $script:Launched.Count

# 실행 실패
$boom = { param($s, $r) throw "실행 실패" }
$st3 = New-WatcherHealthState -RuntimeDir $rt -EnsureScript "C:\fake\ensure.ps1" -IntervalSeconds 60 -Now $t0 -GetWatcherProcesses $noProcs -ComputerName $computer
$d = Invoke-WatcherHealthTick $st3 $t0.AddSeconds(60) $boom
Assert-Equal "실행에 실패하면 launch-failed 로 알린다" $true ($d -like "launch-failed:*")
Assert-Equal "  실행 횟수는 늘지 않음" 0 $st3.LaunchCount

Write-Host "New-WatcherHealthState: 주기 0 = 자동 점검 없음"
$st0 = New-WatcherHealthState -RuntimeDir $rt -EnsureScript "C:\fake\ensure.ps1" -IntervalSeconds 0 -Now $t0 -GetWatcherProcesses $noProcs -ComputerName $computer
Assert-Equal "주기 0 이면 아주 먼 미래에도 점검하지 않는다" $true ($null -eq (Invoke-WatcherHealthTick $st0 $t0.AddDays(30) $launcher))

Write-Host "Get-EnsureWatcherArguments"
$a1 = Get-EnsureWatcherArguments "C:\x y\ensure.ps1" "C:\rt dir" -1
Assert-Equal "하트비트 유예를 끈다 (-StaleThresholdSeconds 0)" $true ($a1 -like "*-StaleThresholdSeconds 0*")
Assert-Equal "자동 점검은 재확인 대기 인자를 넘기지 않는다 (ensure 기본 20초)" $false ($a1 -like "*ConfirmDelaySeconds*")
Assert-Equal "공백 있는 경로는 따옴표로 감싼다" $true (($a1 -like '*-File "C:\x y\ensure.ps1"*') -and ($a1 -like '*-RuntimeDir "C:\rt dir"*'))
$a2 = Get-EnsureWatcherArguments "C:\e.ps1" "C:\rt" 0
Assert-Equal "켜기는 재확인 대기 0초를 넘긴다" $true ($a2 -like "*-ConfirmDelaySeconds 0*")

Write-Host "Start-EnsureWatcherProcess: 인자"
# 실제로 띄우지 않고 명령줄 조립만 보기 위해 ProcessStartInfo 를 가로챌 수 없으므로, 존재하지 않는 스크립트로 즉시 끝나는 프로세스를 띄워 종료 코드만 확인한다.
$p = Start-EnsureWatcherProcess (Join-Path $work "no-such.ps1") $work 0
$p.WaitForExit(20000) | Out-Null
Assert-Equal "창 없이 띄운 프로세스가 끝난다 (스크립트가 없으면 오류 종료)" $true $p.HasExited

Write-Host "Invoke-WatcherStartRequest"
$script:Launched = @()
$launcher3 = { param($s, $r, $d) $script:Launched += ,@($s, $r, $d); return [pscustomobject]@{ HasExited = $false } }
$rt = New-Runtime
$mk = { New-WatcherHealthState -RuntimeDir $rt -EnsureScript "C:\fake\ensure.ps1" -IntervalSeconds 300 -Now $t0 -GetWatcherProcesses $noProcs -ComputerName $computer }

$r = Invoke-WatcherStartRequest $null $t0 $launcher3
Assert-Equal "상태가 없으면(-NoAgent) no-script" "no-script" $r.Result
$stNo = & $mk; $stNo.EnsureScript = ""
$r = Invoke-WatcherStartRequest $stNo $t0 $launcher3
Assert-Equal "ensure 스크립트가 없으면 no-script" "no-script" $r.Result
Assert-Equal "  실행 없음" 0 $script:Launched.Count

$stA = & $mk
Set-Lock $rt $PID (Get-Date)
$r = Invoke-WatcherStartRequest $stA $t0 $launcher3
Assert-Equal "이미 켜져 있으면 already-running" "already-running" $r.Result
Assert-Equal "  실행 없음" 0 $script:Launched.Count
Remove-Item (Join-Path $rt "watcher_$computer.lock") -Force

$stB = & $mk
$r = Invoke-WatcherStartRequest $stB $t0 $launcher3
Assert-Equal "꺼져 있으면 started" "started" $r.Result
Assert-Equal "  ensure 한 번 실행" 1 $script:Launched.Count
Assert-Equal "  재확인 대기 0초로 실행" 0 $script:Launched[0][2]
Assert-Equal "  런타임 폴더를 넘김" $rt $script:Launched[0][1]
Assert-Equal "  실행 횟수 기록" 1 $stB.LaunchCount
Assert-Equal "  마지막 결과 manual-start" "manual-start" $stB.LastResult

$r = Invoke-WatcherStartRequest $stB $t0 $launcher3
Assert-Equal "직전에 띄운 ensure 가 아직 돌면 busy" "busy" $r.Result
Assert-Equal "  추가 실행 없음" 1 $script:Launched.Count

$stC = & $mk
"stopped" | Set-Content (Join-Path $rt "manual_stop.flag")
$r = Invoke-WatcherStartRequest $stC $t0 $launcher3
Assert-Equal "수동 정지 중이어도 직접 누르면 started" "started" $r.Result
Assert-Equal "  수동 정지 플래그를 지웠다" $false (Test-Path (Join-Path $rt "manual_stop.flag"))

$stD = & $mk
$r = Invoke-WatcherStartRequest $stD $t0 { param($s, $r, $d) throw "실행 실패" }
Assert-Equal "실행에 실패하면 failed" "failed" $r.Result
Assert-Equal "  메시지에 사유가 있다" $true ($r.Message -like "*실행 실패*")
Assert-Equal "  실행 횟수는 늘지 않음" 0 $stD.LaunchCount

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
