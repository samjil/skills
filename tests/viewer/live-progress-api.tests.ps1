# 진행 중인 위임의 진행 표시용 서버 응답 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\live-progress-api.tests.ps1
#   - /api/delegate/pending : 진행 중 작업이 대화 ID(conversation_id)·단계 수(step_count)·멈춤 기준(stall_seconds)을 주고 단계 전체(steps)는 싣지 않는다.
#                             실행 표시(claim)만 남고 작업자가 사라진 작업은 interrupted 로 알린다.
#   - /api/delegate/process : since=<단계 번호> 로 그 뒤의 새 단계만 돌려준다. 기록이 새로 만들어지면 reset.
# 임시 폴더에 가짜 agy 대화 기록과 실행 표시 파일을 만들고 뷰어를 -NoAgent 로 실제로 띄웁니다(진짜 뷰어·워처·agy 기록은 건드리지 않습니다).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$viewerScript = Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("live-progress-test-" + [Guid]::NewGuid().ToString("N"))
$rt = Join-Path $work "runtime"
$agyHome = Join-Path $work "agyhome"
foreach ($d in @("inbox", "outbox", "processed", "logs", "logs\data", "logs\heartbeat", "logs\sessions", "logs\running")) { New-Item -ItemType Directory -Force -Path (Join-Path $rt $d) | Out-Null }
New-Item -ItemType Directory -Force -Path (Join-Path $work "handoff") | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

# 가짜 agy 대화 기록: 도구를 부르는 응답(PLANNER_RESPONSE)이 단계 번호 $steps 마다 하나씩.
function New-Transcript([string]$convId, [int[]]$steps) {
    $dir = Join-Path $agyHome "brain\$convId\.system_generated\logs"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $lines = @()
    foreach ($n in $steps) {
        $o = [ordered]@{ step_index = $n; source = "MODEL"; type = "PLANNER_RESPONSE"; status = "DONE"; created_at = "2026-10-16T03:00:00Z"
            tool_calls = @(@{ name = "view_file"; args = @{ AbsolutePath = "C:\work\f$n.txt"; toolAction = "Reading f$n" } }) }
        $lines += ($o | ConvertTo-Json -Compress -Depth 8)
    }
    [System.IO.File]::WriteAllText((Join-Path $dir "transcript_full.jsonl"), (($lines -join "`n") + "`n"), $utf8)
    return (Join-Path $dir "transcript_full.jsonl")
}
$tfRun = New-Transcript "conv-running" @(1, 3, 5)
$tfDead = New-Transcript "conv-dead" @(1, 3)
$tfBg = New-Transcript "conv-bg" @(1)
$tfIdle = New-Transcript "conv-idle" @(1)
# 오래 걸리는 명령을 백그라운드로 돌려 두고 기다리는 대화(시작만 있고 끝난다는 알림이 없다). 둘 다 마지막 활동이 10분 전이다.
[System.IO.File]::AppendAllText($tfBg, ((@{ step_index = 2; type = "GENERIC"; status = "RUNNING"; content = "Tool is running as a background task with task id: conv-bg/task-1" } | ConvertTo-Json -Compress) + "`n"), $utf8)
foreach ($f in @($tfBg, $tfIdle)) { (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddMinutes(-10) }

# 진행 중 작업(작업자 = 이 시험 프로세스, powershell) / 중단된 작업(이미 끝난 프로세스의 PID)
$t0 = (Get-Date).AddMinutes(-3).ToString("yyyy-MM-dd HH:mm:ss")
[System.IO.File]::WriteAllText((Join-Path $rt "inbox\t_run.md"), "진행 중인 질문", $utf8)
[System.IO.File]::WriteAllText((Join-Path $rt "inbox\t_dead.md"), "중단된 질문", $utf8)
[System.IO.File]::WriteAllText((Join-Path $rt "inbox\t_wait.md"), "대기 중인 질문", $utf8)
$deadProc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-Command", "exit 0") -WindowStyle Hidden -PassThru
$deadProc.WaitForExit()
function Put-Claim([string]$id, [int]$claimPid, [string]$conv) {
    $o = [ordered]@{ task_id = $id; pid = $claimPid; model = "gemini-3.8-flash-high"; started_at = $t0; conversation_id = $conv }
    [System.IO.File]::WriteAllText((Join-Path $rt "logs\running\$id.json"), (ConvertTo-Json -InputObject $o -Compress), $utf8)
}
Put-Claim "t_run" $PID "conv-running"
Put-Claim "t_dead" $deadProc.Id "conv-dead"
foreach ($id in @("t_bg", "t_idle")) { [System.IO.File]::WriteAllText((Join-Path $rt "inbox\$id.md"), "질문", $utf8) }
Put-Claim "t_bg" $PID "conv-bg"
Put-Claim "t_idle" $PID "conv-idle"

$port = Get-Random -Minimum 30000 -Maximum 40000
$env:AGY_DELEGATE_RUNTIME = $rt
$env:AGY_HOME = $agyHome
$viewer = $null
try {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$viewerScript`"", "-NoBrowser", "-NoAgent", "-Port", $port,
        "-DataDir", "`"$(Join-Path $rt 'logs\data')`"", "-HandoffDir", "`"$(Join-Path $work 'handoff')`"")
    $viewer = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden -PassThru
    $up = $false
    for ($i = 0; $i -lt 40 -and -not $up; $i++) {
        Start-Sleep -Milliseconds 500
        try { $up = ((Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/status" -TimeoutSec 2).StatusCode -eq 200) } catch {}
    }
    Assert-Equal "뷰어가 응답한다" $true $up
    function Get-Json([string]$path) {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port$path" -TimeoutSec 10
        $text = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        return @{ Text = $text; Obj = (ConvertFrom-Json -InputObject $text) }
    }

    Write-Host "/api/delegate/pending: 진행 중 작업"
    $r = Get-Json "/api/delegate/pending"
    $byId = @{}; foreach ($it in @($r.Obj)) { $byId[$it.task_id] = $it }
    $run = $byId["t_run"]
    Assert-Equal "상태 processing" "processing" $run.state
    Assert-Equal "대화 ID 가 작업 항목에 바로 있다" "conv-running" $run.conversation_id
    Assert-Equal "  progress 에도 같은 ID" "conv-running" $run.progress.conversation_id
    Assert-Equal "단계 수(step_count)" 3 $run.progress.step_count
    Assert-Equal "멈춤 기준(stall_seconds) 기본 300" 300 $run.progress.stall_seconds
    Assert-Equal "백그라운드 도구 대기 아님" $false $run.progress.waiting_background
    Assert-Equal "interrupted 아님" $false $run.interrupted
    Assert-Equal "마지막 활동 시각을 준다" $true ([int64]$run.progress.last_activity_ms -gt 0)
    Assert-Equal "5초마다 불리는 목록에는 단계 전체(steps)를 싣지 않는다" $false ($null -ne $run.progress.PSObject.Properties["steps"])

    Write-Host "/api/delegate/pending: 오래 조용한 작업 - 백그라운드 명령을 기다리는 것과 그냥 멈춘 것을 가른다"
    Assert-Equal "10분째 새 단계가 없지만 백그라운드 명령을 기다리는 중" $true $byId["t_bg"].progress.waiting_background
    Assert-Equal "10분째 새 단계가 없고 기다리는 것도 없음" $false $byId["t_idle"].progress.waiting_background
    Assert-Equal "  마지막 활동 시각이 10분 전쯤이다(화면이 이 값으로 멈춤을 판정한다)" $true (((Get-Date) - [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$byId["t_idle"].progress.last_activity_ms).LocalDateTime).TotalMinutes -gt 9)

    Write-Host "/api/delegate/pending: 중단된 작업과 대기 중 작업"
    $dead = $byId["t_dead"]
    Assert-Equal "작업자가 사라진 작업은 interrupted" $true $dead.interrupted
    Assert-Equal "  processing 이 아니라 queued 로 남는다(진행 중인 척하지 않는다)" "queued" $dead.state
    Assert-Equal "  그래도 대화 ID 와 마지막 진행 상황은 준다" "conv-dead|2" ("{0}|{1}" -f $dead.conversation_id, $dead.progress.step_count)
    Assert-Equal "  시작 시각도 남는다" $t0 $dead.started_at
    $wait = $byId["t_wait"]
    Assert-Equal "그냥 대기 중인 작업은 interrupted 아님·대화 ID 없음" "queued|False|" ("{0}|{1}|{2}" -f $wait.state, $wait.interrupted, $wait.conversation_id)

    Write-Host "/api/delegate/process: since 로 새 단계만"
    $all = (Get-Json "/api/delegate/process?id=conv-running").Obj
    Assert-Equal "since 없이: 전부(3개), 번호 1,3,5" "3|1,3,5" ("{0}|{1}" -f @($all.steps).Count, ((@($all.steps) | ForEach-Object { $_.n }) -join ","))
    Assert-Equal "  전체 단계 수와 마지막 활동 시각" $true ($all.total -eq 3 -and [int64]$all.last_activity_ms -gt 0 -and $all.found -eq $true -and $all.reset -eq $false)
    $part = (Get-Json "/api/delegate/process?id=conv-running&since=3").Obj
    Assert-Equal "since=3: 5번 하나만" "1|5" ("{0}|{1}" -f @($part.steps).Count, @($part.steps)[0].n)
    $none = Get-Json "/api/delegate/process?id=conv-running&since=5"
    Assert-Equal "since=5(마지막): 새 단계 없음, JSON 은 빈 배열" $true (@($none.Obj.steps).Count -eq 0 -and $none.Text -match '"steps":\s*\[\s*\]')

    # 기록에 새 단계가 쌓이면 이어서 받는다
    $extra = [ordered]@{ step_index = 7; source = "MODEL"; type = "PLANNER_RESPONSE"; status = "DONE"; created_at = "2026-10-16T03:01:00Z"
        tool_calls = @(@{ name = "run_command"; args = @{ CommandLine = "dir"; toolAction = "Listing" } }) }
    [System.IO.File]::AppendAllText($tfRun, (($extra | ConvertTo-Json -Compress -Depth 8) + "`n"), $utf8)
    $grown = (Get-Json "/api/delegate/process?id=conv-running&since=5").Obj
    Assert-Equal "기록이 자라면 since=5 로 7번 하나가 온다" "1|7|dir" ("{0}|{1}|{2}" -f @($grown.steps).Count, @($grown.steps)[0].n, @($grown.steps)[0].detail)
    $grownPending = (Get-Json "/api/delegate/pending").Obj
    $runNow = @($grownPending | Where-Object { $_.task_id -eq "t_run" })[0]
    Assert-Equal "  목록의 단계 수도 4로 는다" 4 $runNow.progress.step_count

    $reset = (Get-Json "/api/delegate/process?id=conv-running&since=99").Obj
    Assert-Equal "받아 간 번호가 기록의 마지막보다 크면 reset 과 함께 처음부터" "True|4" ("{0}|{1}" -f $reset.reset, @($reset.steps).Count)
    Assert-Equal "없는 대화는 found False·빈 목록" "False|0" ("{0}|{1}" -f (Get-Json "/api/delegate/process?id=conv-none").Obj.found, @((Get-Json "/api/delegate/process?id=conv-none").Obj.steps).Count)
    $bad = $null
    try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/delegate/process?id=..%5C..%5Cx" -TimeoutSec 5 | Out-Null } catch { $bad = [int]$_.Exception.Response.StatusCode }
    Assert-Equal "경로 문자가 든 id 는 400" 400 $bad
}
finally {
    if ($viewer -and -not $viewer.HasExited) { Stop-Process -Id $viewer.Id -Force -ErrorAction SilentlyContinue }
    $env:AGY_DELEGATE_RUNTIME = $null
    $env:AGY_HOME = $null
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
