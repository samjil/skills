# serve-viewer.ps1
# samjil AI Agent 통합 웹 뷰어 서버 (Delegate QA 실행 기록 & Handoff 인수인계)
#
# 사용법:
#   .\serve-viewer.ps1                   # 브라우저 실행 및 http://127.0.0.1:8787 서빙
#   .\serve-viewer.ps1 -Port 9000        # 포트 지정
#   .\serve-viewer.ps1 -WatcherCheckSeconds 120   # 워처 자동 점검 주기(초). 0이면 점검 안 함
#   종료: 이 창에서 Ctrl+C
#
# agy 워처(watch-agy.ps1)가 꺼져 있으면 뷰어가 주기적으로(기본 60초) 점검해서 창 없이 다시 켭니다.
# stop-agy 로 일부러 끈 상태(manual_stop.flag)면 켜지 않습니다. 끄려면 -NoAgent 를 쓰세요.

param(
    [string]$HandoffDir = "",
    [string]$DataDir    = "",
    [string]$WebDir     = "",
    [int]$Port          = 8787,
    [switch]$NoBrowser  = $false,
    [switch]$NoAgent    = $false,
    [int]$WatcherCheckSeconds = 60
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$parentDir = Split-Path $PSScriptRoot -Parent

if (-not $HandoffDir) {
    if ($env:AGENT_HANDOFF_ROOT) {
        $HandoffDir = $env:AGENT_HANDOFF_ROOT
    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\handoff")) {
        $HandoffDir = Join-Path $env:USERPROFILE ".samjil\handoff"
    } elseif ($parentDir -and (Test-Path (Join-Path $parentDir "handoff"))) {
        $HandoffDir = Join-Path $parentDir "handoff"
    } elseif (Test-Path (Join-Path $PSScriptRoot "runtime\handoff")) {
        $HandoffDir = Join-Path $PSScriptRoot "runtime\handoff"
    } else {
        $HandoffDir = Join-Path $env:USERPROFILE ".samjil\handoff"
    }
}

if (-not $DataDir) {
    $dataCandidates = @()
    if ($env:AGY_DELEGATE_RUNTIME) {
        $dataCandidates += (Join-Path $env:AGY_DELEGATE_RUNTIME "logs\data")
    }
    $dataCandidates += (Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime\logs\data")
    if ($parentDir) {
        $dataCandidates += (Join-Path $parentDir "delegate-agy\runtime\logs\data")
    }
    $dataCandidates += (Join-Path $PSScriptRoot "runtime\delegate-agy\runtime\logs\data")

    foreach ($cand in $dataCandidates) {
        if ($cand -and (Test-Path (Join-Path $cand "index.json"))) {
            $DataDir = $cand
            break
        }
    }

    if (-not $DataDir) {
        $DataDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime\logs\data"
    }
}



if (-not $WebDir) {

    $WebDir = Join-Path $PSScriptRoot "web"

}



if (-not (Test-Path $HandoffDir)) {

    New-Item -ItemType Directory -Force -Path $HandoffDir | Out-Null

}

if (-not (Test-Path $DataDir)) {

    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

}



if (-not (Test-Path $WebDir)) {

    Write-Error "web 폴더를 찾을 수 없습니다: $WebDir"

    exit 1

}



# 워처 상태 판정/자동 재시작 헬퍼
. (Join-Path $PSScriptRoot "watcher-health.ps1")
$WatcherRuntimeDir = Get-WatcherRuntimeDir $DataDir

# Claude Desktop 세션 및 링크 색인 헬퍼
$claudeSessionsScript = Join-Path $PSScriptRoot "claude-sessions.ps1"
if (Test-Path -LiteralPath $claudeSessionsScript) {
    try {
        . $claudeSessionsScript
    } catch {
        Write-Warning ("claude-sessions.ps1 로드 실패: {0}" -f $_.Exception.Message)
    }
}

# Claude 세션 기록에서 호출별 사용량을 읽는 헬퍼(핸드오프 c2a 카드의 Claude 쪽 토큰). 못 불러와도 그 기능만 빠진다.
$claudeUsageScript = Join-Path $PSScriptRoot "claude-usage.ps1"
if (Test-Path -LiteralPath $claudeUsageScript) {
    try {
        . $claudeUsageScript
    } catch {
        Write-Warning ("claude-usage.ps1 로드 실패: {0}" -f $_.Exception.Message)
    }
}

$RouteMap = [ordered]@{

    "/handoff/" = (Resolve-Path $HandoffDir).Path

    "/data/"    = (Resolve-Path $DataDir).Path

    "/"         = (Resolve-Path $WebDir).Path

}



$MimeTypes = @{

    ".html"  = "text/html; charset=utf-8"

    ".htm"   = "text/html; charset=utf-8"

    ".js"    = "text/javascript; charset=utf-8"

    ".css"   = "text/css; charset=utf-8"

    ".json"  = "application/json; charset=utf-8"

    ".jsonl" = "application/x-ndjson; charset=utf-8"

    ".csv"   = "text/csv; charset=utf-8"

    ".txt"   = "text/plain; charset=utf-8"

    ".md"    = "text/plain; charset=utf-8"

    ".ico"   = "image/x-icon"

    ".svg"   = "image/svg+xml"

    ".png"   = "image/png"

    ".jpg"   = "image/jpeg"

    ".jpeg"  = "image/jpeg"

    ".gif"   = "image/gif"

    ".webp"  = "image/webp"

    ".bmp"   = "image/bmp"

}



function Get-Utf8QueryParams([System.Uri]$uri) {

    $dict = @{}

    $q = $uri.Query

    if (-not [string]::IsNullOrWhiteSpace($q)) {

        $trimmed = $q.TrimStart('?')

        $pairs = $trimmed.Split('&')

        foreach ($p in $pairs) {

            if ($p) {

                $idx = $p.IndexOf('=')

                if ($idx -ge 0) {

                    $k = [System.Uri]::UnescapeDataString($p.Substring(0, $idx))

                    $v = [System.Uri]::UnescapeDataString($p.Substring($idx + 1))

                    $dict[$k] = $v

                } else {

                    $k = [System.Uri]::UnescapeDataString($p)

                    $dict[$k] = ""

                }

            }

        }

    }

    return $dict

}



function Get-ContentType($path) {

    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()

    if ($MimeTypes.ContainsKey($ext)) { return $MimeTypes[$ext] }

    return "application/octet-stream"

}



function Resolve-SafePath([string]$urlPath) {

    $rootPrefix = "/"

    $root = $RouteMap["/"]

    foreach ($prefix in $RouteMap.Keys) {

        if ($prefix -ne "/" -and $urlPath.StartsWith($prefix)) {

            $rootPrefix = $prefix

            $root = $RouteMap[$prefix]

            break

        }

    }



    $relative = $urlPath.Substring($rootPrefix.Length).TrimStart('/')

    if ([string]::IsNullOrWhiteSpace($relative)) { $relative = "index.html" }

    $relative = [System.Uri]::UnescapeDataString($relative)



    $combined = Join-Path $root $relative

    $full = $null

    try { $full = [System.IO.Path]::GetFullPath($combined) } catch { return $null }



    $rootWithSep = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

    if ($full -ne $root -and -not $full.StartsWith($rootWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {

        return $null

    }

    return $full

}



function Get-HandoffRoots {

    $roots = [System.Collections.Generic.List[string]]::new()

    if ($HandoffDir -and (Test-Path $HandoffDir)) {

        $roots.Add((Resolve-Path $HandoffDir).Path)

    }

    $cands = @(

        (Join-Path $env:USERPROFILE ".samjil\handoff"),

        (Join-Path $env:USERPROFILE ".samjil\samjil-handoff"),

        (Join-Path $PSScriptRoot "runtime\handoff")

    )

    foreach ($c in $cands) {

        if (Test-Path $c) {

            $p = (Resolve-Path $c).Path

            if (-not $roots.Contains($p)) {

                $roots.Add($p)

            }

        }

    }

    return $roots

}



function Find-HandoffProjectDir([string]$projectName) {

    foreach ($r in (Get-HandoffRoots)) {

        $testP = Join-Path $r $projectName

        if (Test-Path -LiteralPath $testP -PathType Container) {

            return $testP

        }

    }

    return $null

}



# delegate-agy 스크립트를 찾습니다. $RelPath 는 scripts 폴더 기준(예: "start-agy.ps1", "sub\ensure-agy-running.ps1").
# @cwd 값 목록을 중복(대소문자, 끝의 \ 또는 / 무시)·빈 값을 빼고 줄 순서대로 배열로 만든다.
# common.ps1 의 ConvertTo-CwdList 와 같은 규칙의 사본이다(뷰어는 common.ps1 을 불러오지 않는다). tests\delegate-agy\cwd-list.tests.ps1 이 둘이 같은지 확인한다.
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

function Find-DelegateScript([string]$RelPath) {
    $cands = @()
    if ($env:AGY_DELEGATE_SCRIPTS) { $cands += (Join-Path $env:AGY_DELEGATE_SCRIPTS $RelPath) }
    # 이 뷰어와 같은 폴더 구조의 형제 폴더를 먼저 본다: 설치본 뷰어(~/.samjil/viewer) 옆에는 설치본 delegate-agy 가,
    # 저장소의 뷰어(runtime/viewer) 옆에는 저장소의 delegate-agy 가 있어서 두 경우 모두 버전이 맞는다.
    # (설치본을 먼저 보면, 저장소에서 뷰어를 돌릴 때 아직 설치 전인 옛 agy-progress.ps1 을 불러온다.)
    $cands += (Join-Path (Split-Path $PSScriptRoot -Parent) (Join-Path "delegate-agy\scripts" $RelPath))
    $cands += (Join-Path $env:USERPROFILE (Join-Path ".samjil\delegate-agy\scripts" $RelPath))
    $cands += (Join-Path $PSScriptRoot (Join-Path "runtime\delegate-agy\scripts" $RelPath))
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

# 진행 중인 agy 작업이 지금 무엇을 하는지 agy의 대화 기록(transcript_full.jsonl)에서 읽습니다.
# agy는 단계를 하나 끝낼 때마다 이 파일에 한 줄씩 덧붙이므로, 끝부분만 읽어도 현재 단계/최근 동작을 알 수 있습니다.
# 대화를 못 찾거나 모호하면 $null 을 돌려주고, 화면은 진행 상황 줄 없이 기존대로 표시합니다.
# 진행 중인 대화의 과정(도구 호출 목록)을 읽는다. 5초마다 불리는데 대화 기록이 수 MB 까지 커질 수 있어서, 대화마다
# "어디까지 읽었는지(Offset)"와 읽은 단계를 기억해 두고 새로 쌓인 부분만 이어 읽는다(Read-AgyProcessSteps 참고).
# 기억은 최근 8개 대화까지만 둔다.
$script:ProcessCache = @{}
$script:TokenCache = @{}
function Get-AgyProcessStepsCached([string]$ConversationId) {
    if (-not (Get-Command Read-AgyProcessSteps -ErrorAction SilentlyContinue)) { return @() }
    $tp = Get-AgyTranscriptPath (Get-AgyHomeDir) $ConversationId
    if (-not $tp) { return @() }
    $item = Get-Item -LiteralPath $tp -ErrorAction SilentlyContinue
    if (-not $item) { return @() }
    $c = $script:ProcessCache[$ConversationId]
    if (-not $c -or $item.Length -lt $c.Offset) {
        # 처음 보는 대화이거나, 파일이 더 짧아졌으면(새로 만들어짐) 처음부터 읽는다
        $c = @{ Offset = [long]0; Steps = (New-Object System.Collections.ArrayList); Touched = (Get-Date) }
        $script:ProcessCache[$ConversationId] = $c
        if ($script:ProcessCache.Count -gt 8) {
            $oldest = $script:ProcessCache.GetEnumerator() | Sort-Object { $_.Value.Touched } | Select-Object -First 1
            if ($oldest) { $script:ProcessCache.Remove($oldest.Key) }
        }
    }
    $c.Touched = Get-Date
    $r = Read-AgyProcessSteps $tp $c.Offset 400
    foreach ($st in @($r.Steps)) { if ($c.Steps.Count -lt 400) { [void]$c.Steps.Add($st) } }
    $c.Offset = [long]$r.Offset
    return @($c.Steps.ToArray())
}

# ---- 과정 번역("한글로 번역"): 번역은 agy 호출이라 30초~1분 걸린다. 요청 처리 루프를 막지 않도록 숨김 창의 보조 스크립트
# (sub\process-translate.ps1)가 하고, 여기서는 시작시키고 상태만 읽는다. 결과는 <데이터 폴더>\process-ko\<대화 id>.json 에 캐시된다.
$script:TranslateStaleSeconds = 360   # 실행 표시 파일이 이만큼 오래되면 죽은 것으로 본다

function Get-ProcessTranslationPath([string]$ConversationId) {
    if ($ConversationId -notmatch '^[A-Za-z0-9-]{1,80}$') { return $null }
    return (Join-Path $DataDir ("process-ko\{0}.json" -f $ConversationId))
}

# 상태: running(번역 중) | done(끝남) | none(아직 안 함·새 단계가 생김) | error | unavailable(대화 기록이 없어 번역할 수 없음)
# 대화 id 가 올바르지 않으면 $null. items 는 번역해 둔 것(단계 순번 -> label/think/say)이라 상태와 상관없이 함께 준다.
function Get-ProcessTranslationState([string]$ConversationId) {
    $cachePath = Get-ProcessTranslationPath $ConversationId
    if (-not $cachePath) { return $null }
    $cache = @{ Status = ""; Message = ""; StepsCovered = 0; Items = @{}; Model = "" }
    if (Get-Command Read-TranslationCache -ErrorAction SilentlyContinue) { $cache = Read-TranslationCache $cachePath }

    $state = "none"; $message = ""
    $run = Get-Item -LiteralPath "$cachePath.running" -ErrorAction SilentlyContinue
    $transcript = $null
    if (Get-Command Get-AgyTranscriptPath -ErrorAction SilentlyContinue) { $transcript = Get-AgyTranscriptPath (Get-AgyHomeDir) $ConversationId }
    $hasTranscript = [bool]($transcript -and (Test-Path -LiteralPath $transcript -PathType Leaf))

    if ($run -and ((Get-Date) - $run.LastWriteTime).TotalSeconds -lt $script:TranslateStaleSeconds) {
        $state = "running"
    } elseif ($cache.Items.Count -gt 0 -and -not $hasTranscript) {
        $state = "done"      # 대화 기록은 정리됐지만 번역해 둔 것은 남아 있다
    } elseif (-not $hasTranscript) {
        $state = "unavailable"; $message = "agy 대화 기록이 남아 있지 않아 번역할 수 없습니다"
    } elseif ($cache.Status -eq "unavailable") {
        $state = "none"      # 그때는 없었지만 지금은 있다: 다시 시도할 수 있게 둔다
    } elseif ($cache.Status -eq "done") {
        $stepList = @(Get-AgyProcessStepsCached $ConversationId)
        $state = if ($cache.StepsCovered -ge $stepList.Count) { "done" } else { "none" }
        # 번역 규칙이 바뀌어(예: 인용문 안의 한글은 한글로 세지 않는다) 예전에 건너뛴 칸이 새로 번역 대상이 되면 이어서 번역할 수 있게 한다
        if ($state -eq "done" -and (Get-Command Get-TranslationTodo -ErrorAction SilentlyContinue) -and @(Get-TranslationTodo $stepList $cache.Items).Count -gt 0) { $state = "none" }
    } elseif ($cache.Status -eq "error") {
        $state = "error"; $message = $cache.Message
    } elseif ($cache.Status -eq "partial") {
        $state = "error"; $message = "번역이 중간에 멈췄습니다. 다시 시도하면 이어서 합니다"
    }
    return [PSCustomObject]@{ id = $ConversationId; state = $state; message = $message; model = $cache.Model; items = $cache.Items }
}

# 번역을 시작한다(이미 하는 중이거나 끝났거나 할 수 없으면 시작하지 않고 상태만 돌려준다).
function Start-ProcessTranslation([string]$ConversationId) {
    $st = Get-ProcessTranslationState $ConversationId
    if (-not $st -or $st.state -in @("running", "done", "unavailable")) { return $st }
    $trScriptPath = Find-DelegateScript "sub\process-translate.ps1"
    if (-not $trScriptPath) {
        $st.state = "error"; $st.message = "번역 스크립트(process-translate.ps1)를 찾지 못했습니다. install.ps1 을 다시 실행해 주세요"
        return $st
    }
    $cachePath = Get-ProcessTranslationPath $ConversationId
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cachePath) | Out-Null
        # 보조 스크립트가 뜨기까지 1초쯤 걸려서, 그 사이 상태를 물으면 "안 함"으로 보이지 않게 표시 파일을 먼저 만든다
        [System.IO.File]::WriteAllText("$cachePath.running", '{"pid":0}', (New-Object System.Text.UTF8Encoding($false)))
        # 콘솔 창을 아예 만들지 않는 방식(CreateNoWindow)으로 띄운다. Start-Process -WindowStyle Hidden 은 창이 잠깐 깜빡일 수 있다.
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$trScriptPath`" -ConversationId $ConversationId -OutFile `"$cachePath`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        [void][System.Diagnostics.Process]::Start($psi)
    } catch {
        Remove-Item -LiteralPath "$cachePath.running" -Force -ErrorAction SilentlyContinue
        $st.state = "error"; $st.message = "번역을 시작하지 못했습니다: " + $_.Exception.Message
        return $st
    }
    $st.state = "running"; $st.message = ""
    return $st
}

function Get-AgyProgress([string]$ConversationId, $StartedAt, [string]$TaskId = "", [string]$QuestionSnippet = "") {
    try {
        $agyHome = if ($env:AGY_HOME) { $env:AGY_HOME } else { Join-Path $env:USERPROFILE ".gemini\antigravity-cli" }
        if (-not $ConversationId) {
            if (-not $StartedAt) { return $null }
            $convDir = Join-Path $agyHome "conversations"
            if (-not (Test-Path -LiteralPath $convDir -PathType Container)) { return $null }
            $from = $StartedAt.AddSeconds(-5); $to = $StartedAt.AddSeconds(180)
            $cands = @(Get-ChildItem -LiteralPath $convDir -Filter '*.db' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.CreationTime -ge $from -and $_.CreationTime -le $to } |
                Sort-Object CreationTime)
            if ($cands.Count -eq 0) { return $null }
            if ($cands.Count -eq 1) {
                $ConversationId = $cands[0].BaseName
            } else {
                $matchedId = ""
                foreach ($c in $cands) {
                    $candCId = $c.BaseName
                    $candTf = Join-Path $agyHome ("brain\{0}\.system_generated\logs\transcript.jsonl" -f $candCId)
                    if (Test-Path -LiteralPath $candTf) {
                        try {
                            $firstLine = [System.IO.File]::ReadLines($candTf) | Select-Object -First 1
                            if ($firstLine) {
                                if ($TaskId -and $firstLine -match [regex]::Escape($TaskId)) {
                                    $matchedId = $candCId
                                    break
                                }
                                if ($QuestionSnippet -and $firstLine.Contains($QuestionSnippet)) {
                                    $matchedId = $candCId
                                    break
                                }
                            }
                        } catch {}
                    }
                }
                if ($matchedId) {
                    $ConversationId = $matchedId
                } else {
                    $best = $cands | Sort-Object { [Math]::Abs(($_.CreationTime - $StartedAt).TotalSeconds) } | Select-Object -First 1
                    $ConversationId = $best.BaseName
                }
            }
        }
        $tf = Join-Path $agyHome ("brain\{0}\.system_generated\logs\transcript_full.jsonl" -f $ConversationId)
        $item = Get-Item -LiteralPath $tf -ErrorAction SilentlyContinue
        if (-not $item) { return $null }

        # 끝 256KB만 읽습니다(파일은 수 MB까지 커질 수 있음). 잘린 첫 줄은 버립니다.
        $tailBytes = 262144
        $fs = [System.IO.File]::Open($tf, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $offset = [Math]::Max(0, $fs.Length - $tailBytes)
            [void]$fs.Seek($offset, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] ($fs.Length - $offset)
            $read = $fs.Read($buf, 0, $buf.Length)
        } finally { $fs.Dispose() }
        $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
        $lines = @($text -split "\r?\n" | Where-Object { $_ })
        if ($offset -gt 0 -and $lines.Count -gt 0) { $lines = @($lines | Select-Object -Skip 1) }

        $step = $null; $action = ""; $thinking = ""; $say = ""; $tool = ""; $detail = ""; $cwd = ""; $background = $false; $found = $false
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $o = $null
            try { $o = $lines[$i] | ConvertFrom-Json } catch { continue }
            if ($null -eq $step -and $null -ne $o.step_index) { $step = [int]$o.step_index }
            if ($o.type -eq 'PLANNER_RESPONSE') {
                $calls = @($o.tool_calls)
                # 마지막 도구 호출은 가장 최근 응답에서 읽고, agy 의 생각은 그 응답에 없으면(생각은 응답 3개 중 1개꼴) 더 앞 응답까지 거슬러 찾는다
                if (-not $found -and $calls.Count -gt 0 -and $calls[-1].args) {
                    $a = $calls[-1].args
                    $action = [string]$a.toolAction
                    if (-not $action) { $action = [string]$a.toolSummary }
                    if (-not $action) { $action = [string]$calls[-1].name }
                    $tool = [string]$calls[-1].name
                    if (Get-Command Get-AgyToolDetail -ErrorAction SilentlyContinue) { $detail = Get-AgyToolDetail $calls[-1] }
                    if ($tool -eq 'run_command') {
                        $cwd = [string]$a.Cwd
                        $background = ([string]$a.IsDaemon -match '^(?i:true|1)$')
                    }
                }
                if (-not $found) {
                    $found = $true
                    if ($o.content -and $calls.Count -gt 0) { $say = (([string]$o.content) -replace '\s+', ' ').Trim() }
                }
                if ($o.thinking) { $thinking = (([string]$o.thinking) -replace '\s+', ' ').Trim(); break }
            }
        }
        if ($thinking.Length -gt 500) { $thinking = $thinking.Substring(0, 500) + "…" }
        if ($say.Length -gt 300) { $say = $say.Substring(0, 300) + "…" }
        $last = $item.LastWriteTime

        # 실시간 누적 토큰 집계 (transcript.jsonl 우선, 없으면 transcript_full.jsonl — 오프셋 기반 증분 읽기)
        $tInSum = [int64]0; $tOutSum = [int64]0
        $compactTf = Join-Path $agyHome ("brain\{0}\.system_generated\logs\transcript.jsonl" -f $ConversationId)
        $targetTokenFile = if (Test-Path -LiteralPath $compactTf) { $compactTf } else { $tf }
        $tItem = Get-Item -LiteralPath $targetTokenFile -ErrorAction SilentlyContinue
        if ($tItem) {
            try {
                if ($null -eq $script:TokenCache) { $script:TokenCache = @{} }
                $tc = $script:TokenCache[$ConversationId]
                if (-not $tc -or $tc.Path -ne $targetTokenFile -or $tItem.Length -lt $tc.Offset) {
                    $tc = @{ Path = $targetTokenFile; Offset = [long]0; InSum = [int64]0; OutSum = [int64]0; Touched = (Get-Date) }
                    $script:TokenCache[$ConversationId] = $tc
                    if ($script:TokenCache.Count -gt 16) {
                        $oldestT = $script:TokenCache.GetEnumerator() | Sort-Object { $_.Value.Touched } | Select-Object -First 1
                        if ($oldestT) { $script:TokenCache.Remove($oldestT.Key) }
                    }
                }
                $tc.Touched = Get-Date
                if ($tItem.Length -gt $tc.Offset) {
                    $tStream = [System.IO.File]::Open($targetTokenFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        [void]$tStream.Seek($tc.Offset, [System.IO.SeekOrigin]::Begin)
                        $lenToRead = [int]($tStream.Length - $tc.Offset)
                        if ($lenToRead -gt 0) {
                            $tBuf = New-Object byte[] $lenToRead
                            $tRead = $tStream.Read($tBuf, 0, $lenToRead)
                            $lastNl = if ($tRead -gt 0) { [Array]::LastIndexOf($tBuf, [byte]10, $tRead - 1) } else { -1 }
                            if ($lastNl -ge 0) {
                                $chunkText = [System.Text.Encoding]::UTF8.GetString($tBuf, 0, $lastNl + 1)
                                foreach ($tLine in ($chunkText -split "\r?\n")) {
                                    if (-not $tLine) { continue }
                                    if ($tLine -match '"input_tokens"\s*:\s*(\d+)') { $tc.InSum += [int64]$matches[1] }
                                    if ($tLine -match '"cache_read_tokens"\s*:\s*(\d+)') { $tc.InSum += [int64]$matches[1] }
                                    if ($tLine -match '"output_tokens"\s*:\s*(\d+)') { $tc.OutSum += [int64]$matches[1] }
                                }
                                $tc.Offset += ($lastNl + 1)
                            }
                        }
                    } finally {
                        $tStream.Dispose()
                    }
                }
                $tInSum = $tc.InSum
                $tOutSum = $tc.OutSum
            } catch {}
        }

        # 멈춤 판정에 쓸 값. 워처(watch-agy.ps1)와 같은 기준(AGY_STALL_SECONDS, 기본 300초)을 화면에도 알려 줘서, 화면이 "멈춘 것으로 보임"을 같은 잣대로 말하게 한다.
        # 오래 걸리는 명령을 백그라운드로 돌려 두고 기다리는 동안은 새 단계가 없어도 멈춘 게 아니다 - 기록 전체를 훑는 일이라 멈춤 기준에 가까워졌을 때만 확인한다.
        $stallSec = 300
        if (Get-Command Get-AgySecondsSetting -ErrorAction SilentlyContinue) { $stallSec = Get-AgySecondsSetting 'AGY_STALL_SECONDS' 300 30 }
        $waitingBg = $false
        if ((((Get-Date) - $last).TotalSeconds -ge ($stallSec - 60)) -and (Get-Command Get-AgyPendingBackgroundTasks -ErrorAction SilentlyContinue)) {
            try { $waitingBg = (@(Get-AgyPendingBackgroundTasks $agyHome $ConversationId).Count -gt 0) } catch {}
        }
        $stepList = @(Get-AgyProcessStepsCached $ConversationId)

        return [PSCustomObject]@{
            conversation_id = $ConversationId
            step            = $step
            action          = $action
            tool            = $tool
            detail          = $detail
            cwd             = $cwd
            background      = $background
            step_count      = $stepList.Count
            stall_seconds   = $stallSec
            waiting_background = $waitingBg
            steps           = $stepList
            thinking        = $thinking
            say             = $say
            tokens          = [PSCustomObject]@{
                input  = $tInSum
                output = $tOutSum
                total  = ($tInSum + $tOutSum)
            }
            last_activity   = $last.ToString("yyyy-MM-dd HH:mm:ss")
            last_activity_ms = [int64]([DateTimeOffset]$last).ToUnixTimeMilliseconds()
        }
    } catch {
        return $null
    }
}

# 워처와 같이 쓰는 도구 호출·과정 읽기 코드(agy-progress.ps1). 못 찾으면 진행 표시의 도구 설명과 과정 목록만 빠진다.
$agyProgressLib = Find-DelegateScript "sub\agy-progress.ps1"
if ($agyProgressLib) { . $agyProgressLib }
# 번역 캐시 읽기 함수(Read-TranslationCache)도 같이 쓴다. 인자 없이 불러서 함수만 정의된다.
$processTranslateLib = Find-DelegateScript "sub\process-translate.ps1"
if ($processTranslateLib) { . $processTranslateLib }
# 핸드오프 채널 공용 함수(handoff-lib.ps1): 메시지 머리말의 모델과 "자동 이어가기" 상태를 읽는다. 못 찾으면 그 정보만 빠진다.
$script:HandoffMetaCache = @{}
$handoffLibLoaded = $false
foreach ($hlCand in @((Join-Path $PSScriptRoot "..\handoff\scripts\handoff-lib.ps1"), (Join-Path $env:USERPROFILE ".samjil\handoff\scripts\handoff-lib.ps1"))) {
    if (Test-Path -LiteralPath $hlCand) { try { . $hlCand; $handoffLibLoaded = $true } catch {}; break }
}

# HTTP 리스너 기동 (충돌 시 기존 뷰어 자동 정리 및 대체 포트 탐색)
$listener = $null
$prefix = $null
$started = $false
$maxAttempts = 10

# 호출자 프로세스 보호를 위해 PPID 조회
$ppid = 0
try {
    $ppid = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue).ParentProcessId
} catch {}

for ($attempt = 0; $attempt -lt $maxAttempts; $attempt++) {
    $currentPort = $Port + $attempt
    $currentPrefix = "http://127.0.0.1:$currentPort/"
    $candidateListener = New-Object System.Net.HttpListener
    $candidateListener.Prefixes.Add($currentPrefix)

    try {
        $candidateListener.Start()
        $listener = $candidateListener
        $prefix = $currentPrefix
        $Port = $currentPort
        $started = $true
        break
    } catch {
        $candidateListener.Close()

        # 첫 번째 시도(기본 포트)에서 충돌 발생 시, 기존 좀비 뷰어 프로세스 정리 후 1회 재시도
        if ($attempt -eq 0) {
            try {
                $oldViewers = @(Get-CimInstance Win32_Process -Filter "Name like '%powershell%'" -ErrorAction SilentlyContinue | Where-Object {
                    $_.ProcessId -ne $PID -and $_.ProcessId -ne $ppid -and (
                        $_.CommandLine -match "serve-viewer\.ps1" -or
                        $_.CommandLine -match "serve-handoff\.ps1"
                    )
                })
                if ($oldViewers.Count -gt 0) {
                    Write-Host "[*] 기존에 실행 중이던 이전 뷰어 세션을 정리하고 포트를 재확보합니다..." -ForegroundColor Yellow
                    foreach ($ov in $oldViewers) {
                        Stop-Process -Id $ov.ProcessId -Force -ErrorAction SilentlyContinue
                    }
                    Start-Sleep -Milliseconds 600

                    # 동일 포트로 재시도
                    $retryListener = New-Object System.Net.HttpListener
                    $retryListener.Prefixes.Add($currentPrefix)
                    try {
                        $retryListener.Start()
                        $listener = $retryListener
                        $prefix = $currentPrefix
                        $started = $true
                        break
                    } catch {
                        $retryListener.Close()
                    }
                }
            } catch {}
        }
    }
}

if (-not $started) {
    Write-Error "HTTP 리스너 시작 실패: 포트 $Port ~ $($Port + $maxAttempts - 1) 번이 모두 사용 중이거나 권한이 없습니다."
    exit 1
}



Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  samjil 에이전트 통합 대시보드 (Unified Dashboard)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  웹 대시보드     : $prefix" -ForegroundColor Green
Write-Host "  위임 기록(/data): $DataDir" -ForegroundColor White
Write-Host "  대화 저장소     : $HandoffDir" -ForegroundColor White

# --- agy agent (워처) 자동 연동 ---
$watcherHealth = $null
if (-not $NoAgent) {
    # 하트비트만 보지 않고 PID 잠금 파일로 판단합니다(watcher-health.ps1). 명령줄에 watch-agy.ps1 이
    # 남아 있는 빈 -NoExit 창을 "실행 중"으로 오판하지 않습니다.
    $watcherRunning = [bool](Test-WatcherAlive -RuntimeDir $WatcherRuntimeDir).Alive

    $startScript  = Find-DelegateScript "start-agy.ps1"
    $ensureScript = Find-DelegateScript "sub\ensure-agy-running.ps1"

    if ($watcherRunning) {
        Write-Host "  agy agent (워처): 이미 실행 중 (정상)" -ForegroundColor Green
    } elseif ($startScript) {
        Write-Host "  agy agent (워처): 미실행 감지 -> 창 없이 자동 기동..." -ForegroundColor Yellow
        try {
            # -Hidden: 콘솔 창 없이 백그라운드로. (옵션 없이 부르면 -NoExit 콘솔 창이 뜬다. 숨김 뷰어가 이 창을 띄우면 닫을 수도 끌 수도 없다)
            & $startScript -Hidden | Out-Null
            Write-Host "  agy agent (워처): 기동 완료" -ForegroundColor Green
        } catch {
            Write-Host "  agy agent (워처): 자동 기동 실패 ($($_.Exception.Message))" -ForegroundColor Red
        }
    } else {
        Write-Host "  agy agent (워처): start-agy.ps1 스크립트를 찾을 수 없음" -ForegroundColor Gray
    }

    if ($ensureScript) {
        $watcherHealth = New-WatcherHealthState -RuntimeDir $WatcherRuntimeDir -EnsureScript $ensureScript -IntervalSeconds $WatcherCheckSeconds
        if ($WatcherCheckSeconds -gt 0) {
            Write-Host "  워처 자동 점검  : ${WatcherCheckSeconds}초마다 (꺼져 있으면 창 없이 다시 켬, stop-agy 로 끈 상태는 존중)" -ForegroundColor Green
        } else {
            Write-Host "  워처 자동 점검  : 끔 (화면의 켜기 버튼만 사용)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  워처 자동 점검  : ensure-agy-running.ps1 을 찾을 수 없어 끔 (켜기 버튼도 쓸 수 없음)" -ForegroundColor Gray
    }
}

Write-Host "  종료 방법       : 이 창에서 Ctrl+C" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host ""



if (-not $NoBrowser) {

    try { Start-Process $prefix } catch {}

}



try {

    $lastClaudeScanLaunchAt = $null
    $lastClaudeScanProc = $null
    $pendingContext = $null

    while ($listener.IsListening) {

        # 워처 주기 점검. 점검 시각이 아니면 바로 돌아옵니다(점검 자체가 예외를 내도 서버는 계속 돕니다).
        if ($watcherHealth) {
            try {
                $tickResult = Invoke-WatcherHealthTick $watcherHealth
                if ($tickResult -eq 'restart') {
                    Write-Host ("[{0}] agy 워처가 꺼져 있어 자동으로 다시 켭니다 (창 없이 실행, 20초 뒤 재확인)." -f (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Yellow
                } elseif ($tickResult -like 'launch-failed*') {
                    Write-Host ("[{0}] agy 워처 자동 재시작 실패: {1}" -f (Get-Date -Format 'HH:mm:ss'), $tickResult) -ForegroundColor Red
                }
            } catch {}
        }

        $context = $null

        try {

            # 요청이 없어도 1초마다 깨어나 위 점검을 챙깁니다(GetContext 는 요청이 올 때까지 막혀서 쓸 수 없음).
            if ($null -eq $pendingContext) { $pendingContext = $listener.GetContextAsync() }

            if (-not $pendingContext.Wait(1000)) { continue }

            $context = $pendingContext.GetAwaiter().GetResult()

            $pendingContext = $null

        } catch {

            break

        }



        $request = $context.Request

        $response = $context.Response



        try {

            $rawPath = $request.Url.AbsolutePath

            $urlPath = [System.Uri]::UnescapeDataString($rawPath)



            if ($urlPath -eq "/api/handoff/projects" -or $urlPath -eq "/api/projects") {

                $projects = @()

                $seenNames = @{}

                foreach ($hRoot in (Get-HandoffRoots)) {

                    if (-not (Test-Path $hRoot)) { continue }

                    $dirs = Get-ChildItem -LiteralPath $hRoot -Directory -ErrorAction SilentlyContinue

                    foreach ($d in $dirs) {

                        if ($d.Name -eq "templates" -or $d.Name -eq "viewer" -or $d.Name -eq "scripts" -or $seenNames.ContainsKey($d.Name)) { continue }

                        $seenNames[$d.Name] = $true

                        $briefPath = Join-Path $d.FullName "BRIEF.md"

                        $indexPath = Join-Path $d.FullName "INDEX.md"

                        $msgDir = Join-Path $d.FullName "msg"

                        $msgCount = 0

                        if (Test-Path $msgDir) {

                            $msgFiles = Get-ChildItem -LiteralPath $msgDir -Filter "*.md" -File -ErrorAction SilentlyContinue

                            $msgCount = if ($msgFiles) { @($msgFiles).Count } else { 0 }

                        }

                        $candidates = @($d.LastWriteTime)
                        if (Test-Path $indexPath) {
                            $idxItem = Get-Item -LiteralPath $indexPath -ErrorAction SilentlyContinue
                            if ($idxItem) { $candidates += $idxItem.LastWriteTime }
                        }
                        if ($msgFiles -and $msgFiles.Count -gt 0) {
                            $latestMsgFile = $msgFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                            if ($latestMsgFile) { $candidates += $latestMsgFile.LastWriteTime }
                        }
                        $maxTime = ($candidates | Sort-Object -Descending | Select-Object -First 1)
                        $lastUpdated = $maxTime.ToString("yyyy-MM-dd HH:mm:ss")

                        $latestMsg = $null

                        if (Test-Path $indexPath) {

                            $idxContent = Get-Content -LiteralPath $indexPath -Encoding UTF8 -ErrorAction SilentlyContinue

                            if ($idxContent) {

                                $tableLines = $idxContent | Where-Object { $_ -match '^\s*\|\s*\d{4}\s*\|' }

                                if ($tableLines) {

                                    $lastLine = @($tableLines)[-1]

                                    $parts = $lastLine.Split('|') | ForEach-Object { $_.Trim() }

                                    if ($parts.Length -ge 6) {

                                        $latestMsg = [PSCustomObject]@{

                                            num    = $parts[1]

                                            time   = $parts[2]

                                            dir    = $parts[3]

                                            title  = $parts[4]

                                            status = $parts[5]

                                        }

                                    }

                                }

                            }

                        }

                        $projects += [PSCustomObject]@{

                            name      = $d.Name

                            hasBrief  = (Test-Path $briefPath)

                            hasIndex  = (Test-Path $indexPath)

                            msgCount  = $msgCount

                            updated   = $lastUpdated

                            latestMsg = $latestMsg

                        }

                    }

                }

                $arr = @($projects | Sort-Object { $_.updated } -Descending)

                if ($arr.Count -eq 0) {

                    $json = "[]"

                } elseif ($arr.Count -eq 1) {

                    $json = "[" + ($arr[0] | ConvertTo-Json -Depth 5) + "]"

                } else {

                    $json = $arr | ConvertTo-Json -Depth 5

                }

                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

                $response.ContentType = "application/json; charset=utf-8"

                $response.ContentLength64 = $bytes.Length

                $response.Headers.Add("Cache-Control", "no-store")

                $response.OutputStream.Write($bytes, 0, $bytes.Length)



            } elseif ($urlPath -eq "/api/handoff/project" -or $urlPath -eq "/api/project") {

                $params = Get-Utf8QueryParams $request.Url

                $pName = $params["name"]

                if ([string]::IsNullOrWhiteSpace($pName) -or $pName.Contains("..") -or $pName.Contains("/") -or $pName.Contains("\")) {

                    $response.StatusCode = 400

                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid project name")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $bytes.Length

                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                } else {

                    $pDir = Find-HandoffProjectDir $pName

                    if (-not $pDir) {

                        $response.StatusCode = 404

                        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Project not found")

                        $response.ContentType = "text/plain; charset=utf-8"

                        $response.ContentLength64 = $bytes.Length

                        $response.OutputStream.Write($bytes, 0, $bytes.Length)

                    } else {

                        $briefPath = Join-Path $pDir "BRIEF.md"

                        $briefText = if (Test-Path $briefPath) { [System.IO.File]::ReadAllText($briefPath, [System.Text.Encoding]::UTF8) } else { "" }

                        

                        $msgDir = Join-Path $pDir "msg"
                        $fileList = @()
                        $msgFilesByNum = @{}
                        if (Test-Path $msgDir) {
                            $files = Get-ChildItem -LiteralPath $msgDir -Filter "*.md" -File | Sort-Object Name
                            foreach ($f in $files) {
                                $fileList += $f.Name
                                if ($f.Name -match '^(\d{4})-(.*)\.md$') {
                                    $msgFilesByNum[$Matches[1]] = $f
                                }
                            }
                        }

                        $indexPath = Join-Path $pDir "INDEX.md"
                        $indexLines = if (Test-Path $indexPath) { Get-Content -LiteralPath $indexPath -Encoding UTF8 } else { @() }
                        $parsedMessages = @()
                        foreach ($line in $indexLines) {
                            if ($line -match '^\s*\|\s*(\d{4})\s*\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|') {
                                $mNum = $Matches[1].Trim()
                                $mTime = $Matches[2].Trim()
                                $mDir = $Matches[3].Trim()
                                $mTitle = $Matches[4].Trim()
                                $mStatus = $Matches[5].Trim()

                                # 누락된 필드가 있는 경우 실제 메시지 파일에서 자동 복구
                                if ((-not $mTitle -or -not $mDir) -and $msgFilesByNum.ContainsKey($mNum)) {
                                    $mf = $msgFilesByNum[$mNum]
                                    if (-not $mDir) {
                                        if ($mf.Name -match '-(a2c|c2a)-') { $mDir = $Matches[1] }
                                    }
                                    if (-not $mTitle) {
                                        try {
                                            $firstLines = Get-Content -LiteralPath $mf.FullName -TotalCount 10 -Encoding UTF8
                                            foreach ($fl in $firstLines) {
                                                if ($fl -match '^#\s+(.+)$') {
                                                    $mTitle = $Matches[1].Trim()
                                                    break
                                                }
                                            }
                                        } catch {}
                                        if (-not $mTitle -and $mf.Name -match '^\d{4}-[a-z0-9]+-(.*)\.md$') {
                                            $mTitle = $Matches[1].Replace('-', ' ')
                                        }
                                    }
                                    if (-not $mTime) {
                                        $mTime = $mf.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                                    }
                                }

                                # 메시지 머리말의 모델·답장대상·자동(없으면 빈 값). 파일이 안 바뀌면 캐시를 쓴다.
                                $mMeta = @{ model = ""; replyTo = ""; auto = $false }
                                if ($handoffLibLoaded -and $msgFilesByNum.ContainsKey($mNum)) {
                                    try { $mMeta = Get-HandoffMessageMeta $msgFilesByNum[$mNum].FullName $script:HandoffMetaCache } catch {}
                                }
                                # 메시지 파일이 만들어진 시각(UTC, 초 단위). Claude 가 보낸 c2a 가 어느 Claude 호출에서 나왔는지 짐작하는 데 쓴다(수정해도 만든 시각은 그대로).
                                $mCreated = ""
                                if ($msgFilesByNum.ContainsKey($mNum)) { try { $mCreated = $msgFilesByNum[$mNum].CreationTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ") } catch {} }
                                $parsedMessages += [PSCustomObject]@{
                                    num     = $mNum
                                    time    = $mTime
                                    dir     = $mDir
                                    title   = $mTitle
                                    status  = if ($mStatus) { $mStatus } else { "처리됨" }
                                    model   = [string]$mMeta.model
                                    replyTo = [string]$mMeta.replyTo
                                    auto    = [bool]$mMeta.auto
                                    created = $mCreated
                                }
                            }
                        }



                        $autoSummary = $null
                        if ($handoffLibLoaded) { try { $autoSummary = Get-HandoffAutoSummary $pDir } catch {} }
                        $resObj = [PSCustomObject]@{
                            name     = $pName
                            brief    = $briefText
                            messages = $parsedMessages
                            files    = $fileList
                            auto     = $autoSummary
                        }

                        $json = $resObj | ConvertTo-Json -Depth 5

                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

                        $response.ContentType = "application/json; charset=utf-8"

                        $response.ContentLength64 = $bytes.Length

                        $response.Headers.Add("Cache-Control", "no-store")

                        $response.OutputStream.Write($bytes, 0, $bytes.Length)

                    }

                }

            } elseif ($urlPath -eq "/api/handoff/message" -or $urlPath -eq "/api/message") {

                $params = Get-Utf8QueryParams $request.Url

                $pName = $params["project"]

                $fName = $params["file"]

                if ([string]::IsNullOrWhiteSpace($pName) -or [string]::IsNullOrWhiteSpace($fName) -or

                    $pName.Contains("..") -or $pName.Contains("/") -or $pName.Contains("\") -or

                    $fName.Contains("..") -or $fName.Contains("/") -or $fName.Contains("\")) {

                    $response.StatusCode = 400

                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid project or file name")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $bytes.Length

                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                } else {

                    $pDir = Find-HandoffProjectDir $pName

                    $msgFilePath = if ($pDir) { Join-Path $pDir "msg\$fName" } else { $null }

                    if (-not $msgFilePath -or -not (Test-Path -LiteralPath $msgFilePath -PathType Leaf)) {

                        $response.StatusCode = 404

                        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Message file not found: $fName")

                        $response.ContentType = "text/plain; charset=utf-8"

                        $response.ContentLength64 = $bytes.Length

                        $response.OutputStream.Write($bytes, 0, $bytes.Length)

                    } else {

                        $bytes = [System.IO.File]::ReadAllBytes($msgFilePath)

                        $response.ContentType = "text/plain; charset=utf-8"

                        $response.ContentLength64 = $bytes.Length

                        $response.Headers.Add("Cache-Control", "no-store")

                        $response.OutputStream.Write($bytes, 0, $bytes.Length)

                    }

                }

            } elseif ($urlPath -eq "/api/handoff/auto") {
                # 채널의 자동 이어가기 상태(GET)와 켜기·끄기·한도 초기화(POST ?action=on|off|reset).
                # 채널 파일(AUTO.off, AUTO.json)을 바꾸는 동작이라 워처 켜기와 같이 POST + 전용 헤더만 받는다.
                $params = Get-Utf8QueryParams $request.Url
                $aName = [string]$params["name"]
                $aAct = [string]$params["action"]
                $aCode = 200
                $aPayload = $null
                $aMsg = ""
                if (-not $handoffLibLoaded) {
                    $aCode = 503; $aMsg = "handoff-lib.ps1 not found"
                } elseif ([string]::IsNullOrWhiteSpace($aName) -or $aName.Contains("..") -or $aName.Contains("/") -or $aName.Contains("\")) {
                    $aCode = 400; $aMsg = "Invalid project name"
                } elseif ($request.HttpMethod -ne "GET" -and $request.HttpMethod -ne "POST") {
                    $aCode = 405; $aMsg = "Method Not Allowed"
                    $response.Headers.Add("Allow", "GET, POST")
                } elseif ($request.HttpMethod -eq "POST" -and $request.Headers["X-Samjil-Viewer"] -ne "1") {
                    $aCode = 403; $aMsg = "Forbidden"
                } else {
                    $aDir = Find-HandoffProjectDir $aName
                    if (-not $aDir) {
                        $aCode = 404; $aMsg = "Project not found"
                    } elseif ($request.HttpMethod -eq "POST" -and -not (Set-HandoffAutoAction $aDir $aAct)) {
                        $aCode = 400; $aMsg = "Invalid action"
                    } else {
                        if ($request.HttpMethod -eq "POST") {
                            Write-Host ("[{0}] 핸드오프 자동 이어가기 {1}: {2}" -f (Get-Date -Format 'HH:mm:ss'), $aAct, $aName) -ForegroundColor Yellow
                        }
                        $aPayload = Get-HandoffAutoSummary $aDir
                    }
                }
                $response.StatusCode = $aCode
                if ($aPayload) {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($aPayload | ConvertTo-Json -Depth 5))
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                } else {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($aMsg)
                    $response.ContentType = "text/plain; charset=utf-8"
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } elseif ($urlPath -eq "/api/delegate/pending") {

                $runtimeDir = Split-Path (Split-Path $DataDir -Parent) -Parent
                $inboxDir = Join-Path $runtimeDir "inbox"

                $watcherAlive = [bool](Test-WatcherAlive -RuntimeDir $WatcherRuntimeDir).Alive

                $currentTaskFile = Join-Path $runtimeDir "logs\current_task.json"
                $sessionsDir = Join-Path $runtimeDir "logs\sessions"
                $currentTask = $null
                if (Test-Path -LiteralPath $currentTaskFile) {
                    try {
                        $currentTask = Get-Content -LiteralPath $currentTaskFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    } catch {}
                }

                # 작업마다 있는 표시 파일(logs\running\<작업 ID>.json): 동시에 도는 작업 각각의 작업자 PID·모델·시작 시각·대화 ID.
                # 이 폴더가 아예 없으면 옛 워처(한 번에 하나만 처리)라서 예전 규칙(맨 앞 작업이 처리 중)을 쓴다.
                $runningDir = Join-Path $runtimeDir "logs\running"
                $legacyQueue = -not (Test-Path -LiteralPath $runningDir -PathType Container)

                $pendingList = @()
                if (Test-Path -LiteralPath $inboxDir -PathType Container) {
                    $inboxFiles = @(Get-ChildItem -LiteralPath $inboxDir -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Extension -match '^\.(md|txt)$' } |
                        Sort-Object CreationTime)

                    foreach ($f in $inboxFiles) {
                        try {
                            $rawText = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
                            if ($rawText.Length -gt 0 -and $rawText[0] -eq [char]0xFEFF) {
                                $rawText = $rawText.Substring(1)
                            }
                            $lines = $rawText -split "\r?\n"
                            $cwdLines = New-Object System.Collections.ArrayList
                            $sessionVal = ""
                            $modelVal = ""
                            $bodyStartIdx = $lines.Length
                            for ($i = 0; $i -lt $lines.Length; $i++) {
                                $trimmed = $lines[$i].Trim()
                                if ([string]::IsNullOrWhiteSpace($trimmed)) {
                                    continue
                                }
                                if ($trimmed -match '^@cwd:\s*(.*)$') {
                                    [void]$cwdLines.Add($Matches[1].Trim())
                                    continue
                                }
                                if ($trimmed -match '^@session:\s*(.*)$') {
                                    $sessionVal = $Matches[1].Trim()
                                    continue
                                }
                                if ($trimmed -match '^@model:\s*(.*)$') {
                                    $modelVal = $Matches[1].Trim()
                                    continue
                                }
                                $bodyStartIdx = $i
                                break
                            }
                            $question = if ($bodyStartIdx -lt $lines.Length) {
                                ($lines[$bodyStartIdx..($lines.Length - 1)] -join "`r`n").Trim()
                            } else {
                                ""
                            }
                            $claim = $null
                            $claimAlive = $false
                            if (-not $legacyQueue) {
                                $claimFile = Join-Path $runningDir ("{0}.json" -f $f.BaseName)
                                if (Test-Path -LiteralPath $claimFile) {
                                    try { $claim = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($claimFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)) } catch {}
                                }
                                if ($claim -and [int]$claim.pid -gt 0) {
                                    $cp = Get-Process -Id ([int]$claim.pid) -ErrorAction SilentlyContinue
                                    $claimAlive = [bool]($cp -and $cp.ProcessName -eq "powershell")
                                }
                            }
                            if ($legacyQueue) {
                                $state = if ($watcherAlive -and $pendingList.Count -eq 0) { "processing" } else { "queued" }
                            } else {
                                $state = if ($claimAlive) { "processing" } else { "queued" }
                            }

                            # 모델 및 세션 ID 해석
                            $resolvedModel = ""
                            $sessionId = ""
                            if ($claimAlive -and $claim.model) {
                                $resolvedModel = [string]$claim.model
                            } elseif ($legacyQueue -and $currentTask -and $currentTask.task_id -eq $f.BaseName -and $currentTask.model) {
                                $resolvedModel = [string]$currentTask.model
                            }
                            if (-not $resolvedModel -and $sessionVal) {
                                $safeSessionName = ($sessionVal -replace '[\\/:*?"<>|]', '_').Trim()
                                $sFile = Join-Path $sessionsDir ("{0}.json" -f $safeSessionName)
                                if (Test-Path -LiteralPath $sFile) {
                                    try {
                                        $sObj = Get-Content -LiteralPath $sFile -Raw -Encoding UTF8 | ConvertFrom-Json
                                        if ($sObj.model) { $resolvedModel = [string]$sObj.model }
                                        if ($sObj.conversation_id) { $sessionId = [string]$sObj.conversation_id }
                                    } catch {}
                                }
                            }
                            if (-not $resolvedModel -and $modelVal) {
                                $resolvedModel = $modelVal
                            }
                            if (-not $resolvedModel) {
                                $resolvedModel = "gemini-3.8-flash-high"
                            }

                            # 진행 중인 작업이면 agy 대화 기록에서 현재 단계/최근 동작을 읽어 붙입니다.
                            # 실행 표시 파일은 있는데 그 작업자 프로세스가 사라졌으면 "중단된 것으로 보이는" 작업이다(워처가 죽었거나 작업자가 비정상 종료).
                            # 대기 중과 구별해 화면이 "대기 중"이라고 거짓말하지 않게 하고, 마지막 진행 상황도 같이 읽어 준다.
                            $interrupted = [bool](-not $legacyQueue -and $claim -and [int]$claim.pid -gt 0 -and -not $claimAlive -and $claim.started_at)
                            $claimUsable = [bool]($claim -and $claim.started_at -and ($claimAlive -or $interrupted))
                            $progress = $null
                            $startedText = ""
                            if (($state -eq "processing" -or $interrupted) -and (($claimUsable) -or ($legacyQueue -and $currentTask -and $currentTask.task_id -eq $f.BaseName))) {
                                $convId = ""
                                if ($claimUsable -and $claim.conversation_id) { $convId = [string]$claim.conversation_id }
                                if (-not $convId -and $sessionVal) {
                                    $sFile2 = Join-Path $sessionsDir ("{0}.json" -f (($sessionVal -replace '[\\/:*?"<>|]', '_').Trim()))
                                    if (Test-Path -LiteralPath $sFile2) {
                                        try { $convId = [string]((Get-Content -LiteralPath $sFile2 -Raw -Encoding UTF8 | ConvertFrom-Json).conversation_id) } catch {}
                                    }
                                }
                                $startedAt = $null
                                $startedText = ""
                                if ($claimUsable) { $startedText = [string]$claim.started_at } elseif ($currentTask) { $startedText = [string]$currentTask.started_at }
                                try { $startedAt = [datetime]::ParseExact($startedText, "yyyy-MM-dd HH:mm:ss", $null) } catch {}
                                $qSnippet = if ($question.Length -gt 40) { $question.Substring(0, 40) } else { $question }
                                $progress = Get-AgyProgress $convId $startedAt $f.BaseName $qSnippet
                            }

                            # 5초마다 불리는 목록에 단계 전체(최대 400개)를 싣지 않는다. 개수만 알려 주고, 단계는 /api/delegate/process?since= 로 새 것만 받아 간다.
                            $liveConvId = ""
                            if ($progress) {
                                $liveConvId = [string]$progress.conversation_id
                                $progress.PSObject.Properties.Remove('steps')
                            }

                            $pendingList += [PSCustomObject]@{
                                task_id    = $f.BaseName
                                created    = $f.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                                started_at = $(if (($state -eq "processing" -or $interrupted) -and $startedText) { $startedText } else { "" })
                                conversation_id = $liveConvId
                                interrupted = $interrupted
                                question   = $question
                                cwd        = @(ConvertTo-CwdList $cwdLines.ToArray())
                                session    = $sessionVal
                                session_id = $sessionId
                                model      = $resolvedModel
                                state      = $state
                                progress   = $progress
                            }
                        } catch {
                            continue
                        }
                    }
                }

                $json = if ($pendingList.Count -eq 0) {
                    "[]"
                } elseif ($pendingList.Count -eq 1) {
                    "[" + ($pendingList[0] | ConvertTo-Json -Depth 5) + "]"
                } else {
                    $pendingList | ConvertTo-Json -Depth 5
                }

                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.Headers.Add("Cache-Control", "no-store")
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/status" -or $urlPath -eq "/api/system/status") {

                $runtimeDir = Split-Path (Split-Path $DataDir -Parent) -Parent
                $heartbeatDir = Join-Path $runtimeDir "logs\heartbeat"
                $inboxDir = Join-Path $runtimeDir "inbox"

                # 켜짐/꺼짐은 하트비트가 아니라 PID 잠금 파일로 판단합니다(agy 를 기다리는 동안은 하트비트가 낡음).
                $aliveInfo = Test-WatcherAlive -RuntimeDir $WatcherRuntimeDir
                $watcherAlive = [bool]$aliveInfo.Alive
                $lastHeartbeat = ""
                if (Test-Path -LiteralPath $heartbeatDir -PathType Container) {
                    $latestHb = Get-ChildItem -LiteralPath $heartbeatDir -Filter "hb_*.txt" -File -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($latestHb) {
                        $lastHeartbeat = $latestHb.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                }

                $inboxCount = 0
                if (Test-Path -LiteralPath $inboxDir -PathType Container) {
                    $inboxFiles = @(Get-ChildItem -LiteralPath $inboxDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(md|txt)$' })
                    $inboxCount = $inboxFiles.Count
                }

                $autoRestart = [PSCustomObject]@{
                    enabled         = [bool]($watcherHealth -and $watcherHealth.IntervalSeconds -gt 0)
                    intervalSeconds = if ($watcherHealth) { [int]$watcherHealth.IntervalSeconds } else { 0 }
                    lastLaunch      = if ($watcherHealth -and $watcherHealth.LastLaunchAt) { $watcherHealth.LastLaunchAt.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
                    launchCount     = if ($watcherHealth) { [int]$watcherHealth.LaunchCount } else { 0 }
                    lastResult      = if ($watcherHealth) { [string]$watcherHealth.LastResult } else { "" }
                }

                $statusObj = [PSCustomObject]@{
                    port          = $Port
                    watcherAlive  = $watcherAlive
                    watcherSource = [string]$aliveInfo.Source
                    manualStop    = (Test-WatcherManualStop $WatcherRuntimeDir)
                    canStart      = [bool]$watcherHealth
                    autoRestart   = $autoRestart
                    lastHeartbeat = $lastHeartbeat
                    inboxCount    = $inboxCount
                    dataDir       = $DataDir
                    handoffDir    = $HandoffDir
                }
                $json = $statusObj | ConvertTo-Json -Depth 5
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.Headers.Add("Cache-Control", "no-store")
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/watcher/start") {

                # 워처를 켜는 동작이라 POST + 전용 헤더만 받습니다. 다른 웹 페이지가 이 주소로 보내는
                # 단순 요청(전용 헤더를 붙일 수 없음)은 거절됩니다.
                if ($request.HttpMethod -ne "POST") {
                    $response.StatusCode = 405
                    $response.Headers.Add("Allow", "POST")
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Method Not Allowed")
                } elseif ($request.Headers["X-Samjil-Viewer"] -ne "1") {
                    $response.StatusCode = 403
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Forbidden")
                } else {
                    $startRes = Invoke-WatcherStartRequest $watcherHealth
                    Write-Host ("[{0}] 화면에서 워처 켜기 요청: {1}" -f (Get-Date -Format 'HH:mm:ss'), $startRes.Result) -ForegroundColor Yellow
                    $json = ([PSCustomObject]@{ result = $startRes.Result; message = $startRes.Message }) | ConvertTo-Json -Depth 3
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/handoff/claude-usage") {
                # c2a 메시지 카드의 Claude 쪽 토큰: 세션(session)의 기록에서 각 시각(ts, 쉼표로 여럿) 바로 앞에 끝난 Claude 호출의 사용량.
                # 근사치다(claude-usage.ps1 머리말). 읽기만 하고, 세션 ID 는 영문자·숫자·- 만 받는다.
                $params = Get-Utf8QueryParams $request.Url
                $cuSid = [string]$params["session"]
                if ($cuSid -notmatch '^[A-Za-z0-9-]{8,64}$' -or -not (Get-Command Find-ClaudeCallBefore -ErrorAction SilentlyContinue)) {
                    $response.StatusCode = 400
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid session")
                    $response.ContentType = "text/plain; charset=utf-8"
                } else {
                    $cuPath = Get-ClaudeTranscriptPath $cuSid
                    $cuItems = [ordered]@{}
                    if ($cuPath) {
                        $cuCalls = Get-ClaudeUsageCalls $cuPath
                        foreach ($cuTs in @(([string]$params["ts"]) -split ',' | Where-Object { $_ } | Select-Object -First 200)) {
                            $cuAt = [datetime]::MinValue
                            if ([datetime]::TryParse($cuTs, [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal), [ref]$cuAt)) {
                                $cuItems[$cuTs] = Find-ClaudeCallBefore $cuCalls $cuAt
                            } else { $cuItems[$cuTs] = $null }
                        }
                    }
                    $json = ([PSCustomObject]@{ session = $cuSid; found = [bool]$cuPath; items = $cuItems }) | ConvertTo-Json -Depth 5
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } elseif ($urlPath -eq "/api/delegate/process") {

                # 기록에 과정이 저장되지 않은 옛 위임용: agy 의 대화 id 로 대화 기록에서 도구 호출 목록을 읽어 온다.
                # id 는 영문자·숫자·- 만 받는다(경로 문자 차단은 Get-AgyTranscriptPath 가 한다).
                # since=<마지막으로 받은 단계 번호> 를 주면 그 뒤의 새 단계만 돌려준다(진행 중인 작업을 몇 초마다 따라갈 때). 없으면 전부.
                # 대화마다 읽은 위치를 기억하는 캐시(Get-AgyProcessStepsCached)를 거치므로 기록 파일이 안 바뀌었으면 파일을 다시 파싱하지 않는다.
                $params = Get-Utf8QueryParams $request.Url
                $cid = [string]$params["id"]
                $sinceN = -1
                if ($params["since"] -match '^-?\d{1,9}$') { $sinceN = [int]$params["since"] }
                $tp = $null
                if (Get-Command Get-AgyTranscriptPath -ErrorAction SilentlyContinue) { $tp = Get-AgyTranscriptPath (Get-AgyHomeDir) $cid }
                if (-not $tp) {
                    $response.StatusCode = 400
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid id")
                    $response.ContentType = "text/plain; charset=utf-8"
                } else {
                    $found = Test-Path -LiteralPath $tp -PathType Leaf
                    $stepsOut = @()
                    $total = 0
                    $lastMs = 0
                    if ($found) {
                        $all = @(Get-AgyProcessStepsCached $cid)
                        $total = $all.Count
                        $maxN = -1
                        foreach ($s in $all) { if ([int]$s.n -gt $maxN) { $maxN = [int]$s.n } }
                        # 받아 간 번호가 지금 기록의 마지막보다 크면(기록이 새로 만들어짐) 처음부터 다시 준다 - reset 으로 알린다
                        $reset = ($sinceN -gt $maxN -and $maxN -ge 0)
                        $stepsOut = @(if ($sinceN -ge 0 -and -not $reset) { $all | Where-Object { [int]$_.n -gt $sinceN } } else { $all })
                        $lastMs = [int64]([DateTimeOffset](Get-Item -LiteralPath $tp).LastWriteTime).ToUnixTimeMilliseconds()
                    } else { $reset = $false }
                    $json = ([PSCustomObject]@{ id = $cid; found = $found; steps = $stepsOut; total = $total; reset = [bool]$reset; last_activity_ms = $lastMs }) | ConvertTo-Json -Depth 5
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/delegate/translate") {

                # 과정 창의 "한글로 번역". GET 은 상태와 번역해 둔 것을 읽고, POST 는 번역을 시작한다.
                # 시작은 agy 를 부르는 동작이라 워처 켜기와 같이 POST + 전용 헤더만 받는다.
                $params = Get-Utf8QueryParams $request.Url
                $cid = [string]$params["id"]
                if ($request.HttpMethod -eq "POST" -and $request.Headers["X-Samjil-Viewer"] -ne "1") {
                    $response.StatusCode = 403
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Forbidden")
                    $response.ContentType = "text/plain; charset=utf-8"
                } elseif ($request.HttpMethod -ne "POST" -and $request.HttpMethod -ne "GET") {
                    $response.StatusCode = 405
                    $response.Headers.Add("Allow", "GET, POST")
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Method Not Allowed")
                    $response.ContentType = "text/plain; charset=utf-8"
                } else {
                    $trState = if ($request.HttpMethod -eq "POST") { Start-ProcessTranslation $cid } else { Get-ProcessTranslationState $cid }
                    if (-not $trState) {
                        $response.StatusCode = 400
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid id")
                        $response.ContentType = "text/plain; charset=utf-8"
                    } else {
                        if ($request.HttpMethod -eq "POST") {
                            Write-Host ("[{0}] 과정 번역 요청: {1} -> {2}" -f (Get-Date -Format 'HH:mm:ss'), $cid, $trState.state) -ForegroundColor Yellow
                        }
                        $json = $trState | ConvertTo-Json -Depth 6
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                        $response.ContentType = "application/json; charset=utf-8"
                        $response.Headers.Add("Cache-Control", "no-store")
                    }
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/image") {

                $params = Get-Utf8QueryParams $request.Url

                $imgParam = $params["path"]

                $cwdParam = $params["cwd"]

                $targetPath = $null

                if (-not [string]::IsNullOrWhiteSpace($imgParam)) {

                    $targetPath = $imgParam.Trim()

                    if (-not [System.IO.Path]::IsPathRooted($targetPath) -and -not [string]::IsNullOrWhiteSpace($cwdParam)) {

                        $targetPath = Join-Path $cwdParam.Trim() $targetPath

                    }

                }



                $fullPath = $null

                try {

                    if ($targetPath) { $fullPath = [System.IO.Path]::GetFullPath($targetPath) }

                } catch { $fullPath = $null }



                $ext = if ($fullPath) { [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant() } else { "" }

                $allowedImageExts = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".ico")



                if (-not $fullPath -or -not ($allowedImageExts -contains $ext) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {

                    $response.StatusCode = 404

                    $body = [System.Text.Encoding]::UTF8.GetBytes("404 Image Not Found")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $body.Length

                    $response.OutputStream.Write($body, 0, $body.Length)

                } else {

                    $bytes = [System.IO.File]::ReadAllBytes($fullPath)

                    $response.ContentType = Get-ContentType $fullPath

                    $response.ContentLength64 = $bytes.Length

                    $response.Headers.Add("Cache-Control", "public, max-age=3600")

                    $response.Headers.Add("Content-Disposition", "inline")

                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                }

            } elseif ($urlPath -eq "/api/claude/tree") {

                try {
                    $indexFile = Join-Path $DataDir "claude-links.json"
                    $runningFile = "$indexFile.running"
                    $errorFile = "$indexFile.error"

                    $isScanning = $false

                    if (Test-Path -LiteralPath $runningFile) {
                        $runningRaw = $null
                        try {
                            $runningRaw = [System.IO.File]::ReadAllText($runningFile, [System.Text.Encoding]::UTF8)
                        } catch {}

                        $runningJson = $null
                        if ($runningRaw) {
                            try { $runningJson = ConvertFrom-Json -InputObject $runningRaw } catch {}
                        }

                        $rPid = 0
                        if ($runningJson -and $runningJson.pid) {
                            [int]::TryParse([string]$runningJson.pid, [ref]$rPid) | Out-Null
                        }

                        $rItem = Get-Item -LiteralPath $runningFile -ErrorAction SilentlyContinue
                        $isStale = $false

                        if (-not $rItem) {
                            $isStale = $true
                        } else {
                            $ageSec = ((Get-Date) - $rItem.LastWriteTime).TotalSeconds
                            if ($ageSec -ge 600) {
                                $isStale = $true
                            } elseif ($rPid -gt 0) {
                                $proc = Get-Process -Id $rPid -ErrorAction SilentlyContinue
                                if (-not $proc -or $proc.HasExited) {
                                    $isStale = $true
                                }
                            } else {
                                $isStale = $true
                            }
                        }

                        if ($isStale) {
                            Remove-Item -LiteralPath $runningFile -Force -ErrorAction SilentlyContinue
                            $isScanning = $false
                        } else {
                            $isScanning = $true
                        }
                    }

                    if (-not $isScanning -and $lastClaudeScanProc) {
                        try {
                            if (-not $lastClaudeScanProc.HasExited) {
                                $isScanning = $true
                            }
                        } catch {}
                    }

                    $recentlyLaunched = ($lastClaudeScanLaunchAt -and (((Get-Date) - $lastClaudeScanLaunchAt).TotalSeconds -lt 5))

                    $indexExists = Test-Path -LiteralPath $indexFile
                    $indexStale = $false
                    if ($indexExists) {
                        $indexItem = Get-Item -LiteralPath $indexFile -ErrorAction SilentlyContinue
                        if ($indexItem -and (((Get-Date) - $indexItem.LastWriteTime).TotalSeconds -gt 15)) {
                            $indexStale = $true
                        }
                    }

                    $needScan = (-not $indexExists) -or $indexStale

                    if ($needScan -and (-not $isScanning) -and (-not $recentlyLaunched)) {
                        $scannerScript = Join-Path $PSScriptRoot "scan-claude-links.ps1"
                        if (Test-Path -LiteralPath $scannerScript) {
                            $lastClaudeScanLaunchAt = Get-Date
                            $isScanning = $true
                            try {
                                $psi = New-Object System.Diagnostics.ProcessStartInfo
                                $psi.FileName = "powershell.exe"
                                $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scannerScript`" -IndexFile `"$indexFile`""
                                $psi.UseShellExecute = $false
                                $psi.CreateNoWindow = $true
                                $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                                $lastClaudeScanProc = [System.Diagnostics.Process]::Start($psi)
                            } catch {
                                $isScanning = $false
                            }
                        }
                    }

                    $tree = $null
                    if (Get-Command Get-ClaudeSessionTree -ErrorAction SilentlyContinue) {
                        try {
                            $tree = Get-ClaudeSessionTree
                        } catch {}
                    }

                    $available = if ($tree -and $tree.Available) { [bool]$tree.Available } else { $false }

                    $projectsList = @()
                    if ($tree -and $tree.Projects) {
                        foreach ($p in $tree.Projects) {
                            $sessList = @()
                            if ($p.sessions) {
                                foreach ($s in $p.sessions) {
                                    $sessList += $s
                                }
                            }
                            $projectsList += [ordered]@{
                                id       = [string]$p.id
                                name     = [string]$p.name
                                sessions = @($sessList)
                            }
                        }
                    }

                    $ungroupedList = @()
                    if ($tree -and $tree.Ungrouped) {
                        foreach ($s in $tree.Ungrouped) {
                            $ungroupedList += $s
                        }
                    }

                    $scanError = ""
                    if (Test-Path -LiteralPath $errorFile) {
                        try {
                            $scanError = [System.IO.File]::ReadAllText($errorFile, [System.Text.Encoding]::UTF8).Trim()
                        } catch {}
                    }

                    $linkInfo = $null
                    if (Get-Command Read-ClaudeLinkIndex -ErrorAction SilentlyContinue) {
                        try {
                            $linkInfo = Read-ClaudeLinkIndex -IndexFile $indexFile
                        } catch {}
                    }

                    $taskLinks = if ($linkInfo -and $linkInfo.Tasks) { $linkInfo.Tasks } else { @{} }
                    $handoffLinks = if ($linkInfo -and $linkInfo.Msgs) { $linkInfo.Msgs } else { @{} }
                    $updated = if ($linkInfo -and $linkInfo.Updated) { [string]$linkInfo.Updated } else { "" }

                    $outObj = [ordered]@{
                        available    = $available
                        scanning     = $isScanning
                        scanError    = $scanError
                        updated      = $updated
                        projects     = @($projectsList)
                        ungrouped    = @($ungroupedList)
                        taskLinks    = $taskLinks
                        handoffLinks = $handoffLinks
                    }

                    $json = ConvertTo-Json -InputObject $outObj -Depth 6
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentLength64 = $bytes.Length
                    $response.Headers.Add("Cache-Control", "no-store")
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                } catch {
                    $errObj = [ordered]@{
                        available    = $false
                        scanning     = $false
                        scanError    = [string]$_.Exception.Message
                        updated      = ""
                        projects     = @()
                        ungrouped    = @()
                        taskLinks    = @{}
                        handoffLinks = @{}
                    }
                    $json = ConvertTo-Json -InputObject $errObj -Depth 6
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentLength64 = $bytes.Length
                    $response.Headers.Add("Cache-Control", "no-store")
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                }

            } else {

                $filePath = Resolve-SafePath $urlPath



                if (-not $filePath -or -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {

                    if (-not $urlPath.StartsWith("/data/") -and -not [System.IO.Path]::HasExtension($urlPath)) {

                        $filePath = Join-Path $RouteMap["/"] "index.html"

                    }

                }



                if (-not $filePath -or -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {

                    $response.StatusCode = 404

                    $body = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $urlPath")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $body.Length

                    $response.OutputStream.Write($body, 0, $body.Length)

                } else {

                    $bytes = [System.IO.File]::ReadAllBytes($filePath)

                    $response.ContentType = Get-ContentType $filePath

                    $response.ContentLength64 = $bytes.Length

                    $response.Headers.Add("Cache-Control", "no-store")

                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                }

            }



        } catch {

            try {

                $response.StatusCode = 500

                $bytes = [System.Text.Encoding]::UTF8.GetBytes("500 Server Error: $($_.Exception.Message)")

                $response.ContentType = "text/plain; charset=utf-8"

                $response.ContentLength64 = $bytes.Length

                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } catch {}

        } finally {

            try { $response.OutputStream.Close() } catch {}

        }

    }

} finally {

    try { $listener.Stop() } catch {}

    try { $listener.Close() } catch {}

    Write-Host "`n웹 뷰어 서버를 종료했습니다."

}

