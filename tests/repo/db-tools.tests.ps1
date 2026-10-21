# tools\migrate-to-sqlite.ps1 · tools\export-usage-csv.ps1 시험. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\repo\db-tools.tests.ps1
# 가짜 예전 런타임(임시 폴더)만 씁니다. 이 PC 의 실제 기록은 건드리지 않습니다. 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$migrate = Join-Path $repoRoot "tools\migrate-to-sqlite.ps1"
$export = Join-Path $repoRoot "tools\export-usage-csv.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("db-tools-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-db.ps1")
$utf8 = New-Object System.Text.UTF8Encoding($false)
function W([string]$path, [string]$text) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [System.IO.File]::WriteAllText($path, $text, $utf8)
}
function Run-Ps([string[]]$ArgumentList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = (@($ArgumentList | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
    try { $p.StandardInput.Close() } catch {}
    $p.WaitForExit()
    $text = [string]$outTask.Result + [string]$errTask.Result
    $code = $p.ExitCode
    $p.Dispose()
    return @{ Code = $code; Out = $text }
}
function Run-Migrate($rt, [string[]]$Extra = @()) { return (Run-Ps (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $migrate, "-RuntimeDir", $rt, "-SkipProcessCheck") + $Extra)) }

# --- 가짜 예전 런타임 ---
$rt = Join-Path $work "rt"
$logs = Join-Path $rt "logs"; $data = Join-Path $logs "data"
$q1 = '{"timestamp":"2026-10-10 09:00:00","computer_name":"PC","task_id":"q1","model":"m1","attempts":"1","tried_models":"m1","input_tokens":"10","output_tokens":"20","thinking_tokens":"5","total_tokens":"35","elapsed_sec":"12.3","status":"OK","session":"s-a","session_id":"conv-a","question":"질문 1\n둘째 줄","answer":"답 1","process":[{"n":1,"tool":"run_command","detail":"x"},{"n":2,"tool":"write_to_file","detail":"y"}]}'
$q2 = '{"timestamp":"2026-10-10 10:00:00","computer_name":"PC","task_id":"q2","model":"","status":"ERROR","tried_models":"m1","question":"질문 2","answer":"실패 메시지","process":[]}'
$q3 = '{"timestamp":"2026-10-11 09:00:00","computer_name":"PC","task_id":"q3","source":"mcp","model":"m2","status":"OK","question":"질문 3","answer":"답 3"}'
$q4 = '{"timestamp":"2026-09-20 09:00:00","computer_name":"PC","task_id":"q4","model":"m1","status":"OK","question":"질문 4","answer":"답 4","process":null}'
$q5 = '{"timestamp":"2026-10-12 09:00:00","computer_name":"PC","task_id":"q5","status":"OK","question":"질문 5"}'
$q1dup = '{"timestamp":"2026-10-10 09:00:00","computer_name":"PC","task_id":"q1","model":"DUP","question":"중복","answer":"중복 답"}'
$broken = '{"timestamp":"x","task_id":"BROKEN","question":"끊긴'
W (Join-Path $data "qa-2026-10.jsonl") (($q1, $q2, $q3, $broken, $q5) -join "`r`n")
W (Join-Path $data "qa-2026-09.p2.jsonl") $q4
W (Join-Path $data "qa-2026-10.p2.jsonl") $q1dup    # 이름 순으로 나중에 읽히는 샤드의 중복
W (Join-Path $data "index.json") '{"total":6,"shards":[]}'
W (Join-Path $logs "usage.csv") ((
    "timestamp,computer_name,task_id,model,attempts,tried_models,input_tokens,output_tokens,thinking_tokens,total_tokens,elapsed_sec,status,session,session_id",
    "2026-10-10 09:00:00,PC,q1,m1,1,m1,10,20,5,35,12.3,OK,s-a,conv-a",
    "2026-10-10 10:00:00,PC,q2,,,m1,,,,,,ERROR,,",
    "2026-10-13 09:00:00,PC,only1,m3,1,m3,1,2,0,3,1.5,OK,,",
    "2026-10-13 10:00:00,PC,only2,,,m3,,,,,,ERROR,,") -join "`r`n")
W (Join-Path $logs "usage_summary.csv") "model,tasks_ok`r`nm1,2"
W (Join-Path $logs "sessions\a.json") '{ "name": "a", "conversation_id": "conv-a", "cwd": ["D:\\a", "D:\\b"], "model": "m1", "created_at": "2026-10-01 10:00:00", "last_used_at": "2026-10-10 09:00:00", "turn_count": 3 }'
W (Join-Path $logs "sessions\old.json") '{ "name": "old", "conversation_id": "conv-old", "cwd": "D:\\legacy", "model": "m1", "created_at": "2026-10-02 10:00:00", "last_used_at": "2026-10-09 09:00:00", "turn_count": 2 }'
W (Join-Path $logs "sessions\broken.json") '{ 깨진'
W (Join-Path $data "claude-links.json") '{"keep":"me"}'

try {
    Write-Host "이전"
    $r = Run-Migrate $rt
    Assert-Equal "종료 코드 0" 0 $r.Code
    Assert-Equal "  '이전을 마쳤습니다' 를 알린다" $true ($r.Out -like "*이전을 마쳤습니다*")
    Assert-Equal "  깨진 줄 1·중복 1·깨진 세션 1 을 알린다" $true (($r.Out -like "*깨진 줄 1*") -and ($r.Out -like "*중복 1*") -and ($r.Out -like "*깨진 세션 1*"))
    $dbPath = Join-Path $logs "agy.db"
    Assert-Equal "  agy.db 가 생겼다" $true (Test-Path $dbPath)
    $legacy = @(Get-ChildItem $logs -Directory -Filter "legacy-*")
    Assert-Equal "  원본이 legacy-* 폴더로 옮겨졌다" 1 $legacy.Count
    $inLegacy = @(Get-ChildItem $legacy[0].FullName -Recurse -File | ForEach-Object { $_.Name })
    Assert-Equal "  legacy 안에 샤드·index.json·usage.csv·usage_summary.csv·세션 파일이 있다" $true (($inLegacy -contains "qa-2026-10.jsonl") -and ($inLegacy -contains "qa-2026-09.p2.jsonl") -and ($inLegacy -contains "index.json") -and ($inLegacy -contains "usage.csv") -and ($inLegacy -contains "usage_summary.csv") -and ($inLegacy -contains "a.json"))
    Assert-Equal "  원래 자리에는 원본이 없다" $false ((Test-Path (Join-Path $data "qa-2026-10.jsonl")) -or (Test-Path (Join-Path $logs "usage.csv")) -or (Test-Path (Join-Path $logs "sessions")))
    Assert-Equal "  data 폴더의 다른 파일은 그대로다" $true (Test-Path (Join-Path $data "claude-links.json"))

    $all = ConvertFrom-Json -InputObject (Get-QaRecordsJson $dbPath 0)
    $by = @{}; foreach ($x in @($all.records)) { $by[$x.task_id] = $x }
    Assert-Equal "끝난 기록 5건(q1~q5, 중복·깨진 줄 제외)" 5 $all.total
    Assert-Equal "  q1: 먼저 나온 기록이 남는다(중복의 DUP 가 아님)" "m1|답 1" ("{0}|{1}" -f $by["q1"].model, $by["q1"].answer)
    Assert-Equal "  q1: 질문의 줄바꿈이 그대로" "질문 1`n둘째 줄" $by["q1"].question
    Assert-Equal "  q1: 과정 단계 2개" 2 @($by["q1"].process).Count
    Assert-Equal "  q2: process [] 는 '없음'(키가 있고 비어 있다)" "True|0" ("{0}|{1}" -f ($by["q2"].PSObject.Properties.Name -contains "process"), @($by["q2"].process).Count)
    Assert-Equal "  q3: source 가 mcp, process 키 없음" "mcp|False" ("{0}|{1}" -f $by["q3"].source, ($by["q3"].PSObject.Properties.Name -contains "process"))
    Assert-Equal "  q4: process null 은 '모름'(키 없음)" $false ($by["q4"].PSObject.Properties.Name -contains "process")
    Assert-Equal "  q5: 답이 없던 기록은 빈 문자열 답으로 끝난 기록이 된다" "" $by["q5"].answer
    Assert-Equal "usage.csv 에만 있던 작업 2건은 미완료 행으로 들어간다" "only1,only2" ((@(Get-QaIncompleteRows $dbPath) | ForEach-Object { $_.task_id } | Sort-Object) -join ",")
    Assert-Equal "  그 행의 사용량이 그대로" "m3|3" ("{0}|{1}" -f (Get-QaTaskRow $dbPath "only1").model, (Get-QaTaskRow $dbPath "only1").total_tokens)

    $sa = Get-AgySession $dbPath "a"
    Assert-Equal "세션 a: 폴더 둘·횟수" "D:\a|D:\b|3" ("{0}|{1}" -f (@($sa.cwd) -join "|"), $sa.turn_count)
    $so = Get-AgySession $dbPath "old"
    Assert-Equal "  cwd 가 문자열이던 예전 세션은 배열 하나로" "D:\legacy|1" ("{0}|{1}" -f (@($so.cwd) -join "|"), @($so.cwd).Count)
    Assert-Equal "  깨진 세션 파일은 건너뛴다" $true ($null -eq (Get-AgySession $dbPath "broken"))
    $dbm = Open-AgyDb $dbPath
    Assert-Equal "meta 에 이전 시각이 적힌다" $true ([bool](Get-AgyMeta $dbm "migrated_at"))
    $dbm.Dispose()

    Write-Host "다시 실행"
    $r = Run-Migrate $rt
    Assert-Equal "종료 코드 0 이고 '이미 이전했습니다'" "0|True" ("{0}|{1}" -f $r.Code, ($r.Out -like "*이미 이전했습니다*"))

    Write-Host "내보내기"
    $csv = Join-Path $work "usage.csv"
    $r = Run-Ps @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $export, "-RuntimeDir", $rt, "-Out", $csv)
    Assert-Equal "종료 코드 0" 0 $r.Code
    $rows = @(Import-Csv $csv -Encoding UTF8)
    Assert-Equal "  source 가 빈 행만(q1·q2·q4·q5·only1·only2 = 6건, mcp 인 q3 제외)" "6" $rows.Count
    Assert-Equal "  열 이름은 예전 usage.csv 와 같다" "timestamp,computer_name,task_id,model,attempts,tried_models,input_tokens,output_tokens,thinking_tokens,total_tokens,elapsed_sec,status,session,session_id" ((Get-Content $csv -TotalCount 1 -Encoding UTF8).Replace('"', '') -replace '^\xEF\xBB\xBF', '' -replace '^\uFEFF', '')
    $r = Run-Ps @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $export, "-RuntimeDir", $rt, "-Since", "2026-10-11", "-Out", $csv)
    $rows = @(Import-Csv $csv -Encoding UTF8)
    Assert-Equal "  -Since 2026-10-11 이후만(q5·only1·only2)" "3" $rows.Count
    $sum = Join-Path $work "summary.csv"
    $r = Run-Ps @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $export, "-RuntimeDir", $rt, "-Summary", "-Out", $sum)
    $srows = @(Import-Csv $sum -Encoding UTF8)
    $m1 = $srows | Where-Object { $_.model -eq "m1" }
    $unk = $srows | Where-Object { $_.model -eq "(모델 미확정/실패)" }
    Assert-Equal "  -Summary: m1 은 성공 2건(q1·q4)" "2" $m1.tasks_ok
    Assert-Equal "  -Summary: 모델 미확정은 실패 2건(q2·only2)" "2" $unk.tasks_error

    Write-Host "되돌리기"
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ timestamp = "2026-10-15 09:00:00"; computer_name = "PC"; task_id = "newdb"; model = "m1"; status = "OK"; question = "새 질문"; answer = "새 답" }) 'Upsert')
    $dbn = Open-AgyDb $dbPath
    Invoke-AgyDbTransaction $dbn { Set-AgySessionRow $dbn "fresh" "conv-fresh" @("D:\f") "m1" "2026-10-15 09:00:00" "2026-10-15 09:00:00" 1 }
    $dbn.Dispose()
    $r = Run-Migrate $rt @("-Rollback")
    Assert-Equal "종료 코드 0 이고 '되돌렸습니다'" "0|True" ("{0}|{1}" -f $r.Code, ($r.Out -like "*되돌렸습니다*"))
    Assert-Equal "  원본 샤드·usage.csv·세션 파일이 제자리에 돌아왔다" $true ((Test-Path (Join-Path $data "qa-2026-10.jsonl")) -and (Test-Path (Join-Path $logs "usage.csv")) -and (Test-Path (Join-Path $logs "sessions\a.json")))
    Assert-Equal "  agy.db 는 이름이 바뀌어 보관된다" $true ((-not (Test-Path $dbPath)) -and (@(Get-ChildItem $logs -Filter "agy.db.rolledback-*").Count -eq 1))
    Assert-Equal "  DB 에만 있던 새 기록이 옛 형식 샤드로 내보내진다" $true (@(Get-ChildItem $data -Filter "qa-*.jsonl" | Where-Object { (Get-Content $_.FullName -Raw -Encoding UTF8) -like '*"task_id":"newdb"*' }).Count -ge 1)
    Assert-Equal "  DB 에만 있던 새 세션이 세션 파일로 내보내진다" $true (Test-Path (Join-Path $logs "sessions\fresh.json"))

    Write-Host "되돌린 뒤 다시 이전하면 새 기록도 이어진다"
    $r = Run-Migrate $rt
    Assert-Equal "종료 코드 0" 0 $r.Code
    $all2 = ConvertFrom-Json -InputObject (Get-QaRecordsJson (Join-Path $logs "agy.db") 0)
    Assert-Equal "  끝난 기록 6건(원래 5 + newdb)" 6 $all2.total
    Assert-Equal "  fresh 세션도 있다" "conv-fresh" (Get-AgySession (Join-Path $logs "agy.db") "fresh").conversation_id

    Write-Host "안전장치"
    $rt2 = Join-Path $work "rt2"
    $dbOther = Join-Path $rt2 "logs\agy.db"
    [void](Write-QaRecordToDb $dbOther ([ordered]@{ task_id = "x"; question = "q"; answer = "a" }) 'Upsert')
    W (Join-Path $rt2 "logs\data\qa-2026-10.jsonl") $q1
    $r = Run-Migrate $rt2
    Assert-Equal "이전 표시(meta) 없이 기록이 든 DB 는 덮어쓰지 않는다" "1|True" ("{0}|{1}" -f $r.Code, ($r.Out -like "*덮어쓰지 않습니다*"))
    Assert-Equal "  원본도 그대로" $true (Test-Path (Join-Path $rt2 "logs\data\qa-2026-10.jsonl"))
    $rt3 = Join-Path $work "rt3"
    New-Item -ItemType Directory -Force -Path (Join-Path $rt3 "logs") | Out-Null
    $r = Run-Migrate $rt3
    Assert-Equal "옮길 파일이 하나도 없어도 빈 DB 로 이전을 마친다" "0|True" ("{0}|{1}" -f $r.Code, (Test-Path (Join-Path $rt3 "logs\agy.db")))
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
