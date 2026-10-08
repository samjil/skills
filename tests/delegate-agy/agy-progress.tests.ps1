# agy-progress.ps1 의 판정 로직 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-progress.tests.ps1
# 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-progress.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

# 가짜 agy 폴더: conversations\<id>.db 와 brain\<id>\.system_generated\logs\transcript_full.jsonl
$home_ = Join-Path ([IO.Path]::GetTempPath()) ("agy-progress-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $home_ "conversations") | Out-Null
function New-FakeConversation($id, [datetime]$created, [datetime]$dbWritten, $transcriptWritten) {
    $db = Join-Path $home_ "conversations\$id.db"
    Set-Content -LiteralPath $db -Value "x"
    (Get-Item $db).CreationTime = $created
    (Get-Item $db).LastWriteTime = $dbWritten
    if ($transcriptWritten) {
        $dir = Join-Path $home_ "brain\$id\.system_generated\logs"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $tr = Join-Path $dir "transcript_full.jsonl"
        Set-Content -LiteralPath $tr -Value "{}"
        (Get-Item $tr).LastWriteTime = $transcriptWritten
    }
}

$t0 = [datetime]"2026-10-09 02:00:00"

Write-Host "Get-AgyConversationIdFromArgs"
Assert-Equal "--conversation 뒤의 값을 돌려준다" "abc-123" (Get-AgyConversationIdFromArgs @('-p', 'hi', '--conversation', 'abc-123', '--add-dir', 'D:\x'))
Assert-Equal "없으면 `$null" $true ($null -eq (Get-AgyConversationIdFromArgs @('-p', 'hi', '--model', 'm')))
Assert-Equal "마지막 인자가 --conversation 이면(값 없음) `$null" $true ($null -eq (Get-AgyConversationIdFromArgs @('-p', 'hi', '--conversation')))

Write-Host "Test-AgyStalled"
Assert-Equal "마지막 활동 6분 전, 기준 5분 -> 멈춤" $true (Test-AgyStalled $t0.AddMinutes(-6) $t0.AddMinutes(-20) $t0 300)
Assert-Equal "마지막 활동 1분 전 -> 멈춤 아님" $false (Test-AgyStalled $t0.AddMinutes(-1) $t0.AddMinutes(-20) $t0 300)
Assert-Equal "정확히 기준 시간(300초)이면 멈춤" $true (Test-AgyStalled $t0.AddSeconds(-300) $t0.AddMinutes(-20) $t0 300)
Assert-Equal "299초 전이면 멈춤 아님" $false (Test-AgyStalled $t0.AddSeconds(-299) $t0.AddMinutes(-20) $t0 300)
Assert-Equal "이어가기: 대화 파일이 시작보다 옛날이어도 시작 시각을 기준으로 센다(1분 경과 -> 멈춤 아님)" $false (Test-AgyStalled $t0.AddDays(-2) $t0.AddMinutes(-1) $t0 300)
Assert-Equal "활동 기록이 없으면 시작 시각 기준(6분 경과 -> 멈춤)" $true (Test-AgyStalled $null $t0.AddMinutes(-6) $t0 300)

Write-Host "Resolve-AgyConversation"
$missing = Join-Path $home_ "nope"
Assert-Equal "conversations 폴더가 없으면 unavailable" "unavailable" (Resolve-AgyConversation $missing $null $t0 120).State
Assert-Equal "새 대화가 없으면 none" "none" (Resolve-AgyConversation $home_ $null $t0 120).State

New-FakeConversation "old-before-start" $t0.AddMinutes(-30) $t0.AddMinutes(-29) $t0.AddMinutes(-29)
Assert-Equal "시작 전에 만들어진 대화는 무시 -> none" "none" (Resolve-AgyConversation $home_ $null $t0 120).State

New-FakeConversation "mine" $t0.AddSeconds(7) $t0.AddSeconds(30) $t0.AddSeconds(30)
$r = Resolve-AgyConversation $home_ $null $t0 120
Assert-Equal "시작 7초 뒤 생긴 대화 하나 -> found" "found" $r.State
Assert-Equal "  그 대화의 ID" "mine" $r.Id

New-FakeConversation "late-other" $t0.AddSeconds(300) $t0.AddSeconds(301) $t0.AddSeconds(301)
Assert-Equal "창(120초) 밖에서 생긴 대화는 무시 -> 여전히 found" "found" (Resolve-AgyConversation $home_ $null $t0 120).State

New-FakeConversation "other-in-window" $t0.AddSeconds(40) $t0.AddSeconds(41) $t0.AddSeconds(41)
Assert-Equal "창 안에 대화가 둘이면 어느 것인지 모르므로 ambiguous" "ambiguous" (Resolve-AgyConversation $home_ $null $t0 120).State

$k = Resolve-AgyConversation $home_ "known-id" $t0 120
Assert-Equal "이어가기(--conversation)는 ID를 이미 알므로 found" "found" $k.State
Assert-Equal "  그 ID" "known-id" $k.Id

Write-Host "Get-AgyConversationActivity"
$latest = Get-AgyConversationActivity $home_ "mine"
Assert-Equal "db 와 기록 파일 중 늦은 쪽(02:00:30)" ($t0.AddSeconds(30)).ToString("s") $latest.ToString("s")
New-FakeConversation "db-newer" $t0.AddSeconds(5) $t0.AddSeconds(90) $t0.AddSeconds(60)
Assert-Equal "db 쪽이 더 늦으면 db 시각(02:01:30)" ($t0.AddSeconds(90)).ToString("s") (Get-AgyConversationActivity $home_ "db-newer").ToString("s")
Assert-Equal "파일이 하나도 없으면 `$null" $true ($null -eq (Get-AgyConversationActivity $home_ "no-such-id"))

Write-Host "Get-DescendantProcessIdsByName"
# 실제 agy.exe 이름으로 보이게 powershell.exe 를 복사해 가짜 agy 를 만든다.
$fakeDir = Join-Path $home_ "fakebin"
New-Item -ItemType Directory -Force -Path $fakeDir | Out-Null
$fakeAgy = Join-Path $fakeDir "agy.exe"
Copy-Item -LiteralPath (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") -Destination $fakeAgy
$sleepArgs = @("-NoProfile", "-Command", "Start-Sleep 60")
# 내 자손: 이 테스트 프로세스가 직접 띄운다.
$mine = Start-Process -FilePath $fakeAgy -ArgumentList $sleepArgs -PassThru -WindowStyle Hidden
# 남의 것: WMI 가 띄우므로 부모가 이 테스트 프로세스가 아니다(사용자가 직접 띄운 agy 를 흉내).
$cmdLine = '"' + $fakeAgy + '" -NoProfile -Command "Start-Sleep 60"'
$created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine }
$theirsPid = [int]$created.ProcessId
Start-Sleep -Seconds 2
$found = @(Get-DescendantProcessIdsByName $PID "agy")
Assert-Equal "내가 띄운 agy 는 찾는다" $true ($found -contains $mine.Id)
Assert-Equal "부모가 다른 agy(남의 것)는 고르지 않는다" $false ($found -contains $theirsPid)
Assert-Equal "자손 agy 는 정확히 1개" 1 $found.Count
Assert-Equal "다른 이름은 찾지 않는다" 0 @(Get-DescendantProcessIdsByName $PID "no-such-process").Count

Write-Host "Stop-ProcessTree"
Stop-ProcessTree $mine.Id
Start-Sleep -Seconds 1
Assert-Equal "종료된다" $null (Get-Process -Id $mine.Id -ErrorAction SilentlyContinue)
Assert-Equal "남의 agy 는 영향받지 않는다" $true ($null -ne (Get-Process -Id $theirsPid -ErrorAction SilentlyContinue))
Stop-Process -Id $theirsPid -Force -ErrorAction SilentlyContinue

Remove-Item -LiteralPath $home_ -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
