# handoff-db.ps1(핸드오프 폴더 배치 이전 · DB 경로) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\handoff\handoff-layout.tests.ps1
# 임시 폴더와 임시 홈(USERPROFILE)만 씁니다. 이 PC 의 실제 ~/.samjil 은 건드리지 않습니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$work = Join-Path ([IO.Path]::GetTempPath()) ("handoff-layout-test-" + [Guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $work "home"
New-Item -ItemType Directory -Force -Path $fakeHome | Out-Null
$saved = @{}
foreach ($k in @("USERPROFILE", "AGENT_HANDOFF_ROOT", "AGENT_HANDOFF_DATA", "AGY_DB_CACHE_DIR")) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, "Process") }
$env:USERPROFILE = $fakeHome
Remove-Item Env:\AGENT_HANDOFF_ROOT -ErrorAction SilentlyContinue
Remove-Item Env:\AGENT_HANDOFF_DATA -ErrorAction SilentlyContinue
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
. (Join-Path $repoRoot "runtime\handoff\scripts\handoff-lib.ps1")

$script:Failed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}
function New-LegacyChannel([string]$name) {
    $d = Join-Path $fakeHome ".samjil\handoff\$name"
    New-Item -ItemType Directory -Force -Path (Join-Path $d "msg") | Out-Null
    [IO.File]::WriteAllText((Join-Path $d "INDEX.md"), "# INDEX`n| 번호 | 시각 | 방향 | 제목 | 상태 |`n|---|---|---|---|---|`n| 0001 | 2026-10-10 09:00 | c2a | 개통 | 처리됨 |`n| 0002 | 2026-10-10 09:05 | a2c | 확인 | 보냄 |`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $d "msg\0001-c2a-open.md"), "---`n번호: 0001`n---`n본문", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $d "BRIEF.md"), "# BRIEF", (New-Object Text.UTF8Encoding($false)))
    return $d
}

try {
    Write-Host "옛 배치(~\.samjil\handoff\<채널>) -> channels\<채널>"
    [void](New-LegacyChannel "old-app")
    [void](New-LegacyChannel "other-app")
    New-Item -ItemType Directory -Force -Path (Join-Path $fakeHome ".samjil\handoff\scripts"), (Join-Path $fakeHome ".samjil\handoff\templates") | Out-Null
    $root = Get-HandoffRootDir
    $channels = Join-Path $fakeHome ".samjil\handoff\channels"
    Assert-Equal "채널 루트는 handoff\channels 이다" $channels $root
    Assert-Equal "옛 채널 두 개가 channels 로 옮겨졌다" "True|True|False" ("{0}|{1}|{2}" -f (Test-Path (Join-Path $channels "old-app\INDEX.md")), (Test-Path (Join-Path $channels "other-app\msg\0001-c2a-open.md")), (Test-Path (Join-Path $fakeHome ".samjil\handoff\old-app")))
    Assert-Equal "  scripts · templates 는 그대로 둔다" $true ((Test-Path (Join-Path $fakeHome ".samjil\handoff\scripts")) -and (Test-Path (Join-Path $fakeHome ".samjil\handoff\templates")))
    Assert-Equal "채널 목록은 channels 아래 채널만" "old-app|other-app" ((@(Get-HandoffChannelDirs | ForEach-Object { Split-Path -Leaf $_ }) | Sort-Object) -join "|")
    Assert-Equal "DB 는 handoff\data\handoff.db" (Join-Path $fakeHome ".samjil\handoff\data\handoff.db") (Get-HandoffDbPath)

    Write-Host "옛 INDEX.md 는 처음 읽을 때 DB 로 들어온다"
    $rows = @(Read-HandoffIndex (Join-Path $channels "old-app"))
    Assert-Equal "행 2건 · 상태 유지" "2|처리됨|보냄" ("{0}|{1}|{2}" -f $rows.Count, $rows[0].Status, $rows[1].Status)
    Assert-Equal "  DB 파일이 만들어졌다" $true (Test-Path (Get-HandoffDbPath))
    Assert-Equal "  다음 번호는 3" 3 (Get-HandoffNextNumber (Join-Path $channels "old-app"))

    Write-Host "다시 불러도 안전"
    Assert-Equal "이미 옮긴 뒤에는 0개" 0 (Move-HandoffLegacyLayout (Join-Path $fakeHome ".samjil\handoff"))

    Write-Host "채널 루트에 같은 이름이 이미 있으면 덮어쓰지 않는다"
    [void](New-LegacyChannel "old-app")
    [void](Move-HandoffLegacyLayout (Join-Path $fakeHome ".samjil\handoff"))
    Assert-Equal "새 채널(channels\old-app)은 그대로, 옛 폴더도 지우지 않는다" "True|True" ("{0}|{1}" -f (Test-Path (Join-Path $channels "old-app\INDEX.md")), (Test-Path (Join-Path $fakeHome ".samjil\handoff\old-app\INDEX.md")))

    Write-Host "폴더를 다른 프로그램이 열어 두어 이름을 못 바꿀 때는 안의 항목을 옮긴다"
    $held = New-LegacyChannel "held-app"
    $holder = Start-Process -FilePath "cmd.exe" -ArgumentList "/c ping -n 30 127.0.0.1 > nul" -WorkingDirectory $held -WindowStyle Hidden -PassThru
    try {
        Start-Sleep -Milliseconds 500
        $n = Move-HandoffLegacyLayout (Join-Path $fakeHome ".samjil\handoff")
        Assert-Equal "채널 하나를 옮겼다" 1 $n
        Assert-Equal "  새 위치에 INDEX · BRIEF · msg 가 모두 있다" $true ((Test-Path (Join-Path $channels "held-app\INDEX.md")) -and (Test-Path (Join-Path $channels "held-app\BRIEF.md")) -and (Test-Path (Join-Path $channels "held-app\msg\0001-c2a-open.md")))
        Assert-Equal "  옛 폴더에는 파일이 남지 않는다" 0 @(Get-ChildItem -LiteralPath $held -Recurse -File -ErrorAction SilentlyContinue).Count
    } finally { try { Stop-Process -Id $holder.Id -Force -ErrorAction SilentlyContinue } catch {} }

    Write-Host "환경변수 AGENT_HANDOFF_ROOT 가 있으면 그 폴더가 루트, 데이터는 루트 안 .data"
    $env:AGENT_HANDOFF_ROOT = Join-Path $work "custom"
    New-Item -ItemType Directory -Force -Path $env:AGENT_HANDOFF_ROOT | Out-Null
    Assert-Equal "루트" $env:AGENT_HANDOFF_ROOT (Get-HandoffRootDir)
    Assert-Equal "데이터 폴더" (Join-Path $env:AGENT_HANDOFF_ROOT ".data") (Get-HandoffDataDir)
    $env:AGENT_HANDOFF_DATA = Join-Path $work "mydata"
    Assert-Equal "AGENT_HANDOFF_DATA 가 우선" (Join-Path $work "mydata\handoff.db") (Get-HandoffDbPath)
}
finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], "Process") }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed -gt 0) { Write-Host "`n실패 $($script:Failed)건" -ForegroundColor Red; exit 1 }
Write-Host "`n모두 통과" -ForegroundColor Green
exit 0
