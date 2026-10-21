# sync-installed.ps1(소스 -> 설치본 동기화)의 동작을 임시 폴더로 확인한다. 이 PC 의 실제 ~/.samjil 은 건드리지 않는다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\repo\sync-installed.tests.ps1

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script = Join-Path $repoRoot "sync-installed.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("sync-installed-test-" + [Guid]::NewGuid().ToString("N"))
$src = Join-Path $work "src"; $inst = Join-Path $work "installed"; $agents = Join-Path $work "agents"
function W([string]$path, [string]$text) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}
function Run-Sync([string[]]$extra = @()) {
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script, "-SourceRoot", $src, "-InstallRoot", $inst, "-AgentsSkillsRoot", $agents) + $extra
    # 출력을 UTF-8 로 직접 읽는다. PowerShell 의 기본 캡처는 콘솔 코드페이지를 따라서, 콘솔이 없는 환경(run-all.ps1 이 창 없이 띄운 시험)에서는
    # 스크립트가 UTF-8 로 쓴 한글을 다른 코드페이지로 읽어 한글 문구 확인이 어긋난다(전체 실행에서만 4건 실패해서 알았다).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = (@($a | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
    try { $p.StandardInput.Close() } catch {}
    $p.WaitForExit()
    $text = [string]$outTask.Result + [string]$errTask.Result
    $code = $p.ExitCode
    $p.Dispose()
    return @{ Code = $code; Out = $text }
}

# 소스 트리(작게): 워처 스크립트, 뷰어 본체·화면 파일, 스킬 문서
W (Join-Path $src "runtime\delegate-agy\scripts\start-agy.ps1") "start v1"
W (Join-Path $src "runtime\delegate-agy\scripts\sub\watch-agy.ps1") "watch v1"
W (Join-Path $src "runtime\delegate-agy\scripts\sub\agy-db.ps1") "db v1"
W (Join-Path $src "runtime\viewer\serve-viewer.ps1") "serve v1"
W (Join-Path $src "runtime\viewer\web\app.js") "app v1"
W (Join-Path $src "runtime\handoff\templates\t.md") "tpl v1"
W (Join-Path $src "runtime\handoff\scripts\handoff-lib.ps1") "lib v1"
W (Join-Path $src "runtime\handoff\scripts\handoff-stop-hook.ps1") "hook v1"
W (Join-Path $src "samjil-delegate-agy\SKILL.md") "skill v1"
# 설치본에는 살아 있는 운영 데이터가 있다: 건드리면 안 된다
W (Join-Path $inst "delegate-agy\runtime\logs\usage.csv") "LIVE DATA"
W (Join-Path $inst "handoff\some-project\0001.md") "LIVE HANDOFF"
W (Join-Path $inst "viewer\out.log") "viewer log"

Write-Host "처음: 설치본이 비어 있으면 모두 새 파일로 복사한다"
$r = Run-Sync
Assert-Equal "  종료 코드 0" 0 $r.Code
Assert-Equal "  워처 스크립트가 복사됐다" "watch v1" ([System.IO.File]::ReadAllText((Join-Path $inst "delegate-agy\scripts\sub\watch-agy.ps1")))
Assert-Equal "  뷰어 화면 파일이 복사됐다" "app v1" ([System.IO.File]::ReadAllText((Join-Path $inst "viewer\web\app.js")))
Assert-Equal "  handoff 템플릿이 복사됐다" "tpl v1" ([System.IO.File]::ReadAllText((Join-Path $inst "handoff\templates\t.md")))
Assert-Equal "  handoff 스크립트(라이브러리·Stop 훅)가 ~/.samjil/handoff/scripts 로 복사됐다" "lib v1|hook v1" (([System.IO.File]::ReadAllText((Join-Path $inst "handoff\scripts\handoff-lib.ps1"))) + "|" + ([System.IO.File]::ReadAllText((Join-Path $inst "handoff\scripts\handoff-stop-hook.ps1"))))
Assert-Equal "  스킬 문서가 ~/.agents/skills 로 복사됐다" "skill v1" ([System.IO.File]::ReadAllText((Join-Path $agents "samjil-delegate-agy\SKILL.md")))
Assert-Equal "  운영 데이터(usage.csv)는 그대로다" "LIVE DATA" ([System.IO.File]::ReadAllText((Join-Path $inst "delegate-agy\runtime\logs\usage.csv")))
Assert-Equal "  handoff 대화 기록은 그대로다" "LIVE HANDOFF" ([System.IO.File]::ReadAllText((Join-Path $inst "handoff\some-project\0001.md")))

Write-Host "같으면 아무것도 복사하지 않는다"
$r = Run-Sync
Assert-Equal "  종료 코드 0" 0 $r.Code
Assert-Equal "  '설치본이 소스와 같습니다' 를 알린다" $true ($r.Out -like "*설치본이 소스와 같습니다*")

Write-Host "소스를 고치면 -Check 는 어긋남을 알리고(종료 코드 1) 복사하지 않는다"
W (Join-Path $src "runtime\viewer\web\app.js") "app v2"
$r = Run-Sync @("-Check")
Assert-Equal "  종료 코드 1" 1 $r.Code
Assert-Equal "  어긋난 파일 이름을 알린다" $true ($r.Out -like "*web\app.js*")
Assert-Equal "  -Check 는 복사하지 않는다" "app v1" ([System.IO.File]::ReadAllText((Join-Path $inst "viewer\web\app.js")))

Write-Host "바뀐 파일만 복사한다"
W (Join-Path $src "runtime\delegate-agy\scripts\sub\watch-agy.ps1") "watch v2"
$r = Run-Sync
Assert-Equal "  종료 코드 0" 0 $r.Code
Assert-Equal "  app.js 가 복사됐다" "app v2" ([System.IO.File]::ReadAllText((Join-Path $inst "viewer\web\app.js")))
Assert-Equal "  watch-agy.ps1 이 복사됐다" "watch v2" ([System.IO.File]::ReadAllText((Join-Path $inst "delegate-agy\scripts\sub\watch-agy.ps1")))
Assert-Equal "  '어긋난 파일 2개' 로 알린다(바뀌지 않은 파일은 세지 않는다)" $true ($r.Out -like "*어긋난 파일 2개*")
Assert-Equal "  화면 파일은 재시작이 필요 없다(뷰어 재시작 안내 없음)" $false ($r.Out -like "*뷰어 본체 스크립트가 바뀌었습니다*")

Write-Host "뷰어 본체 스크립트가 바뀌면 재시작 안내를 한다"
W (Join-Path $src "runtime\viewer\serve-viewer.ps1") "serve v2"
$r = Run-Sync
Assert-Equal "  뷰어 재시작 안내가 있다" $true ($r.Out -like "*뷰어 본체 스크립트가 바뀌었습니다*")

Write-Host "handoff-lib.ps1 이 바뀌면 워처 재시작을 알리고, Stop 훅만 바뀌면 알리지 않는다(워처는 켜질 때 라이브러리를 읽어 올린다)"
W (Join-Path $src "runtime\handoff\scripts\handoff-stop-hook.ps1") "hook v2"
$r = Run-Sync
Assert-Equal "  훅 스크립트만 바뀌면 워처 재시작 안내가 없다" $false ($r.Out -like "*워처 스크립트가 바뀌었*")
W (Join-Path $src "runtime\handoff\scripts\handoff-lib.ps1") "lib v2"
$r = Run-Sync
Assert-Equal "  handoff-lib.ps1 이 바뀌면 워처 재시작 안내가 있다" $true ($r.Out -like "*워처 스크립트가 바뀌었*")
Assert-Equal "  handoff-lib.ps1 이 바뀌면 뷰어 재시작 안내도 있다(뷰어도 켜질 때 라이브러리를 읽는다)" $true ($r.Out -like "*뷰어 본체 스크립트가 바뀌었습니다*")

Write-Host "agy-db.ps1 이 바뀌면 워처와 뷰어 재시작을 둘 다 알린다(둘 다 켜질 때 DB 모듈을 읽어 올린다)"
W (Join-Path $src "runtime\delegate-agy\scripts\sub\agy-db.ps1") "db v2"
$r = Run-Sync
Assert-Equal "  워처 재시작 안내가 있다" $true ($r.Out -like "*워처 스크립트가 바뀌었*")
Assert-Equal "  뷰어 재시작 안내도 있다" $true ($r.Out -like "*뷰어 본체 스크립트가 바뀌었습니다*")
Write-Host "소스에서 지운 파일은 설치본에 남기고 알리기만 한다"
Remove-Item -LiteralPath (Join-Path $src "runtime\handoff\templates\t.md") -Force
$r = Run-Sync
Assert-Equal "  설치본에 파일이 남아 있다" $true (Test-Path (Join-Path $inst "handoff\templates\t.md"))
Assert-Equal "  '설치본에만 있는 파일' 로 알린다" $true ($r.Out -like "*설치본에만 있는 파일*t.md*")
Assert-Equal "  .log 파일은 설치본에만 있어도 알리지 않는다" $false ($r.Out -like "*out.log*")

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
