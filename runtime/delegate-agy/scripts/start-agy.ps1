# start-agy.ps1
# Antigravity CLI(agy) 위임 워처(watch-agy.ps1)를 안전하게 시작/재시작합니다.
#
# 순서:
#   1. 스크립트 문법 검사 (오류 시 기동 중단 및 syntax-check.log 기록)
#   2. 기존 워처가 살아있으면 정상 종료 신호 전송 및 대기
#   3. 새 콘솔 창에서 watch-agy.ps1 실행
#
# 사용법:
#   .\start-agy.ps1                         # 워처 안전 시작/재시작 (PowerShell)
#   .\start-agy.ps1 -CheckOnly              # 문법 검사만 수행 (워처 미실행)
#   .\start-agy.ps1 -WaitSeconds 60         # 기존 워처 종료 대기 시간 연장

param(
    [string]$RepoRoot    = (Split-Path -Path $PSScriptRoot -Parent),
    [string]$RuntimeDir  = "",
    [int]$WaitSeconds    = 30,
    [switch]$CheckOnly   = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try { chcp 65001 > $null } catch {}



if (-not $RuntimeDir) {

    if ($env:AGY_DELEGATE_RUNTIME) {

        $RuntimeDir = $env:AGY_DELEGATE_RUNTIME

    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime")) {

        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"

    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime")) {

        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime"

    } elseif (Test-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "runtime")) {

        $RuntimeDir = Join-Path (Split-Path $PSScriptRoot -Parent) "runtime"

    } elseif (Test-Path (Join-Path $RepoRoot "runtime")) {

        $RuntimeDir = Join-Path $RepoRoot "runtime"

    } else {

        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"

    }

}

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null



$LogsDir       = Join-Path $RuntimeDir "logs"

$HeartbeatDir  = Join-Path $LogsDir "heartbeat"

$HeartbeatFile = Join-Path $HeartbeatDir ("hb_{0}.txt" -f $env:COMPUTERNAME)

$WatcherScript = Join-Path $PSScriptRoot "sub\watch-agy.ps1"
if (-not (Test-Path $WatcherScript)) {
    $WatcherScript = Join-Path $PSScriptRoot "watch-agy.ps1"
}

$StopScript    = Join-Path $PSScriptRoot "stop-agy.ps1"
$CheckLog      = Join-Path $LogsDir "syntax-check.log"

if (-not (Test-Path $WatcherScript)) {
    Write-Error "watch-agy.ps1을 찾을 수 없습니다: $WatcherScript"
    exit 1
}

# -----------------------------------------------------------------------------
# 1. 스크립트 문법 사전 검증
# -----------------------------------------------------------------------------
$targets = @(
    "start-agy.ps1",
    "stop-agy.ps1",
    "sub\common.ps1",
    "sub\watch-agy.ps1",
    "sub\ensure-agy-running.ps1",
    "sub\log-qa.ps1"
)

$lines = @("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 문법 검사 시작")
$failed = $false

foreach ($relPath in $targets) {
    $file = Join-Path $PSScriptRoot $relPath
    if (-not (Test-Path $file)) {
        # sub 폴더가 아닌 현재 폴더에 있을 수도 있는 하위 호환 폴백
        $file = Join-Path $PSScriptRoot (Split-Path -Leaf $relPath)
        if (-not (Test-Path $file)) { continue }
    }

    $displayName = Split-Path -Leaf $relPath
    $errs = $null
    $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errs)

    if ($errs -and $errs.Count -gt 0) {
        $failed = $true
        $lines += "  FAIL $displayName"
        foreach ($e in $errs) {
            $lines += ("    line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message)
        }
    } else {
        $lines += "  OK   $displayName"
    }
}



$lines | ForEach-Object { Write-Host $_ }

try { $lines | Set-Content -Path $CheckLog -Encoding UTF8 } catch {}



if ($failed) {

    Write-Host ""

    Write-Host "문법 오류가 있어 워처를 시작하지 않았습니다. 위 내용을 확인해 주세요." -ForegroundColor Red

    Write-Host "(상세 로그: $CheckLog)" -ForegroundColor Gray

    Write-Host ""

    if (-not $CheckOnly) { Read-Host "확인했으면 Enter" }

    exit 1

}



if ($CheckOnly) {

    Write-Host "`n문법 검사를 통과했습니다. (-CheckOnly 모드)" -ForegroundColor Green

    exit 0

}



# -----------------------------------------------------------------------------

# 2. 기존 실행 중인 워처 확인 및 안전 재시작 처리

# -----------------------------------------------------------------------------

function Get-WatcherProcessCount {

    try {

        return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |

            Where-Object { $_.CommandLine -like "*watch-agy.ps1*" }).Count

    } catch {

        return -1

    }

}



function Test-WatcherAlive {

    try {

        $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |

            Where-Object { $_.CommandLine -like "*watch-agy.ps1*" })

        if ($procs.Count -gt 0) { return $true }

    } catch {}

    if (-not (Test-Path $HeartbeatFile)) { return $false }

    $ageSec = [int]((Get-Date) - (Get-Item $HeartbeatFile).LastWriteTime).TotalSeconds

    return ($ageSec -le 30)

}



if (Test-WatcherAlive) {

    Write-Host "기존 워처가 실행 중인 것으로 보입니다 - 정상 종료를 요청합니다..." -ForegroundColor Yellow



    if (Test-Path $StopScript) {

        & $StopScript -RepoRoot $RepoRoot -RuntimeDir $RuntimeDir | Out-Null

    } else {

        New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

        "stop requested at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |

            Set-Content -Path (Join-Path $LogsDir "stop.signal") -Encoding UTF8

    }



    $n = Get-WatcherProcessCount

    if ($n -gt 1) {

        Write-Host "주의: 워처가 $n 개 실행 중입니다 - 모두 정리 후 하나만 새로 시작합니다." -ForegroundColor Yellow

    }



    Write-Host "워처가 멈추기를 기다립니다 (최대 ${WaitSeconds}초)..."

    $deadline = (Get-Date).AddSeconds($WaitSeconds)

    $stopSignal = Join-Path $LogsDir "stop.signal"

    while ((Get-Date) -lt $deadline -and (Test-WatcherAlive)) {

        if (-not (Test-Path $stopSignal)) {

            "stop requested at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |

                Set-Content -Path $stopSignal -Encoding UTF8 -ErrorAction SilentlyContinue

        }

        Start-Sleep -Seconds 2

    }



    Remove-Item -Path $stopSignal -Force -ErrorAction SilentlyContinue

    $manualStopFlag = Join-Path $LogsDir "manual_stop.flag"

    Remove-Item -Path $manualStopFlag -Force -ErrorAction SilentlyContinue



    if (Test-WatcherAlive) {

        Write-Host ""

        Write-Host "경고: ${WaitSeconds}초 안에 워처 종료를 확인하지 못했습니다 (처리 중인 작업이 길어질 수 있습니다)." -ForegroundColor Red

        Write-Host "워처 충돌을 방지하기 위해 새 워처를 시작하지 않고 중단합니다." -ForegroundColor Red

        Write-Host "logs\watcher.log 에서 종료를 확인한 뒤 다시 실행해 주세요." -ForegroundColor Gray

        exit 1

    }



    Write-Host "기존 워처가 정상 종료되었습니다." -ForegroundColor Green

} else {

    Write-Host "실행 중인 워처가 없습니다 - 새로 시작합니다." -ForegroundColor Cyan

}



# -----------------------------------------------------------------------------
# 3. 새 콘솔 창에서 워처 기동
# -----------------------------------------------------------------------------
$procParams = @{
    FilePath         = "powershell.exe"
    ArgumentList     = @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$WatcherScript`"", "-RuntimeDir", "`"$RuntimeDir`"")
    WorkingDirectory = $RuntimeDir
}
Start-Process @procParams



Write-Host "새 워처 창을 실행했습니다." -ForegroundColor Green

Write-Host "logs\watcher.log 에서 '===== 워처 시작' 로그로 확인할 수 있습니다." -ForegroundColor Gray

