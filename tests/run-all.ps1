# 저장소의 모든 시험을 한 번에 돌리고 스위트별 결과를 요약한다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 -Fast          # 오래 걸리는 시험(e2e·멈춤 판정 등) 건너뛰기
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 -Only qa-store,hygiene   # 이름에 이 글자가 든 것만
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 -Parallel 1     # 하나씩 차례로(문제를 좁힐 때)
# 시험은 tests\**\*.tests.ps1(PowerShell)과 tests\**\*.tests.js(node)를 모두 찾는다. 시험마다 새 프로세스에서 돌리고,
# 끝났을 때의 종료 코드와 마지막 줄의 "통과 N / 실패 M" 숫자를 읽는다(글자 인코딩과 무관하게 숫자 모양만 본다).
# 하나라도 실패하거나 시간 초과면 종료 코드 1 로 끝난다. 실행 중인 운영 워처·뷰어는 건드리지 않는다(시험이 임시 폴더만 쓴다).
#
# 병렬: 기본으로 -Parallel 개(환경변수 RUNALL_PARALLEL 로도 지정)의 시험을 동시에 돌린다. 시험은 서로 임시 폴더·무작위 포트·이름이 다른 뮤텍스를
# 쓰므로 겹치지 않는다. 오래 걸리는 시험을 먼저 시작해 전체 시간을 줄인다. 실패한 시험은 실패한 줄을 바로 아래에 보여 준다.

param(
    [switch]$Fast,
    [string[]]$Only = @(),
    [int]$TimeoutSeconds = 600,
    [int]$Parallel = 0
)

$ErrorActionPreference = "Stop"
# 출력을 UTF-8 로 고정한다(git 훅·Git Bash 에서 한글이 깨지지 않게)
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
# powershell -File 로 부르면 -Only a,b 가 "a,b" 한 덩어리로 오므로 쉼표로 다시 나눈다
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Parallel -le 0) {
    if ($env:RUNALL_PARALLEL -match '^\d+$' -and [int]$env:RUNALL_PARALLEL -gt 0) { $Parallel = [int]$env:RUNALL_PARALLEL } else { $Parallel = 4 }
}
$testsRoot = $PSScriptRoot
$repoRoot  = Split-Path $testsRoot -Parent

# 오래 걸려서 -Fast 에서 빼는 시험(대략 1분 이상). 이름에 이 글자가 들어 있으면 뺀다. 병렬일 때는 이것들을 먼저 시작한다.
$slowMarkers = @(".e2e.", "invoke-agy-once", "serve-viewer-autostart", "watcher-health", "ensure-viewer")

$suites = @()
# -Include 는 이름 일부가 맞는 파일(run-all.ps1 자신)까지 끌어와 자기 자신을 재귀로 돌리는 일이 있어, 이름을 직접 거른다.
foreach ($f in (Get-ChildItem -LiteralPath $testsRoot -Recurse -File | Where-Object { $_.Name -match '\.tests\.(ps1|js)$' } | Sort-Object FullName)) {
    $rel = $f.FullName.Substring($testsRoot.Length + 1)
    if ($Only.Count -gt 0) {
        $hit = $false
        foreach ($o in $Only) { if ($rel -like "*$o*") { $hit = $true } }
        if (-not $hit) { continue }
    }
    $slow = $false
    foreach ($m in $slowMarkers) { if ($rel -like "*$m*") { $slow = $true } }
    if ($Fast -and $slow) { continue }
    $suites += [pscustomobject]@{ Rel = $rel; Path = $f.FullName; IsNode = $f.Name.EndsWith(".js"); Slow = $slow }
}
# 오래 걸리는 것을 먼저(같은 무리 안에서는 이름순)
$ordered = @($suites | Sort-Object @{ Expression = { if ($_.Slow) { 0 } else { 1 } } }, Rel)

$node = Get-Command node -ErrorAction SilentlyContinue

function Start-Suite($s) {
    $h = [pscustomobject]@{ Suite = $s; Proc = $null; Out = $null; Err = $null; Sw = [Diagnostics.Stopwatch]::StartNew(); Skip = $false }
    if ($s.IsNode -and -not $node) { $h.Skip = $true; return $h }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($s.IsNode) { $psi.FileName = $node.Source; $psi.Arguments = "`"$($s.Path)`"" }
    else { $psi.FileName = "powershell.exe"; $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($s.Path)`"" }
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.WorkingDirectory = $repoRoot
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $h.Proc = $p
    $h.Out = $p.StandardOutput.ReadToEndAsync(); $h.Err = $p.StandardError.ReadToEndAsync()
    try { $p.StandardInput.Close() } catch {}
    return $h
}

function Complete-Suite($h, [bool]$timedOut) {
    $h.Sw.Stop()
    $status = "OK"; $pass = $null; $fail = $null; $tail = ""; $failLines = @()
    if ($h.Skip) {
        $status = "SKIP(node 없음)"
    } elseif ($timedOut) {
        try { & taskkill.exe /PID $h.Proc.Id /T /F 2>&1 | Out-Null } catch {}
        $status = "TIMEOUT"
    } else {
        try { $h.Proc.WaitForExit() } catch {}
        $out = [string]$h.Out.Result
        $lines = @($out -split "\r?\n" | Where-Object { $_.Trim() })
        if ($lines.Count -gt 0) {
            $tail = $lines[-1]
            if ($tail -match '(\d+)\s*/\s*\S+\s+(\d+)\s*$') { $pass = [int]$Matches[1]; $fail = [int]$Matches[2] }
        }
        if ($h.Proc.ExitCode -ne 0) { $status = "FAIL" }
        elseif ($null -ne $fail -and $fail -gt 0) { $status = "FAIL" }
        elseif ($null -eq $pass) { $status = "OK(건수 없음)" }
        if ($status -eq "FAIL") { $failLines = @($lines | Where-Object { $_ -match 'FAIL' } | Select-Object -First 8) }
    }
    try { if ($h.Proc) { $h.Proc.Dispose() } } catch {}
    $r = [pscustomobject]@{ Suite = $h.Suite.Rel; Status = $status; Pass = $pass; Fail = $fail; Seconds = [int]$h.Sw.Elapsed.TotalSeconds; Tail = $tail; FailLines = $failLines }
    $color = if ($status -like "OK*") { "Green" } elseif ($status -like "SKIP*") { "Yellow" } else { "Red" }
    Write-Host ("  {0,-8} {1,-62} 통과 {2,4} / 실패 {3,3}  ({4}초)" -f $status, $r.Suite, $pass, $fail, $r.Seconds) -ForegroundColor $color
    foreach ($fl in $failLines) { Write-Host ("            " + $fl.Trim()) -ForegroundColor Red }
    return $r
}

$results = @()
$total = [Diagnostics.Stopwatch]::StartNew()
$pending = New-Object System.Collections.Queue
foreach ($s in $ordered) { $pending.Enqueue($s) }
$running = New-Object System.Collections.ArrayList
while ($pending.Count -gt 0 -or $running.Count -gt 0) {
    while ($pending.Count -gt 0 -and $running.Count -lt $Parallel) {
        [void]$running.Add((Start-Suite $pending.Dequeue()))
    }
    $done = @()
    foreach ($h in @($running)) {
        if ($h.Skip) { $done += ,@($h, $false); continue }
        if ($h.Proc.HasExited -and $h.Out.IsCompleted -and $h.Err.IsCompleted) { $done += ,@($h, $false) }
        elseif ($h.Sw.Elapsed.TotalSeconds -gt $TimeoutSeconds) { $done += ,@($h, $true) }
    }
    foreach ($d in $done) {
        $results += Complete-Suite $d[0] $d[1]
        $running.Remove($d[0])
    }
    if ($done.Count -eq 0) { Start-Sleep -Milliseconds 200 }
}
$total.Stop()

$bad = @($results | Where-Object { $_.Status -like "FAIL*" -or $_.Status -eq "TIMEOUT" })
$sumPass = ($results | Where-Object { $null -ne $_.Pass } | Measure-Object -Property Pass -Sum).Sum
$sumFail = ($results | Where-Object { $null -ne $_.Fail } | Measure-Object -Property Fail -Sum).Sum
Write-Host ""
Write-Host ("스위트 {0}개 / 통과 {1}건 / 실패 {2}건 / 문제 있는 스위트 {3}개 / {4}초 (동시 {5}개)" -f $results.Count, $sumPass, $sumFail, $bad.Count, [int]$total.Elapsed.TotalSeconds, $Parallel)
foreach ($b in $bad) { Write-Host ("  문제: {0} -> {1}  {2}" -f $b.Suite, $b.Status, $b.Tail) -ForegroundColor Red }
# 이 PC 에서 푸시 전 시험 훅이 꺼져 있으면 알린다(저장소를 새로 받으면 한 번 켜야 한다)
$hooksPath = ""
try { $hooksPath = (@(& git -C $repoRoot config --get core.hooksPath 2>$null) -join "").Trim() } catch {}
if ($hooksPath -ne ".githooks" -and (Test-Path -LiteralPath (Join-Path $repoRoot ".githooks\pre-push"))) {
    Write-Host "참고: 푸시 전 시험 훅이 꺼져 있습니다. 켜려면: powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup-dev.ps1" -ForegroundColor Yellow
}
if ($bad.Count -gt 0) { exit 1 }
