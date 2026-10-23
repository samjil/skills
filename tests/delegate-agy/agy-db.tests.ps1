# 위임 기록·세션 저장소(SQLite, agy-db.ps1) 시험. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-db.tests.ps1
# 임시 폴더의 DB 와 임시 컴파일 캐시만 씁니다. 이 PC 의 실제 기록(~\.samjil)은 건드리지 않습니다. 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$modulePath = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-db.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("agy-db-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
. $modulePath
$dbPath = Join-Path $work "logs\agy.db"

# 창 없이 PowerShell 을 띄운다(시험이 콘솔 창을 깜빡이지 않게)
function Start-HiddenPowerShell([string[]]$ArgumentList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = (@($ArgumentList | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}

try {
    Write-Host "컴파일 캐시"
    Initialize-AgySqlite
    Assert-Equal "  형식을 불러왔다" $true ([bool]('AgySqlite.Db' -as [type]))
    Assert-Equal "  캐시 폴더에 어셈블리가 생겼다" 1 @(Get-ChildItem $env:AGY_DB_CACHE_DIR -Filter "agy-sqlite-*.dll" | Where-Object { $_.Name -notlike "*.tmp.dll" }).Count

    Write-Host "스키마"
    $db = Open-AgyDb $dbPath
    $tables = @($db.Query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name", $null) | ForEach-Object { $_["name"] })
    Assert-Equal "  표 세 개" "agy_sessions,meta,tasks" ($tables -join ",")
    Assert-Equal "  WAL 모드" "wal" ($db.Query("PRAGMA journal_mode", $null))[0]["journal_mode"]
    Assert-Equal "  스키마 버전" 1 ([int]($db.Query("PRAGMA user_version", $null))[0]["user_version"])
    $db.Dispose()
    $db = Open-AgyDb $dbPath
    Assert-Equal "  다시 열어도 그대로(표 세 개)" 3 @($db.Query("SELECT name FROM sqlite_master WHERE type='table'", $null)).Count
    $db.Dispose()

    Write-Host "값 바인딩: 한글·따옴표·줄바꿈·빈 문자열과 NULL 의 구별"
    $db = Open-AgyDb $dbPath
    [void]$db.Execute("INSERT INTO meta (key, value) VALUES (?, ?)", [object[]]@("한글 키", "따옴표 ' `" 와 줄바꿈`n끝 \ 역슬래시"))
    [void]$db.Execute("INSERT INTO meta (key, value) VALUES (?, ?)", [object[]]@("empty", ""))
    [void]$db.Execute("INSERT INTO meta (key, value) VALUES (?, ?)", [object[]]@("nullv", $null))
    Assert-Equal "  한글·따옴표·줄바꿈이 그대로 돌아온다" "따옴표 ' `" 와 줄바꿈`n끝 \ 역슬래시" (Get-AgyMeta $db "한글 키")
    Assert-Equal "  빈 문자열은 빈 문자열이다(NULL 이 아니다)" $false ($null -eq (Get-AgyMeta $db "empty"))
    $nullRow = $db.Query("SELECT value FROM meta WHERE key='nullv'", $null)[0]
    Assert-Equal "  NULL 은 NULL 이다" $true ($null -eq $nullRow["value"])
    $threw = $false
    try { [void]$db.Execute("INSERT INTO meta (key, value) VALUES (?, ?)", [object[]]@("empty", "x")) } catch { $threw = $true }
    Assert-Equal "  기본키 중복은 오류" $true $threw
    $db.Dispose()

    Write-Host "기록 저장 방식 3가지"
    Assert-Equal "  사용량 행 먼저(InsertOnly)" "saved" (Write-QaRecordToDb $dbPath ([ordered]@{ timestamp = "2026-10-16 10:00:00"; computer_name = "PC"; task_id = "t1"; model = "m"; input_tokens = 10; status = "OK" }) 'InsertOnly')
    Assert-Equal "  같은 작업 ID 를 InsertOnly 로 또 쓰면 건너뛴다" "skipped" (Write-QaRecordToDb $dbPath ([ordered]@{ task_id = "t1"; model = "OTHER" }) 'InsertOnly')
    $row = Get-QaTaskRow $dbPath "t1"
    Assert-Equal "  먼저 쓴 값이 남는다" "m|10" ("{0}|{1}" -f $row.model, $row.input_tokens)
    Assert-Equal "  아직 답이 비어 있다(NULL)" $true ($null -eq $row.answer)
    Assert-Equal "  미완료 목록에 1건" 1 @(Get-QaIncompleteRows $dbPath).Count
    Assert-Equal "  끝난 기록은 아직 0건(JSON total)" 0 (ConvertFrom-Json -InputObject (Get-QaRecordsJson $dbPath 0)).total

    $steps = @([pscustomobject]@{ n = 1; tool = "run_command"; detail = "한글 `"따옴표`" \ 역슬래시"; label = "L" })
    Assert-Equal "  FillIfIncomplete 로 질문·답·과정을 채운다" "saved" (Write-QaRecordToDb $dbPath ([ordered]@{ task_id = "t1"; question = "질문`n두 번째 줄 \ `" '"; answer = "답"; process = $steps }) 'FillIfIncomplete')
    Assert-Equal "  이미 끝난 기록에 FillIfIncomplete 는 건너뛴다" "skipped" (Write-QaRecordToDb $dbPath ([ordered]@{ task_id = "t1"; question = "덮어쓰기 시도"; answer = "X" }) 'FillIfIncomplete')
    Assert-Equal "  미완료 목록은 비었다" 0 @(Get-QaIncompleteRows $dbPath).Count

    Write-Host "뷰어 API 본문(Get-QaRecordsJson)"
    $j = ConvertFrom-Json -InputObject (Get-QaRecordsJson $dbPath 0)
    $rec = @($j.records)[0]
    Assert-Equal "  끝난 기록 1건" 1 $j.total
    Assert-Equal "  질문이 그대로(줄바꿈·역슬래시·따옴표)" "질문`n두 번째 줄 \ `" '" $rec.question
    Assert-Equal "  먼저 쓴 사용량 칸이 유지된다" "m|10|OK" ("{0}|{1}|{2}" -f $rec.model, $rec.input_tokens, $rec.status)
    Assert-Equal "  과정 단계가 객체 배열로 나간다" "run_command|한글 `"따옴표`" \ 역슬래시" ("{0}|{1}" -f @($rec.process)[0].tool, @($rec.process)[0].detail)
    Assert-Equal "  값이 NULL 인 칸(source)은 키를 만들지 않는다" $false ($rec.PSObject.Properties.Name -contains "source")
    $seq1 = [long]$j.seq
    Assert-Equal "  since=seq 이면 새 기록 0건" 0 @((ConvertFrom-Json -InputObject (Get-QaRecordsJson $dbPath $seq1)).records).Count

    [void](Write-QaRecordToDb $dbPath ([ordered]@{ task_id = "t2"; timestamp = "2026-10-16 11:00:00"; question = "q"; answer = "a"; process = @() }) 'Upsert')
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ task_id = "t3"; timestamp = "2026-10-16 12:00:00"; question = ""; answer = ""; process = $null }) 'Upsert')
    $j3 = ConvertFrom-Json -InputObject (Get-QaRecordsJson $dbPath $seq1)
    $byId = @{}; foreach ($x in @($j3.records)) { $byId[$x.task_id] = $x }
    Assert-Equal "  증분 조회는 새 기록 2건만" 2 @($j3.records).Count
    Assert-Equal "  process=[] 는 '없음'(빈 배열, 키 있음)" "0|True" ("{0}|{1}" -f @($byId["t2"].process).Count, ($byId["t2"].PSObject.Properties.Name -contains "process"))
    Assert-Equal "  process=`$null 은 '모름'(키 없음)" $false ($byId["t3"].PSObject.Properties.Name -contains "process")
    Assert-Equal "  빈 문자열 답도 끝난 기록이다" "" $byId["t3"].answer
    Assert-Equal "  ConvertTo-AgyJsonString 은 제어문자도 JSON 으로 읽힌다" "a`tb$([char]1)c" (ConvertFrom-Json -InputObject ("[" + (ConvertTo-AgyJsonString "a`tb$([char]1)c") + "]"))

    Write-Host "모르는 칸과 task_id 없음은 오류"
    $threw = $false; try { [void](Write-QaRecordToDb $dbPath ([ordered]@{ task_id = "x"; qustion = "오타" }) 'Upsert') } catch { $threw = $true }
    Assert-Equal "  모르는 칸 이름(오타)" $true $threw
    $threw = $false; try { [void](Write-QaRecordToDb $dbPath ([ordered]@{ question = "q" }) 'Upsert') } catch { $threw = $true }
    Assert-Equal "  task_id 없음" $true $threw

    Write-Host "세션"
    $db = Open-AgyDb $dbPath
    Invoke-AgyDbTransaction $db { Set-AgySessionRow $db (Get-AgySessionKey "내 세션/1") "conv-1" @("D:\a", "D:\b") "m" "2026-10-16 10:00:00" "2026-10-16 10:00:00" 1 }
    $s = Get-AgySessionRow $db (Get-AgySessionKey "내 세션/1")
    Assert-Equal "  폴더 둘" "D:\a|D:\b|2" ("{0}|{1}" -f (@($s.cwd) -join "|"), @($s.cwd).Count)
    Assert-Equal "  나머지 칸" "conv-1|m|1" ("{0}|{1}|{2}" -f $s.conversation_id, $s.model, $s.turn_count)
    Invoke-AgyDbTransaction $db { Set-AgySessionRow $db "one" "c" @("D:\only") "m" "x" "2026-10-16 10:00:00" 1 }
    Invoke-AgyDbTransaction $db { Set-AgySessionRow $db "none" "c" @() "m" "x" "2026-10-16 10:00:00" 1 }
    Assert-Equal "  폴더 하나도 배열" "D:\only|1" ("{0}|{1}" -f (@((Get-AgySessionRow $db "one").cwd) -join "|"), @((Get-AgySessionRow $db "one").cwd).Count)
    Assert-Equal "  폴더 없음은 빈 배열" 0 @((Get-AgySessionRow $db "none").cwd).Count
    Assert-Equal "  이름은 대소문자를 가리지 않는다" "one" (Get-AgySessionRow $db "ONE").name
    Assert-Equal "  없는 세션은 null" $true ($null -eq (Get-AgySessionRow $db "없음"))
    Assert-Equal "  키 규칙: 금지 문자는 _" "내 세션_1" (Get-AgySessionKey "내 세션/1")
    Assert-Equal "  키 규칙: 빈 이름은 _" "_" (Get-AgySessionKey "   ")
    Assert-Equal "  키 규칙: 100자 제한" 100 (Get-AgySessionKey ("가" * 150)).Length
    $db.Dispose()
    Assert-Equal "  경로로 읽는 Get-AgySession" "conv-1" (Get-AgySession $dbPath "내 세션/1").conversation_id
    Assert-Equal "  DB 파일이 없으면 null" $true ($null -eq (Get-AgySession (Join-Path $work "없는\agy.db") "x"))
    $db = Open-AgyDb $dbPath
    Invoke-AgyDbTransaction $db { Set-AgySessionRow $db "old" "c" @() "m" "2020-01-01 00:00:00" "2020-01-01 00:00:00" 1 }
    $db.Dispose()
    Assert-Equal "  오래 안 쓴 세션 정리: 1건 지운다" 1 (Remove-AgySessionsOlderThan $dbPath 30)
    Assert-Equal "  방금 쓴 세션은 남는다" "conv-1" (Get-AgySession $dbPath "내 세션/1").conversation_id

    Write-Host "세션의 이전 질문·답 (Get-AgySessionHistory)"
    foreach ($h in @(
            @("h1", "2026-10-20 10:00:00", "m-low", "첫 질문", "첫 답", "OK", "결제-작업"),
            @("h2", "2026-10-20 10:05:00", "m-low", "둘째 질문", "둘째 답", "OK", "결제-작업"),
            @("h3", "2026-10-20 10:10:00", "m-low", "셋째 질문", "셋째 답", "OK", "결제-작업"),
            @("h4", "2026-10-20 10:15:00", "m-low", "실패한 질문", "실패 답", "ERROR", "결제-작업"),
            @("h5", "2026-10-20 10:20:00", "m-x", "다른 세션 질문", "다른 답", "OK", "다른-작업"),
            @("h6", "2026-10-20 10:25:00", "m-x", "대소문자 질문", "대소문자 답", "OK", "Case-Test"))) {
        [void](Write-QaRecordToDb $dbPath ([ordered]@{ task_id = $h[0]; timestamp = $h[1]; model = $h[2]; question = $h[3]; answer = $h[4]; status = $h[5]; session = $h[6]; process = @() }) 'Upsert')
    }
    $hist = @(Get-AgySessionHistory $dbPath "결제-작업" 2)
    Assert-Equal "  성공한 최근 2건을 오래된 것부터 돌려준다" "h2,h3" (($hist | ForEach-Object { $_.TaskId }) -join ",")
    Assert-Equal "  질문·답·모델·시각이 담긴다" "둘째 질문|둘째 답|m-low|2026-10-20 10:05:00" ("{0}|{1}|{2}|{3}" -f $hist[0].Question, $hist[0].Answer, $hist[0].Model, $hist[0].Timestamp)
    Assert-Equal "  실패한 위임과 다른 세션은 섞이지 않는다" 3 @(Get-AgySessionHistory $dbPath "결제-작업" 10).Count
    Assert-Equal "  세션 이름은 대소문자를 가리지 않는다" "h6" ((@(Get-AgySessionHistory $dbPath "case-TEST" 2) | ForEach-Object { $_.TaskId }) -join ",")
    Assert-Equal "  없는 세션·DB 없음·Limit 0 은 빈 배열" "0|0|0" ("{0}|{1}|{2}" -f @(Get-AgySessionHistory $dbPath "없는세션" 2).Count, @(Get-AgySessionHistory (Join-Path $work "없는\agy.db") "x" 2).Count, @(Get-AgySessionHistory $dbPath "결제-작업" 0).Count)

    Write-Host "보관 기간 정리"
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ task_id = "ancient"; timestamp = "2019-01-01 00:00:00"; question = "q"; answer = "a" }) 'Upsert')
    Assert-Equal "  12개월이 지난 기록 1건을 지운다" 1 (Remove-QaRecordsOlderThan $dbPath 12)
    Assert-Equal "  나머지는 남는다" $true ($null -ne (Get-QaTaskRow $dbPath "t1"))

    Write-Host "프로세스 여러 개가 동시에 쓴다 (6개 x 20건)"
    $before = (ConvertFrom-Json -InputObject (Get-QaRecordsJson $dbPath 0)).total
    $worker = Join-Path $work "worker.ps1"
    $workerText = @'
param([string]$Module, [string]$Db, [string]$Cache, [int]$Id)
$env:AGY_DB_CACHE_DIR = $Cache
. $Module
for ($i = 0; $i -lt 20; $i++) {
    [void](Write-QaRecordToDb $Db ([ordered]@{ task_id = "w${Id}_$i"; timestamp = "2026-10-16 13:00:00"; question = "q"; answer = "a" }) 'Upsert')
}
'@
    [System.IO.File]::WriteAllText($worker, $workerText, (New-Object System.Text.UTF8Encoding($true)))
    $procs = @(1..6 | ForEach-Object { Start-HiddenPowerShell @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $worker, "-Module", $modulePath, "-Db", $dbPath, "-Cache", $env:AGY_DB_CACHE_DIR, "-Id", "$_") })
    foreach ($p in $procs) { $p.WaitForExit() }
    Assert-Equal "  작업자 6개가 모두 정상 종료" 0 @($procs | Where-Object { $_.ExitCode -ne 0 }).Count
    $after = (ConvertFrom-Json -InputObject (Get-QaRecordsJson $dbPath 0)).total
    Assert-Equal "  120건이 하나도 빠지지 않고 들어갔다" 120 ($after - $before)
    Assert-Equal "  pending 에 밀린 것이 없다" 0 @(Get-ChildItem (Get-AgyPendingDir $dbPath) -ErrorAction SilentlyContinue).Count
    $chk = Open-AgyDb $dbPath
    $seqRow = $chk.Query("SELECT COUNT(*) AS n, COUNT(DISTINCT updated_seq) AS d FROM tasks WHERE updated_seq > 0", $null)[0]
    $chk.Dispose()
    Assert-Equal "  갱신 번호(updated_seq)가 행마다 다르다(순서가 겹치지 않는다)" $seqRow["n"] $seqRow["d"]

    Write-Host "DB 를 잠깐 못 쓸 때: pending 폴더로 피했다가 다음에 가져온다"
    $lockDb = Open-AgyDb $dbPath
    [void]$lockDb.Execute("BEGIN IMMEDIATE", $null)
    $short = [AgySqlite.Db]::Open($dbPath, 200)
    $err = $null
    try { [void]$short.Execute("BEGIN IMMEDIATE", $null) } catch { $err = $_ }
    $short.Dispose()
    Assert-Equal "  다른 연결이 쓰기 잠금을 쥐면 BUSY 로 알아본다" $true ($null -ne $err -and (Test-AgyDbTransient $err))
    [void]$lockDb.Execute("ROLLBACK", $null)
    $lockDb.Dispose()
    Save-PendingQaRecord $dbPath ([ordered]@{ task_id = "pend1"; timestamp = "2026-10-16 14:00:00"; question = "pq"; answer = "pa"; process = @([pscustomobject]@{ n = 1; tool = "x" }) }) 'Upsert'
    Assert-Equal "  pending 파일이 생긴다" 1 @(Get-ChildItem (Get-AgyPendingDir $dbPath)).Count
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ task_id = "after"; timestamp = "2026-10-16 14:01:00"; question = "q"; answer = "a" }) 'Upsert')
    Assert-Equal "  다음 쓰기에서 가져오고 파일을 지운다" 0 @(Get-ChildItem (Get-AgyPendingDir $dbPath)).Count
    $p1 = Get-QaTaskRow $dbPath "pend1"
    Assert-Equal "  가져온 기록의 답" "pa" $p1.answer
    Assert-Equal "  가져온 기록의 과정" "x" (@(ConvertFrom-AgyJsonArray $p1.process)[0].tool)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
