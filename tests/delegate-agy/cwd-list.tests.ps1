# @cwd 여러 폴더: 세션 파일 저장/읽기(common.ps1)와 뷰어(serve-viewer.ps1)의 폴더 목록 규칙 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\cwd-list.tests.ps1
# 임시 폴더의 세션 파일만 씁니다. 실제 세션 파일(runtime\logs\sessions)은 건드리지 않습니다(몇 초).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}
function Assert-True($name, $cond) { Assert-Equal $name $true [bool]$cond }

function Get-FunctionText($path, $name) {
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name 를 $path 에서 찾지 못했습니다." }
    return $fn.Extent.Text
}

$commonPath = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\common.ps1"
$viewerPath = Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"

$work = Join-Path ([IO.Path]::GetTempPath()) ("cwd-list-test-" + [Guid]::NewGuid().ToString("N"))
$SessionsDir = Join-Path $work "sessions"
New-Item -ItemType Directory -Force -Path $SessionsDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

# common.ps1 의 함수들(세션 읽기/쓰기와 폴더 목록, QA 기록)을 꺼내 온다
foreach ($name in @("ConvertTo-ReadableJson", "Get-SafeSessionFileName", "Get-SessionPath", "Read-Session", "Write-Session", "ConvertTo-CwdList", "Resolve-TaskCwds", "Get-MissingCwds", "Get-QaShardFiles", "Get-QaShardPath", "Add-QaLine", "Test-QaTaskIdInShardTail", "Test-QaTaskIdInRecentShards", "Add-QaRecordUnlocked")) {
    Invoke-Expression (Get-FunctionText $commonPath $name)
}
# 뷰어의 같은 이름 함수(사본)는 다른 이름으로 불러 와서 비교한다
Invoke-Expression ((Get-FunctionText $viewerPath "ConvertTo-CwdList").Replace("function ConvertTo-CwdList", "function ConvertTo-CwdListViewer"))

Write-Host "뷰어의 ConvertTo-CwdList 는 common.ps1 의 것과 같은 규칙이다(사본이 어긋나지 않게)"
$cases = @(
    @($null), @(""), @("D:\a"), @("D:\a", "D:\b"), @("D:\Repo", "d:\repo\", "D:\REPO/", "D:\other"),
    @("  D:\x  ", "", "   ", $null, "D:\y"), @("\"), @("/", "\"), @("C:\"), @("C:\", "c:")
)
$same = $true; $diff = ""
foreach ($c in $cases) {
    $a = (@(ConvertTo-CwdList $c) -join "|")
    $b = (@(ConvertTo-CwdListViewer $c) -join "|")
    if ($a -ne $b) { $same = $false; $diff += " [$($c -join ',')]: common=$a viewer=$b" }
}
Assert-Equal "  여러 입력에서 두 함수의 결과가 같다$diff" $true $same

Write-Host "세션 파일: 폴더 목록 저장"
Write-Session -Name "multi" -ConversationId "conv-1" -Cwd @("D:\a\repo", "D:\b\docs") -Model "gemini-3.8-flash-medium"
$raw = Get-Content -Raw -LiteralPath (Join-Path $SessionsDir "multi.json") -Encoding UTF8
$j = $raw | ConvertFrom-Json
Assert-Equal "폴더 둘을 cwd 배열로 저장한다" "D:\a\repo|D:\b\docs" (@($j.cwd) -join "|")
Assert-Equal "  JSON 에서 배열이다([ 로 시작)" $true ($raw -match '"cwd":\s*\[')
Assert-Equal "  나머지 항목은 그대로(대화 id·모델·횟수)" "conv-1|gemini-3.8-flash-medium|1" ("{0}|{1}|{2}" -f $j.conversation_id, $j.model, $j.turn_count)
Write-Session -Name "one" -ConversationId "conv-2" -Cwd @("D:\only") -Model "m"
$j1 = (Get-Content -Raw -LiteralPath (Join-Path $SessionsDir "one.json") -Encoding UTF8) | ConvertFrom-Json
Assert-Equal "폴더가 하나여도 배열로 저장한다" "D:\only|1" ("{0}|{1}" -f (@($j1.cwd) -join "|"), @($j1.cwd).Count)
Assert-Equal "  JSON 에서 배열이다" $true ((Get-Content -Raw -LiteralPath (Join-Path $SessionsDir "one.json") -Encoding UTF8) -match '"cwd":\s*\[')
Write-Session -Name "none" -ConversationId "conv-3" -Cwd @() -Model "m"
$j0 = (Get-Content -Raw -LiteralPath (Join-Path $SessionsDir "none.json") -Encoding UTF8) | ConvertFrom-Json
Assert-Equal "폴더가 없으면 빈 배열" 0 @($j0.cwd).Count
Write-Session -Name "dup" -ConversationId "conv-4" -Cwd @("D:\a", "d:\A\", "D:\b") -Model "m"
Assert-Equal "저장할 때도 중복을 한 번만 남긴다" "D:\a|D:\b" (@((Read-Session "dup").cwd) -join "|")
Write-Session -Name "strarg" -ConversationId "conv-5" -Cwd "D:\single-string" -Model "m"
Assert-Equal "문자열 하나를 넘겨도(예전 호출 방식) 배열 하나로 저장한다" "D:\single-string|1" ("{0}|{1}" -f (@((Read-Session "strarg").cwd) -join "|"), @((Read-Session "strarg").cwd).Count)

Write-Host "세션 파일: 예전 형식(cwd 가 문자열)"
$oldJson = '{ "name": "old", "conversation_id": "conv-old", "cwd": "D:\\legacy\\proj", "model": "gemini-3.8-flash-low", "created_at": "2026-10-01 10:00:00", "last_used_at": "2026-10-01 10:00:00", "turn_count": 3 }'
[System.IO.File]::WriteAllText((Join-Path $SessionsDir "old.json"), $oldJson, $utf8)
$old = Read-Session "old"
Assert-Equal "예전 세션 파일을 그대로 읽는다(cwd 는 문자열)" "D:\legacy\proj" $old.cwd
Assert-Equal "  이어갈 때 폴더 목록 하나로 풀린다" "D:\legacy\proj" (@(Resolve-TaskCwds @() $old.cwd) -join "|")
Assert-Equal "  이번 호출에 @cwd 가 있으면 예전 폴더는 쓰지 않는다" "D:\new" (@(Resolve-TaskCwds @("D:\new") $old.cwd) -join "|")
Write-Session -Name "old" -ConversationId "conv-old" -Cwd (Resolve-TaskCwds @() $old.cwd) -Model "(session)"
$upd = Read-Session "old"
Assert-Equal "이어간 뒤 다시 저장하면 배열 형식으로 바뀐다(폴더는 그대로)" "D:\legacy\proj|1" ("{0}|{1}" -f (@($upd.cwd) -join "|"), @($upd.cwd).Count)
Assert-Equal "  횟수는 이어서 늘고 모델은 유지된다" "4|gemini-3.8-flash-low" ("{0}|{1}" -f $upd.turn_count, $upd.model)
[System.IO.File]::WriteAllText((Join-Path $SessionsDir "nocwd.json"), '{ "name": "nocwd", "conversation_id": "conv-x", "model": "m", "turn_count": 1 }', $utf8)
Assert-Equal "cwd 항목이 아예 없는 세션 파일은 빈 목록" 0 @(Resolve-TaskCwds @() (Read-Session "nocwd").cwd).Count
[System.IO.File]::WriteAllText((Join-Path $SessionsDir "broken.json"), '{ 깨진', $utf8)
Assert-Equal "깨진 세션 파일은 null(= 새 세션)" $true ($null -eq (Read-Session "broken"))

Write-Host "이어가기 규칙(세션 고정)"
$sess = Read-Session "multi"
Assert-Equal "이번 호출에 @cwd 가 없으면 세션의 두 폴더를 그대로 쓴다" "D:\a\repo|D:\b\docs" (@(Resolve-TaskCwds @() $sess.cwd) -join "|")
Assert-Equal "이번 호출에 @cwd 가 하나라도 있으면 이번 목록만 쓴다(합치지 않는다)" "D:\c" (@(Resolve-TaskCwds @("D:\c") $sess.cwd) -join "|")

Write-Host "Add-QaRecordUnlocked 및 log-qa.ps1 검증"
$qaDataDir = Join-Path $work "logs\data"
New-Item -ItemType Directory -Force -Path $qaDataDir | Out-Null
$script:DataDir = $qaDataDir
$qaIdxFile = Join-Path $qaDataDir "index.json"

$rec1 = [ordered]@{
    timestamp = "2026-10-15 12:00:00"
    task_id   = "task_dup_1"
    question  = "q1"
    answer    = "a1"
}
$w1 = Add-QaRecordUnlocked $rec1 $qaIdxFile 12
Assert-True "첫 번째 task_id 기록 성공" ($null -ne $w1)
Assert-True "기록된 샤드 경로가 .jsonl 파일임" ($w1.EndsWith(".jsonl"))

$w2 = Add-QaRecordUnlocked $rec1 $qaIdxFile 12
Assert-Equal "동일 task_id 두 번째 시도는 건너뛰고 null 반환" $null $w2

# index.json total 어긋남 보정 검증: total을 99로 조작
$idxObj = Get-Content -Raw $qaIdxFile -Encoding UTF8 | ConvertFrom-Json
$idxObj.total = 99
# 바이트 합산 불일치를 유도하기 위해 dummy 샤드 추가 조작
$idxObj.shards = @(@{ file = "qa-dummy.jsonl"; bytes = 12345; modified = "2026-10-15 00:00:00" })
[System.IO.File]::WriteAllText($qaIdxFile, ($idxObj | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

$rec2 = [ordered]@{
    timestamp = "2026-10-15 12:01:00"
    task_id   = "task_dup_2"
    question  = "q2"
    answer    = "a2"
}
$w3 = Add-QaRecordUnlocked $rec2 $qaIdxFile 12
Assert-True "새 task_id 기록 성공" ($null -ne $w3)

$recalcedIdx = Get-Content -Raw $qaIdxFile -Encoding UTF8 | ConvertFrom-Json
Assert-Equal "어긋난 total이 실제 샤드 줄 수(2건)로 자동 보정됨" 2 $recalcedIdx.total

# log-qa.ps1 실행 시 출력 문자열 끝에 실제 파일 경로가 비어 있지 않은지 검증
$logQaScript = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\log-qa.ps1"
$qFile = Join-Path $work "q.txt"
$aFile = Join-Path $work "a.txt"
[System.IO.File]::WriteAllText($qFile, "질문", [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($aFile, "답변", [System.Text.Encoding]::UTF8)

$logOut = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $logQaScript -RuntimeDir $work -TaskId "task_log_qa_test" -Source "mcp" -QuestionFile $qFile -AnswerFile $aFile
$logOutStr = ($logOut -join "`n").Trim()
Assert-True "log-qa.ps1 출력에 '기록 저장:' 포함" ($logOutStr -match '기록 저장:\s*task_id=task_log_qa_test')
Assert-True "log-qa.ps1 출력 경로가 .jsonl 로 끝남" ($logOutStr -match '->\s*.+\.jsonl$')

# uninstall.ps1 BOM 없음 검증
$unPath = Join-Path $repoRoot "uninstall.ps1"
$unBytes = [System.IO.File]::ReadAllBytes($unPath)
$hasBom = ($unBytes.Length -ge 3 -and $unBytes[0] -eq 0xEF -and $unBytes[1] -eq 0xBB -and $unBytes[2] -eq 0xBF)
Assert-Equal "uninstall.ps1 파일 맨 앞에 UTF-8 BOM 없음" $false $hasBom

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
