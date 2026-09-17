# restart-agy.ps1
# watch-agy.ps1 워처를 안전하게 재시작합니다.
#
# 순서: (1) 기존 워처가 살아있으면 stop-agy.ps1과 같은 방식으로 정상 종료 신호를 보내고,
#       (2) 워처 프로세스가 실제로 사라질 때까지(=완전히 멈출 때까지) 기다린 뒤,
#       (3) 새 콘솔 창에서 watch-agy.ps1을 다시 시작합니다.
#
# 안전장치: 기존 워처가 오래 걸리는 작업(agy 실행 등)을 처리 중이면 그 작업이 끝나야
# 멈추므로 대기 시간이 길어질 수 있습니다. -WaitSeconds 안에 종료가 확인되지 않으면,
# 워처가 두 개 동시에 떠서 같은 inbox/outbox를 두고 충돌하는 걸 막기 위해 "새로 시작하지
# 않고" 경고만 남기고 중단합니다 - 이 경우 잠시 후 다시 실행해 주세요.
#
# 사용법:
#   .\restart-agy.ps1
#   .\restart-agy.ps1 -WaitSeconds 60   # 대기 시간을 늘리고 싶을 때

param($RepoRoot = (Split-Path -Path $PSScriptRoot -Parent), [string]$RuntimeDir = "", [int]$WaitSeconds = 30)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

if (-not $RuntimeDir) {
    if ($env:AGY_DELEGATE_RUNTIME) {
        $RuntimeDir = $env:AGY_DELEGATE_RUNTIME
    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime")) {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime"
    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\agent-delegate-agy\runtime")) {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\agent-delegate-agy\runtime"
    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\delegate\runtime")) {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate\runtime"
    } elseif (Test-Path (Join-Path $env:USERPROFILE ".agent-delegate\runtime")) {
        $RuntimeDir = Join-Path $env:USERPROFILE ".agent-delegate\runtime"
    } elseif (Test-Path (Join-Path $RepoRoot "runtime")) {
        $RuntimeDir = Join-Path $RepoRoot "runtime"
    } else {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime"
    }
}
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

$LogsDir       = Join-Path $RuntimeDir "logs"
$HeartbeatDir  = Join-Path $LogsDir "heartbeat"
$HeartbeatFile = Join-Path $HeartbeatDir ("hb_{0}.txt" -f $env:COMPUTERNAME)
$WatcherScript = Join-Path $PSScriptRoot "watch-agy.ps1"
$StopScript    = Join-Path $PSScriptRoot "stop-agy.ps1"

if (-not (Test-Path $WatcherScript)) {
    Write-Host "watch-agy.ps1을 찾을 수 없습니다: $WatcherScript"
    exit 1
}

# 워처가 살아있는지 확인합니다.
# 프로세스 목록을 직접 보는 것이 가장 확실하고 즉시 알 수 있어서 이 방법을 먼저 씁니다.
# (하트비트 파일은 주기적으로만 갱신되므로 "방금 죽었는지"를 바로 알기 어렵습니다.)
function Get-WatcherProcessCount {
    try {
        return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*watch-agy.ps1*" }).Count
    } catch {
        return -1   # 프로세스 조회 자체가 막힌 환경
    }
}

function Test-WatcherAlive {
    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*watch-agy.ps1*" })
        if ($procs.Count -gt 0) { return $true }
    } catch {}
    # 프로세스 조회가 막힌 환경을 위한 보조 수단 (하트비트 주기 + 여유).
    if (-not (Test-Path $HeartbeatFile)) { return $false }
    $ageSec = [int]((Get-Date) - (Get-Item $HeartbeatFile).LastWriteTime).TotalSeconds
    return ($ageSec -le 30)
}

if (Test-WatcherAlive) {
    Write-Host "기존 워처가 실행 중인 것으로 보입니다 - 정상 종료를 요청합니다..."

    if (Test-Path $StopScript) {
        & $StopScript -RepoRoot $RepoRoot -RuntimeDir $RuntimeDir | Out-Null
    } else {
        New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
        "stop requested at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |
            Set-Content -Path (Join-Path $LogsDir "stop.signal") -Encoding UTF8
    }

    $n = Get-WatcherProcessCount
    if ($n -gt 1) {
        Write-Host "주의: 워처가 $n 개 떠 있습니다 - 전부 정리하고 하나만 다시 띄웁니다."
    }

    Write-Host "워처가 멈추기를 기다립니다 (최대 ${WaitSeconds}초 - 처리 중인 작업이 있으면 끝날 때까지 기다립니다)..."
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $stopSignal = Join-Path $LogsDir "stop.signal"
    while ((Get-Date) -lt $deadline -and (Test-WatcherAlive)) {
        # 정지 신호 파일은 워처가 읽고 지웁니다. 여러 프로세스가 떠 있는 드문 경우에 대비해
        # 몇 초 간격으로 신호를 다시 넣어 줍니다.
        if (-not (Test-Path $stopSignal)) {
            "stop requested at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |
                Set-Content -Path $stopSignal -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 3
    }

    # 아무도 읽어가지 않은 정지 신호가 남아 있으면, 새로 띄울 워처가 그걸 보고 바로 꺼질
    # 수 있으므로 여기서 치웁니다. (워처도 시작할 때 한 번 더 확인하긴 합니다.)
    Remove-Item -Path $stopSignal -Force -ErrorAction SilentlyContinue
    $manualStopFlag = Join-Path $LogsDir "manual_stop.flag"
    Remove-Item -Path $manualStopFlag -Force -ErrorAction SilentlyContinue

    if (Test-WatcherAlive) {
        Write-Host ""
        Write-Host "경고: ${WaitSeconds}초 안에 종료를 확인하지 못했습니다 (오래 걸리는 작업을 처리 중일 수 있습니다)."
        Write-Host "워처를 두 개 동시에 띄우면 같은 inbox/outbox를 두고 충돌할 수 있어, 새로 시작하지 않고 중단합니다."
        Write-Host "logs\watcher.log 에서 '===== 워처 종료' 로그가 남는 걸 확인한 뒤 이 스크립트를 다시 실행해 주세요."
        exit 1
    }

    Write-Host "기존 워처의 종료를 확인했습니다."
} else {
    Write-Host "실행 중인 워처를 찾지 못했습니다 (처음 시작이거나 이미 꺼져 있음) - 새로 시작합니다."
}

Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$WatcherScript`"") `
    -WorkingDirectory $RuntimeDir

Write-Host "새 워처 창을 실행했습니다."
Write-Host "logs\watcher.log 에서 '===== 워처 시작' 로그가 남는지로 확인할 수 있습니다."
