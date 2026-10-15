# 기록 저장소(qa-*.jsonl) 쓰기 경로 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\qa-store.tests.ps1
# 작업자가 작업 하나를 끝낼 때 전체 기록을 다시 읽지 않고 그 작업 한 건만 덧붙이는지(Complete-TaskQaRecord),
# 줄이 끊긴 파일 뒤에 새 기록이 같은 줄로 이어 붙지 않는지(Add-QaLine), 중복·오류 경로·폴백을 확인합니다.
# 워처 본체는 실행하지 않고 watch-agy.ps1/common.ps1 에서 함수만 꺼내 임시 폴더에서 돌립니다. 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$subDir   = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub"
. (Join-Path $subDir "common.ps1")
. (Join-Path $subDir "agy-progress.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

# --- watch-agy.ps1 에서 필요한 정의만 꺼내 옵니다(워처 본체는 실행하지 않음) ---
$tokens = $null; $errs = $null
$astWatch = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $subDir "watch-agy.ps1"), [ref]$tokens, [ref]$errs)
Assert-Equal "watch-agy.ps1 에 문법 오류가 없다" 0 @($errs).Count
$assign = $astWatch.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $n.Left.VariablePath.UserPath -eq "UsageCsvHeader" }, $true)
Invoke-Expression $assign.Extent.Text
foreach ($name in @("Truncate-Text", "Invoke-WithRuntimeLock", "Write-UsageRowUnlocked", "Initialize-QaStore", "New-QaRecordFromRow", "Sync-QaStore",
        "Update-QaIndex", "Update-QAReportUnlocked", "Test-QaTaskIdInShardTail", "Get-QaIndexTotal", "Complete-TaskQaRecord")) {
    $fn = $astWatch.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name 를 watch-agy.ps1 에서 찾지 못했습니다." }
    Invoke-Expression $fn.Extent.Text
}

# --- 임시 런타임 ---
$work = Join-Path ([IO.Path]::GetTempPath()) ("qa-store-test-" + [Guid]::NewGuid().ToString("N"))
$RuntimeDir   = $work
$LogsDir      = Join-Path $work "logs"
$DataDir      = Join-Path $LogsDir "data"
$QaIndexFile  = Join-Path $DataDir "index.json"
$InboxDir     = Join-Path $work "inbox"
$OutboxDir    = Join-Path $work "outbox"
$ProcessedDir = Join-Path $work "processed"
$UsageCsv     = Join-Path $LogsDir "usage.csv"
$ComputerName = "TESTPC"
$QaShardMaxBytes = 5MB; $QaKeepMonths = 12; $QaProcessMaxSteps = 400; $UsageMaxBytes = 2MB; $UsageKeepLines = 3000
foreach ($d in @($LogsDir, $DataDir, $InboxDir, $OutboxDir, $ProcessedDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
function Log($msg) { }
$script:QaKnownIds = $null
$script:QaTotal = 0
$script:FirstUsageRow = $null

function Get-ShardPathNow { return (Get-QaShardPath) }
function Read-ShardRecords([string]$Path) {
    $out = @()
    foreach ($l in @([IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8))) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $r = $null
        try { $r = $l | ConvertFrom-Json } catch { continue }
        if ($r) { $out += $r }
    }
    return @($out)
}
# 작업자 프로세스 하나가 하는 일을 흉내 낸다: 지시파일·응답을 두고 usage 행을 쓴다(프로세스 시작 상태로 되돌린 뒤).
function New-TaskFixture([string]$Id, [string]$Status = "OK") {
    Set-Content -LiteralPath (Join-Path $InboxDir "$Id.md") -Value "질문 $Id" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $OutboxDir "$Id.response.md") -Value "답 $Id" -Encoding UTF8
    $script:QaKnownIds = $null
    $script:QaTotal = 0
    $script:FirstUsageRow = $null
    if ($Status -eq "OK") { Write-UsageRowUnlocked $Id "gemini-x" 1 "gemini-x" 10 20 5 35 12.3 "OK" "" "" }
    else { Write-UsageRowUnlocked $Id $null $null "gemini-x" $null $null $null $null $null "ERROR" "" "" }
}
function Complete-Fixture([string]$Id) {
    Complete-TaskQaRecord $Id (Join-Path $InboxDir "$Id.md") (Join-Path $ProcessedDir "$Id.md")
}

try {
    Write-Host "Add-QaLine"
    $p = Join-Path $work "unit.jsonl"
    Add-QaLine $p '{"a":1}'
    $bytes = [IO.File]::ReadAllBytes($p)
    Assert-Equal "새 파일에는 BOM 이 없다" $false (($bytes.Length -ge 3) -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Assert-Equal "한 줄이 줄바꿈으로 끝난다" 10 $bytes[$bytes.Length - 1]
    Add-QaLine $p '{"a":2}'
    Assert-Equal "정상 파일 뒤에는 빈 줄 없이 이어 붙는다" 2 @([IO.File]::ReadAllLines($p)).Count
    [IO.File]::AppendAllText($p, '{"a":3,"q":"끊긴')
    Add-QaLine $p '{"a":4}'
    $lines = @([IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8))
    Assert-Equal "끊긴 줄 뒤에는 줄바꿈부터 써서 새 기록이 따로 선다 (3줄째=끊긴 줄, 4줄째=새 기록)" '{"a":4}' $lines[3]
    Assert-Equal "  끊긴 줄은 그대로 남는다" '{"a":3,"q":"끊긴' $lines[2]
    $merged = $false
    foreach ($l in $lines) { if ($l.IndexOf('{', 1) -ge 0 -and $l.StartsWith('{') -and $l.EndsWith('}') -and ($l -match '"q":"끊긴\{')) { $merged = $true } }
    Assert-Equal "  두 기록이 한 줄로 합쳐지지 않는다" $false $merged

    Write-Host "Complete-TaskQaRecord: 작업 한 건만 덧붙인다"
    New-TaskFixture "task-a"
    Complete-Fixture "task-a"
    $shard = Get-ShardPathNow
    $recs = Read-ShardRecords $shard
    Assert-Equal "레코드가 한 건 생긴다" 1 $recs.Count
    Assert-Equal "  작업 ID" "task-a" $recs[0].task_id
    Assert-Equal "  질문은 processed 로 옮긴 지시파일 내용" "질문 task-a" ([string]$recs[0].question).Trim()
    Assert-Equal "  답은 outbox 응답 내용" "답 task-a" ([string]$recs[0].answer).Trim()
    Assert-Equal "  usage 행의 토큰·모델·상태가 그대로 들어간다" "gemini-x|10|20|5|35|OK" ("{0}|{1}|{2}|{3}|{4}|{5}" -f $recs[0].model, $recs[0].input_tokens, $recs[0].output_tokens, $recs[0].thinking_tokens, $recs[0].total_tokens, $recs[0].status)
    Assert-Equal "  지시파일은 processed 로 옮겨졌다" $true ((Test-Path (Join-Path $ProcessedDir "task-a.md")) -and -not (Test-Path (Join-Path $InboxDir "task-a.md")))
    Assert-Equal "  전체 읽기(Initialize-QaStore)를 하지 않았다" $true ($null -eq $script:QaKnownIds)
    $idx = Get-Content -Raw -LiteralPath $QaIndexFile -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal "  index.json 의 샤드 바이트가 실제 파일 크기와 같다" (Get-Item $shard).Length $idx.shards[0].bytes
    Assert-Equal "  index.json 의 건수 1" 1 $idx.total

    New-TaskFixture "task-b"
    Complete-Fixture "task-b"
    Assert-Equal "두 번째 작업도 한 건만 늘어난다" 2 (Read-ShardRecords $shard).Count
    Assert-Equal "  index.json 건수 2" 2 ((Get-Content -Raw -LiteralPath $QaIndexFile -Encoding UTF8 | ConvertFrom-Json).total)

    Write-Host "중복 방지"
    New-TaskFixture "task-c"
    $script:QaKnownIds = $null
    [void](Sync-QaStore)    # 워처가 켜지면서 usage.csv 를 보고 먼저 채워 넣은 상황
    $script:QaKnownIds = $null; $script:QaTotal = 0
    Complete-Fixture "task-c"
    $cRecs = @(Read-ShardRecords $shard | Where-Object { $_.task_id -eq "task-c" })
    Assert-Equal "이미 들어간 작업은 다시 덧붙이지 않는다" 1 $cRecs.Count

    Write-Host "깨진 줄이 있는 파일"
    [IO.File]::AppendAllText($shard, '{"timestamp":"x","task_id":"BROKEN","question":"끊긴')
    New-TaskFixture "task-d"
    Complete-Fixture "task-d"
    $all = @([IO.File]::ReadAllLines($shard, [Text.Encoding]::UTF8))
    $dLine = @($all | Where-Object { $_.Contains('"task_id":"task-d"') })
    Assert-Equal "새 기록이 자기 줄에 선다" 1 $dLine.Count
    Assert-Equal "  그 줄은 {로 시작해 }로 끝나고 JSON 으로 읽힌다" $true ($dLine[0].StartsWith('{') -and $dLine[0].EndsWith('}') -and ($null -ne ($dLine[0] | ConvertFrom-Json)))
    $script:QaKnownIds = $null; $script:QaTotal = 0
    Initialize-QaStore
    Assert-Equal "  시작할 때의 엄격한 읽기는 깨진 줄만 건너뛴다 (task-a,b,c,d = 4건)" 4 $script:QaTotal
    Assert-Equal "  깨진 줄의 작업 ID 는 '이미 저장됨'으로 치지 않는다" $false $script:QaKnownIds.Contains("BROKEN")

    Write-Host "오류로 일찍 끝나는 작업 (usage 행에 빈 칸)"
    New-TaskFixture "task-e" "ERROR"
    Complete-Fixture "task-e"
    $e = @(Read-ShardRecords $shard | Where-Object { $_.task_id -eq "task-e" })
    Assert-Equal "상태 ERROR 로 한 건 기록된다" "ERROR" $e[0].status
    Assert-Equal "  토큰 칸은 빈 문자열" "" ([string]$e[0].total_tokens)

    Write-Host "usage 행을 이 프로세스가 못 쓴 경우: 전체 동기화로 물러선다"
    New-TaskFixture "task-f"
    $script:FirstUsageRow = $null
    Complete-Fixture "task-f"
    $f = @(Read-ShardRecords $shard | Where-Object { $_.task_id -eq "task-f" })
    Assert-Equal "usage.csv 기준으로 한 건 채워진다" 1 $f.Count

    Write-Host "Test-QaTaskIdInShardTail"
    $t = Join-Path $work "tail.jsonl"
    Add-QaLine $t ('{"timestamp":"1","task_id":"OTHER","question":"본문에 \"task_id\": \"TARGET\" 라고 적힌 질문","answer":"x"}')
    Assert-Equal "다른 기록의 본문에 적힌 같은 글자는 '있음'이 아니다" $false (Test-QaTaskIdInShardTail $t "TARGET")
    Assert-Equal "자기 작업 ID 는 찾는다" $true (Test-QaTaskIdInShardTail $t "OTHER")
    Add-QaLine $t ('{"timestamp":"2","task_id":"OLD","question":"' + ("가" * 4000) + '"}')
    for ($i = 0; $i -lt 20; $i++) { Add-QaLine $t ('{"timestamp":"3","task_id":"N' + $i + '","question":"' + ("나" * 4000) + '"}') }
    Assert-Equal "꼬리 밖(아주 오래된 기록)은 보지 않는다 - 설계상 한계" $false (Test-QaTaskIdInShardTail $t "OLD" 20000)
    Assert-Equal "꼬리 안의 기록은 찾는다 (읽기 시작 지점에서 잘린 첫 줄은 버림)" $true (Test-QaTaskIdInShardTail $t "N19" 20000)

    Write-Host "Sync-QaStore (전체 동기화는 그대로 동작한다)"
    $script:QaKnownIds = $null; $script:QaTotal = 0
    Remove-Item -LiteralPath $shard -Force
    $added = Sync-QaStore
    Assert-Equal "usage.csv 의 작업 6건이 모두 채워진다" 6 $added
    Assert-Equal "  다시 돌리면 0건" 0 (Sync-QaStore)

    Write-Host "watch-agy.ps1 의 작업자 경로"
    $body = $astWatch.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq "Invoke-InboxTaskBody" }, $true)
    $cmds = $body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    Assert-Equal "Invoke-InboxTaskBody 안에서 전체 동기화(Update-QAReport)를 부르지 않는다" 0 @($cmds | Where-Object { $_.GetCommandName() -eq "Update-QAReport" }).Count
    Assert-Equal "  마무리는 세 곳(@model 오류, @cwd 오류, 정상/실패 끝)에서 Complete-TaskQaRecord 로 한다" 3 @($cmds | Where-Object { $_.GetCommandName() -eq "Complete-TaskQaRecord" }).Count
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
