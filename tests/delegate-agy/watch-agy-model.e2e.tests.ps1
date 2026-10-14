# watch-agy.ps1 을 실제로 띄워 @model: 이 메인 루프 끝까지 이어지는지 확인하는 종단 시험.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\watch-agy-model.e2e.tests.ps1
# 임시 런타임 폴더(-RuntimeDir)와 가짜 agy(agy.cmd, PATH 맨 앞)만 씁니다. 이 PC에 진짜 워처가 떠 있어도 건드리지 않습니다
# (잠금 파일이 런타임 폴더별이고, 워처는 다른 프로세스를 종료하지 않음). 약 1분 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$watcher  = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\watch-agy.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("watch-agy-model-e2e-" + [Guid]::NewGuid().ToString("N"))
$rt = Join-Path $work "runtime"
$fakeBin = Join-Path $work "bin"
foreach ($d in @("inbox", "outbox", "processed", "logs", "logs\data", "logs\heartbeat")) { New-Item -ItemType Directory -Force -Path (Join-Path $rt $d) | Out-Null }
New-Item -ItemType Directory -Force -Path $fakeBin, (Join-Path $work "agyhome\conversations") | Out-Null

Set-Content -Path (Join-Path $fakeBin "fake-agy.ps1") -Encoding ASCII -Value @'
$a = @($args)
$i = [Array]::IndexOf([string[]]$a, '--model'); $model = if ($i -ge 0) { $a[$i + 1] } else { "" }
Add-Content -Path $env:FAKE_ARGS_LOG -Value ("model=" + $model)
$dirs = @(); for ($k = 0; $k -lt ($a.Count - 1); $k++) { if ($a[$k] -eq '--add-dir') { $dirs += $a[$k + 1] } }
Add-Content -Path $env:FAKE_DIRS_LOG -Value ("dirs=" + ($dirs -join '|'))
$quota = @($env:FAKE_QUOTA_MODELS -split ',' | Where-Object { $_ })
if ($quota -contains $model) { '{"status":"ERROR","error":"quota exceeded for model ' + $model + '"}' }
else {
    $dir = Join-Path $env:AGY_HOME "brain\conv-test\.system_generated\logs"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $l1 = '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-13T07:48:57Z","thinking":"folder first","tool_calls":[{"name":"run_command","args":{"CommandLine":"Get-Location","Cwd":"C:\\w","toolAction":"Checking target directory","toolSummary":"Check"}}]}'
    $l2 = '{"step_index":2,"source":"MODEL","type":"GENERIC","status":"DONE","content":"result"}'
    $l3 = '{"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-13T07:49:51Z","thinking":"then write","tool_calls":[{"name":"write_to_file","args":{"TargetFile":"C:\\w\\x.py","CodeContent":"body","toolAction":"Writing x.py"}}]}'
    Set-Content -Path (Join-Path $dir "transcript_full.jsonl") -Value @($l1, $l2, $l3) -Encoding UTF8
    '{"status":"SUCCESS","response":"ok from ' + $model + '","conversation_id":"conv-test","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}'
}
'@
Set-Content -Path (Join-Path $fakeBin "agy.cmd") -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake-agy.ps1`" %*"

$env:PATH = "$fakeBin;$env:PATH"
$env:AGY_HOME = Join-Path $work "agyhome"
$env:FAKE_ARGS_LOG = Join-Path $work "args.log"
$env:FAKE_DIRS_LOG = Join-Path $work "dirs.log"
$env:FAKE_QUOTA_MODELS = "gemini-3.8-flash-medium"

function Send-Task([string]$name, [string]$text) {
    [System.IO.File]::WriteAllText((Join-Path $rt "inbox\$name.md"), $text, (New-Object System.Text.UTF8Encoding($false)))
}
function Get-Response([string]$name) {
    $f = Join-Path $rt "outbox\$name.response.md"
    if (Test-Path $f) { return ([System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)).Trim([char]0xFEFF, " ", "`r", "`n") } else { return $null }
}

$proc = $null
try {
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$watcher`"", "-RuntimeDir", "`"$rt`"") -WindowStyle Hidden -PassThru
    $lock = Join-Path $rt ("logs\watcher_{0}.lock" -f $env:COMPUTERNAME)
    $started = $false
    for ($i = 0; $i -lt 60 -and -not $started; $i++) { if (Test-Path $lock) { $started = $true } else { Start-Sleep -Milliseconds 500 } }
    Write-Host "워처 시작"
    Assert-Equal "  임시 런타임에서 워처가 시작됐다" $true $started

    Send-Task "e2e_low"     "@model: gemini-3.8-flash-low`n간단한 질문입니다."
    Send-Task "e2e_default" "모델을 지정하지 않은 질문입니다."
    Send-Task "e2e_bad"     "@model: claude-opus-4-6-thinking`n질문"
    Send-Task "e2e_quota"   "@model: gemini-3.8-flash-medium`n질문"

    $names = @("e2e_low", "e2e_default", "e2e_bad", "e2e_quota")
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline -and (@($names | Where-Object { $null -ne (Get-Response $_) }).Count -lt $names.Count)) { Start-Sleep -Seconds 2 }

    Write-Host "처리 결과 (outbox)"
    Assert-Equal "  @model 로 낮은 단계를 고르면 그 모델로 처리된다" "ok from gemini-3.8-flash-low" (Get-Response "e2e_low")
    Assert-Equal "  모델을 안 고르면 우선순위 첫 모델로 처리된다" "ok from gemini-3.8-flash-high" (Get-Response "e2e_default")
    $bad = Get-Response "e2e_bad"
    Assert-Equal "  쓸 수 없는 모델(claude)은 agy 를 부르지 않고 실패 메시지를 준다" $true ($bad -like "*지정한 @model 을 쓸 수 없습니다*claude-opus-4-6-thinking*")
    Assert-Equal "    실패 메시지에 쓸 수 있는 모델 목록이 있다" $true ($bad -like "*gemini-3.8-flash-medium*")
    $quota = Get-Response "e2e_quota"
    Assert-Equal "  고른 모델이 쿼터 초과면 실패로 알린다" $true ($quota -like "agy 실행 실패*quota*")
    Assert-Equal "    자동 전환하지 않았다고 밝힌다" $true ($quota -like "*다른 모델로 자동 전환하지 않았습니다*")
    Assert-Equal "    시도한 모델은 고른 하나뿐이다" $true ($quota -like "*시도한 모델: gemini-3.8-flash-medium)*")

    Write-Host "agy 호출 기록 (가짜 agy)"
    $calls = @(if (Test-Path $env:FAKE_ARGS_LOG) { Get-Content $env:FAKE_ARGS_LOG })
    Assert-Equal "  agy 는 정확히 3번만 불렸다 (low, 기본, 쿼터 초과 medium 1번 / 잘못된 모델은 호출 없음)" 3 $calls.Count
    Assert-Equal "  low 요청 -> --model gemini-3.8-flash-low" 1 @($calls | Where-Object { $_ -eq "model=gemini-3.8-flash-low" }).Count
    Assert-Equal "  기본 요청 -> 첫 우선순위 모델" 1 @($calls | Where-Object { $_ -eq "model=gemini-3.8-flash-high" }).Count
    Assert-Equal "  쿼터 초과 요청 -> 다른 모델을 시도하지 않고 medium 1번만" 1 @($calls | Where-Object { $_ -eq "model=gemini-3.8-flash-medium" }).Count

    Write-Host "기록(qa jsonl)에 과정 저장"
$qaFile = Join-Path $rt "logs\data"
$deadline2 = (Get-Date).AddSeconds(40)
$qaRows = @()
while ((Get-Date) -lt $deadline2) {
    $qaRows = @(Get-ChildItem $qaFile -Filter "qa-*.jsonl" -File -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName -Encoding UTF8 } | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    if (@($qaRows | Where-Object { $_.task_id -like "e2e_*" }).Count -ge 4) { break }
    Start-Sleep -Seconds 2
}
$qaLow = $qaRows | Where-Object { $_.task_id -eq "e2e_low" } | Select-Object -First 1
$stepsLow = @($qaLow.process)
Assert-Equal "  성공한 작업의 기록에 process(도구 호출 2개)가 있다" 2 $stepsLow.Count
Assert-Equal "    첫 호출: 도구/대상/라벨" "run_command|Get-Location|Checking target directory" ("{0}|{1}|{2}" -f $stepsLow[0].tool, $stepsLow[0].detail, $stepsLow[0].label)
Assert-Equal "    둘째 호출: 파일 쓰기 대상은 경로(코드 본문 없음)" "write_to_file|C:\w\x.py" ("{0}|{1}" -f $stepsLow[1].tool, $stepsLow[1].detail)
Assert-Equal "    단계 번호는 대화 기록의 step_index" "1,3" (($stepsLow | ForEach-Object { $_.n }) -join ",")
Assert-Equal "    생각이 붙는다" "folder first" $stepsLow[0].think
$qaQuota = $qaRows | Where-Object { $_.task_id -eq "e2e_quota" } | Select-Object -First 1
Assert-Equal "  대화가 없는 실패(쿼터 초과) 기록의 process 는 null(= 모름)" $true ($null -eq $qaQuota.process)
$qaBad = $qaRows | Where-Object { $_.task_id -eq "e2e_bad" } | Select-Object -First 1
Assert-Equal "  agy 를 부르지 않은 실패(잘못된 모델) 기록의 process 도 null" $true ($null -eq $qaBad.process)
$qaDef = $qaRows | Where-Object { $_.task_id -eq "e2e_default" } | Select-Object -First 1
Assert-Equal "  모델을 안 고른 성공 작업도 process 가 저장된다" 2 @($qaDef.process).Count


    Write-Host "@cwd 여러 폴더 (한 번에 하나씩 보내고 가짜 agy 가 받은 --add-dir 를 본다)"
    $dirA = Join-Path $work "proj-a"; $dirB = Join-Path $work "docs b"; $dirC = Join-Path $work "proj-c"
    foreach ($dd in @($dirA, $dirB, $dirC)) { New-Item -ItemType Directory -Force -Path $dd | Out-Null }
    function Invoke-CwdTask([string]$name, [string]$text) {
        if (Test-Path $env:FAKE_DIRS_LOG) { Remove-Item $env:FAKE_DIRS_LOG -Force }
        Send-Task $name $text
        $until = (Get-Date).AddSeconds(60)
        while ((Get-Date) -lt $until -and $null -eq (Get-Response $name)) { Start-Sleep -Milliseconds 500 }
        $dl = @(if (Test-Path $env:FAKE_DIRS_LOG) { Get-Content $env:FAKE_DIRS_LOG })
        return @{ Response = (Get-Response $name); Dirs = $dl }
    }
    $watcherLog = Join-Path $rt "logs\watcher.log"
    # 응답 파일이 먼저 생기고 세션 파일은 그 직후에 쓰이므로, 기대한 내용이 될 때까지 잠깐 기다리며 읽는다
    function Read-SessionUntil([string]$path, [scriptblock]$ok) {
        $obj = $null
        $until = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $until) {
            try { $obj = (Get-Content -Raw -LiteralPath $path -Encoding UTF8) | ConvertFrom-Json } catch { $obj = $null }
            if ($obj -and (& $ok $obj)) { break }
            Start-Sleep -Milliseconds 300
        }
        return $obj
    }
    function Get-LogLines([string]$name) {
        # 그 작업을 처리하는 동안 남은 로그만(처리 중: <이름>.md 줄부터 다음 처리 중 줄 앞까지)
        $all = @(Get-Content $watcherLog -Encoding UTF8)
        $start = -1; for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -like "*처리 중: $name.md*") { $start = $i } }
        if ($start -lt 0) { return @() }
        $end = $all.Count; for ($i = $start + 1; $i -lt $all.Count; $i++) { if ($all[$i] -like "*처리 중:*") { $end = $i; break } }
        return @($all[$start..($end - 1)])
    }

    $r = Invoke-CwdTask "cwd_one" "@cwd: $dirA`n한 폴더 질문"
    Assert-Equal "@cwd 한 줄은 이전과 같이 --add-dir 하나" "dirs=$dirA" $r.Dirs[0]
    Assert-Equal "  agy 는 한 번 불렸다" 1 $r.Dirs.Count
    $logOne = Get-LogLines "cwd_one"
    Assert-Equal "  watcher.log 에 '대상 폴더(--add-dir)' 줄이 한 번" 1 @($logOne | Where-Object { $_ -like "*대상 폴더(--add-dir): $dirA*" }).Count

    $r = Invoke-CwdTask "cwd_two" "@cwd: $dirA`n@cwd: $dirB`n@model: gemini-3.8-flash-low`n두 폴더 질문"
    Assert-Equal "@cwd 두 줄은 --add-dir 를 폴더마다 한 번씩, 줄 순서대로" "dirs=$dirA|$dirB" $r.Dirs[0]
    Assert-Equal "  처리되어 응답이 온다(@model 도 함께 읽힘)" "ok from gemini-3.8-flash-low" $r.Response
    $logTwo = Get-LogLines "cwd_two"
    Assert-Equal "  watcher.log 에 '대상 폴더(--add-dir)' 줄이 폴더마다 한 줄(2번)" 2 @($logTwo | Where-Object { $_ -like "*대상 폴더(--add-dir):*" }).Count
    $dirLines = @($logTwo | Where-Object { $_ -like "*대상 폴더(--add-dir):*" })
    Assert-Equal "  첫 번째 로그 줄이 A, 두 번째가 B" "A|B" ("{0}|{1}" -f $(if ($dirLines[0] -like "*proj-a") { "A" } else { "?" }), $(if ($dirLines[1] -like "*docs b") { "B" } else { "?" }))

    $r = Invoke-CwdTask "cwd_dup" "@cwd: $dirA`n@cwd: $($dirA.ToUpper())\`n@cwd: $dirB`n중복 질문"
    Assert-Equal "같은 폴더를 대소문자·끝의 \ 만 다르게 또 써도 한 번만 넘긴다" "dirs=$dirA|$dirB" $r.Dirs[0]

    $callsBefore = @(if (Test-Path $env:FAKE_ARGS_LOG) { Get-Content $env:FAKE_ARGS_LOG }).Count
    $missing1 = Join-Path $work "no-such-1"; $missing2 = Join-Path $work "no-such-2"
    $r = Invoke-CwdTask "cwd_missing" "@cwd: $dirA`n@cwd: $missing1`n@cwd: $dirB`n@cwd: $missing2`n없는 폴더가 섞인 질문"
    Assert-Equal "없는 폴더가 하나라도 있으면 agy 를 부르지 않는다" 0 $r.Dirs.Count
    Assert-Equal "  agy 호출 기록도 늘지 않았다" $callsBefore (@(if (Test-Path $env:FAKE_ARGS_LOG) { Get-Content $env:FAKE_ARGS_LOG }).Count)
    Assert-Equal "  오류 메시지에 없는 폴더를 모두 적는다" $true (($r.Response -like "*지정한 @cwd 경로를 찾을 수 없습니다*") -and ($r.Response -like "*$missing1*") -and ($r.Response -like "*$missing2*"))
    Assert-Equal "  있는 폴더(A, B)는 오류 메시지에 없다" $false (($r.Response -like "*$dirA*") -or ($r.Response -like "*$dirB*"))
    Assert-Equal "  watcher.log 에도 '@cwd 경로 없음' 이 남는다" 1 @(Get-LogLines "cwd_missing" | Where-Object { $_ -like "*@cwd 경로 없음*" }).Count

    Write-Host "@cwd 여러 폴더 + 세션(@session)"
    $r = Invoke-CwdTask "cwd_s1" "@session: 다폴더-세션`n@cwd: $dirA`n@cwd: $dirB`n@model: gemini-3.8-flash-low`n첫 호출"
    Assert-Equal "첫 호출: 두 폴더가 열린다" "dirs=$dirA|$dirB" $r.Dirs[0]
    $sessFile = Join-Path $rt "logs\sessions\다폴더-세션.json"
    $sess = Read-SessionUntil $sessFile { param($o) @($o.cwd).Count -eq 2 }
    Assert-Equal "  세션 파일의 cwd 는 두 폴더 배열" "$dirA|$dirB" (@($sess.cwd) -join "|")
    $r = Invoke-CwdTask "cwd_s2" "@session: 다폴더-세션`n두 번째 호출(@cwd 없음)"
    Assert-Equal "두 번째 호출(@cwd 없음): 세션의 두 폴더가 그대로 열린다" "dirs=$dirA|$dirB" $r.Dirs[0]
    $r = Invoke-CwdTask "cwd_s3" "@session: 다폴더-세션`n@cwd: $dirC`n세 번째 호출(@cwd 하나)"
    Assert-Equal "이번 호출에 @cwd 가 하나라도 있으면 이번 목록만 쓴다(세션의 폴더와 합치지 않는다)" "dirs=$dirC" $r.Dirs[0]
    $sess = Read-SessionUntil $sessFile { param($o) @($o.cwd).Count -eq 1 -and @($o.cwd)[0] -eq $dirC }
    Assert-Equal "  세션에는 새 목록이 저장된다" "$dirC" (@($sess.cwd) -join "|")
    $r = Invoke-CwdTask "cwd_s4" "@session: 다폴더-세션`n네 번째 호출(@cwd 없음)"
    Assert-Equal "  그다음 @cwd 없는 호출은 바뀐 목록(C)을 이어서 쓴다" "dirs=$dirC" $r.Dirs[0]

    Write-Host "예전 형식 세션 파일(cwd 가 문자열)"
    $oldSess = '{ "name": "예전-세션", "conversation_id": "conv-old", "cwd": ' + (ConvertTo-Json -InputObject $dirB) + ', "model": "gemini-3.8-flash-low", "created_at": "2026-10-01 10:00:00", "last_used_at": "2026-10-01 10:00:00", "turn_count": 2 }'
    [System.IO.File]::WriteAllText((Join-Path $rt "logs\sessions\예전-세션.json"), $oldSess, (New-Object System.Text.UTF8Encoding($false)))
    $r = Invoke-CwdTask "cwd_old" "@session: 예전-세션`n예전 세션을 이어갑니다"
    Assert-Equal "문자열 cwd 가 든 세션을 이어가면 그 폴더 하나가 열린다" "dirs=$dirB" $r.Dirs[0]
    # 응답 파일이 먼저 생기고 세션 파일은 그 직후에 쓰이므로, 다 쓰일 때까지(횟수가 3이 될 때까지) 잠깐 기다린다
    $oldAfter = $null
    $untilSess = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $untilSess) {
        try { $oldAfter = (Get-Content -Raw -LiteralPath (Join-Path $rt "logs\sessions\예전-세션.json") -Encoding UTF8) | ConvertFrom-Json } catch { $oldAfter = $null }
        if ($oldAfter -and $oldAfter.turn_count -eq 3) { break }
        Start-Sleep -Milliseconds 300
    }
    Assert-Equal "  이어간 뒤 세션 파일은 배열 형식으로 바뀌고 폴더·횟수가 유지된다" "$dirB|1|3" ("{0}|{1}|{2}" -f (@($oldAfter.cwd) -join "|"), @($oldAfter.cwd).Count, $oldAfter.turn_count)

Write-Host "사용량 기록 (usage.csv)"
    $usage = @(Import-Csv (Join-Path $rt "logs\usage.csv") -Encoding UTF8)
    $row = { param($id) $usage | Where-Object { $_.task_id -eq $id } | Select-Object -First 1 }
    Assert-Equal "  low: 모델 칸에 그 모델, 상태 OK" "gemini-3.8-flash-low|OK" ("{0}|{1}" -f (& $row "e2e_low").model, (& $row "e2e_low").status)
    Assert-Equal "  기본: 모델 칸에 첫 우선순위 모델" "gemini-3.8-flash-high|OK" ("{0}|{1}" -f (& $row "e2e_default").model, (& $row "e2e_default").status)
    Assert-Equal "  잘못된 모델: ERROR, 시도한 모델 칸에 요청값 (화면에서 어떤 모델을 요청했는지 보임)" "ERROR|claude-opus-4-6-thinking" ("{0}|{1}" -f (& $row "e2e_bad").status, (& $row "e2e_bad").tried_models)
    Assert-Equal "  쿼터 초과: ERROR, 시도한 모델은 하나" "ERROR|gemini-3.8-flash-medium" ("{0}|{1}" -f (& $row "e2e_quota").status, (& $row "e2e_quota").tried_models)
}
finally {
    if ($proc -and -not $proc.HasExited) {
        "stop" | Set-Content -Path (Join-Path $rt "logs\stop.signal") -Encoding UTF8
        $null = $proc.WaitForExit(40000)
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
