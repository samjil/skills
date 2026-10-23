# 핸드오프 펌프(handoff-pump.ps1) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\handoff\handoff-pump.tests.ps1
# 임시 채널 루트(AGENT_HANDOFF_ROOT)와 임시 위임 런타임(inbox/outbox/agy.db)만 씁니다. 실제 워처·agy·채널은 건드리지 않습니다. 몇 초 걸립니다.
# 가짜 agy 는 "outbox 에 응답 파일과 사용량 행(agy.db)을 직접 써 주는 것"으로 흉내 냅니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$subDir   = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub"
. (Join-Path $repoRoot "runtime\handoff\scripts\handoff-lib.ps1")
. (Join-Path $subDir "handoff-pump.ps1")
. (Join-Path $subDir "common.ps1")
. (Join-Path $subDir "agy-rules.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

# watch-agy.ps1 에서 지시어 해석 함수만 꺼내 온다(지시파일을 워처가 읽는 방식 그대로 확인하려고)
$tokens = $null; $errs = $null
$astWatch = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $subDir "watch-agy.ps1"), [ref]$tokens, [ref]$errs)
$fn = $astWatch.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq "ConvertFrom-TaskDirectives" }, $true)
Invoke-Expression $fn.Extent.Text

$work = Join-Path ([IO.Path]::GetTempPath()) ("handoff-pump-test-" + [Guid]::NewGuid().ToString("N"))
$root = Join-Path $work "root"
$rt = Join-Path $work "runtime"
foreach ($d in @($root, (Join-Path $rt "inbox"), (Join-Path $rt "outbox"), (Join-Path $rt "logs\sessions"))) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$savedRoot = $env:AGENT_HANDOFF_ROOT; $savedMax = $env:AGY_HANDOFF_MAX_ROUNDS; $savedAge = $env:AGY_HANDOFF_MAX_AGE_HOURS
$env:AGENT_HANDOFF_ROOT = $root
$env:AGY_HANDOFF_MAX_ROUNDS = "50"      # 아래 본 시험은 한도에 걸리지 않게 넉넉히 두고, 한도 시험은 따로 값을 바꿔서 본다
Remove-Item Env:\AGY_HANDOFF_MAX_AGE_HOURS -ErrorAction SilentlyContinue

$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
$ctx = @{ InboxDir = (Join-Path $rt "inbox"); OutboxDir = (Join-Path $rt "outbox"); DbPath = (Join-Path $rt "logs\agy.db") }
$script:LogLines = @()
function Log($m) { $script:LogLines += $m }

function Add-UsageRow([string]$TaskId, [string]$Model, [string]$Status) {
    [void](Write-QaRecordToDb $ctx.DbPath ([ordered]@{ timestamp = "2026-10-16 10:00:00"; computer_name = "PC"; task_id = $TaskId; model = $Model; attempts = 1; tried_models = $Model
        input_tokens = 10; output_tokens = 20; thinking_tokens = 5; total_tokens = 35; elapsed_sec = "12.3"; status = $Status; session = "handoff-my-app"; session_id = "conv1" }) 'InsertOnly')
}
# 가짜 agy 가 끝낸 것처럼: 응답 파일 + usage 행
function Finish-Task([string]$TaskId, [string]$Response, [string]$Model = "gemini-3.8-flash-high", [string]$Status = "OK") {
    [IO.File]::WriteAllText((Join-Path $ctx.OutboxDir "$TaskId.response.md"), $Response, (New-Object Text.UTF8Encoding($false)))
    Add-UsageRow $TaskId $Model $Status
}
function Get-InboxTasks { return @(Get-ChildItem -LiteralPath $ctx.InboxDir -Filter "handoff_*.md" -File -ErrorAction SilentlyContinue) }
function Get-Row([string]$Dir, [string]$Num) { return @(Read-HandoffIndex $Dir | Where-Object { $_.Num -eq $Num }) | Select-Object -First 1 }

try {
    $repo = Join-Path $work "repos\my-app"
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    $ch = Join-Path $root "my-app"
    New-Item -ItemType Directory -Force -Path (Join-Path $ch "msg") | Out-Null
    Set-Content -LiteralPath (Join-Path $ch "BRIEF.md") -Value ("- **저장소 경로**: ``" + $repo + "``") -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $ch "INDEX.md") -Value "# INDEX`n| 번호 | 시각 | 방향 | 제목 | 상태 |`n|---|---|---|---|---|" -Encoding UTF8

    Write-Host "새 c2a 메시지 -> agy 위임"
    $n1 = Add-HandoffMessage $ch "c2a" "로그인 버튼 색 고치기" "## 요약`n`n- 버튼이 회색으로 보입니다`n`n---`n`n본문 상세 내용 ABC"
    Invoke-HandoffPump $ctx
    $tasks = @(Get-InboxTasks)
    Assert-Equal "위임 지시파일이 inbox 에 한 개 생긴다" 1 $tasks.Count
    Assert-Equal "  파일 이름 모양 handoff_<채널>_<번호>_<시각>.md" $true ($tasks[0].Name -match '^handoff_my-app_0001_\d{6}\.md$')
    $text = [IO.File]::ReadAllText($tasks[0].FullName, [Text.Encoding]::UTF8)
    $dir = ConvertFrom-TaskDirectives $text
    Assert-Equal "  워처가 읽는 지시어: 세션 handoff-my-app" "handoff-my-app" $dir.Session
    Assert-Equal "  @raw: true(워처가 표준 규칙을 덧붙이지 않는다)" $true ([bool]$dir.Raw)
    Assert-Equal "  @cwd 두 곳(채널 폴더 + 저장소)" 2 @($dir.Cwd).Count
    Assert-Equal "  @cwd 에 채널 폴더와 저장소가 있다" $true ((@($dir.Cwd) -contains $ch) -and (@($dir.Cwd) -contains $repo))
    Assert-Equal "  본문에 메시지 전문과 번호·제목이 들어간다" $true (($dir.Prompt -match "본문 상세 내용 ABC") -and ($dir.Prompt -match "#0001") -and ($dir.Prompt -match "로그인 버튼 색 고치기"))
    Assert-Equal "  회신은 최종 답변으로 쓰고 파일을 만들지 말라고 안내한다" $true (($dir.Prompt -match "최종 답변") -and ($dir.Prompt -match "직접 만들거나 고치지"))
    Assert-Equal "  원장 상태는 읽음" "읽음" (Get-Row $ch "0001").Status
    $st = Read-HandoffAutoState $ch
    Assert-Equal "  AUTO.json 에 위임 1건(미완료)" "1|False" ("{0}|{1}" -f @($st.dispatches).Count, $st.dispatches[0].done)
    Invoke-HandoffPump $ctx
    Assert-Equal "다시 점검해도 중복 위임하지 않는다" 1 (Get-InboxTasks).Count

    Write-Host "agy 가 끝나면 a2c 회신을 기록한다"
    Invoke-HandoffPump $ctx
    Assert-Equal "끝나기 전에는 회신이 없다" 1 @(Read-HandoffIndex $ch).Count
    $taskId = $st.dispatches[0].task_id
    Finish-Task $taskId "## 요약`n`n- 색을 #0a84ff 로 고쳤습니다 (src/Login.css:12)`n`n---`n`n상세"
    Invoke-HandoffPump $ctx
    $rows = @(Read-HandoffIndex $ch)
    Assert-Equal "원장에 a2c 회신 한 줄이 붙는다 (0002, 보냄)" "2|0002|a2c|보냄" ("{0}|{1}|{2}|{3}" -f $rows.Count, $rows[1].Num, $rows[1].Dir, $rows[1].Status)
    Assert-Equal "  원래 메시지는 처리됨" "처리됨" (Get-Row $ch "0001").Status
    Assert-Equal "  회신 제목은 Re: + 원래 제목" "Re: 로그인 버튼 색 고치기" $rows[1].Title
    $h = Read-HandoffFrontMatter (Get-HandoffMessageFile $ch "0002").FullName
    Assert-Equal "  머리말: 답장대상 0001, 모델은 usage 행의 모델, 자동 예" "0001|gemini-3.8-flash-high|예" ("{0}|{1}|{2}" -f $h["답장대상"], $h["모델"], $h["자동"])
    Assert-Equal "  본문은 agy 의 최종 답변" $true ((Get-Content -Raw -LiteralPath (Get-HandoffMessageFile $ch "0002").FullName -Encoding UTF8) -match "#0a84ff")
    Assert-Equal "  위임은 완료로 표시된다" $true (Read-HandoffAutoState $ch).dispatches[0].done
    Invoke-HandoffPump $ctx
    Assert-Equal "  다시 점검해도 회신이 늘지 않는다" 2 @(Read-HandoffIndex $ch).Count
    Assert-Equal "  로그에 위임과 회신이 남는다" $true ((@($script:LogLines | Where-Object { $_ -match "위임" }).Count -ge 1) -and (@($script:LogLines | Where-Object { $_ -match "회신 #0002" }).Count -ge 1))

    Write-Host "Get-HandoffSessionModel: DB 의 세션 모델 (usage 행에 모델이 없을 때의 대비)"
    $dbS = Open-AgyDb $ctx.DbPath
    Invoke-AgyDbTransaction $dbS { Set-AgySessionRow $dbS "handoff-my-app" "conv1" @() "gemini-3.8-flash-low" "2026-10-16 09:00:00" "2026-10-16 09:00:00" 1 }
    Invoke-AgyDbTransaction $dbS { Set-AgySessionRow $dbS "handoff-other" "conv2" @() "(session)" "2026-10-16 09:00:00" "2026-10-16 09:00:00" 1 }
    $dbS.Dispose()
    Assert-Equal "세션에 저장된 모델을 돌려준다" "gemini-3.8-flash-low" (Get-HandoffSessionModel $ctx.DbPath "handoff-my-app")
    Assert-Equal "  자리표시자 (session) 는 모델로 쓰지 않는다" "" (Get-HandoffSessionModel $ctx.DbPath "handoff-other")
    Assert-Equal "  없는 세션은 빈 글자" "" (Get-HandoffSessionModel $ctx.DbPath "handoff-nothing")
    Write-Host "답변 모양 정리 (ConvertTo-HandoffReplyBody)"
    Assert-Equal "요약 블록이 없으면 안내 요약을 붙인다" $true ((ConvertTo-HandoffReplyBody "그냥 한 줄 답") -match "(?s)^## 요약.*그냥 한 줄 답")
    Assert-Equal "agy 가 붙인 머리말(---)은 뗀다" $false ((ConvertTo-HandoffReplyBody "---`n번호: 9`n---`n## 요약`n- a") -match "번호: 9")
    Assert-Equal "  요약이 이미 있으면 그대로" "## 요약`n- a" (ConvertTo-HandoffReplyBody "## 요약`n- a")
    Assert-Equal "빈 답변도 회신으로 쓸 수 있는 글이 된다" $true ((ConvertTo-HandoffReplyBody "   ") -match "빈 답변")

    Write-Host "실패하면 보류 + 알림 회신"
    $n3 = Add-HandoffMessage $ch "c2a" "두 번째 요청" "## 요약`n- 두 번째"
    Invoke-HandoffPump $ctx
    $t2 = (Read-HandoffAutoState $ch).dispatches | Where-Object { [string]$_.num -eq $n3 } | Select-Object -First 1
    Finish-Task $t2.task_id "agy 실행 실패 (시도한 모델: gemini-3.8-flash-high) - 한도 초과" "" "ERROR"
    Invoke-HandoffPump $ctx
    Assert-Equal "원래 메시지는 보류" "보류" (Get-Row $ch $n3).Status
    $fail = @(Read-HandoffIndex $ch)[-1]
    Assert-Equal "  알림 회신(a2c, 보냄, 제목에 자동 처리 실패)" $true (($fail.Dir -eq "a2c") -and ($fail.Status -eq "보냄") -and ($fail.Title -match "^자동 처리 실패"))
    Assert-Equal "  알림 본문에 실패 사유가 있다" $true ((Get-Content -Raw -LiteralPath (Get-HandoffMessageFile $ch $fail.Num).FullName -Encoding UTF8) -match "한도 초과")

    Write-Host "쌓여 있던 옛 메시지 · 끄기 표시"
    $n5 = Add-HandoffMessage $ch "c2a" "옛 요청" "## 요약`n- 옛날"
    $idxPath = Join-Path $ch "INDEX.md"
    $old = (Get-Date).AddHours(-3).ToString("yyyy-MM-dd HH:mm")
    $txt = Get-Content -Raw -LiteralPath $idxPath -Encoding UTF8
    Set-Content -LiteralPath $idxPath -Value ([regex]::Replace($txt, "(\| $n5 \| )[0-9: -]+( \|)", "`${1}$old`${2}")) -Encoding UTF8 -NoNewline
    $before = (Get-InboxTasks).Count
    Invoke-HandoffPump $ctx
    Assert-Equal "2시간보다 오래된 보냄 메시지는 위임하지 않는다" $before (Get-InboxTasks).Count
    Assert-Equal "  상태도 그대로(보냄)" "보냄" (Get-Row $ch $n5).Status
    $n6 = Add-HandoffMessage $ch "c2a" "끄기 확인" "## 요약`n- x"
    New-Item -ItemType File -Force -Path (Join-Path $ch "AUTO.off") | Out-Null
    Invoke-HandoffPump $ctx
    Assert-Equal "채널의 AUTO.off 가 있으면 위임하지 않는다" $before (Get-InboxTasks).Count
    Remove-Item (Join-Path $ch "AUTO.off") -Force
    New-Item -ItemType File -Force -Path (Join-Path $root "AUTO.off") | Out-Null
    Invoke-HandoffPump $ctx
    Assert-Equal "  루트의 AUTO.off 도 마찬가지" $before (Get-InboxTasks).Count
    Remove-Item (Join-Path $root "AUTO.off") -Force
    Invoke-HandoffPump $ctx
    Assert-Equal "  끄기를 풀면 바로 위임한다" ($before + 1) (Get-InboxTasks).Count
    $t6 = (Read-HandoffAutoState $ch).dispatches | Where-Object { [string]$_.num -eq $n6 } | Select-Object -First 1
    Finish-Task $t6.task_id "## 요약`n- ok"
    Invoke-HandoffPump $ctx

    Write-Host "한 번에 하나씩"
    $a = Add-HandoffMessage $ch "c2a" "동시 A" "## 요약`n- a"
    $b = Add-HandoffMessage $ch "c2a" "동시 B" "## 요약`n- b"
    $before = (Get-InboxTasks).Count
    Invoke-HandoffPump $ctx
    Assert-Equal "보냄 메시지가 둘이어도 한 채널에서는 하나만 위임한다" ($before + 1) (Get-InboxTasks).Count
    Assert-Equal "  나머지는 보냄으로 남는다" "보냄" (Get-Row $ch $b).Status
    $ta = (Read-HandoffAutoState $ch).dispatches | Where-Object { [string]$_.num -eq $a } | Select-Object -First 1
    Finish-Task $ta.task_id "## 요약`n- a 끝"
    Invoke-HandoffPump $ctx
    Assert-Equal "  첫 위임이 끝나면 다음 것을 위임한다" ($before + 2) (Get-InboxTasks).Count
    $tb = (Read-HandoffAutoState $ch).dispatches | Where-Object { [string]$_.num -eq $b } | Select-Object -First 1
    Finish-Task $tb.task_id "## 요약`n- b 끝"
    Invoke-HandoffPump $ctx

    Write-Host "agy 가 규약대로 직접 회신을 쓴 경우"
    $c = Add-HandoffMessage $ch "c2a" "직접 회신 확인" "## 요약`n- c"
    Invoke-HandoffPump $ctx
    $tc = (Read-HandoffAutoState $ch).dispatches | Where-Object { [string]$_.num -eq $c } | Select-Object -First 1
    $own = Add-HandoffMessage $ch "a2c" "agy 가 직접 쓴 회신" "## 요약`n- 직접" $c "gemini-x"
    $countBefore = @(Read-HandoffIndex $ch).Count
    Finish-Task $tc.task_id "## 요약`n- 최종 답변"
    Invoke-HandoffPump $ctx
    Assert-Equal "중복 회신을 쓰지 않는다" $countBefore @(Read-HandoffIndex $ch).Count
    Assert-Equal "  원래 메시지는 처리됨" "처리됨" (Get-Row $ch $c).Status

    Write-Host "usage 행이 늦게 쓰이는 경우(응답 파일이 먼저)"
    $d = Add-HandoffMessage $ch "c2a" "응답이 먼저" "## 요약`n- d"
    Invoke-HandoffPump $ctx
    $td = (Read-HandoffAutoState $ch).dispatches | Where-Object { [string]$_.num -eq $d } | Select-Object -First 1
    $respFile = Join-Path $ctx.OutboxDir "$($td.task_id).response.md"
    [IO.File]::WriteAllText($respFile, "## 요약`n- d 끝", (New-Object Text.UTF8Encoding($false)))
    $countBefore = @(Read-HandoffIndex $ch).Count
    Invoke-HandoffPump $ctx
    Assert-Equal "usage 행이 없고 응답이 방금 생겼으면 잠깐 기다린다" $countBefore @(Read-HandoffIndex $ch).Count
    (Get-Item $respFile).LastWriteTime = (Get-Date).AddMinutes(-2)
    Invoke-HandoffPump $ctx
    Assert-Equal "  60초가 지나면 usage 행 없이도 회신한다" ($countBefore + 1) @(Read-HandoffIndex $ch).Count

    Write-Host "3시간이 지나도 답이 없는 위임"
    $e = Add-HandoffMessage $ch "c2a" "답 없는 요청" "## 요약`n- e"
    Invoke-HandoffPump $ctx
    $script:__old3 = (Get-Date).AddHours(-4).ToString("yyyy-MM-dd HH:mm:ss")
    Update-HandoffAutoState $ch { param($s) foreach ($x in @($s.dispatches)) { if (-not $x.done) { $x.at = $script:__old3 } } }
    Invoke-HandoffPump $ctx
    Assert-Equal "포기하고 보류 + 알림 회신" "보류" (Get-Row $ch $e).Status
    Assert-Equal "  알림 사유에 3시간" $true ((Get-Content -Raw -LiteralPath (Get-HandoffMessageFile $ch @(Read-HandoffIndex $ch)[-1].Num).FullName -Encoding UTF8) -match "3시간")

    Write-Host "저장소 경로를 모르는 채널"
    $ch2 = Join-Path $root "no-repo"
    New-Item -ItemType Directory -Force -Path (Join-Path $ch2 "msg") | Out-Null
    Set-Content -LiteralPath (Join-Path $ch2 "INDEX.md") -Value "# INDEX`n| 번호 | 시각 | 방향 | 제목 | 상태 |`n|---|---|---|---|---|" -Encoding UTF8
    [void](Add-HandoffMessage $ch2 "c2a" "저장소 없는 채널" "## 요약`n- f")
    $before = (Get-InboxTasks).Count
    Invoke-HandoffPump $ctx
    $newTask = @(Get-InboxTasks | Sort-Object LastWriteTime | Select-Object -Last 1)[0]
    $dir2 = ConvertFrom-TaskDirectives ([IO.File]::ReadAllText($newTask.FullName, [Text.Encoding]::UTF8))
    Assert-Equal "채널 폴더만 @cwd 로 연다" 1 @($dir2.Cwd).Count
    Assert-Equal "  본문에 저장소를 모른다는 안내가 있다" $true ($dir2.Prompt -match "저장소 경로를 알 수 없습니다")
    Assert-Equal "  로그에 알려 준다" $true (@($script:LogLines | Where-Object { $_ -match "저장소 경로를 몰라" }).Count -ge 1)
}
finally {
    # 아래 시험은 별도 채널로 한도를 본다
}

try {
    Write-Host "왕복 한도"
    $env:AGY_HANDOFF_MAX_ROUNDS = "2"
    $ch3 = Join-Path $root "limit-app"
    New-Item -ItemType Directory -Force -Path (Join-Path $ch3 "msg") | Out-Null
    Set-Content -LiteralPath (Join-Path $ch3 "INDEX.md") -Value "# INDEX`n| 번호 | 시각 | 방향 | 제목 | 상태 |`n|---|---|---|---|---|" -Encoding UTF8
    for ($i = 1; $i -le 2; $i++) {
        $nn = Add-HandoffMessage $ch3 "c2a" "왕복 $i" "## 요약`n- r$i"
        Invoke-HandoffPump $ctx
        $dd = (Read-HandoffAutoState $ch3).dispatches | Where-Object { [string]$_.num -eq $nn } | Select-Object -First 1
        Finish-Task $dd.task_id "## 요약`n- 답 $i"
        Invoke-HandoffPump $ctx
    }
    $before = (Get-InboxTasks).Count
    $third = Add-HandoffMessage $ch3 "c2a" "왕복 3 (한도 초과)" "## 요약`n- r3"
    Invoke-HandoffPump $ctx
    $st = Read-HandoffAutoState $ch3
    Assert-Equal "한도(2회/60분)에 닿으면 멈춘다 (halted)" $true $st.halted
    Assert-Equal "  사유에 한도와 사용자 확인이 적힌다" $true (($st.halted_reason -match "한도") -and ($st.halted_reason -match "사용자 확인"))
    Assert-Equal "  위임 지시파일은 만들지 않는다" $before (Get-InboxTasks).Count
    Assert-Equal "  메시지는 보냄 상태로 남는다" "보냄" (Get-Row $ch3 $third).Status
    Invoke-HandoffPump $ctx
    Assert-Equal "  멈춘 채로는 계속 위임하지 않는다" $before (Get-InboxTasks).Count
    Update-HandoffAutoState $ch3 { param($s) $s.halted = $false; $s.halted_at = ""; $s.halted_reason = ""; $s.dispatches = @() }
    Invoke-HandoffPump $ctx
    Assert-Equal "  사용자가 초기화(halted 해제 + 위임 기록 비움)하면 다시 위임한다" ($before + 1) (Get-InboxTasks).Count
    Remove-Item Env:\AGY_HANDOFF_MAX_ROUNDS -ErrorAction SilentlyContinue

    Write-Host "한도 창이 지나면 자동으로 다시 시작"
    $env:AGY_HANDOFF_MAX_ROUNDS = "1"
    $ch4 = Join-Path $root "window-app"
    New-Item -ItemType Directory -Force -Path (Join-Path $ch4 "msg") | Out-Null
    Set-Content -LiteralPath (Join-Path $ch4 "INDEX.md") -Value "# INDEX`n| 번호 | 시각 | 방향 | 제목 | 상태 |`n|---|---|---|---|---|" -Encoding UTF8
    $stOld = Read-HandoffAutoState $ch4
    $stOld.dispatches = @(@{ num = "0000"; task_id = "old"; at = (Get-Date).AddMinutes(-90).ToString("yyyy-MM-dd HH:mm:ss"); done = $true })
    $stOld.halted = $true; $stOld.halted_at = (Get-Date).AddMinutes(-80).ToString("yyyy-MM-dd HH:mm:ss"); $stOld.halted_reason = "한도"
    Write-HandoffAutoState $ch4 $stOld
    $before = (Get-InboxTasks).Count
    [void](Add-HandoffMessage $ch4 "c2a" "창이 지난 뒤" "## 요약`n- w")
    Invoke-HandoffPump $ctx
    Assert-Equal "60분 창 밖의 위임만 남았으면 halted 가 풀리고 위임한다" ($before + 1) (Get-InboxTasks).Count
    Assert-Equal "  halted 는 false" $false (Read-HandoffAutoState $ch4).halted
    Remove-Item Env:\AGY_HANDOFF_MAX_ROUNDS -ErrorAction SilentlyContinue

    Write-Host "워처 연결 (정적 확인)"
    $watchText = [IO.File]::ReadAllText((Join-Path $subDir "watch-agy.ps1"), [Text.Encoding]::UTF8)
    Assert-Equal "메인 루프가 Invoke-HandoffPump 을 5초 간격으로 부른다" $true (($watchText -match "Invoke-HandoffPump @\{") -and ($watchText -match "TotalSeconds -ge 5"))
    Assert-Equal "  작업자 모드에서는 라이브러리를 불러오지 않는다" $true ($watchText -match 'if \(-not \$WorkerTask\) \{\s*\r?\n\s*try \{\s*\r?\n\s*\$handoffLib')
    Assert-Equal "  펌프가 준비되지 않았으면(HandoffPumpReady) 부르지 않는다" $true ($watchText -match 'if \(\$script:HandoffPumpReady -and -not \$script:Stopping')
}
finally {
    $env:AGENT_HANDOFF_ROOT = $savedRoot
    if (-not $savedRoot) { Remove-Item Env:\AGENT_HANDOFF_ROOT -ErrorAction SilentlyContinue }
    if ($savedMax) { $env:AGY_HANDOFF_MAX_ROUNDS = $savedMax } else { Remove-Item Env:\AGY_HANDOFF_MAX_ROUNDS -ErrorAction SilentlyContinue }
    if ($savedAge) { $env:AGY_HANDOFF_MAX_AGE_HOURS = $savedAge } else { Remove-Item Env:\AGY_HANDOFF_MAX_AGE_HOURS -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
