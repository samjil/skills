# agy-progress.ps1 의 과정 읽기(Read-AgyProcessSteps, Get-AgyTranscriptPath) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-process.tests.ps1
# 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다. 임시 폴더의 가짜 대화 기록만 쓰고 실제 agy 기록은 건드리지 않습니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-progress.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("agy-process-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function New-Line($obj) { return ($obj | ConvertTo-Json -Compress -Depth 8) }
function Planner([int]$step, $calls, [string]$created = "2026-10-13T07:48:57Z", [string]$thinking = "생각") {
    $o = [ordered]@{ step_index = $step; source = "MODEL"; type = "PLANNER_RESPONSE"; status = "DONE"; created_at = $created; thinking = $thinking }
    if ($calls) { $o.tool_calls = @($calls) } else { $o.content = "최종 답변" }
    return (New-Line $o)
}
function Call($name, $toolArgs) { return @{ name = $name; args = $toolArgs } }
function Write-Transcript([string]$name, [string[]]$lines, [bool]$bom = $false, [bool]$finalNewline = $true) {
    $path = Join-Path $work $name
    $text = ($lines -join "`n") + $(if ($finalNewline) { "`n" } else { "" })
    $bytes = $utf8.GetBytes($text)
    if ($bom) { $bytes = [byte[]](@(0xEF, 0xBB, 0xBF) + $bytes) }
    [System.IO.File]::WriteAllBytes($path, $bytes)
    return $path
}

Write-Host "Get-AgyTranscriptPath"
$p = Get-AgyTranscriptPath "C:\agyhome" "0ca0fbed-b6b2-40e9-a719-173408c50dae"
Assert-Equal "정상 id 는 brain\<id>\.system_generated\logs\transcript_full.jsonl" "C:\agyhome\brain\0ca0fbed-b6b2-40e9-a719-173408c50dae\.system_generated\logs\transcript_full.jsonl" $p
foreach ($bad in @("..\x", "a/b", "a\b", "", "x y", "id;rm", ("a" * 81))) {
    Assert-Equal "경로 문자가 섞인 id 는 거절: [$bad]" $true ($null -eq (Get-AgyTranscriptPath "C:\agyhome" $bad))
}

Write-Host "Read-AgyProcessSteps: 기본"
$lines = @(
    (New-Line @{ step_index = 0; type = "USER_INPUT"; content = "질문" }),
    (Planner 1 @((Call "view_file" @{ AbsolutePath = "C:\a.md"; StartLine = "1"; EndLine = "45"; toolAction = "Reading a.md"; toolSummary = "Read a.md" }))),
    (New-Line @{ step_index = 2; type = "GENERIC"; content = "결과" }),
    (Planner 3 @((Call "run_command" @{ CommandLine = "Get-Location"; Cwd = "C:\w"; toolAction = "Checking target directory"; toolSummary = "s" }),
                 (Call "write_to_file" @{ TargetFile = "C:\w\x.py"; CodeContent = "긴 본문"; toolSummary = "요약만" })) "2026-10-13T07:49:51Z" "첫 번째  호출에   붙는 생각"),
    (New-Line @{ step_index = 4; type = "GENERIC"; content = "결과" }),
    (Planner 5 @((Call "run_command" @{ CommandLine = "npm run build"; Cwd = "C:\w"; IsDaemon = $true; toolAction = "Building" }))),
    (Planner 6 $null)
)
$path = Write-Transcript "a.jsonl" $lines
$r = Read-AgyProcessSteps $path
$st = @($r.Steps)
Assert-Equal "도구 호출만 모은다 (호출 4개: view_file, run_command, write_to_file, run_command)" 4 $st.Count
Assert-Equal "  결과 줄(GENERIC)·질문(USER_INPUT)·도구 없는 최종 답변은 제외" "view_file,run_command,write_to_file,run_command" (($st | ForEach-Object { $_.tool }) -join ",")
Assert-Equal "  단계 번호" "1,3,3,5" (($st | ForEach-Object { $_.n }) -join ",")
Assert-Equal "  첫 호출의 대상(경로와 행 범위)" "C:\a.md (1~45행)" $st[0].detail
Assert-Equal "  첫 호출의 영어 라벨" "Reading a.md" $st[0].label
Assert-Equal "  명령 대상" "Get-Location" $st[1].detail
Assert-Equal "  toolAction 이 없으면 toolSummary 가 라벨" "요약만" $st[2].label
Assert-Equal "  쓰기 대상은 파일 경로이고 코드 본문은 없다" "C:\w\x.py" $st[2].detail
Assert-Equal "  생각은 공백을 줄여 첫 호출에만 붙는다" "첫 번째 호출에 붙는 생각" $st[1].think
Assert-Equal "  같은 응답의 두 번째 호출에는 생각이 없다" "" $st[2].think
Assert-Equal "  백그라운드 명령은 bg=true" $true ([bool]$st[3].bg)
Assert-Equal "  일반 호출에는 bg 키가 없다" $false ($st[0].Contains("bg"))
$expectedAt = ([datetime]::SpecifyKind([datetime]"2026-10-13 07:48:57", [DateTimeKind]::Utc)).ToLocalTime().ToString("HH:mm:ss")
Assert-Equal "  시각은 UTC 를 이 PC 의 시각(HH:mm:ss)으로" $expectedAt $st[0].at
Assert-Equal "  Offset 은 파일 끝" (Get-Item $path).Length $r.Offset

Write-Host "Read-AgyProcessSteps: agy 가 도구를 부르며 적은 진행 설명(say)"
$sayLine = New-Line ([ordered]@{ step_index = 1; type = "PLANNER_RESPONSE"; created_at = "2026-10-13T07:48:57Z"; content = 'I have  launched `npm run build`   and will wait.';
    tool_calls = @((Call "run_command" @{ CommandLine = "npm run build"; toolAction = "Building" }), (Call "view_file" @{ AbsolutePath = "C:\f"; toolAction = "V" })) })
$ps = Write-Transcript "say.jsonl" @($sayLine, (Planner 3 @((Call "list_dir" @{ DirectoryPath = "C:\w"; toolAction = "L" }))))
$sst = @((Read-AgyProcessSteps $ps).Steps)
Assert-Equal "도구를 부르면서 적은 content 는 첫 호출의 say (공백은 줄인다)" 'I have launched `npm run build` and will wait.' $sst[0].say
Assert-Equal "  같은 응답의 두 번째 호출에는 say 가 없다" $false $sst[1].Contains("say")
Assert-Equal "  content 가 없는 응답에는 say 키가 없다" $false $sst[2].Contains("say")
$longSay = New-Line ([ordered]@{ step_index = 1; type = "PLANNER_RESPONSE"; created_at = "2026-10-13T07:48:57Z"; content = ("나" * 400); tool_calls = @((Call "list_dir" @{ DirectoryPath = "C:\w"; toolAction = "L" })) })
$rls = @((Read-AgyProcessSteps (Write-Transcript "longsay.jsonl" @($longSay))).Steps)[0].say
Assert-Equal "say 기본 상한은 300자(넘으면 … 를 붙인다)" 301 $rls.Length

Write-Host "Read-AgyProcessSteps: 이어 읽기(진행 중인 대화)"
$base = @((Planner 1 @((Call "list_dir" @{ DirectoryPath = "C:\w"; toolAction = "L" }))), (Planner 2 @((Call "view_file" @{ AbsolutePath = "C:\f"; toolAction = "V" }))))
$p2 = Write-Transcript "b.jsonl" $base
$r1 = Read-AgyProcessSteps $p2
Assert-Equal "처음에는 2개" 2 @($r1.Steps).Count
# agy 가 새 줄을 쓰는 중: 줄바꿈이 아직 없는 마지막 줄은 읽지 않는다
$partial = (Planner 3 @((Call "run_command" @{ CommandLine = "echo 한글 명령"; toolAction = "E" })))
[System.IO.File]::AppendAllText($p2, $partial.Substring(0, 60), $utf8)
$r2 = Read-AgyProcessSteps $p2 $r1.Offset
Assert-Equal "쓰는 중인 마지막 줄(줄바꿈 없음)은 읽지 않는다" 0 @($r2.Steps).Count
Assert-Equal "  Offset 도 그 줄 앞에 그대로" $r1.Offset $r2.Offset
# 줄이 완성되면(나머지 + 줄바꿈) 그때 읽는다
[System.IO.File]::AppendAllText($p2, $partial.Substring(60) + "`n", $utf8)
$r3 = Read-AgyProcessSteps $p2 $r2.Offset
Assert-Equal "줄이 완성되면 새로 쌓인 것만 읽는다" 1 @($r3.Steps).Count
Assert-Equal "  한글이 든 명령도 온전하다" "echo 한글 명령" @($r3.Steps)[0].detail
Assert-Equal "  Offset 은 파일 끝" (Get-Item $p2).Length $r3.Offset
$r4 = Read-AgyProcessSteps $p2 $r3.Offset
Assert-Equal "더 쌓인 게 없으면 빈 목록" 0 @($r4.Steps).Count
Assert-Equal "  Offset 은 그대로" $r3.Offset $r4.Offset
# 파일이 교체돼 더 짧아졌으면 처음부터 다시 읽는다
$p3 = Write-Transcript "b.jsonl" @($base[0])
$r5 = Read-AgyProcessSteps $p3 $r3.Offset
Assert-Equal "Offset 이 파일보다 크면(파일이 바뀜) 처음부터 읽는다" 1 @($r5.Steps).Count

Write-Host "Read-AgyProcessSteps: 경계 사례"
$pb = Write-Transcript "bom.jsonl" @((Planner 1 @((Call "list_dir" @{ DirectoryPath = "C:\w"; toolAction = "L" })))) $true
Assert-Equal "파일 맨 앞에 BOM 이 있어도 첫 줄을 읽는다" 1 @((Read-AgyProcessSteps $pb).Steps).Count
$many = 1..8 | ForEach-Object { Planner $_ @((Call "view_file" @{ AbsolutePath = "C:\f$_"; toolAction = "V" })) }
$pm = Write-Transcript "many.jsonl" $many
$rm = Read-AgyProcessSteps $pm 0 3
Assert-Equal "MaxSteps(3)를 넘는 호출은 담지 않는다" 3 @($rm.Steps).Count
Assert-Equal "  앞쪽 3개가 남는다" "1,2,3" ((@($rm.Steps) | ForEach-Object { $_.n }) -join ",")
Assert-Equal "  Offset 은 그래도 파일 끝(다음에 같은 걸 다시 읽지 않는다)" (Get-Item $pm).Length $rm.Offset
$pt = Write-Transcript "think.jsonl" @((Planner 1 @((Call "list_dir" @{ DirectoryPath = "C:\w"; toolAction = "L" })) "2026-10-13T07:48:57Z" ("가" * 500)))
$rt = Read-AgyProcessSteps $pt 0 400 50
Assert-Equal "생각은 ThinkingMax(50)에서 자르고 … 를 붙인다" 51 @($rt.Steps)[0].think.Length
Assert-Equal "  끝이 …" "…" @($rt.Steps)[0].think.Substring(50)
Assert-Equal "생각 기본 상한은 500자(넘으면 … 를 붙인다)" 501 @((Read-AgyProcessSteps (Write-Transcript "think600.jsonl" @((Planner 1 @((Call "list_dir" @{ DirectoryPath = "C:\w"; toolAction = "L" })) "2026-10-13T07:48:57Z" ("가" * 600))))).Steps)[0].think.Length
$rn = Read-AgyProcessSteps (Join-Path $work "없는파일.jsonl") 123
Assert-Equal "파일이 없으면 빈 목록" 0 @($rn.Steps).Count
Assert-Equal "  Offset 은 그대로" 123 $rn.Offset
Assert-Equal "경로가 비어 있어도 오류 없이 빈 목록" 0 @((Read-AgyProcessSteps $null).Steps).Count
$pe = Write-Transcript "empty.jsonl" @()
Assert-Equal "빈 파일은 빈 목록" 0 @((Read-AgyProcessSteps $pe).Steps).Count
$pg = Write-Transcript "garbage.jsonl" @("이건 JSON 이 아님 tool_calls", (Planner 1 @((Call "list_dir" @{ DirectoryPath = "C:\w"; toolAction = "L" }))))
Assert-Equal "깨진 줄은 건너뛰고 나머지를 읽는다" 1 @((Read-AgyProcessSteps $pg).Steps).Count
$pn = Write-Transcript "noargs.jsonl" @((Planner 1 @(@{ name = "list_dir" })))
$rr = Read-AgyProcessSteps $pn
Assert-Equal "인자가 없는 호출도 오류 없이(대상·라벨 빈 값)" "list_dir||" ("{0}|{1}|{2}" -f @($rr.Steps)[0].tool, @($rr.Steps)[0].detail, @($rr.Steps)[0].label)

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
