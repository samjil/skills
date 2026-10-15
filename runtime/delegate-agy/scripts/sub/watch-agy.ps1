# watch-agy.ps1

# Antigravity CLI(agy) 파일 기반 지시/응답 워처 (PC별 독립 실행)

#

# 사용법:

#   1) runtime\inbox 폴더에 .txt 또는 .md 파일을 만들고 그 안에 agy에게 시킬 지시문을

#      적어 저장합니다. (예: inbox\작업1.md)

#   2) 이 스크립트를 PowerShell에서 실행해 둔 채로 둡니다.

#      감지되면 자동으로 agy CLI를 호출해서 처리하고,

#      runtime\outbox 폴더에 같은 이름 + .response.md 파일로 답변을 저장합니다.

#      처리한 지시파일은 runtime\processed 폴더로 이동합니다.

#   3) 종료하려면 이 창에서 Ctrl+C 를 누르세요.

#

# 설계 (docs\설계.md 3.2절 참고):

#   - 이 repo를 PC마다 각자 clone해서 쓰므로 "인스턴스 폴더"(PC별 하위 폴더) 개념이

#     없습니다. runtime\ 폴더 자체가 이미 이 PC 전용입니다 (.gitignore로 git 추적 제외).

#   - 화면 표시는 이 스크립트가 아니라 serve-report.ps1이 띄우는 로컬 웹 서버 + web\

#     페이지가 담당합니다. 이 스크립트는 logs\data\qa-*.jsonl 원본 기록만 관리합니다.

#

# 주의: --dangerously-skip-permissions 는 헤드리스 실행 중 권한 확인 프롬프트 때문에

#       멈추는 것을 막기 위한 것입니다. agy가 실행할 수 있는 작업 범위를 신뢰할 수 있을 때만

#       사용하세요. 필요 없다면 아래에서 이 옵션을 지우세요.



param(
    [string]$RepoRoot    = "",
    [string]$RuntimeDir  = "",
    [int]$PollSeconds    = 2,
    [int]$MaxParallel    = 0,       # 한 번에 돌릴 작업 수(0 이면 환경변수 AGY_MAX_PARALLEL, 그것도 없으면 3)
    [string]$WorkerTask  = "",      # 내부용: 지시파일 하나만 처리하고 끝나는 작업자 모드(워처가 작업마다 띄운다)
    [switch]$SkipPermissions = $true
)

# 콘솔에서 한글이 깨지지 않도록 출력 인코딩을 UTF-8로 고정합니다.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    chcp 65001 > $null
} catch {}

if (-not $RepoRoot) {
    $parent = Split-Path -Path $PSScriptRoot -Parent
    if ((Split-Path -Leaf $PSScriptRoot) -eq "sub") {
        $RepoRoot = Split-Path -Path $parent -Parent
    } else {
        $RepoRoot = $parent
    }
}

if (-not $RuntimeDir) {
    if ($env:AGY_DELEGATE_RUNTIME) {
        $RuntimeDir = $env:AGY_DELEGATE_RUNTIME
    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime")) {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"
    } elseif (Test-Path (Join-Path $RepoRoot "runtime")) {
        $RuntimeDir = Join-Path $RepoRoot "runtime"
    } else {
        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime"
    }
}



# 동시에 돌릴 작업 수. 1 이면 예전처럼 한 번에 하나씩 처리한다.
if ($MaxParallel -le 0) {
    $MaxParallel = 3
    if ($env:AGY_MAX_PARALLEL -match '^\d+$' -and [int]$env:AGY_MAX_PARALLEL -gt 0) { $MaxParallel = [int]$env:AGY_MAX_PARALLEL }
}

# --- 모델 우선순위 ---

# agy 응답 JSON에는 모델명이 담겨오지 않습니다 (CLI 자체 한계). 그래서 "어떤 모델을 썼는지

# 사후에 알아내는" 대신 "어떤 모델을 쓸지 우리가 --model로 직접 지정"하는 방식을 씁니다.

# 맨 위(가장 강력한 모델)부터 순서대로 시도하고, 쿼터 초과/일시적 사용 불가 오류가 나면

# 자동으로 다음 순위 모델로 넘어갑니다. 우리가 지정해서 성공한 값이므로 model 컬럼은 100%

# 정확합니다. 아래 ID 목록은 `agy models` 명령으로 확인한 실제 값(2026-09 기준)입니다.

# Gemini 계열 모델만 사용합니다(Claude/GPT-OSS 제외).

$ModelPriority = @(

    "gemini-3.8-flash-high",

    "gemini-3.7-flash-high",

    "gemini-3.1-pro-high",

    "gemini-3.6-flash-high"

)



# 이 패턴에 걸리는 오류일 때만 "다음 모델로 자동 폴백"합니다 (쿼터 초과/요청 과다/일시적

# 사용 불가 등). 프롬프트 자체 문제 같은, 모델을 바꿔도 똑같이 실패할 오류까지 모든 모델로

# 재시도하면 시간만 낭비하므로 걸러냅니다.

$FallbackErrorPattern = '(?i)(quota|rate.?limit|429|resource.?exhausted|overloaded|unavailable|capacity|too many requests|exceeded|throttle)'

# --- 요청에서 고르는 모델 (@model:) ---
# 지시파일 맨 위에 "@model: <ID>" 줄을 쓰면 위의 우선순위 목록 대신 그 모델 하나만 씁니다.
# 지정한 모델이 쿼터 초과/사용 불가여도 다른 모델로 자동 전환하지 않고 실패로 기록합니다
# (원하지 않은 모델의 결과를 조용히 받지 않게 하려는 것이고, 어떻게 할지는 Claude 가 사용자에게 묻습니다).
# Gemini 계열만 허용합니다(위 정책과 같음). `agy models` 로 확인한 2026-10 기준 flash 3단계와
# 우선순위 목록의 ID 입니다. 이 목록에 없는 값은 agy 를 부르지 않고 바로 실패 처리합니다.
$SelectableModels = @(@("gemini-3.8-flash-high", "gemini-3.8-flash-medium", "gemini-3.8-flash-low") + $ModelPriority | Select-Object -Unique)

# 지시파일 맨 위의 "@키: 값" 줄(순서 무관, 여러 줄 가능)을 읽고, 그 형식이 아닌 첫 줄부터를 프롬프트 본문으로 돌려줍니다.
#   @cwd:     agy 의 워크스페이스에 추가할 폴더 (--add-dir). 여러 줄 가능: 줄마다 폴더 하나, 폴더마다 --add-dir 를 한 번씩 넘긴다(줄 순서 유지, 같은 경로는 대소문자·끝의 \ 를 무시하고 한 번만)
#   @session: 대화를 이어갈 세션 이름
#   @model:   이번 호출에 쓸 모델 하나 (위 $SelectableModels)
# 반환: @{ Cwd; Session; Model; Prompt }  (Cwd 는 폴더 배열이고 없으면 빈 배열, Session/Model 은 없으면 $null)
function ConvertFrom-TaskDirectives([string]$rawText) {
    $cwdRaw = New-Object System.Collections.ArrayList; $session = $null; $model = $null
    $prompt = $rawText
    while ($prompt.Length -gt 0) {
        $firstLine = ($prompt -split "`r?`n", 2)[0]
        if ($firstLine -match '^\s*$') {
            # 빈 줄은 건너뛰고 계속 파싱합니다
        } elseif ($firstLine -match '^\ufeff?@cwd:\s*(.+)$') {
            [void]$cwdRaw.Add($Matches[1].Trim())
        } elseif ($firstLine -match '^\ufeff?@session:\s*(.+)$') {
            $session = $Matches[1].Trim()
        } elseif ($firstLine -match '^\ufeff?@model:\s*(.+)$') {
            $model = $Matches[1].Trim()
        } else {
            break
        }
        $rest = ($prompt -split "`r?`n", 2)
        $prompt = if ($rest.Length -gt 1) { $rest[1] } else { "" }
    }
    return @{ Cwd = @(ConvertTo-CwdList $cwdRaw.ToArray()); Session = $session; Model = $model; Prompt = $prompt }
}

# 요청한 @model 을 확인합니다. 반환: @{ Model = <정식 ID 또는 $null>; Error = <사용자에게 보일 사유 또는 $null> }
#   - 목록에 없으면 오류(대소문자는 구분하지 않고 정식 ID 로 바꿔 줍니다).
#   - 이어가는 세션(@session 으로 기존 대화를 잇는 경우)은 agy 가 시작할 때의 모델을 유지하므로,
#     다른 모델을 요청하면 조용히 무시하지 않고 오류로 알립니다.
function Resolve-RequestedModel([string]$requested, [string]$conversationId, [string]$knownModel, [string]$sessionName) {
    if (-not $requested) { return @{ Model = $null; Error = $null } }
    $canonical = @($SelectableModels | Where-Object { $_ -ieq $requested }) | Select-Object -First 1
    if (-not $canonical) {
        return @{ Model = $null; Error = "지정한 @model 을 쓸 수 없습니다: $requested (쓸 수 있는 모델: $($SelectableModels -join ', '))" }
    }
    if ($conversationId -and ($canonical -ne $knownModel)) {
        $was = if ($knownModel) { $knownModel } else { "기록 없음" }
        return @{ Model = $canonical; Error = "이어가는 세션 '$sessionName' 은 시작할 때의 모델($was)로 계속됩니다. 다른 모델($canonical)을 쓰려면 @session 없이 보내거나 새 세션 이름으로 보내세요." }
    }
    return @{ Model = $canonical; Error = $null }
}



$ComputerName = $env:COMPUTERNAME

if (-not $ComputerName) { $ComputerName = "(알수없음)" }



$InboxDir     = Join-Path $RuntimeDir "inbox"

$OutboxDir    = Join-Path $RuntimeDir "outbox"

$ProcessedDir = Join-Path $RuntimeDir "processed"

$StuckDir     = Join-Path $RuntimeDir "_stuck"

$LogsDir      = Join-Path $RuntimeDir "logs"
# 지금 돌고 있는 작업마다 <작업 ID>.json 표시 파일을 둔다(작업자 프로세스 PID·세션·폴더·모델). 워처와 뷰어가 읽는다.
$RunningDir   = Join-Path $LogsDir "running"



New-Item -ItemType Directory -Force -Path $InboxDir, $OutboxDir, $ProcessedDir, $StuckDir, $LogsDir | Out-Null



# 로그류는 전부 별도의 logs 폴더 안에 모아서 기록합니다.

$LogFile        = Join-Path $LogsDir "watcher.log"

$LogMaxBytes    = 5MB      # 이 크기를 넘으면 오래된 부분을 잘라냅니다.

$LogKeepLines   = 2000     # 자를 때 남겨둘 최근 줄 수.



# 다른 스코프(엔진 종료 이벤트 핸들러 등)에서도 로그 파일 경로를 참조할 수 있도록 전역에도 둡니다.

$global:LogFile = $LogFile



# 하트비트 파일: 워처가 살아있는 동안 주기적으로 현재 시각으로 갱신됩니다.

# Stop-Process -Force / 작업 관리자 강제 종료처럼 로그를 남길 틈도 없이 프로세스가 죽는

# 경우는 이 파일의 마지막 수정 시각이 오래된 채로 멈춰 있는 것으로 "사후에" 알아챌 수 있습니다

# (그런 강제 종료 자체를 코드로 가로챌 방법은 없습니다 - OS 차원의 제약입니다).

# 이 PC 하나만 쓰므로 파일 이름에 컴퓨터 이름을 꼭 붙일 필요는 없지만, 나중에 로그만

# 보고도 출처를 알 수 있도록 그대로 유지합니다. 로컬 전용이라 동기화 부담이 없으므로

# 주기를 짧게 잡아도 무방합니다.

$HeartbeatDir  = Join-Path $LogsDir "heartbeat"

New-Item -ItemType Directory -Force -Path $HeartbeatDir | Out-Null

$HeartbeatFile = Join-Path $HeartbeatDir ("hb_{0}.txt" -f $ComputerName)

$HeartbeatIntervalSec = 10



# 잠금 파일: 이 워처 프로세스의 PID를 적어둡니다.

# "프로세스 목록에서 watch-agy.ps1을 찾기"로 생존을 판단하는 방식은 실패해서 워처가

# 하나 더 뜨는 사고로 이어진 적이 있습니다. PID를 파일에 적어두면 워치독이 그 PID만

# 확인하면 되므로 훨씬 확실합니다. 정상 종료 시에는 아래 finally에서 이 파일을 지웁니다.

$LockFile = Join-Path $LogsDir ("watcher_{0}.lock" -f $ComputerName)

$script:LastHeartbeatAt = [datetime]::MinValue



# 정지 신호 파일: stop-agy.ps1이 이 파일을 만들어두면, 아래 메인 루프가 폴링할 때마다

# 확인해서(Stop-Process로 강제로 죽이지 않고) 스스로 정상 종료합니다.

$StopSignalFile = Join-Path $LogsDir "stop.signal"



# 수동 정지 표시 파일: stop-agy.ps1이 정지 신호와 함께 이 파일도 남겨둡니다.

# watch-agy.ps1이 시작될 때(아래) 이 파일을 지우므로("다시 켜졌다"는 뜻), 워치독

# (ensure-agy-running.ps1)은 이 파일이 남아있는 동안은 "사용자가 일부러 끈 상태"로

# 판단하고 자동으로 재시작하지 않습니다.

$ManualStopFlag = Join-Path $LogsDir "manual_stop.flag"

# 공통 함수(세션 관리, 뮤텍스 락, 샤드/인덱스 관리 등)를 가져옵니다.
$commonFile = Join-Path $PSScriptRoot "common.ps1"
if (-not (Test-Path $commonFile)) {
    $commonFile = Join-Path (Split-Path $PSScriptRoot -Parent) "common.ps1"
}
. $commonFile


# 작업자 모드에서는 줄마다 "[작업 ID] "를 붙여 여러 작업의 로그가 섞여도 구분되게 한다.
$script:LogPrefix = ""
function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $($script:LogPrefix)$msg"
    Write-Host $line
    try {
        if (-not (Test-Path $LogsDir)) {
            New-Item -ItemType Directory -Force -Path $LogsDir -ErrorAction SilentlyContinue | Out-Null
        }
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $LogMaxBytes)) {
            Invoke-WithRuntimeLock {
                if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $LogMaxBytes)) {
                    $tail = Get-Content -Path $LogFile -Tail $LogKeepLines -ErrorAction SilentlyContinue
                    Set-Content -Path $LogFile -Value $tail -Encoding UTF8 -ErrorAction SilentlyContinue
                }
            } 10
        }
        # 다른 프로세스가 같은 순간 쓰고 있으면 잠깐 기다렸다가 다시 쓴다
        for ($try = 0; $try -lt 10; $try++) {
            try {
                [System.IO.File]::AppendAllText($LogFile, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
                break
            } catch { Start-Sleep -Milliseconds (20 + 20 * $try) }
        }
    } catch {}
}



# --- 사용량(모델/토큰/소요시간) 기록 ---

# 참고: agy.exe 응답 JSON에는 model, cost 필드가 없습니다 (CLI 자체 한계, 2026-09 확인).

#       cost_usd는 알아낼 방법이 없어 컬럼에서 뺐습니다. model은 우리가 --model로 직접

#       지정해서 성공한 값이므로 그대로 신뢰해서 기록합니다.

$UsageCsv       = Join-Path $LogsDir "usage.csv"

$UsageMaxBytes  = 2MB

$UsageKeepLines = 3000



# 매 작업(행)마다 쌓이는 usage.csv와 별도로, "모델별로 한눈에 보기" 편하도록 모델 단위로

# 집계한 요약 CSV도 함께 유지합니다.

$SummaryCsv = Join-Path $LogsDir "usage_summary.csv"



function Get-JsonField($obj, [string[]]$paths) {

    foreach ($p in $paths) {

        $cur = $obj

        $ok = $true

        foreach ($part in ($p -split '\.')) {

            if ($null -ne $cur -and ($cur.PSObject.Properties.Name -contains $part)) {

                $cur = $cur.$part

            } else {

                $ok = $false

                break

            }

        }

        if ($ok -and $null -ne $cur -and $cur -ne "") { return $cur }

    }

    return $null

}



# usage.csv의 정식 헤더입니다. 예전 버전으로 이미 파일이 존재하면, 컬럼 수가 안 맞아서

# 이후 Import-Csv 집계가 깨지므로 자동으로 예전 파일을 보관하고 새로 시작합니다.

# session: @session:으로 이어간 작업이면 그 이름, 아니면 빈 칸 (3.8절 - docs\설계.md).

# session_id: agy 응답의 conversation_id (동일 세션 식별용).

$UsageCsvHeader = "timestamp,computer_name,task_id,model,attempts,tried_models,input_tokens,output_tokens,thinking_tokens,total_tokens,elapsed_sec,status,session,session_id"
# 이 프로세스가 usage.csv 에 처음 쓴 행. 작업자는 작업 하나만 하므로 그 작업의 행이고, Complete-TaskQaRecord 가
# 기록 저장소에 넣을 레코드를 만들 때 usage.csv 를 다시 읽지 않고 이걸 쓴다.
$script:FirstUsageRow = $null



function Write-UsageRowUnlocked($taskId, $model, $attempts, $triedModels, $inputTokens, $outputTokens, $thinkingTokens, $totalTokens, $elapsedSec, $status, [string]$session = "", [string]$sessionId = "") {

    try {

        if (-not (Test-Path $UsageCsv)) {

            $UsageCsvHeader | Set-Content -Path $UsageCsv -Encoding UTF8

        } else {

            $firstLine = Get-Content -Path $UsageCsv -TotalCount 1 -ErrorAction SilentlyContinue

            if ($firstLine -ne $UsageCsvHeader) {

                # 스키마가 다른 예전 파일 - 섞이면 집계가 깨지므로 보관하고 새로 시작합니다.

                $archivePath = Join-Path $LogsDir ("usage_before_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

                Move-Item -Path $UsageCsv -Destination $archivePath -Force

                Log "usage.csv 스키마가 예전 버전이라 '$archivePath' 로 보관하고 새로 시작합니다."

                $UsageCsvHeader | Set-Content -Path $UsageCsv -Encoding UTF8

            } elseif ((Get-Item $UsageCsv).Length -gt $UsageMaxBytes) {

                $header = Get-Content -Path $UsageCsv -TotalCount 1

                $tail   = Get-Content -Path $UsageCsv -Tail $UsageKeepLines

                @($header) + $tail | Set-Content -Path $UsageCsv -Encoding UTF8

            }

        }

        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $row = @($ts, $ComputerName, $taskId, $model, $attempts, $triedModels, $inputTokens, $outputTokens, $thinkingTokens, $totalTokens, $elapsedSec, $status, $session, $sessionId) |

            ForEach-Object { if ($null -eq $_) { "" } else { ($_ -replace ',', ';') } }

        ($row -join ",") | Add-Content -Path $UsageCsv -Encoding UTF8
        if ($null -eq $script:FirstUsageRow) {
            $script:FirstUsageRow = [PSCustomObject]([ordered]@{
                timestamp = $row[0]; computer_name = $row[1]; task_id = $row[2]; model = $row[3]; attempts = $row[4]; tried_models = $row[5]
                input_tokens = $row[6]; output_tokens = $row[7]; thinking_tokens = $row[8]; total_tokens = $row[9]
                elapsed_sec = $row[10]; status = $row[11]; session = $row[12]; session_id = $row[13]
            })
        }

    } catch {

        Log "usage.csv 기록 중 오류: $($_.Exception.Message)"

    }

}



# usage.csv 전체를 모델별로 집계해서 usage_summary.csv를 다시 씁니다.

function Update-UsageSummaryUnlocked {

    try {

        if (-not (Test-Path $UsageCsv)) { return }

        $rows = Import-Csv -Path $UsageCsv -Encoding UTF8

        if (-not $rows) { return }



        $groups = @($rows | Group-Object { if ($_.model) { $_.model } else { "(모델 미확정/실패)" } })



        $summary = foreach ($g in $groups) {

            # 참고: Windows PowerShell 5.1에서는 Where-Object 결과가 1건뿐이면 배열이 아니라

            # 단일 객체로 풀려서 .Count 프로퍼티가 아예 없어져(=$null) 버립니다. @(...)로

            # 감싸서 결과가 0건이든 1건이든 항상 배열이 되도록 강제합니다.

            $okRows  = @($g.Group | Where-Object { $_.status -eq 'OK' })

            $errRows = @($g.Group | Where-Object { $_.status -eq 'ERROR' })



            $inSum    = ($okRows | Where-Object { $_.input_tokens }    | Measure-Object -Property input_tokens    -Sum).Sum

            $outSum   = ($okRows | Where-Object { $_.output_tokens }   | Measure-Object -Property output_tokens   -Sum).Sum

            $thinkSum = ($okRows | Where-Object { $_.thinking_tokens } | Measure-Object -Property thinking_tokens -Sum).Sum

            $totSum   = ($okRows | Where-Object { $_.total_tokens }    | Measure-Object -Property total_tokens    -Sum).Sum



            $elapsedVals = $okRows | Where-Object { $_.elapsed_sec } | ForEach-Object { [double]$_.elapsed_sec }

            $avgElapsed  = if ($elapsedVals) { [math]::Round((($elapsedVals | Measure-Object -Average).Average), 1) } else { $null }



            $lastUsed = ($g.Group | Sort-Object timestamp -Descending | Select-Object -First 1).timestamp



            [PSCustomObject]@{

                model                 = $g.Name

                tasks_ok              = $okRows.Count

                tasks_error           = $errRows.Count

                total_input_tokens    = $inSum

                total_output_tokens   = $outSum

                total_thinking_tokens = $thinkSum

                total_tokens          = $totSum

                avg_elapsed_sec       = $avgElapsed

                last_used_at          = $lastUsed

            }

        }



        $summary | Sort-Object -Property total_tokens -Descending |

            Export-Csv -Path $SummaryCsv -NoTypeInformation -Encoding UTF8 -Force

    } catch {

        Log "usage_summary.csv 갱신 중 오류: $($_.Exception.Message)"

    }

}



function Truncate-Text($s, [int]$maxLen) {

    if ($null -eq $s) { return "" }

    if ($s.Length -gt $maxLen) {

        return $s.Substring(0, $maxLen) + "`n... (내용이 길어 일부 생략됨 - 전체 내용은 outbox/processed 폴더의 원본 파일 참고)"

    }

    return $s

}



# ============================================================================

# Q&A 기록 저장소 (JSON Lines)

# ----------------------------------------------------------------------------

#   logs\data\qa-YYYY-MM.jsonl : 원본 기록. 한 줄에 작업 한 건(JSON). 이어붙이기만 하므로

#                                파일 전체를 다시 쓰지 않습니다. 메모장으로 열면 그대로 읽힙니다.

#                                한 파일이 5MB를 넘으면 qa-YYYY-MM.p2.jsonl 로 나뉩니다.

#   logs\data\index.json       : 어떤 파일이 있고 총 몇 건인지 (사람이 읽는 목차).

#

# 화면 표시용 껍데기 파일은 여기서 만들지 않습니다. serve-report.ps1이 띄우는 로컬 웹

# 서버가 이 jsonl 파일들을 직접 서빙하고, web\app.js가 fetch()로 읽어 렌더링합니다.

# ============================================================================

$DataDir          = Join-Path $LogsDir "data"

$QaIndexFile      = Join-Path $DataDir "index.json"

$QaShardMaxBytes  = 5MB    # 월별 파일이 이보다 커지면 .p2, .p3 으로 나눕니다.

$QaKeepMonths     = 12     # 이보다 오래된 월별 파일은 자동으로 지웁니다.

# 기록에 저장하는 "과정"(agy 가 부른 도구 목록)의 최대 개수. 한 작업이 100~수백 번 도구를 부르는 일이 있어
# 기록 파일이 커지는 것을 막는다. 넘으면 앞쪽 이만큼만 남긴다.
$QaProcessMaxSteps = 400



# @session: <이름>으로 이어가는 agy 대화의 이름<->conversation_id 매핑 파일들이 담깁니다.

# (common.ps1의 세션 헬퍼 함수들이 이 경로를 씁니다. 3.8절 참고 - docs\설계.md)

$SessionsDir      = Join-Path $LogsDir "sessions"

$SessionMaxAgeDays = 30    # 이보다 오래 안 쓴 세션은 자동으로 정리합니다.



$script:QaKnownIds = $null

$script:QaTotal    = 0



# ConvertTo-ReadableJson / Get-QaShardFiles / Get-QaShardPath는 common.ps1에서 로드됨
# 호출 하나가 "일하는 중인지 멈췄는지" 판정하는 헬퍼(agy-progress.ps1). 테스트: tests\delegate-agy
$progressFile = Join-Path $PSScriptRoot "agy-progress.ps1"
if (-not (Test-Path $progressFile)) {
    $progressFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-progress.ps1"
}
. $progressFile



# 워처가 켜질 때 한 번만: 기존 기록을 읽어 "이미 저장된 작업ID"를 메모리에 올립니다.

function Initialize-QaStore {

    $script:QaKnownIds = New-Object 'System.Collections.Generic.HashSet[string]'

    $script:QaTotal    = 0

    try {

        New-Item -ItemType Directory -Force -Path $DataDir | Out-Null



        # 보관 기간이 지난 월별 파일 정리

        $cutMonth = (Get-Date).AddMonths(-$QaKeepMonths).ToString("yyyy-MM")

        foreach ($f in (Get-QaShardFiles)) {

            if ($f.Name -match '^qa-(\d{4}-\d{2})') {

                if ($matches[1] -lt $cutMonth) {

                    Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue

                    Log "보관 기간($QaKeepMonths 개월)이 지난 기록 파일을 정리했습니다: $($f.Name)"

                }

            }

        }



        foreach ($f in (Get-QaShardFiles)) {

            foreach ($line in @(Get-Content -Path $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {

                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                $rec = $null

                try { $rec = $line | ConvertFrom-Json } catch { continue }

                if ($null -eq $rec) { continue }

                $script:QaTotal++

                if ($rec.task_id) { [void]$script:QaKnownIds.Add([string]$rec.task_id) }

            }

        }

        Log "기록 저장소를 읽었습니다: 총 $($script:QaTotal) 건 (폴더: $DataDir)"

    } catch {

        Log "기록 저장소 초기화 중 오류: $($_.Exception.Message)"

    }

}



# usage.csv 의 행 하나(없는 칸은 빈 문자열)로 기록 저장소(jsonl)에 넣을 레코드를 만듭니다.
# Sync-QaStore(usage.csv 를 읽어 빠진 것을 채움)와 작업자의 단일 추가(Complete-TaskQaRecord)가 같은 레코드를 만들도록 한 곳에 둡니다.
# $QuestionPath 를 주면 그 지시파일을 질문으로 쓰고, 안 주면 processed 폴더에서 작업 ID 로 찾습니다.
function New-QaRecordFromRow($r, [string]$QuestionPath = "") {
    $taskId = [string]$r.task_id

    if (-not $QuestionPath) {
        $qFile = Get-ChildItem -Path $ProcessedDir -Filter "$taskId.*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($qFile) { $QuestionPath = $qFile.FullName }
    }
    $qText = if ($QuestionPath -and (Test-Path -LiteralPath $QuestionPath)) {
        Get-Content -Raw -LiteralPath $QuestionPath -Encoding UTF8 -ErrorAction SilentlyContinue
    } else { "(원본 지시파일을 찾을 수 없음 - 이미 정리되었을 수 있습니다)" }

    $aPath = Join-Path $OutboxDir "$taskId.response.md"
    $aText = if (Test-Path $aPath) {
        Get-Content -Raw -Path $aPath -Encoding UTF8 -ErrorAction SilentlyContinue
    } else { "(응답 파일 없음)" }

    # 과정(agy 가 부른 도구 목록)도 같이 기록한다. agy 의 대화 기록은 나중에 정리될 수 있어서 작업이 끝난 직후에
    # 저장해 둔다. 대화 기록을 못 읽으면(대화 id 없음/파일 없음) $null = "모름", 읽었는데 도구를 안 썼으면 @() = "없음".
    $processSteps = $null
    if ($r.session_id) {
        $tPath = Get-AgyTranscriptPath (Get-AgyHomeDir) ([string]$r.session_id)
        if ($tPath -and (Test-Path -LiteralPath $tPath)) {
            $processSteps = @((Read-AgyProcessSteps $tPath 0 $QaProcessMaxSteps).Steps)
        }
    }

    return [ordered]@{
        timestamp       = [string]$r.timestamp
        computer_name   = [string]$r.computer_name
        task_id         = $taskId
        model           = [string]$r.model
        attempts        = [string]$r.attempts
        tried_models    = [string]$r.tried_models
        input_tokens    = [string]$r.input_tokens
        output_tokens   = [string]$r.output_tokens
        thinking_tokens = [string]$r.thinking_tokens
        total_tokens    = [string]$r.total_tokens
        elapsed_sec     = [string]$r.elapsed_sec
        status          = [string]$r.status
        session         = [string]$r.session
        session_id      = [string]$r.session_id
        question        = (Truncate-Text ([string]$qText) 20000)
        answer          = (Truncate-Text ([string]$aText) 20000)
        process         = $processSteps
    }
}

# usage.csv에 있는데 아직 jsonl에 없는 작업을 찾아서 이어붙입니다.
function Sync-QaStore {
    if ($null -eq $script:QaKnownIds) { Initialize-QaStore }
    if (-not (Test-Path $UsageCsv)) { return 0 }
    $added = 0
    try {
        $rows = @(Import-Csv -Path $UsageCsv -Encoding UTF8 | Sort-Object timestamp)
        foreach ($r in $rows) {
            $taskId = [string]$r.task_id
            if ([string]::IsNullOrWhiteSpace($taskId)) { continue }
            if ($script:QaKnownIds.Contains($taskId)) { continue }

            $rec = New-QaRecordFromRow $r
            $line = ConvertTo-ReadableJson $rec 6
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            Add-QaLine (Get-QaShardPath) $line

            [void]$script:QaKnownIds.Add($taskId)
            $script:QaTotal++
            $added++
        }
    } catch {
        Log "기록 저장소 동기화 중 오류: $($_.Exception.Message)"
    }
    return $added
}

function Update-QaIndex([int]$Total = -1) {

    try {

        $shards = @()

        foreach ($f in (Get-QaShardFiles)) {

            $shards += [ordered]@{

                file     = $f.Name

                bytes    = $f.Length

                modified = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")

            }

        }

        $idx = [ordered]@{

            updated     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

            total       = $(if ($Total -ge 0) { $Total } else { $script:QaTotal })

            keep_months = $QaKeepMonths

            note        = "qa-YYYY-MM.jsonl 파일의 한 줄이 작업 한 건입니다. 한 파일이 5MB를 넘으면 같은 달이라도 qa-YYYY-MM.p2.jsonl 처럼 나뉩니다."

            shards      = @($shards)

        }

        Set-Content -Path $QaIndexFile -Value (ConvertTo-ReadableJson $idx 6 -Pretty) -Encoding UTF8

    } catch {

        Log "index.json 갱신 중 오류: $($_.Exception.Message)"

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

# index.json 에 적힌 기록 건수(없거나 읽을 수 없으면 0). 작업자가 건수를 +1 할 때 쓴다.
function Get-QaIndexTotal {
    try {
        if (-not (Test-Path -LiteralPath $QaIndexFile)) { return 0 }
        $o = Get-Content -Raw -LiteralPath $QaIndexFile -Encoding UTF8 | ConvertFrom-Json
        if ($o -and $o.total) { return [int]$o.total }
    } catch {}
    return 0
}

# 작업자가 작업 하나를 끝낼 때의 마무리: 지시파일을 processed 로 옮기고, 기록 저장소에 "이 작업 한 건만" 덧붙이고,
# index.json 을 갱신한다. 전부 뮤텍스 한 번 안에서 한다.
# 예전에는 여기서 Update-QAReport(전체 동기화)를 불렀다. 작업자는 작업마다 새 프로세스라 그때마다 모든 기록 파일을
# 처음부터 끝까지 JSON 으로 읽어야 했고, 그것도 뮤텍스를 쥔 채였다. 전체 동기화는 이제 워처가 켜질 때와
# 사라진 작업을 정리할 때(Resolve-DeadClaim)만 한다.
# 이 작업의 usage 행을 이 프로세스가 쓰지 못했거나 덧붙이다 오류가 나면 예전 방식(usage.csv 기준 전체 동기화)으로 물러선다.
function Complete-TaskQaRecord([string]$TaskId, [string]$SourcePath, [string]$DonePath) {
    Invoke-WithRuntimeLock {
        Move-Item -Path $SourcePath -Destination $DonePath -Force
        $row = $script:FirstUsageRow
        if ($null -eq $row -or [string]$row.task_id -ne $TaskId) {
            Update-QAReportUnlocked
            return
        }
        try {
            $shard = Get-QaShardPath
            if (Test-QaTaskIdInShardTail $shard $TaskId) { return }
            $line = ConvertTo-ReadableJson (New-QaRecordFromRow $row $DonePath) 6
            if ([string]::IsNullOrWhiteSpace($line)) { throw "레코드를 JSON으로 변환하지 못했습니다." }
            Add-QaLine $shard $line
            if ($null -ne $script:QaKnownIds) { [void]$script:QaKnownIds.Add($TaskId); $script:QaTotal++ }
            Update-QaIndex ((Get-QaIndexTotal) + 1)
        } catch {
            Log "기록 저장소에 작업 한 건을 덧붙이다 오류가 나서 전체 동기화로 대신합니다: $($_.Exception.Message)"
            Update-QAReportUnlocked
        }
    }
}

function Update-QAReportUnlocked {
    $null = Sync-QaStore
    Update-QaIndex
}

# 위 세 함수는 usage.csv·기록 저장소를 읽고 다시 쓰므로, 작업자 여러 개가 동시에 부르지 못하게 잠금 안에서 부른다.
function Write-UsageRow($taskId, $model, $attempts, $triedModels, $inputTokens, $outputTokens, $thinkingTokens, $totalTokens, $elapsedSec, $status, [string]$session = "", [string]$sessionId = "") {
    $bound = $PSBoundParameters
    Invoke-WithRuntimeLock { Write-UsageRowUnlocked @bound }
}
function Update-UsageSummary { Invoke-WithRuntimeLock { Update-UsageSummaryUnlocked } }
function Update-QAReport { Invoke-WithRuntimeLock { Update-QAReportUnlocked } }

# agy 한 번 호출이 이 시간을 넘기면 강제로 중단하고 그 작업을 실패 처리합니다.

# (없으면 agy가 멈췄을 때 워처 전체가 무한정 묶입니다 - 실제로 agy가 콘솔 입력을

#  기다리는 바람에 워처가 13분 넘게 그 자리에서 멈춘 적이 있습니다.)

$AgyTimeoutSeconds = 1800

# 위 절대 마감과 별개로, agy 대화 기록에 새 단계가 이 시간 동안 하나도 없으면 "멈춘 것"으로 보고
# 중단합니다. 단계가 계속 기록되는 동안은(= 일하는 중) 절대 마감까지 기다립니다.
# 이 값의 근거와 한계는 agy-progress.ps1 머리말을 보세요.
$AgyStallSeconds = 300
# 마감/멈춤을 점검하는 주기(초)
$AgyPollSeconds = 30
# 오래 걸리는 호출의 진행 상황(경과 시간, 마지막 활동)을 로그에 남기는 주기(초)
$AgyProgressLogSeconds = 600
# 시작 직후 이번 호출이 만든 대화를 찾는 데 쓰는 시간 창(초)
$AgyConversationWindowSeconds = 120



# agy를 "백그라운드 작업"으로 한 번 실행하고, 타임아웃을 걸어 기다립니다.

# 백그라운드 작업에는 콘솔이 붙어있지 않기 때문에, agy(또는 agy가 실행한 명령)가 입력을

# 요구해도 즉시 EOF가 되어 무한 대기에 빠지지 않습니다. 이것이 위 사고의 직접적인 방지책이고,

# 타임아웃은 그 밖의 이유로 멈추는 경우를 위한 안전장치입니다.

#

# 반환: @{ TimedOut = $true/$false; Raw = <agy 표준출력> }

function Invoke-AgyOnce($agyArgs, $errFile, $workDir, [string]$marker = "") {



    $job = $null

    try {

        $job = Start-Job -ScriptBlock {

            param($a, $ef, $wd)

            if ($wd) { Set-Location -Path $wd }



            # [중요] 백그라운드 작업은 별도의 PowerShell 프로세스라서, 워처가 위에서 설정해둔

            # UTF-8 인코딩을 물려받지 않습니다. PowerShell은 외부 명령의 표준출력을

            # [Console]::OutputEncoding 기준으로 해석하므로, 이 설정을 안 하면 agy가 돌려준

            # UTF-8 한글을 CP949로 잘못 읽어서 전부 깨집니다.

            try {

                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

                $OutputEncoding = [System.Text.Encoding]::UTF8

                chcp 65001 > $null

            } catch {}



            & agy @a 2>$ef

        } -ArgumentList (, $agyArgs), $errFile, $workDir

    } catch {

        # 작업 생성 자체가 실패하면 예전 방식(직접 호출)으로 물러섭니다.

        Log "  백그라운드 실행에 실패해 직접 호출로 대체합니다: $($_.Exception.Message)"

        return @{ TimedOut = $false; Raw = (& agy @agyArgs 2>$errFile) }

    }



    # 절대 마감(AgyTimeoutSeconds)까지 기다리되, AgyPollSeconds마다 깨어나 "아직 일하는가"를 봅니다.
    # 대화 기록에 새 단계가 계속 쌓이면 일하는 중이므로 그대로 두고, AgyStallSeconds 동안
    # 하나도 없으면 멈춘 것으로 보고 중단합니다.
    $startedAt       = Get-Date
    $agyHome         = Get-AgyHomeDir
    $knownConv       = Get-AgyConversationIdFromArgs $agyArgs
    $convId          = $null
    $stallCheck      = $true     # 대화를 못 찾거나 모호하면 $false: 절대 마감만 적용
    $stopReason      = $null     # 'cap'(절대 마감) | 'stall'(멈춤)
    $lastActivity    = $null
    $stopNow         = $null
    $nextProgressLog = $AgyProgressLogSeconds
    $finished        = $null

    while ($true) {
        $finished = Wait-Job -Job $job -Timeout $AgyPollSeconds
        if ($null -ne $finished) { break }

        $now     = Get-Date
        $elapsed = ($now - $startedAt).TotalSeconds
        if ($elapsed -ge $AgyTimeoutSeconds) { $stopReason = 'cap'; $stopNow = $now; break }

        if ($stallCheck -and -not $convId) {
            $found = Resolve-AgyConversation $agyHome $knownConv $startedAt $AgyConversationWindowSeconds $marker
            if ($found.State -eq 'found') {
                $convId = $found.Id
                # 동시에 도는 작업이 여럿이어도 뷰어가 이 작업의 진행을 읽을 수 있게 대화 ID 를 작업 표시 파일에 적어 둔다
                if ($script:CurrentTaskId -and (Get-Command Write-RunningClaim -ErrorAction SilentlyContinue)) {
                    Write-RunningClaim $script:CurrentTaskId @{ conversation_id = [string]$convId }
                }
            } elseif ($found.State -eq 'unavailable') {
                $stallCheck = $false
                Log "  멈춤 점검 불가: agy 대화 폴더를 찾을 수 없습니다 ($agyHome). 절대 마감 $AgyTimeoutSeconds 초만 적용합니다."
            } elseif ($found.State -eq 'ambiguous') {
                if ($marker -and $elapsed -le $AgyConversationWindowSeconds) {
                    # 표식으로 내 대화를 가려내는 중이다(대화 기록이 아직 안 써졌을 수 있다). 다음 점검 때 다시 본다.
                } else {
                    $stallCheck = $false
                    Log "  멈춤 점검 불가: 시작 직후 새 대화가 둘 이상이라 이번 호출의 것을 가릴 수 없습니다. 절대 마감 $AgyTimeoutSeconds 초만 적용합니다."
                }
            } elseif ($elapsed -gt $AgyConversationWindowSeconds) {
                $stallCheck = $false
                Log "  멈춤 점검 불가: 시작 후 $AgyConversationWindowSeconds 초 안에 새 대화가 보이지 않습니다. 절대 마감 $AgyTimeoutSeconds 초만 적용합니다."
            }
        }

        if ($stallCheck -and $convId) {
            $lastActivity = Get-AgyConversationActivity $agyHome $convId
            if (Test-AgyStalled $lastActivity $startedAt $now $AgyStallSeconds) {
                $stopReason = 'stall'; $stopNow = $now; break
            }
        }

        if ($elapsed -ge $nextProgressLog) {
            $nextProgressLog += $AgyProgressLogSeconds
            if ($convId -and $lastActivity) {
                $idleNow = [math]::Max(0, [int](($now - $lastActivity).TotalSeconds))
                Log ("  진행 점검: 경과 {0}초, 마지막 활동 {1}초 전 - 작업 중으로 보고 계속 기다립니다 (대화 {2})" -f [int]$elapsed, $idleNow, $convId)
            } else {
                Log ("  진행 점검: 경과 {0}초 (마지막 활동은 확인할 수 없음)" -f [int]$elapsed)
            }
        }
    }

    if ($null -eq $finished) {
        $idleSeconds = $null
        $lastText    = "확인 불가"
        if ($stopReason -eq 'stall') {
            $ref = $startedAt
            if (($null -ne $lastActivity) -and ($lastActivity -gt $ref)) { $ref = $lastActivity }
            $idleSeconds = ($stopNow - $ref).TotalSeconds
            $lastText    = $ref.ToString("HH:mm:ss")
        }

        # 순서가 중요합니다: agy를 먼저 죽이고 나서 작업을 정리합니다. Stop-Job 은 작업 안의 agy가
        # 끝날 때까지 돌아오지 않으므로(실측: 60초짜리 가짜 agy에서 65초 뒤에야 반환), 먼저 부르면
        # 멈춘 agy 앞에서 워처가 그대로 묶여 멈춤 판정이 소용없어집니다.
        # 대상은 "이 워처의 자손인 agy"만입니다. 이름만으로 고르면 사용자가 직접 띄운 다른 agy까지 죽입니다.
        foreach ($agyPid in @(Get-DescendantProcessIdsByName $PID "agy")) {
            Stop-ProcessTree $agyPid
        }
        Stop-Job   -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return @{ TimedOut = $true; Raw = $null; Reason = $stopReason; IdleSeconds = $idleSeconds; LastActivity = $lastText; ConversationId = $convId }
    }



    $out = Receive-Job -Job $job -ErrorAction SilentlyContinue
    $jobErrors = @($job.ChildJobs[0].Error)
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    if (-not $out -and $jobErrors.Count -gt 0) {
        $errText = ($jobErrors | ForEach-Object { $_.ToString() }) -join "`n"
        if ($errFile) {
            Add-Content -Path $errFile -Value "PowerShell 프로세스 실행 오류: $errText" -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        return @{ TimedOut = $false; Raw = $null; ExecutionError = $errText }
    }

    return @{ TimedOut = $false; Raw = $out }

}



# $conversationId가 없으면: $ModelPriority 목록을 순서대로 시도합니다(기존 동작).

# $conversationId가 있으면(@session:으로 이어가는 경우): --conversation으로 그 대화를

# 이어가는 호출 한 번만 합니다 - 모델은 그 대화가 시작될 때 쓴 걸 agy가 그대로 유지하므로

# --model도, 폴백 후보 목록도 필요 없습니다(직접 검증함). agy는 conversation_id가

# 만료/유실됐어도 에러 없이 조용히 새 대화로 시작해주므로, 성공 응답에서 conversation_id가

# 우리가 보낸 것과 다르면 그걸로 "세션이 갱신됐다"는 걸 알아챕니다.

# 쿼터 초과 등 폴백 대상 오류면(새 세션 시도일 때만) 다음 모델로, 그 외 오류면 즉시 중단합니다.

function Invoke-AgyWithFallback($safePrompt, $targetCwd, [bool]$skipPerm, $errFile, [string]$conversationId = "", [string]$knownModel = "", [string]$taskId = "", [string]$promptFile = "", [string]$requestedModel = "") {
    $result = [ordered]@{
        Success        = $false
        Response       = $null
        RawJson        = $null
        ModelUsed      = $null
        Attempts       = 0
        TriedModels    = @()
        InTok          = $null
        OutTok         = $null
        ThinkTok       = $null
        TotTok         = $null
        AgyDuration    = $null
        ElapsedSec     = 0
        ErrorMessage   = $null
        ConversationId = $null
        SessionRenewed = $false
    }

    $overallStart = Get-Date
    # 주의: 여기서 @($null)을 쓰면 안 됩니다 - PowerShell은 "원소가 $null 하나뿐인 배열"을
    # if/스크립트 출력 캡처 과정에서 그냥 $null로 뭉개버려서(직접 겪음: $candidates.Count가
    # 0이 되고 foreach가 한 번도 안 돎), 세션을 이어가려던 호출이 조용히 아무것도 안 하고
    # "실패(시도한 모델: )"로 끝나버립니다. 그래서 $null이 아닌 문자열 자리표시자를 씁니다.
    # 이어가는 세션: 호출 한 번. @model 로 지정했으면 그 모델 하나만(폴백 없음). 아니면 우선순위 목록.
    # @() 로 감싸는 이유: if 식은 원소 하나짜리 배열을 문자열로 풀어서 $candidates[-1] 이 마지막 "글자"가 된다.
    $candidates = @(if ($conversationId) { "(continue)" } elseif ($requestedModel) { $requestedModel } else { $ModelPriority })

    foreach ($candidate in $candidates) {
        $result.Attempts++
        $result.TriedModels += $candidate

        # 웹 뷰어 실시간 표시용: 현재 실행 중인 작업과 모델 정보를 current_task.json에 기록
        $modelForReport = if ($conversationId) {
            if ($knownModel) { $knownModel } else { $ModelPriority[0] }
        } else {
            $candidate
        }
        $currentTaskFile = Join-Path $LogsDir "current_task.json"
        if ($taskId) {
            try {
                [ordered]@{
                    task_id    = $taskId
                    model      = $modelForReport
                    attempt    = $result.Attempts
                    started_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                } | ConvertTo-Json -Compress | Set-Content -Path $currentTaskFile -Encoding UTF8 -ErrorAction SilentlyContinue
                # 작업마다 따로 있는 표시 파일에도 모델·시도를 적는다(뷰어가 어느 작업이 어떤 모델로 도는지 읽는다)
                Write-RunningClaim $taskId @{ model = $modelForReport; attempt = $result.Attempts; started_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
            } catch {}
        }

        # 프롬프트 인자: 임시 프롬프트 파일(@경로)이 제공되면 파일 참조 문법 사용
        $promptArg = if ($promptFile -and (Test-Path -LiteralPath $promptFile)) { "@$promptFile" } else { $safePrompt }
        $agyArgs = @('-p', $promptArg, '--output-format', 'json')

        if ($conversationId) { $agyArgs += @('--conversation', $conversationId) } else { $agyArgs += @('--model', $candidate) }

        foreach ($dir in @($targetCwd)) { if ($dir) { $agyArgs += @('--add-dir', [string]$dir) } }

        if ($skipPerm)  { $agyArgs += '--dangerously-skip-permissions' }

        # 동시에 도는 다른 작업과 대화를 헷갈리지 않게, 이 호출의 질문에만 들어 있는 글(표식)을 함께 넘긴다:
        # 프롬프트 파일을 쓰면 그 파일 이름, 아니면 지시문 첫 줄(따옴표·역슬래시 앞까지, 12자 이상일 때만).
        $marker = ""
        if ($promptFile) {
            $marker = [System.IO.Path]::GetFileName($promptFile)
        } elseif ($safePrompt) {
            $firstLine = ([string]$safePrompt -split "[\r\n]")[0]
            $cut = [regex]::Replace($firstLine, '[\\"].*$', '')
            if ($cut.Length -ge 12) { $marker = $cut.Substring(0, [Math]::Min(60, $cut.Length)) }
        }
        $call = Invoke-AgyOnce $agyArgs $errFile $RuntimeDir $marker

        if ($call.TimedOut) {

            if ($call.Reason -eq 'stall') {
                $idleMin = [math]::Round($call.IdleSeconds / 60, 1)
                $result.ErrorMessage = "agy가 $idleMin 분 동안 진행하지 않아 중단했습니다 (멈춤 판정: 마지막 활동 $($call.LastActivity), 대화 ID $($call.ConversationId))"
                Log "  멈춤: 대화 기록에 새 단계가 $idleMin 분 동안 없어 강제로 중단했습니다 (마지막 활동 $($call.LastActivity), 대화 $($call.ConversationId)). 이 작업은 실패로 기록합니다."
            } else {
                $result.ErrorMessage = "agy 호출이 $AgyTimeoutSeconds 초를 넘겨 중단했습니다 (타임아웃)"
                Log "  타임아웃: agy 호출이 $AgyTimeoutSeconds 초를 넘겨 강제로 중단했습니다. 이 작업은 실패로 기록합니다."
            }

            break

        }

        $raw = $call.Raw

        $json = $null

        try { $json = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $json = $null }

        if ($null -eq $json) {

            # JSON 파싱 자체가 실패 - agy 실행이 비정상 종료된 경우. 모델 문제가 아닐 가능성이
            # 높으므로 다음 모델로 넘어가지 않고 여기서 중단합니다.
            $result.RawJson = $raw
            if ($call.ExecutionError) {
                $result.ErrorMessage = "agy 실행 오류: $($call.ExecutionError)"
                Log "  오류: $($call.ExecutionError)"
            } else {
                $result.ErrorMessage = "agy 응답을 JSON으로 해석할 수 없음"
            }

            break

        }



        if ($json.status -ne "ERROR" -and $json.response) {

            # 성공

            $result.Success        = $true

            $result.Response       = $json.response

            $result.RawJson        = $raw

            $result.ModelUsed      = if ($conversationId) {

                # 세션에 실제로 기록된 모델명이 없으면 추측해서 채우지 않습니다 - 검증 안 된
                # 값을 사실처럼 기록하지 않는다는 원칙(SKILL.md 참고). 빈 값으로 두면
                # usage.csv/usage_summary.csv 쪽에서 이미 "(모델 미확정/실패)"로 집계됩니다.
                $knownModel

            } else {

                $candidate

            }

            $result.ConversationId = [string](Get-JsonField $json @('conversation_id'))

            if ($conversationId -and $result.ConversationId -and $result.ConversationId -ne $conversationId) {

                $result.SessionRenewed = $true

                Log "  참고: 이어가려던 세션이 만료/유실된 것 같아 agy가 새 세션으로 시작했습니다."

            }

            $result.InTok    = Get-JsonField $json @('usage.input_tokens', 'usage.prompt_tokens', 'input_tokens', 'usage.tokens.input')

            $result.OutTok   = Get-JsonField $json @('usage.output_tokens', 'usage.completion_tokens', 'output_tokens', 'usage.tokens.output')

            $result.ThinkTok = Get-JsonField $json @('usage.thinking_tokens', 'usage.reasoning_tokens', 'thinking_tokens')

            $result.TotTok   = Get-JsonField $json @('usage.total_tokens', 'total_tokens', 'usage.tokens.total')

            if (-not $result.TotTok -and $result.InTok -and $result.OutTok) {

                $result.TotTok = [int]$result.InTok + [int]$result.OutTok

            }

            $result.AgyDuration = Get-JsonField $json @('duration_seconds', 'duration_ms')

            break

        }



        # status == ERROR

        $errText = if ($json.error) { [string]$json.error } else { "" }

        $result.RawJson = $raw

        $result.ErrorMessage = $errText



        $isLast = ($candidate -eq $candidates[-1])

        if (-not $isLast -and $errText -match $FallbackErrorPattern) {

            Log "  모델 '$candidate' 사용 불가/쿼터 초과로 다음 모델로 폴백합니다: $errText"

            continue

        } else {

            # 모델 문제가 아니거나(다른 모델로 재시도해도 동일하게 실패할 오류), 마지막 후보였음

            break

        }

    }



    $result.ElapsedSec = [math]::Round(((Get-Date) - $overallStart).TotalSeconds, 1)

    # current_task.json 은 "가장 최근에 시작한 작업"을 가리키는 호환용 파일이다. 내가 쓴 것일 때만 지운다(다른 작업이 덮어썼을 수 있다).
    $currentTaskFile = Join-Path $LogsDir "current_task.json"
    if ($taskId -and (Test-Path $currentTaskFile)) {
        try {
            $ct = [System.IO.File]::ReadAllText($currentTaskFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
            if ([string]$ct.task_id -eq $taskId) { Remove-Item -Path $currentTaskFile -Force -ErrorAction SilentlyContinue }
        } catch { Remove-Item -Path $currentTaskFile -Force -ErrorAction SilentlyContinue }
    }

    return $result

}



# ----------------------------------------------------------------------------
# 동시 실행: 작업 표시 파일, 충돌 판정, 작업자 프로세스
# ----------------------------------------------------------------------------

# 표시 파일(logs\running\<작업 ID>.json)을 읽는다. 없거나 반쯤 쓴 파일이면 $null.
function Read-RunningClaim([string]$Path) {
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $t = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        if (-not $t.Trim()) { return $null }
        return (ConvertFrom-Json -InputObject $t -ErrorAction Stop)
    } catch { return $null }
}

# 표시 파일에 필드를 합쳐 쓴다(이미 있는 필드는 그대로 두고 준 것만 덮는다). 임시 파일에 쓰고 바꿔치기해서 읽는 쪽이 반쯤 쓴 파일을 보지 않는다.
function Write-RunningClaim([string]$TaskId, [hashtable]$Fields) {
    if (-not $TaskId) { return }
    try {
        if (-not (Test-Path -LiteralPath $RunningDir)) { New-Item -ItemType Directory -Force -Path $RunningDir | Out-Null }
        $path = Join-Path $RunningDir ("{0}.json" -f $TaskId)
        $data = [ordered]@{ task_id = $TaskId }
        $old = Read-RunningClaim $path
        if ($old) { foreach ($p in $old.PSObject.Properties) { $data[$p.Name] = $p.Value } }
        foreach ($k in $Fields.Keys) { $data[$k] = $Fields[$k] }
        $tmp = "$path.$PID.tmp"
        [System.IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $data -Compress -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $path -Force
    } catch {}
}

function Remove-RunningClaim([string]$TaskId) {
    if (-not $TaskId) { return }
    Remove-Item -LiteralPath (Join-Path $RunningDir ("{0}.json" -f $TaskId)) -Force -ErrorAction SilentlyContinue
}

# 표시 파일이 가리키는 작업자 프로세스가 살아 있는가
function Test-ClaimAlive($Claim) {
    $claimPid = 0
    try { $claimPid = [int]$Claim.pid } catch { $claimPid = 0 }
    if ($claimPid -le 0) { return $false }
    $p = Get-Process -Id $claimPid -ErrorAction SilentlyContinue
    return [bool]($p -and -not $p.HasExited -and $p.ProcessName -eq "powershell")
}

# 작업자가 끝내지 못하고 사라졌는데 지시파일이 inbox 에 그대로 남은 경우: 영원히 다시 시도하지 않도록 실패로 기록하고 옮긴다.
function Resolve-DeadClaim($Claim, [string]$ClaimPath) {
    $taskId = [string]$Claim.task_id
    # PID 가 아직 채워지지 않은 표시(띄우는 도중 워처가 멈춘 것)는 시작도 못 한 작업이다: 표시만 지워 다시 시작하게 한다
    $deadPid = 0
    try { $deadPid = [int]$Claim.pid } catch { $deadPid = 0 }
    if ($deadPid -le 0) { Remove-Item -LiteralPath $ClaimPath -Force -ErrorAction SilentlyContinue; return }
    $inboxFile = $null
    foreach ($ext in @(".md", ".txt")) {
        $cand = Join-Path $InboxDir ($taskId + $ext)
        if (Test-Path -LiteralPath $cand) { $inboxFile = $cand; break }
    }
    if ($inboxFile) {
        $msg = "작업을 처리하던 프로세스가 끝내지 못하고 사라졌습니다(워처를 껐거나 강제 종료됐을 수 있습니다). 같은 지시를 다시 보내 주세요."
        Log "실패: $taskId - $msg"
        $outFile = Join-Path $OutboxDir "$taskId.response.md"
        if (-not (Test-Path -LiteralPath $outFile)) { Set-Content -Path $outFile -Value $msg -Encoding UTF8 }
        Write-UsageRow $taskId $null $null $null $null $null $null $null $null "ERROR" ([string]$Claim.session) ""
        Move-Item -LiteralPath $inboxFile -Destination (Join-Path $ProcessedDir (Split-Path $inboxFile -Leaf)) -Force -ErrorAction SilentlyContinue
        Update-QAReport
    }
    Remove-Item -LiteralPath $ClaimPath -Force -ErrorAction SilentlyContinue
}

# 지금 돌고 있는 작업들의 표시 목록. 죽은 작업의 표시는 여기서 정리한다.
function Get-RunningClaims {
    $alive = @()
    if (Test-Path -LiteralPath $RunningDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $RunningDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
            $c = Read-RunningClaim $f.FullName
            if ($null -eq $c) {
                # 읽을 수 없는 표시 파일은 오래되면(쓰다 만 것) 지운다
                if (((Get-Date) - $f.LastWriteTime).TotalSeconds -gt 120) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
                continue
            }
            if (Test-ClaimAlive $c) { $alive += $c } else { Resolve-DeadClaim $c $f.FullName }
        }
    }
    return @($alive)
}

# 폴더 경로를 비교용으로 정리한다(대소문자·끝의 구분자·슬래시 방향 무시)
function ConvertTo-SpaceKey([string]$Path) {
    $p = ([string]$Path).Trim().Replace('/', '\').TrimEnd('\').ToLowerInvariant()
    return $p
}

# 두 작업의 "공간"(작업 폴더들)이 겹치는가: 같은 폴더이거나 한쪽이 다른 쪽의 상위 폴더이면 겹친다.
# 폴더가 하나도 없는 작업은 폴더로 구분할 수 없으므로 겹치는 것으로 본다(같은 세션끼리 차례로 하는 쪽이 안전하다).
function Test-SpaceOverlap($CwdsA, $CwdsB) {
    $a = @(@($CwdsA) | Where-Object { $_ } | ForEach-Object { ConvertTo-SpaceKey $_ })
    $b = @(@($CwdsB) | Where-Object { $_ } | ForEach-Object { ConvertTo-SpaceKey $_ })
    if ($a.Count -eq 0 -or $b.Count -eq 0) { return $true }
    foreach ($x in $a) {
        foreach ($y in $b) {
            if ($x -eq $y -or $x.StartsWith($y + '\') -or $y.StartsWith($x + '\')) { return $true }
        }
    }
    return $false
}

# 두 작업을 동시에 돌리면 안 되는가: 세션 이름이 같고(비어 있지 않고) 공간이 겹칠 때만 그렇다.
function Test-TaskConflict([string]$SessionA, $CwdsA, [string]$SessionB, $CwdsB) {
    if (-not $SessionA -or -not $SessionB) { return $false }
    if ($SessionA -ne $SessionB) { return $false }
    return (Test-SpaceOverlap $CwdsA $CwdsB)
}

# 작업자 프로세스(보이지 않는 창)를 띄워 지시파일 하나를 처리하게 한다. 띄웠으면 $true.
# 작업자는 watch-agy.ps1 을 그대로 쓰되 명령줄에 "watch-agy.ps1" 이 나타나지 않게 얇은 껍데기(agy-task-worker.ps1)로 띄운다 —
# start-agy/ensure-agy-running 이 명령줄의 그 이름으로 워처를 찾기 때문에, 작업자가 워처로 오인되어 종료되는 일을 막는다.
function Start-InboxWorker([System.IO.FileInfo]$File, [string]$Session, $Cwds) {
    $taskId = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $wrapper = Join-Path $PSScriptRoot "agy-task-worker.ps1"
    if (-not (Test-Path -LiteralPath $wrapper)) {
        Log "오류: 작업자 스크립트를 찾을 수 없습니다: $wrapper (install.ps1 을 다시 실행해 주세요)"
        return $false
    }
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$wrapper`"",
        "-RepoRoot", "`"$RepoRoot`"", "-RuntimeDir", "`"$RuntimeDir`"", "-WorkerTask", "`"$($File.FullName)`"")
    if ($SkipPermissions) { $argList += "-SkipPermissions" }
    try {
        # 표시 파일을 먼저 만들어 두고(PID 는 0) 띄운 뒤 PID 를 채운다: 그 사이 다른 쪽이 "안 도는 작업"으로 보지 않게
        Write-RunningClaim $taskId @{ pid = 0; session = $Session; cwds = @($Cwds); started = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); watcher_pid = $PID }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = ($argList -join " ")
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $proc = [System.Diagnostics.Process]::Start($psi)
        Write-RunningClaim $taskId @{ pid = $proc.Id }
        Log "작업 시작: $($File.Name) (작업자 PID $($proc.Id)$(if ($Session) { ", 세션: $Session" }))"
        return $true
    } catch {
        Log "작업자를 띄우지 못했습니다: $($_.Exception.Message)"
        Remove-RunningClaim $taskId
        return $false
    }
}

# 지시파일 하나를 끝까지 처리한다(작업자 모드의 본체). 끝나면 표시 파일을 지운다.
function Invoke-InboxTask([string]$TaskPath) {
    $file = Get-Item -LiteralPath $TaskPath -ErrorAction SilentlyContinue
    if (-not $file) { return }
    $taskKey = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    if ($WorkerTask) { $script:LogPrefix = "[$taskKey] " }
    # 표시 파일의 PID 를 내 것으로 확정한다(껍데기 프로세스가 곧 이 프로세스다)
    Write-RunningClaim $taskKey @{ pid = $PID }
    $script:CurrentTaskId = $taskKey
    try {
        Invoke-InboxTaskBody $file
    } finally {
        Remove-RunningClaim $taskKey
    }
}

# 한 지시파일을 처리하는 본체(예전에 메인 루프 안에 있던 부분)

function Invoke-InboxTaskBody([System.IO.FileInfo]$file) {
    $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

    $outFile   = Join-Path $OutboxDir  "$baseName.response.md"

    $errFile   = Join-Path $OutboxDir  "$baseName.error.log"

    $doneFile  = Join-Path $ProcessedDir $file.Name



    Log "처리 중: $($file.Name)"



    $rawText = Get-Content -Raw -Path $file.FullName -Encoding UTF8

    # 지시문 맨 앞의 "[언어 규칙 — 가장 먼저 지킨다] 생각·도구 설명을 한국어로…" 문단은 쓰지 않기로 했다(사용자 결정).
    # 이미 예전 지침을 읽은 Claude 세션이 계속 붙여 보내도 agy 에 넘기지 않고, 지시파일에서도 뺀다(뷰어에도 안 보인다).
    $ruleLine = [regex]::new('(?m)^[ \t]*\[언어 규칙[^\]\r\n]*\][^\r\n]*(\r?\n|$)')
    if ($ruleLine.IsMatch($rawText)) {
        $rawText = $ruleLine.Replace($rawText, '')
        try {
            [System.IO.File]::WriteAllText($file.FullName, $rawText, (New-Object System.Text.UTF8Encoding($false)))
            Log "  -> 지시문 맨 앞의 언어 규칙 문단을 뺐습니다(사용하지 않는 규칙)"
        } catch {}
    }



    # 지시파일 맨 위에 "@키: 값" 줄이 있으면(순서 무관, 여러 줄 가능) 읽어들이고,

    # 그 형식이 아닌 첫 줄부터가 실제 프롬프트 본문입니다. 지원하는 키:

    #   @cwd:     agy의 워크스페이스에 추가할 폴더 (--add-dir). 여러 줄 가능(폴더마다 --add-dir 한 번씩)

    #   @session: 대화를 이어갈 세션 이름 (3.8절 - docs\설계.md). 같은 이름으로 다시

    #             보내면 이전 대화 맥락을 그대로 이어받습니다. 이 줄이 없으면 매번

    #             빈 상태로 새로 시작하는 기존 동작 그대로입니다.

    # (@model: <ID> 는 이번 호출에 쓸 모델 하나를 지정합니다 - ConvertFrom-TaskDirectives 참고)
    $directives     = ConvertFrom-TaskDirectives $rawText
    $targetCwds     = @($directives.Cwd)
    $sessionName    = $directives.Session
    $requestedModel = $directives.Model
    $promptText     = $directives.Prompt



    # 세션이 있으면 이전에 저장해둔 conversation_id와 model을 불러옵니다. @cwd를 이번엔

    # 안 줬으면 세션에 저장된(sticky) 폴더를 이어서 씁니다 - 매번 반복 안 해도 됩니다.

    $conversationId = ""

    $knownModel     = ""

    if ($sessionName) {

        $existingSession = Invoke-WithRuntimeLock { Read-Session $sessionName }

        if ($existingSession) {

            if ($existingSession.conversation_id) { $conversationId = [string]$existingSession.conversation_id }

            # 이번 호출에 @cwd 가 하나라도 있으면 이번 목록만, 없으면 세션의 목록(예전 파일의 문자열 하나도 읽는다)
            $targetCwds = @(Resolve-TaskCwds $targetCwds $existingSession.cwd)

            if ($existingSession.model) { $knownModel = [string]$existingSession.model }

        }

    }



    # @model 검사: 쓸 수 없는 모델이면 agy 를 부르지 않고 바로 실패 처리합니다(@cwd 오류와 같은 방식).
    $modelCheck = Resolve-RequestedModel $requestedModel $conversationId $knownModel $sessionName
    if ($modelCheck.Error) {
        Set-Content -Path $outFile -Value $modelCheck.Error -Encoding UTF8
        Log "실패: $($modelCheck.Error)"
        Write-UsageRow $baseName $null $null $requestedModel $null $null $null $null $null "ERROR" $sessionName $conversationId
        Complete-TaskQaRecord $baseName $file.FullName $doneFile
        return
    }
    $requestedModel = $modelCheck.Model
    if ($requestedModel) { Log "  -> 지정 모델(@model): $requestedModel (다른 모델로 자동 전환하지 않음)" }

    $missingCwds = @(Get-MissingCwds $targetCwds)
    if ($missingCwds.Count -gt 0) {
        Set-Content -Path $outFile -Value "지정한 @cwd 경로를 찾을 수 없습니다: $($missingCwds -join ', ')" -Encoding UTF8
        Log "실패: @cwd 경로 없음 ($($missingCwds -join ', '))"
        # agy를 호출하지 않고 여기서 바로 실패 처리하는 경우도, 나중에 "이 작업이
        # 있었는지" 조회할 수 있도록 다른 실패와 똑같이 usage.csv/qa-jsonl에 남깁니다
        # (여기서 기록하지 않으면 outbox에는 파일이 남는데 기록에서는 통째로 빠집니다).
        Write-UsageRow $baseName $null $null $null $null $null $null $null $null "ERROR" $sessionName $conversationId

        Complete-TaskQaRecord $baseName $file.FullName $doneFile

        return
    }



    foreach ($cwdPath in $targetCwds) {

        Log "  -> 대상 폴더(--add-dir): $cwdPath"

    }

    if ($sessionName) {

        Log "  -> 세션: $sessionName$(if ($conversationId) { " (이어감, ID: $conversationId)" } else { " (새로 시작)" })"

    }



    $recModel    = $null
    $recAttempts = $null
    $recTried    = ""
    $recInTok    = $null
    $recOutTok   = $null
    $recThinkTok = $null
    $recTotTok   = $null
    $recElapsed  = $null
    $recStatus   = "ERROR"
    $effectiveSessionId = $conversationId

    try {
        # 프롬프트 길이와 무관하게 항상 임시 프롬프트 파일(@$tempPromptFile)을 사용하여
        # 명령줄 따옴표/이스케이프 깨짐을 방지하고 병렬 실행 시 고유한 대화 식별 Marker를 보장합니다.
        $promptsDir = Join-Path $LogsDir "prompts"
        if (-not (Test-Path -LiteralPath $promptsDir)) {
            New-Item -ItemType Directory -Force -Path $promptsDir | Out-Null
        }
        $tempPromptFile = Join-Path $promptsDir "prompt_$baseName.txt"
        [System.IO.File]::WriteAllText($tempPromptFile, $promptText, (New-Object System.Text.UTF8Encoding($false)))
        $safePrompt = $promptText -replace '"', '\"'

        $agyResult = Invoke-AgyWithFallback -safePrompt $safePrompt -targetCwd $targetCwds -skipPerm:$SkipPermissions -errFile $errFile -conversationId $conversationId -knownModel $knownModel -taskId $baseName -promptFile $tempPromptFile -requestedModel $requestedModel

        if ($agyResult.RawJson) {
            Set-Content -Path (Join-Path $OutboxDir "$baseName.raw.json") -Value $agyResult.RawJson -Encoding UTF8
        }

        $triedStr = $agyResult.TriedModels -join ' -> '
        $effectiveSessionId = if ($agyResult.ConversationId) { $agyResult.ConversationId } else { $conversationId }
        $recAttempts = $agyResult.Attempts
        $recTried    = $triedStr

        if ($agyResult.Success) {
            Set-Content -Path $outFile -Value $agyResult.Response -Encoding UTF8

            $elapsedForLog = if ($agyResult.AgyDuration) { [math]::Round([double]$agyResult.AgyDuration, 1) } else { $agyResult.ElapsedSec }
            $timeSrc = if ($agyResult.AgyDuration) { "agy 자체 보고" } else { "워처 측정(폴백 시도 포함 총 시간)" }
            $thinkPart = if ($agyResult.ThinkTok) { "/사고:$($agyResult.ThinkTok)" } else { "" }
            $tokStr  = if ($agyResult.TotTok) { "$($agyResult.TotTok) (입력:$($agyResult.InTok)/출력:$($agyResult.OutTok)$thinkPart)" } else { "확인불가" }
            $attemptNote = if ($agyResult.Attempts -gt 1) { " (시도: $triedStr)" } else { "" }
            $sessionNote = if ($sessionName) { " [세션: $sessionName (ID: $effectiveSessionId)]" } else { "" }

            $modelDisplay = if ($agyResult.ModelUsed) { $agyResult.ModelUsed } else { "(확인불가)" }
            Log "완료 -> $outFile"
            Log "  사용 모델: $modelDisplay$attemptNote$sessionNote | 토큰: $tokStr | 소요시간: ${elapsedForLog}초 ($timeSrc)"

            $recModel    = $agyResult.ModelUsed
            $recInTok    = $agyResult.InTok
            $recOutTok   = $agyResult.OutTok
            $recThinkTok = $agyResult.ThinkTok
            $recTotTok   = $agyResult.TotTok
            $recElapsed  = $elapsedForLog
            $recStatus   = "OK"

            Write-UsageRow $baseName $recModel $recAttempts $recTried $recInTok $recOutTok $recThinkTok $recTotTok $recElapsed "OK" $sessionName $effectiveSessionId

            if ($sessionName -and $agyResult.ConversationId) {
                Invoke-WithRuntimeLock { Write-Session -Name $sessionName -ConversationId $agyResult.ConversationId -Cwd $targetCwds -Model $agyResult.ModelUsed }
            }
        } else {
            $failMsg = "agy 실행 실패 (시도한 모델: $triedStr) - $($agyResult.ErrorMessage)"
            if ($requestedModel -and -not $conversationId) { $failMsg += " [@model 로 지정한 모델이라 다른 모델로 자동 전환하지 않았습니다]" }

            Set-Content -Path $outFile -Value $failMsg -Encoding UTF8
            Log $failMsg
            $recElapsed = $agyResult.ElapsedSec
            Write-UsageRow $baseName $null $recAttempts $recTried $null $null $null $null $recElapsed "ERROR" $sessionName $effectiveSessionId
        }

        Update-UsageSummary
    } catch {
        $errMsg = "agy 실행 중 오류: $($_.Exception.Message)"
        Set-Content -Path $outFile -Value $errMsg -Encoding UTF8
        Log $errMsg
        Write-UsageRow $baseName $null $null $null $null $null $null $null $null "ERROR" $sessionName $conversationId
        Update-UsageSummary
    } finally {
        if ($tempPromptFile -and (Test-Path -LiteralPath $tempPromptFile)) {
            Remove-Item -LiteralPath $tempPromptFile -Force -ErrorAction SilentlyContinue
        }
    }



    # 지시파일을 processed 로 옮긴 뒤에 기록 저장소에 덧붙여야 방금 처리한 작업의 질문 내용도 바로 담긴다.
    Complete-TaskQaRecord $baseName $file.FullName $doneFile
}

# 작업자 모드: 지시파일 하나만 처리하고 끝낸다(워처 본체는 시작하지 않는다)
if ($WorkerTask) {
    Invoke-InboxTask $WorkerTask
    exit 0
}

$script:Stopping = $false
$script:SeenFiles = @{}


# --- 종료 로그 ---

# Ctrl+C로 종료되면(가장 흔한 종료 방법) 아래 while 루프를 감싼 try/finally의 finally가

# 실행되어 종료 로그가 남습니다. 추가로, PowerShell 엔진 자체가 닫히는 경우(exit 입력, 창

# 닫기 등)에 대비해 PowerShell.Exiting 이벤트에도 로그를 남기는 핸들러를 걸어둡니다.

$global:AgyWatcherExitLogged = $false



$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {

    try {

        if (-not $global:AgyWatcherExitLogged) {

            $global:AgyWatcherExitLogged = $true

            $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            Add-Content -Path $global:LogFile -Value "[$ts] ------------------------------------------------------------" -Encoding UTF8

            Add-Content -Path $global:LogFile -Value "[$ts] ===== 워처 종료 (PowerShell 엔진 종료 이벤트 감지) =====" -Encoding UTF8

            Add-Content -Path $global:LogFile -Value "[$ts] ------------------------------------------------------------" -Encoding UTF8

        }

    } catch {}

}



Log "------------------------------------------------------------"

Log "===== 워처 시작 ====="

Log "  repo 루트              : $RepoRoot"

Log "  런타임 폴더            : $RuntimeDir"

Log "  지시파일 폴더 (inbox)  : $InboxDir"

Log "  답변파일 폴더 (outbox) : $OutboxDir"

Log "  처리완료 폴더          : $ProcessedDir"

Log "  로그 폴더              : $LogsDir"

Log "  모델 우선순위          : $($ModelPriority -join ' -> ')"
Log "  지정 가능 모델(@model:): $($SelectableModels -join ', ')"

Log "  컴퓨터 이름            : $ComputerName"

Log "종료하려면 Ctrl+C 를 누르세요."

Log "------------------------------------------------------------"



if (Test-Path $StopSignalFile) {

    Remove-Item -Path $StopSignalFile -Force -ErrorAction SilentlyContinue

    Log "이전에 남아있던 정지 신호 파일을 정리했습니다 (시작 직후 바로 멈추는 걸 방지)."

}



# restart-agy.ps1/ensure-agy-running.ps1는 시작하기 전에 살아있는지 먼저 확인하지만,

# 그 확인과 이 스크립트가 실제로 실행되는 사이에는 시간차가 있어 경쟁 상태가 생길 수

# 있습니다(예: 사용자가 start-agy.ps1을 두 번 연달아 실행). 그래서 여기서도 한 번 더,

# 이 잠금 파일이 지금 살아있는 다른 워처를 가리키는지 스스로 확인합니다 - 안 그러면

# 그냥 덮어쓰고 둘 다 같은 inbox를 폴링하게 되어 파일 이동이 충돌합니다.

if (Test-Path $LockFile) {

    $existingPid = 0

    try { $existingPid = [int]((Get-Content -Path $LockFile -Raw -ErrorAction SilentlyContinue).Trim()) } catch { $existingPid = 0 }

    if ($existingPid -gt 0 -and $existingPid -ne $PID) {

        $existingProc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue

        if ($existingProc -and $existingProc.ProcessName -eq "powershell") {

            Log "다른 워처가 이미 실행 중인 것으로 보여(PID $existingPid) 시작하지 않습니다."

            Log "먼저 stop-agy.ps1로 끄거나 restart-agy.ps1로 재시작해 주세요."

            exit 1

        }

    }

}



try {

    "$PID" | Set-Content -Path $LockFile -Encoding UTF8

    Log "잠금 파일에 이 워처의 PID($PID)를 기록했습니다: $LockFile"

} catch {

    Log "잠금 파일 기록 실패(계속 진행합니다): $($_.Exception.Message)"

}



if (Test-Path $ManualStopFlag) {

    Remove-Item -Path $ManualStopFlag -Force -ErrorAction SilentlyContinue

    Log "수동 정지 표시를 해제했습니다 (워처가 다시 시작됨 -> 워치독이 정상적으로 감시를 재개합니다)."

}



Update-QAReport

New-Item -ItemType Directory -Force -Path $RunningDir -ErrorAction SilentlyContinue | Out-Null
Remove-StaleSessions -MaxAgeDays $SessionMaxAgeDays



try {

    while ($true) {

        # stop-agy.ps1이 만든 정지 신호 파일이 있으면, 강제 종료가 아니라 정상적으로

        # 이 루프를 빠져나가서 아래 finally 블록의 정상 종료 로그를 그대로 남깁니다.

        if ((Test-Path $StopSignalFile) -and -not $script:Stopping) {
            Remove-Item -Path $StopSignalFile -Force -ErrorAction SilentlyContinue
            $script:Stopping = $true
            $nowRunning = @(Get-RunningClaims).Count
            Log "정지 신호 파일 감지 -> 새 작업은 더 받지 않고, 실행 중인 작업 ${nowRunning}건이 끝나면 정상 종료합니다."
        }



        # --- 디스패처: 작업마다 작업자 프로세스를 띄워 여러 작업을 동시에 돌린다 ---
        # 규칙: 같은 @session 이름이면서 작업 폴더(@cwd)가 겹치는 작업끼리만 차례로 한다(같은 대화·같은 폴더를 동시에 만지지 않게).
        #       세션이 다르거나, 같은 세션이어도 폴더가 서로 다르면(겹치지 않으면) 함께 돌린다. 동시에 도는 수는 $MaxParallel 까지.
        $claims = @(Get-RunningClaims)
        if ($script:Stopping) {
            if ($claims.Count -eq 0) {
                Log "실행 중이던 작업이 모두 끝나 정상 종료합니다."
                break
            }
        } else {
            $reserved = New-Object System.Collections.ArrayList
            foreach ($c in $claims) { [void]$reserved.Add(@{ Session = [string]$c.session; Cwds = @($c.cwds) }) }
            $runningIds = @($claims | ForEach-Object { [string]$_.task_id })
            $slots = $MaxParallel - $claims.Count

            $files = @(Get-ChildItem -Path $InboxDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in ".txt", ".md" } |
                Sort-Object CreationTime)

            # 사라진 파일의 기록은 버린다
            foreach ($seenKey in @($script:SeenFiles.Keys)) {
                if (-not (Test-Path -LiteralPath $seenKey)) { $script:SeenFiles.Remove($seenKey) }
            }

            foreach ($file in $files) {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                if ($runningIds -contains $baseName) { continue }

                # 파일이 아직 저장(쓰기) 중일 수 있으므로 크기가 한 번 더 확인할 때까지 같아야 시작한다.
                # ($file.Length 는 열거 시점 값이라 믿지 않고 Get-Item 으로 새로 읽는다)
                $cur = Get-Item -LiteralPath $file.FullName -ErrorAction SilentlyContinue
                if (-not $cur) { continue }
                $seen = $script:SeenFiles[$file.FullName]
                if ($null -eq $seen -or $seen.Len -ne $cur.Length) {
                    $script:SeenFiles[$file.FullName] = @{ Len = $cur.Length; At = (Get-Date) }
                    continue
                }
                if (((Get-Date) - $seen.At).TotalMilliseconds -lt 700) { continue }

                # 이 작업의 세션·폴더(세션에 저장된 폴더 포함)를 읽는다
                $taskSession = ""
                $taskCwds = @()
                try {
                    $rawText = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
                    $dir = ConvertFrom-TaskDirectives $rawText
                    $taskSession = [string]$dir.Session
                    $taskCwds = @($dir.Cwd)
                    if ($taskSession) {
                        $sess = Invoke-WithRuntimeLock { Read-Session $taskSession }
                        if ($sess) { $taskCwds = @(Resolve-TaskCwds $taskCwds $sess.cwd) }
                    }
                } catch {}

                $conflict = $false
                foreach ($r in $reserved) {
                    if (Test-TaskConflict $taskSession $taskCwds $r.Session $r.Cwds) { $conflict = $true; break }
                }
                # 시작하지 못하는 작업도 자리를 잡아 둔다: 같은 세션·폴더의 뒤 작업이 앞질러 시작하지 않게
                [void]$reserved.Add(@{ Session = $taskSession; Cwds = $taskCwds })
                if ($conflict -or $slots -le 0) { continue }

                if (Start-InboxWorker $file $taskSession $taskCwds) { $slots-- }
            }
        }



        # 하트비트: $HeartbeatIntervalSec 마다만 씁니다.
        try {
            if (((Get-Date) - $script:LastHeartbeatAt).TotalSeconds -ge $HeartbeatIntervalSec) {
                if (-not (Test-Path $HeartbeatDir)) {
                    New-Item -ItemType Directory -Force -Path $HeartbeatDir -ErrorAction SilentlyContinue | Out-Null
                }
                Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Set-Content -Path $HeartbeatFile -Encoding UTF8 -ErrorAction Stop
                $script:LastHeartbeatAt = Get-Date
            }
        } catch {}



        Start-Sleep -Seconds $PollSeconds

    }

} catch {

    # PowerShell이 스스로 감지할 수 있는 오류(스크립트 내부 예외 등)로 루프가 죽는 경우

    # 여기서 실제 오류 내용을 로그에 남깁니다. 단, Stop-Process/작업 관리자 강제 종료처럼

    # OS가 프로세스를 그 자리에서 즉시 죽이는 경우는 어떤 프로그램의 try/catch/finally로도

    # 절대 잡을 수 없습니다 - 이런 강제종료는 위의 하트비트 파일로 사후에 감지해야 합니다.

    try {

        $global:AgyWatcherExitLogged = $true

        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        Add-Content -Path $LogFile -Value "[$ts] ------------------------------------------------------------" -Encoding UTF8

        Add-Content -Path $LogFile -Value "[$ts] ===== 워처 비정상 종료 (처리되지 않은 오류) =====" -Encoding UTF8

        Add-Content -Path $LogFile -Value "[$ts] $($_.Exception.Message)" -Encoding UTF8

        Add-Content -Path $LogFile -Value "[$ts]   위치: $($_.InvocationInfo.PositionMessage)" -Encoding UTF8

    } catch {}

} finally {

    # Ctrl+C를 포함해 이 루프가 어떤 이유로든 빠져나갈 때(catch에서 처리된 경우도 포함) 항상 실행됩니다.

    # 위 catch에서 이미 "비정상 종료" 로그를 남긴 경우는 여기서 또 남기지 않습니다.

    # 잠금 파일은 내 PID가 적혀 있을 때만 지웁니다 (다른 워처 것을 지우지 않도록).

    try {

        if ((Test-Path $LockFile) -and ((Get-Content -Path $LockFile -Raw -ErrorAction SilentlyContinue).Trim() -eq "$PID")) {

            Remove-Item -Path $LockFile -Force -ErrorAction SilentlyContinue

        }

        Remove-Item -Path $HeartbeatFile -Force -ErrorAction SilentlyContinue

    } catch {}



    if (-not $global:AgyWatcherExitLogged) {

        $global:AgyWatcherExitLogged = $true

        Log "------------------------------------------------------------"

        Log "===== 워처 종료 (Ctrl+C 또는 스크립트 종료) ====="

        Log "------------------------------------------------------------"

    }

}

