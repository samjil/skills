# 뷰어의 Claude 사용량 API(/api/handoff/claude-usage)와 메시지의 생성 시각(created) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\claude-usage-api.tests.ps1
# 임시 포트에 -NoAgent 뷰어를 숨겨서 띄우고, 임시 채널 루트와 임시 Claude 프로젝트 폴더(CLAUDE_PROJECTS_DIR)만 봅니다.
# 실제 뷰어(8787)·워처·채널·~/.claude 는 건드리지 않습니다. 약 20초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$viewerScript = Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"
. (Join-Path $repoRoot "runtime\handoff\scripts\handoff-lib.ps1")
$psExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("claude-usage-api-test-" + [Guid]::NewGuid().ToString("N"))
$root = Join-Path $work "handoff"
$dataDir = Join-Path $work "data"
$projects = Join-Path $work "claude-projects"
$projDir = Join-Path $projects "D--Repos-x"
New-Item -ItemType Directory -Force -Path $root, $dataDir, $projDir | Out-Null
$savedRoot = $env:AGENT_HANDOFF_ROOT
$env:AGENT_HANDOFF_ROOT = $root
$viewer = $null

function Get-FreePort {
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop(); return $port
}
function Invoke-Http([string]$Url) {
    $req = [System.Net.WebRequest]::Create($Url)
    $req.Method = "GET"; $req.Timeout = 10000
    try { $resp = $req.GetResponse() } catch [System.Net.WebException] { $resp = $_.Exception.Response; if (-not $resp) { throw } }
    try {
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        return @{ Code = [int]$resp.StatusCode; Body = $sr.ReadToEnd() }
    } finally { $resp.Close() }
}
function New-AssistantLine([string]$Id, [string]$Ts, [long]$In, [long]$Create, [long]$Read, [long]$Out) {
    return ('{"type":"assistant","message":{"id":"' + $Id + '","role":"assistant","model":"claude-sonnet-5-5","content":[{"type":"tool_use","name":"Bash","input":{}}],"usage":{"input_tokens":' + $In + ',"cache_creation_input_tokens":' + $Create + ',"cache_read_input_tokens":' + $Read + ',"output_tokens":' + $Out + '}},"timestamp":"' + $Ts + '"}')
}

try {
    $ch = Join-Path $root "my-app"
    New-Item -ItemType Directory -Force -Path (Join-Path $ch "msg") | Out-Null
    Set-Content -LiteralPath (Join-Path $ch "INDEX.md") -Value "# INDEX`n| 번호 | 시각 | 방향 | 제목 | 상태 |`n|---|---|---|---|---|" -Encoding UTF8
    $n1 = Add-HandoffMessage $ch "c2a" "Claude 가 보낸 것" "## 요약`n- a" "" "claude-sonnet-5-5"
    $file = Get-ChildItem -LiteralPath (Join-Path $ch "msg") -Filter "$n1-*.md" | Select-Object -First 1
    $created = $file.CreationTimeUtc

    # 가짜 Claude 세션 기록: 메시지 파일이 생기기 1초 전에 끝난 호출(찾아야 함)과 그 뒤 10분 후의 호출
    $sid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    $iso = { param($d) $d.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
    $tsBefore = $created.AddSeconds(-1)
    $lines = @(
        (New-AssistantLine "msg_old" (& $iso $created.AddMinutes(-30)) 5 100 1000 50),
        (New-AssistantLine "msg_send" (& $iso $tsBefore) 2 2804 531696 1622),
        (New-AssistantLine "msg_later" (& $iso $created.AddMinutes(10)) 9 9 9 9)
    )
    [IO.File]::WriteAllLines((Join-Path $projDir "$sid.jsonl"), $lines, (New-Object System.Text.UTF8Encoding($false)))

    $port = Get-FreePort
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -NoBrowser -NoAgent -Port {1} -HandoffDir "{2}" -DataDir "{3}"' -f $viewerScript, $port, $root, $dataDir)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables["CLAUDE_PROJECTS_DIR"] = $projects
    if (-not $env:USERPROFILE) { $psi.EnvironmentVariables["USERPROFILE"] = $HOME }
    $viewer = [System.Diagnostics.Process]::Start($psi)
    $null = $viewer.StandardOutput.ReadToEndAsync()
    $null = $viewer.StandardError.ReadToEndAsync()
    $base = "http://127.0.0.1:$port"
    $up = $false
    for ($i = 0; $i -lt 40 -and -not $up; $i++) {
        Start-Sleep -Milliseconds 500
        try { $up = ((Invoke-Http "$base/api/status").Code -eq 200) } catch { $up = $false }
    }
    Write-Host "뷰어 시작"
    Assert-Equal "  임시 포트에서 뷰어가 떴다" $true $up

    Write-Host "메시지의 생성 시각 (created)"
    $proj = (Invoke-Http "$base/api/handoff/project?name=my-app").Body | ConvertFrom-Json
    $msg = @($proj.messages)[0]
    Assert-Equal "메시지에 created 가 있다(UTC, 초 단위, Z)" $true ($msg.created -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')
    Assert-Equal "  파일 생성 시각과 같다(초 단위)" $created.ToString("yyyy-MM-ddTHH:mm:ssZ") $msg.created

    Write-Host "Claude 사용량 (/api/handoff/claude-usage)"
    $ts = $msg.created
    $r = Invoke-Http "$base/api/handoff/claude-usage?session=$sid&ts=$([uri]::EscapeDataString($ts))"
    Assert-Equal "200" 200 $r.Code
    $o = $r.Body | ConvertFrom-Json
    Assert-Equal "  기록을 찾았다" $true $o.found
    $item = $o.items.$ts
    Assert-Equal "  생성 시각 바로 앞의 호출: 출력 + 새 입력(일반 2 + 캐시 쓰기 2804)" "1622|2806|4428" ("{0}|{1}|{2}" -f $item.output, $item.newInput, $item.front)
    Assert-Equal "  맥락 크기(새 입력 + 캐시에서 다시 읽은 531696)와 모델" "534502|claude-sonnet-5-5" ("{0}|{1}" -f $item.context, $item.model)
    $far = $created.AddMinutes(-20).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $o2 = (Invoke-Http "$base/api/handoff/claude-usage?session=$sid&ts=$([uri]::EscapeDataString($far + ',' + $ts))").Body | ConvertFrom-Json
    Assert-Equal "  여러 시각을 한 번에: 앞 호출이 3분보다 오래 전이면 null, 다른 시각은 그대로" "True|4428" ("{0}|{1}" -f ($null -eq $o2.items.$far), $o2.items.$ts.front)
    $bad = (Invoke-Http "$base/api/handoff/claude-usage?session=$sid&ts=not-a-time,$([uri]::EscapeDataString($ts))").Body | ConvertFrom-Json
    Assert-Equal "  시각이 아닌 값은 null 로 두고 나머지는 처리한다" "True|4428" ("{0}|{1}" -f ($null -eq $bad.items.'not-a-time'), $bad.items.$ts.front)
    $none = (Invoke-Http "$base/api/handoff/claude-usage?session=99999999-0000-0000-0000-000000000000&ts=$([uri]::EscapeDataString($ts))").Body | ConvertFrom-Json
    Assert-Equal "없는 세션: found false, 항목 없음" "False|0" ("{0}|{1}" -f $none.found, @($none.items.PSObject.Properties).Count)
    Assert-Equal "세션 ID 가 이상하면 400" 400 (Invoke-Http "$base/api/handoff/claude-usage?session=..%5C..%5Cx&ts=$ts").Code
    Assert-Equal "  세션 ID 가 없어도 400" 400 (Invoke-Http "$base/api/handoff/claude-usage?ts=$ts").Code
}
finally {
    if ($viewer -and -not $viewer.HasExited) { try { $viewer.Kill() } catch {} }
    $env:AGENT_HANDOFF_ROOT = $savedRoot
    if (-not $savedRoot) { Remove-Item Env:\AGENT_HANDOFF_ROOT -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
