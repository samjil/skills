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
#  * 에이전트 간 대화 기록(~/.samjil/agent-handoff/)은 소중한 자산이므로
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

# 안전한 스킬 폴더/정션 제거 함수
function Remove-SkillTarget([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $item = Get-Item -LiteralPath $Path -Force
        # 윈도우 Junction/ReparsePoint 안전 해제 (타깃 폴더 데이터 보존)
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$Path`"" > $null 2>&1
            Write-Host "[✓] 정션 링크 안전 해제: $Path" -ForegroundColor Green
        } else {
            Remove-Item -Recurse -Force -LiteralPath $Path
            Write-Host "[✓] 스킬 디렉터리 삭제 완료: $Path" -ForegroundColor Green
        }
    } catch {
        Write-Warning "삭제 실패 ($Path): $_"
    }
}

# 1. Claude Code 전역 스킬 제거 (~/.claude/skills/)
$claudeSkillsDir = Join-Path $env:USERPROFILE ".claude\skills"
$targetSkills = @("agent-handoff", "agent-delegate-agy")

foreach ($s in $targetSkills) {
    $targetPath = Join-Path $claudeSkillsDir $s
    if (Test-Path $targetPath) {
        Remove-SkillTarget $targetPath
    }
}

# 2. Antigravity 설정 정리 (~/.gemini/config/skills.json)
$skillsJsonPath = Join-Path $env:USERPROFILE ".gemini\config\skills.json"
if (Test-Path $skillsJsonPath) {
    try {
        $raw = Get-Content $skillsJsonPath -Raw -Encoding UTF8
        $json = ConvertFrom-Json $raw
        if ($json.entries) {
            $filtered = @()
            foreach ($e in $json.entries) {
                $p = $e.path
                # samjil 관련 경로만 제거하고 다른 스킬 경로는 보존
                if ($p -match "samjil" -or $p -match "agent-handoff" -or $p -match "agent-delegate-agy") {
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

# 3. 원격 irm 모드로 다운로드된 임시 스킬 폴더 정리
$remoteSkillDir = Join-Path $env:USERPROFILE ".gemini\skills\samjil-skills"
if (Test-Path $remoteSkillDir) {
    Remove-Item -Recurse -Force $remoteSkillDir -ErrorAction SilentlyContinue
    Write-Host "[✓] 원격 설치 스킬 패키지 삭제 완료: $remoteSkillDir" -ForegroundColor Green
}

# 4. 대화 기록 및 런타임 (~/.samjil/) 영구 보존
$samjilDir = Join-Path $env:USERPROFILE ".samjil"
if (Test-Path $samjilDir) {
    Write-Host "[i] 에이전트 대화 기록 및 데이터는 안전하게 보존되었습니다: $samjilDir" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  스킬 제거가 완료되었습니다." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
