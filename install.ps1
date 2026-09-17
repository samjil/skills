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

[CmdletBinding()]
param(
    [string]$TargetDir = "",
    [switch]$Uninstall
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

if ($Uninstall) {
    $uninstallScript = Join-Path $PSScriptRoot "uninstall.ps1"
    if (-not [string]::IsNullOrEmpty($PSScriptRoot) -and (Test-Path $uninstallScript)) {
        & $uninstallScript
    } else {
        $rawUninstall = (Invoke-RestMethod -Uri "https://raw.githubusercontent.com/samjil/skills/main/uninstall.ps1" -UseBasicParsing)
        Invoke-Expression $rawUninstall
    }
    exit 0
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  samjil AI Agent Skills Installer" -ForegroundColor Cyan
Write-Host "  (skills.sh 호환 Antigravity & Claude Code 전역 설치기)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$isRemote = [string]::IsNullOrEmpty($PSScriptRoot) -or (-not (Test-Path (Join-Path $PSScriptRoot "agent-handoff")))

if ($isRemote) {
    # 원격 실행 모드: GitHub에서 최신 스킬 다운로드
    if (-not $TargetDir) {
        $TargetDir = Join-Path $env:USERPROFILE ".gemini\skills\samjil-skills"
    }
    Write-Host "[•] 원격 설치 모드로 실행 중..." -ForegroundColor Yellow
    Write-Host "[•] 설치 대상 경로: $TargetDir" -ForegroundColor Gray

    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    }

    $zipUrl = "https://github.com/samjil/skills/archive/refs/heads/main.zip"
    $tempZip = Join-Path $env:TEMP "samjil-skills-main.zip"
    $tempExtract = Join-Path $env:TEMP "samjil-skills-extract"

    Write-Host "[•] GitHub에서 최신 스킬 패키지 다운로드 중..." -ForegroundColor Gray
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
        if (Test-Path $tempExtract) { Remove-Item -Recurse -Force $tempExtract }
        Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force

        $extractedRoot = Join-Path $tempExtract "skills-main"
        if (-not (Test-Path $extractedRoot)) {
            $sub = Get-ChildItem -LiteralPath $tempExtract -Directory | Select-Object -First 1
            if ($sub) { $extractedRoot = $sub.FullName }
        }

        Copy-Item -Recurse -Force (Join-Path $extractedRoot "*") $TargetDir
        Remove-Item -Force $tempZip -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue
        Write-Host "[✓] 최신 스킬 다운로드 및 배치 완료!" -ForegroundColor Green
    } catch {
        Write-Error "GitHub 패키지 다운로드 실패: $($_.Exception.Message)"
        exit 1
    }
    $SkillsDir = $TargetDir
} else {
    # 로컬 실행 모드
    $SkillsDir = $PSScriptRoot
    Write-Host "[•] 로컬 저장소 모드로 실행 중: $SkillsDir" -ForegroundColor Gray
}

$SkillsDir = (Resolve-Path $SkillsDir).Path
$NormalizedSkillsPath = $SkillsDir.Replace('\', '/')

# 1. Antigravity 글로벌 skills.json 등록
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

$exists = $false
foreach ($entry in $configObj.entries) {
    if ($entry -and $entry.path) {
        $p = [string]$entry.path
        if ($p.TrimEnd('/').ToLowerInvariant() -eq $NormalizedSkillsPath.TrimEnd('/').ToLowerInvariant()) {
            $exists = $true
            break
        }
    }
}

if (-not $exists) {
    $newEntry = [PSCustomObject]@{ path = $NormalizedSkillsPath }
    $entriesList = [System.Collections.ArrayList]@($configObj.entries)
    $entriesList.Add($newEntry) | Out-Null
    $configObj.entries = $entriesList.ToArray()

    $jsonOutput = $configObj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($SkillsJsonPath, $jsonOutput, [System.Text.Encoding]::UTF8)
    Write-Host "[✓] Antigravity skills.json 에 등록 완료: $NormalizedSkillsPath" -ForegroundColor Green
} else {
    Write-Host "[•] Antigravity skills.json 에 이미 등록되어 있습니다: $NormalizedSkillsPath" -ForegroundColor Gray
}

# 2. Claude Code 전역 스킬 설치 (~/.claude/skills/<skill-name>)
$ClaudeSkillsDir = Join-Path $env:USERPROFILE ".claude\skills"

if (-not (Test-Path $ClaudeSkillsDir)) {
    New-Item -ItemType Directory -Force -Path $ClaudeSkillsDir | Out-Null
}

$skillDirs = Get-ChildItem -LiteralPath $SkillsDir -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "SKILL.md")
}

$installedNames = @()
foreach ($sDir in $skillDirs) {
    $sName = $sDir.Name
    $installedNames += $sName
    $cTarget = Join-Path $ClaudeSkillsDir $sName

    # 기존에 정션이 걸려있다면 안전하게 연결 해제
    if (Test-Path $cTarget) {
        $item = Get-Item -LiteralPath $cTarget -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            cmd /c rmdir "$cTarget" 2>&1 | Out-Null
        }
    }

    # 정션 없이 독립 디렉터리로 전체 복사
    if (-not (Test-Path $cTarget)) {
        New-Item -ItemType Directory -Force -Path $cTarget | Out-Null
    }
    Copy-Item -Recurse -Force -Path (Join-Path $sDir.FullName "*") -Destination $cTarget
    Write-Host "[✓] Claude Code 스킬 전역 복사/배치 완료: $sName" -ForegroundColor Green
}

# 3. 전역 런타임 저장소 초기화 (~/.samjil/agent-handoff & ~/.samjil/agent-delegate-agy/runtime)
$SamjilRoot = Join-Path $env:USERPROFILE ".samjil"
$HandoffDir = Join-Path $SamjilRoot "agent-handoff"
if (-not (Test-Path $HandoffDir)) {
    New-Item -ItemType Directory -Force -Path $HandoffDir | Out-Null
    Write-Host "[✓] Handoff 대화 저장소 생성 완료: $HandoffDir" -ForegroundColor Green
}

# 기존 ~/.samjil/handoff 또는 ~/.agent-handoff 가 있다면 자동 복사 마이그레이션
$legacyHandoffPaths = @(
    (Join-Path $SamjilRoot "handoff"),
    (Join-Path $env:USERPROFILE ".agent-handoff")
)
foreach ($legacy in $legacyHandoffPaths) {
    if ((Test-Path $legacy) -and (Get-ChildItem -LiteralPath $HandoffDir).Count -eq 0) {
        try {
            Get-ChildItem -LiteralPath $legacy -Directory | ForEach-Object {
                $dest = Join-Path $HandoffDir $_.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item -Recurse -Force -LiteralPath $_.FullName -Destination $dest
                    Write-Host "[•] 기존 대화 기록을 ~/.samjil/agent-handoff 로 복사했습니다: $($_.Name)" -ForegroundColor Green
                }
            }
        } catch {}
    }
}

$DelegateRuntimeDir = Join-Path $SamjilRoot "agent-delegate-agy\runtime"
$inboxDir = Join-Path $DelegateRuntimeDir "inbox"
$outboxDir = Join-Path $DelegateRuntimeDir "outbox"
$processedDir = Join-Path $DelegateRuntimeDir "processed"
$logsDir = Join-Path $DelegateRuntimeDir "logs"
New-Item -ItemType Directory -Force -Path $inboxDir, $outboxDir, $processedDir, $logsDir | Out-Null
Write-Host "[✓] Delegate 런타임 저장소 생성 완료: $DelegateRuntimeDir" -ForegroundColor Green

# 기존 ~/.samjil/delegate/runtime 데이터 이전
$legacyDelegateRuntime = Join-Path $SamjilRoot "delegate\runtime"
if ((Test-Path $legacyDelegateRuntime) -and (Test-Path $DelegateRuntimeDir)) {
    try {
        Copy-Item -Recurse -Force -Path (Join-Path $legacyDelegateRuntime "*") -Destination $DelegateRuntimeDir -ErrorAction SilentlyContinue
    } catch {}
}

$skillsDisplay = ($installedNames | ForEach-Object { "'$_'" }) -join ", "

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  설치가 성공적으로 완료되었습니다!" -ForegroundColor Green
Write-Host "  - Antigravity 및 Claude 에서 $skillsDisplay 스킬이 전역 활성화되었습니다." -ForegroundColor White
Write-Host "  - 대화 저장소 : $HandoffDir (뷰어: agent-handoff/viewer/serve-handoff.bat)" -ForegroundColor Gray
Write-Host "  - 위임 런타임 : $DelegateRuntimeDir (워처: agent-delegate-agy/scripts/start-agy.bat)" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
