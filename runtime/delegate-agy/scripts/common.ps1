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
        return [regex]::Replace($json, '\\u([0-9a-fA-F]{4})', {
            param($m)
            $code = [Convert]::ToInt32($m.Groups[1].Value, 16)
            if ($code -lt 0x20) { return $m.Value }
            return [string][char]$code
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

function Write-Session([string]$Name, [string]$ConversationId, [string]$Cwd, [string]$Model) {
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
        cwd             = $Cwd
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
