# 뷰어의 대기 중 작업 목록(/api/delegate/pending)이 @cwd 여러 줄을 폴더 배열(cwd)로 돌려주는지 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\pending-cwd.tests.ps1
# 임시 런타임 폴더로 뷰어를 -NoAgent 로 실제로 띄웁니다(진짜 뷰어·워처·기록은 건드리지 않습니다. 몇 초).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$viewerScript = Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("pending-cwd-test-" + [Guid]::NewGuid().ToString("N"))
$rt = Join-Path $work "runtime"
foreach ($d in @("inbox", "outbox", "processed", "logs", "logs\data", "logs\heartbeat", "logs\sessions")) { New-Item -ItemType Directory -Force -Path (Join-Path $rt $d) | Out-Null }
New-Item -ItemType Directory -Force -Path (Join-Path $work "handoff") | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Put-Inbox([string]$name, [string]$text) { [System.IO.File]::WriteAllText((Join-Path $rt "inbox\$name.md"), $text, $utf8) }

Put-Inbox "t_two"   "@cwd: D:\a\repo`n@cwd: D:\b\docs`n@model: gemini-3.8-flash-low`n두 폴더 질문"
Put-Inbox "t_one"   "@cwd: D:\only`n한 폴더 질문"
Put-Inbox "t_none"  "폴더 없는 질문"
Put-Inbox "t_dup"   "@cwd: D:\Repo`n@cwd: d:\repo\`n@session: s1`n@cwd: D:\other`n중복이 섞인 질문"
Put-Inbox "t_late"  "첫 줄은 본문`n@cwd: D:\late"

$port = Get-Random -Minimum 30000 -Maximum 40000
$env:AGY_DELEGATE_RUNTIME = $rt
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

    $resp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/delegate/pending" -TimeoutSec 5
    $text = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    # 파이프(| ConvertFrom-Json)로 넘기면 5.1 에서 배열이 한 덩어리로 나오므로 -InputObject 로 받는다
    $parsed = ConvertFrom-Json -InputObject $text
    $items = @($parsed)
    $byId = @{}; foreach ($it in $items) { $byId[$it.task_id] = $it }
    Assert-Equal "대기 중 작업이 5건 보인다" 5 $items.Count

    Write-Host "cwd 는 폴더 배열이다"
    Assert-Equal "@cwd 두 줄: 줄 순서대로 두 폴더" "D:\a\repo|D:\b\docs" (@($byId["t_two"].cwd) -join "|")
    Assert-Equal "  모델 지시어도 함께 읽힌다" "gemini-3.8-flash-low" $byId["t_two"].model
    Assert-Equal "  질문 본문에는 지시어 줄이 없다" "두 폴더 질문" $byId["t_two"].question
    Assert-Equal "@cwd 한 줄: 폴더 하나(배열)" "D:\only|1" ("{0}|{1}" -f (@($byId["t_one"].cwd) -join "|"), @($byId["t_one"].cwd).Count)
    Assert-Equal "@cwd 없음: 빈 배열" 0 @($byId["t_none"].cwd).Count
    Assert-Equal "중복(대소문자·끝의 \)은 한 번만, 사이에 다른 지시어가 껴 있어도 순서대로" "D:\Repo|D:\other" (@($byId["t_dup"].cwd) -join "|")
    Assert-Equal "  세션 이름도 읽힌다" "s1" $byId["t_dup"].session
    Assert-Equal "본문이 시작된 뒤의 @cwd 는 폴더가 아니다" 0 @($byId["t_late"].cwd).Count

    Write-Host "JSON 모양(예전 화면 코드도 읽을 수 있어야 한다)"
    Assert-Equal "한 폴더도 JSON 배열(cwd 값이 대괄호)로 나간다" $true ($text -match '"cwd":\s*\[\s*"D:\\\\only"\s*\]')
    Assert-Equal "폴더가 없으면 빈 배열([])" $true ($text -match '"task_id":\s*"t_none"[\s\S]*?"cwd":\s*\[\s*\]')
}
finally {
    if ($viewer -and -not $viewer.HasExited) { Stop-Process -Id $viewer.Id -Force -ErrorAction SilentlyContinue }
    $env:AGY_DELEGATE_RUNTIME = $null
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
