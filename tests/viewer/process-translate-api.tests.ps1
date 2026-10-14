# 뷰어의 과정 번역(Get-ProcessTranslationState, Start-ProcessTranslation) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\process-translate-api.tests.ps1
# serve-viewer.ps1 에서 함수 정의만 꺼내 오고(서버 본체는 실행하지 않음), 가짜 agy(agy.cmd, PATH 맨 앞)와 임시 폴더만 씁니다.
# 번역은 실제로 숨김 창의 보조 스크립트(process-translate.ps1)를 띄워서 끝날 때까지 기다립니다(몇 초).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$scriptsDir = Join-Path $repoRoot "runtime\delegate-agy\scripts"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("process-translate-api-test-" + [Guid]::NewGuid().ToString("N"))
$DataDir = Join-Path $work "data"
$agyHome = Join-Path $work "agyhome"
$fakeBin = Join-Path $work "bin"
New-Item -ItemType Directory -Force -Path $DataDir, $agyHome, $fakeBin | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

. (Join-Path $scriptsDir "sub\agy-progress.ps1")
. (Join-Path $scriptsDir "sub\process-translate.ps1")

$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"), [ref]$tokens, [ref]$errs)
$script:ProcessCache = @{}
$script:TranslateStaleSeconds = 360
# Find-DelegateScript 는 $PSScriptRoot 를 써서(꺼내 온 함수에는 파일이 없어 비어 있다) 환경변수 AGY_DELEGATE_SCRIPTS 만 보는 간단한 것으로 바꿔 쓴다.
function Find-DelegateScript([string]$RelPath) {
    $c = Join-Path $env:AGY_DELEGATE_SCRIPTS $RelPath
    if (Test-Path -LiteralPath $c) { return $c }
    return $null
}
foreach ($name in @("Get-AgyProcessStepsCached", "Get-ProcessTranslationPath", "Get-ProcessTranslationState", "Start-ProcessTranslation")) {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name 를 serve-viewer.ps1 에서 찾지 못했습니다." }
    Invoke-Expression $fn.Extent.Text
}
$env:AGY_DELEGATE_SCRIPTS = $scriptsDir
$env:AGY_HOME = $agyHome

Set-Content -Path (Join-Path $fakeBin "fake-agy.ps1") -Encoding ASCII -Value @'
$a = @($args)
Add-Content -Path $env:FAKE_ARGS_LOG -Value "call"
$pf = ([string]$a[1]).Substring(1)
$text = [System.IO.File]::ReadAllText($pf, [System.Text.Encoding]::UTF8)
$line = ($text -split "`n" | Where-Object { $_.Trim().StartsWith('[') } | Select-Object -Last 1)
$in = ConvertFrom-Json -InputObject $line
$out = foreach ($it in @($in)) {
    $o = [ordered]@{ i = $it.i }
    foreach ($f in 'label', 'think', 'say') { if ($it.PSObject.Properties[$f]) { $o[$f] = 'KO:' + $it.$f } }
    $o
}
$resp = ConvertTo-Json -InputObject @($out) -Compress
'{"status":"SUCCESS","response":' + (ConvertTo-Json -InputObject $resp) + ',"conversation_id":"tr-conv"}'
'@
Set-Content -Path (Join-Path $fakeBin "agy.cmd") -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake-agy.ps1`" %*"
$env:PATH = "$fakeBin;$env:PATH"
$env:FAKE_ARGS_LOG = Join-Path $work "args.log"

function J($o) { return ($o | ConvertTo-Json -Compress -Depth 8) }
function New-Transcript([string]$id, [string[]]$thinkings) {
    $dir = Join-Path $agyHome "brain\$id\.system_generated\logs"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $n = 1; $lines = @()
    foreach ($t in $thinkings) {
        $lines += (J ([ordered]@{ step_index = $n; type = "PLANNER_RESPONSE"; created_at = "2026-10-13T07:48:57Z"; thinking = $t; tool_calls = @(@{ name = "view_file"; args = @{ AbsolutePath = "C:\f$n.md"; toolAction = "Reading f$n" } }) }))
        $n += 2
    }
    [System.IO.File]::WriteAllText((Join-Path $dir "transcript_full.jsonl"), (($lines -join "`n") + "`n"), $utf8)
    return (Join-Path $dir "transcript_full.jsonl")
}
function Wait-State([string]$id, [string]$want, [int]$seconds = 60) {
    for ($i = 0; $i -lt ($seconds * 2); $i++) {
        $s = Get-ProcessTranslationState $id
        if ($s.state -ne $want) { return $s }
        Start-Sleep -Milliseconds 500
    }
    return (Get-ProcessTranslationState $id)
}

Write-Host "대화 id 검사"
Assert-Equal "경로 문자가 든 id 는 null" $true ($null -eq (Get-ProcessTranslationState "..\x"))
Assert-Equal "  Start 도 null" $true ($null -eq (Start-ProcessTranslation "a/b"))
Assert-Equal "  빈 id 도 null" $true ($null -eq (Get-ProcessTranslationState ""))
Assert-Equal "캐시 경로는 데이터 폴더의 process-ko 아래" (Join-Path $DataDir "process-ko\abc-1.json") (Get-ProcessTranslationPath "abc-1")

Write-Host "대화 기록이 없을 때"
$s0 = Get-ProcessTranslationState "conv-none"
Assert-Equal "대화 기록도 캐시도 없으면 unavailable" "unavailable" $s0.state
Assert-Equal "  Start 해도 시작하지 않는다(agy 를 부르지 않음)" "unavailable" (Start-ProcessTranslation "conv-none").state
Assert-Equal "  agy 를 부른 적이 없다" $false (Test-Path $env:FAKE_ARGS_LOG)

Write-Host "번역하기: 시작 -> running -> done"
$tp1 = New-Transcript "conv-a" @("Read the spec first.", "Write the code next.")
Assert-Equal "아직 안 했으면 none" "none" (Get-ProcessTranslationState "conv-a").state
$st = Start-ProcessTranslation "conv-a"
Assert-Equal "Start 는 바로 running 을 돌려준다" "running" $st.state
$final = Wait-State "conv-a" "running" 90
Assert-Equal "끝나면 done" "done" $final.state
Assert-Equal "  번역해 둔 것이 함께 온다(0번째 생각·라벨)" "KO:Read the spec first.|KO:Reading f1" ("{0}|{1}" -f $final.items["0"].think, $final.items["0"].label)
Assert-Equal "  1번째도" "KO:Write the code next." $final.items["1"].think
Assert-Equal "  agy 는 한 번 불렀다" 1 @(Get-Content -LiteralPath $env:FAKE_ARGS_LOG).Count
Assert-Equal "  표시 파일이 남지 않는다" $false (Test-Path ((Get-ProcessTranslationPath "conv-a") + ".running"))

Write-Host "다시 요청하면 캐시"
$again = Start-ProcessTranslation "conv-a"
Assert-Equal "이미 끝났으면 done 을 돌려주고 시작하지 않는다" "done" $again.state
Start-Sleep -Seconds 2
Assert-Equal "  agy 를 또 부르지 않았다" 1 @(Get-Content -LiteralPath $env:FAKE_ARGS_LOG).Count

Write-Host "진행 중인 대화에 단계가 늘면"
$script:ProcessCache = @{}
$line3 = J ([ordered]@{ step_index = 5; type = "PLANNER_RESPONSE"; created_at = "2026-10-13T07:49:57Z"; thinking = "Finish up."; tool_calls = @(@{ name = "view_file"; args = @{ AbsolutePath = "C:\f5.md"; toolAction = "Reading f5" } }) })
[System.IO.File]::AppendAllText($tp1, $line3 + "`n", $utf8)
Assert-Equal "새 단계가 생기면 none(번역해 둔 것은 그대로 items 에 있다)" "none|2" ("{0}|{1}" -f (Get-ProcessTranslationState "conv-a").state, (Get-ProcessTranslationState "conv-a").items.Count)
Assert-Equal "  Start 하면 running" "running" (Start-ProcessTranslation "conv-a").state
$final2 = Wait-State "conv-a" "running" 90
Assert-Equal "  끝나면 done, 새 단계(2번째)도 번역" "done|KO:Finish up." ("{0}|{1}" -f $final2.state, $final2.items["2"].think)
Assert-Equal "  agy 는 새 단계 때문에 한 번 더 불렀다" 2 @(Get-Content -LiteralPath $env:FAKE_ARGS_LOG).Count

Write-Host "번역 규칙이 바뀌어 예전에 건너뛴 칸이 생기면(인용문 안의 한글은 한글로 세지 않는다)"
[void](New-Transcript "conv-q" @("Examined the ``04_문진 이벤트 로그.sql`` file and compared the event names."))
$cq = Get-ProcessTranslationPath "conv-q"
# 예전 규칙으로 끝낸 캐시를 흉내 낸다: 단계 수는 다 덮었지만 그 칸은 한글이 있다고 건너뛰어 번역이 비어 있다
Write-TranslationCache $cq "done" "" 1 @{} "m"
$callsQ = @(Get-Content -LiteralPath $env:FAKE_ARGS_LOG).Count
Assert-Equal "끝난 캐시여도 번역할 칸이 남아 있으면 none" "none" (Get-ProcessTranslationState "conv-q").state
Assert-Equal "  Start 하면 running" "running" (Start-ProcessTranslation "conv-q").state
$finalQ = Wait-State "conv-q" "running" 90
Assert-Equal "  끝나면 done, 한글 인용문이 든 생각이 번역된다" "done|True" ("{0}|{1}" -f $finalQ.state, ($finalQ.items["0"].think -like "KO:Examined the*"))
Assert-Equal "  agy 를 한 번 불렀다" ($callsQ + 1) @(Get-Content -LiteralPath $env:FAKE_ARGS_LOG).Count
Assert-Equal "  번역을 마치면 더는 남은 칸이 없어 done 이 유지된다" "done" (Get-ProcessTranslationState "conv-q").state

Write-Host "대화 기록이 정리된 뒤에도 번역은 남는다"
Remove-Item -LiteralPath (Join-Path $agyHome "brain\conv-a") -Recurse -Force
$script:ProcessCache = @{}
$kept = Get-ProcessTranslationState "conv-a"
Assert-Equal "번역해 둔 것이 있으면 done(items 3개)" "done|3" ("{0}|{1}" -f $kept.state, $kept.items.Count)

Write-Host "실패와 멈춘 표시 파일"
[void](New-Transcript "conv-b" @("Think b."))
$cb = Get-ProcessTranslationPath "conv-b"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cb) | Out-Null
Write-TranslationCache $cb "error" "agy 번역 호출이 170 초를 넘겨 중단했습니다" 0 @{} "m"
$eb = Get-ProcessTranslationState "conv-b"
Assert-Equal "이전에 실패했으면 error 와 이유" "error|agy 번역 호출이 170 초를 넘겨 중단했습니다" ("{0}|{1}" -f $eb.state, $eb.message)
Write-TranslationCache $cb "partial" "" 0 @{ "0" = @{ think = "일부" } } "m"
$pb = Get-ProcessTranslationState "conv-b"
Assert-Equal "중간에 멈춘 partial 은 error(이어서 하라는 안내)" "error|True" ("{0}|{1}" -f $pb.state, ($pb.message -like "*이어서*"))
Assert-Equal "  그래도 번역된 일부는 준다" "일부" $pb.items["0"].think
[System.IO.File]::WriteAllText("$cb.running", '{"pid":1}', $utf8)
Assert-Equal "새 표시 파일이 있으면 running" "running" (Get-ProcessTranslationState "conv-b").state
(Get-Item "$cb.running").LastWriteTime = (Get-Date).AddMinutes(-10)
Assert-Equal "10분 지난 표시 파일은 죽은 것으로 본다(running 이 아님)" "error" (Get-ProcessTranslationState "conv-b").state
Remove-Item "$cb.running" -Force
Assert-Equal "error 상태에서 Start 하면 다시 시작(running)" "running" (Start-ProcessTranslation "conv-b").state
$fb = Wait-State "conv-b" "running" 90
Assert-Equal "  끝나면 done" "done" $fb.state

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
