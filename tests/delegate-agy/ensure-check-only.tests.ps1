# ensure-agy-running.ps1 -CheckOnly 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\ensure-check-only.tests.ps1
# 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다. 임시 폴더만 쓰고 워처는 띄우지 않습니다(-CheckOnly 는 켜지 않음).
# 이 PC에 진짜 워처가 떠 있어도 결과가 흔들리지 않게, ensure 의 "프로세스 목록 보조 검사"(Get-CimInstance)만
# 빈 결과로 가립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ensure = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\ensure-agy-running.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("ensure-check-test-" + [Guid]::NewGuid().ToString("N"))
function New-Runtime {
    $rt = Join-Path $work ([Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path (Join-Path $rt "heartbeat") | Out-Null
    return $rt
}
$lockName = "watcher_{0}.lock" -f $env:COMPUTERNAME
$hbName   = "hb_{0}.txt" -f $env:COMPUTERNAME

# ensure 를 -CheckOnly 로 돌려 @{ Output; Code } 를 돌려준다.
function Invoke-Check([string]$rt, [int]$stale = 300) {
    $res = & {
        function Get-CimInstance { @() }
        $o = & $ensure -RuntimeDir $rt -CheckOnly -StaleThresholdSeconds $stale
        @{ Output = (@($o) -join "").Trim(); Code = $LASTEXITCODE }
    }
    return $res
}

Write-Host "-CheckOnly"
$rt = New-Runtime
$r = Invoke-Check $rt
Assert-Equal "아무 흔적도 없으면 DEAD" "DEAD" $r.Output
Assert-Equal "  종료 코드 1" 1 $r.Code

"$PID" | Set-Content -Path (Join-Path $rt "$lockName") -Encoding UTF8
$r = Invoke-Check $rt
Assert-Equal "잠금 PID가 살아 있는 powershell 이면 ALIVE" "ALIVE" $r.Output
Assert-Equal "  종료 코드 0" 0 $r.Code

"x" | Set-Content (Join-Path $rt "manual_stop.flag")
$r = Invoke-Check $rt
Assert-Equal "살아 있으면 수동 정지 플래그가 있어도 ALIVE (정지 중일 수 있음)" "ALIVE" $r.Output
Remove-Item (Join-Path $rt "$lockName") -Force

$r = Invoke-Check $rt
Assert-Equal "죽었고 수동 정지 플래그가 있으면 MANUAL_STOP" "MANUAL_STOP" $r.Output
Assert-Equal "  종료 코드 2" 2 $r.Code

Write-Host "-CheckOnly: 낡은 잠금 파일"
$rt = New-Runtime
$gone = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-Command", "exit 0" -WindowStyle Hidden -PassThru
$gone.WaitForExit()
"$($gone.Id)" | Set-Content -Path (Join-Path $rt "$lockName") -Encoding UTF8
$r = Invoke-Check $rt
Assert-Equal "잠금 PID의 프로세스가 끝났으면 DEAD" "DEAD" $r.Output
Assert-Equal "  낡은 잠금 파일은 치웠다" $false (Test-Path (Join-Path $rt "$lockName"))

Write-Host "-CheckOnly: 하트비트 유예 (-StaleThresholdSeconds)"
$rt = New-Runtime
$hb = Join-Path $rt "heartbeat\$hbName"
"x" | Set-Content $hb; (Get-Item $hb).LastWriteTime = (Get-Date).AddSeconds(-290)
$r = Invoke-Check $rt 300
Assert-Equal "창을 닫은 직후(290초 전 하트비트)는 기본값 300 이면 ALIVE 로 오판한다" "ALIVE" $r.Output
$r = Invoke-Check $rt 0
Assert-Equal "-StaleThresholdSeconds 0 이면 DEAD" "DEAD" $r.Output

Write-Host "-CheckOnly: 켜지 않는다"
$rt = New-Runtime
$null = Invoke-Check $rt 0
$log = Join-Path $rt "logs\watchdog.log"
$restarted = (Test-Path $log) -and ((Get-Content $log -Raw) -match "재시작")
Assert-Equal "죽어 있어도 재시작을 시도하지 않는다 (watchdog.log 에 재시작 기록 없음)" $false $restarted

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
