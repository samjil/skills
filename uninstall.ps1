if ($MyInvocation.MyCommand.Path -and (-not $env:SAMJIL_UTF8_ACTIVE)) {
    $env:SAMJIL_UTF8_ACTIVE = "1"
    try {
        $utf8Content = [System.IO.File]::ReadAllText($MyInvocation.MyCommand.Path, [System.Text.Encoding]::UTF8)
        $sb = [scriptblock]::Create($utf8Content)
        & $sb @args
        exit $LASTEXITCODE
    } finally {
        $env:SAMJIL_UTF8_ACTIVE = $null
    }
}

# ==========================================================
#  samjil AI Agent Skills Uninstaller
#  Antigravity & Claude Code 스킬 원클릭 제거 스크립트
#
#  사용법:
#    1. 로컬 실행:
#       .\uninstall.ps1
#    2. 웹 원클릭 실행 (irm | iex):
#       irm https://raw.githubusercontent.com/samjil/skills/main/uninstall.ps1 | iex
#
#  * 에이전트 간 대화 기록(~/.samjil/samjil-handoff/<프로젝트>/msg/)은 사용자의 소중한 자산이므로
#    제거 시에도 절대 삭제되지 않고 영구 보존됩니다.
# ==========================================================

$Force = ($args -contains "-Force")

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  samjil AI Agent Skills Uninstaller" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 안전한 스킬 디렉터리/정션 제거 함수
function Remove-SkillTarget([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $item = Get-Item -LiteralPath $Path -Force
        # 정션 링크 안전 해제
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$Path`"" > $null 2>&1
            Write-Host "[+] 정션 링크 해제: $Path" -ForegroundColor Green
        } else {
            Remove-Item -Recurse -Force -LiteralPath $Path
            Write-Host "[+] 스킬 디렉터리 삭제 완료: $Path" -ForegroundColor Green
        }
    } catch {
        Write-Warning "삭제 실패 ($Path): $_"
    }
}

$targetSkills = @("samjil-handoff", "samjil-delegate-agy", "agent-handoff", "agent-delegate-agy")

# -----------------------------------------------------------------------------
# 1. Claude Code 전역 스킬 제거 (~/.claude/skills/)
# -----------------------------------------------------------------------------
$claudeSkillsDir = Join-Path $env:USERPROFILE ".claude\skills"
foreach ($s in $targetSkills) {
    $targetPath = Join-Path $claudeSkillsDir $s
    if (Test-Path $targetPath) {
        Remove-SkillTarget $targetPath
    }
}

# -----------------------------------------------------------------------------
# 2. Antigravity (AGY) 전역 스킬 제거 (~/.agents/skills/)
# -----------------------------------------------------------------------------
$agentsSkillsDir = Join-Path $env:USERPROFILE ".agents\skills"
foreach ($s in $targetSkills) {
    $targetPath = Join-Path $agentsSkillsDir $s
    if (Test-Path $targetPath) {
        Remove-SkillTarget $targetPath
    }
}

# -----------------------------------------------------------------------------
# 3. Antigravity 설정 정리 (~/.gemini/config/skills.json)
# -----------------------------------------------------------------------------
$skillsJsonPath = Join-Path $env:USERPROFILE ".gemini\config\skills.json"
if (Test-Path $skillsJsonPath) {
    try {
        $raw = Get-Content $skillsJsonPath -Raw -Encoding UTF8
        $json = ConvertFrom-Json $raw
        if ($json.entries) {
            $filtered = @()
            foreach ($e in $json.entries) {
                $p = $e.path
                # 저장소 직접 연결 또는 samjil 이전 임시 경로 제거
                if ($p -match "samjil" -or $p -match "github.com/samjil") {
                    Write-Host "[+] Antigravity skills.json 등록 해제: $p" -ForegroundColor Green
                } else {
                    $filtered += $e
                }
            }
            $json.entries = $filtered
            $updatedJson = ConvertTo-Json $json -Depth 10
            [System.IO.File]::WriteAllText($skillsJsonPath, $updatedJson, [System.Text.Encoding]::UTF8)
        }
    } catch {
        Write-Warning "skills.json 정리 중 오류: $_"
    }
}

# ~/.agents/.skill-lock.json 에서 samjil 스킬 등록 정보 정리
$skillLockPath = Join-Path $env:USERPROFILE ".agents\.skill-lock.json"
if (Test-Path $skillLockPath) {
    try {
        $rawLock = Get-Content $skillLockPath -Raw -Encoding UTF8
        $lockJson = ConvertFrom-Json $rawLock
        if ($lockJson.skills) {
            $lockChanged = $false
            foreach ($ts in $targetSkills) {
                if ($lockJson.skills.PSObject.Properties[$ts]) {
                    $lockJson.skills.PSObject.Properties.Remove($ts)
                    $lockChanged = $true
                }
            }
            if ($lockChanged) {
                $updatedLock = ConvertTo-Json $lockJson -Depth 10
                [System.IO.File]::WriteAllText($skillLockPath, $updatedLock, [System.Text.Encoding]::UTF8)
                Write-Host "[+] ~/.agents/.skill-lock.json 등록 해제 완료" -ForegroundColor Green
            }
        }
    } catch {
        Write-Warning "skill-lock.json 정리 중 오류: $_"
    }
}

# -----------------------------------------------------------------------------
# 4. 부속 도구 및 런타임 정리 (~/.samjil/)
# -----------------------------------------------------------------------------
$samjilDir = Join-Path $env:USERPROFILE ".samjil"
if (Test-Path -LiteralPath $samjilDir) {
    # 4-1. 통합 웹 뷰어 실행부 제거
    $webDir = Join-Path $samjilDir "web"
    if (Test-Path -LiteralPath $webDir) {
        Remove-Item -Recurse -Force -LiteralPath $webDir -ErrorAction SilentlyContinue
        Write-Host "[+] 웹 대시보드 파일 삭제 완료: $webDir" -ForegroundColor Green
    }
    $viewerFiles = @("serve-viewer.bat", "serve-viewer.ps1", "serve-dashboard.bat")
    foreach ($vf in $viewerFiles) {
        $vPath = Join-Path $samjilDir $vf
        if (Test-Path -LiteralPath $vPath) {
            Remove-Item -Force -LiteralPath $vPath -ErrorAction SilentlyContinue
            Write-Host "[+] 뷰어 실행 파일 삭제: $vPath" -ForegroundColor Green
        }
    }

    # 4-2. Delegate 디렉터리 (scripts + runtime) 제거
    $delegateDirs = @(
        (Join-Path $samjilDir "delegate-agy"),
        (Join-Path $samjilDir "samjil-delegate-agy"),
        (Join-Path $samjilDir "agent-delegate-agy")
    )
    foreach ($dd in $delegateDirs) {
        if (Test-Path -LiteralPath $dd) {
            Remove-Item -Recurse -Force -LiteralPath $dd -ErrorAction SilentlyContinue
            Write-Host "[+] Delegate 도구 및 런타임 삭제 완료: $dd" -ForegroundColor Green
        }
    }

    # 4-3. Handoff 웹 뷰어 및 템플릿 도구 제거 (설치 시 추가된 툴링 파일만)
    $toolDirs = @(
        (Join-Path $samjilDir "handoff\templates"),
        (Join-Path $samjilDir "samjil-handoff\viewer"),
        (Join-Path $samjilDir "samjil-handoff\templates"),
        (Join-Path $samjilDir "agent-handoff\viewer"),
        (Join-Path $samjilDir "agent-handoff\templates")
    )
    foreach ($td in $toolDirs) {
        if (Test-Path -LiteralPath $td) {
            Remove-Item -Recurse -Force -LiteralPath $td -ErrorAction SilentlyContinue
            Write-Host "[+] Handoff 설치 도구 삭제 완료: $td" -ForegroundColor Green
        }
    }

    # 4-4. Handoff 대화 저장소 처리 (~/.samjil/handoff/, ~/.samjil/samjil-handoff/, ~/.samjil/agent-handoff/)
    $handoffDirs = @(
        (Join-Path $samjilDir "handoff"),
        (Join-Path $samjilDir "samjil-handoff"),
        (Join-Path $samjilDir "agent-handoff")
    )
    foreach ($hd in $handoffDirs) {
        if (Test-Path -LiteralPath $hd) {
            # 실제 대화 파일(.md)이 남아있는지 확인
            $handoffFiles = @(Get-ChildItem -LiteralPath $hd -Recurse -File -Filter "*.md" -ErrorAction SilentlyContinue)
            if ($handoffFiles.Count -gt 0) {
                # 실제 대화 기록이 있으면 100% 영구 보존!
                Write-Host "[i] 에이전트 대화 기록($($handoffFiles.Count)건)이 존재하여 안전하게 보존합니다: $hd" -ForegroundColor Cyan
            } else {
                # 대화 파일이 없는 빈 폴더면 클린 삭제
                Remove-Item -Recurse -Force -LiteralPath $hd -ErrorAction SilentlyContinue
                Write-Host "[+] 빈 Handoff 디렉터리 삭제 완료: $hd" -ForegroundColor Green
            }
        }
    }

    # 4-5. 레거시 빈 디렉터리 정리
    $legacyDirs = @(
        (Join-Path $samjilDir "delegate")
    )
    foreach ($ld in $legacyDirs) {
        if (Test-Path -LiteralPath $ld) {
            $ldFiles = @(Get-ChildItem -LiteralPath $ld -Recurse -File -ErrorAction SilentlyContinue)
            if ($ldFiles.Count -eq 0) {
                Remove-Item -Recurse -Force -LiteralPath $ld -ErrorAction SilentlyContinue
            }
        }
    }

    # 4-6. ~/.samjil 루트 디렉터리가 비어있으면 삭제
    $remaining = @(Get-ChildItem -LiteralPath $samjilDir -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
        Remove-Item -Force -LiteralPath $samjilDir -ErrorAction SilentlyContinue
        Write-Host "[+] 빈 ~/.samjil 디렉터리 정리 완료: $samjilDir" -ForegroundColor Green
    } else {
        Write-Host "[i] 에이전트 대화 기록이 보존되어 ~/.samjil 디렉터리를 유지합니다: $samjilDir" -ForegroundColor Cyan
    }
}

# -----------------------------------------------------------------------------
# 5. 기타 임시/원격 다운로드 패키지 정리
# -----------------------------------------------------------------------------
$remoteSkillDir = Join-Path $env:USERPROFILE ".gemini\skills\samjil-skills"
if (Test-Path $remoteSkillDir) {
    Remove-Item -Recurse -Force $remoteSkillDir -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  스킬 및 부속 도구 제거가 완료되었습니다." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
