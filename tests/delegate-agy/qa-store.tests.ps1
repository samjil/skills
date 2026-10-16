# 위임 기록 저장소(SQLite) 쓰기 경로 시험. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\qa-store.tests.ps1
# 작업자가 작업 하나를 끝낼 때 그 작업 한 건만 채우는지(Complete-TaskQaRecord), 사용량 행이 먼저 들어가는지(Write-UsageRow),
# 중복·오류 경로·보충(Sync-QaStore)·보관 기간 정리(Initialize-QaStore)를 확인합니다.
# 워처 본체는 실행하지 않고 watch-agy.ps1/common.ps1 에서 함수만 꺼내 임시 폴더에서 돌립니다. 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$subDir   = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

# --- 임시 런타임 ---
$work = Join-Path ([IO.Path]::GetTempPath()) ("qa-store-test-" + [Guid]::NewGuid().ToString("N"))
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
$RuntimeDir   = $work
$LogsDir      = Join-Path $work "logs"
$AgyDbPath    = Join-Path $LogsDir "agy.db"
$InboxDir     = Join-Path $work "inbox"
$OutboxDir    = Join-Path $work "outbox"
$ProcessedDir = Join-Path $work "processed"
$ComputerName = "TESTPC"
$QaKeepMonths = 12; $QaProcessMaxSteps = 400
foreach ($d in @($LogsDir, $InboxDir, $OutboxDir, $ProcessedDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
function Log($msg) { }

. (Join-Path $subDir "common.ps1")
. (Join-Path $subDir "agy-progress.ps1")

# --- watch-agy.ps1 에서 필요한 정의만 꺼내 옵니다(워처 본체는 실행하지 않음) ---
$tokens = $null; $errs = $null
$astWatch = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $subDir "watch-agy.ps1"), [ref]$tokens, [ref]$errs)
Assert-Equal "watch-agy.ps1 에 문법 오류가 없다" 0 @($errs).Count
foreach ($name in @("Write-UsageRow", "Initialize-QaStore", "New-QaRecordFromRow", "Sync-QaStore", "Update-QAReport", "Complete-TaskQaRecord")) {
    $fn = $astWatch.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name 를 watch-agy.ps1 에서 찾지 못했습니다." }
    Invoke-Expression $fn.Extent.Text
}

# 작업자 프로세스 하나가 하는 일을 흉내 낸다: 지시파일·응답을 두고 사용량 행을 쓴다
function New-TaskFixture([string]$Id, [string]$Status = "OK", [bool]$WithUsage = $true) {
    Set-Content -LiteralPath (Join-Path $InboxDir "$Id.md") -Value "질문 $Id" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $OutboxDir "$Id.response.md") -Value "답 $Id" -Encoding UTF8
    if (-not $WithUsage) { return }
    if ($Status -eq "OK") { Write-UsageRow $Id "gemini-x" 1 "gemini-x" 10 20 5 35 12.3 "OK" "" "" }
    else { Write-UsageRow $Id $null $null "gemini-x" $null $null $null $null $null "ERROR" "" "" }
}
function Complete-Fixture([string]$Id) {
    Complete-TaskQaRecord $Id (Join-Path $InboxDir "$Id.md") (Join-Path $ProcessedDir "$Id.md")
}
function Get-Done { return (ConvertFrom-Json -InputObject (Get-QaRecordsJson $AgyDbPath 0)) }

try {
    Write-Host "Write-UsageRow: 사용량 행이 먼저 들어간다 (아직 끝난 기록이 아니다)"
    New-TaskFixture "task-a"
    $row = Get-QaTaskRow $AgyDbPath "task-a"
    Assert-Equal "행이 생긴다" "gemini-x|10|20|5|35|OK|TESTPC" ("{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f $row.model, $row.input_tokens, $row.output_tokens, $row.thinking_tokens, $row.total_tokens, $row.status, $row.computer_name)
    Assert-Equal "  시각이 들어 있다" $true ([bool]$row.timestamp)
    Assert-Equal "  질문·답은 아직 NULL" $true (($null -eq $row.question) -and ($null -eq $row.answer))
    Assert-Equal "  끝난 기록은 0건(뷰어에 안 보인다)" 0 (Get-Done).total
    Write-UsageRow "task-a" "OTHER" 9 "x" 9 9 9 9 9 "ERROR" "" ""
    Assert-Equal "  같은 작업 ID 의 사용량 행을 또 쓰면 먼저 쓴 것이 남는다" "gemini-x" (Get-QaTaskRow $AgyDbPath "task-a").model

    Write-Host "Complete-TaskQaRecord: 작업 한 건을 채운다"
    Complete-Fixture "task-a"
    $row = Get-QaTaskRow $AgyDbPath "task-a"
    Assert-Equal "질문은 processed 로 옮긴 지시파일 내용" "질문 task-a" ([string]$row.question).Trim()
    Assert-Equal "  답은 outbox 응답 내용" "답 task-a" ([string]$row.answer).Trim()
    Assert-Equal "  사용량 칸이 그대로 있다" "gemini-x|10|OK" ("{0}|{1}|{2}" -f $row.model, $row.input_tokens, $row.status)
    Assert-Equal "  대화 id 가 없으면 과정은 NULL(= 모름)" $true ($null -eq $row.process)
    Assert-Equal "  지시파일은 processed 로 옮겨졌다" $true ((Test-Path (Join-Path $ProcessedDir "task-a.md")) -and -not (Test-Path (Join-Path $InboxDir "task-a.md")))
    Assert-Equal "  끝난 기록 1건" 1 (Get-Done).total
    New-TaskFixture "task-b"
    Complete-Fixture "task-b"
    Assert-Equal "두 번째 작업도 한 건만 늘어난다" 2 (Get-Done).total

    Write-Host "중복 방지"
    Set-Content -LiteralPath (Join-Path $OutboxDir "task-a.response.md") -Value "다른 답" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $InboxDir "task-a.md") -Value "다시 온 지시" -Encoding UTF8
    Complete-Fixture "task-a"
    Assert-Equal "이미 끝난 작업은 다시 채우지 않는다(먼저 채운 답이 남는다)" "답 task-a" ([string](Get-QaTaskRow $AgyDbPath "task-a").answer).Trim()
    Assert-Equal "  건수도 그대로" 2 (Get-Done).total
    New-TaskFixture "task-c"
    [void](Sync-QaStore)    # 워처가 켜지면서 사용량 행만 있는 작업을 먼저 채워 넣은 상황
    Assert-Equal "보충이 먼저 채운 작업" "답 task-c" ([string](Get-QaTaskRow $AgyDbPath "task-c").answer).Trim()
    Complete-Fixture "task-c"
    Assert-Equal "  그 뒤 작업자가 마무리해도 한 건이다" 3 (Get-Done).total

    Write-Host "오류로 일찍 끝나는 작업 (사용량 행에 빈 칸)"
    New-TaskFixture "task-e" "ERROR"
    Complete-Fixture "task-e"
    $e = Get-QaTaskRow $AgyDbPath "task-e"
    Assert-Equal "상태 ERROR 로 한 건 기록된다" "ERROR" $e.status
    Assert-Equal "  토큰 칸은 빈 문자열(NULL 이 아니다)" "" ([string]$e.total_tokens)
    Assert-Equal "  빈 문자열이다(NULL 아님)" $false ($null -eq $e.total_tokens)

    Write-Host "사용량 행을 쓰지 못한 경우: 마무리가 전체 보충으로 물러서고 오류 없이 끝난다"
    New-TaskFixture "task-f" "OK" $false
    $threw = $false
    try { Complete-Fixture "task-f" } catch { $threw = $true }
    Assert-Equal "예외 없이 끝난다" $false $threw
    Assert-Equal "  지시파일은 processed 로 옮겨졌다" $true (Test-Path (Join-Path $ProcessedDir "task-f.md"))
    Assert-Equal "  사용량 행이 없으니 기록도 없다" $true ($null -eq (Get-QaTaskRow $AgyDbPath "task-f"))

    Write-Host "Sync-QaStore: 사용량 행만 있는 작업을 채운다"
    foreach ($id in @("task-g", "task-h", "task-i")) { New-TaskFixture $id }
    Assert-Equal "미완료가 3건" 3 @(Get-QaIncompleteRows $AgyDbPath).Count
    Assert-Equal "채운 건수 3" 3 (Sync-QaStore)
    Assert-Equal "  다시 돌리면 0건" 0 (Sync-QaStore)
    Assert-Equal "  지시파일이 아직 inbox 에 있어 processed 에 없으면 질문은 안내 문구" $true (([string](Get-QaTaskRow $AgyDbPath "task-g").question) -like "*원본 지시파일을 찾을 수 없음*")
    Assert-Equal "  답은 outbox 응답" "답 task-g" ([string](Get-QaTaskRow $AgyDbPath "task-g").answer).Trim()

    Write-Host "Initialize-QaStore: 보관 기간이 지난 기록을 정리한다"
    [void](Write-QaRecordToDb $AgyDbPath ([ordered]@{ task_id = "ancient"; timestamp = "2019-01-01 00:00:00"; question = "q"; answer = "a" }) 'Upsert')
    Assert-Equal "정리 전에는 있다" $true ($null -ne (Get-QaTaskRow $AgyDbPath "ancient"))
    Initialize-QaStore
    Assert-Equal "12개월이 지난 기록은 사라진다" $true ($null -eq (Get-QaTaskRow $AgyDbPath "ancient"))
    Assert-Equal "  최근 기록은 남는다" $true ($null -ne (Get-QaTaskRow $AgyDbPath "task-a"))

    Write-Host "watch-agy.ps1 의 작업자 경로"
    $body = $astWatch.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq "Invoke-InboxTaskBody" }, $true)
    $cmds = $body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    Assert-Equal "Invoke-InboxTaskBody 안에서 전체 보충(Update-QAReport)을 부르지 않는다" 0 @($cmds | Where-Object { $_.GetCommandName() -eq "Update-QAReport" }).Count
    Assert-Equal "  모델별 요약 CSV 갱신(Update-UsageSummary)도 부르지 않는다(CSV 는 필요할 때 내보낸다)" 0 @($cmds | Where-Object { $_.GetCommandName() -eq "Update-UsageSummary" }).Count
    Assert-Equal "  마무리는 세 곳(@model 오류, @cwd 오류, 정상/실패 끝)에서 Complete-TaskQaRecord 로 한다" 3 @($cmds | Where-Object { $_.GetCommandName() -eq "Complete-TaskQaRecord" }).Count

    Write-Host "New-QaRecord: 기록 틀(워처와 log-qa.ps1 이 같이 쓴다)"
    $rw = New-QaRecord ([ordered]@{ answer = "a"; task_id = "t1"; question = "q"; status = "OK"; timestamp = "2026-10-16 10:00:00" })
    Assert-Equal "칸 순서는 틀을 따른다(넣은 순서와 무관)" "timestamp,task_id,status,question,answer" (@($rw.Keys) -join ",")
    Assert-Equal "log-qa 의 기록에만 있는 source 는 넣으면 들어간다" $true ((New-QaRecord ([ordered]@{ task_id = "t"; source = "mcp" })).Contains("source"))
    Assert-Equal "넣지 않은 칸(워처의 토큰 칸 등)은 빈 값으로 만들지 않는다" $false ($rw.Contains("input_tokens"))
    $threw = $false
    try { [void](New-QaRecord ([ordered]@{ task_id = "t"; qustion = "오타" })) } catch { $threw = $true }
    Assert-Equal "모르는 칸 이름(오타)은 오류다" $true $threw
    $etsFile = Join-Path $work "ets.txt"
    [System.IO.File]::WriteAllText($etsFile, "파일 내용", (New-Object System.Text.UTF8Encoding($false)))
    $etsText = Get-Content -Raw -LiteralPath $etsFile -Encoding UTF8
    $recEts = New-QaRecord ([ordered]@{ task_id = "t"; question = $etsText; answer = $etsText })
    Assert-Equal "Get-Content -Raw 의 숨은 속성이 붙은 글도 일반 문자열이 된다(직렬화가 작다)" $true ((ConvertTo-Json -InputObject $recEts -Compress).Length -lt 400)
    Assert-Equal "question 은 문자열 형식이다" "System.String" $recEts.question.GetType().FullName
    $long = "가" * 25000
    $recLong = New-QaRecord ([ordered]@{ task_id = "t"; question = $long; answer = $long })
    Assert-Equal "question 은 20000자에서 잘리고 안내가 붙는다" $true (($recLong.question.Length -gt 20000) -and ($recLong.question.Length -lt 20200) -and ($recLong.question -like "*일부 생략됨*"))
    Assert-Equal "process 는 그대로(배열 유지)" 2 @((New-QaRecord ([ordered]@{ task_id = "t"; process = @("a", "b") })).process).Count
    Assert-Equal "process 가 `$null 이면 `$null 그대로(= 모름)" $true ($null -eq (New-QaRecord ([ordered]@{ task_id = "t"; process = $null })).process)
    Assert-Equal "숫자도 문자열로(사용량 행처럼)" "System.String" (New-QaRecord ([ordered]@{ task_id = "t"; attempts = 2 })).attempts.GetType().FullName
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
