# agy-progress.ps1
# watch-agy.ps1이 agy 호출 하나를 기다리는 동안 "아직 일하는 중인가, 멈췄는가"를 판단하는
# 헬퍼 모음입니다. dot-source해서 씁니다: `. (Join-Path $PSScriptRoot "agy-progress.ps1")`
#
# 왜 필요한가:
#   예전에는 호출 하나에 고정 600초 마감만 있었습니다. 그런데 저장소 여러 개를 가로지르는
#   검토 같은 작업은 정상적으로도 10분 넘게 걸리고(120~145단계), 마감에 걸리면 이미 끝낸
#   결과(결과 파일까지 써 둔 것)도 실패로 기록되고 버려졌습니다. 그래서 절대 마감을 늘리고,
#   대신 "새 단계가 계속 기록되는지"로 멈춤을 따로 판정합니다.
#
# 신호:
#   agy는 단계를 하나 끝낼 때마다 대화 기록을 씁니다(확인: 진행 중인 작업의 기록 파일에
#   방금 끝난 단계가 이미 들어 있음). 이 파일들의 마지막 수정 시각을 "마지막 활동"으로 봅니다.
#     <AgyHome>\conversations\<id>.db
#     <AgyHome>\brain\<id>\.system_generated\logs\transcript_full.jsonl
#   CPU 사용량은 신호로 쓸 수 없습니다. 모델 응답을 기다리는 동안 agy는 거의 놀기 때문입니다
#   (실측: 작업 중인데 10초에 CPU 0.1초).
#
# 멈춤 기준(워처의 $AgyStallSeconds)의 근거:
#   정상 작업에서 새 단계 사이가 가장 길게 비었던 것은 113초였습니다(5건, 약 640단계 관찰).
#   관찰이 5건뿐이라 이보다 오래 조용한 정상 작업이 없다고 보장하지는 못합니다.
#
# 대화를 못 찾거나 어느 것인지 모호하면 멈춤 판정을 하지 않습니다(절대 마감만 적용).
# 멀쩡히 일하는 작업을 잘못 끊는 쪽이 이 개선이 막으려던 바로 그 피해이기 때문입니다.

# agy가 대화/기록을 저장하는 루트. agy가 저장 위치를 바꾸면 AGY_HOME 으로 지정할 수 있습니다.
function Get-AgyHomeDir {
    if ($env:AGY_HOME) { return $env:AGY_HOME }
    return (Join-Path $env:USERPROFILE ".gemini\antigravity-cli")
}

# agy 인자 목록에서 `--conversation <id>`의 id를 꺼냅니다(이어가기 호출). 없으면 $null.
function Get-AgyConversationIdFromArgs($agyArgs) {
    $list = @($agyArgs)
    for ($i = 0; $i -lt ($list.Count - 1); $i++) {
        if ($list[$i] -eq '--conversation') { return [string]$list[$i + 1] }
    }
    return $null
}

# 이번 호출이 만든 대화를 찾습니다. 반환: @{ State = ...; Id = ... }
#   found       - 찾음(Id 사용 가능). 이어가기 호출이면 이미 아는 id를 그대로 씁니다.
#   none        - 시작 이후 새로 생긴 대화가 아직 없음(조금 더 기다려 볼 수 있음)
#   ambiguous   - 시작 직후 창 안에 대화가 둘 이상 생겨 어느 것인지 알 수 없음
#   unavailable - 대화 폴더 자체가 없음(agy 저장 방식이 바뀌었을 수 있음)
# 새 대화는 호출을 시작한 시각 직후 WindowSeconds 안에 만들어진 것만 후보로 봅니다
# (실측: 시작 후 약 7초 안에 생김). 그보다 늦게 생긴 다른 agy 대화는 무시합니다.
function Resolve-AgyConversation($AgyHome, $KnownId, [datetime]$StartedAt, [int]$WindowSeconds = 120) {
    $convDir = Join-Path $AgyHome "conversations"
    if (-not (Test-Path -LiteralPath $convDir -PathType Container)) {
        return @{ State = 'unavailable'; Id = $null }
    }
    if ($KnownId) { return @{ State = 'found'; Id = [string]$KnownId } }

    $from = $StartedAt.AddSeconds(-2)
    $to   = $StartedAt.AddSeconds($WindowSeconds)
    $candidates = @(Get-ChildItem -LiteralPath $convDir -Filter '*.db' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.CreationTime -ge $from -and $_.CreationTime -le $to })

    if ($candidates.Count -eq 1) { return @{ State = 'found'; Id = $candidates[0].BaseName } }
    if ($candidates.Count -gt 1) { return @{ State = 'ambiguous'; Id = $null } }
    return @{ State = 'none'; Id = $null }
}

# 그 대화의 마지막 활동 시각(대화 DB와 기록 파일 중 더 늦은 수정 시각). 파일이 없으면 $null.
function Get-AgyConversationActivity($AgyHome, $Id) {
    $paths = @(
        (Join-Path $AgyHome "conversations\$Id.db"),
        (Join-Path $AgyHome "brain\$Id\.system_generated\logs\transcript_full.jsonl")
    )
    $latest = $null
    foreach ($p in $paths) {
        $item = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
        if ($item -and (($null -eq $latest) -or ($item.LastWriteTime -gt $latest))) {
            $latest = $item.LastWriteTime
        }
    }
    return $latest
}

# 멈췄는가: 마지막 활동(없으면, 또는 호출 시작보다 옛날이면 호출 시작 시각)으로부터
# StallSeconds 이상 지났으면 $true. 이어가기 호출은 대화 파일이 이미 옛날 것일 수 있어서
# 호출 시작 시각을 하한으로 둡니다.
function Test-AgyStalled($LastActivity, [datetime]$StartedAt, [datetime]$Now, [int]$StallSeconds) {
    $ref = $StartedAt
    if (($null -ne $LastActivity) -and ($LastActivity -gt $ref)) { $ref = $LastActivity }
    return (($Now - $ref).TotalSeconds -ge $StallSeconds)
}

# RootPid 의 자손 프로세스 중 이름이 ProcessName 인 것의 PID 목록.
# 시간 초과로 끊을 때 "이번 호출이 띄운 agy"만 정확히 가리기 위해 씁니다. 이름만으로 고르면
# 이 워처와 상관없는 다른 agy(사용자가 직접 띄운 것, 다른 워처의 것)까지 죽일 수 있습니다.
function Get-DescendantProcessIdsByName([int]$RootPid, [string]$ProcessName = "agy") {
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $parentOf = @{}
    foreach ($p in $all) { $parentOf[[int]$p.ProcessId] = [int]$p.ParentProcessId }
    $hits = @()
    foreach ($p in $all) {
        if ($p.Name -ne "$ProcessName.exe") { continue }
        $cur = [int]$p.ParentProcessId
        for ($depth = 0; ($depth -lt 32) -and ($cur -gt 0); $depth++) {
            if ($cur -eq $RootPid) { $hits += [int]$p.ProcessId; break }
            if (-not $parentOf.ContainsKey($cur)) { break }
            $cur = $parentOf[$cur]
        }
    }
    return $hits
}

# 프로세스와 그 자식 프로세스(agy가 띄운 MCP 서버 등)를 함께 종료합니다.
function Stop-ProcessTree([int]$ProcessId) {
    try {
        & taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null
    } catch {}
    # taskkill 이 못 죽였으면(권한 등) 마지막 수단으로 본체만이라도 종료
    try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}
