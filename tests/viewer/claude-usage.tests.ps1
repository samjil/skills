# claude-usage.ps1(Claude 세션 기록에서 호출별 사용량 읽기) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\claude-usage.tests.ps1
# 가짜 세션 기록(임시 폴더)만 읽습니다. 실제 ~/.claude 는 건드리지 않습니다. 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\viewer\claude-usage.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

# 실제 세션 기록의 모양을 따른 한 줄. 응답 하나(id)가 블록마다 줄로 나뉘고 줄마다 같은 usage 가 붙는다.
function New-AssistantLine([string]$Id, [string]$Ts, [string]$Block, [long]$In, [long]$Create, [long]$Read, [long]$Out, [string]$Model = "claude-sonnet-5-5", [string]$Text = "") {
    $content = if ($Block -eq "tool_use") { '[{"type":"tool_use","id":"toolu_x","name":"Bash","input":{"command":"echo \"usage\":{\"output_tokens\":999999}"}}]' } else { '[{"type":"' + $Block + '","' + $Block + '":"' + $Text + '"}]' }
    return ('{"parentUuid":"p","type":"assistant","message":{"id":"' + $Id + '","type":"message","role":"assistant","model":"' + $Model + '","content":' + $content + ',"stop_reason":null,"usage":{"input_tokens":' + $In + ',"cache_creation_input_tokens":' + $Create + ',"cache_read_input_tokens":' + $Read + ',"cache_creation":{"ephemeral_1h_input_tokens":' + $Create + '},"output_tokens":' + $Out + ',"output_tokens_details":{"thinking_tokens":5},"iterations":[{"input_tokens":' + $In + ',"output_tokens":' + $Out + '}]}},"timestamp":"' + $Ts + '","sessionId":"s"}')
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("claude-usage-test-" + [Guid]::NewGuid().ToString("N"))
$proj = Join-Path $work "projects\D--Repos-x"
New-Item -ItemType Directory -Force -Path $proj | Out-Null
try {
    Write-Host "한 줄 읽기 (ConvertFrom-ClaudeUsageLine)"
    $l = ConvertFrom-ClaudeUsageLine (New-AssistantLine "msg_A1" "2026-10-16T05:36:14.653Z" "tool_use" 2 2804 531696 1622)
    Assert-Equal "응답 id·모델" "msg_A1|claude-sonnet-5-5" ("{0}|{1}" -f $l.Id, $l.Model)
    Assert-Equal "  토큰 4종(일반 입력 · 캐시 쓰기 · 캐시 읽기 · 출력)" "2|2804|531696|1622" ("{0}|{1}|{2}|{3}" -f $l.Input, $l.CacheCreate, $l.CacheRead, $l.Output)
    Assert-Equal "  시각은 UTC" "2026-10-16 05:36:14" $l.At.ToString("yyyy-MM-dd HH:mm:ss")
    Assert-Equal "  도구 입력 속 글자(\`"usage\`":{...)에 속지 않는다(진짜 usage 의 출력 1622)" 1622 $l.Output
    Assert-Equal "  assistant 가 아닌 줄은 건너뛴다" $true ($null -eq (ConvertFrom-ClaudeUsageLine '{"type":"user","message":{"role":"user","content":"hi"},"timestamp":"2026-10-16T05:00:00Z"}'))
    Assert-Equal "  usage 가 없으면 건너뛴다" $true ($null -eq (ConvertFrom-ClaudeUsageLine '{"type":"assistant","message":{"id":"msg_B","content":[]},"timestamp":"2026-10-16T05:00:00Z"}'))
    Assert-Equal "  깨진(쓰다 만) 줄도 오류 없이 건너뛴다" $true ($null -eq (ConvertFrom-ClaudeUsageLine '{"type":"assistant","message":{"id":"msg_C","usage":{"input_tokens":1'))
    Assert-Equal "  빈 줄" $true ($null -eq (ConvertFrom-ClaudeUsageLine ""))

    Write-Host "호출 목록 (Get-ClaudeUsageCalls): 응답 id 로 한 번씩, 시각 순"
    $sid = "11111111-2222-3333-4444-555555555555"
    $path = Join-Path $proj "$sid.jsonl"
    $lines = @(
        '{"type":"user","message":{"role":"user","content":"시작"},"timestamp":"2026-10-16T05:30:00.000Z"}',
        (New-AssistantLine "msg_A" "2026-10-16T05:30:05.100Z" "thinking" 3 1000 50000 400),
        (New-AssistantLine "msg_A" "2026-10-16T05:30:05.200Z" "text" 3 1000 50000 400),
        (New-AssistantLine "msg_A" "2026-10-16T05:30:09.000Z" "tool_use" 3 1000 50000 400),
        '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]},"timestamp":"2026-10-16T05:30:10.000Z"}',
        (New-AssistantLine "msg_B" "2026-10-16T05:36:14.653Z" "tool_use" 2 2804 531696 1622),
        (New-AssistantLine "msg_C" "2026-10-16T05:50:37.780Z" "text" 2 1854 577341 2130 "claude-opus-4-5")
    )
    [IO.File]::WriteAllLines($path, $lines, (New-Object System.Text.UTF8Encoding($false)))
    $calls = @(Get-ClaudeUsageCalls $path)
    Assert-Equal "줄 6개(assistant)가 응답 3개로" 3 $calls.Count
    Assert-Equal "  시각 순" "msg_A|msg_B|msg_C" (($calls | ForEach-Object { $_.Id }) -join "|")
    Assert-Equal "  응답의 시각은 마지막 블록이 끝난 시각" "05:30:09" $calls[0].At.ToString("HH:mm:ss")
    Assert-Equal "  응답마다 모델이 다를 수 있다" "claude-sonnet-5-5|claude-opus-4-5" ("{0}|{1}" -f $calls[1].Model, $calls[2].Model)
    Assert-Equal "  같은 응답 줄들의 출력은 한 번만 센다(400)" 400 $calls[0].Output
    $again = @(Get-ClaudeUsageCalls $path)
    Assert-Equal "  파일이 안 바뀌면 같은 목록을 돌려준다(캐시)" "3|3" ("{0}|{1}" -f $again.Count, @($script:ClaudeUsageCache[$path].Calls).Count)
    Add-Content -LiteralPath $path -Value (New-AssistantLine "msg_D" "2026-10-16T06:00:00.000Z" "text" 1 10 100 20) -Encoding UTF8
    Assert-Equal "  파일이 자라면 다시 읽어 새 호출이 들어온다" 4 @(Get-ClaudeUsageCalls $path).Count
    Assert-Equal "  없는 파일은 빈 목록" 0 @(Get-ClaudeUsageCalls (Join-Path $proj "nope.jsonl")).Count

    Write-Host "메시지 시각 바로 앞의 호출 (Find-ClaudeCallBefore)"
    $calls = @(Get-ClaudeUsageCalls $path)
    $u = Find-ClaudeCallBefore $calls ([datetime]::Parse("2026-10-16T05:36:16.568Z", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal))
    Assert-Equal "파일이 2초 뒤에 생겼으면 그 앞의 호출(msg_B 05:36:14)" "2026-10-16T05:36:14Z" $u.at
    Assert-Equal "  출력 + 새 입력(일반 2 + 캐시 쓰기 2804) = 앞에 보이는 값" "1622|2806|4428" ("{0}|{1}|{2}" -f $u.output, $u.newInput, $u.front)
    Assert-Equal "  맥락 = 새 입력 + 캐시에서 다시 읽은 입력" "531696|534502" ("{0}|{1}" -f $u.cacheRead, $u.context)
    Assert-Equal "  모델" "claude-sonnet-5-5" $u.model
    $t = [datetime]::Parse("2026-10-16T05:36:14.000Z", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
    Assert-Equal "시각이 호출 끝과 거의 같아도(2초 여유) 그 호출" "msg_B" ((Find-ClaudeCallBefore $calls $t) | ForEach-Object { if ($_.front -eq 4428) { "msg_B" } })
    Assert-Equal "그 호출 뒤에 시작한 호출은 쓰지 않는다(05:30:14 → msg_A: 출력 400 + 새 입력 3+1000)" 1403 (Find-ClaudeCallBefore $calls $t.AddMinutes(-5.9)).front
    Assert-Equal "첫 호출보다 앞선 시각은 없음" $true ($null -eq (Find-ClaudeCallBefore $calls ([datetime]::Parse("2026-10-16T05:00:00Z", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal))))
    Assert-Equal "가까운 호출이 3분보다 오래 전이면 없음(그 사이에 다른 일이 있었을 수 있다)" $true ($null -eq (Find-ClaudeCallBefore $calls $t.AddMinutes(5)))
    Assert-Equal "  창을 늘리면(600초) 찾는다" 4428 (Find-ClaudeCallBefore $calls $t.AddMinutes(5) 600).front
    Assert-Equal "빈 호출 목록" $true ($null -eq (Find-ClaudeCallBefore @() $t))

    Write-Host "기록 파일 찾기 (Get-ClaudeTranscriptPath)"
    Assert-Equal "세션 ID 로 프로젝트 폴더 아래 파일을 찾는다" $path (Get-ClaudeTranscriptPath $sid (Join-Path $work "projects"))
    Assert-Equal "  없는 세션" $true ($null -eq (Get-ClaudeTranscriptPath "99999999-0000-0000-0000-000000000000" (Join-Path $work "projects")))
    Assert-Equal "  경로 조작 문자가 든 ID 는 거절" $true (($null -eq (Get-ClaudeTranscriptPath "..\..\x" (Join-Path $work "projects"))) -and ($null -eq (Get-ClaudeTranscriptPath "a*" (Join-Path $work "projects"))))
    Assert-Equal "  빈 ID 와 너무 짧은 ID" $true (($null -eq (Get-ClaudeTranscriptPath "" (Join-Path $work "projects"))) -and ($null -eq (Get-ClaudeTranscriptPath "abc" (Join-Path $work "projects"))))
    Assert-Equal "  프로젝트 폴더가 없으면 null" $true ($null -eq (Get-ClaudeTranscriptPath $sid (Join-Path $work "nope")))
}
finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
