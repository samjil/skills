# agy 워처 SessionStart 훅(session-start-hook.ps1)과 등록기(register-session-hook.ps1) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\session-start-hook.tests.ps1
# 실패가 하나라도 있으면 종료 코드 1. 임시 폴더만 쓰고, 진짜 워처와 ~/.claude/settings.json 은 건드리지 않습니다
# (ensure-agy-running.ps1 자리에는 상태를 흉내 내는 가짜 스크립트를 넣습니다).

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sub = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub"
$hookScript = Join-Path $sub "session-start-hook.ps1"
$registerScript = Join-Path $sub "register-session-hook.ps1"

$script:Failed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("session-hook-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

try {
    Write-Host "SessionStart 훅 (session-start-hook.ps1)"
    # 가짜 ensure: -CheckOnly 면 환경변수 FAKE_STATE 를 그대로 출력하고, 아니면(기동 요청) 표시 파일을 남긴다.
    $fake = Join-Path $work "fake-ensure.ps1"
    $marker = Join-Path $work "started.txt"
    [IO.File]::WriteAllText($fake, @'
param([string]$RuntimeDir, [switch]$CheckOnly, [int]$StaleThresholdSeconds, [int]$ConfirmDelaySeconds)
if ($CheckOnly) { $env:FAKE_STATE; exit 0 }
Set-Content -LiteralPath (Join-Path (Split-Path $PSCommandPath -Parent) "started.txt") -Value "started"
'@, $utf8)

    function Invoke-Hook([string]$state) {
        $env:FAKE_STATE = $state
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        $out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hookScript -RuntimeDir $work -EnsureScript $fake 2>&1 | Out-String)
        for ($i = 0; $i -lt 20 -and $state -eq "DEAD" -and -not (Test-Path -LiteralPath $marker); $i++) { Start-Sleep -Milliseconds 250 }
        return @{ Out = $out; Code = $LASTEXITCODE; Started = (Test-Path -LiteralPath $marker) }
    }

    $r = Invoke-Hook "ALIVE"
    Assert-Equal "ALIVE 면 스킬 지시와 켜져 있음을 출력" $true (($r.Out -match "samjil-delegate-agy 스킬을 먼저") -and ($r.Out -match "켜져 있음"))
    Assert-Equal "  워처를 새로 켜지 않는다" $false $r.Started
    Assert-Equal "  종료 코드 0" 0 $r.Code

    $r = Invoke-Hook "DEAD"
    Assert-Equal "DEAD 면 켜는 중이라고 출력" $true ($r.Out -match "켜는 중")
    Assert-Equal "  백그라운드로 ensure 를 실행한다" $true $r.Started

    $r = Invoke-Hook "MANUAL_STOP"
    Assert-Equal "MANUAL_STOP 이면 켜지 않는다고 출력" $true ($r.Out -match "일부러 꺼 둔")
    Assert-Equal "  켜지 않는다" $false $r.Started

    $r = Invoke-Hook ""
    Assert-Equal "상태를 못 읽어도 스킬 지시는 출력하고 종료 코드 0" $true (($r.Out -match "samjil-delegate-agy 스킬을 먼저") -and ($r.Code -eq 0))
    Assert-Equal "  켜지 않는다" $false $r.Started

    $r = & {
        $env:FAKE_STATE = "ALIVE"
        $o = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hookScript -RuntimeDir $work -EnsureScript (Join-Path $work "없는파일.ps1") 2>&1 | Out-String)
        @{ Out = $o; Code = $LASTEXITCODE }
    }
    Assert-Equal "ensure 스크립트가 없으면 직접 처리 안내와 종료 코드 0" $true (($r.Out -match "확인하지 못했다") -and ($r.Code -eq 0))

    Write-Host "settings.json 등록기 (register-session-hook.ps1)"
    $settings = Join-Path $work "claude\settings.json"
    $hook = Join-Path $work "samjil\delegate-agy\scripts\sub\session-start-hook.ps1"
    function Invoke-Register([string[]]$Extra = @()) {
        $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        $o = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $registerScript -SettingsPath $settings -HookScript $hook @Extra 2>&1 | Out-String).Trim()
        $ErrorActionPreference = $prev
        return @{ Out = $o; Code = $LASTEXITCODE }
    }
    function Read-Settings { Get-Content -Raw -LiteralPath $settings -Encoding UTF8 | ConvertFrom-Json }

    $r = Invoke-Register
    Assert-Equal "설정 파일이 없으면 새로 만들며 ADDED" "ADDED|0" ("{0}|{1}" -f $r.Out, $r.Code)
    $h = (Read-Settings).hooks.SessionStart[0].hooks[0]
    Assert-Equal "  SessionStart 훅 한 개: type=command, timeout=30" "command|30" ("{0}|{1}" -f $h.type, $h.timeout)
    Assert-Equal "  명령은 슬래시 경로를 큰따옴표로 감싼 powershell -File" $true (($h.command -match '^powershell\.exe -NoProfile -ExecutionPolicy Bypass -File "') -and ($h.command -notmatch '\\') -and ($h.command -match 'session-start-hook\.ps1"$'))
    Assert-Equal "다시 실행하면 UNCHANGED (중복으로 넣지 않는다)" "UNCHANGED" (Invoke-Register).Out
    Assert-Equal "-Check 는 PRESENT" "PRESENT" (Invoke-Register @("-Check")).Out

    # 다른 설정·다른 훅은 보존한다
    $other = [pscustomobject]@{ theme = "dark"; hooks = [pscustomobject]@{ Stop = @([pscustomobject]@{ hooks = @([pscustomobject]@{ type = "command"; command = "echo stop" }) }) } }
    [IO.File]::WriteAllText($settings, ($other | ConvertTo-Json -Depth 10), $utf8)
    Assert-Equal "기존 Stop 훅이 있는 설정에도 ADDED" "ADDED" (Invoke-Register).Out
    $s = Read-Settings
    Assert-Equal "  Stop 훅과 theme 은 그대로" "echo stop|dark" ("{0}|{1}" -f $s.hooks.Stop[0].hooks[0].command, $s.theme)
    Assert-Equal "  백업 파일(.bak-*)을 남긴다" $true (@(Get-ChildItem (Split-Path $settings) -Filter "settings.json.bak-*").Count -ge 1)

    Assert-Equal "-Remove 는 REMOVED" "REMOVED" (Invoke-Register @("-Remove")).Out
    $s = Read-Settings
    Assert-Equal "  SessionStart 만 빠지고 Stop 훅은 남는다" "False|echo stop" ("{0}|{1}" -f [bool]$s.hooks.PSObject.Properties["SessionStart"], $s.hooks.Stop[0].hooks[0].command)
    Assert-Equal "  다시 -Remove 하면 NOTFOUND" "NOTFOUND" (Invoke-Register @("-Remove")).Out

    [IO.File]::WriteAllText($settings, "{ 깨진 json", $utf8)
    $r = Invoke-Register
    Assert-Equal "JSON 이 깨진 설정은 건드리지 않고 오류 종료" $true (($r.Code -ne 0) -and ((Get-Content -Raw -LiteralPath $settings -Encoding UTF8) -eq "{ 깨진 json"))
}
finally {
    Remove-Item Env:\FAKE_STATE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed -gt 0) { Write-Host "`n실패 $($script:Failed)건" -ForegroundColor Red; exit 1 }
Write-Host "`n모두 통과" -ForegroundColor Green
exit 0
