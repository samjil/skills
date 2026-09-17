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

    [string]$RepoRoot    = (Split-Path -Path $PSScriptRoot -Parent),

    [string]$RuntimeDir  = "",

    [int]$PollSeconds    = 2,

    [switch]$SkipPermissions = $true

)



# 콘솔에서 한글이 깨지지 않도록 출력 인코딩을 UTF-8로 고정합니다.

try {

    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    $OutputEncoding = [System.Text.Encoding]::UTF8

    chcp 65001 > $null

} catch {}



if (-not $RuntimeDir) {

    if ($env:AGY_DELEGATE_RUNTIME) {

        $RuntimeDir = $env:AGY_DELEGATE_RUNTIME

    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime")) {

        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime"

    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\agent-delegate-agy\runtime")) {

        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\agent-delegate-agy\runtime"

    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\delegate\runtime")) {

        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\delegate\runtime"

    } elseif (Test-Path (Join-Path $env:USERPROFILE ".agent-delegate\runtime")) {

        $RuntimeDir = Join-Path $env:USERPROFILE ".agent-delegate\runtime"

    } elseif (Test-Path (Join-Path $RepoRoot "runtime")) {

        $RuntimeDir = Join-Path $RepoRoot "runtime"

    } else {

        $RuntimeDir = Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime"

    }

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



$ComputerName = $env:COMPUTERNAME

if (-not $ComputerName) { $ComputerName = "(알수없음)" }



$InboxDir     = Join-Path $RuntimeDir "inbox"

$OutboxDir    = Join-Path $RuntimeDir "outbox"

$ProcessedDir = Join-Path $RuntimeDir "processed"

$StuckDir     = Join-Path $RuntimeDir "_stuck"

$LogsDir      = Join-Path $RuntimeDir "logs"



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



function Log($msg) {

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $line = "[$ts] $msg"

    Write-Host $line

    try {

        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt $LogMaxBytes)) {

            $tail = Get-Content -Path $LogFile -Tail $LogKeepLines

            Set-Content -Path $LogFile -Value $tail -Encoding UTF8

        }

        Add-Content -Path $LogFile -Value $line -Encoding UTF8

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



function Write-UsageRow($taskId, $model, $attempts, $triedModels, $inputTokens, $outputTokens, $thinkingTokens, $totalTokens, $elapsedSec, $status, [string]$session = "", [string]$sessionId = "") {

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

    } catch {

        Log "usage.csv 기록 중 오류: $($_.Exception.Message)"

    }

}



# usage.csv 전체를 모델별로 집계해서 usage_summary.csv를 다시 씁니다.

function Update-UsageSummary {

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



# @session: <이름>으로 이어가는 agy 대화의 이름<->conversation_id 매핑 파일들이 담깁니다.

# (common.ps1의 세션 헬퍼 함수들이 이 경로를 씁니다. 3.8절 참고 - docs\설계.md)

$SessionsDir      = Join-Path $LogsDir "sessions"

$SessionMaxAgeDays = 30    # 이보다 오래 안 쓴 세션은 자동으로 정리합니다.



$script:QaKnownIds = $null

$script:QaTotal    = 0



# ConvertTo-ReadableJson / Get-QaShardFiles / Get-QaShardPath는 log-qa.ps1과 공유합니다

# (common.ps1 참고 - 두 곳에 복사해두면 한쪽만 고치고 놓치는 사고가 나기 쉽습니다).

. (Join-Path $PSScriptRoot "common.ps1")



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



            $qFile = Get-ChildItem -Path $ProcessedDir -Filter "$taskId.*" -ErrorAction SilentlyContinue | Select-Object -First 1

            $qText = if ($qFile) {

                Get-Content -Raw -Path $qFile.FullName -Encoding UTF8 -ErrorAction SilentlyContinue

            } else { "(원본 지시파일을 찾을 수 없음 - 이미 정리되었을 수 있습니다)" }



            $aPath = Join-Path $OutboxDir "$taskId.response.md"

            $aText = if (Test-Path $aPath) {

                Get-Content -Raw -Path $aPath -Encoding UTF8 -ErrorAction SilentlyContinue

            } else { "(응답 파일 없음)" }



            $rec = [ordered]@{

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

            }



            $line = ConvertTo-ReadableJson $rec 6

            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            Add-Content -Path (Get-QaShardPath) -Value $line -Encoding UTF8



            [void]$script:QaKnownIds.Add($taskId)

            $script:QaTotal++

            $added++

        }

    } catch {

        Log "기록 저장소 동기화 중 오류: $($_.Exception.Message)"

    }

    return $added

}



function Update-QaIndex {

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

            total       = $script:QaTotal

            keep_months = $QaKeepMonths

            note        = "qa-YYYY-MM.jsonl 파일의 한 줄이 작업 한 건입니다. 한 파일이 5MB를 넘으면 같은 달이라도 qa-YYYY-MM.p2.jsonl 처럼 나뉩니다."

            shards      = @($shards)

        }

        Set-Content -Path $QaIndexFile -Value (ConvertTo-ReadableJson $idx 6 -Pretty) -Encoding UTF8

    } catch {

        Log "index.json 갱신 중 오류: $($_.Exception.Message)"

    }

}



function Update-QAReport {

    $null = Sync-QaStore

    Update-QaIndex

}



# agy 한 번 호출이 이 시간을 넘기면 강제로 중단하고 그 작업을 실패 처리합니다.

# (없으면 agy가 멈췄을 때 워처 전체가 무한정 묶입니다 - 실제로 agy가 콘솔 입력을

#  기다리는 바람에 워처가 13분 넘게 그 자리에서 멈춘 적이 있습니다.)

$AgyTimeoutSeconds = 600



# agy를 "백그라운드 작업"으로 한 번 실행하고, 타임아웃을 걸어 기다립니다.

# 백그라운드 작업에는 콘솔이 붙어있지 않기 때문에, agy(또는 agy가 실행한 명령)가 입력을

# 요구해도 즉시 EOF가 되어 무한 대기에 빠지지 않습니다. 이것이 위 사고의 직접적인 방지책이고,

# 타임아웃은 그 밖의 이유로 멈추는 경우를 위한 안전장치입니다.

#

# 반환: @{ TimedOut = $true/$false; Raw = <agy 표준출력> }

function Invoke-AgyOnce($agyArgs, $errFile, $workDir) {

    # 타임아웃 시 남을 수 있는 자식 프로세스를 가려내기 위해, 호출 전 agy 프로세스 목록을 기억합니다.

    $before = @(Get-Process -Name "agy" -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })



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



    $finished = Wait-Job -Job $job -Timeout $AgyTimeoutSeconds



    if ($null -eq $finished) {

        Stop-Job   -Job $job -ErrorAction SilentlyContinue

        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue



        # 작업을 죽여도 자식 agy.exe가 남을 수 있으므로, 이번 호출로 새로 생긴 것만 정리합니다.

        foreach ($proc in @(Get-Process -Name "agy" -ErrorAction SilentlyContinue)) {

            if ($before -notcontains $proc.Id) {

                try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}

            }

        }

        return @{ TimedOut = $true; Raw = $null }

    }



    $out = Receive-Job -Job $job -ErrorAction SilentlyContinue

    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    return @{ TimedOut = $false; Raw = $out }

}



# $conversationId가 없으면: $ModelPriority 목록을 순서대로 시도합니다(기존 동작).

# $conversationId가 있으면(@session:으로 이어가는 경우): --conversation으로 그 대화를

# 이어가는 호출 한 번만 합니다 - 모델은 그 대화가 시작될 때 쓴 걸 agy가 그대로 유지하므로

# --model도, 폴백 후보 목록도 필요 없습니다(직접 검증함). agy는 conversation_id가

# 만료/유실됐어도 에러 없이 조용히 새 대화로 시작해주므로, 성공 응답에서 conversation_id가

# 우리가 보낸 것과 다르면 그걸로 "세션이 갱신됐다"는 걸 알아챕니다.

# 쿼터 초과 등 폴백 대상 오류면(새 세션 시도일 때만) 다음 모델로, 그 외 오류면 즉시 중단합니다.

function Invoke-AgyWithFallback($safePrompt, $targetCwd, [bool]$skipPerm, $errFile, [string]$conversationId = "", [string]$knownModel = "") {

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

    $candidates = if ($conversationId) { @("(continue)") } else { $ModelPriority }



    foreach ($candidate in $candidates) {

        $result.Attempts++

        $result.TriedModels += $candidate



        $agyArgs = @('-p', $safePrompt, '--output-format', 'json')

        if ($conversationId) { $agyArgs += @('--conversation', $conversationId) } else { $agyArgs += @('--model', $candidate) }

        if ($targetCwd) { $agyArgs += @('--add-dir', $targetCwd) }

        if ($skipPerm)  { $agyArgs += '--dangerously-skip-permissions' }



        $call = Invoke-AgyOnce $agyArgs $errFile $RuntimeDir

        if ($call.TimedOut) {

            $result.ErrorMessage = "agy 호출이 $AgyTimeoutSeconds 초를 넘겨 중단했습니다 (타임아웃)"

            Log "  타임아웃: agy 호출이 $AgyTimeoutSeconds 초를 넘겨 강제로 중단했습니다. 이 작업은 실패로 기록합니다."

            break

        }

        $raw = $call.Raw



        $json = $null

        try { $json = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $json = $null }



        if ($null -eq $json) {

            # JSON 파싱 자체가 실패 - agy 실행이 비정상 종료된 경우. 모델 문제가 아닐 가능성이

            # 높으므로 다음 모델로 넘어가지 않고 여기서 중단합니다.

            $result.RawJson = $raw

            $result.ErrorMessage = "agy 응답을 JSON으로 해석할 수 없음"

            break

        }



        if ($json.status -ne "ERROR" -and $json.response) {

            # 성공

            $result.Success        = $true

            $result.Response       = $json.response

            $result.RawJson        = $raw

            $result.ModelUsed      = if ($conversationId) {

                if ($knownModel) { $knownModel } else { $ModelPriority[0] }

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

    return $result

}



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

Remove-StaleSessions -MaxAgeDays $SessionMaxAgeDays



try {

    while ($true) {

        # stop-agy.ps1이 만든 정지 신호 파일이 있으면, 강제 종료가 아니라 정상적으로

        # 이 루프를 빠져나가서 아래 finally 블록의 정상 종료 로그를 그대로 남깁니다.

        if (Test-Path $StopSignalFile) {

            Remove-Item -Path $StopSignalFile -Force -ErrorAction SilentlyContinue

            Log "정지 신호 파일 감지 -> 정상 종료합니다."

            break

        }



        $files = Get-ChildItem -Path $InboxDir -File -ErrorAction SilentlyContinue |

            Where-Object { $_.Extension -in ".txt", ".md" } |

            Sort-Object CreationTime



        foreach ($file in $files) {

            # 파일이 아직 저장(쓰기) 중일 수 있으므로 크기가 안정될 때까지 대기

            # 참고: $file.Length는 Get-ChildItem이 열거 시점에 캐시해둔 값이라 신뢰하지

            # 않고, "before"/"after" 모두 Get-Item으로 매번 새로 조회해서 비교합니다.

            $before = Get-Item -LiteralPath $file.FullName -ErrorAction SilentlyContinue

            Start-Sleep -Milliseconds 700

            $current = Get-Item -LiteralPath $file.FullName -ErrorAction SilentlyContinue

            if (-not $before -or -not $current -or $current.Length -ne $before.Length) { continue }



            $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

            $outFile   = Join-Path $OutboxDir  "$baseName.response.md"

            $errFile   = Join-Path $OutboxDir  "$baseName.error.log"

            $doneFile  = Join-Path $ProcessedDir $file.Name



            Log "처리 중: $($file.Name)"



            $rawText = Get-Content -Raw -Path $file.FullName -Encoding UTF8



            # 지시파일 맨 위에 "@키: 값" 줄이 있으면(순서 무관, 여러 줄 가능) 읽어들이고,

            # 그 형식이 아닌 첫 줄부터가 실제 프롬프트 본문입니다. 지원하는 키:

            #   @cwd:     agy의 워크스페이스에 추가할 폴더 (--add-dir)

            #   @session: 대화를 이어갈 세션 이름 (3.8절 - docs\설계.md). 같은 이름으로 다시

            #             보내면 이전 대화 맥락을 그대로 이어받습니다. 이 줄이 없으면 매번

            #             빈 상태로 새로 시작하는 기존 동작 그대로입니다.

            $targetCwd   = $null

            $sessionName = $null

            $promptText  = $rawText

            while ($true) {

                $firstLine = ($promptText -split "`r?`n", 2)[0]

                if ($firstLine -match '^\s*$') {

                    # 빈 줄은 건너뛰고 계속 파싱합니다

                } elseif ($firstLine -match '^\ufeff?@cwd:\s*(.+)$') {

                    $targetCwd = $Matches[1].Trim()

                } elseif ($firstLine -match '^\ufeff?@session:\s*(.+)$') {

                    $sessionName = $Matches[1].Trim()

                } else {

                    break

                }

                $rest = ($promptText -split "`r?`n", 2)

                $promptText = if ($rest.Length -gt 1) { $rest[1] } else { "" }

            }



            # 세션이 있으면 이전에 저장해둔 conversation_id와 model을 불러옵니다. @cwd를 이번엔

            # 안 줬으면 세션에 저장된(sticky) 폴더를 이어서 씁니다 - 매번 반복 안 해도 됩니다.

            $conversationId = ""

            $knownModel     = ""

            if ($sessionName) {

                $existingSession = Read-Session $sessionName

                if ($existingSession) {

                    if ($existingSession.conversation_id) { $conversationId = [string]$existingSession.conversation_id }

                    if (-not $targetCwd -and $existingSession.cwd) { $targetCwd = [string]$existingSession.cwd }

                    if ($existingSession.model) { $knownModel = [string]$existingSession.model }

                }

            }



            if ($targetCwd -and -not (Test-Path $targetCwd)) {

                Set-Content -Path $outFile -Value "지정한 @cwd 경로를 찾을 수 없습니다: $targetCwd" -Encoding UTF8

                Log "실패: @cwd 경로 없음 ($targetCwd)"

                # agy를 호출하지 않고 여기서 바로 실패 처리하는 경우도, 나중에 "이 작업이

                # 있었는지" 조회할 수 있도록 다른 실패와 똑같이 usage.csv/qa-jsonl에 남깁니다

                # (여기서 기록하지 않으면 outbox에는 파일이 남는데 기록에서는 통째로 빠집니다).

                Write-UsageRow $baseName $null $null $null $null $null $null $null $null "ERROR" $sessionName $conversationId

                Move-Item -Path $file.FullName -Destination $doneFile -Force

                Update-QAReport

                continue

            }



            if ($targetCwd) {

                Log "  -> 대상 폴더(--add-dir): $targetCwd"

            }

            if ($sessionName) {

                Log "  -> 세션: $sessionName$(if ($conversationId) { " (이어감, ID: $conversationId)" } else { " (새로 시작)" })"

            }



            try {

                # 참고 (시행착오 기록):

                #   - -p는 반드시 자기 값을 직접 받아야 한다 (stdin 단독 사용 불가).

                #   - 프롬프트에 큰따옴표(")가 섞이면 PowerShell -> 네이티브 exe 커맨드라인

                #     변환 과정에서 인자 경계가 깨지므로, 미리 \" 로 이스케이프해서 넘긴다.

                #   - --cwd 플래그는 존재하지 않는다. 대상 폴더는 --add-dir로 추가한다.

                $safePrompt = $promptText -replace '"', '\"'



                $agyResult = Invoke-AgyWithFallback -safePrompt $safePrompt -targetCwd $targetCwd -skipPerm:$SkipPermissions -errFile $errFile -conversationId $conversationId -knownModel $knownModel



                if ($agyResult.RawJson) {

                    Set-Content -Path (Join-Path $OutboxDir "$baseName.raw.json") -Value $agyResult.RawJson -Encoding UTF8

                }



                $triedStr = $agyResult.TriedModels -join ' -> '

                $effectiveSessionId = if ($agyResult.ConversationId) { $agyResult.ConversationId } else { $conversationId }



                if ($agyResult.Success) {

                    Set-Content -Path $outFile -Value $agyResult.Response -Encoding UTF8



                    $elapsedForLog = if ($agyResult.AgyDuration) { [math]::Round([double]$agyResult.AgyDuration, 1) } else { $agyResult.ElapsedSec }

                    $timeSrc = if ($agyResult.AgyDuration) { "agy 자체 보고" } else { "워처 측정(폴백 시도 포함 총 시간)" }

                    $thinkPart = if ($agyResult.ThinkTok) { "/사고:$($agyResult.ThinkTok)" } else { "" }

                    $tokStr  = if ($agyResult.TotTok) { "$($agyResult.TotTok) (입력:$($agyResult.InTok)/출력:$($agyResult.OutTok)$thinkPart)" } else { "확인불가" }

                    $attemptNote = if ($agyResult.Attempts -gt 1) { " (시도: $triedStr)" } else { "" }

                    $sessionNote = if ($sessionName) { " [세션: $sessionName (ID: $effectiveSessionId)]" } else { "" }



                    Log "완료 -> $outFile"

                    Log "  사용 모델: $($agyResult.ModelUsed)$attemptNote$sessionNote | 토큰: $tokStr | 소요시간: ${elapsedForLog}초 ($timeSrc)"



                    Write-UsageRow $baseName $agyResult.ModelUsed $agyResult.Attempts $triedStr $agyResult.InTok $agyResult.OutTok $agyResult.ThinkTok $agyResult.TotTok $elapsedForLog "OK" $sessionName $effectiveSessionId



                    # 세션이 이어졌든 새로 시작했든, 성공한 응답의 conversation_id로 레지스트리를

                    # 갱신합니다(만료돼서 agy가 새 id로 시작했어도 이렇게 하면 자동으로 복구됨).

                    if ($sessionName -and $agyResult.ConversationId) {

                        Write-Session -Name $sessionName -ConversationId $agyResult.ConversationId -Cwd $targetCwd -Model $agyResult.ModelUsed

                    }

                } else {

                    $failMsg = "agy 실행 실패 (시도한 모델: $triedStr) - $($agyResult.ErrorMessage)"

                    Set-Content -Path $outFile -Value $failMsg -Encoding UTF8

                    Log $failMsg

                    Write-UsageRow $baseName $null $agyResult.Attempts $triedStr $null $null $null $null $agyResult.ElapsedSec "ERROR" $sessionName $effectiveSessionId

                }



                Update-UsageSummary

            } catch {

                $errMsg = "agy 실행 중 오류: $($_.Exception.Message)"

                Set-Content -Path $outFile -Value $errMsg -Encoding UTF8

                Log $errMsg

                Write-UsageRow $baseName $null $null $null $null $null $null $null $null "ERROR" $sessionName $conversationId

                Update-UsageSummary

            }



            Move-Item -Path $file.FullName -Destination $doneFile -Force



            # jsonl 기록은 원본 지시파일이 processed로 옮겨진 뒤에 갱신해야

            # 방금 처리한 작업의 질문 내용도 바로 담깁니다.

            Update-QAReport

        }



        # 하트비트: $HeartbeatIntervalSec 마다만 씁니다.

        try {

            if (((Get-Date) - $script:LastHeartbeatAt).TotalSeconds -ge $HeartbeatIntervalSec) {

                Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Set-Content -Path $HeartbeatFile -Encoding UTF8

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

