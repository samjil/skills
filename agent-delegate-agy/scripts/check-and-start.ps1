# check-and-start.ps1
# 워처를 시작하기 전에 스크립트 문법을 먼저 검사합니다.
#
# 왜 필요한가: 스크립트에 문법 오류가 있으면 워처가 아예 못 뜨고, 워처가 없으면 agy에게
# 무엇도 시킬 수 없어서 원인 파악조차 어려워집니다.
# 그래서 검사 -> 통과할 때만 시작 순서로 진행하고, 결과는 runtime\logs\syntax-check.log 에도
# 남깁니다.
#
# 사용법: start-agy.bat 더블클릭 (또는 이 파일을 -File 로 실행)

param(
    [string]$RepoRoot   = (Split-Path -Path $PSScriptRoot -Parent),
    [string]$RuntimeDir = "",
    # 검사만 하고 워처는 시작하지 않습니다 (문법만 확인할 때 사용).
    [switch]$CheckOnly
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

if (-not $RuntimeDir) {
    if ($env:AGY_DELEGATE_RUNTIME) {
        $RuntimeDir = $env:AGY_DELEGATE_RUNTIME
    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\agent-delegate-agy\runtime")) {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\agent-delegate-agy\runtime"
    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\delegate\runtime")) {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate\runtime"
    } elseif (Test-Path (Join-Path $env:USERPROFILE ".agent-delegate\runtime")) {
        $RuntimeDir = Join-Path $env:USERPROFILE ".agent-delegate\runtime"
    } elseif (Test-Path (Join-Path $RepoRoot "runtime")) {
        $RuntimeDir = Join-Path $RepoRoot "runtime"
    } else {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\agent-delegate-agy\runtime"
    }
}

$LogsDir = Join-Path $RuntimeDir "logs"
New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
$CheckLog = Join-Path $LogsDir "syntax-check.log"

$targets = @("common.ps1", "watch-agy.ps1", "ensure-agy-running.ps1", "restart-agy.ps1", "stop-agy.ps1", "serve-report.ps1", "log-qa.ps1", "stop-watchdog.ps1")
$lines = @("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 문법 검사 시작")
$failed = $false

foreach ($name in $targets) {
    $file = Join-Path $PSScriptRoot $name
    if (-not (Test-Path $file)) {
        $lines += "  SKIP $name (파일 없음)"
        continue
    }
    $errs = $null
    $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) {
        $failed = $true
        $lines += "  FAIL $name"
        foreach ($e in $errs) {
            $lines += ("    line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message)
        }
    } else {
        $lines += "  OK   $name"
    }
}

$lines | ForEach-Object { Write-Host $_ }
$lines | Set-Content -Path $CheckLog -Encoding UTF8

if ($failed) {
    Write-Host ""
    Write-Host "문법 오류가 있어 워처를 시작하지 않았습니다. 위 내용을 확인해 주세요."
    Write-Host "(같은 내용이 runtime\logs\syntax-check.log 에도 저장되어 있습니다)"
    Write-Host ""
    if (-not $CheckOnly) { Read-Host "확인했으면 Enter" }
    exit 1
}

Write-Host ""
if ($CheckOnly) {
    Write-Host "문법 검사를 통과했습니다. (-CheckOnly 이므로 워처는 시작하지 않습니다)"
    exit 0
}

Write-Host "문법 검사를 통과했습니다. 워처를 시작합니다..."
Write-Host ""
& (Join-Path $PSScriptRoot "restart-agy.ps1") -RepoRoot $RepoRoot -RuntimeDir $RuntimeDir
