# submit-task.ps1 시험: 임시 런타임 폴더에 지시문을 넣고, 결과·오류·진행 상태·종료 코드를 확인한다. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\submit-task.tests.ps1
# 실제 워처·agy 는 띄우지 않습니다(응답 파일은 시험이 직접 만듭니다). 약 30초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script_ = Join-Path $repoRoot "runtime\delegate-agy\scripts\submit-task.ps1"
$psExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("submit-task-test-" + [Guid]::NewGuid().ToString("N"))
$rt = Join-Path $work "runtime"
foreach ($d in @("inbox", "outbox", "logs\running", "logs\heartbeat")) { New-Item -ItemType Directory -Force -Path (Join-Path $rt $d) | Out-Null }
$agyHome = Join-Path $work "agyhome"
$utf8 = New-Object Text.UTF8Encoding($false)

function Start-Submit([string[]]$ArgList, [string]$Stdin = "", [hashtable]$Env = @{}) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + $script_ + '"')) + $ArgList
    $psi.Arguments = ($a -join " ")
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.EnvironmentVariables["AGY_HOME"] = $agyHome
    $psi.EnvironmentVariables["USERPROFILE"] = $work
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = [string]$Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $bytes = $utf8.GetBytes($Stdin)
    $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $p.StandardInput.Close()
    return $p
}
function Wait-Submit($p) {
    $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); [void]$p.WaitForExit()
    return @{ Out = $out; Err = $err; Exit = $p.ExitCode }
}
function Run-Submit([string[]]$ArgList, [string]$Stdin = "") { return (Wait-Submit (Start-Submit (@("-RuntimeDir", ('"' + $rt + '"')) + $ArgList) $Stdin)) }
function Write-Utf8([string]$Path, [string]$Text, [bool]$Bom = $false) { [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($Bom))) }

try {
    Write-Host "넣기 (표준입력 -> inbox)"
    $task = "@cwd: C:\project`n@model: gemini-3.8-flash-medium`n한글 지시문 `"따옴표`" 와 `$변수 와 'x'`n최종 답변은 한글로."
    $r = Run-Submit @("-NoWait") $task
    Assert-Equal "종료 코드 0" 0 $r.Exit
    $m = [regex]::Match($r.Out, 'submitted: (claude_\d{9,11}_\d+)')
    Assert-Equal "작업 ID 는 claude_<초>_<숫자> 모양" $true $m.Success
    $id1 = $m.Groups[1].Value
    $inFile = Join-Path $rt "inbox\$id1.md"
    Assert-Equal "  inbox 에 <ID>.md 가 생겼다" $true (Test-Path $inFile)
    Assert-Equal "  내용이 그대로다(한글·따옴표·달러 기호)" $task ([IO.File]::ReadAllText($inFile, $utf8))
    Assert-Equal "  BOM 이 없다" $false ([IO.File]::ReadAllBytes($inFile)[0] -eq 0xEF)
    Assert-Equal "  임시 파일(.tmp)이 남지 않는다" 0 @(Get-ChildItem (Join-Path $rt "inbox") -Filter "*.tmp").Count
    $r2 = Run-Submit @("-NoWait") "두 번째"
    $id2 = [regex]::Match($r2.Out, 'submitted: (\S+)').Groups[1].Value
    Assert-Equal "  연달아 넣어도 ID 가 다르다" $true ($id1 -ne $id2)

    Write-Host "지시문 파일(-File) · 입력 오류"
    $tf = Join-Path $work "task.md"; Write-Utf8 $tf "파일에서 읽은 지시문" $true
    $r = Run-Submit @("-NoWait", "-File", ('"' + $tf + '"'))
    $idF = [regex]::Match($r.Out, 'submitted: (\S+)').Groups[1].Value
    Assert-Equal "-File 로 읽고 BOM 은 걷는다" "파일에서 읽은 지시문" ([IO.File]::ReadAllText((Join-Path $rt "inbox\$idF.md"), $utf8))
    $r = Run-Submit @("-NoWait") "   "
    Assert-Equal "빈 지시문은 종료 코드 3" 3 $r.Exit
    $r = Wait-Submit (Start-Submit @("-RuntimeDir", ('"' + (Join-Path $work "없는폴더") + '"'), "-NoWait") "x" @{ AGY_DELEGATE_RUNTIME = ""; USERPROFILE = (Join-Path $work "홈없음") })
    Assert-Equal "런타임 폴더를 못 찾으면 종료 코드 3" 3 $r.Exit
    $r = Run-Submit @("-Poll", "../evil")
    Assert-Equal "경로가 섞인 작업 ID 는 종료 코드 3" 3 $r.Exit

    Write-Host "결과 기다리기 (-Poll)"
    Write-Utf8 (Join-Path $rt "outbox\$id1.response.md") "결과 본문 줄1`n줄2" $true
    $r = Run-Submit @("-Poll", $id1, "-WaitSeconds", "5")
    Assert-Equal "응답이 있으면 RESULT + 본문(BOM 제거), 종료 코드 0" "0|True" ("{0}|{1}" -f $r.Exit, ($r.Out -match "(?s)^===RESULT=== $id1\r?\n결과 본문 줄1\r?\n줄2"))
    Write-Utf8 (Join-Path $rt "outbox\$id2.error.log") "실행 오류 로그"
    $r = Run-Submit @("-Poll", $id2, "-WaitSeconds", "5")
    Assert-Equal "응답 없이 error.log 만 있으면 ERROR, 종료 코드 1" "1|True" ("{0}|{1}" -f $r.Exit, ($r.Out -match "===ERROR=== $id2\r?\n실행 오류 로그"))
    Write-Utf8 (Join-Path $rt "outbox\$id2.response.md") "응답도 있음"
    $r = Run-Submit @("-Poll", $id2, "-WaitSeconds", "5")
    Assert-Equal "응답이 있으면 error.log 가 있어도 RESULT" $true ($r.Out -match "===RESULT=== $id2")
    Write-Utf8 (Join-Path $rt "outbox\빈응답.response.md") ""

    Write-Host "여러 개 · 진행 상태(PENDING)"
    $idQ = "claude_1790000000_7"
    Write-Utf8 (Join-Path $rt "inbox\$idQ.md") "대기 중인 작업"
    $r = Run-Submit @("-Poll", "$id1,$idQ", "-WaitSeconds", "2")
    Assert-Equal "한 개는 결과, 한 개는 대기 -> 종료 코드 2" 2 $r.Exit
    Assert-Equal "  끝난 것은 RESULT 로" $true ($r.Out -match "===RESULT=== $id1")
    Assert-Equal "  대기열에 있는 것은 '대기열에서 기다리는 중'" $true ($r.Out -match "===PENDING=== $idQ 대기열에서 기다리는 중")
    Assert-Equal "  하트비트가 없으면 워처 확인 안내" $true ($r.Out -match "워처 하트비트가 없습니다")
    Set-Content -LiteralPath (Join-Path $rt "logs\heartbeat\hb_T.txt") -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Encoding UTF8
    $r = Run-Submit @("-Poll", $idQ, "-WaitSeconds", "1")
    Assert-Equal "  하트비트가 있으면 안내가 없다" $false ($r.Out -match "하트비트")
    $r = Run-Submit @("-Poll", "claude_1_1", "-WaitSeconds", "1")
    Assert-Equal "  어디에도 없는 ID 는 '접수 기록 없음'" $true ($r.Out -match "접수 기록 없음")

    $idR = "claude_1790000001_8"
    $conv = "abc-123"
    $started = (Get-Date).AddMinutes(-11).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Utf8 (Join-Path $rt "logs\running\$idR.json") (@{ task_id = $idR; pid = 1; model = "gemini-3.8-flash-high"; started_at = $started; session = "결제-리팩토링"; conversation_id = $conv } | ConvertTo-Json -Compress)
    $tdir = Join-Path $agyHome "brain\$conv\.system_generated\logs"
    New-Item -ItemType Directory -Force -Path $tdir | Out-Null
    Write-Utf8 (Join-Path $tdir "transcript_full.jsonl") ('{"step_index":13,"type":"USER_INPUT","status":"DONE"}' + "`n" + '{"step_index":14,"type":"PLANNER_RESPONSE","status":"DONE","tool_calls":[{"name":"view_file"}]}' + "`n")
    $r = Run-Submit @("-Poll", $idR, "-WaitSeconds", "1")
    Assert-Equal "실행 중이면 경과·모델·세션·마지막 단계를 한 줄로 보여 준다" "True|True|True|True" ("{0}|{1}|{2}|{3}" -f ($r.Out -match "===PENDING=== $idR 진행 중"), ($r.Out -match "경과 1[01]분"), ($r.Out -match "모델 gemini-3.8-flash-high · 세션 결제-리팩토링"), ($r.Out -match "마지막 단계 #14 PLANNER_RESPONSE DONE 도구: view_file"))
    Assert-Equal "  진행 상태를 보여도 PENDING 은 한 줄이다" 1 @($r.Out -split "`n" | Where-Object { $_ -match "===PENDING===" }).Count

    Write-Host "넣고 기다리기: 기다리는 동안 응답이 생기면 바로 돌려준다"
    $p = Start-Submit @("-RuntimeDir", ('"' + $rt + '"'), "-WaitSeconds", "20") "기다리는 지시문"
    $line = $p.StandardOutput.ReadLine()
    $idW = [regex]::Match($line, 'submitted: (\S+)').Groups[1].Value
    Assert-Equal "  먼저 'submitted: <ID>' 를 내보낸다" $true ($idW -ne "")
    Start-Sleep -Seconds 1
    Write-Utf8 (Join-Path $rt "outbox\$idW.response.md") "나중에 생긴 응답"
    $rest = $p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit()
    Assert-Equal "  응답이 생기면 RESULT 로 끝나고 종료 코드 0" "0|True" ("{0}|{1}" -f $p.ExitCode, ($rest -match "===RESULT=== $idW\r?\n나중에 생긴 응답"))
    $r = Run-Submit @("-WaitSeconds", "2") "끝내 응답이 없는 지시문"
    Assert-Equal "  시간 안에 안 끝나면 PENDING + 종료 코드 2(작업은 inbox 에 남는다)" "2|True" ("{0}|{1}" -f $r.Exit, ($r.Out -match "submitted: claude_\d+_\d+" -and $r.Out -match "===PENDING==="))
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
