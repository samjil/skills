# Claude Stop 훅(handoff-stop-hook.ps1)과 설정 등록기(register-handoff-hook.ps1) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\handoff\handoff-stop-hook.tests.ps1
# 훅은 실제로 새 PowerShell 프로세스로 띄워 stdin 에 훅 입력(JSON)을 넣고 stdout/종료 코드를 읽습니다. 임시 채널 루트·임시 settings.json 만 씁니다.
# 기다리는 시험은 훅의 대기 시간을 몇 초로 줄여서 봅니다. 약 40초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$scriptsDir = Join-Path $repoRoot "runtime\handoff\scripts"
. (Join-Path $scriptsDir "handoff-lib.ps1")
$hookScript = Join-Path $scriptsDir "handoff-stop-hook.ps1"
$registerScript = Join-Path $scriptsDir "register-handoff-hook.ps1"
$psExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName    # 지금 이 시험을 돌리는 PowerShell 과 같은 것

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("handoff-hook-test-" + [Guid]::NewGuid().ToString("N"))
$root = Join-Path $work "root"
$rt = Join-Path $work "runtime"
New-Item -ItemType Directory -Force -Path $root, (Join-Path $rt "logs\heartbeat") | Out-Null
$savedRoot = $env:AGENT_HANDOFF_ROOT
$env:AGENT_HANDOFF_ROOT = $root

function Start-PsProcess([string]$File, [string[]]$ArgList, [string]$StdinText, [hashtable]$Env) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $args_ = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + $File + '"')) + $ArgList
    $psi.Arguments = ($args_ -join " ")
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = [string]$Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($StdinText)
    $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $p.StandardInput.Close()
    return $p
}
function Wait-PsProcess($p) {
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    [void]$p.WaitForExit()
    if ($err.Trim() -and $env:HANDOFF_TEST_SHOW_STDERR) { Write-Host ("  [stderr] " + $err.Trim()) -ForegroundColor DarkGray }
    return @{ Out = $out; Exit = $p.ExitCode; Err = $err }
}
$baseEnv = @{ SAMJIL_HANDOFF_DEBUG = "1"; AGENT_HANDOFF_ROOT = $root; AGY_DELEGATE_RUNTIME = $rt; SAMJIL_HANDOFF_WAIT_SECONDS = "4"; SAMJIL_HANDOFF_POLL_SECONDS = "1" }
function Merge-Env([hashtable]$Extra) { $e = $baseEnv.Clone(); foreach ($k in $Extra.Keys) { $e[$k] = $Extra[$k] }; return $e }
function Invoke-Hook([string]$Cwd, [hashtable]$ExtraEnv = @{}, [string]$Stdin = $null) {
    $e = Merge-Env $ExtraEnv
    if ([string]::IsNullOrEmpty($Stdin)) { $Stdin = (@{ cwd = $Cwd; session_id = "s1"; hook_event_name = "Stop"; stop_hook_active = $false } | ConvertTo-Json -Compress) }
    return (Wait-PsProcess (Start-PsProcess $hookScript @() $Stdin $e))
}
function Touch-Heartbeat { Set-Content -LiteralPath (Join-Path $rt "logs\heartbeat\hb_TESTPC.txt") -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Encoding UTF8 }
function New-Channel([string]$Name) {
    $dir = Join-Path $root $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $dir "msg") | Out-Null
    Set-Content -LiteralPath (Join-Path $dir "INDEX.md") -Value "# INDEX`n| 번호 | 시각 | 방향 | 제목 | 상태 |`n|---|---|---|---|---|" -Encoding UTF8
    return $dir
}
function Set-RowTime([string]$Dir, [string]$Num, [datetime]$When) {
    $p = Join-Path $Dir "INDEX.md"
    $t = Get-Content -Raw -LiteralPath $p -Encoding UTF8
    Set-Content -LiteralPath $p -Value ([regex]::Replace($t, "(\| $Num \| )[0-9: -]+( \|)", "`${1}$($When.ToString('yyyy-MM-dd HH:mm'))`${2}")) -Encoding UTF8 -NoNewline
}

try {
    $code = Join-Path $work "code"
    $app = New-Channel "my-app"
    $appCwd = Join-Path $code "my-app"
    New-Item -ItemType Directory -Force -Path $appCwd | Out-Null

    Write-Host "아무 일도 하지 않는 경우"
    $r = Invoke-Hook (Join-Path $code "other-project")
    Assert-Equal "채널이 없는 폴더에서는 출력 없이 끝난다" "0||" ("{0}|{1}|{2}" -f $r.Exit, $r.Out.Trim(), "")
    $r = Invoke-Hook $appCwd
    Assert-Equal "채널은 있지만 메시지가 없으면 출력 없이 끝난다" "0|" ("{0}|{1}" -f $r.Exit, $r.Out.Trim())
    $r = Invoke-Hook $appCwd @{} "이건 JSON 이 아님"
    Assert-Equal "입력이 JSON 이 아니어도 조용히 끝난다(종료 코드 0)" "0|" ("{0}|{1}" -f $r.Exit, $r.Out.Trim())

    Write-Host "agy 회신이 이미 와 있는 경우 -> 이어가기(block)"
    $n1 = Add-HandoffMessage $app "a2c" "로그인 색 수정 완료" "## 요약`n- 고쳤습니다" "0000" "gemini-3.8-flash-high"
    $r = Invoke-Hook $appCwd
    $json = $r.Out | ConvertFrom-Json
    Assert-Equal "decision 은 block" "block" $json.decision
    Assert-Equal "  사유에 번호·제목·메시지 파일 경로가 있다" $true (($json.reason -match "#$n1") -and ($json.reason -match "로그인 색 수정 완료") -and ($json.reason -match "0001-a2c"))
    Assert-Equal "  사유에 처리 규칙(읽음→처리됨, c2a 회신, 사용자 확인 필요)이 있다" $true (($json.reason -match "'읽음'") -and ($json.reason -match "처리됨") -and ($json.reason -match "사용자 확인 필요"))
    Assert-Equal "  '메시지 확인해줘'를 말할 필요 없다고 알린다" $true ($json.reason -match "말하지 않아도")
    Assert-Equal "  출력에 BOM 이 없다" $false (($r.Out.Length -gt 0) -and ($r.Out[0] -eq [char]0xFEFF))
    Assert-Equal "  사유의 줄바꿈이 LF 로 통일돼 있다(CR 없음)" $false $json.reason.Contains("`r")
    Assert-Equal "  막은 횟수가 AUTO.json 에 1로 남는다" 1 (Read-HandoffAutoState $app).hook_blocks[$n1]
    $r = Invoke-Hook $appCwd
    Assert-Equal "같은 회신은 두 번째도 막는다" "block" ($r.Out | ConvertFrom-Json).decision
    $r = Invoke-Hook $appCwd
    Assert-Equal "  세 번째는 막지 않고 넘어간다(같은 회신당 최대 2번)" "0|" ("{0}|{1}" -f $r.Exit, $r.Out.Trim())
    Set-HandoffStatus $app $n1 "처리됨" | Out-Null
    Update-HandoffAutoState $app { param($s) $s.hook_blocks = @{} }

    Write-Host "세션 전용 채널(폴더 이름이 저장소와 다름) -> 세션 ID + 저장소 경로로 찾는다"
    $sessRepo = Join-Path $work "repos\sess-repo"
    New-Item -ItemType Directory -Force -Path $sessRepo | Out-Null
    $sessCh = New-Channel "sess-repo--hook-test"
    $sessId = "11111111-2222-3333-4444-555555555555"
    Set-Content -LiteralPath (Join-Path $sessCh "BRIEF.md") -Value ("- **저장소 경로**: ``" + $sessRepo + "```n- **세션 ID**: ``" + $sessId + "``") -Encoding UTF8
    $sn = Add-HandoffMessage $sessCh "a2c" "세션 채널 회신" "## 요약`n- 왔습니다" "0000" "gemini-3.8-flash-high"
    $sessStdin = { param($sid) (@{ cwd = $sessRepo; session_id = $sid; hook_event_name = "Stop"; stop_hook_active = $false } | ConvertTo-Json -Compress) }
    $r = Invoke-Hook $sessRepo @{} (& $sessStdin $sessId)
    $json = $r.Out | ConvertFrom-Json
    Assert-Equal "세션 ID 가 맞으면 폴더 이름이 달라도 회신을 이어 간다(block)" "block" $json.decision
    Assert-Equal "  사유에 세션 채널의 회신 번호·제목이 있다" $true (($json.reason -match "#$sn") -and ($json.reason -match "세션 채널 회신"))
    $r = Invoke-Hook $sessRepo @{} (& $sessStdin "다른-세션")
    Assert-Equal "다른 세션에서는 그 채널을 건드리지 않는다(출력 없음)" "0|" ("{0}|{1}" -f $r.Exit, $r.Out.Trim())
    Set-HandoffStatus $sessCh $sn "처리됨" | Out-Null

    Write-Host "세션을 이어서 다시 열어 ID 가 바뀐 경우 -> BRIEF 에 적힌 두 번째 ID 로 찾는다"
    $resumedId = "99999999-8888-7777-6666-555555555555"
    $sn2 = Add-HandoffMessage $sessCh "a2c" "이어 연 세션의 회신" "## 요약`n- 왔습니다" "0000" "gemini-3.8-flash-high"
    $r = Invoke-Hook $sessRepo @{} (& $sessStdin $resumedId)
    Assert-Equal "읽지 않은 회신이 있어도 BRIEF 에 없는 새 ID 는 채널을 못 찾고 조용히 끝난다" "0|" ("{0}|{1}" -f $r.Exit, $r.Out.Trim())
    Set-Content -LiteralPath (Join-Path $sessCh "BRIEF.md") -Value ("- **저장소 경로**: ``" + $sessRepo + "```n- **세션 ID**: ``" + $sessId + "``, ``" + $resumedId + "``") -Encoding UTF8
    $r = Invoke-Hook $sessRepo @{} (& $sessStdin $resumedId)
    Assert-Equal "두 번째 ID 로 연 세션도 회신을 이어 간다(block)" "block" ($r.Out | ConvertFrom-Json).decision
    $r = Invoke-Hook $sessRepo @{} (& $sessStdin $sessId)
    Assert-Equal "  첫 번째 ID 도 그대로 이어 간다" "block" ($r.Out | ConvertFrom-Json).decision
    Set-HandoffStatus $sessCh $sn2 "처리됨" | Out-Null

    Write-Host "오래된 회신 · 끄기 표시"
    $n2 = Add-HandoffMessage $app "a2c" "오래된 회신" "## 요약`n- old"
    Set-RowTime $app $n2 (Get-Date).AddHours(-8)
    $r = Invoke-Hook $appCwd
    Assert-Equal "6시간보다 오래된 읽지 않은 회신은 막지 않는다" "0|" ("{0}|{1}" -f $r.Exit, $r.Out.Trim())
    $n3 = Add-HandoffMessage $app "a2c" "끄기 확인" "## 요약`n- x"
    New-Item -ItemType File -Force -Path (Join-Path $app "AUTO.off") | Out-Null
    $r = Invoke-Hook $appCwd
    Assert-Equal "AUTO.off 가 있으면 아무 일도 하지 않는다" "0|" ("{0}|{1}" -f $r.Exit, $r.Out.Trim())
    Remove-Item (Join-Path $app "AUTO.off") -Force
    Set-HandoffStatus $app $n2 "확인함" | Out-Null; Set-HandoffStatus $app $n3 "확인함" | Out-Null

    Write-Host "방금 보낸 메시지의 회신을 기다리기"
    Touch-Heartbeat
    $c1 = Add-HandoffMessage $app "c2a" "agy 에게 부탁" "## 요약`n- 부탁"
    $p = Start-PsProcess $hookScript @() (@{ cwd = $appCwd } | ConvertTo-Json -Compress) (Merge-Env @{ SAMJIL_HANDOFF_WAIT_SECONDS = "30" })
    Start-Sleep -Seconds 3
    Assert-Equal "회신이 오기 전에는 훅이 끝나지 않고 기다린다" $false $p.HasExited
    $reply = Add-HandoffMessage $app "a2c" "Re: agy 에게 부탁" "## 요약`n- 했습니다" $c1 "gemini-3.8-flash-high" $true
    $res = Wait-PsProcess $p
    $json = $res.Out | ConvertFrom-Json
    Assert-Equal "회신이 오면 block 으로 이어 간다" "block" $json.decision
    Assert-Equal "  새 회신 번호가 사유에 있다" $true ($json.reason -match "#$reply")
    Set-HandoffStatus $app $c1 "처리됨" | Out-Null; Set-HandoffStatus $app $reply "처리됨" | Out-Null
    Update-HandoffAutoState $app { param($s) $s.hook_blocks = @{} }

    $c2 = Add-HandoffMessage $app "c2a" "답이 안 오는 부탁" "## 요약`n- 부탁2"
    $t0 = Get-Date
    $r = Invoke-Hook $appCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "3" }
    $sec = ((Get-Date) - $t0).TotalSeconds
    $json = $r.Out | ConvertFrom-Json
    Assert-Equal "기다려도 회신이 없으면 systemMessage 로 알리고 끝낸다(block 아님)" $true (($null -eq $json.decision) -and ($json.systemMessage -match "기다리기를 멈춥니다"))
    Assert-Equal "  대기 시간만큼만 기다렸다" $true ($sec -ge 3 -and $sec -lt 25)

    Write-Host "기다리지 않는 경우"
    Remove-Item (Join-Path $rt "logs\heartbeat\hb_TESTPC.txt") -Force
    $t0 = Get-Date
    $r = Invoke-Hook $appCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "30" }
    Assert-Equal "워처 하트비트가 없으면 바로 끝내며 알린다" $true (((($r.Out | ConvertFrom-Json).systemMessage) -match "워처가 꺼져") -and (((Get-Date) - $t0).TotalSeconds -lt 20))
    Touch-Heartbeat
    Update-HandoffAutoState $app { param($s) $s.halted = $true; $s.halted_reason = "자동 왕복 한도에 도달했습니다." }
    $r = Invoke-Hook $appCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "30" }
    Assert-Equal "왕복 한도로 멈춘 채널은 바로 끝내며 사유를 알린다" $true (($r.Out | ConvertFrom-Json).systemMessage -match "한도")
    Update-HandoffAutoState $app { param($s) $s.halted = $false; $s.halted_reason = "" }
    Set-HandoffStatus $app $c2 "보류" | Out-Null
    $c3 = Add-HandoffMessage $app "c2a" "오래전에 보낸 부탁" "## 요약`n- old"
    Set-RowTime $app $c3 (Get-Date).AddMinutes(-40)
    $r = Invoke-Hook $appCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "30" }
    Assert-Equal "10분보다 오래전에 보낸 메시지는 기다리지 않는다" "0|" ("{0}|{1}" -f $r.Exit, $r.Out.Trim())

    Write-Host "모델이 빠진 c2a 에 이 세션의 모델을 적어 둔다"
    $st = New-Channel "stamp-app"
    $stCwd = Join-Path $code "stamp-app"
    New-Item -ItemType Directory -Force -Path $stCwd | Out-Null
    $nOld = Add-HandoffMessage $st "c2a" "오래된 보냄" "## 요약`n- old"
    Set-RowTime $st $nOld (Get-Date).AddHours(-3)
    $nNew = Add-HandoffMessage $st "c2a" "방금 보냄" "## 요약`n- new"
    $nHas = Add-HandoffMessage $st "c2a" "모델 이미 있음" "## 요약`n- has" "" "claude-sonnet-4-5"
    $tr = Join-Path $work "transcript.jsonl"
    $nNewName = (Get-HandoffMessageFile $st $nNew).Name
    $nHasName = (Get-HandoffMessageFile $st $nHas).Name
    $nOldName = (Get-HandoffMessageFile $st $nOld).Name
    $trLines = @(
        ('{"type":"user","message":{"role":"user","content":"wrote ' + $nNewName + ' and ' + $nHasName + ' and ' + $nOldName + '"}}'),
        '{"type":"user","message":{"role":"user","content":"hi"}}',
        '{"type":"assistant","message":{"model":"claude-opus-4-5-20251101","role":"assistant","content":[{"type":"text","text":"ok"}]},"effort":"high","perTurnEffort":null}',
        '{"type":"assistant","message":{"model":"claude-opus-4-5-20251101","role":"assistant","content":[{"type":"text","text":"ok2"}]},"effort":"medium","perTurnEffort":null}',
        '{"type":"assistant","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"x"}]}}'
    )
    [IO.File]::WriteAllText($tr, (($trLines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    $stdinSt = (@{ cwd = $stCwd; session_id = "s1"; hook_event_name = "Stop"; transcript_path = $tr } | ConvertTo-Json -Compress)
    $r = Invoke-Hook $stCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "1" } $stdinSt
    Assert-Equal "  방금 보낸 c2a 에 대화 기록의 마지막 모델이 적힌다" "claude-opus-4-5-20251101" ([string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nNew).FullName)["모델"])
    Assert-Equal "  15분보다 오래된 c2a 는 건드리지 않는다" "" ([string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nOld).FullName)["모델"])
    Assert-Equal "  모델이 이미 있는 c2a 는 그대로 둔다" "claude-sonnet-4-5" ([string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nHas).FullName)["모델"])
    Assert-Equal "  노력은 가장 최근 assistant 줄의 effort 가 적힌다(<synthetic> 줄은 건너뜀)" "medium" ([string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nNew).FullName)["노력"])
    Assert-Equal "  모델이 이미 있어도 노력이 없으면 노력만 채운다(모델은 그대로)" "claude-sonnet-4-5|medium" ("{0}|{1}" -f [string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nHas).FullName)["모델"], [string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nHas).FullName)["노력"])
    Assert-Equal "  15분보다 오래된 c2a 에는 노력도 넣지 않는다" "" ([string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nOld).FullName)["노력"])
    Assert-Equal "  이 세션이 쓴 c2a 에는 세션 ID 도 적힌다(오래된 것은 안 적는다)" "s1|" ("{0}|{1}" -f [string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nNew).FullName)["세션"], [string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nOld).FullName)["세션"])
    $nPer = Add-HandoffMessage $st "c2a" "이번 턴만 노력 다름" "## 요약`n- p"
    $trPer = Join-Path $work "transcript-per.jsonl"
    [IO.File]::WriteAllText($trPer, ('{"type":"user","message":{"role":"user","content":"wrote ' + (Get-HandoffMessageFile $st $nPer).Name + '"}}' + "`n" + '{"type":"assistant","message":{"model":"claude-sonnet-5-5","role":"assistant","content":[]},"effort":"high","perTurnEffort":"xhigh"}' + "`n"), (New-Object Text.UTF8Encoding($false)))
    [void](Invoke-Hook $stCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "1" } (@{ cwd = $stCwd; session_id = "s1"; hook_event_name = "Stop"; transcript_path = $trPer } | ConvertTo-Json -Compress))
    Assert-Equal "  perTurnEffort 가 있으면 그것을 쓴다" "claude-sonnet-5-5|xhigh" ("{0}|{1}" -f [string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nPer).FullName)["모델"], [string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nPer).FullName)["노력"])
    $nNew2 = Add-HandoffMessage $st "c2a" "대화 기록 없이" "## 요약`n- z"
    $r = Invoke-Hook $stCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "1" }
    Assert-Equal "  대화 기록 경로가 없으면 모델을 만들어 넣지 않는다" "" ([string](Read-HandoffFrontMatter (Get-HandoffMessageFile $st $nNew2).FullName)["모델"])

    Write-Host "같은 채널을 세션 둘이 함께 쓸 때 -> 회신은 그 c2a 를 쓴 세션에게만 간다"
    $two = New-Channel "two-app"
    $twoCwd = Join-Path $code "two-app"
    New-Item -ItemType Directory -Force -Path $twoCwd | Out-Null
    $tdir = Join-Path $work "tr2"
    New-Item -ItemType Directory -Force -Path $tdir | Out-Null
    $trA = Join-Path $tdir "sessA.jsonl"
    $trB = Join-Path $tdir "sessB.jsonl"
    $cA = Add-HandoffMessage $two "c2a" "A 가 보낸 질문" "## 요약`n- A" "" "claude-sonnet-5-5"
    $cB = Add-HandoffMessage $two "c2a" "B 가 보낸 질문" "## 요약`n- B" "" "claude-sonnet-5-5"
    $nameA = (Get-HandoffMessageFile $two $cA).Name
    $nameB = (Get-HandoffMessageFile $two $cB).Name
    $enc = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($trA, ('{"type":"user","message":{"role":"user","content":"wrote ' + $nameA + '"}}' + "`n"), $enc)
    [IO.File]::WriteAllText($trB, ('{"type":"user","message":{"role":"user","content":"wrote ' + $nameB + '"}}' + "`n"), $enc)
    $stdinOf = { param($sid, $tr) (@{ cwd = $twoCwd; session_id = $sid; hook_event_name = "Stop"; transcript_path = $tr } | ConvertTo-Json -Compress) }
    [void](Invoke-Hook $twoCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "1" } (& $stdinOf "sessA" $trA))
    Assert-Equal "A 의 훅은 A 의 대화 기록에 있는 c2a 에만 세션을 적는다" "sessA|" ("{0}|{1}" -f [string](Read-HandoffFrontMatter (Get-HandoffMessageFile $two $cA).FullName)["세션"], [string](Read-HandoffFrontMatter (Get-HandoffMessageFile $two $cB).FullName)["세션"])
    [void](Invoke-Hook $twoCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "1" } (& $stdinOf "sessB" $trB))
    Assert-Equal "B 의 훅은 B 의 c2a 에 세션을 적고 A 의 것은 그대로 둔다" "sessA|sessB" ("{0}|{1}" -f [string](Read-HandoffFrontMatter (Get-HandoffMessageFile $two $cA).FullName)["세션"], [string](Read-HandoffFrontMatter (Get-HandoffMessageFile $two $cB).FullName)["세션"])
    $rA = Add-HandoffMessage $two "a2c" "Re: A 가 보낸 질문" "## 요약`n- 답A" $cA "gemini-3.8-flash-high" $true
    $rB = Add-HandoffMessage $two "a2c" "Re: B 가 보낸 질문" "## 요약`n- 답B" $cB "gemini-3.8-flash-high" $true
    [IO.File]::SetLastWriteTime($trA, (Get-Date))
    [IO.File]::SetLastWriteTime($trB, (Get-Date))
    $r = Invoke-Hook $twoCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "1" } (& $stdinOf "sessB" $trB)
    $json = $r.Out | ConvertFrom-Json
    Assert-Equal "B 는 자기 c2a 의 회신만 받는다(block, A 의 회신은 안 나온다)" $true (($json.decision -eq "block") -and ($json.reason -match "#$rB") -and ($json.reason -notmatch "#$rA"))
    Assert-Equal "  A 의 회신은 막은 횟수에도 안 잡힌다" $false ((Read-HandoffAutoState $two).hook_blocks.ContainsKey($rA))
    $r = Invoke-Hook $twoCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "1" } (& $stdinOf "sessA" $trA)
    $json = $r.Out | ConvertFrom-Json
    Assert-Equal "A 는 자기 c2a 의 회신만 받는다(block, B 의 회신은 안 나온다)" $true (($json.decision -eq "block") -and ($json.reason -match "#$rA") -and ($json.reason -notmatch "#$rB"))
    Set-HandoffStatus $two $rA "처리됨" | Out-Null
    Set-HandoffStatus $two $rB "처리됨" | Out-Null
    Update-HandoffAutoState $two { param($s) $s.hook_blocks = @{} }
    Write-Host "  주인 세션이 조용해졌거나 없으면 아무 세션이나 받는다"
    $rA2 = Add-HandoffMessage $two "a2c" "Re: A 두 번째" "## 요약`n- 답A2" $cA "gemini-3.8-flash-high" $true
    [IO.File]::SetLastWriteTime($trA, (Get-Date).AddHours(-2))
    $r = Invoke-Hook $twoCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "1" } (& $stdinOf "sessB" $trB)
    Assert-Equal "  주인(A)의 대화 기록이 한 시간 넘게 멈춰 있으면 B 가 받는다" $true ((($r.Out | ConvertFrom-Json).decision -eq "block") -and (($r.Out | ConvertFrom-Json).reason -match "#$rA2"))
    Set-HandoffStatus $two $rA2 "처리됨" | Out-Null
    Update-HandoffAutoState $two { param($s) $s.hook_blocks = @{} }
    $cOld = Add-HandoffMessage $two "c2a" "세션 표시 없는 질문" "## 요약`n- old"
    $rOld = Add-HandoffMessage $two "a2c" "Re: 세션 표시 없는 질문" "## 요약`n- 답" $cOld "gemini-3.8-flash-high" $true
    [IO.File]::SetLastWriteTime($trA, (Get-Date))
    $r = Invoke-Hook $twoCwd @{ SAMJIL_HANDOFF_WAIT_SECONDS = "1" } (& $stdinOf "sessA" $trA)
    Assert-Equal "  주인 표시가 없는 c2a 의 회신은 아무 세션이나 받는다(예전 메시지)" $true ((($r.Out | ConvertFrom-Json).decision -eq "block") -and (($r.Out | ConvertFrom-Json).reason -match "#$rOld"))
    Set-HandoffStatus $two $rOld "처리됨" | Out-Null

    Write-Host "한글 채널 이름·경로, 하위 폴더에서 열기"
    $kr = New-Channel "프로젝트-가나다"
    $krCwd = Join-Path $code "프로젝트-가나다\src"
    New-Item -ItemType Directory -Force -Path $krCwd | Out-Null
    $k1 = Add-HandoffMessage $kr "a2c" "한글 회신" "## 요약`n- 가"
    $r = Invoke-Hook $krCwd
    $json = $r.Out | ConvertFrom-Json
    Assert-Equal "한글 폴더 이름의 채널을 찾는다 (stdin UTF-8)" $true (($json.decision -eq "block") -and ($json.reason -match "프로젝트-가나다") -and ($json.reason -match "한글 회신"))
}
finally {
    $env:AGENT_HANDOFF_ROOT = $savedRoot
    if (-not $savedRoot) { Remove-Item Env:\AGENT_HANDOFF_ROOT -ErrorAction SilentlyContinue }
}

# ------------------------------------------------------------------------------------------
Write-Host "settings.json 등록기 (register-handoff-hook.ps1)"
try {
    $settings = Join-Path $work "claude\settings.json"
    $hook = Join-Path $work "samjil\handoff\scripts\handoff-stop-hook.ps1"
    function Invoke-Register([string[]]$Extra = @()) {
        $res = Wait-PsProcess (Start-PsProcess $registerScript (@("-SettingsPath", ('"' + $settings + '"'), "-HookScript", ('"' + $hook + '"')) + $Extra) "" @{})
        return $res
    }
    $r = Invoke-Register
    Assert-Equal "설정 파일이 없으면 새로 만들며 ADDED" "ADDED|0" ("{0}|{1}" -f $r.Out.Trim(), $r.Exit)
    $s = Get-Content -Raw -LiteralPath $settings -Encoding UTF8 | ConvertFrom-Json
    $h = $s.hooks.Stop[0].hooks[0]
    Assert-Equal "  Stop 훅 한 개: type=command, timeout=1900" "command|1900" ("{0}|{1}" -f $h.type, $h.timeout)
    Assert-Equal "  명령은 슬래시 경로를 큰따옴표로 감싼 powershell -File" $true (($h.command -match '^powershell\.exe -NoProfile -ExecutionPolicy Bypass -File "') -and ($h.command -notmatch '\\') -and ($h.command -match 'handoff-stop-hook\.ps1"$'))
    $r = Invoke-Register
    Assert-Equal "다시 실행하면 UNCHANGED (중복으로 넣지 않는다)" "UNCHANGED" $r.Out.Trim()
    Assert-Equal "  Stop 훅은 그대로 하나" 1 @((Get-Content -Raw -LiteralPath $settings -Encoding UTF8 | ConvertFrom-Json).hooks.Stop).Count
    $r = Invoke-Register @("-Check")
    Assert-Equal "-Check 는 PRESENT" "PRESENT" $r.Out.Trim()

    # 다른 설정·다른 훅이 있는 settings.json
    $other = '{ "model": "opus", "permissions": { "allow": ["Bash(git status)"] }, "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "echo mine" } ] } ], "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "echo pre" } ] } ] } }'
    [IO.File]::WriteAllText($settings, $other, (New-Object Text.UTF8Encoding($false)))
    $r = Invoke-Register
    Assert-Equal "다른 훅이 있어도 ADDED" "ADDED" $r.Out.Trim()
    $s = Get-Content -Raw -LiteralPath $settings -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal "  기존 Stop 훅은 그대로 남는다" "echo mine" $s.hooks.Stop[0].hooks[0].command
    Assert-Equal "  우리 훅은 새 항목으로 붙는다 (Stop 2개)" 2 @($s.hooks.Stop).Count
    Assert-Equal "  다른 설정(model, permissions, PreToolUse)은 그대로" "opus|Bash(git status)|echo pre" ("{0}|{1}|{2}" -f $s.model, @($s.permissions.allow)[0], $s.hooks.PreToolUse[0].hooks[0].command)
    Assert-Equal "  바꾸기 전 설정이 .bak-* 로 백업된다" $true (@(Get-ChildItem -LiteralPath (Split-Path $settings) -Filter "settings.json.bak-*").Count -ge 1)
    $hook2 = Join-Path $work "moved\handoff-stop-hook.ps1"
    $res = Wait-PsProcess (Start-PsProcess $registerScript @("-SettingsPath", ('"' + $settings + '"'), "-HookScript", ('"' + $hook2 + '"')) "" @{})
    Assert-Equal "경로가 바뀌면 UPDATED (항목은 늘지 않는다)" "UPDATED|2" ("{0}|{1}" -f $res.Out.Trim(), @((Get-Content -Raw -LiteralPath $settings -Encoding UTF8 | ConvertFrom-Json).hooks.Stop).Count)

    $r = Invoke-Register @("-Remove")
    Assert-Equal "-Remove 는 REMOVED" "REMOVED" $r.Out.Trim()
    $s = Get-Content -Raw -LiteralPath $settings -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal "  우리 훅만 빠지고 다른 Stop 훅은 남는다" "1|echo mine" ("{0}|{1}" -f @($s.hooks.Stop).Count, $s.hooks.Stop[0].hooks[0].command)
    $r = Invoke-Register @("-Remove")
    Assert-Equal "  또 빼면 NOTFOUND" "NOTFOUND" $r.Out.Trim()

    [IO.File]::WriteAllText($settings, '{ "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "powershell.exe -File \"x/handoff-stop-hook.ps1\"" } ] } ] } }', (New-Object Text.UTF8Encoding($false)))
    [void](Invoke-Register @("-Remove"))
    $s = Get-Content -Raw -LiteralPath $settings -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal "우리 훅만 있던 settings 에서 빼면 빈 hooks 도 정리한다" $false ($s.PSObject.Properties.Name -contains "hooks")

    $bad = "{ 깨진 json"
    [IO.File]::WriteAllText($settings, $bad, (New-Object Text.UTF8Encoding($false)))
    $r = Invoke-Register
    Assert-Equal "JSON 이 깨진 settings.json 은 건드리지 않고 오류(종료 코드 1)" "1|" ("{0}|{1}" -f $r.Exit, $r.Out.Trim())
    Assert-Equal "  파일 내용은 그대로" $bad ([IO.File]::ReadAllText($settings, [Text.Encoding]::UTF8))
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
