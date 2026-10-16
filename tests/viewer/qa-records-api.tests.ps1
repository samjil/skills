# 뷰어의 위임 기록 API(/api/qa/records) 시험. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\qa-records-api.tests.ps1
# 임시 런타임 폴더(DB)로 뷰어를 -NoAgent 로 실제로 띄웁니다(진짜 뷰어·워처·기록은 건드리지 않습니다. 몇 초).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$viewerScript = Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("qa-records-api-test-" + [Guid]::NewGuid().ToString("N"))
$rt = Join-Path $work "runtime"
foreach ($d in @("inbox", "outbox", "processed", "logs", "logs\data", "logs\heartbeat")) { New-Item -ItemType Directory -Force -Path (Join-Path $rt $d) | Out-Null }
New-Item -ItemType Directory -Force -Path (Join-Path $work "handoff") | Out-Null
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
$env:AGY_DELEGATE_RUNTIME = $rt
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-db.ps1")
$dbPath = Join-Path $rt "logs\agy.db"

function Get-Api([string]$Query) {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/qa/records$Query" -TimeoutSec 10
    $text = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    return @{ Status = [int]$resp.StatusCode; Text = $text; Json = (ConvertFrom-Json -InputObject $text); Headers = $resp.Headers }
}

$port = Get-Random -Minimum 30000 -Maximum 40000
$viewer = $null
try {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$viewerScript`"", "-NoBrowser", "-NoAgent", "-Port", $port,
        "-DataDir", "`"$(Join-Path $rt 'logs\data')`"", "-HandoffDir", "`"$(Join-Path $work 'handoff')`"")
    $viewer = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden -PassThru
    $up = $false
    for ($i = 0; $i -lt 40 -and -not $up; $i++) {
        Start-Sleep -Milliseconds 500
        try { $up = ((Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/status" -TimeoutSec 2).StatusCode -eq 200) } catch {}
    }
    Assert-Equal "뷰어가 응답한다" $true $up

    Write-Host "DB 가 아직 없을 때"
    $a = Get-Api "?since=0"
    Assert-Equal "빈 목록을 200 으로 돌려준다" "200|0|0|0" ("{0}|{1}|{2}|{3}" -f $a.Status, @($a.Json.records).Count, $a.Json.total, $a.Json.seq)

    Write-Host "기록이 있을 때"
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ timestamp = "2026-10-16 10:00:00"; computer_name = "PC"; task_id = "a1"; model = "m"; status = "OK"; question = "질문 `"하나`"`n둘째 줄"; answer = "답"; process = @([pscustomobject]@{ n = 1; tool = "run_command"; detail = "x" }) }) 'Upsert')
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ timestamp = "2026-10-16 10:05:00"; computer_name = "PC"; task_id = "a2"; model = "m"; status = "OK"; question = "q2"; answer = "a2" }) 'Upsert')
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ timestamp = "2026-10-16 10:10:00"; computer_name = "PC"; task_id = "a3-usage-only"; model = "m"; status = "OK" }) 'InsertOnly')
    $a = Get-Api "?since=0"
    Assert-Equal "끝난 기록 2건만 보인다(사용량만 있는 행은 숨는다)" "2|2" ("{0}|{1}" -f @($a.Json.records).Count, $a.Json.total)
    $byId = @{}; foreach ($r in @($a.Json.records)) { $byId[$r.task_id] = $r }
    Assert-Equal "  질문이 그대로(따옴표·줄바꿈)" "질문 `"하나`"`n둘째 줄" $byId["a1"].question
    Assert-Equal "  과정이 객체 배열로 나간다" "run_command" @($byId["a1"].process)[0].tool
    Assert-Equal "  값이 없는 칸(source·process)은 키가 없다" $false ($byId["a2"].PSObject.Properties.Name -contains "process")
    Assert-Equal "  Cache-Control: no-store" "no-store" ([string]$a.Headers["Cache-Control"])
    Assert-Equal "  JSON 콘텐츠 형식" $true ([string]$a.Headers["Content-Type"] -like "application/json*")
    $seq1 = [long]$a.Json.seq
    Assert-Equal "  seq 는 0 보다 크다" $true ($seq1 -gt 0)

    Write-Host "증분 조회"
    $b = Get-Api "?since=$seq1"
    Assert-Equal "since=seq 이면 새 기록 0건, total 은 그대로" "0|2|$seq1" ("{0}|{1}|{2}" -f @($b.Json.records).Count, $b.Json.total, $b.Json.seq)
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ task_id = "a3-usage-only"; question = "q3"; answer = "a3" }) 'FillIfIncomplete')
    $c = Get-Api "?since=$seq1"
    Assert-Equal "사용량만 있던 행이 채워지면 그 한 건만 새로 온다" "1|a3-usage-only|3" ("{0}|{1}|{2}" -f @($c.Json.records).Count, @($c.Json.records)[0].task_id, $c.Json.total)
    Assert-Equal "  seq 가 커진다" $true ([long]$c.Json.seq -gt $seq1)
    Assert-Equal "since 가 숫자가 아니면 0 으로 본다(전부)" 3 @((Get-Api "?since=abc").Json.records).Count
    Assert-Equal "since 가 없어도 전부" 3 @((Get-Api "").Json.records).Count
}
finally {
    if ($viewer -and -not $viewer.HasExited) { Stop-Process -Id $viewer.Id -Force -ErrorAction SilentlyContinue }
    $env:AGY_DELEGATE_RUNTIME = $null
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
