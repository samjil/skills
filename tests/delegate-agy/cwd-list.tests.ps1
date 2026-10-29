# @cwd 여러 폴더: 세션 저장/읽기(common.ps1, SQLite)와 뷰어(serve-viewer.ps1)의 폴더 목록 규칙 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\cwd-list.tests.ps1
# 임시 폴더의 DB 만 씁니다. 실제 기록(runtime\data\delegate.db)은 건드리지 않습니다(몇 초).

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

# 창 없이 PowerShell 을 띄워 종료 코드와 출력(UTF-8)을 돌려준다
function Invoke-HiddenPs([string[]]$ArgumentList) {
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

$commonPath = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\common.ps1"
$viewerPath = Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"

$work = Join-Path ([IO.Path]::GetTempPath()) ("cwd-list-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
$AgyDbPath = Join-Path $work "data\delegate.db"
. $commonPath
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

try {
    Write-Host "세션: 폴더 목록 저장"
    Write-Session -Name "multi" -ConversationId "conv-1" -Cwd @("D:\a\repo", "D:\b\docs") -Model "gemini-3.8-flash-medium"
    $s = Read-Session "multi"
    Assert-Equal "폴더 둘을 cwd 배열로 저장한다" "D:\a\repo|D:\b\docs" (@($s.cwd) -join "|")
    Assert-Equal "  나머지 항목은 그대로(대화 id·모델·횟수)" "conv-1|gemini-3.8-flash-medium|1" ("{0}|{1}|{2}" -f $s.conversation_id, $s.model, $s.turn_count)
    Write-Session -Name "one" -ConversationId "conv-2" -Cwd @("D:\only") -Model "m"
    Assert-Equal "폴더가 하나여도 배열로 저장한다" "D:\only|1" ("{0}|{1}" -f (@((Read-Session "one").cwd) -join "|"), @((Read-Session "one").cwd).Count)
    Write-Session -Name "none" -ConversationId "conv-3" -Cwd @() -Model "m"
    Assert-Equal "폴더가 없으면 빈 배열" 0 @((Read-Session "none").cwd).Count
    Write-Session -Name "dup" -ConversationId "conv-4" -Cwd @("D:\a", "d:\A\", "D:\b") -Model "m"
    Assert-Equal "저장할 때도 중복을 한 번만 남긴다" "D:\a|D:\b" (@((Read-Session "dup").cwd) -join "|")
    Write-Session -Name "strarg" -ConversationId "conv-5" -Cwd "D:\single-string" -Model "m"
    Assert-Equal "문자열 하나를 넘겨도(예전 호출 방식) 배열 하나로 저장한다" "D:\single-string|1" ("{0}|{1}" -f (@((Read-Session "strarg").cwd) -join "|"), @((Read-Session "strarg").cwd).Count)

    Write-Host "세션: 이어가기"
    Write-Session -Name "multi" -ConversationId "conv-1b" -Cwd @("D:\a\repo") -Model "(session)"
    $s2 = Read-Session "multi"
    Assert-Equal "이어간 뒤 횟수가 늘고 모델 자리표시자는 기존 모델을 지우지 않는다" "2|gemini-3.8-flash-medium|conv-1b" ("{0}|{1}|{2}" -f $s2.turn_count, $s2.model, $s2.conversation_id)
    Assert-Equal "  폴더는 이번 목록으로 바뀐다" "D:\a\repo" (@($s2.cwd) -join "|")
    Assert-Equal "  처음 만든 시각은 그대로" $s.created_at $s2.created_at
    Assert-Equal "이름은 대소문자를 가리지 않는다" "conv-1b" (Read-Session "MULTI").conversation_id
    Assert-Equal "없는 세션은 null(= 새 세션)" $true ($null -eq (Read-Session "없는-세션"))

    Write-Host "이어가기 규칙(세션 고정)"
    Assert-Equal "예전처럼 문자열 하나로 들어온 폴더도 목록 하나로 풀린다" "D:\legacy\proj" (@(Resolve-TaskCwds @() "D:\legacy\proj") -join "|")
    Assert-Equal "  이번 호출에 @cwd 가 있으면 예전 폴더는 쓰지 않는다" "D:\new" (@(Resolve-TaskCwds @("D:\new") "D:\legacy\proj") -join "|")
    $sess = Read-Session "dup"
    Assert-Equal "이번 호출에 @cwd 가 없으면 세션의 두 폴더를 그대로 쓴다" "D:\a|D:\b" (@(Resolve-TaskCwds @() $sess.cwd) -join "|")
    Assert-Equal "이번 호출에 @cwd 가 하나라도 있으면 이번 목록만 쓴다(합치지 않는다)" "D:\c" (@(Resolve-TaskCwds @("D:\c") $sess.cwd) -join "|")

    Write-Host "오래 안 쓴 세션 정리"
    $dbx = Open-AgyDb $AgyDbPath
    Invoke-AgyDbTransaction $dbx { Set-AgySessionRow $dbx "ancient" "c" @() "m" "2020-01-01 00:00:00" "2020-01-01 00:00:00" 1 }
    $dbx.Dispose()
    Remove-StaleSessions -MaxAgeDays 30
    Assert-Equal "30일 넘게 안 쓴 세션은 지워진다" $true ($null -eq (Read-Session "ancient"))
    Assert-Equal "  방금 쓴 세션은 남는다" "conv-1b" (Read-Session "multi").conversation_id

    Write-Host "log-qa.ps1 검증"
    $logQaScript = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\log-qa.ps1"
    $qFile = Join-Path $work "q.txt"
    $aFile = Join-Path $work "a.txt"
    [System.IO.File]::WriteAllText($qFile, "질문", [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($aFile, "답변", [System.Text.Encoding]::UTF8)
    $r1 = Invoke-HiddenPs @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $logQaScript, "-RuntimeDir", $work, "-TaskId", "task_log_qa_test", "-Source", "mcp", "-QuestionFile", $qFile, "-AnswerFile", $aFile)
    Assert-Equal "종료 코드 0" 0 $r1.Code
    Assert-True "출력에 '기록 저장:' 과 작업 ID 가 있다" ($r1.Out -match '기록 저장:\s*task_id=task_log_qa_test')
    Assert-True "  출력 끝이 DB 경로다" ($r1.Out -match '->\s*.+agy\.db')
    $row = Get-QaTaskRow $AgyDbPath "task_log_qa_test"
    Assert-Equal "  DB 에 질문·답·출처가 들어간다" "질문|답변|mcp" ("{0}|{1}|{2}" -f ([string]$row.question).Trim(), ([string]$row.answer).Trim(), $row.source)
    Assert-True "  끝난 기록(answer 가 NULL 이 아님)이다" ($null -ne $row.answer)
    $r2 = Invoke-HiddenPs @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $logQaScript, "-RuntimeDir", $work, "-TaskId", "task_log_qa_test", "-Source", "mcp", "-QuestionFile", $qFile, "-AnswerFile", $aFile)
    Assert-True "같은 작업 ID 를 또 기록하면 실패한다" ($r2.Code -ne 0)
    Assert-True "  이유가 '이미 존재'로 보인다" ($r2.Out -match '이미 존재')
    $json = ConvertFrom-Json -InputObject (Get-QaRecordsJson $AgyDbPath 0)
    Assert-Equal "  그래도 기록은 한 건뿐이다" 1 $json.total

    # uninstall.ps1 BOM 없음 검증
    $unPath = Join-Path $repoRoot "uninstall.ps1"
    $unBytes = [System.IO.File]::ReadAllBytes($unPath)
    $hasBom = ($unBytes.Length -ge 3 -and $unBytes[0] -eq 0xEF -and $unBytes[1] -eq 0xBB -and $unBytes[2] -eq 0xBF)
    Assert-Equal "uninstall.ps1 파일 맨 앞에 UTF-8 BOM 없음" $false $hasBom
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
