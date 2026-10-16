# tools\setup-dev.ps1(새 PC 개발 시작: 훅 켜기·환경 점검)의 동작을 임시 git 저장소로 확인한다. 이 저장소의 git 설정은 건드리지 않는다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\repo\setup-dev.tests.ps1

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script = Join-Path $repoRoot "tools\setup-dev.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("setup-dev-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $work ".githooks") | Out-Null
& git -C $work init -q 2>$null
function Run-Setup([string[]]$extra = @()) {
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script, "-RepoRoot", $work) + $extra
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = (@($a | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    try { $p.StandardInput.Close() } catch {}
    $p.WaitForExit()
    $r = @{ Code = $p.ExitCode; Out = ([string]$o.Result + [string]$e.Result) }
    $p.Dispose()
    return $r
}
function Get-HooksPath { return (@(& git -C $work config --get core.hooksPath 2>$null) -join "").Trim() }

Write-Host "훅 파일이 없으면 종료 코드 2"
$r = Run-Setup
Assert-Equal "  종료 코드 2" 2 $r.Code
Assert-Equal "  훅 파일이 없다고 알린다" $true ($r.Out -like "*훅 파일이 없습니다*")
Assert-Equal "  git 설정은 바뀌지 않는다" "" (Get-HooksPath)

Write-Host "훅 파일이 CRLF 이면 종료 코드 2"
[System.IO.File]::WriteAllText((Join-Path $work ".githooks\pre-push"), "#!/bin/sh`r`nexit 0`r`n", (New-Object System.Text.UTF8Encoding($false)))
$r = Run-Setup
Assert-Equal "  종료 코드 2" 2 $r.Code
Assert-Equal "  모양이 틀리다고 알린다" $true ($r.Out -like "*훅 파일 모양이 틀립니다*")
Assert-Equal "  훅을 켜지 않는다" "" (Get-HooksPath)

Write-Host "올바른 훅 파일: -Check 는 꺼져 있으면 1, 켜지 않는다"
[System.IO.File]::WriteAllText((Join-Path $work ".githooks\pre-push"), "#!/bin/sh`nexit 0`n", (New-Object System.Text.UTF8Encoding($false)))
$r = Run-Setup @("-Check")
Assert-Equal "  종료 코드 1" 1 $r.Code
Assert-Equal "  꺼져 있다고 알린다" $true ($r.Out -like "*꺼져 있음*")
Assert-Equal "  -Check 는 설정을 바꾸지 않는다" "" (Get-HooksPath)

Write-Host "켜기"
$r = Run-Setup
Assert-Equal "  종료 코드 0" 0 $r.Code
Assert-Equal "  core.hooksPath 가 .githooks 가 된다" ".githooks" (Get-HooksPath)
Assert-Equal "  '켰습니다' 를 알린다" $true ($r.Out -like "*켰습니다*")

Write-Host "다시 돌려도 같은 결과(여러 번 돌려도 안전)"
$r = Run-Setup
Assert-Equal "  종료 코드 0" 0 $r.Code
Assert-Equal "  '켜져 있음' 을 알린다" $true ($r.Out -like "*켜져 있음*")
Assert-Equal "  -Check 도 0" 0 (Run-Setup @("-Check")).Code

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
