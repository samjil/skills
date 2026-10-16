# 이 저장소를 새로 받은 PC 에서 개발을 시작할 때 한 번 돌린다(여러 번 돌려도 같은 결과).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup-dev.ps1           # 푸시 전 시험 훅을 켜고 환경을 점검한다
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup-dev.ps1 -Check    # 바꾸지 않고 상태만 본다(훅이 꺼져 있으면 종료 코드 1)
#
# 하는 일
#   1) git 훅 폴더를 .githooks 로 지정한다(git config core.hooksPath .githooks). 이 설정은 저장소 로컬이라 clone 할 때마다 한 번 필요하다.
#   2) 훅 파일(.githooks/pre-push)이 있고 첫 줄이 #!/bin/sh 이며 CRLF 가 없는지 본다(CRLF 이면 sh 가 "bad interpreter" 로 실패한다).
#   3) 도구가 있는지 알린다: git, Windows PowerShell 5.1(필수), node(뷰어 화면 시험용, 없으면 그 시험만 건너뜀).
#   4) 설치본(~/.samjil)이 소스와 어긋났는지 sync-installed.ps1 -Check 로 알려 준다(고치지는 않는다).
# 종료 코드: 0 정상 / 1 -Check 에서 훅이 꺼져 있음 / 2 훅 파일이 없거나 모양이 틀림 / 3 git 이 없음

param(
    [switch]$Check,
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Write-Item([string]$mark, [string]$text, [string]$color = "Gray") { Write-Host ("  {0} {1}" -f $mark, $text) -ForegroundColor $color }

Write-Host "개발 환경 점검: $RepoRoot"

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { Write-Item "[X]" "git 이 없습니다. Git for Windows 를 설치하세요." Red; exit 3 }
Write-Item "[v]" ("git: " + (& git --version)) Green

$psVer = $PSVersionTable.PSVersion
Write-Item "[v]" ("PowerShell: {0}.{1} (이 스크립트가 도는 호스트)" -f $psVer.Major, $psVer.Minor) Green
if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { Write-Item "[v]" "powershell.exe: 있음(훅과 시험이 이것으로 돈다)" Green } else { Write-Item "[!]" "powershell.exe 가 PATH 에 없습니다. 훅은 시험 없이 통과하고 시험은 돌릴 수 없습니다." Yellow }
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) { Write-Item "[v]" ("node: " + (& node --version) + " (뷰어 화면 시험용)") Green } else { Write-Item "[ ]" "node 가 없습니다. 뷰어 화면(node) 시험은 건너뜁니다." Yellow }

# 훅 파일 모양
$hook = Join-Path $RepoRoot ".githooks\pre-push"
if (-not (Test-Path -LiteralPath $hook)) { Write-Item "[X]" "훅 파일이 없습니다: $hook" Red; exit 2 }
$hb = [System.IO.File]::ReadAllBytes($hook)
$first = ([System.Text.Encoding]::UTF8.GetString($hb, 0, [Math]::Min(20, $hb.Length)) -split "`n")[0]
$hasCr = $false; foreach ($x in $hb) { if ($x -eq 13) { $hasCr = $true; break } }
if ($first -ne "#!/bin/sh" -or $hasCr) {
    Write-Item "[X]" "훅 파일 모양이 틀립니다(첫 줄 '$first', CR 있음=$hasCr). .gitattributes 의 '.githooks/* text eol=lf' 가 적용되지 않았을 수 있습니다: git add --renormalize . 또는 파일을 다시 받으세요." Red
    exit 2
}
Write-Item "[v]" "훅 파일: .githooks/pre-push (LF, #!/bin/sh)" Green

# 훅 켜기
$cur = ""
# 값이 없으면 git 이 아무것도 출력하지 않아 [string] 변환이 $null 이 되므로 -join 으로 받는다
try { $cur = (@(& git -C $RepoRoot config --get core.hooksPath 2>$null) -join "").Trim() } catch {}
if ($cur -eq ".githooks") {
    Write-Item "[v]" "푸시 전 시험 훅: 켜져 있음 (core.hooksPath=.githooks)" Green
} elseif ($Check) {
    Write-Item "[X]" "푸시 전 시험 훅: 꺼져 있음 (core.hooksPath='$cur'). 켜려면 -Check 없이 다시 실행하세요." Yellow
    exit 1
} else {
    & git -C $RepoRoot config core.hooksPath .githooks
    Write-Item "[v]" "푸시 전 시험 훅을 켰습니다 (core.hooksPath=.githooks, 이 저장소에만 적용)" Green
}

# 설치본 상태(고치지 않고 알리기만)
$sync = Join-Path $RepoRoot "sync-installed.ps1"
if (Test-Path -LiteralPath $sync) {
    $out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync -Check 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0) { Write-Item "[v]" "설치본(~/.samjil)이 소스와 같습니다" Green }
    else { Write-Item "[!]" "설치본이 소스와 다릅니다. 반영하려면: powershell -NoProfile -ExecutionPolicy Bypass -File sync-installed.ps1" Yellow }
}
Write-Host "끝. 시험은 tests\run-all.ps1 (빠른 실행: -Fast)"
exit 0
