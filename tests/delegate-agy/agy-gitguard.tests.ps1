# agy-gitguard.ps1(agy 가 git 상태를 바꿨는지 전후로 비교해 경고하는 안전장치) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-gitguard.tests.ps1
# 임시 git 저장소를 만들어 실제 git 으로 확인합니다(agy·워처는 띄우지 않습니다). git 이 PATH 에 있어야 합니다. 약 20초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-gitguard.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { Write-Host "git 이 없어 이 시험을 건너뜁니다."; Write-Host "통과 0 / 실패 0"; exit 0 }

# 시험용 신원(stash create·commit 에 필요). 이 프로세스에서만 쓴다.
$saved = @{}
foreach ($k in @("GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL", "AGY_GIT_GUARD", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM")) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
$env:GIT_AUTHOR_NAME = "t"; $env:GIT_AUTHOR_EMAIL = "t@example.com"; $env:GIT_COMMITTER_NAME = "t"; $env:GIT_COMMITTER_EMAIL = "t@example.com"
$env:GIT_CONFIG_NOSYSTEM = "1"
Remove-Item Env:\AGY_GIT_GUARD -ErrorAction SilentlyContinue

$work = Join-Path ([IO.Path]::GetTempPath()) ("gitguard-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)

function G([string]$Dir, [string[]]$A) { $r = Invoke-AgyGit $Dir $A; if ($r.Code -ne 0) { throw "git $($A -join ' ') 실패($($r.Code)) in $Dir" }; return $r.Out }
function New-Repo([string]$Name, [bool]$Commit = $true) {
    $d = Join-Path $work $Name
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    [void](G $d @("init", "-q", "-b", "main"))
    [void](G $d @("config", "commit.gpgsign", "false"))
    if ($Commit) {
        [IO.File]::WriteAllText((Join-Path $d "a.txt"), "one`n", $utf8)
        [void](G $d @("add", "-A")); [void](G $d @("commit", "-q", "-m", "init"))
    }
    return $d
}
function Short([string]$h) { return $h.Substring(0, 8) }

try {
    Write-Host "저장소가 아니거나 꺼져 있을 때"
    $plain = Join-Path $work "plain"; New-Item -ItemType Directory -Force -Path $plain | Out-Null
    $s = New-AgyGitGuardState @($plain) "t_plain"
    Assert-Equal "저장소가 아닌 폴더는 기록 대상이 없다" 0 @($s.Repos).Count
    Assert-Equal "  배너도 없다" "" (Get-AgyGitGuardBanner $s)
    Assert-Equal "  없는 폴더·빈 목록도 조용히 넘어간다" 0 @((New-AgyGitGuardState @((Join-Path $work "없음")) "t").Repos).Count
    Assert-Equal "  null 상태의 배너는 빈 문자열" "" (Get-AgyGitGuardBanner $null)
    $env:AGY_GIT_GUARD = "off"
    $repoOff = New-Repo "off"
    Assert-Equal "AGY_GIT_GUARD=off 면 아무것도 기록하지 않는다" 0 @((New-AgyGitGuardState @($repoOff) "t_off").Repos).Count
    Remove-Item Env:\AGY_GIT_GUARD

    Write-Host "바뀐 것이 없을 때"
    $r1 = New-Repo "clean"
    $s = New-AgyGitGuardState @($r1) "t_clean"
    Assert-Equal "저장소를 기록한다(HEAD·브랜치)" "1|main|True" ("{0}|{1}|{2}" -f @($s.Repos).Count, $s.Repos[0].Branch, ($s.Repos[0].Head -match '^[0-9a-f]{40}$'))
    Assert-Equal "  깨끗하면 스냅샷 참조를 만들지 않는다" "" $s.Repos[0].SnapRef
    Assert-Equal "  agy 가 git 을 안 건드렸으면 배너가 없다" "" (Get-AgyGitGuardBanner $s)
    [IO.File]::WriteAllText((Join-Path $r1 "a.txt"), "two`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $r1 "new.txt"), "n`n", $utf8)
    Assert-Equal "  파일만 고치고 git 상태는 그대로면 배너가 없다(agy 의 정상 작업)" "" (Get-AgyGitGuardBanner $s)
    [void](G $r1 @("checkout", "-q", "--", "a.txt")); Remove-Item (Join-Path $r1 "new.txt")

    Write-Host "agy 가 커밋했을 때"
    $r2 = New-Repo "commit"
    $s = New-AgyGitGuardState @($r2) "t_commit"
    $headBefore = $s.Repos[0].Head
    [IO.File]::WriteAllText((Join-Path $r2 "a.txt"), "agy 가 고침`n", $utf8)
    [void](G $r2 @("add", "-A")); [void](G $r2 @("commit", "-q", "-m", "agy 의 임의 커밋"))
    $b = Get-AgyGitGuardBanner $s
    Assert-Equal "경고 배너가 인용(>)으로 시작한다" $true ($b.StartsWith("> **[경고: agy 가 git 상태를 바꾼 것으로 보입니다"))
    Assert-Equal "  저장소 경로가 있다(Windows 임시 폴더의 8.3 짧은 이름 차이를 피해 폴더 이름만 본다)" $true ($b.Contains((Split-Path $r2 -Leaf)))
    Assert-Equal "  HEAD 변화(앞 8자리)와 새 커밋 제목이 있다" $true (($b -match [regex]::Escape((Short $headBefore))) -and ($b -match "agy 의 임의 커밋"))
    Assert-Equal "  복구 명령(reset --mixed <이전 HEAD>)이 있다" $true ($b -match ("reset --mixed " + $headBefore))
    Assert-Equal "  자동으로 되돌리지 않았다고 밝힌다" $true ($b -match "자동으로 되돌리지 않았습니다")
    Assert-Equal "  배너는 빈 줄 하나로 본문과 구분된다" $true ($b.EndsWith("`n`n") -and -not $b.EndsWith("`n`n`n"))
    Assert-Equal "  경고만 하고 실제로는 되돌리지 않는다(HEAD 가 그대로 새 커밋)" $true ((G $r2 @("rev-parse", "HEAD")) -ne $headBefore)
    [void](G $r2 @("reset", "-q", "--mixed", $headBefore))
    Assert-Equal "  배너의 명령대로 풀면 변경은 작업 트리에 남는다" "agy 가 고침" ([IO.File]::ReadAllText((Join-Path $r2 "a.txt"), $utf8).Trim())
    Assert-Equal "  복구 뒤에는 경고가 없다" "" (Get-AgyGitGuardBanner $s)

    Write-Host "브랜치 이동 · stash · 같은 저장소의 다른 작업"
    $r3 = New-Repo "branch"
    $s = New-AgyGitGuardState @($r3) "t_branch"
    [void](G $r3 @("switch", "-q", "-c", "agy-branch"))
    $b = Get-AgyGitGuardBanner $s
    Assert-Equal "브랜치가 바뀌면 경고(원래 브랜치로 돌아가는 명령 포함)" "True|True" ("{0}|{1}" -f ($b -match "브랜치: main -> agy-branch"), ($b -match "switch main"))
    Assert-Equal "  HEAD 는 같으니 reset 명령은 없다" $false ($b -match "reset --mixed")
    [void](G $r3 @("switch", "-q", "main"))
    $r4 = New-Repo "stash"
    $s = New-AgyGitGuardState @($r4) "t_stash"
    [IO.File]::WriteAllText((Join-Path $r4 "a.txt"), "stash 할 변경`n", $utf8)
    [void](G $r4 @("stash", "push", "-q"))
    Assert-Equal "stash 개수가 바뀌면 경고" $true ((Get-AgyGitGuardBanner $s) -match "stash 개수: 0 -> 1")
    $s = New-AgyGitGuardState @($r1) "t_conc"
    [void](G $r1 @("switch", "-q", "-c", "other"))
    Assert-Equal "같은 폴더를 쓰던 다른 위임 작업이 있으면 그 사실을 알린다" $true ((Get-AgyGitGuardBanner $s 2) -match "다른 위임 작업이 2 개")
    Assert-Equal "  없으면 그 줄이 없다" $false ((Get-AgyGitGuardBanner $s 0) -match "다른 위임 작업")
    [void](G $r1 @("switch", "-q", "main"))

    Write-Host "커밋 안 한 변경의 스냅샷"
    $r5 = New-Repo "dirty"
    [IO.File]::WriteAllText((Join-Path $r5 "a.txt"), "사용자가 고치던 중`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $r5 "untracked.txt"), "추적 안 함`n", $utf8)
    $statusBefore = G $r5 @("status", "--porcelain")
    $s = New-AgyGitGuardState @($r5) "t_dirty"
    Assert-Equal "추적 중인 파일에 변경이 있으면 스냅샷 참조를 만든다" "refs/samjil/snapshots/t_dirty" $s.Repos[0].SnapRef
    Assert-Equal "  참조가 실제 커밋을 가리킨다" $s.Repos[0].SnapHash (G $r5 @("rev-parse", "refs/samjil/snapshots/t_dirty"))
    Assert-Equal "  스냅샷이 사용자의 변경을 담고 있다" $true ((G $r5 @("show", "$($s.Repos[0].SnapHash):a.txt")) -match "사용자가 고치던 중")
    Assert-Equal "  작업 트리·인덱스는 건드리지 않았다(status 가 그대로)" $statusBefore (G $r5 @("status", "--porcelain"))
    Assert-Equal "  stash 목록에도 남지 않는다" 0 @((G $r5 @("stash", "list")) -split "\r?\n" | Where-Object { $_ }).Count
    [void](G $r5 @("add", "-A")); [void](G $r5 @("commit", "-q", "-m", "agy 커밋"))
    $b = Get-AgyGitGuardBanner $s
    Assert-Equal "  agy 가 커밋하면 배너에 스냅샷 참조와 되살리기 명령이 있다" $true (($b -match "refs/samjil/snapshots/t_dirty") -and ($b -match ("stash apply " + $s.Repos[0].SnapHash)))
    $r6 = New-Repo "untracked-only"
    [IO.File]::WriteAllText((Join-Path $r6 "u.txt"), "x`n", $utf8)
    Assert-Equal "  추적 안 하는 파일만 있으면 스냅샷은 없다(오류도 없다)" "" (New-AgyGitGuardState @($r6) "t_u").Repos[0].SnapRef

    Write-Host "여러 폴더 · 하위 폴더 · 커밋이 없는 저장소 · 오래된 스냅샷 정리"
    $sub = Join-Path $r1 "sub\deep"; New-Item -ItemType Directory -Force -Path $sub | Out-Null
    $s = New-AgyGitGuardState @($r1, $sub, $r2) "t_multi"
    Assert-Equal "같은 저장소의 하위 폴더는 한 번만 센다(저장소 둘)" 2 @($s.Repos).Count
    $leafs = @($s.Repos | ForEach-Object { Split-Path $_.Root -Leaf })
    Assert-Equal "  루트는 저장소 최상위다(하위 폴더 이름이 아니다)" $true (($leafs -contains "clean") -and ($leafs -contains "commit") -and -not ($leafs -contains "deep"))
    $r7 = New-Repo "empty" $false
    [IO.File]::WriteAllText((Join-Path $r7 "a.txt"), "x`n", $utf8)
    $s = New-AgyGitGuardState @($r7) "t_empty"
    Assert-Equal "첫 커밋도 없는 저장소는 오류 없이 HEAD 없음으로 기록한다" "1||" ("{0}|{1}|{2}" -f @($s.Repos).Count, $s.Repos[0].Head, $s.Repos[0].SnapRef)
    [void](G $r7 @("add", "-A")); [void](G $r7 @("commit", "-q", "-m", "first"))
    Assert-Equal "  agy 가 첫 커밋을 만들면 '(커밋 없음) ->' 로 알린다" $true ((Get-AgyGitGuardBanner $s) -match "HEAD: \(커밋 없음\) ->")
    $r8 = New-Repo "prune"
    for ($i = 1; $i -le 23; $i++) {
        [IO.File]::WriteAllText((Join-Path $r8 "a.txt"), "v$i`n", $utf8)
        [void](New-AgyGitGuardState @($r8) ("t_p{0:D2}" -f $i))
        Start-Sleep -Milliseconds 1100     # 커밋 시각(초 단위)으로 오래된 순을 가리므로 초가 바뀌게 한다
    }
    $refs = @((G $r8 @("for-each-ref", "--format=%(refname)", "refs/samjil/snapshots")) -split "\r?\n" | Where-Object { $_ })
    Assert-Equal "스냅샷 참조는 최근 20개만 남긴다" 20 $refs.Count
    Assert-Equal "  가장 오래된 것이 지워지고 최신 것은 남는다" "False|True" ("{0}|{1}" -f ($refs -contains "refs/samjil/snapshots/t_p01"), ($refs -contains "refs/samjil/snapshots/t_p23"))
}
finally {
    foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "Env:\$k" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
