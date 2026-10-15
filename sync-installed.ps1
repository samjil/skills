# 저장소의 소스를 이 PC 에 설치된 사본(~/.samjil, ~/.agents/skills)에 반영한다. 개발하면서 소스를 고칠 때마다 쓴다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File sync-installed.ps1                    # 다른 파일만 복사하고 결과를 알려 준다
#   powershell -NoProfile -ExecutionPolicy Bypass -File sync-installed.ps1 -Check             # 복사하지 않고 어긋난 파일만 알린다(어긋나면 종료 코드 1)
#   powershell -NoProfile -ExecutionPolicy Bypass -File sync-installed.ps1 -RestartWatcher    # 워처 스크립트가 바뀌었으면 (일이 없을 때) 워처도 다시 켠다
#   powershell -NoProfile -ExecutionPolicy Bypass -File sync-installed.ps1 -RestartViewer     # 뷰어 본체 스크립트가 바뀌었으면 뷰어도 다시 켠다
#
# install.ps1 은 스킬 설치·정리까지 하는 전체 설치라 개발 중에 자주 돌리기엔 무겁다. 이 스크립트는 같은 배치 규칙만 따라 "바뀐 파일만" 복사한다:
#   runtime\delegate-agy\scripts   -> ~\.samjil\delegate-agy\scripts      (delegate-agy\runtime 의 로그·큐·세션은 건드리지 않는다)
#   runtime\viewer                 -> ~\.samjil\viewer
#   runtime\handoff\templates      -> ~\.samjil\handoff\templates         (handoff 의 대화 기록은 건드리지 않는다)
#   <스킬>\SKILL.md                -> ~\.agents\skills\<스킬>\SKILL.md      (samjil-handoff, samjil-delegate-agy, samjil-git-commit)
# 소스에서 지운 파일은 설치본에 남는다(지우지 않고 "설치본에만 있는 파일"로 알리기만 한다).
#
# 왜 "워처를 다시 켜야 하는가": 워처는 켜질 때 스크립트를 읽어 메모리에 올리지만, 작업자는 작업마다 새 프로세스로 스크립트를 다시 읽는다.
# 파일만 바꾸고 워처를 안 켜면 새 작업자와 옛 워처가 섞여 돌아 서로 맞지 않을 수 있다. 그래서 워처 스크립트가 바뀌면 재시작을 알리거나(-RestartWatcher 로) 직접 한다.
# 뷰어의 화면 파일(web\*)은 읽을 때마다 디스크에서 내려가므로 브라우저를 새로 고치면 되고, 재시작이 필요 없다.

param(
    [switch]$Check,
    [switch]$RestartWatcher,
    [switch]$RestartViewer,
    [string]$SourceRoot = $PSScriptRoot,
    [string]$InstallRoot = (Join-Path $env:USERPROFILE ".samjil"),
    [string]$AgentsSkillsRoot = (Join-Path $env:USERPROFILE ".agents\skills")
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Get-FileHashHex([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString($sha.ComputeHash($fs)).Replace("-", "") } finally { $fs.Dispose(); $sha.Dispose() }
}

# 소스 폴더의 모든 파일을 대상 폴더와 견줘 목록을 만든다. 반환: Changed(복사할 것) / OnlyInDest(설치본에만 있는 것)
function Compare-Tree([string]$Src, [string]$Dest) {
    $changed = @(); $onlyDest = @()
    if (-not (Test-Path -LiteralPath $Src)) { return @{ Changed = @(); OnlyInDest = @(); Missing = $true } }
    $srcFiles = @(Get-ChildItem -LiteralPath $Src -Recurse -File)
    $seen = @{}
    foreach ($f in $srcFiles) {
        $rel = $f.FullName.Substring($Src.TrimEnd('\').Length + 1)
        $seen[$rel.ToLowerInvariant()] = $true
        $d = Join-Path $Dest $rel
        if (-not (Test-Path -LiteralPath $d)) { $changed += [pscustomobject]@{ Rel = $rel; Src = $f.FullName; Dest = $d; Reason = "새 파일" }; continue }
        if ((Get-Item -LiteralPath $d).Length -ne $f.Length -or (Get-FileHashHex $f.FullName) -ne (Get-FileHashHex $d)) {
            $changed += [pscustomobject]@{ Rel = $rel; Src = $f.FullName; Dest = $d; Reason = "내용이 다름" }
        }
    }
    if (Test-Path -LiteralPath $Dest) {
        foreach ($f in (Get-ChildItem -LiteralPath $Dest -Recurse -File)) {
            $rel = $f.FullName.Substring($Dest.TrimEnd('\').Length + 1)
            if ($f.Extension -eq ".log") { continue }    # 뷰어가 남기는 out.log/error.log 같은 실행 흔적은 소스에 없는 게 정상이다
            if (-not $seen.ContainsKey($rel.ToLowerInvariant())) { $onlyDest += $rel }
        }
    }
    return @{ Changed = @($changed); OnlyInDest = @($onlyDest); Missing = $false }
}

$mappings = @(
    @{ Name = "delegate-agy 스크립트"; Src = (Join-Path $SourceRoot "runtime\delegate-agy\scripts"); Dest = (Join-Path $InstallRoot "delegate-agy\scripts") },
    @{ Name = "웹 뷰어";               Src = (Join-Path $SourceRoot "runtime\viewer");               Dest = (Join-Path $InstallRoot "viewer") },
    @{ Name = "handoff 템플릿";        Src = (Join-Path $SourceRoot "runtime\handoff\templates");    Dest = (Join-Path $InstallRoot "handoff\templates") }
)

$allChanged = @()
$orphans = @()
foreach ($m in $mappings) {
    $r = Compare-Tree $m.Src $m.Dest
    if ($r.Missing) { continue }
    foreach ($c in $r.Changed) { $allChanged += [pscustomobject]@{ Group = $m.Name; Rel = $c.Rel; Src = $c.Src; Dest = $c.Dest; Reason = $c.Reason } }
    foreach ($o in $r.OnlyInDest) { $orphans += ("{0}: {1}" -f $m.Name, $o) }
}
foreach ($skill in @("samjil-handoff", "samjil-delegate-agy", "samjil-git-commit")) {
    $src = Join-Path $SourceRoot "$skill\SKILL.md"
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dest = Join-Path $AgentsSkillsRoot "$skill\SKILL.md"
    if (-not (Test-Path -LiteralPath $dest)) { $allChanged += [pscustomobject]@{ Group = "스킬"; Rel = "$skill\SKILL.md"; Src = $src; Dest = $dest; Reason = "새 파일" }; continue }
    if ((Get-FileHashHex $src) -ne (Get-FileHashHex $dest)) { $allChanged += [pscustomobject]@{ Group = "스킬"; Rel = "$skill\SKILL.md"; Src = $src; Dest = $dest; Reason = "내용이 다름" } }
}

if ($allChanged.Count -eq 0) {
    Write-Host "설치본이 소스와 같습니다." -ForegroundColor Green
} else {
    Write-Host ("어긋난 파일 {0}개:" -f $allChanged.Count) -ForegroundColor Yellow
    foreach ($c in $allChanged) { Write-Host ("  [{0}] {1} ({2})" -f $c.Group, $c.Rel, $c.Reason) }
}
if ($orphans.Count -gt 0) {
    Write-Host "설치본에만 있는 파일(지우지 않음):" -ForegroundColor DarkGray
    foreach ($o in $orphans) { Write-Host "  $o" -ForegroundColor DarkGray }
}

if ($Check) {
    if ($allChanged.Count -gt 0) { exit 1 }
    exit 0
}

foreach ($c in $allChanged) {
    New-Item -ItemType Directory -Force -Path (Split-Path $c.Dest -Parent) | Out-Null
    Copy-Item -LiteralPath $c.Src -Destination $c.Dest -Force
}
if ($allChanged.Count -gt 0) { Write-Host ("복사했습니다: {0}개" -f $allChanged.Count) -ForegroundColor Green }

# --- 재시작이 필요한가 ---
$watcherChanged = @($allChanged | Where-Object { $_.Group -eq "delegate-agy 스크립트" -and $_.Rel -like "*.ps1" })
$viewerMain = @("serve-viewer.ps1", "claude-sessions.ps1", "watcher-health.ps1")
$viewerChanged = @($allChanged | Where-Object { $_.Group -eq "웹 뷰어" -and ($viewerMain -contains $_.Rel) })

function Get-WatcherProcessId {
    $p = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'watch-agy\.ps1' -and $_.CommandLine -notmatch 'WorkerTask' })
    if ($p.Count -gt 0) { return [int]$p[0].ProcessId }
    return 0
}

if ($watcherChanged.Count -gt 0) {
    $wpid = Get-WatcherProcessId
    if ($wpid -le 0) {
        Write-Host "워처 스크립트가 바뀌었습니다. 워처가 꺼져 있어 다음에 켤 때 새 코드를 씁니다." -ForegroundColor Cyan
    } elseif (-not $RestartWatcher) {
        Write-Host ("워처 스크립트가 바뀌었는데 워처(PID {0})는 옛 코드로 돌고 있습니다. 새 작업자와 옛 워처가 섞이지 않게 다시 켜야 합니다: -RestartWatcher" -f $wpid) -ForegroundColor Yellow
    } else {
        $running = @(Get-ChildItem (Join-Path $InstallRoot "delegate-agy\runtime\logs\running") -Filter "*.json" -ErrorAction SilentlyContinue)
        if ($running.Count -gt 0) {
            Write-Host ("돌고 있는 작업이 {0}건이라 워처를 다시 켜지 않았습니다. 끝난 뒤 -RestartWatcher 로 다시 실행하세요." -f $running.Count) -ForegroundColor Yellow
        } else {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallRoot "delegate-agy\scripts\start-agy.ps1") -Hidden | Out-Null
            Start-Sleep -Seconds 4
            $np = Get-WatcherProcessId
            Write-Host ("워처를 다시 켰습니다 (이전 PID {0} -> 새 PID {1})." -f $wpid, $np) -ForegroundColor Green
        }
    }
}
if ($viewerChanged.Count -gt 0) {
    if (-not $RestartViewer) {
        Write-Host "뷰어 본체 스크립트가 바뀌었습니다. 뷰어를 다시 켜야 반영됩니다: -RestartViewer" -ForegroundColor Yellow
    } else {
        $ev = Join-Path $InstallRoot "viewer\ensure-viewer-running.ps1"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ev -Stop | Out-Null
        Start-Sleep -Seconds 2
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ev | Out-Null
        Write-Host "뷰어를 다시 켰습니다." -ForegroundColor Green
    }
}
exit 0
