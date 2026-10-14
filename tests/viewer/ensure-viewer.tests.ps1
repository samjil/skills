# ensure-viewer-running.ps1 (뷰어를 콘솔 창·브라우저 탭 없이 백그라운드로 켜기) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\ensure-viewer.tests.ps1
# 임시 포트(38792, 38793)와 임시 폴더에서 뷰어를 -NoAgent 로 실제로 띄워 봅니다(진짜 뷰어·워처에는 손대지 않습니다. 약 20초).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ensure = Join-Path $repoRoot "runtime\viewer\ensure-viewer-running.ps1"
$startAgy = Join-Path $repoRoot "runtime\delegate-agy\scripts\start-agy.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

. $ensure   # 인자 없이 점(.)으로 불러서 함수만 정의한다

# 보이는 터미널/콘솔 창을 실제로 센다. Windows Terminal 이 콘솔을 호스팅하면 그 창은 WindowsTerminal.exe 의 것이라
# 파워셸 프로세스의 MainWindowHandle 이 0 으로 나와서(창이 떠 있는데도) 그 값은 "창 없음"의 증거가 되지 못한다.
if (-not ("WinEnumTest" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class WinEnumTest {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    public static List<string> Visible() {
        var list = new List<string>();
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h)) return true;
            var c = new StringBuilder(256); GetClassName(h, c, 256);
            var t = new StringBuilder(256); GetWindowText(h, t, 256);
            string cls = c.ToString();
            if (cls == "CASCADIA_HOSTING_WINDOW_CLASS" || cls == "ConsoleWindowClass") list.Add(h.ToInt64() + "|" + cls + "|" + t);
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@
}
function Get-VisibleConsoleWindows { return @([WinEnumTest]::Visible()) }

$work = Join-Path ([IO.Path]::GetTempPath()) ("ensure-viewer-test-" + [Guid]::NewGuid().ToString("N"))
$dataDir = Join-Path $work "data"; $handoffDir = Join-Path $work "handoff"
New-Item -ItemType Directory -Force -Path $dataDir, $handoffDir | Out-Null
$port = 38792
$realAlive = Test-ViewerAlive 8787   # 진짜 뷰어가 떠 있었는지(시험 뒤에도 그대로여야 한다)

Write-Host "함수"
$cmd = Get-ViewerLaunchCommand "C:\v\serve-viewer.ps1" 9000 ""
Assert-Equal "브라우저 탭을 열지 않는다(-NoBrowser)" $true ($cmd -match ' -NoBrowser')
Assert-Equal "  포트를 넘긴다" $true ($cmd -match '-Port 9000')
Assert-Equal "  콘솔을 만들지 않는 실행(powershell.exe -NoLogo -NoProfile)" $true ($cmd -like 'powershell.exe -NoLogo -NoProfile *')
Assert-Equal "  -NoAgent 는 기본으로 붙지 않는다(뷰어가 워처도 켜야 한다)" $false ($cmd -match 'NoAgent')
$cmd2 = Get-ViewerLaunchCommand "C:\v w\serve-viewer.ps1" 9000 '-NoAgent -DataDir "C:\a b\data"'
Assert-Equal "추가 인자 문자열은 명령줄 뒤에 그대로 붙는다" $true ($cmd2 -match '-Port 9000 -NoAgent -DataDir "C:\\a b\\data"$')
Assert-Equal "  공백이 든 스크립트 경로도 따옴표로 감싼다" $true ($cmd2 -match '-File "C:\\v w\\serve-viewer\.ps1"')
Assert-Equal "기본 포트(8787)의 뷰어: -Port 가 없는 명령줄" $true (Test-ViewerCommandLineForPort 'powershell -NoProfile -File "x\serve-viewer.ps1" -NoBrowser' 8787)
Assert-Equal "  다른 포트에는 해당하지 않는다" $false (Test-ViewerCommandLineForPort 'powershell -NoProfile -File "x\serve-viewer.ps1" -NoBrowser' 9000)
Assert-Equal "-Port 9000 인 뷰어는 9000 의 것" $true (Test-ViewerCommandLineForPort 'powershell -File x\serve-viewer.ps1 -Port 9000' 9000)
Assert-Equal "  8787 의 것이 아니다(진짜 뷰어를 끄지 않는다)" $false (Test-ViewerCommandLineForPort 'powershell -File x\serve-viewer.ps1 -Port 9000' 8787)
Assert-Equal "  90001 같은 비슷한 번호와 헷갈리지 않는다" $false (Test-ViewerCommandLineForPort 'powershell -File x\serve-viewer.ps1 -Port 90001' 9000)
Assert-Equal "명령줄이 비어 있으면 해당 없음" $false (Test-ViewerCommandLineForPort "" 8787)

Write-Host "꺼져 있을 때"
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensure -Port $port -CheckOnly
Assert-Equal "-CheckOnly 는 DEAD(종료 코드 1)" "DEAD|1" ("{0}|{1}" -f (($out | Out-String).Trim()), $LASTEXITCODE)
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensure -Port $port -Stop
Assert-Equal "-Stop 인데 떠 있는 것이 없으면 NONE(0)" "NONE|0" ("{0}|{1}" -f (($out | Out-String).Trim()), $LASTEXITCODE)

Write-Host "다른 프로그램이 그 포트를 쓰고 있을 때"
$port2 = 38793
$job = Start-Job -ScriptBlock {
    param($p)
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://127.0.0.1:$p/")
    $l.Start()
    for ($i = 0; $i -lt 6; $i++) {
        $c = $l.GetContext()
        $b = [System.Text.Encoding]::UTF8.GetBytes('{"x":1}')
        $c.Response.ContentType = "application/json"; $c.Response.OutputStream.Write($b, 0, $b.Length); $c.Response.Close()
    }
    $l.Stop()
} -ArgumentList $port2
Start-Sleep -Seconds 2
Assert-Equal "200 JSON 을 주지만 watcherAlive 가 없으면 우리 뷰어가 아니다(DEAD)" $false (Test-ViewerAlive $port2)
Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue

Write-Host "창 없이 켜기"
$q = [char]34
$viewerArgs = "-NoAgent -DataDir $q$dataDir$q -HandoffDir $q$handoffDir$q"
$winsBefore = Get-VisibleConsoleWindows
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensure -Port $port -ViewerArgs $viewerArgs
Assert-Equal "꺼져 있으면 켜고 STARTED(0)" "STARTED|0" ("{0}|{1}" -f (($out | Out-String).Trim()), $LASTEXITCODE)
Assert-Equal "  응답한다(/api/status)" $true (Test-ViewerAlive $port)
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'serve-viewer\.ps1' -and $_.CommandLine -match "-Port $port" })
Assert-Equal "  뷰어 프로세스가 하나 떠 있다" 1 $procs.Count
if ($procs.Count -eq 1) {
    Start-Sleep -Seconds 2
    $newWins = @(Get-VisibleConsoleWindows | Where-Object { $winsBefore -notcontains $_ })
    Assert-Equal "  새로 보이는 터미널/콘솔 창이 없다(실제 창 수를 센다)" 0 $newWins.Count
    Assert-Equal "  브라우저 탭을 열지 않는 인자(-NoBrowser)로 떴다" $true ($procs[0].CommandLine -match '-NoBrowser')
}
Assert-Equal "  뷰어에 시험용 데이터 폴더와 -NoAgent 가 실제로 넘어갔다" $true ($procs.Count -eq 1 -and $procs[0].CommandLine.Contains($dataDir) -and $procs[0].CommandLine -match '-NoAgent')
$cmdWindows = @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" | Where-Object { $_.CommandLine -match "serve-viewer" -and $_.CommandLine -match "-Port $port" })
Assert-Equal "  cmd 창(serve-viewer.bat)을 거치지 않았다" 0 $cmdWindows.Count

$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensure -Port $port -ViewerArgs $viewerArgs
Assert-Equal "이미 떠 있으면 ALIVE(0)이고 또 켜지 않는다" "ALIVE|0" ("{0}|{1}" -f (($out | Out-String).Trim()), $LASTEXITCODE)
$procs2 = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'serve-viewer\.ps1' -and $_.CommandLine -match "-Port $port" })
Assert-Equal "  뷰어 프로세스는 여전히 하나" 1 $procs2.Count
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensure -Port $port -CheckOnly
Assert-Equal "-CheckOnly 는 ALIVE(0)" "ALIVE|0" ("{0}|{1}" -f (($out | Out-String).Trim()), $LASTEXITCODE)

Write-Host "끄기(-Stop)"
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensure -Port $port -Stop
Assert-Equal "-Stop 은 STOPPED(0)" "STOPPED|0" ("{0}|{1}" -f (($out | Out-String).Trim()), $LASTEXITCODE)
Start-Sleep -Seconds 1
Assert-Equal "  그 뒤로 응답하지 않는다" $false (Test-ViewerAlive $port)
Assert-Equal "  진짜 뷰어(8787)는 시험 전과 같은 상태다(건드리지 않았다)" $realAlive (Test-ViewerAlive 8787)

Write-Host "뷰어와 워처가 둘 다 꺼져 있을 때: 한 번에 켜지고 창이 뜨지 않는다"
$work2 = Join-Path ([IO.Path]::GetTempPath()) ("ensure-viewer-both-" + [Guid]::NewGuid().ToString("N"))
$rt = Join-Path $work2 "runtime"
foreach ($d in @("inbox", "outbox", "processed", "logs", "logs\data", "logs\heartbeat")) { New-Item -ItemType Directory -Force -Path (Join-Path $rt $d) | Out-Null }
New-Item -ItemType Directory -Force -Path (Join-Path $work2 "handoff") | Out-Null
$port3 = 38795
$env:AGY_DELEGATE_RUNTIME = $rt   # 뷰어가 켜는 워처도 이 임시 런타임을 쓴다(진짜 워처는 건드리지 않는다)
$q = [char]34
$winsBefore2 = Get-VisibleConsoleWindows
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensure -Port $port3 -ViewerArgs "-DataDir $q$(Join-Path $rt 'logs\data')$q -HandoffDir $q$(Join-Path $work2 'handoff')$q"
Assert-Equal "-NoAgent 없이 켜면 STARTED(0)" "STARTED|0" ("{0}|{1}" -f (($out | Out-String).Trim()), $LASTEXITCODE)
$lockFile = Join-Path $rt ("logs\watcher_{0}.lock" -f $env:COMPUTERNAME)
$lockUp = $false
for ($i = 0; $i -lt 90 -and -not $lockUp; $i++) { if (Test-Path $lockFile) { $lockUp = $true } else { Start-Sleep -Seconds 1 } }
Assert-Equal "  뷰어가 워처도 함께 켰다(잠금 파일이 생김)" $true $lockUp
Start-Sleep -Seconds 3
$newWins2 = @(Get-VisibleConsoleWindows | Where-Object { $winsBefore2 -notcontains $_ })
Assert-Equal "  뷰어와 워처를 켜는 동안 새로 보이는 터미널/콘솔 창이 하나도 없다" 0 $newWins2.Count
$noExit = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match '-NoExit' -and $_.CommandLine -like "*$rt*" })
Assert-Equal "  -NoExit(눈에 보이는 워처 창) 으로 뜬 워처가 없다" 0 $noExit.Count
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensure -Port $port3 -Stop | Out-Null
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine -like "*$rt*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$env:AGY_DELEGATE_RUNTIME = $null
Start-Sleep -Seconds 2
Remove-Item -LiteralPath $work2 -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "워처 시작 스크립트(start-agy.ps1 -Hidden)"
$ast = [System.Management.Automation.Language.Parser]::ParseFile($startAgy, [ref]$null, [ref]$null)
Assert-Equal "-Hidden 스위치가 있다" $true (@($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Hidden' }).Count -eq 1)
$src = [System.IO.File]::ReadAllText($startAgy, [System.Text.Encoding]::UTF8)
Assert-Equal "  -Hidden 이면 콘솔을 만들지 않는 WScript.Shell.Run(명령, 0)으로 띄운다" $true ($src -match '\$sh\.Run\(\$cmd, 0, \$false\)')
Assert-Equal "  -Hidden 이 아니면(기본) 예전처럼 -NoExit 창으로 띄운다" $true ($src -match '"-NoExit"')
$viewerSrc = [System.IO.File]::ReadAllText((Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"), [System.Text.Encoding]::UTF8)
Assert-Equal "뷰어가 시작할 때 꺼진 워처를 켜는 호출에 -Hidden 이 붙어 있다(없으면 -NoExit 콘솔 창이 뜬다)" $true ($viewerSrc -match '& \$startScript -Hidden')

Write-Host "더블클릭 실행 파일(start-viewer-hidden.vbs)"
$vbs = [System.IO.File]::ReadAllText((Join-Path $repoRoot "runtime\viewer\start-viewer-hidden.vbs"))
Assert-Equal "창 없이(0) 숨김 실행으로 ensure-viewer-running.ps1 을 부른다" $true ($vbs -match 'sh\.Run .*ensure-viewer-running\.ps1.*, 0, False')
Assert-Equal "  스크립트 폴더 기준 경로를 쓴다(설치 위치와 상관없이 동작)" $true ($vbs -match 'GetParentFolderName\(WScript\.ScriptFullName\)')

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
