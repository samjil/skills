# watch-agy.ps1 의 @model: (요청에서 모델 고르기) 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\model-select.tests.ps1
# 지시어 해석과 모델 검증은 순수 함수로 검사하고, 후보 선택/폴백 없음은 가짜 agy(agy.cmd)로 실제 호출 경로를 돌립니다.
# 실제 agy 는 건드리지 않습니다(PATH 맨 앞의 임시 폴더에 가짜를 둠). 약 20초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$subDir   = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub"
. (Join-Path $subDir "agy-progress.ps1")

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

# --- watch-agy.ps1 에서 필요한 정의만 꺼내 옵니다(워처 본체는 실행하지 않음) ---
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $subDir "watch-agy.ps1"), [ref]$tokens, [ref]$errs)
$wantedVars = @("ModelPriority", "FallbackErrorPattern", "SelectableModels")
$assigns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        ($wantedVars -contains $n.Left.VariablePath.UserPath) }, $false)
foreach ($a in ($assigns | Sort-Object { $_.Extent.StartOffset })) { Invoke-Expression $a.Extent.Text }
$fnTexts = @{}
foreach ($name in @("Get-JsonField", "Invoke-AgyOnce", "Get-AgyPromptMarker", "Invoke-AgyWithFallback", "ConvertFrom-TaskDirectives", "Resolve-RequestedModel")) {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name 를 watch-agy.ps1 에서 찾지 못했습니다." }
    $fnTexts[$name] = $fn.Extent.Text
    Invoke-Expression $fn.Extent.Text
}

$astCommon = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $subDir "common.ps1"), [ref]$tokens, [ref]$errs)
foreach ($name in @("ConvertTo-CwdList", "Resolve-TaskCwds", "Get-MissingCwds")) {
    $fn = $astCommon.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name 를 common.ps1 에서 찾지 못했습니다." }
    $fnTexts[$name] = $fn.Extent.Text
    Invoke-Expression $fn.Extent.Text
}

Write-Host "정의"
Assert-Equal "우선순위 목록의 첫 모델은 gemini-3.8-flash-high" "gemini-3.8-flash-high" $ModelPriority[0]
Assert-Equal "고를 수 있는 모델에 flash 3단계가 있다" $true (($SelectableModels -contains "gemini-3.8-flash-high") -and ($SelectableModels -contains "gemini-3.8-flash-medium") -and ($SelectableModels -contains "gemini-3.8-flash-low"))
Assert-Equal "우선순위 목록의 모델도 고를 수 있다 (gemini-3.1-pro-high)" $true ($SelectableModels -contains "gemini-3.1-pro-high")
Assert-Equal "중복 없이 담긴다" $SelectableModels.Count (@($SelectableModels | Select-Object -Unique).Count)
Assert-Equal "Gemini 계열만 허용한다 (claude/gpt-oss 제외)" 0 @($SelectableModels | Where-Object { $_ -notlike "gemini-*" }).Count

Write-Host "ConvertFrom-TaskDirectives"
$d = ConvertFrom-TaskDirectives "그냥 질문입니다"
Assert-Equal "지시어가 없으면 본문 그대로" "그냥 질문입니다" $d.Prompt
Assert-Equal "  cwd 는 빈 배열, session/model 은 `$null" $true ((@($d.Cwd).Count -eq 0) -and ($null -eq $d.Session) -and ($null -eq $d.Model))

$d = ConvertFrom-TaskDirectives "@cwd: C:\proj`n@session: 작업-1`n@model: gemini-3.8-flash-low`n본문 첫 줄`n둘째 줄"
Assert-Equal "세 지시어를 모두 읽는다 (cwd)" "C:\proj" (@($d.Cwd) -join "|")
Assert-Equal "  session" "작업-1" $d.Session
Assert-Equal "  model" "gemini-3.8-flash-low" $d.Model
Assert-Equal "  본문은 지시어 다음 줄부터" "본문 첫 줄`n둘째 줄" $d.Prompt

$d = ConvertFrom-TaskDirectives "@model: gemini-3.8-flash-medium`r`n`r`n@cwd: C:\p`r`n질문"
Assert-Equal "순서가 달라도, 사이에 빈 줄이 있어도, CRLF 여도 읽는다 (model)" "gemini-3.8-flash-medium" $d.Model
Assert-Equal "  cwd" "C:\p" (@($d.Cwd) -join "|")
Assert-Equal "  본문" "질문" $d.Prompt

$d = ConvertFrom-TaskDirectives ([string][char]0xFEFF + "@model: gemini-3.8-flash-low`n질문")
Assert-Equal "맨 앞 BOM 이 있어도 첫 줄 지시어를 읽는다" "gemini-3.8-flash-low" $d.Model

$d = ConvertFrom-TaskDirectives "@model:    gemini-3.8-flash-high   `n질문"
Assert-Equal "값 앞뒤 공백은 지운다" "gemini-3.8-flash-high" $d.Model

$d = ConvertFrom-TaskDirectives "첫 줄은 본문`n@model: gemini-3.8-flash-low`n끝"
Assert-Equal "본문이 시작된 뒤의 @model 줄은 지시어가 아니다" $null $d.Model
Assert-Equal "  본문에 그대로 남는다" "첫 줄은 본문`n@model: gemini-3.8-flash-low`n끝" $d.Prompt

$d = ConvertFrom-TaskDirectives "@foo: 모르는 키`n@model: gemini-3.8-flash-low`n끝"
Assert-Equal "모르는 @키 줄에서 지시어 읽기가 멈춘다 (그 뒤 @model 은 읽지 않음)" $null $d.Model


Write-Host "ConvertFrom-TaskDirectives: @cwd 여러 줄"
$d = ConvertFrom-TaskDirectives "@cwd: D:\a\repo`n@cwd: D:\b\docs`n@model: gemini-3.8-flash-medium`n본문"
Assert-Equal "@cwd 를 여러 줄 쓰면 줄 순서대로 모두 읽는다" "D:\a\repo|D:\b\docs" (@($d.Cwd) -join "|")
Assert-Equal "  개수는 2" 2 @($d.Cwd).Count
Assert-Equal "  다른 지시어와 본문은 그대로" "gemini-3.8-flash-medium|본문" ("{0}|{1}" -f $d.Model, $d.Prompt)
$d = ConvertFrom-TaskDirectives "@cwd: D:\a`n@model: gemini-3.8-flash-low`n@cwd: D:\b`n@session: s`n@cwd: D:\c`n질문"
Assert-Equal "다른 지시어 사이에 끼어 있어도 순서대로 모은다" "D:\a|D:\b|D:\c" (@($d.Cwd) -join "|")
$d = ConvertFrom-TaskDirectives "@cwd: D:\Repo`n@cwd: d:\repo\`n@cwd: D:\REPO/`n@cwd: D:\other`n질문"
Assert-Equal "같은 경로는 대소문자와 끝의 \ 또는 / 를 무시하고 처음 것만 남긴다" "D:\Repo|D:\other" (@($d.Cwd) -join "|")
$d = ConvertFrom-TaskDirectives "@cwd: D:\a`r`n`r`n@cwd:    D:\b with space   `r`n질문"
Assert-Equal "빈 줄과 CRLF 가 있어도, 값 앞뒤 공백은 지우고 안의 공백은 둔다" "D:\a|D:\b with space" (@($d.Cwd) -join "|")
$d = ConvertFrom-TaskDirectives "질문 첫 줄`n@cwd: D:\late"
Assert-Equal "본문이 시작된 뒤의 @cwd 는 지시어가 아니다(폴더 없음)" 0 @($d.Cwd).Count
$d = ConvertFrom-TaskDirectives "@cwd: D:\only`n질문"
Assert-Equal "한 줄짜리는 이전과 같은 폴더 하나(배열이지만 요소는 하나)" "D:\only|1" ("{0}|{1}" -f (@($d.Cwd) -join "|"), @($d.Cwd).Count)
$d = ConvertFrom-TaskDirectives "질문만"
Assert-Equal "@cwd 가 없으면 빈 배열(null 이 아님)" "0|False" ("{0}|{1}" -f @($d.Cwd).Count, ($null -eq $d.Cwd))
Assert-Equal "ConvertTo-CwdList: 문자열 하나(예전 세션 파일)도 읽는다" "D:\old" (@(ConvertTo-CwdList "D:\old") -join "|")
Assert-Equal "  배열도 읽는다" "D:\a|D:\b" (@(ConvertTo-CwdList @("D:\a", "D:\b")) -join "|")
Assert-Equal "  null·빈 문자열·공백뿐인 값은 뺀다" 0 @(ConvertTo-CwdList @($null, "", "   ")).Count
Assert-Equal "Resolve-TaskCwds: 이번 호출에 @cwd 가 있으면 이번 목록만(세션과 합치지 않는다)" "D:\new" (@(Resolve-TaskCwds @("D:\new") @("D:\old1", "D:\old2")) -join "|")
Assert-Equal "  없으면 세션의 목록(배열)" "D:\old1|D:\old2" (@(Resolve-TaskCwds @() @("D:\old1", "D:\old2")) -join "|")
Assert-Equal "  없으면 세션의 값이 문자열(예전 파일)이어도 읽는다" "D:\old" (@(Resolve-TaskCwds @() "D:\old") -join "|")
Assert-Equal "  둘 다 없으면 빈 배열" 0 @(Resolve-TaskCwds @() $null).Count
Assert-Equal "Get-MissingCwds: 없는 폴더만 모두 돌려준다" "D:\no-such-1|D:\no-such-2" (@(Get-MissingCwds @($env:TEMP, "D:\no-such-1", "D:\no-such-2")) -join "|")
Assert-Equal "  모두 있으면 빈 배열" 0 @(Get-MissingCwds @($env:TEMP, $env:windir)).Count

# 빈 문자열/공백뿐인 입력이 무한 루프에 빠지지 않는다(예전 인라인 루프에는 그 위험이 있었음)
$job = Start-Job -ScriptBlock { param($t, $u) Invoke-Expression $u; Invoke-Expression $t; $x = ConvertFrom-TaskDirectives ""; $y = ConvertFrom-TaskDirectives "  `n  "; "ok" } -ArgumentList $fnTexts["ConvertFrom-TaskDirectives"], $fnTexts["ConvertTo-CwdList"]
$finished = Wait-Job $job -Timeout 20
Assert-Equal "빈 입력에서 멈추지 않는다" $true ([bool]$finished)
if (-not $finished) { Stop-Job $job }
Remove-Job $job -Force -ErrorAction SilentlyContinue

Write-Host "Resolve-RequestedModel"
$r = Resolve-RequestedModel "" "" "" ""
Assert-Equal "요청이 없으면 모델도 오류도 없다" $true (($null -eq $r.Model) -and ($null -eq $r.Error))

$r = Resolve-RequestedModel "gemini-3.8-flash-medium" "" "" ""
Assert-Equal "쓸 수 있는 모델이면 그대로" "gemini-3.8-flash-medium" $r.Model
Assert-Equal "  오류 없음" $null $r.Error

$r = Resolve-RequestedModel "GEMINI-3.8-Flash-LOW" "" "" ""
Assert-Equal "대소문자는 구분하지 않고 정식 ID 로 바꾼다" "gemini-3.8-flash-low" $r.Model

$r = Resolve-RequestedModel "claude-opus-4-6-thinking" "" "" ""
Assert-Equal "목록에 없는 모델은 오류 (claude)" $null $r.Model
Assert-Equal "  오류에 지정한 값이 있다" $true ($r.Error -like "*claude-opus-4-6-thinking*")
Assert-Equal "  오류에 쓸 수 있는 모델 목록이 있다" $true ($r.Error -like "*gemini-3.8-flash-medium*")

$r = Resolve-RequestedModel "gemini-9.9-nope" "" "" ""
Assert-Equal "존재하지 않는 ID 도 오류" $true ([bool]$r.Error)

$r = Resolve-RequestedModel "gemini-3.8-flash-high" "conv-1" "gemini-3.8-flash-high" "작업-1"
Assert-Equal "이어가는 세션에서 시작 모델과 같은 모델을 말하면 괜찮다" $null $r.Error

$r = Resolve-RequestedModel "gemini-3.8-flash-low" "conv-1" "gemini-3.8-flash-high" "작업-1"
Assert-Equal "이어가는 세션에서 다른 모델을 말하면 오류 (조용히 무시하지 않는다)" $true ([bool]$r.Error)
Assert-Equal "  오류에 세션 이름과 시작 모델이 있다" $true (($r.Error -like "*작업-1*") -and ($r.Error -like "*gemini-3.8-flash-high*"))

$r = Resolve-RequestedModel "gemini-3.8-flash-low" "" "" "새-세션"
Assert-Equal "새로 시작하는 세션(이어갈 대화 없음)에는 어떤 모델이든 쓸 수 있다" $null $r.Error

# --- 가짜 agy 로 Invoke-AgyWithFallback 의 후보 선택을 확인 ---
$work = Join-Path ([IO.Path]::GetTempPath()) ("model-select-test-" + [Guid]::NewGuid().ToString("N"))
$fakeBin = Join-Path $work "bin"
New-Item -ItemType Directory -Force -Path $fakeBin, (Join-Path $work "agyhome\conversations") | Out-Null
Set-Content -Path (Join-Path $fakeBin "fake-agy.ps1") -Encoding ASCII -Value @'
$a = @($args)
$i = [Array]::IndexOf([string[]]$a, '--model'); $model = if ($i -ge 0) { $a[$i + 1] } else { "" }
$c = [Array]::IndexOf([string[]]$a, '--conversation'); $conv = if ($c -ge 0) { $a[$c + 1] } else { "" }
Add-Content -Path $env:FAKE_ARGS_LOG -Value ("model=" + $model + " conv=" + $conv)
$dirs = @(); for ($k = 0; $k -lt ($a.Count - 1); $k++) { if ($a[$k] -eq '--add-dir') { $dirs += $a[$k + 1] } }
Add-Content -Path $env:FAKE_DIRS_LOG -Value ("dirs=" + ($dirs -join '|'))
$quota = @($env:FAKE_QUOTA_MODELS -split ',' | Where-Object { $_ })
if ($quota -contains $model) { '{"status":"ERROR","error":"quota exceeded for model ' + $model + '"}' }
else { '{"status":"SUCCESS","response":"ok from ' + $model + '","conversation_id":"conv-test","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}' }
'@
Set-Content -Path (Join-Path $fakeBin "agy.cmd") -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake-agy.ps1`" %*"
$env:PATH = "$fakeBin;$env:PATH"
$env:AGY_HOME = Join-Path $work "agyhome"
$env:FAKE_ARGS_LOG = Join-Path $work "args.log"
$env:FAKE_DIRS_LOG = Join-Path $work "dirs.log"

$LogsDir = $work; $RuntimeDir = $work
$AgyTimeoutSeconds = 60; $AgyStallSeconds = 30; $AgyPollSeconds = 2; $AgyProgressLogSeconds = 600; $AgyConversationWindowSeconds = 5
$script:LogLines = @()
function Log($msg) { $script:LogLines += $msg }

function Run-Agy([string]$requested, [string]$quotaModels = "", [string]$conversationId = "", [string]$knownModel = "", $cwds = $null) {
    Remove-Item $env:FAKE_ARGS_LOG -Force -ErrorAction SilentlyContinue
    Remove-Item $env:FAKE_DIRS_LOG -Force -ErrorAction SilentlyContinue
    $env:FAKE_QUOTA_MODELS = $quotaModels
    $r = Invoke-AgyWithFallback -safePrompt "hello" -targetCwd $cwds -skipPerm $false -errFile (Join-Path $work "err.log") -conversationId $conversationId -knownModel $knownModel -taskId "t" -requestedModel $requested
    # @(if ...) 로 감싼다: if 식은 한 줄짜리 배열을 문자열로 풀어 버려서 $calls[0] 이 첫 "글자"가 된다.
    $calls = @(if (Test-Path $env:FAKE_ARGS_LOG) { Get-Content $env:FAKE_ARGS_LOG })
    $dirs = @(if (Test-Path $env:FAKE_DIRS_LOG) { Get-Content $env:FAKE_DIRS_LOG })
    return @{ Result = $r; Calls = $calls; Dirs = $dirs }
}

Write-Host "Invoke-AgyWithFallback (가짜 agy)"
$o = Run-Agy ""
Assert-Equal "모델을 안 고르면 우선순위 첫 모델로 호출한다" "model=$($ModelPriority[0]) conv=" $o.Calls[0]
Assert-Equal "  성공하고 사용 모델이 첫 모델이다" $ModelPriority[0] $o.Result.ModelUsed

$o = Run-Agy "" $ModelPriority[0]
Assert-Equal "모델을 안 고르고 첫 모델이 쿼터 초과면 다음 모델로 폴백한다 (기존 동작)" 2 $o.Calls.Count
Assert-Equal "  두 번째로 시도한 모델" "model=$($ModelPriority[1]) conv=" $o.Calls[1]
Assert-Equal "  성공" $true $o.Result.Success

$o = Run-Agy "gemini-3.8-flash-medium"
Assert-Equal "@model 로 고르면 그 모델 하나만 호출한다" 1 $o.Calls.Count
Assert-Equal "  --model 에 그 값을 넘겼다" "model=gemini-3.8-flash-medium conv=" $o.Calls[0]
Assert-Equal "  성공하고 사용 모델이 그 모델이다" "gemini-3.8-flash-medium" $o.Result.ModelUsed
Assert-Equal "  시도한 모델 기록은 그 하나" "gemini-3.8-flash-medium" ($o.Result.TriedModels -join ",")

$o = Run-Agy "gemini-3.8-flash-medium" "gemini-3.8-flash-medium"
Assert-Equal "고른 모델이 쿼터 초과면 다른 모델로 넘어가지 않는다 (호출 1번)" 1 $o.Calls.Count
Assert-Equal "  실패로 끝난다" $false $o.Result.Success
Assert-Equal "  오류에 쿼터 초과가 담긴다" $true ($o.Result.ErrorMessage -like "*quota*")
Assert-Equal "  시도한 모델은 고른 하나뿐" "gemini-3.8-flash-medium" ($o.Result.TriedModels -join ",")
Assert-Equal "  사용 모델은 비어 있다 (실제로 못 썼다)" $null $o.Result.ModelUsed

$o = Run-Agy "gemini-3.8-flash-low" "" "conv-1" "gemini-3.8-flash-low"
Assert-Equal "이어가는 세션은 --conversation 만 쓰고 --model 은 넘기지 않는다" "model= conv=conv-1" $o.Calls[0]


Write-Host "Invoke-AgyWithFallback: @cwd 폴더마다 --add-dir"
$o = Run-Agy "" "" "" "" @("D:\a\repo", "D:\b\docs")
Assert-Equal "폴더가 둘이면 --add-dir 를 폴더마다 한 번씩, 줄 순서대로 넘긴다" "dirs=D:\a\repo|D:\b\docs" $o.Dirs[0]
Assert-Equal "  agy 는 한 번만 불렀다" 1 $o.Calls.Count
$o = Run-Agy "" "" "" "" @("D:\only")
Assert-Equal "폴더가 하나면 이전처럼 --add-dir 하나" "dirs=D:\only" $o.Dirs[0]
$o = Run-Agy "" "" "" "" "D:\as-string"
Assert-Equal "문자열 하나를 줘도(예전 호출 방식) --add-dir 하나" "dirs=D:\as-string" $o.Dirs[0]
$o = Run-Agy "" "" "" "" $null
Assert-Equal "폴더가 없으면 --add-dir 를 붙이지 않는다" "dirs=" $o.Dirs[0]
$o = Run-Agy "" "" "" "" @()
Assert-Equal "빈 배열도 --add-dir 를 붙이지 않는다" "dirs=" $o.Dirs[0]
$o = Run-Agy "gemini-3.8-flash-low" "" "conv-1" "gemini-3.8-flash-low" @("D:\a", "D:\b")
Assert-Equal "이어가는 세션 호출에도 폴더마다 --add-dir 를 넘긴다" "dirs=D:\a|D:\b" $o.Dirs[0]
$o = Run-Agy "" $ModelPriority[0] "" "" @("D:\a", "D:\b")
Assert-Equal "모델 폴백으로 다시 불러도 두 번 모두 같은 폴더 목록을 넘긴다" "2|dirs=D:\a|D:\b|dirs=D:\a|D:\b" ("{0}|{1}|{2}" -f $o.Dirs.Count, $o.Dirs[0], $o.Dirs[1])

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
