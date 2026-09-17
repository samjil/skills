# log-qa.ps1
# watch-agy.ps1가 관리하는 것과 같은 기록 저장소(runtime\logs\data\qa-*.jsonl)에
# Q&A 한 건을 추가로 남깁니다. 워처(inbox 파일 위임) 경로를 거치지 않고
# 다른 통로(예: antigravity MCP 직접 호출)로 주고받은 질문/답변을 같은 웹 뷰어에서
# 함께 볼 수 있게 하기 위한 것입니다.
#
# watch-agy.ps1이 쓰는 기록과 구분할 수 있도록 모든 레코드에 "source" 필드를 남깁니다:
#   - "bridge" : inbox 파일 위임 -> watch-agy.ps1이 agy CLI를 호출한 기록
#   - "mcp"    : Claude가 antigravity MCP(ask_antigravity 등)를 직접 호출한 기록
#
# usage.csv/usage_summary.csv는 건드리지 않습니다 (그건 watch-agy.ps1이 실제 agy CLI
# 호출의 토큰/비용을 집계하는 원장이라, 성격이 다른 MCP 호출을 섞으면 집계가 왜곡됩니다).
#
# 사용법:
#   .\log-qa.ps1 -Source mcp -QuestionFile q.txt -AnswerFile a.txt -Model "Gemini 3.1 Pro High"

param(
    [string]$RepoRoot   = "",
    [string]$RuntimeDir = "",
    [Parameter(Mandatory = $true)][ValidateSet("mcp", "bridge")][string]$Source,
    [Parameter(Mandatory = $true)][string]$QuestionFile,
    [Parameter(Mandatory = $true)][string]$AnswerFile,
    [string]$Model  = "",
    [string]$Status = "OK",
    [string]$TaskId = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

# 참고: [Parameter(Mandatory=...)] 속성이 있는 "고급" 스크립트는 파라미터 바인딩 단계에서
# $PSScriptRoot가 아직 채워지지 않은 경우가 있어(watch-agy.ps1 등 단순 param 스크립트와
# 다른 점), 기본값 식이 아니라 본문에서 안전하게 다시 계산합니다.
if (-not $RepoRoot) {
    $root = $PSScriptRoot
    if (-not $root -and $MyInvocation.MyCommand.Path) { $root = Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
    $RepoRoot = Split-Path -Path $root -Parent
}
if (-not $RuntimeDir) { $RuntimeDir = Join-Path $RepoRoot "runtime" }
$DataDir     = Join-Path $RuntimeDir "logs\data"
$QaIndexFile = Join-Path $DataDir "index.json"
$QaShardMaxBytes = 5MB

if (-not (Test-Path $QuestionFile)) { throw "QuestionFile을 찾을 수 없습니다: $QuestionFile" }
if (-not (Test-Path $AnswerFile))   { throw "AnswerFile을 찾을 수 없습니다: $AnswerFile" }

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

if (-not $TaskId) {
    $rand = -join ((48..57 + 97..102) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    $TaskId = "{0}_{1}_{2}" -f $Source, (Get-Date -Format "yyyyMMdd_HHmmss"), $rand
}

# ConvertTo-ReadableJson / Get-QaShardFiles / Get-QaShardPath는 watch-agy.ps1과 공유합니다
# (common.ps1 참고 - 두 곳에 복사해두면 한쪽만 고치고 놓치는 사고가 나기 쉽습니다).
. (Join-Path $PSScriptRoot "common.ps1")

# [string] 캐스팅이 중요합니다: Get-Content -Raw가 돌려주는 문자열에는 PSPath/PSProvider/
# PSDrive 같은 숨은 ETS NoteProperty가 붙어 있어서, 캐스팅 없이 그대로 해시테이블에 넣고
# ConvertTo-Json으로 직렬화하면 그 파일시스템 메타데이터(드라이브 정보 등)까지 깊이
# 재귀적으로 통째로 직렬화되어 몇십 MB짜리 레코드가 만들어집니다(실제로 겪은 사고).
$qText = [string](Get-Content -Raw -Path $QuestionFile -Encoding UTF8)
$aText = [string](Get-Content -Raw -Path $AnswerFile -Encoding UTF8)

$rec = [ordered]@{
    timestamp     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    computer_name = $env:COMPUTERNAME
    task_id       = $TaskId
    source        = $Source
    model         = $Model
    status        = $Status
    question      = $qText
    answer        = $aText
}

$line = ConvertTo-ReadableJson $rec 6
if ([string]::IsNullOrWhiteSpace($line)) { throw "레코드를 JSON으로 변환하지 못했습니다." }
# 경로를 한 번만 계산해서 씁니다 - Add-Content 이후에 다시 계산하면 방금 쓴 내용 때문에
# 파일 크기가 달라져 있어(특히 회전 기준을 넘겼다면) 실제로 쓴 파일과 다른 경로를 보고할 수 있습니다.
$shardPath = Get-QaShardPath
Add-Content -Path $shardPath -Value $line -Encoding UTF8

# index.json은 실제 shard 파일들을 다시 읽어 총 건수를 새로 계산합니다
# (watch-agy.ps1이 지금 안 떠 있어도 웹 뷰어가 정확한 총 건수를 보여주도록).
$total = 0
$shards = @()
foreach ($f in (Get-QaShardFiles)) {
    $lineCount = @(Get-Content -Path $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    $total += $lineCount
    $shards += [ordered]@{
        file     = $f.Name
        bytes    = $f.Length
        modified = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    }
}
$idx = [ordered]@{
    updated     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    total       = $total
    keep_months = 12
    note        = "qa-YYYY-MM.jsonl 파일의 한 줄이 작업 한 건입니다. source 필드로 bridge(inbox 위임)/mcp(직접 호출)를 구분합니다."
    shards      = @($shards)
}
Set-Content -Path $QaIndexFile -Value (ConvertTo-ReadableJson $idx 6 -Pretty) -Encoding UTF8

Write-Host "기록 저장: task_id=$TaskId source=$Source -> $shardPath"
