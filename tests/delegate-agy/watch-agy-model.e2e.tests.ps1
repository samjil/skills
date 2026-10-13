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
$quota = @($env:FAKE_QUOTA_MODELS -split ',' | Where-Object { $_ })
if ($quota -contains $model) { '{"status":"ERROR","error":"quota exceeded for model ' + $model + '"}' }
else { '{"status":"SUCCESS","response":"ok from ' + $model + '","conversation_id":"conv-test","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}' }
'@
Set-Content -Path (Join-Path $fakeBin "agy.cmd") -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake-agy.ps1`" %*"

$env:PATH = "$fakeBin;$env:PATH"
$env:AGY_HOME = Join-Path $work "agyhome"
$env:FAKE_ARGS_LOG = Join-Path $work "args.log"
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
