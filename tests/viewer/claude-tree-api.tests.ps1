# Claude 세션 트리 및 링크 색인 API (/api/claude/tree) 테스트 (Pester 없이 실행)
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\claude-tree-api.tests.ps1

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$viewerScript = Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"

$script:Passed = 0
$script:Failed = 0

function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) {
        $script:Passed++
        Write-Host "  PASS  $name" -ForegroundColor Green
    } else {
        $script:Failed++
        Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red
    }
}

function Assert-True($name, $actual) {
    Assert-Equal $name $true ([bool]$actual)
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-tree-test-" + [Guid]::NewGuid().ToString("N"))
$desktopDir = Join-Path $workDir "desktop"
$projectsDir = Join-Path $workDir "projects"
$dataDir = Join-Path $workDir "data"
$handoffDir = Join-Path $workDir "handoff"

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$viewer1 = $null
$viewer2 = $null
$prevDesktopEnv = $env:CLAUDE_DESKTOP_DIR
$prevProjectsEnv = $env:CLAUDE_PROJECTS_DIR

try {
    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null
    New-Item -ItemType Directory -Force -Path $projectsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    New-Item -ItemType Directory -Force -Path $handoffDir | Out-Null

    # 1. 가짜 Claude Desktop 설정 파일 생성
    # 그룹 2개: cg-proj1 (세션 3개 배정), cg-empty (세션 0개 배정)
    $cfgObj = @{
        preferences = @{
            epitaxyPrefs = @{
                "dframe-group-scopes" = [ordered]@{
                    "user1/org1" = @{
                        groups = @(
                            @{ id = "cg-proj1"; name = "프로젝트-하나" },
                            @{ id = "cg-empty"; name = "빈-프로젝트" }
                        )
                        assignments = @{
                            "code:local_s1" = "cg-proj1"
                            "code:local_s2" = "cg-proj1"
                            "code:local_s3" = "cg-proj1"
                        }
                    }
                }
            }
        }
    }
    $cfgJson = ConvertTo-Json -InputObject $cfgObj -Depth 6
    [System.IO.File]::WriteAllText((Join-Path $desktopDir "claude_desktop_config.json"), $cfgJson, $utf8NoBom)

    # 2. 세션 메타데이터 생성 (그룹 소속 3개 + 그룹 없는 세션 1개)
    $sessionsDir = Join-Path $desktopDir "claude-code-sessions\user1\org1"
    New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null

    $s1Meta = @{
        sessionId      = "local_s1"
        cliSessionId   = "cli-session-1"
        title          = "세션 1 제목"
        cwd            = "D:\work\repo1"
        createdAt      = 1760000000000
        lastActivityAt = 1770000000000
        isArchived     = $false
    }
    $s2Meta = @{
        sessionId      = "local_s2"
        cliSessionId   = "cli-session-2"
        title          = "세션 2 제목"
        cwd            = "D:\work\repo1"
        createdAt      = 1761000000000
        lastActivityAt = 1775000000000
        isArchived     = $false
    }
    $s3Meta = @{
        sessionId      = "local_s3"
        cliSessionId   = "cli-session-3"
        title          = "세션 3 보관"
        cwd            = "D:\work\repo1"
        createdAt      = 1762000000000
        lastActivityAt = 1765000000000
        isArchived     = $true
    }
    $sUngroupedMeta = @{
        sessionId      = "local_ungrouped"
        cliSessionId   = "cli-session-ungrouped"
        title          = "그룹 없는 세션"
        cwd            = "D:\work\ungrouped"
        createdAt      = 1763000000000
        lastActivityAt = 1768000000000
        isArchived     = $false
    }

    [System.IO.File]::WriteAllText((Join-Path $sessionsDir "local_s1.json"), (ConvertTo-Json -InputObject $s1Meta), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $sessionsDir "local_s2.json"), (ConvertTo-Json -InputObject $s2Meta), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $sessionsDir "local_s3.json"), (ConvertTo-Json -InputObject $s3Meta), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $sessionsDir "local_ungrouped.json"), (ConvertTo-Json -InputObject $sUngroupedMeta), $utf8NoBom)

    # 3. 대화 기록 파일 생성 (위임 작업 ID 와 인수인계 메시지 파일)
    $projLogsDir = Join-Path $projectsDir "enc-folder-1"
    New-Item -ItemType Directory -Force -Path $projLogsDir | Out-Null

    $s1LogFile = Join-Path $projLogsDir "cli-session-1.jsonl"
    $s1Lines = @(
        '{"timestamp":"2026-10-14T08:00:00.000Z","message":"작업 claude_1791969860_1001 및 0001-c2a-기능구현.md 요청"}'
    )
    [System.IO.File]::WriteAllText($s1LogFile, (($s1Lines -join "`n") + "`n"), $utf8NoBom)

    $s2LogFile = Join-Path $projLogsDir "cli-session-2.jsonl"
    $s2Lines = @(
        '{"timestamp":"2026-10-14T09:00:00.000Z","message":"작업 claude_1791969860_2001 및 0002-a2c-보고서.md 완료"}'
    )
    [System.IO.File]::WriteAllText($s2LogFile, (($s2Lines -join "`n") + "`n"), $utf8NoBom)

    # 4. 뷰어 기동
    $env:CLAUDE_DESKTOP_DIR = $desktopDir
    $env:CLAUDE_PROJECTS_DIR = $projectsDir
    $port1 = Get-Random -Minimum 30000 -Maximum 40000

    $argList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$viewerScript`"",
        "-NoBrowser", "-NoAgent",
        "-Port", $port1,
        "-DataDir", "`"$dataDir`"",
        "-HandoffDir", "`"$handoffDir`""
    )
    $viewer1 = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden -PassThru

    $up = $false
    for ($i = 0; $i -lt 40 -and -not $up; $i++) {
        Start-Sleep -Milliseconds 300
        try {
            $up = ((Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port1/api/status" -TimeoutSec 2).StatusCode -eq 200)
        } catch {}
    }
    Assert-True "뷰어 서버 기동 성공" $up

    # -------------------------------------------------------------
    # 시험 1: 첫 요청 및 스캔 완료 대기 (폴링 최대 60초)
    # -------------------------------------------------------------
    Write-Host "`n[시험 1: 첫 요청 및 스캔 폴링]"
    $firstResp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port1/api/claude/tree" -TimeoutSec 5
    Assert-Equal "첫 요청 200 응답" 200 $firstResp.StatusCode

    $firstRaw = [System.Text.Encoding]::UTF8.GetString($firstResp.RawContentStream.ToArray())
    $firstJson = ConvertFrom-Json -InputObject $firstRaw

    Assert-Equal "available=true" $true $firstJson.available
    Assert-Equal "세션 있는 그룹(cg-proj1)만 포함되어 projects 는 1개" 1 @($firstJson.projects).Count
    Assert-Equal "첫 번째 프로젝트 id 는 cg-proj1" "cg-proj1" $firstJson.projects[0].id
    Assert-Equal "첫 번째 프로젝트 sessions 는 3개" 3 @($firstJson.projects[0].sessions).Count
    Assert-Equal "ungrouped 세션 1개" 1 @($firstJson.ungrouped).Count
    Assert-Equal "ungrouped 세션 id" "cli-session-ungrouped" $firstJson.ungrouped[0].id

    # 세션 필드(id, title, cwd, created, lastActivity, archived) 검증
    $sFields = @("id", "title", "cwd", "created", "lastActivity", "archived")
    $firstSession = $firstJson.projects[0].sessions[0]
    foreach ($fld in $sFields) {
        Assert-True ("projects 세션에 $fld 필드 존재") ($firstSession.PSObject.Properties[$fld] -ne $null)
    }
    $ungroupedSession = $firstJson.ungrouped[0]
    foreach ($fld in $sFields) {
        Assert-True ("ungrouped 세션에 $fld 필드 존재") ($ungroupedSession.PSObject.Properties[$fld] -ne $null)
    }

    # 스캔 폴링: scanning=false 이고 taskLinks / handoffLinks 가 채워질 때까지 대기
    Write-Host "스캔 완료 대기 중..."
    $pollJson = $firstJson
    $pollRaw = $firstRaw
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 60) {
        if (-not $pollJson.scanning -and $pollJson.taskLinks.PSObject.Properties["claude_1791969860_1001"]) {
            break
        }
        Start-Sleep -Milliseconds 300
        $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port1/api/claude/tree" -TimeoutSec 5
        $pollRaw = [System.Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        $pollJson = ConvertFrom-Json -InputObject $pollRaw
    }
    $sw.Stop()

    Assert-Equal "스캔 완료 후 scanning=false" $false $pollJson.scanning
    Assert-Equal "작업 1001 -> cli-session-1 연결" "cli-session-1" $pollJson.taskLinks."claude_1791969860_1001"
    Assert-Equal "작업 2001 -> cli-session-2 연결" "cli-session-2" $pollJson.taskLinks."claude_1791969860_2001"
    Assert-Equal "메시지 0001 -> cli-session-1 연결" "cli-session-1" $pollJson.handoffLinks."0001-c2a-기능구현.md"
    Assert-Equal "메시지 0002 -> cli-session-2 연결" "cli-session-2" $pollJson.handoffLinks."0002-a2c-보고서.md"
    Assert-True "updated 필드가 채워짐" (-not [string]::IsNullOrEmpty($pollJson.updated))

    # -------------------------------------------------------------
    # 시험 2: 응답 JSON 원문 모양 검증 (배열 및 객체 유지)
    # -------------------------------------------------------------
    Write-Host "`n[시험 2: JSON 원문 모양 검증]"
    Assert-True "projects 가 JSON 배열로 나감" ($pollRaw -match '"projects":\s*\[')
    Assert-True "ungrouped 가 JSON 배열로 나감" ($pollRaw -match '"ungrouped":\s*\[')
    Assert-True "sessions 가 JSON 배열로 나감" ($pollRaw -match '"sessions":\s*\[')
    Assert-True "taskLinks 가 JSON 객체로 나감" ($pollRaw -match '"taskLinks":\s*\{')
    Assert-True "handoffLinks 가 JSON 객체로 나감" ($pollRaw -match '"handoffLinks":\s*\{')

    # 원소 하나뿐인 그룹 + 빈 ungrouped 상황 테스트
    # local_ungrouped, local_s2, local_s3 삭제
    Remove-Item (Join-Path $sessionsDir "local_ungrouped.json") -Force
    Remove-Item (Join-Path $sessionsDir "local_s2.json") -Force
    Remove-Item (Join-Path $sessionsDir "local_s3.json") -Force

    $singleResp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port1/api/claude/tree" -TimeoutSec 5
    $singleRaw = [System.Text.Encoding]::UTF8.GetString($singleResp.RawContentStream.ToArray())
    $singleJson = ConvertFrom-Json -InputObject $singleRaw

    Assert-Equal "단일 프로젝트 남음" 1 @($singleJson.projects).Count
    Assert-Equal "단일 프로젝트 내 세션 1개" 1 @($singleJson.projects[0].sessions).Count
    Assert-Equal "ungrouped 0개" 0 @($singleJson.ungrouped).Count
    Assert-True "원소 1개여도 projects 는 JSON 배열" ($singleRaw -match '"projects":\s*\[')
    Assert-True "원소 1개여도 sessions 는 JSON 배열" ($singleRaw -match '"sessions":\s*\[')
    Assert-True "0개여도 ungrouped 는 JSON 배열" ($singleRaw -match '"ungrouped":\s*\[')

    # -------------------------------------------------------------
    # 시험 3: 스캔 시작 규칙 (15초 신선도 & 20초 전 되돌림 시 재스캔)
    # -------------------------------------------------------------
    Write-Host "`n[시험 3: 스캔 시작 규칙]"
    # 색인이 신선한 상태(15초 안)에서 연달아 5번 요청
    for ($k = 0; $k -lt 5; $k++) {
        Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port1/api/claude/tree" -TimeoutSec 5 | Out-Null
    }
    # 이 시험이 띄운 뷰어의 스캔만 센다(-IndexFile 이 이 시험의 임시 $dataDir 안). 컴퓨터 전체에서 세면 같은 순간 운영 뷰어나 다른 시험의 뷰어가 띄운
    # 스캔이 잡혀 가끔 실패했다(병렬 실행에서 재현해 원인을 확인).
    $runningScanners = @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.Name -like "powershell*" -and $_.CommandLine -like "*scan-claude-links.ps1*" -and $_.CommandLine -like "*$dataDir*" })
    Assert-Equal "신선한 색인일 때 새 스캔 프로세스가 뜨지 않음" 0 $runningScanners.Count

    # 메모리 5초 런치 유예를 안전하게 넘기기 위해 잠시 대기 (최대 6초)
    Start-Sleep -Seconds 6

    # 대화 기록에 새 줄 덧붙이기
    $newLine = '{"timestamp":"2026-10-14T10:00:00.000Z","message":"새 작업 claude_1791969860_9001 추가"}' + "`n"
    [System.IO.File]::AppendAllText($s1LogFile, $newLine, $utf8NoBom)

    # 색인 파일 수정 시각을 20초 전으로 되돌림
    $indexFile = Join-Path $dataDir "cache\claude-links.json"
    (Get-Item -LiteralPath $indexFile).LastWriteTime = (Get-Date).AddSeconds(-20)

    # 요청 보내면 스캔이 다시 트리거됨
    $rescanResp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port1/api/claude/tree" -TimeoutSec 5
    Assert-Equal "재스캔 트리거 후 200 응답" 200 $rescanResp.StatusCode

    # 새 작업 ID 9001 이 색인에 나타날 때까지 폴링 (최대 30초)
    $rescanPollJson = $null
    $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw2.Elapsed.TotalSeconds -lt 30) {
        $r2 = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port1/api/claude/tree" -TimeoutSec 5
        $rescanPollJson = ConvertFrom-Json -InputObject ([System.Text.Encoding]::UTF8.GetString($r2.RawContentStream.ToArray()))
        if (-not $rescanPollJson.scanning -and $rescanPollJson.taskLinks.PSObject.Properties["claude_1791969860_9001"]) {
            break
        }
        Start-Sleep -Milliseconds 300
    }
    $sw2.Stop()
    Assert-Equal "재스캔 후 새 작업 9001 이 색인에 반영됨" "cli-session-1" $rescanPollJson.taskLinks."claude_1791969860_9001"

    # -------------------------------------------------------------
    # 시험 4: 오류 처리 (깨진 색인 파일)
    # -------------------------------------------------------------
    Write-Host "`n[시험 4: 깨진 색인 파일 오류 처리]"
    [System.IO.File]::WriteAllText($indexFile, "{ not valid json !!", $utf8NoBom)

    $brokenResp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port1/api/claude/tree" -TimeoutSec 5
    Assert-Equal "깨진 색인에도 200 응답" 200 $brokenResp.StatusCode
    $brokenRaw = [System.Text.Encoding]::UTF8.GetString($brokenResp.RawContentStream.ToArray())
    $brokenJson = ConvertFrom-Json -InputObject $brokenRaw

    Assert-Equal "available 은 계속 true" $true $brokenJson.available
    Assert-True "projects 는 배열" ($brokenRaw -match '"projects":\s*\[')
    Assert-True "ungrouped 는 배열" ($brokenRaw -match '"ungrouped":\s*\[')
    Assert-True "taskLinks 는 객체" ($brokenRaw -match '"taskLinks":\s*\{')
    Assert-True "handoffLinks 는 객체" ($brokenRaw -match '"handoffLinks":\s*\{')

    # -------------------------------------------------------------
    # 시험 5: Desktop 폴더가 아예 없는 환경
    # -------------------------------------------------------------
    Write-Host "`n[시험 5: Desktop 폴더가 없는 환경]"
    # 기존 뷰어 종료
    if ($viewer1 -and -not $viewer1.HasExited) {
        Stop-Process -Id $viewer1.Id -Force -ErrorAction SilentlyContinue
        $viewer1 = $null
    }

    $nonexistentDesktop = Join-Path $workDir "nonexistent-desktop"
    $env:CLAUDE_DESKTOP_DIR = $nonexistentDesktop
    $port2 = Get-Random -Minimum 30000 -Maximum 40000

    $argList2 = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$viewerScript`"",
        "-NoBrowser", "-NoAgent",
        "-Port", $port2,
        "-DataDir", "`"$dataDir`"",
        "-HandoffDir", "`"$handoffDir`""
    )
    $viewer2 = Start-Process -FilePath "powershell.exe" -ArgumentList $argList2 -WindowStyle Hidden -PassThru

    $up2 = $false
    for ($i = 0; $i -lt 40 -and -not $up2; $i++) {
        Start-Sleep -Milliseconds 300
        try {
            $up2 = ((Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port2/api/status" -TimeoutSec 2).StatusCode -eq 200)
        } catch {}
    }
    Assert-True "두 번째 뷰어 서버 기동 성공" $up2

    $noDesktopResp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port2/api/claude/tree" -TimeoutSec 5
    Assert-Equal "Desktop 없는 환경 200 응답" 200 $noDesktopResp.StatusCode
    $noDesktopRaw = [System.Text.Encoding]::UTF8.GetString($noDesktopResp.RawContentStream.ToArray())
    $noDesktopJson = ConvertFrom-Json -InputObject $noDesktopRaw

    Assert-Equal "available=false" $false $noDesktopJson.available
    Assert-Equal "projects 는 빈 배열" 0 @($noDesktopJson.projects).Count
    Assert-Equal "ungrouped 는 빈 배열" 0 @($noDesktopJson.ungrouped).Count
    Assert-True "projects 원문 배열 확인" ($noDesktopRaw -match '"projects":\s*\[\s*\]')
    Assert-True "ungrouped 원문 배열 확인" ($noDesktopRaw -match '"ungrouped":\s*\[\s*\]')

    # 다른 API(/api/status)에 계속 응답하는지 확인
    $statusResp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port2/api/status" -TimeoutSec 5
    Assert-Equal "/api/status 계속 응답" 200 $statusResp.StatusCode
}
finally {
    if ($viewer1 -and -not $viewer1.HasExited) {
        Stop-Process -Id $viewer1.Id -Force -ErrorAction SilentlyContinue
    }
    if ($viewer2 -and -not $viewer2.HasExited) {
        Stop-Process -Id $viewer2.Id -Force -ErrorAction SilentlyContinue
    }
    $env:CLAUDE_DESKTOP_DIR = $prevDesktopEnv
    $env:CLAUDE_PROJECTS_DIR = $prevProjectsEnv
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
