# agy-progress.ps1 의 판정 로직 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-progress.tests.ps1
# 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-progress.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

# 가짜 agy 폴더: conversations\<id>.db 와 brain\<id>\.system_generated\logs\transcript_full.jsonl
$home_ = Join-Path ([IO.Path]::GetTempPath()) ("agy-progress-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $home_ "conversations") | Out-Null
function New-FakeConversation($id, [datetime]$created, [datetime]$dbWritten, $transcriptWritten) {
    $db = Join-Path $home_ "conversations\$id.db"
    Set-Content -LiteralPath $db -Value "x"
    (Get-Item $db).CreationTime = $created
    (Get-Item $db).LastWriteTime = $dbWritten
    if ($transcriptWritten) {
        $dir = Join-Path $home_ "brain\$id\.system_generated\logs"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $tr = Join-Path $dir "transcript_full.jsonl"
        Set-Content -LiteralPath $tr -Value "{}"
        (Get-Item $tr).LastWriteTime = $transcriptWritten
    }
}

$t0 = [datetime]"2026-10-09 02:00:00"

Write-Host "Get-AgyConversationIdFromArgs"
Assert-Equal "--conversation 뒤의 값을 돌려준다" "abc-123" (Get-AgyConversationIdFromArgs @('-p', 'hi', '--conversation', 'abc-123', '--add-dir', 'D:\x'))
Assert-Equal "없으면 `$null" $true ($null -eq (Get-AgyConversationIdFromArgs @('-p', 'hi', '--model', 'm')))
Assert-Equal "마지막 인자가 --conversation 이면(값 없음) `$null" $true ($null -eq (Get-AgyConversationIdFromArgs @('-p', 'hi', '--conversation')))

Write-Host "Test-AgyStalled"
Assert-Equal "마지막 활동 6분 전, 기준 5분 -> 멈춤" $true (Test-AgyStalled $t0.AddMinutes(-6) $t0.AddMinutes(-20) $t0 300)
Assert-Equal "마지막 활동 1분 전 -> 멈춤 아님" $false (Test-AgyStalled $t0.AddMinutes(-1) $t0.AddMinutes(-20) $t0 300)
Assert-Equal "정확히 기준 시간(300초)이면 멈춤" $true (Test-AgyStalled $t0.AddSeconds(-300) $t0.AddMinutes(-20) $t0 300)
Assert-Equal "299초 전이면 멈춤 아님" $false (Test-AgyStalled $t0.AddSeconds(-299) $t0.AddMinutes(-20) $t0 300)
Assert-Equal "이어가기: 대화 파일이 시작보다 옛날이어도 시작 시각을 기준으로 센다(1분 경과 -> 멈춤 아님)" $false (Test-AgyStalled $t0.AddDays(-2) $t0.AddMinutes(-1) $t0 300)
Assert-Equal "활동 기록이 없으면 시작 시각 기준(6분 경과 -> 멈춤)" $true (Test-AgyStalled $null $t0.AddMinutes(-6) $t0 300)

Write-Host "Resolve-AgyConversation"
$missing = Join-Path $home_ "nope"
Assert-Equal "conversations 폴더가 없으면 unavailable" "unavailable" (Resolve-AgyConversation $missing $null $t0 120).State
Assert-Equal "새 대화가 없으면 none" "none" (Resolve-AgyConversation $home_ $null $t0 120).State

New-FakeConversation "old-before-start" $t0.AddMinutes(-30) $t0.AddMinutes(-29) $t0.AddMinutes(-29)
Assert-Equal "시작 전에 만들어진 대화는 무시 -> none" "none" (Resolve-AgyConversation $home_ $null $t0 120).State

New-FakeConversation "mine" $t0.AddSeconds(7) $t0.AddSeconds(30) $t0.AddSeconds(30)
$r = Resolve-AgyConversation $home_ $null $t0 120
Assert-Equal "시작 7초 뒤 생긴 대화 하나 -> found" "found" $r.State
Assert-Equal "  그 대화의 ID" "mine" $r.Id

New-FakeConversation "late-other" $t0.AddSeconds(300) $t0.AddSeconds(301) $t0.AddSeconds(301)
Assert-Equal "창(120초) 밖에서 생긴 대화는 무시 -> 여전히 found" "found" (Resolve-AgyConversation $home_ $null $t0 120).State

New-FakeConversation "other-in-window" $t0.AddSeconds(40) $t0.AddSeconds(41) $t0.AddSeconds(41)
Assert-Equal "창 안에 대화가 둘이면 어느 것인지 모르므로 ambiguous" "ambiguous" (Resolve-AgyConversation $home_ $null $t0 120).State

$k = Resolve-AgyConversation $home_ "known-id" $t0 120
Assert-Equal "이어가기(--conversation)는 ID를 이미 알므로 found" "found" $k.State
Assert-Equal "  그 ID" "known-id" $k.Id

Write-Host "Get-AgyConversationActivity"
$latest = Get-AgyConversationActivity $home_ "mine"
Assert-Equal "db 와 기록 파일 중 늦은 쪽(02:00:30)" ($t0.AddSeconds(30)).ToString("s") $latest.ToString("s")
New-FakeConversation "db-newer" $t0.AddSeconds(5) $t0.AddSeconds(90) $t0.AddSeconds(60)
Assert-Equal "db 쪽이 더 늦으면 db 시각(02:01:30)" ($t0.AddSeconds(90)).ToString("s") (Get-AgyConversationActivity $home_ "db-newer").ToString("s")
Assert-Equal "파일이 하나도 없으면 `$null" $true ($null -eq (Get-AgyConversationActivity $home_ "no-such-id"))

Write-Host "Get-DescendantProcessIdsByName"
# 실제 agy.exe 이름으로 보이게 powershell.exe 를 복사해 가짜 agy 를 만든다.
$fakeDir = Join-Path $home_ "fakebin"
New-Item -ItemType Directory -Force -Path $fakeDir | Out-Null
$fakeAgy = Join-Path $fakeDir "agy.exe"
Copy-Item -LiteralPath (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") -Destination $fakeAgy
$sleepArgs = @("-NoProfile", "-Command", "Start-Sleep 60")
# 내 자손: 이 테스트 프로세스가 직접 띄운다.
$mine = Start-Process -FilePath $fakeAgy -ArgumentList $sleepArgs -PassThru -WindowStyle Hidden
# 남의 것: WMI 가 띄우므로 부모가 이 테스트 프로세스가 아니다(사용자가 직접 띄운 agy 를 흉내).
$cmdLine = '"' + $fakeAgy + '" -NoProfile -Command "Start-Sleep 60"'
# WMI 로 만드는 이유: 이 시험 프로세스의 자손이 아닌 "남의 agy" 를 흉내 내려고. 다만 기본 설정으로 만들면 콘솔 창이 시험 때마다 보였다 사라진다
# (콘솔 창 감시기로 잡음) - ShowWindow=0(SW_HIDE) 으로 창 없이 만든다.
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
$created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine; ProcessStartupInformation = $startup }
$theirsPid = [int]$created.ProcessId
Start-Sleep -Seconds 2
$found = @(Get-DescendantProcessIdsByName $PID "agy")
Assert-Equal "내가 띄운 agy 는 찾는다" $true ($found -contains $mine.Id)
Assert-Equal "부모가 다른 agy(남의 것)는 고르지 않는다" $false ($found -contains $theirsPid)
Assert-Equal "자손 agy 는 정확히 1개" 1 $found.Count
Assert-Equal "다른 이름은 찾지 않는다" 0 @(Get-DescendantProcessIdsByName $PID "no-such-process").Count

Write-Host "Stop-ProcessTree"
Stop-ProcessTree $mine.Id
Start-Sleep -Seconds 1
Assert-Equal "종료된다" $null (Get-Process -Id $mine.Id -ErrorAction SilentlyContinue)
Assert-Equal "남의 agy 는 영향받지 않는다" $true ($null -ne (Get-Process -Id $theirsPid -ErrorAction SilentlyContinue))
Stop-Process -Id $theirsPid -Force -ErrorAction SilentlyContinue

Write-Host "Resolve-AgyConversation: 표식(Marker)으로 동시에 시작한 내 대화 고르기"
$home2 = Join-Path ([IO.Path]::GetTempPath()) ("agy-progress-marker-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $home2 "conversations") | Out-Null
function New-MarkedConversation($id, [datetime]$created, $firstLine) {
    $db = Join-Path $home2 "conversations\$id.db"
    Set-Content -LiteralPath $db -Value "x"
    (Get-Item $db).CreationTime = $created
    if ($null -ne $firstLine) {
        $dir = Join-Path $home2 "brain\$id\.system_generated\logs"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dir "transcript_full.jsonl"), ($firstLine + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    }
}
New-MarkedConversation "conv-a" $t0.AddSeconds(5) '{"step_index":0,"type":"USER_INPUT","content":"<USER_REQUEST>\n@C:\\x\\prompt_task-a.txt\n</USER_REQUEST>"}'
New-MarkedConversation "conv-b" $t0.AddSeconds(6) '{"step_index":0,"type":"USER_INPUT","content":"<USER_REQUEST>\n@C:\\x\\prompt_task-b.txt\n</USER_REQUEST>"}'
Assert-Equal "표식이 없으면 후보가 둘이라 ambiguous(예전과 같다)" "ambiguous" (Resolve-AgyConversation $home2 $null $t0 120).State
$ra = Resolve-AgyConversation $home2 $null $t0 120 "prompt_task-a.txt"
Assert-Equal "표식이 한 대화에만 있으면 그 대화를 고른다 (a)" "found|conv-a" ("{0}|{1}" -f $ra.State, $ra.Id)
$rb = Resolve-AgyConversation $home2 $null $t0 120 "prompt_task-b.txt"
Assert-Equal "  (b)" "found|conv-b" ("{0}|{1}" -f $rb.State, $rb.Id)
Assert-Equal "표식이 어느 대화에도 없으면 ambiguous" "ambiguous" (Resolve-AgyConversation $home2 $null $t0 120 "prompt_task-zzz.txt").State
New-MarkedConversation "conv-c" $t0.AddSeconds(7) '{"content":"여러 파일에 같은 표식 prompt_task-a.txt"}'
Assert-Equal "표식이 둘 이상에 있으면 ambiguous" "ambiguous" (Resolve-AgyConversation $home2 $null $t0 120 "prompt_task-a.txt").State
New-MarkedConversation "conv-d" $t0.AddSeconds(8) '{"content":"<USER_REQUEST>\n한글 지시문 첫머리입니다 보고서를 써 주세요\n</USER_REQUEST>"}'
Assert-Equal "한글 표식도 찾는다" "found|conv-d" (("{0}|{1}" -f (Resolve-AgyConversation $home2 $null $t0 120 "한글 지시문 첫머리입니다").State, (Resolve-AgyConversation $home2 $null $t0 120 "한글 지시문 첫머리입니다").Id))
New-MarkedConversation "conv-e" $t0.AddSeconds(9) $null
Assert-Equal "대화 기록이 아직 없는 후보가 있어도 표식이 한 곳에만 있으면 그것을 고른다" "found|conv-d" (("{0}|{1}" -f (Resolve-AgyConversation $home2 $null $t0 120 "한글 지시문 첫머리입니다").State, (Resolve-AgyConversation $home2 $null $t0 120 "한글 지시문 첫머리입니다").Id))
Assert-Equal "표식이 비어 있으면 후보가 여럿일 때 ambiguous" "ambiguous" (Resolve-AgyConversation $home2 $null $t0 120 "").State
Remove-Item -LiteralPath $home2 -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Get-AgyLastStepSummary / Format-AgyLastStep (멈춤 판정 때 마지막 단계를 로그에 남기는 진단)"
$home3 = Join-Path ([IO.Path]::GetTempPath()) ("agy-last-step-" + [Guid]::NewGuid().ToString("N"))
function Write-Transcript($id, [string[]]$lines) {
    $dir = Join-Path $home3 "brain\$id\.system_generated\logs"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dir "transcript_full.jsonl"), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}
$stPlanner = '{"step_index":21,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","thinking":"실행","tool_calls":[{"name":"run_command","args":{"CommandLine":"pytest -v","toolAction":"x"}},{"name":"view_file","args":{}}]}'
$stResult  = '{"step_index":22,"source":"MODEL","type":"GENERIC","status":"DONE","content":"ok"}'
$stFinal   = '{"step_index":23,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","thinking":"끝"}'
Write-Transcript "ls-tool" @($stResult, $stPlanner)
$s1 = Get-AgyLastStepSummary $home3 "ls-tool"
Assert-Equal "도구를 부른 모델 응답이 마지막이면 tool-running" "tool-running|21|PLANNER_RESPONSE|run_command,view_file" ("{0}|{1}|{2}|{3}" -f $s1.Hint, $s1.Index, $s1.Type, (@($s1.Tools) -join ","))
Write-Transcript "ls-gen" @($stPlanner, $stResult)
$s2 = Get-AgyLastStepSummary $home3 "ls-gen"
Assert-Equal "도구 결과가 마지막이면 model-generating(모델이 다음 응답을 만드는 중일 수 있음)" "model-generating|22|GENERIC|0" ("{0}|{1}|{2}|{3}" -f $s2.Hint, $s2.Index, $s2.Type, @($s2.Tools).Count)
Write-Transcript "ls-fin" @($stPlanner, $stResult, $stFinal)
Assert-Equal "도구 없는 모델 응답이 마지막이면 model-finishing" "model-finishing" (Get-AgyLastStepSummary $home3 "ls-fin").Hint
Write-Transcript "ls-partial" @($stPlanner, $stResult, '{"step_ind')
Assert-Equal "쓰는 중이라 끊긴 마지막 줄은 건너뛰고 앞의 온전한 단계를 쓴다" 22 (Get-AgyLastStepSummary $home3 "ls-partial").Index
$big = '{"step_index":30,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","thinking":"' + ("가" * 300000) + '","tool_calls":[{"name":"write_to_file","args":{}}]}'
Write-Transcript "ls-big" @($stResult, $big)
$s5 = Get-AgyLastStepSummary $home3 "ls-big"
Assert-Equal "아주 큰 줄(응답 30만 자)도 줄 전체를 JSON 으로 읽지 않고 단계·도구를 뽑는다" "30|write_to_file|tool-running" ("{0}|{1}|{2}" -f $s5.Index, (@($s5.Tools) -join ","), $s5.Hint)
Assert-Equal "대화 기록이 없으면 `$null" $true ($null -eq (Get-AgyLastStepSummary $home3 "ls-none"))
Assert-Equal "경로 문자가 든 id 는 `$null" $true ($null -eq (Get-AgyLastStepSummary $home3 "..\x"))
Assert-Equal "요약이 없으면 로그 글도 비어 있다" "" (Format-AgyLastStep $null)
$fmt = Format-AgyLastStep $s2
Assert-Equal "로그 글에 단계 번호·종류·짐작이 든다" $true (($fmt -like "*#22*") -and ($fmt -like "*GENERIC*") -and ($fmt -like "*모델 응답을 기다리는 중이거나 agy 가 멈춘 것일 수 있음*"))
Assert-Equal "도구가 도는 중이면 도구 이름과 짐작이 로그 글에 든다" $true ((Format-AgyLastStep $s1) -like "*run_command,view_file*도구가 아직 도는 중일 수 있음*")

Write-Host "Get-AgyFinalResponse (멈춤으로 끊기 직전, 이미 끝난 최종 응답이 대화 기록에 있으면 회수한다)"
$finStep  = '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","thinking":"","content":"최종 답입니다.\n\nFILE: a.py\n```python\nprint(\"hi\")\n```\n끝."}'
$userStep = '{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","content":"질문"}'
Write-Transcript "fr-ok" @($userStep, $finStep)
$fr = Get-AgyFinalResponse $home3 "fr-ok"
Assert-Equal "도구 없이 끝난 최종 응답은 내용을 돌려준다(줄바꿈·따옴표·코드 블록 그대로)" "최종 답입니다.`n`nFILE: a.py`n``````python`nprint(`"hi`")`n```````n끝." $fr.Text
Assert-Equal "  단계 번호" 1 $fr.Index
$toolStep = '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","content":"파일을 만들겠습니다","tool_calls":[{"name":"write_to_file","args":{}}]}'
Write-Transcript "fr-tool" @($userStep, $toolStep)
Assert-Equal "도구 호출이 붙은 응답은 최종이 아니다" $true ($null -eq (Get-AgyFinalResponse $home3 "fr-tool"))
Write-Transcript "fr-running" @($userStep, ($finStep -replace '"status":"DONE"', '"status":"RUNNING"'))
Assert-Equal "아직 RUNNING 이면 회수하지 않는다" $true ($null -eq (Get-AgyFinalResponse $home3 "fr-running"))
Write-Transcript "fr-result" @($userStep, $finStep, '{"step_index":2,"source":"MODEL","type":"GENERIC","status":"DONE","content":"도구 결과"}')
Assert-Equal "마지막 단계가 최종 응답이 아니면(뒤에 다른 단계가 있으면) 회수하지 않는다" $true ($null -eq (Get-AgyFinalResponse $home3 "fr-result"))
Write-Transcript "fr-user" @($userStep)
Assert-Equal "사용자 입력만 있으면 없다" $true ($null -eq (Get-AgyFinalResponse $home3 "fr-user"))
Write-Transcript "fr-empty" @($userStep, '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","content":"   "}')
Assert-Equal "내용이 비어 있으면 없다" $true ($null -eq (Get-AgyFinalResponse $home3 "fr-empty"))
Write-Transcript "fr-partial" @($userStep, '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","content":"끊긴')
Assert-Equal "쓰는 중이라 끊긴 줄은 읽을 수 없으니 없다" $true ($null -eq (Get-AgyFinalResponse $home3 "fr-partial"))
$bigFin = '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","content":"' + ("가" * 500000) + '"}'
Write-Transcript "fr-big" @($userStep, $bigFin)
Assert-Equal "아주 긴 최종 응답(50만 자)도 온전히 회수한다" 500000 (Get-AgyFinalResponse $home3 "fr-big").Text.Length
Write-Transcript "fr-prev" @($userStep, $finStep, $bigFin)
Assert-Equal "마지막 줄이 읽기 한도보다 길면 앞 단계의 응답을 최종으로 착각하지 않고 없다고 본다" $true ($null -eq (Get-AgyFinalResponse $home3 "fr-prev" 100000))
Assert-Equal "대화 기록이 없으면 없다" $true ($null -eq (Get-AgyFinalResponse $home3 "fr-none"))
Assert-Equal "경로 문자가 든 id 는 없다" $true ($null -eq (Get-AgyFinalResponse $home3 "..\x"))
Write-Host "Get-AgyPendingBackgroundTasks (오래 걸리는 명령을 백그라운드로 돌려 두고 기다리는 중인가)"
$bgId = "bg-conv"
$bgRun4 = '{"step_index":4,"source":"MODEL","type":"GENERIC","status":"RUNNING","content":"Created At: x\nTool is running as a background task with task id: ' + $bgId + '/task-4\nTask Description: Start-Sleep -Seconds 420\nYOU MUST TAKE ONE OF THE FOLLOWING TWO ACTIONS"}'
$bgRun7 = '{"step_index":7,"source":"MODEL","type":"GENERIC","status":"RUNNING","content":"Tool is running as a background task with task id: ' + $bgId + '/task-7\nTask Description: pytest"}'
$bgDone4 = '{"step_index":6,"source":"SYSTEM","type":"SYSTEM_MESSAGE","status":"DONE","content":"<SYSTEM_MESSAGE>\n[Message] timestamp=x sender=' + $bgId + '/task-4 priority=H content=Task id \"' + $bgId + '/task-4\" finished with result:\n\nThe command exited with code 0."}'
$bgDoneOther = '{"step_index":6,"source":"SYSTEM","type":"SYSTEM_MESSAGE","status":"DONE","content":"[Message] sender=other-conv/task-4 content=finished"}'
Write-Transcript $bgId @($stPlanner, $bgRun4, $stResult)
Assert-Equal "시작만 있고 끝 알림이 없으면 도는 중이다" "bg-conv/task-4" (@(Get-AgyPendingBackgroundTasks $home3 $bgId) -join ",")
Write-Transcript $bgId @($stPlanner, $bgRun4, $stResult, $bgDone4, $stFinal)
Assert-Equal "같은 task-N 의 끝 알림(SYSTEM_MESSAGE)이 오면 도는 중이 아니다" 0 @(Get-AgyPendingBackgroundTasks $home3 $bgId).Count
Write-Transcript $bgId @($bgRun4, $bgRun7, $bgDone4)
Assert-Equal "둘 중 하나만 끝났으면 나머지 하나가 도는 중이다" "bg-conv/task-7" (@(Get-AgyPendingBackgroundTasks $home3 $bgId) -join ",")
Write-Transcript $bgId @($bgRun4, $bgDoneOther)
Assert-Equal "다른 대화의 같은 번호 끝 알림은 세지 않는다" "bg-conv/task-4" (@(Get-AgyPendingBackgroundTasks $home3 $bgId) -join ",")
Write-Transcript $bgId @($stPlanner, $stResult, $stFinal)
Assert-Equal "백그라운드 도구가 없으면 비어 있다" 0 @(Get-AgyPendingBackgroundTasks $home3 $bgId).Count
Assert-Equal "대화 기록이 없으면 비어 있다" 0 @(Get-AgyPendingBackgroundTasks $home3 "bg-none").Count
Assert-Equal "경로 문자가 든 id 는 비어 있다" 0 @(Get-AgyPendingBackgroundTasks $home3 "..\x").Count
Write-Transcript $bgId @($bgRun4, '{"step_ind')
Assert-Equal "쓰는 중이라 끊긴 마지막 줄이 있어도 도는 중으로 읽는다" "bg-conv/task-4" (@(Get-AgyPendingBackgroundTasks $home3 $bgId) -join ",")
Remove-Item -LiteralPath $home3 -Recurse -Force -ErrorAction SilentlyContinue


Write-Host "Get-AgySecondsSetting (마감·멈춤 기준을 환경변수에서 읽기)"
$envName = "AGY_TEST_SECONDS_SETTING"
$envBefore = [Environment]::GetEnvironmentVariable($envName)
try {
    [Environment]::SetEnvironmentVariable($envName, $null)
    Assert-Equal "환경변수가 없으면 기본값" 1800 (Get-AgySecondsSetting $envName 1800 60)
    [Environment]::SetEnvironmentVariable($envName, "900")
    Assert-Equal "숫자면 그 값" 900 (Get-AgySecondsSetting $envName 1800 60)
    [Environment]::SetEnvironmentVariable($envName, "60")
    Assert-Equal "최솟값과 같으면 그 값" 60 (Get-AgySecondsSetting $envName 1800 60)
    [Environment]::SetEnvironmentVariable($envName, "59")
    Assert-Equal "최솟값보다 작으면 기본값" 1800 (Get-AgySecondsSetting $envName 1800 60)
    [Environment]::SetEnvironmentVariable($envName, "abc")
    Assert-Equal "숫자가 아니면 기본값" 1800 (Get-AgySecondsSetting $envName 1800 60)
    [Environment]::SetEnvironmentVariable($envName, "-5")
    Assert-Equal "음수면 기본값" 1800 (Get-AgySecondsSetting $envName 1800 60)
    [Environment]::SetEnvironmentVariable($envName, "12 ")
    Assert-Equal "공백이 섞이면 기본값" 1800 (Get-AgySecondsSetting $envName 1800 60)
    [Environment]::SetEnvironmentVariable($envName, "99999999999999")
    Assert-Equal "너무 큰 수는 기본값" 1800 (Get-AgySecondsSetting $envName 1800 60)
} finally { [Environment]::SetEnvironmentVariable($envName, $envBefore) }

Write-Host "Test-AgyAliveAtCap (절대 마감 이후: 진짜 일하는 중인가, 멈춘 것인가)"
$capNow = [datetime]"2026-10-16 12:00:00"
$capId = "cap-conv"
function New-CpuSamples([double[]]$cpus, [int]$stepSeconds) {
    $list = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $cpus.Count; $i++) { [void]$list.Add(@{ At = $capNow.AddSeconds(-($cpus.Count - 1 - $i) * $stepSeconds); Cpu = $cpus[$i] }) }
    return $list
}
$quiet = New-CpuSamples @(10.0, 10.1, 10.2, 10.2, 10.3) 4     # 16초 동안 0.3초만 씀
$busy  = New-CpuSamples @(10.0, 12.0, 14.0, 16.0, 18.0) 4     # 16초 동안 8초 씀
# 대화가 없다(= 새 단계·도구 로그를 볼 수 없는) 호출
Assert-Equal "CPU 표본이 둘 미만이면 판단하지 않고 일하는 중으로 둔다" $true (Test-AgyAliveAtCap $home_ "" $capNow 8 (New-Object System.Collections.ArrayList)).Alive
Assert-Equal "표본이 아직 창(8초)만큼 쌓이지 않았으면 일하는 중으로 둔다" $true (Test-AgyAliveAtCap $home_ "" $capNow 8 (New-CpuSamples @(10.0, 10.1) 2)).Alive
Assert-Equal "CPU 를 거의 안 쓰고 다른 활동도 없으면 멈춘 것" $false (Test-AgyAliveAtCap $home_ "" $capNow 8 $quiet).Alive
Assert-Equal "  멈췄다고 볼 때 설명이 있다" $true ((Test-AgyAliveAtCap $home_ "" $capNow 8 $quiet).Note -like "*활동이 모두 없어*")
$busyR = Test-AgyAliveAtCap $home_ "" $capNow 8 $busy
Assert-Equal "CPU 를 계속 쓰면 일하는 중" $true $busyR.Alive
Assert-Equal "  근거 글에 CPU 사용량이 든다" $true ($busyR.Reason -like "*CPU*")
# 대화가 있는 호출
$aliveId = "cap-alive"; $deadId = "cap-dead"; $taskId = "cap-task"
New-FakeConversation $aliveId $capNow.AddMinutes(-40) $capNow.AddSeconds(-3) $capNow.AddSeconds(-3)
New-FakeConversation $deadId $capNow.AddMinutes(-40) $capNow.AddMinutes(-20) $capNow.AddMinutes(-20)
New-FakeConversation $taskId $capNow.AddMinutes(-40) $capNow.AddMinutes(-20) $capNow.AddMinutes(-20)
$taskDir = Join-Path $home_ "brain\$taskId\.system_generated\tasks"
New-Item -ItemType Directory -Force -Path $taskDir | Out-Null
Set-Content -LiteralPath (Join-Path $taskDir "task-4.log") -Value "build output"
(Get-Item (Join-Path $taskDir "task-4.log")).LastWriteTime = $capNow.AddSeconds(-2)
Assert-Equal "3초 전에 새 단계가 기록됐으면 CPU 가 조용해도 일하는 중" $true (Test-AgyAliveAtCap $home_ $aliveId $capNow 8 $quiet).Alive
Assert-Equal "  근거는 새 단계" $true ((Test-AgyAliveAtCap $home_ $aliveId $capNow 8 $quiet).Reason -like "*새 단계*")
Assert-Equal "20분 전이 마지막 활동이고 CPU 도 조용하면 멈춘 것" $false (Test-AgyAliveAtCap $home_ $deadId $capNow 8 $quiet).Alive
Assert-Equal "새 단계는 없어도 백그라운드 도구가 방금 출력을 냈으면 일하는 중" $true (Test-AgyAliveAtCap $home_ $taskId $capNow 8 $quiet).Alive
Assert-Equal "  근거는 도구 출력" $true ((Test-AgyAliveAtCap $home_ $taskId $capNow 8 $quiet).Reason -like "*도구가 출력*")
Assert-Equal "20분 전이 마지막 활동이어도 CPU 를 계속 쓰면 일하는 중" $true (Test-AgyAliveAtCap $home_ $deadId $capNow 8 $busy).Alive
Assert-Equal "Get-AgyTaskLogActivity: 도구 로그가 없으면 `$null" $true ($null -eq (Get-AgyTaskLogActivity $home_ $deadId))
Assert-Equal "Get-AgyTaskLogActivity: 있으면 마지막 수정 시각" $true ((Get-AgyTaskLogActivity $home_ $taskId) -eq $capNow.AddSeconds(-2))
Assert-Equal "Get-AgyTreeCpuSeconds: 지금 프로세스는 CPU 를 쓴 적이 있다" $true ((Get-AgyTreeCpuSeconds $PID) -gt 0)
Assert-Equal "Get-AgyTreeCpuSeconds: 없는 프로세스는 0" 0 (Get-AgyTreeCpuSeconds 2147000000)
Remove-Item -LiteralPath $home_ -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
