# serve-viewer.ps1 을 실제로 띄워서, 워처가 꺼져 있을 때 뷰어가 주기적으로 다시 켜는지 확인하는 통합 테스트.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\serve-viewer-autostart.tests.ps1
# 임시 폴더, 가짜 start-agy.ps1 / ensure-agy-running.ps1(호출 기록만 남김), 점검 주기 3초로 돌립니다.
# 실제 워처/뷰어/agy 는 건드리지 않습니다(환경변수 AGY_DELEGATE_RUNTIME / AGY_DELEGATE_SCRIPTS 로 가리킴).
# 전체 약 1분 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$viewerScript = Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("serve-viewer-autostart-test-" + [Guid]::NewGuid().ToString("N"))
$runtime = Join-Path $work "runtime"
$scripts = Join-Path $work "scripts"
$handoff = Join-Path $work "handoff"
New-Item -ItemType Directory -Force -Path (Join-Path $work "data"), (Join-Path $runtime "logs"), (Join-Path $runtime "heartbeat"), (Join-Path $runtime "inbox"), (Join-Path $scripts "sub"), $handoff | Out-Null
Set-Content -Path (Join-Path $work "data\delegate.db") -Value "" -NoNewline -Encoding ASCII    # 빈 파일도 빈 SQLite DB 로 읽힌다

$ensureLog = Join-Path $work "ensure-calls.txt"
$startLog  = Join-Path $work "start-calls.txt"
# 가짜: 호출됐다는 기록만 남기고 끝난다. (실제 워처를 띄우지 않는다)
Set-Content -Path (Join-Path $scripts "start-agy.ps1") -Encoding ASCII -Value @'
param([switch]$Hidden)
Add-Content -Path $env:FAKE_START_LOG -Value ("start hidden=" + [bool]$Hidden + " " + (Get-Date -Format o))
'@
Set-Content -Path (Join-Path $scripts "sub\ensure-agy-running.ps1") -Encoding ASCII -Value @'
param([string]$RuntimeDir = "", [int]$ConfirmDelaySeconds = -1, [int]$StaleThresholdSeconds = 300)
Add-Content -Path $env:FAKE_ENSURE_LOG -Value ("ensure " + $RuntimeDir + " delay=" + $ConfirmDelaySeconds + " stale=" + $StaleThresholdSeconds)
'@

$env:AGY_DELEGATE_RUNTIME = $runtime
$env:AGY_DELEGATE_SCRIPTS = $scripts
$env:FAKE_ENSURE_LOG = $ensureLog
$env:FAKE_START_LOG  = $startLog

$port = Get-Random -Minimum 30000 -Maximum 40000
$lockFile = Join-Path $runtime ("watcher_{0}.lock" -f $env:COMPUTERNAME)
$hbFile   = Join-Path $runtime ("heartbeat\hb_{0}.txt" -f $env:COMPUTERNAME)
$flagFile = Join-Path $runtime "manual_stop.flag"

function Get-Status {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/status" -TimeoutSec 5
        return ($r.Content | ConvertFrom-Json)
    } catch { return $null }
}
function Get-CallCount($file) {
    if (Test-Path $file) { return @(Get-Content $file).Count } else { return 0 }
}
function Wait-Until([scriptblock]$cond, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (& $cond) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

$viewer = $null
try {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$viewerScript`"", "-NoBrowser", "-Port", "$port",
                 "-WatcherCheckSeconds", "3", "-HandoffDir", "`"$handoff`"")
    $viewer = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden -PassThru

    Write-Host "A) 시작 직후: 워처가 꺼져 있다"
    $up = Wait-Until { $null -ne (Get-Status) } 30
    Assert-Equal "  뷰어가 응답한다" $true $up
    $st = Get-Status
    Assert-Equal "  watcherAlive = false" $false $st.watcherAlive
    Assert-Equal "  manualStop = false" $false $st.manualStop
    Assert-Equal "  autoRestart.enabled = true" $true $st.autoRestart.enabled
    Assert-Equal "  autoRestart.intervalSeconds = 3" 3 $st.autoRestart.intervalSeconds
    Assert-Equal "  canStart = true (켜기 버튼을 보여도 됨)" $true $st.canStart
    Assert-Equal "  시작 시 start-agy.ps1 을 한 번 호출했다" 1 (Get-CallCount $startLog)
    $startLine = if (Test-Path $startLog) { (Get-Content $startLog | Select-Object -First 1) } else { "" }
    Assert-Equal "  -Hidden(창 없이)로 불렀다(없으면 -NoExit 콘솔 창이 뜬다)" $true ($startLine -match 'hidden=True')

    Write-Host "B) 주기 점검이 꺼진 워처를 보고 ensure-agy-running.ps1 을 띄운다 (요청이 없어도)"
    $called = Wait-Until { (Get-CallCount $ensureLog) -ge 1 } 20
    Assert-Equal "  ensure 가 호출됐다" $true $called
    $line = if (Test-Path $ensureLog) { (Get-Content $ensureLog | Select-Object -First 1) } else { "" }
    Assert-Equal "  런타임 폴더와 하트비트 유예 0을 넘겼다 (자동 점검은 재확인 대기를 기본값으로 둠)" ("ensure " + $runtime + " delay=-1 stale=0") $line
    $st = Get-Status
    Assert-Equal "  status 가 실행 횟수를 보여 준다 (>=1)" $true ([int]$st.autoRestart.launchCount -ge 1)
    Assert-Equal "  status 에 마지막 실행 시각이 있다" $true ([bool]$st.autoRestart.lastLaunch)

    Write-Host "C) 워처가 살아 있으면(잠금 PID) 더 띄우지 않는다. 하트비트가 30분 낡아도 켜짐으로 본다"
    "$PID" | Set-Content -Path $lockFile -Encoding UTF8
    "x" | Set-Content -Path $hbFile -Encoding UTF8
    (Get-Item $hbFile).LastWriteTime = (Get-Date).AddMinutes(-30)
    Start-Sleep -Seconds 4   # 점검 한 번 지나가게 둔다(진행 중이던 ensure 가 있으면 끝나도록)
    $before = Get-CallCount $ensureLog
    $st = Get-Status
    Assert-Equal "  watcherAlive = true" $true $st.watcherAlive
    Assert-Equal "  근거는 lock" "lock" $st.watcherSource
    Start-Sleep -Seconds 8
    Assert-Equal "  8초(점검 2~3번) 동안 ensure 호출이 늘지 않았다" $before (Get-CallCount $ensureLog)

    Write-Host "D) stop-agy 로 끈 상태(manual_stop.flag)면 켜지 않는다"
    Remove-Item $lockFile -Force
    "stopped" | Set-Content -Path $flagFile -Encoding UTF8
    Start-Sleep -Seconds 4
    $before = Get-CallCount $ensureLog
    $st = Get-Status
    Assert-Equal "  watcherAlive = false" $false $st.watcherAlive
    Assert-Equal "  manualStop = true" $true $st.manualStop
    Start-Sleep -Seconds 8
    Assert-Equal "  8초 동안 ensure 호출이 늘지 않았다" $before (Get-CallCount $ensureLog)

    Write-Host "E) 수동 정지가 풀리면 다시 점검해서 켠다"
    Remove-Item $flagFile -Force
    $resumed = Wait-Until { (Get-CallCount $ensureLog) -gt $before } 15
    Assert-Equal "  ensure 가 다시 호출됐다" $true $resumed

    Write-Host "F) 점검이 도는 동안에도 다른 API 요청이 정상으로 응답한다"
    $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/delegate/pending" -TimeoutSec 5
    Assert-Equal "  /api/delegate/pending 200" 200 $r.StatusCode
    $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/" -TimeoutSec 5
    Assert-Equal "  / (index.html) 200" 200 $r.StatusCode

    Write-Host "G) 화면의 켜기 버튼 (POST /api/watcher/start)"
    function Send-Start([bool]$withHeader, [string]$method = "POST") {
        $headers = @{}
        if ($withHeader) { $headers["X-Samjil-Viewer"] = "1" }
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Method $method -Headers $headers -Uri "http://127.0.0.1:$port/api/watcher/start" -TimeoutSec 5
            return @{ Status = [int]$r.StatusCode; Body = ($r.Content | ConvertFrom-Json) }
        } catch {
            return @{ Status = [int]$_.Exception.Response.StatusCode; Body = $null }
        }
    }
    Assert-Equal "  GET 은 405" 405 (Send-Start $true "GET").Status
    Assert-Equal "  전용 헤더가 없는 POST 는 403 (다른 웹 페이지의 단순 요청 차단)" 403 (Send-Start $false).Status

    "$PID" | Set-Content -Path $lockFile -Encoding UTF8
    $res = Send-Start $true
    Assert-Equal "  켜져 있으면 already-running" "already-running" $res.Body.result
    Remove-Item $lockFile -Force

    "stopped" | Set-Content -Path $flagFile -Encoding UTF8
    $before = Get-CallCount $ensureLog
    $res = Send-Start $true
    Assert-Equal "  꺼져 있으면 200 + started" "started" $res.Body.result
    $called = Wait-Until { (Get-CallCount $ensureLog) -gt $before } 15
    Assert-Equal "  ensure 가 호출됐다" $true $called
    $last = (Get-Content $ensureLog | Select-Object -Last 1)
    Assert-Equal "  재확인 대기 0초로 호출됐다 (바로 켬)" ("ensure " + $runtime + " delay=0 stale=0") $last
    Assert-Equal "  수동 정지 플래그를 지웠다 (직접 누른 것이므로)" $false (Test-Path $flagFile)
}
finally {
    if ($viewer -and -not $viewer.HasExited) { Stop-Process -Id $viewer.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
