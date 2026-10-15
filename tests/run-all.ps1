# 저장소의 모든 시험을 한 번에 돌리고 스위트별 결과를 요약한다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 -Fast          # 오래 걸리는 시험(e2e·멈춤 판정 등) 건너뛰기
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 -Only qa-store,hygiene   # 이름에 이 글자가 든 것만
# 시험은 tests\**\*.tests.ps1(PowerShell)과 tests\**\*.tests.js(node)를 모두 찾는다. 시험마다 새 프로세스에서 돌리고,
# 끝났을 때의 종료 코드와 마지막 줄의 "통과 N / 실패 M" 숫자를 읽는다(글자 인코딩과 무관하게 숫자 모양만 본다).
# 하나라도 실패하거나 시간 초과면 종료 코드 1 로 끝난다. 실행 중인 운영 워처·뷰어는 건드리지 않는다(시험이 임시 폴더만 쓴다).

param(
    [switch]$Fast,
    [string[]]$Only = @(),
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"
# powershell -File 로 부르면 -Only a,b 가 "a,b" 한 덩어리로 오므로 쉼표로 다시 나눈다
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$testsRoot = $PSScriptRoot
$repoRoot  = Split-Path $testsRoot -Parent

# 오래 걸려서 -Fast 에서 빼는 시험(대략 1분 이상). 이름에 이 글자가 들어 있으면 뺀다.
$slowMarkers = @(".e2e.", "invoke-agy-once", "serve-viewer-autostart", "watcher-health")

$suites = @()
# -Include 는 이름 일부가 맞는 파일(run-all.ps1 자신)까지 끌어와 자기 자신을 재귀로 돌리는 일이 있어, 이름을 직접 거른다.
foreach ($f in (Get-ChildItem -LiteralPath $testsRoot -Recurse -File | Where-Object { $_.Name -match '\.tests\.(ps1|js)$' } | Sort-Object FullName)) {
    $rel = $f.FullName.Substring($testsRoot.Length + 1)
    if ($Only.Count -gt 0) {
        $hit = $false
        foreach ($o in $Only) { if ($rel -like "*$o*") { $hit = $true } }
        if (-not $hit) { continue }
    }
    if ($Fast) {
        $slow = $false
        foreach ($m in $slowMarkers) { if ($rel -like "*$m*") { $slow = $true } }
        if ($slow) { continue }
    }
    $suites += [pscustomobject]@{ Rel = $rel; Path = $f.FullName; IsNode = $f.Name.EndsWith(".js") }
}

$node = Get-Command node -ErrorAction SilentlyContinue
$results = @()
$total = [Diagnostics.Stopwatch]::StartNew()
foreach ($s in $suites) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $status = "OK"; $pass = $null; $fail = $null; $tail = ""
    if ($s.IsNode -and -not $node) {
        $status = "SKIP(node 없음)"
    } else {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ($s.IsNode) { $psi.FileName = $node.Source; $psi.Arguments = "`"$($s.Path)`"" }
        else { $psi.FileName = "powershell.exe"; $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($s.Path)`"" }
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
        $psi.WorkingDirectory = $repoRoot
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
        try { $p.StandardInput.Close() } catch {}
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch {}
            $status = "TIMEOUT"
        } else {
            $p.WaitForExit()
            $out = [string]$outTask.Result
            $lines = @($out -split "\r?\n" | Where-Object { $_.Trim() })
            if ($lines.Count -gt 0) {
                $tail = $lines[-1]
                if ($tail -match '(\d+)\s*/\s*\S+\s+(\d+)\s*$') { $pass = [int]$Matches[1]; $fail = [int]$Matches[2] }
            }
            if ($p.ExitCode -ne 0) { $status = "FAIL" }
            elseif ($null -ne $fail -and $fail -gt 0) { $status = "FAIL" }
            elseif ($null -eq $pass) { $status = "OK(건수 없음)" }
        }
        try { $p.Dispose() } catch {}
    }
    $sw.Stop()
    $results += [pscustomobject]@{ Suite = $s.Rel; Status = $status; Pass = $pass; Fail = $fail; Seconds = [int]$sw.Elapsed.TotalSeconds; Tail = $tail }
    $color = if ($status -like "OK*") { "Green" } elseif ($status -like "SKIP*") { "Yellow" } else { "Red" }
    Write-Host ("  {0,-8} {1,-62} 통과 {2,4} / 실패 {3,3}  ({4}초)" -f $status, $s.Rel, $pass, $fail, [int]$sw.Elapsed.TotalSeconds) -ForegroundColor $color
}
$total.Stop()

$bad = @($results | Where-Object { $_.Status -like "FAIL*" -or $_.Status -eq "TIMEOUT" })
$sumPass = ($results | Where-Object { $null -ne $_.Pass } | Measure-Object -Property Pass -Sum).Sum
$sumFail = ($results | Where-Object { $null -ne $_.Fail } | Measure-Object -Property Fail -Sum).Sum
Write-Host ""
Write-Host ("스위트 {0}개 / 통과 {1}건 / 실패 {2}건 / 문제 있는 스위트 {3}개 / {4}초" -f $results.Count, $sumPass, $sumFail, $bad.Count, [int]$total.Elapsed.TotalSeconds)
foreach ($b in $bad) { Write-Host ("  문제: {0} -> {1}  {2}" -f $b.Suite, $b.Status, $b.Tail) -ForegroundColor Red }
if ($bad.Count -gt 0) { exit 1 }
