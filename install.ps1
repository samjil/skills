if ($MyInvocation.MyCommand.Path -and (-not $env:SAMJIL_UTF8_ACTIVE)) {
    $env:SAMJIL_UTF8_ACTIVE = "1"
    $env:SAMJIL_SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
    try {
        $utf8Content = [System.IO.File]::ReadAllText($MyInvocation.MyCommand.Path, [System.Text.Encoding]::UTF8)
        $sb = [scriptblock]::Create($utf8Content)
        & $sb @args
        exit $LASTEXITCODE
    } finally {
        $env:SAMJIL_UTF8_ACTIVE = $null
        $env:SAMJIL_SCRIPT_DIR = $null
    }
}

# install.ps1
# samjil AI Agent Skills 전역 설치 스크립트 (Antigravity & Claude Code)
#
# [사용법 1: 로컬 실행]
#   저장소를 clone한 폴더에서:
#   .\install.ps1
#
# [사용법 2: 원격 웹 원라이너 (새 PC 등)]
#   저장소를 clone하지 않고 PowerShell에서 바로 실행:
#   irm https://raw.githubusercontent.com/samjil/skills/main/install.ps1 | iex

$ScriptDir = if ($env:SAMJIL_SCRIPT_DIR) { $env:SAMJIL_SCRIPT_DIR } elseif ($PSScriptRoot) { $PSScriptRoot } else { "" }
$TargetDir = ""
$Uninstall = $false
if ($args) {
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i] -eq "-TargetDir" -and ($i + 1) -lt $args.Count) {
            $TargetDir = $args[++$i]
        } elseif ($args[$i] -eq "-Uninstall") {
            $Uninstall = $true
        }
    }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

if ($Uninstall) {
    $uninstallScript = Join-Path $ScriptDir "uninstall.ps1"
    if (-not [string]::IsNullOrEmpty($ScriptDir) -and (Test-Path $uninstallScript)) {
        & $uninstallScript
    } else {
        $rawUninstall = (Invoke-RestMethod -Uri "https://raw.githubusercontent.com/samjil/skills/main/uninstall.ps1" -UseBasicParsing)
        Invoke-Expression $rawUninstall
    }
    exit 0
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  samjil AI Agent Skills Installer" -ForegroundColor Cyan
Write-Host "  (Antigravity & Claude Code 전역 설치기)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$isRemote = [string]::IsNullOrEmpty($ScriptDir) -or (-not (Test-Path (Join-Path $ScriptDir "samjil-handoff")))

if ($isRemote) {
    # 원격 실행 모드: GitHub에서 최신 소스 다운로드
    Write-Host "[*] 원격 설치 모드로 최신 패키지 다운로드 중..." -ForegroundColor Yellow
    $zipUrl = "https://github.com/samjil/skills/archive/refs/heads/main.zip"
    $tempZip = Join-Path $env:TEMP "samjil-skills-main.zip"
    $tempExtract = Join-Path $env:TEMP "samjil-skills-extract"

    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
        if (Test-Path $tempExtract) { Remove-Item -Recurse -Force $tempExtract }
        Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force

        $extractedRoot = Join-Path $tempExtract "skills-main"
        if (-not (Test-Path $extractedRoot)) {
            $sub = Get-ChildItem -LiteralPath $tempExtract -Directory | Select-Object -First 1
            if ($sub) { $extractedRoot = $sub.FullName }
        }
        $SkillsSourceDir = $extractedRoot
        Write-Host "[+] 최신 패키지 다운로드 완료!" -ForegroundColor Green
    } catch {
        Write-Error "GitHub 패키지 다운로드 실패: $($_.Exception.Message)"
        exit 1
    }
} else {
    # 로컬 저장소 모드 (저장소는 소스 관리 전용)
    $SkillsSourceDir = $ScriptDir
    Write-Host "[*] 로컬 설치 소스 패키지: $SkillsSourceDir" -ForegroundColor Gray
}

$SkillsSourceDir = (Resolve-Path $SkillsSourceDir).Path

# -----------------------------------------------------------------------------
# 1. Antigravity 설정 정리 및 ~/.agents/skills 등록 보장
# -----------------------------------------------------------------------------
# 저장소 자체(D:\Repos\...)는 스킬 경로로 직접 연결하지 않으므로 skills.json에서 제거합니다.
$GeminiConfigDir = Join-Path $env:USERPROFILE ".gemini\config"
$SkillsJsonPath = Join-Path $GeminiConfigDir "skills.json"

if (-not (Test-Path $GeminiConfigDir)) {
    New-Item -ItemType Directory -Force -Path $GeminiConfigDir | Out-Null
}

$configObj = $null
if (Test-Path $SkillsJsonPath) {
    try {
        $rawJson = Get-Content -LiteralPath $SkillsJsonPath -Raw -Encoding UTF8
        if ($rawJson -and $rawJson.Trim()) {
            $configObj = $rawJson | ConvertFrom-Json
        }
    } catch {}
}

if (-not $configObj) {
    $configObj = [PSCustomObject]@{ entries = @() }
}
if (-not $configObj.entries) {
    $configObj | Add-Member -MemberType NoteProperty -Name "entries" -Value @() -Force
}

# 저장소 경로나 samjil 관련 이전 직접 참조 항목 제거
$cleanedEntries = @()
$hasAgentsSkills = $false
foreach ($entry in $configObj.entries) {
    if ($entry -and $entry.path) {
        $p = [string]$entry.path
        if ($p -eq "~/.agents/skills" -or $p -eq ((Join-Path $env:USERPROFILE ".agents\skills").Replace('\', '/'))) {
            $hasAgentsSkills = $true
            $cleanedEntries += $entry
        } elseif ($p -match "samjil" -or $p -match "github.com/samjil") {
            # 저장소 직접 연결 해제
            Write-Host "[*] Antigravity skills.json 등록 해제: $p" -ForegroundColor Gray
        } else {
            $cleanedEntries += $entry
        }
    }
}

if (-not $hasAgentsSkills) {
    $cleanedEntries += [PSCustomObject]@{ path = "~/.agents/skills" }
    Write-Host "[+] Antigravity skills.json 에 ~/.agents/skills 등록 완료" -ForegroundColor Green
}

$configObj.entries = $cleanedEntries
$jsonOutput = $configObj | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($SkillsJsonPath, $jsonOutput, [System.Text.Encoding]::UTF8)

# -----------------------------------------------------------------------------
# 2. 에이전트 스킬 배포 (Claude Code & Antigravity AGY)
#    -> 스킬 폴더에는 순수 SKILL.md 만 배치
# -----------------------------------------------------------------------------
$ClaudeSkillsRoot = Join-Path $env:USERPROFILE ".claude\skills"
$AgentsSkillsRoot = Join-Path $env:USERPROFILE ".agents\skills"

New-Item -ItemType Directory -Force -Path $ClaudeSkillsRoot, $AgentsSkillsRoot | Out-Null

# 구버전 스킬 정리 (agent-handoff, agent-delegate-agy)
$legacySkills = @("agent-handoff", "agent-delegate-agy")
foreach ($old in $legacySkills) {
    $cOld = Join-Path $ClaudeSkillsRoot $old
    if (Test-Path $cOld) {
        $item = Get-Item -LiteralPath $cOld -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { cmd /c rmdir "$cOld" 2>&1 | Out-Null }
        else { Remove-Item -Recurse -Force -LiteralPath $cOld -ErrorAction SilentlyContinue }
    }
    $aOld = Join-Path $AgentsSkillsRoot $old
    if (Test-Path $aOld) {
        Remove-Item -Recurse -Force -LiteralPath $aOld -ErrorAction SilentlyContinue
    }
}

$targetSkills = @("samjil-handoff", "samjil-delegate-agy")

foreach ($sName in $targetSkills) {
    $srcSkillDir = Join-Path $SkillsSourceDir $sName
    $srcSkillMd = Join-Path $srcSkillDir "SKILL.md"

    if (-not (Test-Path $srcSkillMd)) { continue }

    # (1) 공용 스킬 저장소: ~/.agents/skills/<skill-name>/
    $aDestDir = Join-Path $AgentsSkillsRoot $sName
    if (Test-Path $aDestDir) {
        $subDirsToClean = @((Join-Path $aDestDir "scripts"), (Join-Path $aDestDir "viewer"), (Join-Path $aDestDir "templates"))
        foreach ($sd in $subDirsToClean) {
            if (Test-Path $sd) { Remove-Item -Recurse -Force -LiteralPath $sd -ErrorAction SilentlyContinue }
        }
    } else {
        New-Item -ItemType Directory -Force -Path $aDestDir | Out-Null
    }
    Copy-Item -Force -LiteralPath $srcSkillMd -Destination (Join-Path $aDestDir "SKILL.md")
    Write-Host "[+] 공용 스킬 저장소 배치 완료: $sName (SKILL.md)" -ForegroundColor Green

    # (2) Claude Code: ~/.claude/skills/<skill-name>/ -> ~/.agents/skills/<skill-name>/ 정션(Junction) 연결
    $cDestDir = Join-Path $ClaudeSkillsRoot $sName
    if (Test-Path $cDestDir) {
        $item = Get-Item -LiteralPath $cDestDir -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            cmd /c rmdir "$cDestDir" 2>&1 | Out-Null
        } else {
            Remove-Item -Recurse -Force -LiteralPath $cDestDir -ErrorAction SilentlyContinue
        }
    }
    cmd /c mklink /J "$cDestDir" "$aDestDir" 2>&1 | Out-Null
    Write-Host "[+] Claude Code 정션(Junction) 연결 완료: $sName -> ~/.agents/skills/$sName" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 3. 부속 도구 및 스크립트, 웹 파일 설치 (~/.samjil/)
# -----------------------------------------------------------------------------
$SamjilRoot = Join-Path $env:USERPROFILE ".samjil"
New-Item -ItemType Directory -Force -Path $SamjilRoot | Out-Null

# 3-1. 런타임 배치 (~/.samjil/delegate-agy, ~/.samjil/handoff)
$srcRuntime = Join-Path $SkillsSourceDir "runtime"
if (Test-Path $srcRuntime) {
    $srcDelegate = Join-Path $srcRuntime "delegate-agy"
    if (Test-Path $srcDelegate) {
        $destDelegate = Join-Path $SamjilRoot "delegate-agy"
        New-Item -ItemType Directory -Force -Path $destDelegate | Out-Null
        Copy-Item -Recurse -Force -Path (Join-Path $srcDelegate "*") -Destination $destDelegate
        Write-Host "[+] delegate-agy 런타임 및 스크립트 배치 완료 (~/.samjil/delegate-agy)" -ForegroundColor Green
    }

    $srcHandoff = Join-Path $srcRuntime "handoff"
    if (Test-Path $srcHandoff) {
        $destHandoff = Join-Path $SamjilRoot "handoff"
        New-Item -ItemType Directory -Force -Path $destHandoff | Out-Null
        Copy-Item -Recurse -Force -Path (Join-Path $srcHandoff "*") -Destination $destHandoff
        Write-Host "[+] handoff 템플릿 배치 완료 (~/.samjil/handoff)" -ForegroundColor Green
    }
}

# 3-2. 통합 웹 뷰어 실행부 배치 (~/.samjil/web, ~/.samjil/serve-viewer.*)
$srcWeb = Join-Path $SkillsSourceDir "web"
if (Test-Path $srcWeb) {
    $destWeb = Join-Path $SamjilRoot "web"
    New-Item -ItemType Directory -Force -Path $destWeb | Out-Null
    Copy-Item -Recurse -Force -Path (Join-Path $srcWeb "*") -Destination $destWeb
    Write-Host "[+] 통합 대시보드 웹 파일 배치 완료 (~/.samjil/web)" -ForegroundColor Green
}

$viewerFiles = @("serve-viewer.ps1")
foreach ($vf in $viewerFiles) {
    $srcVf = Join-Path $SkillsSourceDir $vf
    if (Test-Path $srcVf) {
        Copy-Item -Force -LiteralPath $srcVf -Destination (Join-Path $SamjilRoot $vf)
    }
}
Write-Host "[+] 통합 뷰어 실행 스크립트 배치 완료 (~/.samjil/serve-viewer.ps1)" -ForegroundColor Green

# 3-3. 중복/구버전 스크립트 정리 (~/.samjil/)
$oldRedundantFiles = @(
    (Join-Path $SamjilRoot "serve-viewer.bat"),
    (Join-Path $SamjilRoot "serve-dashboard.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\start-agy.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\stop-agy.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\restart-agy.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\serve-dashboard.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\serve-report.bat"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\check-and-start.ps1"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\restart-agy.ps1"),
    (Join-Path $SamjilRoot "delegate-agy\scripts\stop-watchdog.ps1")
)
foreach ($orf in $oldRedundantFiles) {
    if (Test-Path -LiteralPath $orf) {
        Remove-Item -Force -LiteralPath $orf -ErrorAction SilentlyContinue
    }
}

# 3-4. 기존 레거시 데이터 자동 마이그레이션 (대화 기록 및 QA 로그 보존)
$newHandoffDir = Join-Path $SamjilRoot "handoff"
$legacyHandoffPaths = @(
    (Join-Path $SamjilRoot "samjil-handoff"),
    (Join-Path $SamjilRoot "agent-handoff"),
    (Join-Path $env:USERPROFILE ".agent-handoff")
)
foreach ($legacy in $legacyHandoffPaths) {
    if (Test-Path $legacy) {
        $legacyProjects = Get-ChildItem -LiteralPath $legacy -Directory -ErrorAction SilentlyContinue
        if ($legacyProjects.Count -gt 0) {
            New-Item -ItemType Directory -Force -Path $newHandoffDir | Out-Null
            foreach ($proj in $legacyProjects) {
                if ($proj.Name -eq "viewer" -or $proj.Name -eq "templates" -or $proj.Name -eq "scripts") { continue }
                $dest = Join-Path $newHandoffDir $proj.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item -Recurse -Force -LiteralPath $proj.FullName -Destination $dest
                    Write-Host "[*] 기존 대화 기록을 ~/.samjil/handoff 로 이전했습니다: $($proj.Name)" -ForegroundColor Green
                }
            }
        }
        $oldViewer = Join-Path $legacy "viewer"
        if (Test-Path $oldViewer) { Remove-Item -Recurse -Force $oldViewer -ErrorAction SilentlyContinue }
        $oldTemplates = Join-Path $legacy "templates"
        if (Test-Path $oldTemplates) { Remove-Item -Recurse -Force $oldTemplates -ErrorAction SilentlyContinue }
    }
}

$oldDelegateLogs = Join-Path $SamjilRoot "samjil-delegate-agy\runtime\logs"
$newDelegateLogs = Join-Path $SamjilRoot "delegate-agy\runtime\logs"
if ((Test-Path $oldDelegateLogs) -and (-not (Test-Path $newDelegateLogs))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $SamjilRoot "delegate-agy\runtime") | Out-Null
    Copy-Item -Recurse -Force -LiteralPath $oldDelegateLogs -Destination $newDelegateLogs
    Write-Host "[*] 기존 위임 로그를 ~/.samjil/delegate-agy 로 이전했습니다" -ForegroundColor Green
}

$oldDelegateScripts = Join-Path $SamjilRoot "samjil-delegate-agy\scripts"
if (Test-Path $oldDelegateScripts) {
    Remove-Item -Recurse -Force $oldDelegateScripts -ErrorAction SilentlyContinue
}

# 원격 설치 임시 파일 정리
if ($isRemote) {
    Remove-Item -Force $tempZip -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  설치가 성공적으로 완료되었습니다!" -ForegroundColor Green
Write-Host "  [스킬 (순수 SKILL.md)]" -ForegroundColor White
Write-Host "    - Claude Code : ~/.claude/skills/samjil-*" -ForegroundColor Gray
Write-Host "    - Antigravity : ~/.agents/skills/samjil-*" -ForegroundColor Gray
Write-Host "  [도구 및 웹 파일 (~/.samjil)]" -ForegroundColor White
Write-Host "    - 통합 웹 뷰어 실행 : ~/.samjil/serve-viewer.ps1" -ForegroundColor Cyan
Write-Host "      (브라우저에서 Delegate QA / Handoff 탭 선택 열람)" -ForegroundColor Gray
Write-Host "    - 위임 워처 시작/재시작 : ~/.samjil/delegate-agy/scripts/start-agy.ps1" -ForegroundColor Gray
Write-Host "    - 위임 워처 안전 중지   : ~/.samjil/delegate-agy/scripts/stop-agy.ps1" -ForegroundColor Gray
Write-Host "    - 대화 저장소         : ~/.samjil/handoff/" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
