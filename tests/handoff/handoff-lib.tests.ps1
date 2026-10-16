# handoff-lib.ps1(채널·원장·메시지 공용 함수) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\handoff\handoff-lib.tests.ps1
# 임시 채널 루트(AGENT_HANDOFF_ROOT)에서만 돌립니다. 실제 ~/.samjil/handoff 는 건드리지 않습니다. 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\handoff\scripts\handoff-lib.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("handoff-lib-test-" + [Guid]::NewGuid().ToString("N"))
$root = Join-Path $work "root"
New-Item -ItemType Directory -Force -Path $root | Out-Null
$savedRoot = $env:AGENT_HANDOFF_ROOT
$env:AGENT_HANDOFF_ROOT = $root

function New-Channel([string]$Name, [string]$IndexText = $null, [bool]$Bom = $false) {
    $dir = Join-Path $root $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $dir "msg") | Out-Null
    if ([string]::IsNullOrEmpty($IndexText)) {   # [string] 매개변수의 $null 기본값은 빈 문자열이 된다
        $IndexText = "# INDEX`n| 번호 | 시각 | 방향 | 제목 | 상태 |`n|---|---|---|---|---|`n| 0001 | 2026-10-10 09:00 | c2a | 채널 개통 | 처리됨 |`n| 0002 | 2026-10-10 09:05 | a2c | 개통 확인 | 보냄 |`n"
    }
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($IndexText)
    if ($Bom) { $bytes = [byte[]](@(0xEF, 0xBB, 0xBF) + $bytes) }
    [IO.File]::WriteAllBytes((Join-Path $dir "INDEX.md"), $bytes)
    return $dir
}
function Read-Raw([string]$Path) { return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) }

try {
    Write-Host "채널 루트 · 채널 찾기"
    Assert-Equal "AGENT_HANDOFF_ROOT 가 있으면 그 폴더가 루트" $root (Get-HandoffRootDir)
    $proj = New-Channel "my-app"
    Assert-Equal "이름으로 채널 폴더를 찾는다" $proj (Find-HandoffChannelDir "my-app")
    Assert-Equal "  없는 이름은 `$null" $true ($null -eq (Find-HandoffChannelDir "nope"))
    Assert-Equal "  경로 조작 문자(..)가 든 이름은 거절" $true ($null -eq (Find-HandoffChannelDir "..\x"))
    New-Item -ItemType Directory -Force -Path (Join-Path $root "templates"), (Join-Path $root "scripts") | Out-Null
    Assert-Equal "INDEX.md 가 있는 폴더만 채널로 센다 (templates/scripts 제외)" 1 @(Get-HandoffChannelDirs).Count
    $sub = Join-Path $work "code\my-app\src\deep"
    New-Item -ItemType Directory -Force -Path $sub | Out-Null
    Assert-Equal "cwd 의 폴더 이름이 채널 이름과 같으면 찾는다" $proj (Resolve-HandoffChannelForCwd (Join-Path $work "code\my-app"))
    Assert-Equal "  하위 폴더에서 열어도(세 단계 위까지) 찾는다" $proj (Resolve-HandoffChannelForCwd $sub)
    Assert-Equal "  관계 없는 폴더는 `$null" $true ($null -eq (Resolve-HandoffChannelForCwd (Join-Path $work "code")))
    Assert-Equal "  빈 cwd 는 `$null" $true ($null -eq (Resolve-HandoffChannelForCwd ""))

    Write-Host "작업 저장소 경로 (BRIEF.md)"
    $repo = Join-Path $work "repos\real-repo"
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    Set-Content -LiteralPath (Join-Path $proj "BRIEF.md") -Value ("- **저장소 경로**: ``" + $repo + "`` (브랜치: main)") -Encoding UTF8
    Assert-Equal "BRIEF.md 의 저장소 경로를 읽는다" $repo (Get-HandoffRepoPath $proj)
    Set-Content -LiteralPath (Join-Path $proj "BRIEF.md") -Value "- **저장소 경로**: ``<저장소 절대 경로>``" -Encoding UTF8
    Assert-Equal "  자리표시자는 경로로 치지 않는다" $true ($null -eq (Get-HandoffRepoPath $proj))
    Set-Content -LiteralPath (Join-Path $proj "BRIEF.md") -Value ("저장소 경로: ``" + (Join-Path $work "없는폴더") + "``") -Encoding UTF8
    Assert-Equal "  없는 폴더도 `$null" $true ($null -eq (Get-HandoffRepoPath $proj))

    Write-Host "세션 전용 채널 (BRIEF.md 의 세션 ID + 저장소 경로)"
    $sess = New-Channel "real-repo--feature-x"
    $sid = "44e5130e-ba9f-423c-b916-8da73d04a9b9"
    Set-Content -LiteralPath (Join-Path $sess "BRIEF.md") -Value ("- **저장소 경로**: ``" + $repo + "```n- **세션 ID**: ``" + $sid + "``") -Encoding UTF8
    Assert-Equal "BRIEF.md 의 세션 ID 를 읽는다" $sid (Get-HandoffBriefSessionId $sess)
    Set-Content -LiteralPath (Join-Path $sess "BRIEF.md") -Value "세션 ID: ``<세션 ID>``" -Encoding UTF8
    Assert-Equal "  자리표시자는 세션 ID 로 치지 않는다" "" (Get-HandoffBriefSessionId $sess)
    Assert-Equal "  BRIEF.md 가 없으면 빈 문자열" "" (Get-HandoffBriefSessionId (Join-Path $work "없는채널"))
    Set-Content -LiteralPath (Join-Path $sess "BRIEF.md") -Value ("- **저장소 경로**: ``" + $repo + "```n- **세션 ID**: ``" + $sid + "``") -Encoding UTF8
    $repoSub = Join-Path $repo "src\deep"
    New-Item -ItemType Directory -Force -Path $repoSub | Out-Null
    Assert-Equal "세션 ID 와 저장소 경로가 맞으면 폴더 이름이 달라도 찾는다" $sess (Resolve-HandoffChannelForCwd $repo $sid)
    Assert-Equal "  저장소 하위 폴더에서 열어도 찾는다" $sess (Resolve-HandoffChannelForCwd $repoSub $sid)
    Assert-Equal "  끝에 \ 가 붙은 cwd 도 찾는다" $sess (Resolve-HandoffChannelForCwd ($repo + "\") $sid)
    Assert-Equal "  다른 세션 ID 는 못 찾는다" $true ($null -eq (Resolve-HandoffChannelForCwd $repo "other-session"))
    Assert-Equal "  세션 ID 를 안 주면(옛 호출) 못 찾는다" $true ($null -eq (Resolve-HandoffChannelForCwd $repo))
    Assert-Equal "  저장소 경로 밖의 폴더는 못 찾는다" $true ($null -eq (Resolve-HandoffChannelForCwd (Join-Path $work "repos") $sid))
    Assert-Equal "  접두어만 같은 형제 폴더(real-repo2)는 못 찾는다" $true ($null -eq (Resolve-HandoffChannelForCwd ($repo + "2") $sid))
    $repoCase = $repo.ToUpperInvariant()
    Assert-Equal "  대소문자가 달라도 찾는다" $sess (Resolve-HandoffChannelForCwd $repoCase $sid)
    $other = New-Channel "other-session-chan"
    Set-Content -LiteralPath (Join-Path $other "BRIEF.md") -Value ("- **저장소 경로**: ``" + $repo + "``") -Encoding UTF8
    Assert-Equal "  세션 ID 줄이 없는 채널은 세션으로 찾지 않는다(같은 저장소여도)" $sess (Resolve-HandoffChannelForCwd $repo $sid)
    Assert-Equal "세션 ID 로 못 찾으면 이름 규칙으로 되돌아간다" $proj (Resolve-HandoffChannelForCwd (Join-Path $work "code\my-app") "other-session")
    Assert-Equal "  세션 ID 가 맞아도 저장소가 다르면 이름 규칙을 쓴다" $proj (Resolve-HandoffChannelForCwd (Join-Path $work "code\my-app") $sid)

    Write-Host "머리말 읽기 (Read-HandoffFrontMatter)"
    $fm = Join-Path $work "fm.md"
    [IO.File]::WriteAllText($fm, "---`n번호: `"0042`"`n방향: `"a2c`" # c2a 또는 a2c`n시각: 2026-10-16 10:12`n제목: [채널 개통] 제목: 콜론이 든 제목`n답장대상: 0041`n모델: Gemini 3.8 Flash`n자동: 예`n---`n`n본문: 이건 머리말이 아님`n", (New-Object Text.UTF8Encoding($false)))
    $h = Read-HandoffFrontMatter $fm
    Assert-Equal "따옴표를 벗긴다" "0042" $h["번호"]
    Assert-Equal "  줄 끝 주석을 뗀다" "a2c" $h["방향"]
    Assert-Equal "  제목 안의 콜론은 값의 일부" "[채널 개통] 제목: 콜론이 든 제목" $h["제목"]
    Assert-Equal "  답장대상·모델·자동" "0041|Gemini 3.8 Flash|예" ("{0}|{1}|{2}" -f $h["답장대상"], $h["모델"], $h["자동"])
    Assert-Equal "  본문의 '키: 값'은 읽지 않는다" $false $h.ContainsKey("본문")
    $fmBom = Join-Path $work "fm-bom.md"
    [IO.File]::WriteAllBytes($fmBom, [byte[]](@(0xEF, 0xBB, 0xBF) + (New-Object Text.UTF8Encoding($false)).GetBytes("---`n모델: claude-opus-4-5`n---`n")))
    Assert-Equal "  BOM 이 있어도 읽는다" "claude-opus-4-5" (Read-HandoffFrontMatter $fmBom)["모델"]
    $fmNone = Join-Path $work "fm-none.md"
    [IO.File]::WriteAllText($fmNone, "# 제목만 있는 옛 메시지`n본문`n", (New-Object Text.UTF8Encoding($false)))
    Assert-Equal "  머리말이 없으면 빈 해시테이블" 0 (Read-HandoffFrontMatter $fmNone).Count
    Assert-Equal "  파일이 없어도 빈 해시테이블" 0 (Read-HandoffFrontMatter (Join-Path $work "x.md")).Count

    Write-Host "원장 읽기"
    $r = ConvertFrom-HandoffIndexLine "| 0007 | 2026-10-10 09:05 | a2c | 제목 | 보냄 |"
    Assert-Equal "한 줄을 읽는다" "0007|2026-10-10 09:05|a2c|제목|보냄" ("{0}|{1}|{2}|{3}|{4}" -f $r.Num, $r.Time, $r.Dir, $r.Title, $r.Status)
    $r = ConvertFrom-HandoffIndexLine "| 0008 | 2026-10-10 09:05 | c2a | 가 | 나 | 읽음 |"
    Assert-Equal "  (제목)" "가|나" $r.Title
    Assert-Equal "  (상태)" "읽음" $r.Status
    Assert-Equal "  머리줄·구분줄·설명은 행이 아니다" $true (($null -eq (ConvertFrom-HandoffIndexLine "| 번호 | 시각 | 방향 | 제목 | 상태 |")) -and ($null -eq (ConvertFrom-HandoffIndexLine "|---|---|---|---|---|")) -and ($null -eq (ConvertFrom-HandoffIndexLine "# INDEX")))
    $rows = @(Read-HandoffIndex $proj)
    Assert-Equal "INDEX.md 의 행을 모두 읽는다" 2 $rows.Count
    Assert-Equal "  두 번째 행의 방향·상태" "a2c|보냄" ("{0}|{1}" -f $rows[1].Dir, $rows[1].Status)

    Write-Host "상태 칸만 고치기 (Set-HandoffStatus)"
    $before = Read-Raw (Join-Path $proj "INDEX.md")
    Assert-Equal "0002 를 읽음으로" $true (Set-HandoffStatus $proj "0002" "읽음")
    $after = Read-Raw (Join-Path $proj "INDEX.md")
    $bl = @($before -split "`n"); $al = @($after -split "`n")
    $diff = @(0..($bl.Count - 1) | Where-Object { $bl[$_] -ne $al[$_] })
    Assert-Equal "  바뀐 줄은 그 한 줄뿐" 1 $diff.Count
    Assert-Equal "  그 줄은 상태 칸만 바뀐다" "| 0002 | 2026-10-10 09:05 | a2c | 개통 확인 | 읽음 |" $al[$diff[0]]
    Assert-Equal "  같은 상태로 다시 바꾸면 `$false" $false (Set-HandoffStatus $proj "0002" "읽음")
    Assert-Equal "  없는 번호는 `$false" $false (Set-HandoffStatus $proj "0099" "읽음")
    Assert-Equal "  모르는 상태 낱말은 `$false" $false (Set-HandoffStatus $proj "0002" "끝남")
    $crlf = New-Channel "crlf-app" "# INDEX`r`n| 번호 | 시각 | 방향 | 제목 | 상태 |`r`n|---|---|---|---|---|`r`n| 0001 | 2026-10-10 09:00 | c2a | 개통 | 보냄 |`r`n" $true
    Assert-Equal "CRLF + BOM 원장도 고친다" $true (Set-HandoffStatus $crlf "0001" "처리됨")
    $bytes = [IO.File]::ReadAllBytes((Join-Path $crlf "INDEX.md"))
    $txt = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    Assert-Equal "  BOM 이 그대로 남는다" $true ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Assert-Equal "  줄바꿈은 CRLF 그대로, 끝의 줄바꿈도 유지" $true (($txt -notmatch "(?<!\r)\n") -and $txt.EndsWith("`r`n"))
    Assert-Equal "  상태가 바뀌었다" "처리됨" @(Read-HandoffIndex $crlf)[0].Status

    Write-Host "새 메시지 쓰기 (Add-HandoffMessage)"
    $num = Add-HandoffMessage $proj "a2c" "Re: 개통 확인" "## 요약`n`n- 확인했습니다`n`n---`n`n상세" "0002" "gemini-3.8-flash-high" $true
    Assert-Equal "다음 번호 0003 을 딴다" "0003" $num
    $file = Get-HandoffMessageFile $proj "0003"
    Assert-Equal "  파일 이름 모양(번호-방향-슬러그.md)" $true ($file.Name -match '^0003-a2c-[A-Za-z0-9가-힣_-]+\.md$')
    $h = Read-HandoffFrontMatter $file.FullName
    Assert-Equal "  머리말: 번호·방향·답장대상·모델·자동" "0003|a2c|0002|gemini-3.8-flash-high|예" ("{0}|{1}|{2}|{3}|{4}" -f $h["번호"], $h["방향"], $h["답장대상"], $h["모델"], $h["자동"])
    Assert-Equal "  제목" "Re: 개통 확인" $h["제목"]
    Assert-Equal "  본문이 머리말 다음에 온다" $true ((Read-Raw $file.FullName) -match "---\r?\n\r?\n## 요약")
    $rows = @(Read-HandoffIndex $proj)
    Assert-Equal "  원장에 한 줄이 붙고 상태는 보냄" "0003|a2c|보냄" ("{0}|{1}|{2}" -f $rows[-1].Num, $rows[-1].Dir, $rows[-1].Status)
    Assert-Equal "  새 줄은 마지막 행 바로 다음(빈 줄 없음)" $false ((Read-Raw (Join-Path $proj "INDEX.md")) -match "\n\s*\n\|")

    Set-Content -LiteralPath (Join-Path $proj "INDEX.md") -Value (((Read-Raw (Join-Path $proj "INDEX.md")).TrimEnd() + "`n`n`n")) -Encoding UTF8 -NoNewline
    $n2 = Add-HandoffMessage $proj "c2a" "끝에 빈 줄이 있던 원장" "## 요약`n- x"
    Assert-Equal "원장 끝에 빈 줄이 여럿 있어도 표가 끊기지 않는다" $false ((Read-Raw (Join-Path $proj "INDEX.md")) -match "\|\s*\r?\n\s*\r?\n\s*\|\s*0004")
    Assert-Equal "  번호는 0004" "0004" $n2

    Set-Content -LiteralPath (Join-Path $proj "msg\0005-c2a-someone-else.md") -Value "다른 쪽이 방금 쓴 파일" -Encoding UTF8
    $n3 = Add-HandoffMessage $proj "a2c" "충돌 피하기" "## 요약`n- y"
    Assert-Equal "원장에 없지만 msg 에 이미 있는 번호는 건너뛴다" "0006" $n3
    Assert-Equal "  남의 파일은 그대로" "다른 쪽이 방금 쓴 파일" (Read-Raw (Join-Path $proj "msg\0005-c2a-someone-else.md")).Trim()

    $n4 = Add-HandoffMessage $proj "a2c" "줄바꿈`n과 | 파이프" "## 요약`n- z"
    $row = @(Read-HandoffIndex $proj)[-1]
    Assert-Equal "제목의 줄바꿈과 | 는 공백으로 바꿔 원장을 깨지 않는다" "줄바꿈 과 파이프" $row.Title
    Assert-Equal "방향이 c2a/a2c 가 아니면 쓰지 않는다" $true ($null -eq (Add-HandoffMessage $proj "x2y" "t" "b"))
    $fresh = Join-Path $root "fresh"
    New-Item -ItemType Directory -Force -Path $fresh | Out-Null
    $nf = Add-HandoffMessage $fresh "c2a" "원장 없는 채널" "## 요약`n- a"
    Assert-Equal "INDEX.md 가 없으면 머리줄과 함께 새로 만든다" "0001" $nf
    Assert-Equal "  (표 머리줄이 있다)" $true ((Read-Raw (Join-Path $fresh "INDEX.md")) -match "\| 번호 \| 시각 \| 방향 \| 제목 \| 상태 \|")

    Write-Host "자동 이어가기 상태 (AUTO.json / AUTO.off)"
    $st = Read-HandoffAutoState $proj
    Assert-Equal "상태 파일이 없으면 빈 상태" "0|False" ("{0}|{1}" -f @($st.dispatches).Count, $st.halted)
    $now = Get-Date
    $st.dispatches = @(
        @{ num = "0002"; task_id = "t1"; at = $now.AddMinutes(-90).ToString("yyyy-MM-dd HH:mm:ss"); done = $true },
        @{ num = "0004"; task_id = "t2"; at = $now.AddMinutes(-10).ToString("yyyy-MM-dd HH:mm:ss"); done = $true },
        @{ num = "0006"; task_id = "t3"; at = $now.AddMinutes(-1).ToString("yyyy-MM-dd HH:mm:ss"); done = $false }
    )
    $st.halted = $true; $st.halted_at = "x"; $st.halted_reason = "한도"
    $st.hook_blocks["0003"] = 2
    Write-HandoffAutoState $proj $st
    $back = Read-HandoffAutoState $proj
    Assert-Equal "쓰고 다시 읽으면 같다 (위임 3건, halted, 사유)" "3|True|한도" ("{0}|{1}|{2}" -f @($back.dispatches).Count, $back.halted, $back.halted_reason)
    Assert-Equal "  훅이 막은 횟수" 2 $back.hook_blocks["0003"]
    Assert-Equal "  60분 창 안의 위임 수는 2 (90분 전 것은 뺀다)" 2 (Get-HandoffRounds $back 60)
    Assert-Equal "  창을 120분으로 하면 3" 3 (Get-HandoffRounds $back 120)
    Assert-Equal "  임시 파일(.tmp)이 남지 않는다" $false (Test-Path (Join-Path $proj "AUTO.json.tmp"))
    $one = @{ dispatches = @(@{ num = "0009"; task_id = "t9"; at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); done = $false }); halted = $false; halted_at = ""; halted_reason = ""; hook_blocks = @{} }
    Write-HandoffAutoState $proj $one
    Assert-Equal "위임이 한 건뿐이어도 배열로 읽는다(5.1 배열 풀림 방지)" 1 @((Read-HandoffAutoState $proj).dispatches).Count
    Set-Content -LiteralPath (Join-Path $proj "AUTO.json") -Value "{ 깨진 json" -Encoding UTF8
    Assert-Equal "깨진 AUTO.json 은 빈 상태로 읽는다" 0 @((Read-HandoffAutoState $proj).dispatches).Count
    Assert-Equal "AUTO.off 가 없으면 켜짐" $false (Test-HandoffAutoDisabled $proj)
    New-Item -ItemType File -Force -Path (Join-Path $proj "AUTO.off") | Out-Null
    Assert-Equal "채널의 AUTO.off 가 있으면 꺼짐" $true (Test-HandoffAutoDisabled $proj)
    Remove-Item (Join-Path $proj "AUTO.off") -Force
    New-Item -ItemType File -Force -Path (Join-Path $root "AUTO.off") | Out-Null
    Assert-Equal "루트의 AUTO.off 는 모든 채널을 끈다" $true (Test-HandoffAutoDisabled $proj)
    Remove-Item (Join-Path $root "AUTO.off") -Force
    Write-Host "뷰어용 요약 (Get-HandoffMessageMeta / Get-HandoffAutoSummary / Set-HandoffAutoAction)"
    $cache = @{}
    $metaFile = (Get-HandoffMessageFile $proj "0003").FullName
    $m1 = Get-HandoffMessageMeta $metaFile $cache
    Assert-Equal "머리말에서 모델·답장대상·자동을 읽는다" "gemini-3.8-flash-high|0002|True" ("{0}|{1}|{2}" -f $m1.model, $m1.replyTo, $m1.auto)
    $m2 = Get-HandoffMessageMeta $metaFile $cache
    Assert-Equal "  파일이 안 바뀌면 캐시를 쓴다(같은 객체)" $true ([object]::ReferenceEquals($m1, $m2))
    $oldMeta = Join-Path $work "old-msg.md"
    [IO.File]::WriteAllText($oldMeta, "# 옛 메시지 (머리말 없음)`n본문", (New-Object Text.UTF8Encoding($false)))
    $m3 = Get-HandoffMessageMeta $oldMeta $cache
    Assert-Equal "  머리말이 없는 옛 메시지는 모델 빈 값" "||False" ("{0}|{1}|{2}" -f $m3.model, $m3.replyTo, $m3.auto)
    Assert-Equal "  없는 파일도 빈 값(오류 없음)" "" (Get-HandoffMessageMeta (Join-Path $work "nope.md") $cache).model

    Remove-Item (Join-Path $proj "AUTO.json") -Force -ErrorAction SilentlyContinue
    $sum = Get-HandoffAutoSummary $proj
    Assert-Equal "요약: 기본은 켜짐, 멈춤 아님, 왕복 0/6, 60분 창" "True|False|0|6|60" ("{0}|{1}|{2}|{3}|{4}" -f $sum.enabled, $sum.halted, $sum.rounds, $sum.maxRounds, $sum.windowMinutes)
    Assert-Equal "  AUTO 끄기: off -> enabled False" "True|False" ("{0}|{1}" -f (Set-HandoffAutoAction $proj "off"), (Get-HandoffAutoSummary $proj).enabled)
    Assert-Equal "  AUTO 켜기: on -> enabled True" "True|True" ("{0}|{1}" -f (Set-HandoffAutoAction $proj "on"), (Get-HandoffAutoSummary $proj).enabled)
    $st = Read-HandoffAutoState $proj
    $st.dispatches = @(
        @{ num = "0010"; task_id = "tA"; at = (Get-Date).AddMinutes(-5).ToString("yyyy-MM-dd HH:mm:ss"); done = $true },
        @{ num = "0011"; task_id = "tB"; at = (Get-Date).AddMinutes(-1).ToString("yyyy-MM-dd HH:mm:ss"); done = $false })
    $st.halted = $true; $st.halted_reason = "한도"; $st.hook_blocks["0003"] = 1
    Write-HandoffAutoState $proj $st
    $sum = Get-HandoffAutoSummary $proj
    Assert-Equal "  멈춤·사유·왕복 수·진행 중 위임" "True|한도|2|1|0011" ("{0}|{1}|{2}|{3}|{4}" -f $sum.halted, $sum.haltedReason, $sum.rounds, @($sum.inFlight).Count, $sum.inFlight[0].num)
    Assert-Equal "  reset -> 멈춤 해제, 왕복 0, 진행 중 위임만 남음" "True|False|1|1" ("{0}|{1}|{2}|{3}" -f (Set-HandoffAutoAction $proj "reset"), (Get-HandoffAutoSummary $proj).halted, (Get-HandoffAutoSummary $proj).rounds, @((Get-HandoffAutoSummary $proj).inFlight).Count)
    Assert-Equal "  reset 은 훅이 막은 횟수도 비운다" 0 (Read-HandoffAutoState $proj).hook_blocks.Count
    Assert-Equal "  알 수 없는 동작은 false" $false (Set-HandoffAutoAction $proj "explode")

    Assert-Equal "왕복 한도 기본값 6" 6 (Get-HandoffMaxRounds)
    $env:AGY_HANDOFF_MAX_ROUNDS = "3"
    Assert-Equal "  환경변수로 바꿀 수 있다" 3 (Get-HandoffMaxRounds)
    Remove-Item Env:\AGY_HANDOFF_MAX_ROUNDS -ErrorAction SilentlyContinue

    $modelCh = Join-Path $root "model-ch"
    New-Item -ItemType Directory -Force -Path (Join-Path $modelCh "msg") | Out-Null
    Set-Content -LiteralPath (Join-Path $modelCh "INDEX.md") -Value "# INDEX`n| 번호 | 시각 | 방향 | 제목 | 상태 |`n|---|---|---|---|---|" -Encoding UTF8
    Write-Host "모델 자리표시자 · 모델 채워 넣기"
    $nS = Add-HandoffMessage $modelCh "a2c" "자리표시자 모델" "## 요약`n- s" "" "(session)"
    Assert-Equal "'(session)' 은 모델명이 아니라 머리말에 넣지 않는다" "" ([string](Read-HandoffFrontMatter (Get-HandoffMessageFile $modelCh $nS).FullName)["모델"])
    $nM = Add-HandoffMessage $modelCh "c2a" "모델 없이 보냄" "## 요약`n- m"
    $fM = (Get-HandoffMessageFile $modelCh $nM).FullName
    Assert-Equal "Set-HandoffMessageModel: 모델이 없으면 넣는다" $true (Set-HandoffMessageModel $fM "claude-opus-4-5-20251101")
    $hM = Read-HandoffFrontMatter $fM
    Assert-Equal "  머리말에 모델이 생기고 나머지는 그대로" "claude-opus-4-5-20251101|c2a|모델 없이 보냄" ("{0}|{1}|{2}" -f $hM["모델"], $hM["방향"], $hM["제목"])
    Assert-Equal "  본문은 그대로" $true ((Read-Raw $fM) -match "---\r?\n\r?\n## 요약\r?\n- m")
    Assert-Equal "  이미 있으면 덮어쓰지 않는다" $false (Set-HandoffMessageModel $fM "claude-sonnet-4-5")
    Assert-Equal "  그대로 claude-opus-4-5-20251101" "claude-opus-4-5-20251101" ([string](Read-HandoffFrontMatter $fM)["모델"])
    $fNo = Join-Path $modelCh "msg\9999-c2a-머리말-없음.md"
    Set-Content -LiteralPath $fNo -Value "본문만 있는 파일" -Encoding UTF8
    Assert-Equal "  머리말이 없는 파일은 건드리지 않는다" $false (Set-HandoffMessageModel $fNo "claude-opus-4-5")
    Remove-Item -LiteralPath $fNo -Force
}
finally {
    $env:AGENT_HANDOFF_ROOT = $savedRoot
    if (-not $savedRoot) { Remove-Item Env:\AGENT_HANDOFF_ROOT -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
