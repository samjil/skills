# common.ps1
# watch-agy.ps1과 log-qa.ps1이 함께 쓰는 Q&A 저장소(runtime\logs\data\qa-*.jsonl) 관련
# 헬퍼 함수 모음입니다. dot-source해서 씁니다: `. (Join-Path $PSScriptRoot "common.ps1")`
#
# 왜 따로 뺐는가: 예전에 이 함수들이 두 파일에 복사돼 있었는데, 한쪽만 고치고 다른 쪽을
# 놓치면 같은 버그(예: ETS 속성이 붙은 문자열을 그대로 직렬화해 레코드가 수십 MB로
# 부풀던 문제)가 조용히 재발할 수 있었습니다. 한 곳에서만 관리하도록 통합했습니다.
#
# 이 파일을 dot-source하는 스크립트는 아래 변수들을 먼저 정의해 둬야 합니다:
#   $DataDir          - runtime\logs\data 경로
#   $QaShardMaxBytes  - 월별 파일 회전 기준 (바이트)
#   $SessionsDir      - runtime\logs\sessions 경로 (세션 연속성 기능에서 사용)

# PowerShell 5.1의 ConvertTo-Json은 한글 등 비ASCII 문자를 유니코드 이스케이프로 바꿔버려서
# 파일을 직접 열었을 때 읽을 수가 없습니다. 제어문자는 규격대로 그대로 두고 나머지만 실제
# 글자로 되돌려서, "메모장으로 열어도 바로 읽히는" JSON을 만듭니다.
function ConvertTo-ReadableJson($InputObject, [int]$Depth = 6, [switch]$Pretty) {
    try {
        $json = if ($Pretty) {
            ConvertTo-Json -InputObject $InputObject -Depth $Depth
        } else {
            ConvertTo-Json -InputObject $InputObject -Depth $Depth -Compress
        }
        if ($null -eq $json) { return "" }
        # 역슬래시가 짝수 개 앞선 \uXXXX 만 이스케이프 표기다. 홀수 개면 본문에 원래 있던
        # 글자(지시문 속 "\ufeff" 처럼)라, 바꾸면 역슬래시가 홀로 남아 그 줄 전체가 JSON 으로
        # 안 읽힌다. 큰따옴표 · 역슬래시도 글자로 풀면 문자열이 끊기므로 그대로 둔다.
        return [regex]::Replace($json, '(?<!\\)((?:\\\\)*)\\u([0-9a-fA-F]{4})', {
            param($m)
            $code = [Convert]::ToInt32($m.Groups[2].Value, 16)
            if ($code -lt 0x20 -or $code -eq 0x22 -or $code -eq 0x5C) { return $m.Value }
            return $m.Groups[1].Value + [string][char]$code
        })
    } catch {
        return ""
    }
}

function Get-QaShardFiles {
    if (-not (Test-Path $DataDir)) { return @() }
    return @(Get-ChildItem -Path $DataDir -Filter "qa-*.jsonl" -File -ErrorAction SilentlyContinue | Sort-Object Name)
}

# 이번 달 기록을 이어붙일 파일 경로. 5MB를 넘으면 .p2, .p3 ... 으로 넘어갑니다.
function Get-QaShardPath {
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    $month = Get-Date -Format "yyyy-MM"
    $path  = Join-Path $DataDir ("qa-{0}.jsonl" -f $month)
    $part  = 1
    while ((Test-Path $path) -and ((Get-Item $path).Length -gt $QaShardMaxBytes)) {
        $part++
        $path = Join-Path $DataDir ("qa-{0}.p{1}.jsonl" -f $month, $part)
    }
    return $path
}

# 기록 저장소(qa-*.jsonl)에 한 줄을 덧붙입니다. watch-agy.ps1(Sync-QaStore, 작업자의 단일 추가)과
# log-qa.ps1 이 함께 씁니다.
#  - 파일 끝이 줄바꿈이 아니면(앞선 쓰기가 도중에 끊긴 것) 줄바꿈부터 씁니다. 안 그러면 새 기록이 끊긴 줄 뒤에
#    이어 붙어 "{잘린 기록{정상 기록}" 한 줄이 되고, 그 줄의 두 기록이 모두 JSON 으로 읽히지 않습니다.
#  - 줄바꿈 + 한 줄을 한 번의 쓰기로 씁니다(추가 모드라 항상 파일 끝에 붙습니다).
#  - BOM 없는 UTF-8 로 씁니다(읽는 쪽은 BOM 이 있든 없든 읽습니다).
function Add-QaLine([string]$Path, [string]$Line) {
    $needBreak = $false
    if (Test-Path -LiteralPath $Path) {
        $rs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($rs.Length -gt 0) {
                [void]$rs.Seek(-1, [System.IO.SeekOrigin]::End)
                $needBreak = ($rs.ReadByte() -ne 10)
            }
        } finally { $rs.Dispose() }
    }
    $text = $(if ($needBreak) { "`r`n" } else { "" }) + $Line + "`r`n"
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
    $ws = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try {
        $ws.Write($bytes, 0, $bytes.Length)
        $ws.Flush()
    } finally { $ws.Dispose() }
}

# ============================================================================
# 세션 연속성 (@session: <이름>)
# ----------------------------------------------------------------------------
# agy는 매번 빈 상태로 시작하는 게 기본이지만, agy CLI 자체가 --conversation <id>로
# 대화를 이어갈 수 있는 기능을 지원합니다(응답 JSON의 conversation_id를 그대로 다음
# 호출에 넘기면 됨 - 2026-09 확인). 이 파일들은 "사람이 붙인 세션 이름" <-> "agy의
# conversation_id"를 매핑해서, 지시파일에 매번 긴 UUID를 안 적어도 되게 해줍니다.
#
# 세션 하나당 파일 하나(runtime\logs\sessions\<이름>.json)로 관리합니다. 워처가
# 작업을 한 번에 하나씩 순차 처리하므로(같은 프로세스, 같은 while 루프) 이 파일들에
# 대한 동시 쓰기 경쟁은 구조적으로 생기지 않습니다 - 별도 잠금이 필요 없습니다.
#
# 대화가 만료/유실됐을 때: agy는 에러로 죽지 않고 조용히 새 conversation_id로
# 폴백합니다(직접 검증함 - 존재하지 않는 conversation_id를 줘도 exit 0, status
# SUCCESS로 새로 시작함). 그래서 우리 쪽에서 "이어붙이기 실패 시 재시도" 로직이
# 따로 필요 없고, 매 호출 후 응답의 conversation_id로 레지스트리를 덮어쓰기만
# 하면 자동으로 복구됩니다.
# ============================================================================

# 세션 이름을 안전한 파일명으로 바꿉니다 (경로 조작 방지 + 파일시스템 금지 문자 제거).
function Get-SafeSessionFileName([string]$Name) {
    $safe = ($Name -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "_" }
    if ($safe.Length -gt 100) { $safe = $safe.Substring(0, 100) }
    return $safe
}

function Get-SessionPath([string]$Name) {
    New-Item -ItemType Directory -Force -Path $SessionsDir | Out-Null
    return Join-Path $SessionsDir ("{0}.json" -f (Get-SafeSessionFileName $Name))
}

# 세션 정보를 읽습니다. 없거나 손상됐으면 $null (그러면 호출부는 "새 세션 시작"으로
# 처리하면 됩니다 - agy의 자체 폴백과 같은 방향이라 자연스럽게 맞물립니다).
function Read-Session([string]$Name) {
    $path = Get-SessionPath $Name
    if (-not (Test-Path $path)) { return $null }
    try {
        $raw = Get-Content -Raw -Path $path -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return $raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

# @cwd(작업 폴더) 값을 폴더 경로 배열로 바꿉니다. 문자열 하나(예전 세션 파일이나 @cwd 한 줄)든 배열(여러 폴더)이든 받고,
# 비어 있는 값과 중복(대소문자, 끝의 \ 또는 / 무시)은 뺍니다. 줄 순서는 유지합니다. 읽을 수 없는 값은 빈 배열.
# (뷰어의 serve-viewer.ps1 에 같은 규칙의 사본이 있습니다 - tests\delegate-agy\cwd-list.tests.ps1 이 둘이 같은지 확인합니다.)
function ConvertTo-CwdList($Value) {
    $out = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($v in @($Value)) {
        if ($null -eq $v) { continue }
        $s = ([string]$v).Trim()
        if (-not $s) { continue }
        $key = $s.TrimEnd([char]92, [char]47).ToLowerInvariant()
        if (-not $key) { $key = $s.ToLowerInvariant() }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$out.Add($s)
    }
    return @($out.ToArray())
}

# 이번 호출에 쓸 폴더 목록. 이번 지시파일에 @cwd 가 하나라도 있으면 이번 목록만 쓰고(세션의 폴더와 합치지 않는다),
# 하나도 없으면 세션에 저장된 목록을 이어서 쓴다(sticky). 세션의 값은 문자열(예전 파일)이든 배열이든 읽는다.
function Resolve-TaskCwds($DirectiveCwds, $SessionCwd) {
    $own = @(ConvertTo-CwdList $DirectiveCwds)
    if ($own.Count -gt 0) { return $own }
    return @(ConvertTo-CwdList $SessionCwd)
}

# 없는 폴더만 골라 돌려줍니다(모두 있으면 빈 배열).
function Get-MissingCwds($Cwds) {
    $missing = @(@($Cwds) | Where-Object { $_ -and -not (Test-Path -LiteralPath $_) })
    return $missing
}

function Write-Session([string]$Name, [string]$ConversationId, [string[]]$Cwd, [string]$Model) {
    $path = Get-SessionPath $Name
    $existing = Read-Session $Name
    $createdAt = if ($existing -and $existing.created_at) { [string]$existing.created_at } else { Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
    $turnCount = 1
    if ($existing -and $existing.turn_count) { $turnCount = [int]$existing.turn_count + 1 }

    # 세션을 이어가는 호출은 실제 모델명을 모르고 "(session)" 자리표시자만 넘어옵니다
    # (watch-agy.ps1의 Invoke-AgyWithFallback 참고). 그걸 그대로 덮어쓰면 세션을 시작할 때
    # 기록해둔 진짜 모델명이 다음 호출부터 영영 사라지므로, 그럴 땐 기존 값을 유지합니다.
    $resolvedModel = $Model
    if ((-not $resolvedModel) -or ($resolvedModel -eq "(session)")) {
        if ($existing -and $existing.model) { $resolvedModel = [string]$existing.model }
    }

    $data = [ordered]@{
        name            = $Name
        conversation_id = $ConversationId
        cwd             = @(ConvertTo-CwdList $Cwd)
        model           = $resolvedModel
        created_at      = $createdAt
        last_used_at    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        turn_count      = $turnCount
    }
    Set-Content -Path $path -Value (ConvertTo-ReadableJson $data 4 -Pretty) -Encoding UTF8
}

# 오래(기본 30일) 안 쓴 세션 파일은 정리합니다. qa-jsonl의 12개월 보관 정리와 같은 패턴.
function Remove-StaleSessions([int]$MaxAgeDays = 30) {
    if (-not (Test-Path $SessionsDir)) { return }
    $cut = (Get-Date).AddDays(-$MaxAgeDays)
    foreach ($f in (Get-ChildItem -Path $SessionsDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        if ($f.LastWriteTime -lt $cut) {
            Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

# 여러 프로세스(워처, 작업자, log-qa.ps1)가 같은 파일을 만지므로, 쓰는 구간을 이 PC 전체에서
# 하나만 들어가게 이름 있는 뮤텍스로 묶는다. 런타임 폴더마다 이름이 달라서 다른 런타임(시험용 등)과는 서로 막지 않는다.
function Invoke-WithRuntimeLock([scriptblock]$Block, [int]$TimeoutSeconds = 60) {
    $baseDir = if ($RuntimeDir) { $RuntimeDir } elseif ($DataDir) { Split-Path (Split-Path $DataDir -Parent) -Parent } else { $PSScriptRoot }
    $sha = New-Object System.Security.Cryptography.SHA1Managed
    $hash = [BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($baseDir.ToLowerInvariant().TrimEnd('\', '/')))).Replace('-', '')
    $mutex = New-Object System.Threading.Mutex($false, "Local\samjil-agy-$hash")
    $got = $false
    try {
        try { $got = $mutex.WaitOne($TimeoutSeconds * 1000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
        & $Block
    } finally {
        if ($got) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
}

# 기록 저장소의 현재 파일(ShardPath) 맨 끝 TailBytes 바이트 안에 이 작업 ID 의 레코드가 있는지 봅니다.
# 방금 끝난 작업의 레코드가 다른 프로세스(워처가 켜질 때의 전체 동기화 등)에 의해 이미 들어갔는지 확인하는 용도라
# 파일 전체를 읽지 않습니다. 작업 ID 가 든 줄만 엄격하게(ConvertFrom-Json) 읽어서, 깨진 줄이나 다른 레코드의 본문에
# 우연히 적힌 같은 글자는 "있음"으로 치지 않습니다.
function Test-QaTaskIdInShardTail([string]$ShardPath, [string]$TaskId, [int]$TailBytes = 262144) {
    if (-not (Test-Path -LiteralPath $ShardPath)) { return $false }
    $buf = $null
    $got = 0
    $start = [long]0
    $fs = New-Object System.IO.FileStream($ShardPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $len = $fs.Length
        $start = [Math]::Max([long]0, $len - $TailBytes)
        [void]$fs.Seek($start, [System.IO.SeekOrigin]::Begin)
        $buf = [byte[]]::new([int]($len - $start))
        while ($got -lt $buf.Length) {
            $n = $fs.Read($buf, $got, $buf.Length - $got)
            if ($n -le 0) { break }
            $got += $n
        }
    } finally { $fs.Dispose() }
    $lines = [System.Text.Encoding]::UTF8.GetString($buf, 0, $got) -split "\r?\n"
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($i -eq 0 -and $start -gt 0) { continue }    # 읽기 시작 지점에서 잘린 첫 줄
        $l = $lines[$i].Trim().TrimStart([char]0xFEFF)
        if (-not $l) { continue }
        if ($l.IndexOf($TaskId, [System.StringComparison]::Ordinal) -lt 0) { continue }
        $rec = $null
        try { $rec = $l | ConvertFrom-Json } catch { continue }
        if ($null -ne $rec -and [string]$rec.task_id -ceq $TaskId) { return $true }
    }
    return $false
}

# 가장 최근에 쓴 샤드 3개의 꼬리에서 task_id 를 찾는다. 샤드가 5MB 를 넘어 막 새 파일로 나뉜 직후에는 "지금 쓰는 파일"이
# 비어 있어 앞 파일 끝에 있는 같은 기록을 못 보므로, 활성 샤드 하나만 보지 않는다. 파일 전체는 읽지 않는다.
function Test-QaTaskIdInRecentShards([string]$TaskId) {
    $recent = @(Get-QaShardFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 3)
    foreach ($f in $recent) {
        if (Test-QaTaskIdInShardTail $f.FullName $TaskId) { return $true }
    }
    return $false
}

# 단일 Q&A 레코드 1건을 추가하고 index.json을 갱신한다. 반환: 기록된 샤드 경로(건너뛰었거나 실패하면 $null).
function Add-QaRecordUnlocked([System.Collections.IDictionary]$Record, [string]$QaIndexFile, [int]$QaKeepMonths = 12) {
    $taskId = if ($Record -and $Record.Contains("task_id")) { [string]$Record["task_id"] } else { "" }
    if ($taskId -and (Test-QaTaskIdInRecentShards $taskId)) {
        return $null
    }

    $line = ConvertTo-ReadableJson $Record 6
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $shardPath = Get-QaShardPath
    # 파일 끝이 줄바꿈이 아니면 줄바꿈부터 쓰므로, 덧붙인 바이트 수는 실제 파일 크기 차이로 잰다(total 빠른 계산 검증용).
    $sizeBefore = if (Test-Path -LiteralPath $shardPath) { (Get-Item -LiteralPath $shardPath).Length } else { 0 }
    Add-QaLine $shardPath $line
    $appendedBytes = (Get-Item -LiteralPath $shardPath).Length - $sizeBefore

    $shardFiles = @(Get-QaShardFiles)
    $canUseFastTotal = $false
    $fastTotal = 0

    if ($QaIndexFile -and (Test-Path -LiteralPath $QaIndexFile)) {
        try {
            $oldIdx = ([System.IO.File]::ReadAllText($QaIndexFile, [System.Text.Encoding]::UTF8)).TrimStart([char]0xFEFF) | ConvertFrom-Json
            if ($null -ne $oldIdx.total -and $null -ne $oldIdx.shards) {
                $oldShards = @($oldIdx.shards)
                $oldBytesSum = [long]0
                foreach ($os in $oldShards) { $oldBytesSum += [long]$os.bytes }
                $curBytesSum = [long]0
                foreach ($cf in $shardFiles) { $curBytesSum += [long]$cf.Length }
                # 샤드 개수가 같고(또는 새 샤드 1개가 막 생겼고) 바이트 차이가 방금 덧붙인 크기와 정확히 일치할 때만 +1 사용
                if (($oldShards.Count -eq $shardFiles.Count -or ($oldShards.Count + 1) -eq $shardFiles.Count) -and (($curBytesSum - $oldBytesSum) -eq $appendedBytes)) {
                    $fastTotal = [int]$oldIdx.total + 1
                    $canUseFastTotal = $true
                }
            }
        } catch { $canUseFastTotal = $false }
    }

    $shards = @()
    $recalcTotal = 0
    foreach ($f in $shardFiles) {
        if (-not $canUseFastTotal) {
            $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
            $recalcTotal += @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
        }
        $shards += [ordered]@{
            file     = $f.Name
            bytes    = $f.Length
            modified = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
    $total = if ($canUseFastTotal) { $fastTotal } else { $recalcTotal }

    if ($QaIndexFile) {
        $idx = [ordered]@{
            updated     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            total       = $total
            keep_months = $QaKeepMonths
            note        = "qa-YYYY-MM.jsonl 파일의 한 줄이 작업 한 건입니다. 한 파일이 5MB를 넘으면 같은 달이라도 qa-YYYY-MM.p2.jsonl 처럼 나뉩니다."
            shards      = @($shards)
        }
        [System.IO.File]::WriteAllText($QaIndexFile, (ConvertTo-ReadableJson $idx 6 -Pretty), $utf8NoBom)
    }
    return $shardPath
}

