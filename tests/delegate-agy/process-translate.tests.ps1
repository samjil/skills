# process-translate.ps1 (과정 창의 "한글로 번역") 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\process-translate.tests.ps1
# 함수 단위 시험 + 가짜 agy(agy.cmd, PATH 맨 앞)로 본체를 끝까지 돌리는 시험입니다. 진짜 agy 와 agy 기록은 건드리지 않습니다(몇 초).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$trScript = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\process-translate.ps1"
. $trScript

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("process-translate-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

Write-Host "Test-HasHangul"
Assert-Equal "한글이 있으면 true" $true (Test-HasHangul "폴더 확인 중")
Assert-Equal "영어만 있으면 false" $false (Test-HasHangul "Checking target directory")
Assert-Equal "영어에 한글이 조금 섞여도 true" $true (Test-HasHangul "Reading 파일")
Assert-Equal "빈 글은 false" $false (Test-HasHangul "")
Assert-Equal "null 도 false" $false (Test-HasHangul $null)

Write-Host "Test-NeedsTranslation (인용문 안의 한글은 세지 않는다)"
Assert-Equal "영어 문장 속 백틱 한글 인용문은 번역 대상" $true (Test-NeedsTranslation 'Examined the `04_문진 이벤트 로그 - 조회.sql` file, identifying event names.')
Assert-Equal "큰따옴표 안의 한글도 번역 대상" $true (Test-NeedsTranslation 'Open the "문진 로그" file now.')
Assert-Equal "둥근 큰따옴표 안의 한글도 번역 대상" $true (Test-NeedsTranslation ('Open the ' + [char]0x201C + '문진 로그' + [char]0x201D + ' file now.'))
Assert-Equal "작은따옴표 안의 한글도 번역 대상" $true (Test-NeedsTranslation "Open the '문진 로그' file now.")
Assert-Equal "인용문 밖에 한글이 있으면 번역 안 함" $false (Test-NeedsTranslation '`a.sql` 파일을 읽는 중')
Assert-Equal "영어에 한글이 조금 섞이면(인용문 밖) 번역 안 함" $false (Test-NeedsTranslation 'Reading 파일')
Assert-Equal "영어만 있으면 번역 대상" $true (Test-NeedsTranslation 'Reading a.md')
Assert-Equal "인용문뿐이면 번역할 영어가 없어 대상이 아니다" $false (Test-NeedsTranslation '`04_문진.sql`')
Assert-Equal "기호뿐이어도 대상이 아니다" $false (Test-NeedsTranslation '---')
Assert-Equal "빈 글·null 도 대상이 아니다" $false ((Test-NeedsTranslation '') -or (Test-NeedsTranslation $null))
Assert-Equal "don't 같은 아포스트로피는 인용문이 아니다" $false (Test-NeedsTranslation "I don't know 문진 it's")

Write-Host "Get-TranslationTodo"
$steps = @(
    [ordered]@{ n = 1; tool = "view_file"; detail = "a.md"; label = "Reading a.md"; think = "Read the spec first." },
    [ordered]@{ n = 3; tool = "write_to_file"; detail = "b.py"; label = "파일 작성 중"; think = "" },
    [ordered]@{ n = 5; tool = "run_command"; detail = "pytest"; label = "Running tests"; think = "생각은 이미 한글"; say = "I have started the tests." },
    [ordered]@{ n = 7; tool = "run_command"; detail = "x"; label = ""; think = "" }
)
$todo = @(Get-TranslationTodo $steps @{})
Assert-Equal "번역할 칸이 있는 단계만(0, 2번째)" "0,2" (($todo | ForEach-Object { $_.i }) -join ",")
Assert-Equal "  0번째: 라벨과 생각" "label,think" ((@($todo[0].Keys) | Where-Object { $_ -ne 'i' }) -join ",")
Assert-Equal "  한글이 이미 든 칸(생각)은 뺀다: 2번째는 라벨과 설명만" "label,say" ((@($todo[1].Keys) | Where-Object { $_ -ne 'i' }) -join ",")
Assert-Equal "  라벨이 한글인 1번째 단계는 건너뛴다" $false (($todo | ForEach-Object { $_.i }) -contains 1)
$done = @{ "0" = @{ label = "a.md 읽는 중" } }
$todo2 = @(Get-TranslationTodo $steps $done)
Assert-Equal "이미 번역한 칸은 다시 안 한다: 0번째는 생각만" "think" ((@($todo2[0].Keys) | Where-Object { $_ -ne 'i' }) -join ",")
$done = @{ "0" = @{ label = "x"; think = "y" }; "2" = @{ label = "x"; say = "y" } }
Assert-Equal "모두 번역해 뒀으면 할 일이 없다" 0 @(Get-TranslationTodo $steps $done).Count
Assert-Equal "단계가 없으면 할 일이 없다" 0 @(Get-TranslationTodo @() @{}).Count

Write-Host "Split-TranslationChunks"
$items = 1..5 | ForEach-Object { [ordered]@{ i = $_; think = ("a" * 100) } }
$ch = @(Split-TranslationChunks $items 300)
Assert-Equal "300자 안쪽으로 나눈다(항목 하나가 130자: 2개씩)" "2,2,1" ((@($ch) | ForEach-Object { @($_).Count }) -join ",")
Assert-Equal "순서가 유지된다" "1,2,3,4,5" ((@($ch) | ForEach-Object { @($_) } | ForEach-Object { $_.i }) -join ",")
$big = @([ordered]@{ i = 0; think = ("b" * 9000) }, [ordered]@{ i = 1; think = "c" })
$ch2 = @(Split-TranslationChunks $big 5000)
Assert-Equal "혼자 한도를 넘는 항목은 따로 한 덩어리로 보낸다" "1,1" ((@($ch2) | ForEach-Object { @($_).Count }) -join ",")
Assert-Equal "할 일이 없으면 덩어리도 없다" 0 @(Split-TranslationChunks @() 5000).Count

Write-Host "ConvertFrom-TranslationReply / Merge-TranslationReply"
$r1 = ConvertFrom-TranslationReply '[{"i":0,"think":"안녕"}]'
Assert-Equal "깨끗한 JSON 배열" "안녕" $r1[0].think
$r2 = ConvertFrom-TranslationReply ("여기 번역입니다:`n``````json`n" + '[{"i":0,"think":"가"},{"i":2,"label":"나"}]' + "`n``````")
Assert-Equal "코드블록과 앞뒤 설명이 섞여도 배열을 꺼낸다" 2 @($r2).Count
Assert-Equal "배열이 아니면 null" $true ($null -eq (ConvertFrom-TranslationReply "번역할 수 없습니다"))
Assert-Equal "깨진 JSON 은 null" $true ($null -eq (ConvertFrom-TranslationReply '[{"i":0,'))
Assert-Equal "빈 글은 null" $true ($null -eq (ConvertFrom-TranslationReply ""))
$chunk = @([ordered]@{ i = 0; label = "L"; think = "T" }, [ordered]@{ i = 2; say = "S" })
$cache = @{}
$n = Merge-TranslationReply $cache $chunk @(
    [pscustomobject]@{ i = 0; label = " 라벨 "; think = "생각"; say = "요청 안 한 칸" },
    [pscustomobject]@{ i = 2; say = "설명" },
    [pscustomobject]@{ i = 9; think = "요청 안 한 단계" },
    [pscustomobject]@{ i = 2; think = "요청 안 한 칸" })
Assert-Equal "요청한 칸만 넣는다(0번 라벨·생각, 2번 설명 = 3칸)" 3 $n
Assert-Equal "  앞뒤 공백은 지운다" "라벨" $cache["0"].label
Assert-Equal "  요청하지 않은 칸(say)은 버린다" $false $cache["0"].ContainsKey("say")
Assert-Equal "  요청하지 않은 단계(9)는 버린다" $false $cache.ContainsKey("9")
Assert-Equal "  요청하지 않은 칸(2번의 think)은 버린다" $false $cache["2"].ContainsKey("think")
$n2 = Merge-TranslationReply @{} $chunk @([pscustomobject]@{ i = 0; label = ""; think = ("가" * 3001) })
Assert-Equal "빈 글과 3000자를 넘는 글은 버린다" 0 $n2
Assert-Equal "i 가 없는 항목은 건너뛴다" 0 (Merge-TranslationReply @{} $chunk @([pscustomobject]@{ think = "x" }))

Write-Host "Read/Write-TranslationCache"
$cf = Join-Path $work "cache.json"
Assert-Equal "파일이 없으면 빈 캐시" "|0|0" ("{0}|{1}|{2}" -f (Read-TranslationCache $cf).Status, (Read-TranslationCache $cf).StepsCovered, (Read-TranslationCache $cf).Items.Count)
Write-TranslationCache $cf "done" "" 7 @{ "0" = @{ label = "라벨"; think = "생각 `"따옴표`" 와 `n줄바꿈" } } "m1"
$rc = Read-TranslationCache $cf
Assert-Equal "쓴 것을 그대로 읽는다(상태·단계 수·모델)" "done|7|m1" ("{0}|{1}|{2}" -f $rc.Status, $rc.StepsCovered, $rc.Model)
Assert-Equal "  따옴표와 줄바꿈이 든 글도 온전하다" "생각 `"따옴표`" 와 `n줄바꿈" $rc.Items["0"].think
Assert-Equal "  임시 파일이 남지 않는다" $false (Test-Path "$cf.tmp")
[System.IO.File]::WriteAllText($cf, "{ 깨진", $utf8)
Assert-Equal "깨진 캐시는 빈 캐시로 본다" 0 (Read-TranslationCache $cf).Items.Count

Write-Host "본체: 가짜 agy 로 끝까지"
$fakeBin = Join-Path $work "bin"
$agyHome = Join-Path $work "agyhome"
New-Item -ItemType Directory -Force -Path $fakeBin | Out-Null
Set-Content -Path (Join-Path $fakeBin "fake-agy.ps1") -Encoding ASCII -Value @'
$a = @($args)
Add-Content -Path $env:FAKE_ARGS_LOG -Value ("args=" + ($a -join ' '))
if ($env:FAKE_MODE -eq 'hang') { Start-Sleep -Seconds 30 }
$pf = ([string]$a[1]).Substring(1)
$text = [System.IO.File]::ReadAllText($pf, [System.Text.Encoding]::UTF8)
$line = ($text -split "`n" | Where-Object { $_.Trim().StartsWith('[') } | Select-Object -Last 1)
if ($env:FAKE_MODE -eq 'garbage-once' -and -not (Test-Path ($env:FAKE_ARGS_LOG + '.once'))) { New-Item -ItemType File -Path ($env:FAKE_ARGS_LOG + '.once') | Out-Null; '{"status":"SUCCESS","response":"I wrote a plan. Please approve."}'; exit 0 }
if ($env:FAKE_MODE -eq 'garbage') { '{"status":"SUCCESS","response":"cannot translate this"}'; exit 0 }
$in = ConvertFrom-Json -InputObject $line
$out = foreach ($it in @($in)) {
    $o = [ordered]@{ i = $it.i }
    foreach ($f in 'label', 'think', 'say') { if ($it.PSObject.Properties[$f]) { $o[$f] = 'KO:' + $it.$f } }
    $o
}
$resp = ConvertTo-Json -InputObject @($out) -Compress
'{"status":"SUCCESS","response":' + (ConvertTo-Json -InputObject $resp) + ',"conversation_id":"tr-conv"}'
'@
Set-Content -Path (Join-Path $fakeBin "agy.cmd") -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake-agy.ps1`" %*"
$env:PATH = "$fakeBin;$env:PATH"
$env:AGY_HOME = $agyHome
$env:FAKE_ARGS_LOG = Join-Path $work "args.log"

# 가짜 대화 기록: 영어 생각 2개 + 한글 생각 1개 + 영어 라벨
$convId = "conv-tr-1"
$tdir = Join-Path $agyHome "brain\$convId\.system_generated\logs"
New-Item -ItemType Directory -Force -Path $tdir | Out-Null
function J($o) { return ($o | ConvertTo-Json -Compress -Depth 8) }
$lines = @(
    (J ([ordered]@{ step_index = 1; type = "PLANNER_RESPONSE"; created_at = "2026-10-13T07:48:57Z"; thinking = "Read the spec first."; tool_calls = @(@{ name = "view_file"; args = @{ AbsolutePath = "C:\a.md"; toolAction = "Reading a.md" } }) })),
    (J ([ordered]@{ step_index = 3; type = "PLANNER_RESPONSE"; created_at = "2026-10-13T07:49:57Z"; thinking = "이미 한글 생각"; tool_calls = @(@{ name = "run_command"; args = @{ CommandLine = "ls"; toolAction = "목록 보기" } }) })),
    (J ([ordered]@{ step_index = 5; type = "PLANNER_RESPONSE"; created_at = "2026-10-13T07:50:57Z"; thinking = "Run the tests next."; content = "I have started the tests."; tool_calls = @(@{ name = "run_command"; args = @{ CommandLine = "pytest"; toolAction = "Running tests" } }) }))
)
[System.IO.File]::WriteAllText((Join-Path $tdir "transcript_full.jsonl"), (($lines -join "`n") + "`n"), $utf8)

$out1 = Join-Path $work "ko\$convId.json"
& $trScript -ConversationId $convId -OutFile $out1 -TimeoutSeconds 60
$c1 = Read-TranslationCache $out1
Assert-Equal "상태 done, 3단계를 다뤘다" "done|3" ("{0}|{1}" -f $c1.Status, $c1.StepsCovered)
Assert-Equal "  0번째: 라벨과 생각을 번역" "KO:Reading a.md|KO:Read the spec first." ("{0}|{1}" -f $c1.Items["0"].label, $c1.Items["0"].think)
Assert-Equal "  1번째(이미 한글)는 번역하지 않는다" $false $c1.Items.ContainsKey("1")
Assert-Equal "  2번째: 라벨·생각·설명" "KO:Running tests|KO:Run the tests next.|KO:I have started the tests." ("{0}|{1}|{2}" -f $c1.Items["2"].label, $c1.Items["2"].think, $c1.Items["2"].say)
Assert-Equal "  실행 표시 파일(.running)이 남지 않는다" $false (Test-Path "$out1.running")
$log = Get-Content -LiteralPath $env:FAKE_ARGS_LOG -Raw
Assert-Equal "  agy 는 읽기 전용(--mode plan)으로 부른다" $true ($log -match '--mode plan')
Assert-Equal "  권한 자동 승인(--dangerously-skip-permissions)을 쓰지 않는다" $false ($log -match 'dangerously')
Assert-Equal "  번역 모델은 gemini-3.8-flash-low" $true ($log -match '--model gemini-3.8-flash-low')
Assert-Equal "  agy 는 한 번만 불렀다(한 덩어리)" 1 @(Get-Content -LiteralPath $env:FAKE_ARGS_LOG).Count

# 두 번째 실행: 이미 다 번역했으니 agy 를 부르지 않는다
Remove-Item -LiteralPath $env:FAKE_ARGS_LOG -Force
& $trScript -ConversationId $convId -OutFile $out1 -TimeoutSeconds 60
Assert-Equal "다시 실행해도 agy 를 부르지 않는다(캐시)" $false (Test-Path $env:FAKE_ARGS_LOG)
Assert-Equal "  상태는 그대로 done" "done" (Read-TranslationCache $out1).Status

# 진행 중인 대화에 단계가 늘면 새 단계만 번역한다
$more = J ([ordered]@{ step_index = 7; type = "PLANNER_RESPONSE"; created_at = "2026-10-13T07:51:57Z"; thinking = "Finish up."; tool_calls = @(@{ name = "view_file"; args = @{ AbsolutePath = "C:\b.md"; toolAction = "Reading b.md" } }) })
[System.IO.File]::AppendAllText((Join-Path $tdir "transcript_full.jsonl"), $more + "`n", $utf8)
& $trScript -ConversationId $convId -OutFile $out1 -TimeoutSeconds 60
$c3 = Read-TranslationCache $out1
Assert-Equal "새 단계(3번째)만 번역하고 4단계를 다뤘다" "done|4|KO:Finish up." ("{0}|{1}|{2}" -f $c3.Status, $c3.StepsCovered, $c3.Items["3"].think)
Assert-Equal "  앞서 번역한 것은 그대로" "KO:Read the spec first." $c3.Items["0"].think

# 대화 기록이 없으면 unavailable
$out2 = Join-Path $work "ko\nope.json"
& $trScript -ConversationId "conv-nope" -OutFile $out2
Assert-Equal "대화 기록이 없으면 unavailable" "unavailable" (Read-TranslationCache $out2).Status
Assert-Equal "  실행 표시 파일이 남지 않는다" $false (Test-Path "$out2.running")

# 경로 문자가 든 대화 id 는 거절(unavailable)
$out3 = Join-Path $work "ko\bad.json"
& $trScript -ConversationId "..\x" -OutFile $out3
Assert-Equal "경로 문자가 든 대화 id 는 unavailable" "unavailable" (Read-TranslationCache $out3).Status

# agy 가 번역이 아닌 답을 주면 error
$env:FAKE_MODE = "garbage"
$convId2 = "conv-tr-2"
$tdir2 = Join-Path $agyHome "brain\$convId2\.system_generated\logs"
New-Item -ItemType Directory -Force -Path $tdir2 | Out-Null
[System.IO.File]::WriteAllText((Join-Path $tdir2 "transcript_full.jsonl"), ($lines[0] + "`n"), $utf8)
$out4 = Join-Path $work "ko\$convId2.json"
Remove-Item -LiteralPath $env:FAKE_ARGS_LOG -Force -ErrorAction SilentlyContinue
& $trScript -ConversationId $convId2 -OutFile $out4 -TimeoutSeconds 60
$c4 = Read-TranslationCache $out4
Assert-Equal "JSON 이 아닌 답이면 error 와 이유" "error|True" ("{0}|{1}" -f $c4.Status, ($c4.Message -like "*JSON*"))
Assert-Equal "  번역된 것은 없고 단계 수도 올라가지 않는다" "0|0" ("{0}|{1}" -f $c4.Items.Count, $c4.StepsCovered)
Assert-Equal "  실행 표시 파일이 남지 않는다" $false (Test-Path "$out4.running")
Assert-Equal "  해석 못 하는 답은 한 번 더 불러 보고 그래도 안 되면 error(agy 2번)" 2 @(Get-Content -LiteralPath $env:FAKE_ARGS_LOG | Where-Object { $_ -like "args=*" }).Count

# 첫 답만 계획서 같은 엉뚱한 글이고 두 번째는 번역이면 다시 불러서 해낸다
$env:FAKE_MODE = "garbage-once"
Remove-Item -LiteralPath $env:FAKE_ARGS_LOG -Force -ErrorAction SilentlyContinue
$out6 = Join-Path $work "ko\once.json"
& $trScript -ConversationId $convId2 -OutFile $out6 -TimeoutSeconds 60
$c6 = Read-TranslationCache $out6
Assert-Equal "첫 답이 엉뚱해도 한 번 더 불러서 done" "done|KO:Reading a.md" ("{0}|{1}" -f $c6.Status, $c6.Items["0"].label)
Assert-Equal "  agy 는 2번 불렀다" 2 @(Get-Content -LiteralPath $env:FAKE_ARGS_LOG | Where-Object { $_ -like "args=*" }).Count
Remove-Item -LiteralPath ($env:FAKE_ARGS_LOG + ".once") -Force -ErrorAction SilentlyContinue
$env:FAKE_MODE = $null

# agy 가 시간 안에 안 끝나면 error
$env:FAKE_MODE = "hang"
$out5 = Join-Path $work "ko\hang.json"
$sw = [Diagnostics.Stopwatch]::StartNew()
& $trScript -ConversationId $convId2 -OutFile $out5 -TimeoutSeconds 4
$c5 = Read-TranslationCache $out5
Assert-Equal "시간을 넘기면 error(타임아웃 4초, 20초 안에 끝남)" "error|True" ("{0}|{1}" -f $c5.Status, ($c5.Message -like "*넘겨*" -and $sw.Elapsed.TotalSeconds -lt 20))
$env:FAKE_MODE = $null

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
