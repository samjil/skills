# agy-layout.ps1(위임 폴더 배치와 옛 배치 이전) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-layout.tests.ps1
# 임시 폴더만 씁니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-layout.ps1")
Remove-Item Env:\AGY_DELEGATE_DATA -ErrorAction SilentlyContinue

$script:Failed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("agy-layout-test-" + [Guid]::NewGuid().ToString("N"))
function New-File([string]$path, [string]$text = "x") {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    $text | Set-Content -LiteralPath $path
}

try {
    Write-Host "경로 규칙"
    $rt = Join-Path $work "delegate-agy\runtime"
    $L = Get-AgyLayout $rt "PC1"
    Assert-Equal "런타임 폴더 이름이 runtime 이면 data 는 그 옆" (Join-Path $work "delegate-agy\data") $L.DataDir
    Assert-Equal "DB 는 data\delegate.db" (Join-Path $work "delegate-agy\data\delegate.db") $L.DbPath
    Assert-Equal "처리 파일은 data\tasks 아래" "processed|outbox|stuck" ((Split-Path $L.ProcessedDir -Leaf) + "|" + (Split-Path $L.OutboxDir -Leaf) + "|" + (Split-Path $L.StuckDir -Leaf))
    Assert-Equal "하트비트·잠금·정지 표시는 runtime 바로 아래(logs 밖)" $true (($L.HeartbeatDir -eq (Join-Path $rt "heartbeat")) -and ($L.LockFile -eq (Join-Path $rt "watcher_PC1.lock")) -and ($L.ManualStopFlag -eq (Join-Path $rt "manual_stop.flag")))
    Assert-Equal "logs 는 runtime\logs" (Join-Path $rt "logs") $L.LogsDir
    Assert-Equal "이름이 runtime 이 아니면 data 는 그 안(시험용 임시 폴더)" (Join-Path $work "x1\data") (Get-AgyDataDir (Join-Path $work "x1"))

    Write-Host "옛 배치 이전"
    $old = Join-Path $work "old\runtime"
    New-File (Join-Path $old "outbox\a.response.md")
    New-File (Join-Path $old "processed\a.md")
    New-File (Join-Path $old "_stuck\s.json")
    New-File (Join-Path $old "screenshots\s.png")
    New-File (Join-Path $old "inbox\pending.json")
    New-File (Join-Path $old "logs\agy.db") "DB"
    New-File (Join-Path $old "logs\agy.db.bak-1") "BAK"
    New-File (Join-Path $old "logs\heartbeat\hb_PC1.txt")
    New-File (Join-Path $old "logs\running\t.json")
    New-File (Join-Path $old "logs\prompts\p.txt")
    New-File (Join-Path $old "logs\watcher_PC1.lock") "123"
    New-File (Join-Path $old "logs\manual_stop.flag")
    New-File (Join-Path $old "logs\watcher.log") "LOG"
    New-File (Join-Path $old "logs\data\claude-links.json")
    New-File (Join-Path $old "logs\data\process-ko\c.json")
    New-File (Join-Path $old "logs\data\qa-2026-09.jsonl.bak-1")
    New-File (Join-Path $old "logs\legacy-1\x.csv")
    $O = Get-AgyLayout $old "PC1"
    $n = Move-AgyLegacyLayout $old
    Assert-Equal "옮긴 항목이 있다" $true ($n -ge 12)
    Assert-Equal "outbox · processed · stuck · screenshots → data" $true ((Test-Path (Join-Path $O.OutboxDir "a.response.md")) -and (Test-Path (Join-Path $O.ProcessedDir "a.md")) -and (Test-Path (Join-Path $O.StuckDir "s.json")) -and (Test-Path (Join-Path $O.ScreenshotsDir "s.png")))
    Assert-Equal "DB 는 delegate.db 로(내용 유지)" "DB" ((Get-Content -LiteralPath $O.DbPath) -join "")
    Assert-Equal "DB 백업은 backups\delegate.db.bak-*" $true (Test-Path (Join-Path $O.BackupsDir "delegate.db.bak-1"))
    Assert-Equal "하트비트 · running · prompts · 잠금 · 정지 표시 → runtime" $true ((Test-Path (Join-Path $O.HeartbeatDir "hb_PC1.txt")) -and (Test-Path (Join-Path $O.RunningDir "t.json")) -and (Test-Path (Join-Path $O.PromptsDir "p.txt")) -and (Test-Path $O.LockFile) -and (Test-Path $O.ManualStopFlag))
    Assert-Equal "연결 정보 · 번역 캐시 → data\cache" $true ((Test-Path (Join-Path $O.CacheDir "claude-links.json")) -and (Test-Path (Join-Path $O.CacheDir "process-ko\c.json")))
    Assert-Equal "옛 샤드 백업 · legacy → backups" $true ((Test-Path (Join-Path $O.BackupsDir "qa-2026-09.jsonl.bak-1")) -and (Test-Path (Join-Path $O.BackupsDir "legacy-1\x.csv")))
    Assert-Equal "inbox 와 logs\watcher.log 는 그대로" $true ((Test-Path (Join-Path $old "inbox\pending.json")) -and (Test-Path (Join-Path $old "logs\watcher.log")))
    Assert-Equal "옛 위치에는 남지 않는다" $false ((Test-Path (Join-Path $old "outbox")) -or (Test-Path (Join-Path $old "logs\agy.db")) -or (Test-Path (Join-Path $old "logs\data")))
    Assert-Equal "다시 불러도 안전(0건)" 0 (Move-AgyLegacyLayout $old)

    Write-Host "충돌 시 덮어쓰지 않음"
    $old2 = Join-Path $work "old2\runtime"
    New-File (Join-Path $old2 "logs\agy.db") "OLD"
    $O2 = Get-AgyLayout $old2 "PC1"
    New-File $O2.DbPath "NEW"
    Move-AgyLegacyLayout $old2 | Out-Null
    Assert-Equal "새 DB 가 이미 있으면 그대로 두고 옛 DB 도 지우지 않는다" "NEW|OLD" (((Get-Content -LiteralPath $O2.DbPath) -join "") + "|" + ((Get-Content -LiteralPath (Join-Path $old2 "logs\agy.db")) -join ""))

    Write-Host "새 위치에 빈 폴더만 있을 때"
    $old3 = Join-Path $work "old3\runtime"
    New-File (Join-Path $old3 "outbox\z.md")
    $O3 = Get-AgyLayout $old3 "PC1"
    New-Item -ItemType Directory -Force -Path $O3.OutboxDir | Out-Null
    Move-AgyLegacyLayout $old3 | Out-Null
    Assert-Equal "빈 폴더는 치우고 옮긴다" $true (Test-Path (Join-Path $O3.OutboxDir "z.md"))
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed -gt 0) { Write-Host "`n실패 $($script:Failed)건" -ForegroundColor Red; exit 1 }
Write-Host "`n모두 통과" -ForegroundColor Green
exit 0
