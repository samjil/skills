# agy-retention.ps1(위임 작업 파일 보관 기간 정리) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-retention.tests.ps1
# 임시 폴더만 씁니다. 런타임 폴더 이름이 runtime 이 아니면 data 는 그 안에 생깁니다(agy-layout.ps1).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-layout.ps1")
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-retention.ps1")
Remove-Item Env:\AGY_DELEGATE_DATA -ErrorAction SilentlyContinue

$script:Failed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("agy-retention-test-" + [Guid]::NewGuid().ToString("N"))
function New-File([string]$rel, [int]$ageDays) {
    $p = Join-Path $work $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $p -Parent) | Out-Null
    "x" | Set-Content -LiteralPath $p
    (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddDays(-$ageDays)
}
function Exists([string]$rel) { Test-Path -LiteralPath (Join-Path $work $rel) }

try {
    # 3개월(약 90일)이 지난 것 = 지운다
    New-File "data\tasks\processed\old.json" 100
    New-File "data\tasks\outbox\old.md" 92
    New-File "data\tasks\stuck\old.json" 200
    New-File "data\screenshots\old.png" 120
    New-File "data\cache\process-ko\old.json" 100
    New-File "data\backups\delegate.db.bak-x" 100
    New-File "prompts\old.txt" 100
    New-File "running\old.json" 100
    # 3개월이 안 된 것 = 남긴다
    New-File "data\tasks\processed\new.json" 5
    New-File "data\tasks\outbox\new.md" 85
    New-File "data\screenshots\new.png" 1
    New-File "data\cache\process-ko\new.json" 2
    # 오래돼도 지우면 안 되는 것
    New-File "inbox\pending-old.json" 400
    New-File "data\delegate.db" 400
    New-File "data\cache\claude-links.json" 400
    New-File "logs\watcher.log" 400
    New-File "heartbeat\hb_PC1.txt" 400

    $n = Remove-DelegationFilesOlderThan $work 3
    Assert-Equal "3개월이 지난 파일 8개를 지운다" 8 $n
    Assert-Equal "processed: 오래된 것 삭제 / 최근 것 남김" "False|True" ("{0}|{1}" -f (Exists "data\tasks\processed\old.json"), (Exists "data\tasks\processed\new.json"))
    Assert-Equal "outbox: 92일 삭제 / 85일 남김" "False|True" ("{0}|{1}" -f (Exists "data\tasks\outbox\old.md"), (Exists "data\tasks\outbox\new.md"))
    Assert-Equal "stuck · screenshots · process-ko · backups · prompts · running 의 오래된 것 삭제" $false ((Exists "data\tasks\stuck\old.json") -or (Exists "data\screenshots\old.png") -or (Exists "data\cache\process-ko\old.json") -or (Exists "data\backups\delegate.db.bak-x") -or (Exists "prompts\old.txt") -or (Exists "running\old.json"))
    Assert-Equal "  최근 파일은 남김" $true ((Exists "data\screenshots\new.png") -and (Exists "data\cache\process-ko\new.json"))
    Assert-Equal "inbox(처리 전 작업)는 오래돼도 지우지 않는다" $true (Exists "inbox\pending-old.json")
    Assert-Equal "delegate.db · 연결 정보 · 로그 · 하트비트는 지우지 않는다" $true ((Exists "data\delegate.db") -and (Exists "data\cache\claude-links.json") -and (Exists "logs\watcher.log") -and (Exists "heartbeat\hb_PC1.txt"))
    Assert-Equal "최상위 폴더는 비어도 남긴다" $true (Exists "data\tasks\stuck")

    New-File "data\tasks\processed\sub\deep\old.json" 150
    Remove-DelegationFilesOlderThan $work 3 | Out-Null
    Assert-Equal "비게 된 하위 폴더는 정리한다" $false (Exists "data\tasks\processed\sub")

    Assert-Equal "없는 런타임 폴더도 오류 없이 0" 0 (Remove-DelegationFilesOlderThan (Join-Path $work "없음") 3)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed -gt 0) { Write-Host "`n실패 $($script:Failed)건" -ForegroundColor Red; exit 1 }
Write-Host "`n모두 통과" -ForegroundColor Green
exit 0
