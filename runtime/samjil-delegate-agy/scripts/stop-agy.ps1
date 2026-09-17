# stop-agy.ps1
# watch-agy.ps1 워처를 강제로 죽이지 않고, "정상 종료 로그"를 남기면서 안전하게 멈춥니다.
#
# 동작 방식: runtime\logs\stop.signal 파일을 만들어두면, 워처가 폴링할 때마다(기본 2초 주기)
# 이 파일이 있는지 확인하고, 있으면 스스로 while 루프를 빠져나가면서 기존 finally 블록의
# 정상 종료 로그("===== 워처 종료 ...")를 그대로 남깁니다. Stop-Process로 강제 종료하는 것과
# 달리, 처리 중이던 작업(agy 실행 등)은 끝까지 마친 뒤에 멈추므로 안전합니다.
#
# 사용법:
#   .\stop-agy.ps1

param([string]$RepoRoot = (Split-Path -Path $PSScriptRoot -Parent), [string]$RuntimeDir = "")

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

$LogsDir        = Join-Path $RuntimeDir "logs"
$StopSignalFile = Join-Path $LogsDir "stop.signal"
$HeartbeatDir   = Join-Path $LogsDir "heartbeat"
$HeartbeatFile  = Join-Path $HeartbeatDir ("hb_{0}.txt" -f $env:COMPUTERNAME)
$ManualStopFlag = Join-Path $LogsDir "manual_stop.flag"

if (-not (Test-Path $LogsDir)) {
    Write-Host "logs 폴더를 찾을 수 없습니다: $LogsDir"
    Write-Host "워처(watch-agy.ps1)가 한 번도 실행된 적이 없을 수 있습니다."
    exit 1
}

# 하트비트 파일로 워처가 지금 살아있는지 참고용으로 확인합니다 (신호를 보내는 데는 필요 없습니다).
if (Test-Path $HeartbeatFile) {
    $ageSec = [int]((Get-Date) - (Get-Item $HeartbeatFile).LastWriteTime).TotalSeconds
    if ($ageSec -gt 10) {
        Write-Host "참고: 하트비트가 ${ageSec}초 전에 마지막으로 갱신됐습니다 - 워처가 이미 꺼져 있을 수 있습니다."
    }
} else {
    Write-Host "참고: 하트비트 파일이 없습니다 - 워처가 실행된 적이 없거나 이미 꺼져 있을 수 있습니다."
}

"stop requested at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $StopSignalFile -Encoding UTF8
"stopped manually at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $ManualStopFlag -Encoding UTF8

Write-Host "종료 신호를 보냈습니다: $StopSignalFile"
Write-Host "수동 정지 표시를 남겼습니다(워치독을 등록해뒀어도 이 표시가 있는 동안은 자동으로 다시 켜지지 않습니다): $ManualStopFlag"
Write-Host "워처가 지금 처리 중인 작업이 있다면 그걸 끝낸 뒤, 다음 폴링 주기 안에(기본 2초) 정상 종료됩니다."
Write-Host "logs\watcher.log 에서 '===== 워처 종료' 로그가 남는지로 확인할 수 있습니다."
