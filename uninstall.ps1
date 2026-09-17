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
#  * 에이전트 간 대화 기록(~/.samjil/agent-handoff/<프로젝트>/msg/)은 사용자의 소중한 자산이므로
#    제거 시에도 절대 삭제되지 않고 영구 보존됩니다.
# ==========================================================

param(
    [switch]$Force = $false
)

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
            Write-Host "[✓] 정션 링크 해제: $Path" -ForegroundColor Green
        } else {
            Remove-Item -Recurse -Force -LiteralPath $Path
            Write-Host "[✓] 스킬 디렉터리 삭제 완료: $Path" -ForegroundColor Green
        }
    } catch {
        Write-Warning "삭제 실패 ($Path): $_"
    }
}

$targetSkills = @("agent-handoff", "agent-delegate-agy")

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
                    Write-Host "[✓] Antigravity skills.json 등록 해제: $p" -ForegroundColor Green
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

# -----------------------------------------------------------------------------
# 4. 부속 도구 및 런타임 정리 (~/.samjil/)
# -----------------------------------------------------------------------------
$samjilDir = Join-Path $env:USERPROFILE ".samjil"
if (Test-Path -LiteralPath $samjilDir) {
    # 4-1. Delegate 디렉터리 (scripts + runtime) 제거
    $delegateDir = Join-Path $samjilDir "agent-delegate-agy"
    if (Test-Path -LiteralPath $delegateDir) {
        Remove-Item -Recurse -Force -LiteralPath $delegateDir -ErrorAction SilentlyContinue
        Write-Host "[✓] Delegate 도구 및 런타임 삭제 완료: $delegateDir" -ForegroundColor Green
    }

    # 4-2. Handoff 웹 뷰어 도구 (~/.samjil/agent-handoff/viewer) 제거
    $handoffViewer = Join-Path $samjilDir "agent-handoff\viewer"
    if (Test-Path -LiteralPath $handoffViewer) {
        Remove-Item -Recurse -Force -LiteralPath $handoffViewer -ErrorAction SilentlyContinue
        Write-Host "[✓] Handoff 웹 뷰어 도구 삭제 완료: $handoffViewer" -ForegroundColor Green
    }

    # 4-3. Handoff 대화 저장소 처리 (~/.samjil/agent-handoff/)
    $handoffDir = Join-Path $samjilDir "agent-handoff"
    if (Test-Path -LiteralPath $handoffDir) {
        # 실제 대화 파일(.md)이 남아있는지 확인
        $handoffFiles = @(Get-ChildItem -LiteralPath $handoffDir -Recurse -File -Filter "*.md" -ErrorAction SilentlyContinue)
        if ($handoffFiles.Count -gt 0) {
            # 실제 대화 기록이 있으면 100% 영구 보존!
            Write-Host "[i] 에이전트 대화 기록($($handoffFiles.Count)건)이 존재하여 안전하게 보존합니다: $handoffDir" -ForegroundColor Cyan
        } else {
            # 대화 파일이 없는 빈 폴더면 클린 삭제
            Remove-Item -Recurse -Force -LiteralPath $handoffDir -ErrorAction SilentlyContinue
            Write-Host "[✓] 빈 Handoff 디렉터리 삭제 완료: $handoffDir" -ForegroundColor Green
        }
    }

    # 4-4. 레거시 빈 디렉터리 정리
    $legacyDirs = @(
        (Join-Path $samjilDir "delegate"),
        (Join-Path $samjilDir "handoff")
    )
    foreach ($ld in $legacyDirs) {
        if (Test-Path -LiteralPath $ld) {
            $ldFiles = @(Get-ChildItem -LiteralPath $ld -Recurse -File -ErrorAction SilentlyContinue)
            if ($ldFiles.Count -eq 0) {
                Remove-Item -Recurse -Force -LiteralPath $ld -ErrorAction SilentlyContinue
            }
        }
    }

    # 4-5. ~/.samjil 루트 디렉터리가 비어있으면 삭제
    $remaining = @(Get-ChildItem -LiteralPath $samjilDir -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
        Remove-Item -Force -LiteralPath $samjilDir -ErrorAction SilentlyContinue
        Write-Host "[✓] 빈 ~/.samjil 디렉터리 정리 완료: $samjilDir" -ForegroundColor Green
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
