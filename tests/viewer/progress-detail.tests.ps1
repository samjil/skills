# 진행 중인 위임 카드의 "지금:" 줄이 쓰는 서버 쪽 데이터(Get-AgyProgress, Get-AgyToolDetail) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\progress-detail.tests.ps1
# 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다. 임시 폴더에 가짜 agy 대화 기록을 만들어 쓰고 실제 agy 기록은 건드리지 않습니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

# Get-AgyToolDetail 은 워처와 뷰어가 함께 쓰는 agy-progress.ps1 에 있다.
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-progress.ps1")

# Get-AgyProgress 는 serve-viewer.ps1 에서 함수 정의만 꺼내 옵니다(서버 본체는 실행하지 않음).
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"), [ref]$tokens, [ref]$errs)
$script:ProcessCache = @{}
$script:TokenCache = @{}
foreach ($name in @("Get-AgyProcessStepsCached", "Get-AgyProgress")) {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name 를 serve-viewer.ps1 에서 찾지 못했습니다." }
    Invoke-Expression $fn.Extent.Text
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("progress-detail-test-" + [Guid]::NewGuid().ToString("N"))
$env:AGY_HOME = $work

# 마지막 줄이 "도구 호출"인 가짜 대화 기록을 만들고 Get-AgyProgress 결과를 돌려준다.
function New-Progress($toolName, $toolArgs, [int]$step = 17, [string]$id = ("conv-" + [Guid]::NewGuid().ToString("N"))) {
    $dir = Join-Path $work "brain\$id\.system_generated\logs"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $call = [ordered]@{ step_index = $step; source = "MODEL"; type = "PLANNER_RESPONSE"; status = "DONE"; thinking = "생각 내용"
        tool_calls = @(@{ name = $toolName; args = $toolArgs }) }
    $first = [ordered]@{ step_index = ($step - 1); source = "MODEL"; type = "GENERIC"; status = "DONE"; content = "이전 결과" }
    $lines = @(($first | ConvertTo-Json -Compress -Depth 8), ($call | ConvertTo-Json -Compress -Depth 8))
    [System.IO.File]::WriteAllText((Join-Path $dir "transcript_full.jsonl"), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return (Get-AgyProgress $id $null)
}

Write-Host "실제 사례: 17단계 'Checking target directory'"
$p = New-Progress "run_command" @{ CommandLine = "Get-Location"; Cwd = "C:\work\agy-high-test"; WaitMsBeforeAsync = 5000; toolAction = "Checking target directory"; toolSummary = "Check target directory" }
Assert-Equal "단계 번호" 17 $p.step
Assert-Equal "영어 라벨은 그대로" "Checking target directory" $p.action
Assert-Equal "도구 이름" "run_command" $p.tool
Assert-Equal "실제로 실행한 명령" "Get-Location" $p.detail
Assert-Equal "실행 폴더" "C:\work\agy-high-test" $p.cwd
Assert-Equal "백그라운드 아님" $false $p.background
Assert-Equal "생각 내용" "생각 내용" $p.thinking

Write-Host "지금 줄 아래의 agy 말(thinking, say)"
# 생각은 응답 3개 중 1개꼴로만 있어서, 마지막 응답에 없으면 더 앞 응답에서 찾는다
function New-ProgressLines([string[]]$lines) {
    $id = "conv-" + [Guid]::NewGuid().ToString("N")
    $dir = Join-Path $work "brain\$id\.system_generated\logs"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dir "transcript_full.jsonl"), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return (Get-AgyProgress $id $null)
}
function J($o) { return ($o | ConvertTo-Json -Compress -Depth 8) }
$pa = @{ name = "view_file"; args = @{ AbsolutePath = "C:\a.md"; toolAction = "Reading a.md" } }
$pb = @{ name = "run_command"; args = @{ CommandLine = "npm test"; toolAction = "Testing" } }
$pt = New-ProgressLines @(
    (J ([ordered]@{ step_index = 1; type = "PLANNER_RESPONSE"; thinking = "Read the spec before anything else."; tool_calls = @($pa) })),
    (J ([ordered]@{ step_index = 2; type = "GENERIC"; content = "결과" })),
    (J ([ordered]@{ step_index = 3; type = "PLANNER_RESPONSE"; tool_calls = @($pb) })),
    (J ([ordered]@{ step_index = 4; type = "GENERIC"; content = "결과" })))
Assert-Equal "마지막 응답에 생각이 없으면 앞 응답의 생각을 보인다" "Read the spec before anything else." $pt.thinking
Assert-Equal "  도구와 대상은 그래도 마지막 호출" "run_command|npm test" ("{0}|{1}" -f $pt.tool, $pt.detail)
$pq = New-ProgressLines @(
    (J ([ordered]@{ step_index = 1; type = "PLANNER_RESPONSE"; thinking = "Old thought."; tool_calls = @($pa) })),
    (J ([ordered]@{ step_index = 3; type = "PLANNER_RESPONSE"; thinking = "Newest   thought."; content = "I have started   the tests and will wait."; tool_calls = @($pb) })))
Assert-Equal "마지막 응답에 생각이 있으면 그것을 보인다(공백은 줄인다)" "Newest thought." $pq.thinking
Assert-Equal "도구를 부르면서 적은 content 는 say" "I have started the tests and will wait." $pq.say
$pr = New-ProgressLines @((J ([ordered]@{ step_index = 1; type = "PLANNER_RESPONSE"; tool_calls = @($pa) })))
Assert-Equal "생각도 설명도 없으면 빈 글" "|" ("{0}|{1}" -f $pr.thinking, $pr.say)
$pl = New-ProgressLines @((J ([ordered]@{ step_index = 1; type = "PLANNER_RESPONSE"; thinking = ("가" * 700); tool_calls = @($pa) })))
Assert-Equal "생각은 500자에서 자르고 … 를 붙인다" 501 $pl.thinking.Length

Write-Host "도구별 대상(detail)"
$lbl = @{ toolAction = "x"; toolSummary = "y" }
function With-Label($h) { $o = @{}; foreach ($k in $h.Keys) { $o[$k] = $h[$k] }; $o.toolAction = "라벨"; $o.toolSummary = "요약"; return $o }

Assert-Equal "view_file: 경로와 행 범위" "C:\a\b.md (1~100행)" (New-Progress "view_file" (With-Label @{ AbsolutePath = "C:\a\b.md"; StartLine = "1"; EndLine = "100" })).detail
Assert-Equal "view_file: 행 범위가 없으면 경로만" "C:\a\b.md" (New-Progress "view_file" (With-Label @{ AbsolutePath = "C:\a\b.md" })).detail
Assert-Equal "write_to_file: 대상 파일" "C:\p\new.py" (New-Progress "write_to_file" (With-Label @{ TargetFile = "C:\p\new.py"; Description = "d"; Overwrite = "True"; CodeContent = "긴 코드 본문" })).detail
Assert-Equal "write_to_file: 코드 본문은 detail 에 안 들어간다" $false ((New-Progress "write_to_file" (With-Label @{ TargetFile = "C:\p\new.py"; CodeContent = "긴 코드 본문" })).detail -like "*코드 본문*")
Assert-Equal "replace_file_content: 대상 파일" "C:\p\old.py" (New-Progress "replace_file_content" (With-Label @{ TargetFile = "C:\p\old.py"; TargetContent = "a"; ReplacementContent = "b" })).detail
Assert-Equal "list_dir: 폴더" "C:\p" (New-Progress "list_dir" (With-Label @{ DirectoryPath = "C:\p" })).detail
Assert-Equal "find_by_name: 패턴과 폴더" "*.ts (C:\src)" (New-Progress "find_by_name" (With-Label @{ Pattern = "*.ts"; SearchDirectory = "C:\src" })).detail
Assert-Equal "grep_search: 검색어와 폴더" "TODO (C:\src)" (New-Progress "grep_search" (With-Label @{ Query = "TODO"; SearchPath = "C:\src" })).detail
Assert-Equal "search_web: 검색어" "agy login" (New-Progress "search_web" (With-Label @{ query = "agy login" })).detail
Assert-Equal "read_url_content: 주소" "https://x.y/z" (New-Progress "read_url_content" (With-Label @{ Url = "https://x.y/z" })).detail
Assert-Equal "manage_task: 동작과 작업 ID" "status conv/task-12" (New-Progress "manage_task" (With-Label @{ Action = "status"; TaskId = "conv/task-12" })).detail
Assert-Equal "schedule: 초와 메시지" "1초 · Check task-79" (New-Progress "schedule" (With-Label @{ DurationSeconds = "1"; Prompt = "Check task-79"; TimerCondition = "c/task-79" })).detail
Assert-Equal "generate_image: 이미지 이름" "weather_icon" (New-Progress "generate_image" (With-Label @{ ImageName = "weather_icon"; Prompt = "긴 프롬프트" })).detail

Write-Host "run_command 부가 정보"
$bg = New-Progress "run_command" (With-Label @{ CommandLine = "npm run build"; Cwd = "C:\app"; IsDaemon = $true })
Assert-Equal "IsDaemon=true 는 백그라운드" $true $bg.background
$bg2 = New-Progress "run_command" (With-Label @{ CommandLine = "npm run build"; Cwd = "C:\app"; IsDaemon = "True" })
Assert-Equal "IsDaemon=`"True`"(문자열)도 백그라운드" $true $bg2.background
$fg = New-Progress "run_command" (With-Label @{ CommandLine = "dir"; Cwd = "C:\app"; IsDaemon = $false })
Assert-Equal "IsDaemon=false 는 백그라운드 아님" $false $fg.background

Write-Host "다듬기와 경계 사례"
$multi = New-Progress "run_command" (With-Label @{ CommandLine = "echo 1`r`n  echo   2`t`n`necho 3"; Cwd = "C:\x" })
Assert-Equal "여러 줄 명령은 한 줄로, 공백은 하나로" "echo 1 echo 2 echo 3" $multi.detail
$long = New-Progress "run_command" (With-Label @{ CommandLine = ("x" * 500); Cwd = "C:\x" })
Assert-Equal "200자를 넘으면 자르고 … 를 붙인다" 201 $long.detail.Length
Assert-Equal "  끝이 …" "…" $long.detail.Substring(200)
$unknown = New-Progress "brand_new_tool" @{ toolAction = "라벨"; toolSummary = "요약"; Target = "대상값"; Flag = $true }
Assert-Equal "모르는 도구: 이름은 그대로" "brand_new_tool" $unknown.tool
Assert-Equal "모르는 도구: 라벨이 아닌 첫 문자열 인자를 대상으로" "대상값" $unknown.detail
$noargs = New-Progress "list_dir" @{ toolAction = "라벨" }
Assert-Equal "대상 인자가 없으면 detail 은 빈 값(오류 없음)" "" $noargs.detail
Assert-Equal "  라벨은 그대로" "라벨" $noargs.action
$onlySummary = New-Progress "view_file" @{ AbsolutePath = "C:\a.md"; toolSummary = "요약만 있음" }
Assert-Equal "toolAction 이 없으면 toolSummary 를 라벨로(기존 동작)" "요약만 있음" $onlySummary.action
$bare = New-Progress "view_file" @{ AbsolutePath = "C:\a.md" }
Assert-Equal "라벨이 둘 다 없으면 도구 이름을 라벨로(기존 동작)" "view_file" $bare.action

Write-Host "도구 호출이 없는 응답(최종 답변)"
$id = "conv-final"
$dir = Join-Path $work "brain\$id\.system_generated\logs"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[System.IO.File]::WriteAllText((Join-Path $dir "transcript_full.jsonl"), ('{"step_index":30,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","thinking":"끝","content":"최종 답변"}' + "`n"), (New-Object System.Text.UTF8Encoding($false)))
$final = Get-AgyProgress $id $null
Assert-Equal "오류 없이 단계는 읽는다" 30 $final.step
Assert-Equal "도구/대상/라벨은 비어 있다" "||" ("{0}|{1}|{2}" -f $final.tool, $final.detail, $final.action)

Write-Host "진행 중인 대화의 과정 목록(steps): 새로 쌓인 것만 이어 읽는다"
$sid = "conv-steps"
$sdir = Join-Path $work "brain\$sid\.system_generated\logs"
New-Item -ItemType Directory -Force -Path $sdir | Out-Null
$stFile = Join-Path $sdir "transcript_full.jsonl"
function PlannerLine([int]$n, [string]$cmd) {
    return ([ordered]@{ step_index = $n; type = "PLANNER_RESPONSE"; created_at = "2026-10-13T07:48:57Z"; thinking = "t$n"
        tool_calls = @(@{ name = "run_command"; args = @{ CommandLine = $cmd; Cwd = "C:\w"; toolAction = "L$n" } }) } | ConvertTo-Json -Compress -Depth 8)
}
$u8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($stFile, ((PlannerLine 1 "cmd1") + "`n" + (PlannerLine 3 "cmd2") + "`n"), $u8)
$g1 = Get-AgyProgress $sid $null
Assert-Equal "처음에는 호출 2개를 담는다" 2 @($g1.steps).Count
Assert-Equal "  마지막 호출이 지금(detail)이다" "cmd2" $g1.detail
[System.IO.File]::AppendAllText($stFile, ((PlannerLine 5 "cmd3") + "`n"), $u8)
$g2 = Get-AgyProgress $sid $null
Assert-Equal "새 줄이 쌓이면 3개 (앞의 것을 다시 읽어 중복되지 않는다)" 3 @($g2.steps).Count
Assert-Equal "  순서와 번호" "1,3,5" ((@($g2.steps) | ForEach-Object { $_.n }) -join ",")
$g3 = Get-AgyProgress $sid $null
Assert-Equal "변화가 없을 때 다시 불러도 그대로 3개" 3 @($g3.steps).Count
[System.IO.File]::AppendAllText($stFile, (PlannerLine 7 "cmd4").Substring(0, 40), $u8)   # agy 가 쓰는 중인 줄(줄바꿈 없음)
$g4 = Get-AgyProgress $sid $null
Assert-Equal "쓰는 중인 마지막 줄은 아직 담지 않는다" 3 @($g4.steps).Count
[System.IO.File]::WriteAllText($stFile, ((PlannerLine 1 "new1") + "`n"), $u8)   # 파일이 새로 만들어져 더 짧아짐
$g5 = Get-AgyProgress $sid $null
Assert-Equal "파일이 더 짧아지면(새로 만들어짐) 처음부터 다시 읽는다" 1 @($g5.steps).Count
Assert-Equal "  새 내용이다" "new1" @($g5.steps)[0].detail
Assert-Equal "도구를 부르지 않은 최종 답변뿐이면 steps 는 빈 목록" 0 @($final.steps).Count

Write-Host "실시간 누적 토큰 증분 읽기 검증"
$tokConvId = "conv-token-test"
$tokDir = Join-Path $work "brain\$tokConvId\.system_generated\logs"
New-Item -ItemType Directory -Force -Path $tokDir | Out-Null
$tokFullFile = Join-Path $tokDir "transcript_full.jsonl"
[System.IO.File]::WriteAllText($tokFullFile, ((PlannerLine 1 "dummy") + "`n"), $u8)
$tokFile = Join-Path $tokDir "transcript.jsonl"
$line1 = '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","input_tokens":100,"output_tokens":50}' + "`n"
[System.IO.File]::WriteAllText($tokFile, $line1, $u8)

$tokProg1 = Get-AgyProgress $tokConvId $null
Assert-Equal "첫 호출 시 input_tokens 100" 100 $tokProg1.tokens.input
Assert-Equal "첫 호출 시 output_tokens 50" 50 $tokProg1.tokens.output
Assert-Equal "첫 호출 시 total 150" 150 $tokProg1.tokens.total

$line2 = '{"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","input_tokens":200,"cache_read_tokens":30,"output_tokens":70}' + "`n"
[System.IO.File]::AppendAllText($tokFile, $line2, $u8)

$tokProg2 = Get-AgyProgress $tokConvId $null
Assert-Equal "증분 읽기 후 input_tokens 330 (100 + 200 + 30)" 330 $tokProg2.tokens.input
Assert-Equal "증분 읽기 후 output_tokens 120 (50 + 70)" 120 $tokProg2.tokens.output
Assert-Equal "증분 읽기 후 total 450" 450 $tokProg2.tokens.total

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
$env:AGY_HOME = $null
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
