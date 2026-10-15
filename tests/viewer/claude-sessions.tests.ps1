# Claude 세션 및 링크 색인 단위 테스트 (Pester 없이 실행)
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\claude-sessions.tests.ps1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sessionsScript = Join-Path $repoRoot 'runtime\viewer\claude-sessions.ps1'
$scannerScript  = Join-Path $repoRoot 'runtime\viewer\scan-claude-links.ps1'

. $sessionsScript

$script:Passed = 0
$script:Failed = 0

function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) {
        $script:Passed++
        Write-Host "  PASS  $name" -ForegroundColor Green
    }
    else {
        $script:Failed++
        Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red
    }
}

function Assert-True($name, $actual) {
    Assert-Equal $name $true ([bool]$actual)
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-test-' + [Guid]::NewGuid().ToString('N'))
$desktopDir = Join-Path $workDir 'desktop'
$projectsDir = Join-Path $workDir 'projects'
$indexFile = Join-Path $workDir 'cache\claude-links.json'

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null
    New-Item -ItemType Directory -Force -Path $projectsDir | Out-Null

    # ---------------------------------------------------------
    # 0. 환경변수 시험
    # ---------------------------------------------------------
    Write-Host "`n[0. 환경변수 디렉터리 확인]"
    $prevDesktop = $env:CLAUDE_DESKTOP_DIR
    $prevProjects = $env:CLAUDE_PROJECTS_DIR
    try {
        $env:CLAUDE_DESKTOP_DIR = $desktopDir
        $env:CLAUDE_PROJECTS_DIR = $projectsDir
        Assert-Equal "Get-ClaudeDesktopDir 가 환경변수를 우선한다" $desktopDir (Get-ClaudeDesktopDir)
        Assert-Equal "Get-ClaudeProjectsDir 가 환경변수를 우선한다" $projectsDir (Get-ClaudeProjectsDir)
    }
    finally {
        $env:CLAUDE_DESKTOP_DIR = $prevDesktop
        $env:CLAUDE_PROJECTS_DIR = $prevProjects
    }

    # ---------------------------------------------------------
    # 1. Read-ClaudeGroups 시험
    # ---------------------------------------------------------
    Write-Host "`n[1. Read-ClaudeGroups]"
    # 1-1. config 없음
    $resNoConfig = Read-ClaudeGroups -DesktopDir (Join-Path $workDir 'nonexistent')
    Assert-Equal "설정 파일 없음: Groups 는 빈 배열" 0 @($resNoConfig.Groups).Count
    Assert-Equal "설정 파일 없음: Assignments 는 빈 해시테이블" 0 $resNoConfig.Assignments.Count

    # 1-2. config 깨짐
    $cfgFile = Join-Path $desktopDir 'claude_desktop_config.json'
    [System.IO.File]::WriteAllText($cfgFile, "{ broken json", $utf8NoBom)
    $resBroken = Read-ClaudeGroups -DesktopDir $desktopDir
    Assert-Equal "설정 파일 깨짐: Groups 는 빈 배열" 0 @($resBroken.Groups).Count
    Assert-Equal "설정 파일 깨짐: Assignments 는 빈 해시테이블" 0 $resBroken.Assignments.Count

    # 1-3. config 에 키 없음
    [System.IO.File]::WriteAllText($cfgFile, '{"mcpServers":{}}', $utf8NoBom)
    $resNoKey = Read-ClaudeGroups -DesktopDir $desktopDir
    Assert-Equal "키 없음: Groups 는 빈 배열" 0 @($resNoKey.Groups).Count
    Assert-Equal "키 없음: Assignments 는 빈 해시테이블" 0 $resNoKey.Assignments.Count

    # 1-4. scope 2개, 그룹 3개(중복 1개), manual 섹션 order 순서 시험
    # scope1: groups=[cg-1, cg-2], assignments={code:local_s1: cg-1, code:local_s2: cg-2}
    # scope2: groups=[cg-2(중복), cg-3], assignments={code:local_s3: cg-3}
    # sections: cg-2 (order: 1), cg-1 (order: 2). cg-3 은 sections 에 없음 -> 뒤에 붙어야 함.
    $validConfig = @{
        preferences = @{
            epitaxyPrefs = @{
                "dframe-group-scopes" = [ordered]@{
                    "user1/org1" = @{
                        groups = @(
                            @{ id = "cg-1"; name = "프로젝트-하나" },
                            @{ id = "cg-2"; name = "프로젝트-둘" }
                        )
                        assignments = @{
                            "code:local_s1" = "cg-1"
                            "code:local_s2" = "cg-2"
                        }
                    }
                    "user2/org2" = @{
                        groups = @(
                            @{ id = "cg-2"; name = "프로젝트-둘-중복" },
                            @{ id = "cg-3"; name = "프로젝트-셋" }
                        )
                        assignments = @{
                            "code:local_s3" = "cg-3"
                        }
                    }
                }
                "dframe-code-sections" = @{
                    "user1/org1" = @{
                        sections = @(
                            @{ id = "pinned"; kind = "pinned"; order = 0 },
                            @{ id = "cg-2"; kind = "manual"; name = "프로젝트-둘"; order = 1 },
                            @{ id = "cg-1"; kind = "manual"; name = "프로젝트-하나"; order = 2 }
                        )
                    }
                }
            }
        }
    }
    $cfgJson = ConvertTo-Json -InputObject $validConfig -Depth 6
    [System.IO.File]::WriteAllText($cfgFile, $cfgJson, $utf8NoBom)

    $groupsRes = Read-ClaudeGroups -DesktopDir $desktopDir
    $groupsList = @($groupsRes.Groups)
    Assert-Equal "중복 제외 그룹 3개" 3 $groupsList.Count
    Assert-Equal "첫 번째 그룹은 섹션 order 에 따라 cg-2" "cg-2" $groupsList[0].id
    Assert-Equal "두 번째 그룹은 cg-1" "cg-1" $groupsList[1].id
    Assert-Equal "섹션에 없는 세 번째 그룹 cg-3 은 뒤에 붙음" "cg-3" $groupsList[2].id
    Assert-Equal "그룹 이름 보존(한글)" "프로젝트-둘" $groupsList[0].name

    $assigns = $groupsRes.Assignments
    Assert-Equal "assignments 의 code: 접두어가 떼어짐 (local_s1 -> cg-1)" "cg-1" $assigns["local_s1"]
    Assert-Equal "local_s2 -> cg-2" "cg-2" $assigns["local_s2"]
    Assert-Equal "local_s3 -> cg-3" "cg-3" $assigns["local_s3"]

    # ---------------------------------------------------------
    # 2. Get-ClaudeSessionTree 시험
    # ---------------------------------------------------------
    Write-Host "`n[2. Get-ClaudeSessionTree]"
    # 2-1. 세션 폴더 없음 -> Available=$false
    $treeNoSessions = Get-ClaudeSessionTree -DesktopDir (Join-Path $workDir 'nonexistent')
    Assert-Equal "세션 폴더 없음: Available 은 $false" $false $treeNoSessions.Available
    Assert-Equal "세션 폴더 없음: Projects 는 빈 배열" 0 @($treeNoSessions.Projects).Count
    Assert-Equal "세션 폴더 없음: Ungrouped 는 빈 배열" 0 @($treeNoSessions.Ungrouped).Count

    # 세션 파일 생성 준비
    $sessionsDir = Join-Path $desktopDir 'claude-code-sessions\user1\org1'
    New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null

    # local_s1 (cg-1 그룹 소속): lastActivityAt = 1770000000000 (더 예전)
    $s1Meta = @{
        sessionId      = "local_s1"
        cliSessionId   = "cli-session-1"
        title          = "세션 1 한글 제목"
        cwd            = "D:\work\repo1"
        createdAt      = 1760000000000
        lastActivityAt = 1770000000000
        isArchived     = $false
    }
    # local_s1_b (cg-1 그룹 소속): lastActivityAt = 1780000000000 (더 최근 -> s1보다 먼저 나와야 함)
    $s1bMeta = @{
        sessionId      = "local_s1_b"
        cliSessionId   = "cli-session-1b"
        title          = "세션 1-b"
        cwd            = "D:\work\repo1"
        createdAt      = 1761000000000
        lastActivityAt = 1780000000000
        isArchived     = $false
    }
    # local_s2 (cg-2 그룹 소속): archived = true
    $s2Meta = @{
        sessionId      = "local_s2"
        cliSessionId   = "cli-session-2"
        title          = "세션 2 보관본"
        cwd            = "D:\work\repo2"
        createdAt      = 1762000000000
        lastActivityAt = 1762500000000
        isArchived     = $true
    }
    # local_s4 (어느 그룹에도 배정 안 됨 -> Ungrouped)
    $s4Meta = @{
        sessionId      = "local_s4"
        cliSessionId   = "cli-session-4"
        title          = "그룹 없는 세션"
        cwd            = "D:\work\ungrouped"
        createdAt      = 1763000000000
        lastActivityAt = 1763500000000
        isArchived     = $false
    }
    # local_s5 (삭제된 그룹 cg-deleted 에 배정됨 -> Ungrouped)
    $s5Meta = @{
        sessionId      = "local_s5"
        cliSessionId   = "cli-session-5"
        title          = "삭제된 그룹 배정 세션"
        cwd            = "D:\work\deleted"
        createdAt      = 1764000000000
        lastActivityAt = 1764500000000
        isArchived     = $false
    }
    # 무시되어야 하는 파일
    $schedMeta = @{ dummy = 123 }

    [System.IO.File]::WriteAllText((Join-Path $sessionsDir 'local_s1.json'), (ConvertTo-Json -InputObject $s1Meta), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $sessionsDir 'local_s1_b.json'), (ConvertTo-Json -InputObject $s1bMeta), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $sessionsDir 'local_s2.json'), (ConvertTo-Json -InputObject $s2Meta), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $sessionsDir 'local_s4.json'), (ConvertTo-Json -InputObject $s4Meta), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $sessionsDir 'local_s5.json'), (ConvertTo-Json -InputObject $s5Meta), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $sessionsDir 'scheduled-tasks.json'), (ConvertTo-Json -InputObject $schedMeta), $utf8NoBom)

    # config 에 local_s1_b, local_s5 assignment 추가
    $validConfig.preferences.epitaxyPrefs."dframe-group-scopes"."user1/org1".assignments["code:local_s1_b"] = "cg-1"
    $validConfig.preferences.epitaxyPrefs."dframe-group-scopes"."user1/org1".assignments["code:local_s5"] = "cg-deleted"
    [System.IO.File]::WriteAllText($cfgFile, (ConvertTo-Json -InputObject $validConfig -Depth 6), $utf8NoBom)

    $tree = Get-ClaudeSessionTree -DesktopDir $desktopDir
    Assert-Equal "Available=$true" $true $tree.Available

    # Groups 는 cg-2, cg-1, cg-3 순서. cg-3 에는 세션이 0개이므로 제외되어야 함!
    # 따라서 Projects 에는 cg-2(1개), cg-1(2개) 만 나타남.
    $projects = @($tree.Projects)
    Assert-Equal "세션이 0 개인 cg-3 제외 후 프로젝트 2개" 2 $projects.Count
    Assert-Equal "첫 프로젝트는 cg-2" "cg-2" $projects[0].id
    Assert-Equal "두 번째 프로젝트는 cg-1" "cg-1" $projects[1].id

    # cg-1 안의 세션 정렬: s1_b (lastActivityAt 1780...) 가 s1 (1770...) 보다 앞에 와야 함
    $cg1Sessions = @($projects[1].sessions)
    Assert-Equal "cg-1 그룹에 세션 2개" 2 $cg1Sessions.Count
    Assert-Equal "최근 활동이 더 늦은 cli-session-1b 가 첫 번째" "cli-session-1b" $cg1Sessions[0].id
    Assert-Equal "cli-session-1 가 두 번째" "cli-session-1" $cg1Sessions[1].id
    Assert-True "시각 형식이 yyyy-MM-dd HH:mm:ss" ($cg1Sessions[0].created -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')
    Assert-True "lastActivity 시각 형식" ($cg1Sessions[0].lastActivity -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')

    # cg-2 안의 세션 보관(archived) 플래그
    $cg2Sessions = @($projects[0].sessions)
    Assert-Equal "cg-2 세션 보관 여부 true" $true $cg2Sessions[0].archived

    # Ungrouped 세션: 배정 없는 cli-4 와 삭제된 그룹 배정 cli-5
    $ungrouped = @($tree.Ungrouped)
    Assert-Equal "Ungrouped 세션 2개" 2 $ungrouped.Count
    $ungroupedIds = @($ungrouped | ForEach-Object { $_.id })
    Assert-True "cli-session-4 가 Ungrouped 에 포함" ($ungroupedIds -contains "cli-session-4")
    Assert-True "삭제된 그룹의 cli-session-5 가 Ungrouped 에 포함" ($ungroupedIds -contains "cli-session-5")

    # config 파일이 아예 없을 때 -> 모든 세션이 Ungrouped
    Remove-Item -LiteralPath $cfgFile -Force
    $treeNoCfg = Get-ClaudeSessionTree -DesktopDir $desktopDir
    Assert-Equal "config 없음: Projects 는 0개" 0 @($treeNoCfg.Projects).Count
    Assert-Equal "config 없음: 모든 세션 5개가 Ungrouped" 5 @($treeNoCfg.Ungrouped).Count

    # config 복원
    [System.IO.File]::WriteAllText($cfgFile, (ConvertTo-Json -InputObject $validConfig -Depth 6), $utf8NoBom)

    # ---------------------------------------------------------
    # 3. Update-ClaudeLinkIndex & Read-ClaudeLinkIndex 시험
    # ---------------------------------------------------------
    Write-Host "`n[3. Update-ClaudeLinkIndex & Read-ClaudeLinkIndex]"

    $projFolder1 = Join-Path $projectsDir "enc-folder-1"
    $projFolder2 = Join-Path $projectsDir "enc-folder-2"
    New-Item -ItemType Directory -Force -Path $projFolder1 | Out-Null
    New-Item -ItemType Directory -Force -Path $projFolder2 | Out-Null

    # 세션 1 파일: cli-session-1.jsonl
    # 작업: claude_1791969860_1001, 메시지: 0004-c2a-카드-그림자.md
    # 공통 작업: claude_1791969860_2001 (ts: 2026-10-14T08:30:00.000Z)
    # 동일 ts 작업: claude_1791969860_3001 (ts: 2026-10-14T12:00:00.000Z)
    $s1Log = Join-Path $projFolder1 'cli-session-1.jsonl'
    $s1Lines = @(
        '{"timestamp":"2026-10-14T08:00:00.000Z","message":"작업 요청: claude_1791969860_1001 및 0004-c2a-카드-그림자.md"}',
        '{"timestamp":"2026-10-14T08:30:00.000Z","message":"공통 작업 claude_1791969860_2001 실행"}',
        '{"timestamp":"2026-10-14T12:00:00.000Z","message":"동일시각 작업 claude_1791969860_3001"}'
    )
    [System.IO.File]::WriteAllText($s1Log, (($s1Lines -join "`n") + "`n"), $utf8NoBom)

    # 세션 2 파일: cli-session-2.jsonl
    # 공통 작업: claude_1791969860_2001 (ts: 2026-10-14T08:15:00.000Z -> s1보다 이름!)
    # 세션2 고유: claude_1791969860_4001_a, 메시지: 0005-a2c-결과-보고.md
    # 동일 ts 작업: claude_1791969860_3001 (ts: 2026-10-14T12:00:00.000Z -> createdAt 비교: s1(1760) < s2(1762) -> s1이 승리)
    $s2Log = Join-Path $projFolder2 'cli-session-2.jsonl'
    $s2Lines = @(
        '{"timestamp":"2026-10-14T08:15:00.000Z","message":"포크 세션에서 claude_1791969860_2001 먼저 발생"}',
        '{"timestamp":"2026-10-14T09:00:00.000Z","message":"세션2 작업 claude_1791969860_4001_a 및 0005-a2c-결과-보고.md"}',
        '{"timestamp":"2026-10-14T12:00:00.000Z","message":"동일시각 작업 claude_1791969860_3001"}'
    )
    [System.IO.File]::WriteAllText($s2Log, (($s2Lines -join "`n") + "`n"), $utf8NoBom)

    # (a), (b), (f) 첫 스캔 실행 (cli-session-1b, 4, 5는 대화 기록이 없으므로 무시됨)
    $scan1 = Update-ClaudeLinkIndex -IndexFile $indexFile -DesktopDir $desktopDir -ProjectsDir $projectsDir
    Assert-Equal "첫 스캔에서 파일 2개 읽음" 2 $scan1.Scanned
    Assert-True "읽은 바이트 수 > 0" ($scan1.NewBytes -gt 0)

    $read1 = Read-ClaudeLinkIndex -IndexFile $indexFile
    Assert-Equal "작업 1001 은 cli-session-1 소유" "cli-session-1" $read1.Tasks["claude_1791969860_1001"]
    Assert-Equal "한글 메시지 0004-c2a-카드-그림자.md 는 cli-session-1 소유" "cli-session-1" $read1.Msgs["0004-c2a-카드-그림자.md"]
    Assert-Equal "작업 4001_a 는 cli-session-2 소유" "cli-session-2" $read1.Tasks["claude_1791969860_4001_a"]
    Assert-Equal "메시지 0005-a2c-결과-보고.md 는 cli-session-2 소유" "cli-session-2" $read1.Msgs["0005-a2c-결과-보고.md"]

    # (b) 시각 비교: 2001 은 cli-session-2 가 08:15 로 더 이르므로 cli-session-2 소유
    Assert-Equal "공통 작업 2001 은 시각이 더 이른 cli-session-2 가 소유" "cli-session-2" $read1.Tasks["claude_1791969860_2001"]
    # (b) 시각 같을 때 createdAt 비교: s1(1760000000000) < s2(1762000000000) -> s1 소유
    Assert-Equal "동일 시각 작업 3001 은 createdAt 이 더 이른 cli-session-1 이 소유" "cli-session-1" $read1.Tasks["claude_1791969860_3001"]

    # (c) 증분 스캔: 두 번째 호출에서 NewBytes 가 0
    $scan2 = Update-ClaudeLinkIndex -IndexFile $indexFile -DesktopDir $desktopDir -ProjectsDir $projectsDir
    Assert-Equal "두 번째 호출에서 새로 읽은 바이트는 0" 0 $scan2.NewBytes
    Assert-Equal "두 번째 호출에서 스캔된 파일 수 0" 0 $scan2.Scanned

    # (c) 줄 덧붙이기: 새 줄만 읽고 새 ID 가 색인에 들어옴
    $newLine = '{"timestamp":"2026-10-14T13:00:00.000Z","message":"새 작업 claude_1791969860_5001"}' + "`n"
    [System.IO.File]::AppendAllText($s1Log, $newLine, $utf8NoBom)

    $scan3 = Update-ClaudeLinkIndex -IndexFile $indexFile -DesktopDir $desktopDir -ProjectsDir $projectsDir
    Assert-Equal "줄 덧붙인 후 파일 1개 스캔" 1 $scan3.Scanned
    Assert-True "새로 읽은 바이트 > 0" ($scan3.NewBytes -gt 0)
    $read3 = Read-ClaudeLinkIndex -IndexFile $indexFile
    Assert-Equal "새 작업 5001 이 색인에 추가됨" "cli-session-1" $read3.Tasks["claude_1791969860_5001"]

    # (d) 마지막 줄이 줄바꿈 없이 덜 써졌을 때: 처리되지 않다가 줄바꿈 붙은 뒤 처리
    $incomplete = '{"timestamp":"2026-10-14T14:00:00.000Z","message":"덜 써진 줄 claude_1791969860_9999'
    [System.IO.File]::AppendAllText($s1Log, $incomplete, $utf8NoBom)

    $scan4 = Update-ClaudeLinkIndex -IndexFile $indexFile -DesktopDir $desktopDir -ProjectsDir $projectsDir
    $read4 = Read-ClaudeLinkIndex -IndexFile $indexFile
    Assert-Equal "줄바꿈 없는 미완성 줄의 9999 는 아직 색인에 없음" $false ($read4.Tasks.ContainsKey("claude_1791969860_9999"))

    # 줄바꿈 붙여서 완성
    [System.IO.File]::AppendAllText($s1Log, "`"}`n", $utf8NoBom)
    $scan5 = Update-ClaudeLinkIndex -IndexFile $indexFile -DesktopDir $desktopDir -ProjectsDir $projectsDir
    $read5 = Read-ClaudeLinkIndex -IndexFile $indexFile
    Assert-Equal "줄바꿈이 붙은 뒤 9999 가 색인에 들어옴" "cli-session-1" $read5.Tasks["claude_1791969860_9999"]

    # (e) 파일이 줄어들면(size < offset) 그 세션을 처음부터 다시 읽음
    # s2Log 를 작은 내용으로 다시 쓰기
    $s2NewLines = @(
        '{"timestamp":"2026-10-14T15:00:00.000Z","message":"리셋 후 단독 작업 claude_1791969860_7777"}'
    )
    [System.IO.File]::WriteAllText($s2Log, (($s2NewLines -join "`n") + "`n"), $utf8NoBom)

    $scan6 = Update-ClaudeLinkIndex -IndexFile $indexFile -DesktopDir $desktopDir -ProjectsDir $projectsDir
    $read6 = Read-ClaudeLinkIndex -IndexFile $indexFile
    Assert-Equal "s2 가 리셋된 후 새 작업 7777 반영" "cli-session-2" $read6.Tasks["claude_1791969860_7777"]
    Assert-Equal "s2 의 이전 작업 4001_a 는 제거됨" $false ($read6.Tasks.ContainsKey("claude_1791969860_4001_a"))

    # (h) 깨진 색인 파일 -> 다시 만듦
    [System.IO.File]::WriteAllText($indexFile, "{ broken index json", $utf8NoBom)
    $scanBroken = Update-ClaudeLinkIndex -IndexFile $indexFile -DesktopDir $desktopDir -ProjectsDir $projectsDir
    $readBroken = Read-ClaudeLinkIndex -IndexFile $indexFile
    Assert-True "깨진 색인 복구 후 정상 읽힘" ($null -ne $readBroken.Tasks)
    Assert-Equal "복구 후 7777 존재" "cli-session-2" $readBroken.Tasks["claude_1791969860_7777"]

    # (i) Read-ClaudeLinkIndex 캐시 동작 검증
    $cached1 = Read-ClaudeLinkIndex -IndexFile $indexFile
    $cached2 = Read-ClaudeLinkIndex -IndexFile $indexFile
    Assert-Equal "동일 파일 두 번 읽었을 때 캐시된 동일 결과 반환" $cached1.Updated $cached2.Updated
    Assert-Equal "캐시 결과 객체 키 동일" $cached1.Tasks.Count $cached2.Tasks.Count

    # 인덱스 파일에 새 내용 쓰기 (수정 시각 및 크기 변경)
    Start-Sleep -Milliseconds 50
    $newIndexObj = @{ version = 1; files = @{}; tasks = @{ "test_cached_task" = @{ session = "cli-session-test"; ts = "2026-10-15 12:00:00" } }; msgs = @{}; updated = "2026-10-15 12:00:00" }
    [System.IO.File]::WriteAllText($indexFile, (ConvertTo-Json -InputObject $newIndexObj -Depth 5), $utf8NoBom)
    (Get-Item -LiteralPath $indexFile).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddSeconds(5)

    $readUpdated = Read-ClaudeLinkIndex -IndexFile $indexFile
    Assert-Equal "파일 갱신 후 새 작업 즉시 반영" "cli-session-test" $readUpdated.Tasks["test_cached_task"]
    Assert-Equal "파일 갱신 후 updated 필드 반영" "2026-10-15 12:00:00" $readUpdated.Updated

    # (i) scan-claude-links.ps1 를 새 powershell.exe 로 실행
    Write-Host "`n[4. scan-claude-links.ps1 외부 프로세스 실행]"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scannerScript`" -IndexFile `"$indexFile`" -DesktopDir `"$desktopDir`" -ProjectsDir `"$projectsDir`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit(10000) | Out-Null
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    Assert-Equal "스캐너 프로세스 정상 종료(exit 0)" 0 $p.ExitCode
    Assert-Equal ".running 파일이 남지 않음" $false (Test-Path -LiteralPath "$indexFile.running")
    Assert-Equal ".error 파일이 없음" $false (Test-Path -LiteralPath "$indexFile.error")
    Assert-True "색인 파일이 존재함" (Test-Path -LiteralPath $indexFile)

    # ---------------------------------------------------------
    # 4. 수 MB 대용량 한 줄 및 한글 검증
    # ---------------------------------------------------------
    Write-Host "`n[5. 수 MB 대용량 한 줄 & 한글 깨짐 검증]"
    $bigPadding = New-Object string ('가', 2000000) # 한글 200만 글자 (~6MB)
    $bigLine = '{"timestamp":"2026-10-14T16:00:00.000Z","message":"대용량 ' + $bigPadding + ' claude_1791969860_8888 및 0006-c2a-초대용량-메시지.md"}' + "`n"
    [System.IO.File]::AppendAllText($s1Log, $bigLine, $utf8NoBom)

    $scanBig = Update-ClaudeLinkIndex -IndexFile $indexFile -DesktopDir $desktopDir -ProjectsDir $projectsDir
    $readBig = Read-ClaudeLinkIndex -IndexFile $indexFile
    Assert-Equal "수 MB 줄에서 8888 작업 정상 추출" "cli-session-1" $readBig.Tasks["claude_1791969860_8888"]
    Assert-Equal "수 MB 줄에서 한글 파일명 정상 추출" "cli-session-1" $readBig.Msgs["0006-c2a-초대용량-메시지.md"]

}
finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
