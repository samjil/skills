# 뷰어의 핸드오프 API 테스트(메시지 머리말의 모델, 자동 이어가기 상태, 켜기·끄기·초기화). Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\handoff\handoff-viewer-api.tests.ps1
# 임시 포트에 -NoAgent 뷰어를 숨겨서 띄우고 임시 채널 루트만 보게 합니다. 실제 뷰어(8787)·워처·채널은 건드리지 않습니다. 약 20초 걸립니다.

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

$work = Join-Path ([IO.Path]::GetTempPath()) ("handoff-api-test-" + [Guid]::NewGuid().ToString("N"))
$root = Join-Path $work "handoff"
$dataDir = Join-Path $work "data"
New-Item -ItemType Directory -Force -Path $root, $dataDir | Out-Null
$savedRoot = $env:AGENT_HANDOFF_ROOT
$env:AGENT_HANDOFF_ROOT = $root
$viewer = $null

function Get-FreePort {
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop(); return $port
}
function Invoke-Http([string]$Method, [string]$Url, [hashtable]$Headers = @{}) {
    $req = [System.Net.WebRequest]::Create($Url)
    $req.Method = $Method
    $req.Timeout = 10000
    foreach ($k in $Headers.Keys) { $req.Headers.Add($k, [string]$Headers[$k]) }
    # .NET Framework(Windows PowerShell 5.1)는 본문이 있을 수 있는 메서드에 Content-Length 가 없으면 http.sys 가 411 로 먼저 거절한다
    if ($Method -eq "POST" -or $Method -eq "PUT") { $req.ContentLength = 0 }
    try {
        $resp = $req.GetResponse()
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if (-not $resp) { throw }
    }
    try {
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        $body = $sr.ReadToEnd()
        return @{ Code = [int]$resp.StatusCode; Body = $body }
    } finally { $resp.Close() }
}

try {
    $ch = Join-Path $root "my-app"
    New-Item -ItemType Directory -Force -Path (Join-Path $ch "msg") | Out-Null
    Set-Content -LiteralPath (Join-Path $ch "INDEX.md") -Value "# INDEX`n| 번호 | 시각 | 방향 | 제목 | 상태 |`n|---|---|---|---|---|" -Encoding UTF8
    $n1 = Add-HandoffMessage $ch "c2a" "Claude 가 보낸 것" "## 요약`n- a" "" "claude-opus-4-5"
    $n2 = Add-HandoffMessage $ch "a2c" "agy 의 회신" "## 요약`n- b" $n1 "gemini-3.8-flash-high" $true
    $oldFile = Join-Path $ch "msg\0003-c2a-old.md"
    Set-Content -LiteralPath $oldFile -Value "# 옛 메시지(머리말 없음)`n본문" -Encoding UTF8
    Add-Content -LiteralPath (Join-Path $ch "INDEX.md") -Value "| 0003 | 2026-10-01 09:00 | c2a | 옛 메시지 | 처리됨 |" -Encoding UTF8

    $port = Get-FreePort
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -NoBrowser -NoAgent -Port {1} -HandoffDir "{2}" -DataDir "{3}"' -f $viewerScript, $port, $root, $dataDir)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    if (-not $env:USERPROFILE) { $psi.EnvironmentVariables["USERPROFILE"] = $HOME }   # Windows 밖(Linux 등)에서 돌릴 때만 필요
    $viewer = [System.Diagnostics.Process]::Start($psi)
    $null = $viewer.StandardOutput.ReadToEndAsync()
    $null = $viewer.StandardError.ReadToEndAsync()
    $base = "http://127.0.0.1:$port"
    $up = $false
    for ($i = 0; $i -lt 40 -and -not $up; $i++) {
        Start-Sleep -Milliseconds 500
        try { $up = ((Invoke-Http "GET" "$base/api/status").Code -eq 200) } catch { $up = $false }
    }
    Assert-Equal "임시 뷰어가 뜬다" $true $up
    if (-not $up) { throw "뷰어가 뜨지 않아 이후 시험을 건너뜁니다" }

    Write-Host "/api/handoff/project: 메시지 머리말과 자동 상태"
    $r = Invoke-Http "GET" "$base/api/handoff/project?name=my-app"
    Assert-Equal "200" 200 $r.Code
    $data = $r.Body | ConvertFrom-Json
    $m1 = @($data.messages | Where-Object { $_.num -eq $n1 })[0]
    $m2 = @($data.messages | Where-Object { $_.num -eq $n2 })[0]
    $m3 = @($data.messages | Where-Object { $_.num -eq "0003" })[0]
    Assert-Equal "Claude 가 보낸 메시지: 모델 claude-opus-4-5, 자동 아님" "claude-opus-4-5|False" ("{0}|{1}" -f $m1.model, $m1.auto)
    Assert-Equal "agy 회신: 모델·답장대상·자동" "gemini-3.8-flash-high|$n1|True" ("{0}|{1}|{2}" -f $m2.model, $m2.replyTo, $m2.auto)
    Assert-Equal "머리말이 없는 옛 메시지: 모델·답장대상 빈 값" "||False" ("{0}|{1}|{2}" -f $m3.model, $m3.replyTo, $m3.auto)
    Assert-Equal "auto 요약: 켜짐, 멈춤 아님, 왕복 0/6" "True|False|0|6" ("{0}|{1}|{2}|{3}" -f $data.auto.enabled, $data.auto.halted, $data.auto.rounds, $data.auto.maxRounds)
    Assert-Equal "기존 필드(번호·시각·방향·제목·상태)는 그대로" "c2a|Claude 가 보낸 것|보냄" ("{0}|{1}|{2}" -f $m1.dir, $m1.title, $m1.status)

    Write-Host "/api/handoff/auto: 켜기·끄기·초기화"
    $h = @{ "X-Samjil-Viewer" = "1" }
    $r = Invoke-Http "GET" "$base/api/handoff/auto?name=my-app"
    Assert-Equal "GET 은 상태를 돌려준다" "200|True" ("{0}|{1}" -f $r.Code, ($r.Body | ConvertFrom-Json).enabled)
    $r = Invoke-Http "POST" "$base/api/handoff/auto?name=my-app&action=off"
    Assert-Equal "전용 헤더 없는 POST 는 403 (다른 웹 페이지가 못 누른다)" 403 $r.Code
    Assert-Equal "  그리고 아무것도 바뀌지 않았다" $false (Test-Path (Join-Path $ch "AUTO.off"))
    $r = Invoke-Http "POST" "$base/api/handoff/auto?name=my-app&action=off" $h
    Assert-Equal "off -> 200, enabled False, AUTO.off 생김" "200|False|True" ("{0}|{1}|{2}" -f $r.Code, ($r.Body | ConvertFrom-Json).enabled, (Test-Path (Join-Path $ch "AUTO.off")))
    $r = Invoke-Http "POST" "$base/api/handoff/auto?name=my-app&action=on" $h
    Assert-Equal "on -> enabled True, AUTO.off 사라짐" "True|False" ("{0}|{1}" -f ($r.Body | ConvertFrom-Json).enabled, (Test-Path (Join-Path $ch "AUTO.off")))
    Update-HandoffAutoState $ch { param($s) $s.halted = $true; $s.halted_reason = "한도 도달"; $s.dispatches = @(@{ num = "0001"; task_id = "t"; at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); done = $true }) }
    $data = (Invoke-Http "GET" "$base/api/handoff/project?name=my-app").Body | ConvertFrom-Json
    Assert-Equal "멈춘 채널: halted·사유·왕복 1" "True|한도 도달|1" ("{0}|{1}|{2}" -f $data.auto.halted, $data.auto.haltedReason, $data.auto.rounds)
    $disp = @($data.auto.dispatches)
    Assert-Equal "auto.dispatches: 메시지 번호 -> 위임 작업 ID 와 끝남 여부(화면이 진행 과정을 찾는 데 쓴다)" "1|0001|t|True" ("{0}|{1}|{2}|{3}" -f $disp.Count, $disp[0].num, $disp[0].taskId, $disp[0].done)
    $r = Invoke-Http "POST" "$base/api/handoff/auto?name=my-app&action=reset" $h
    Assert-Equal "reset -> halted False, 왕복 0" "False|0" ("{0}|{1}" -f ($r.Body | ConvertFrom-Json).halted, ($r.Body | ConvertFrom-Json).rounds)
    Assert-Equal "알 수 없는 action 은 400" 400 (Invoke-Http "POST" "$base/api/handoff/auto?name=my-app&action=explode" $h).Code
    Assert-Equal "없는 채널은 404" 404 (Invoke-Http "POST" "$base/api/handoff/auto?name=nope&action=off" $h).Code
    Assert-Equal "경로 조작 문자가 든 이름은 400" 400 (Invoke-Http "POST" "$base/api/handoff/auto?name=..%5Cx&action=off" $h).Code
    Assert-Equal "이름이 없으면 400" 400 (Invoke-Http "GET" "$base/api/handoff/auto").Code
    Assert-Equal "PUT 은 405" 405 (Invoke-Http "PUT" "$base/api/handoff/auto?name=my-app&action=off" $h).Code
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
