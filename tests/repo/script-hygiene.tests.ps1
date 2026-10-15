# 저장소의 스크립트가 Windows PowerShell 5.1 에서 반복해서 사고를 낸 모양을 지키는지 확인하는 점검.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\repo\script-hygiene.tests.ps1
# 실제로 겪은 일을 막으려고 만들었습니다:
#   - BOM 없는 UTF-8 .ps1 은 5.1 이 시스템 코드페이지(CP949)로 읽어 한글이 깨진다. (install.ps1/uninstall.ps1 만 예외: irm | iex 로 받으면 BOM 이 첫 줄을 깨뜨림)
#   - 줄바꿈이 섞이거나 CR 만 있는 줄이 있으면 diff 가 파일 전체로 번지고, 주석·문자열 안의 줄이 합쳐져 보인다.
#   - 합치다 남은 충돌 표시(<<<<<<<)가 파일에 남는다.
#   - 함수가 돌려준 값이 하나뿐이면 배열이 풀려서 .Count/.Length/[0] 이 엉뚱하게 동작한다(@() 로 감싸 받아야 한다).
# 몇 초 걸립니다. git 이 있으면 추적 중인 파일만, 없으면 폴더 전체를 봅니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

# --- 점검할 파일 목록 ---
function Get-RepoFiles([string[]]$Patterns) {
    $files = @()
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and (Test-Path (Join-Path $repoRoot ".git"))) {
        Push-Location $repoRoot
        try { $files = @(& git -c core.quotepath=off ls-files -- $Patterns 2>$null | Where-Object { $_ }) } finally { Pop-Location }
        $files = @($files | ForEach-Object { Join-Path $repoRoot ($_ -replace '/', '\') } | Where-Object { Test-Path -LiteralPath $_ })
    }
    if ($files.Count -eq 0) {
        $files = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include $Patterns -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(\.git|node_modules)\\' } | ForEach-Object { $_.FullName })
    }
    return $files
}
function Get-Rel([string]$Path) { return $Path.Substring($repoRoot.Length + 1) }

$psFiles = @(Get-RepoFiles @("*.ps1"))
# install/uninstall 은 BOM 없이 둔다(irm | iex 호환) — 이 둘은 파일 안의 자가 치유 가드가 한글 깨짐을 막는다.
$noBomByDesign = @("install.ps1", "uninstall.ps1")

Write-Host "파일 모양 (BOM · 줄바꿈 · 깨진 글자 · 충돌 표시)"
$bad = @{ Bom = @(); Eol = @(); Mojibake = @(); Parse = @() }
foreach ($f in $psFiles) {
    $rel = Get-Rel $f
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $wantBom = ($noBomByDesign -notcontains $rel)
    if ($hasBom -ne $wantBom) { $bad.Bom += $rel }
    $crlf = 0; $lf = 0; $cr = 0
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 13) { if ($i + 1 -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { $crlf++; $i++ } else { $cr++ } }
        elseif ($bytes[$i] -eq 10) { $lf++ }
    }
    # 이 PC 는 core.autocrlf=true 라 작업 폴더가 CRLF 다. 다른 방식으로 받은 파일(LF)도 읽기는 되니, 섞이거나 CR 만 있는 경우만 사고로 본다.
    if ($cr -gt 0 -or ($crlf -gt 0 -and $lf -gt 0)) { $bad.Eol += ("{0} (CRLF {1} / LF {2} / CR {3})" -f $rel, $crlf, $lf, $cr) }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)   # GetString 은 BOM 을 떼지 않는다
    if ($text.Contains([string][char]0xFFFD)) { $bad.Mojibake += $rel }
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errs)
    if (@($errs).Count -gt 0) { $bad.Parse += ("{0}: {1}" -f $rel, $errs[0].Message) }
}
Assert-Equal "점검한 .ps1 파일이 있다 ($($psFiles.Count)개)" $true ($psFiles.Count -gt 0)
Assert-Equal "BOM 규칙: 런타임·시험은 BOM 있음, install/uninstall 은 BOM 없음  $(@($bad.Bom) -join ', ')" 0 @($bad.Bom).Count
Assert-Equal "줄바꿈이 섞이거나 CR 만 있는 줄이 없다  $(@($bad.Eol) -join ', ')" 0 @($bad.Eol).Count
Assert-Equal "깨진 글자(U+FFFD)가 없다  $(@($bad.Mojibake) -join ', ')" 0 @($bad.Mojibake).Count
Assert-Equal "문법 오류가 없다  $(@($bad.Parse) -join ' | ')" 0 @($bad.Parse).Count

$textFiles = @(Get-RepoFiles @("*.ps1", "*.js", "*.md", "*.html", "*.css", "*.json", "*.vbs", "*.bat"))
$markerFiles = @()
foreach ($f in $textFiles) {
    foreach ($line in [System.IO.File]::ReadLines($f, [System.Text.Encoding]::UTF8)) {
        if ($line -match '^(<<<<<<< |>>>>>>> )' -or $line -eq '=======') { $markerFiles += (Get-Rel $f); break }
    }
}
Assert-Equal "합치다 남은 충돌 표시가 없다  $(@($markerFiles) -join ', ')" 0 @($markerFiles).Count

# --- 함수 반환값을 @() 없이 받아 .Count/.Length/[n] 로 쓰는 모양 ---
# 규칙: `$x = 우리가_만든_함수 ...` (@() 로 감싸지 않음) 다음에 같은 함수 안에서 $x.Count / $x.Length / $x[...] 를 쓰면 위험하다.
# 함수가 원소 하나를 돌려주면 5.1 은 배열을 풀어 버려서 .Count 가 비고, 원소가 없으면 $null 이 된다.
# 원소 하나를 돌려주는 게 확실한 함수는 아래 허용 목록에 이유와 함께 적는다.
$allowReturnsScalar = @{
    "Get-Utf8QueryParams" = "해시테이블을 돌려준다(해시테이블은 풀리지 않고 .Count 는 키 개수다)"
    "Get-ProcTable" = "해시테이블(프로세스 번호 -> 정보)을 돌려준다. 풀리지 않고 [번호] 로 읽는다(tools/watch-console-windows.ps1)"
}

Write-Host ""
Write-Host "함수 반환값을 배열로 받아 쓰는지"
$userFunctions = @{}
$asts = @{}
foreach ($f in $psFiles) {
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errs)
    $asts[$f] = $ast
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $userFunctions[$fn.Name] = $true }
}
function Get-EnclosingScope($node) {
    $p = $node.Parent
    while ($p -and -not ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and $p.Parent) { $p = $p.Parent }
    return $p
}
$risky = @()
foreach ($f in $psFiles) {
    $ast = $asts[$f]
    $assigns = $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $n.Operator -eq [System.Management.Automation.Language.TokenKind]::Equals }, $true)
    foreach ($a in $assigns) {
        $rhs = $a.Right
        # 오른쪽이 `함수 인자...` 한 줄짜리 명령일 때만(@() · $() · 괄호로 감싼 건 제외)
        if (-not ($rhs -is [System.Management.Automation.Language.PipelineAst])) { continue }
        if ($rhs.PipelineElements.Count -ne 1) { continue }
        $cmd = $rhs.PipelineElements[0]
        if (-not ($cmd -is [System.Management.Automation.Language.CommandAst])) { continue }
        $name = $cmd.GetCommandName()
        if (-not $name -or -not $userFunctions.ContainsKey($name) -or $allowReturnsScalar.ContainsKey($name)) { continue }
        $var = $a.Left.VariablePath.UserPath
        $scope = Get-EnclosingScope $a
        $root = if ($scope) { $scope } else { $ast }
        $uses = $root.FindAll({ param($n)
                (($n -is [System.Management.Automation.Language.MemberExpressionAst] -and
                        $n.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                        $n.Expression.VariablePath.UserPath -eq $var -and
                        ([string]$n.Member.Value) -in @("Count", "Length")) -or
                    ($n -is [System.Management.Automation.Language.IndexExpressionAst] -and
                        $n.Target -is [System.Management.Automation.Language.VariableExpressionAst] -and
                        $n.Target.VariablePath.UserPath -eq $var)) -and
                $n.Extent.StartOffset -gt $a.Extent.EndOffset }, $true)
        # 같은 변수를 그사이에 다시 대입했다면(예: @() 로 다시 받음) 첫 사용 전까지만 본다
        $reassigned = $root.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $n.Left.VariablePath.UserPath -eq $var -and
                $n.Extent.StartOffset -gt $a.Extent.EndOffset }, $true)
        $nextAssign = [int]::MaxValue
        foreach ($ra in @($reassigned)) { if ($ra.Extent.StartOffset -lt $nextAssign) { $nextAssign = $ra.Extent.StartOffset } }
        $firstUse = @($uses | Where-Object { $_.Extent.StartOffset -lt $nextAssign } | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1)
        if ($firstUse.Count -gt 0) {
            $risky += ("{0}:{1} `${2} = {3} ... `${2} 의 .Count/.Length/[ ] 사용(줄 {4})" -f (Get-Rel $f), $a.Extent.StartLineNumber, $var, $name, $firstUse[0].Extent.StartLineNumber)
        }
    }
}
Assert-Equal "함수 결과를 @() 없이 받아 .Count/.Length/[ ] 로 쓰는 곳이 없다 (원소 하나면 배열이 풀려 값이 빈다)" 0 @($risky).Count
foreach ($r in $risky) { Write-Host "        $r" -ForegroundColor Yellow }

# 규칙 자체가 동작하는지: 위험한 모양을 일부러 만들어 잡아내는지 확인한다(규칙이 조용히 꺼지는 것을 막는다)
Write-Host ""
Write-Host "점검 규칙 자체 확인"
$sample = @'
function Get-Things { return @(1) }
function Use-Bad { $x = Get-Things; return $x.Count }
function Use-Good { $x = @(Get-Things); return $x.Count }
function Use-Reassigned { $x = Get-Things; $x = @($x); return $x.Count }
'@
$t2 = $null; $e2 = $null
$sampleAst = [System.Management.Automation.Language.Parser]::ParseInput($sample, [ref]$t2, [ref]$e2)
$found = @()
foreach ($fn in $sampleAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -like "Use-*" }, $true)) {
    foreach ($a in $fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $rhs = $a.Right
        if ($rhs -is [System.Management.Automation.Language.PipelineAst] -and $rhs.PipelineElements.Count -eq 1 -and $rhs.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst] -and $rhs.PipelineElements[0].GetCommandName() -eq "Get-Things") {
            $var = $a.Left.VariablePath.UserPath
            $use = @($fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] -and $n.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Expression.VariablePath.UserPath -eq $var -and ([string]$n.Member.Value) -eq "Count" -and $n.Extent.StartOffset -gt $a.Extent.EndOffset }, $true))
            $re = @($fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.VariablePath.UserPath -eq $var -and $n.Extent.StartOffset -gt $a.Extent.EndOffset }, $true))
            if ($use.Count -gt 0 -and ($re.Count -eq 0 -or $re[0].Extent.StartOffset -gt $use[0].Extent.StartOffset)) { $found += $fn.Name }
        }
    }
}
Assert-Equal "위험한 모양(@() 없이 받고 .Count)만 잡는다" "Use-Bad" ($found -join ",")

Write-Host ""
Write-Host "문서·스크립트 전체: 홀로 있는 CR 문자"
# .ps1 은 위에서 봤다. 나머지 글 파일(문서·화면 코드 등)에 CR 만 있는 줄이 있으면 경로의 \r 이 글자로 둔갑한 것처럼 보이는 일이 생긴다
# (실제로 README 의 `tests\repo` 가 `tests` + CR + `epo` 로 깨져 올라간 적이 있다).
$loneCr = @()
foreach ($f in $textFiles) {
    $b = [System.IO.File]::ReadAllBytes($f)
    for ($i = 0; $i -lt $b.Length; $i++) {
        if ($b[$i] -eq 13 -and -not ($i + 1 -lt $b.Length -and $b[$i + 1] -eq 10)) { $loneCr += (Get-Rel $f); break }
    }
}
Assert-Equal "글 파일에 CR 만 있는 줄이 없다  $(@($loneCr) -join ', ')" 0 @($loneCr).Count

Write-Host ""
Write-Host "README 가 가리키는 시험 파일이 실제로 있는지"
$readme = Join-Path $repoRoot "README.md"
$missingTests = @()
if (Test-Path -LiteralPath $readme) {
    $readmeText = [System.IO.File]::ReadAllText($readme, [System.Text.Encoding]::UTF8)
    $allTests = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "tests") -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    foreach ($m in [regex]::Matches($readmeText, '`([A-Za-z0-9_.\\/-]+\.tests\.(?:ps1|js))`')) {
        $leaf = ($m.Groups[1].Value -split '[\\/]')[-1]
        if ($allTests -notcontains $leaf) { $missingTests += $m.Groups[1].Value }
    }
}
Assert-Equal "README 에 적힌 시험 파일이 모두 tests 아래에 있다  $(@($missingTests | Select-Object -Unique) -join ', ')" 0 @($missingTests | Select-Object -Unique).Count

Write-Host ""
Write-Host "시험이 함수를 뜯어 올 때 쓰는 이름 목록이 실제 함수와 맞는지"
# 시험은 `foreach ($name in @("A","B",...)) { ... FunctionDefinitionAst ... -eq $name ... }` 모양으로 다른 파일에서 함수를 꺼내 온다.
# 함수를 옮기거나 지웠는데 목록이 그대로면 시험이 깨지거나(이번에도 겪음) 조용히 건너뛴다. 목록의 모든 이름이 저장소 어딘가에 정의돼 있어야 한다.
function Get-StaleExtractNames($Ast, $KnownFunctions) {
    $stale = @()
    foreach ($fe in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
        if ($fe.Body.Extent.Text -notmatch 'FunctionDefinitionAst') { continue }
        # 배열 글자(@("A","B"))의 원소만 이름으로 본다. 조건 안의 코드(예: .FindAll(...) 의 메서드 이름)는 이름이 아니다.
        $names = @()
        foreach ($arr in $fe.Condition.FindAll({ param($n) $n -is [System.Management.Automation.Language.ArrayExpressionAst] }, $true)) {
            foreach ($s in $arr.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)) {
                $inCode = $false; $p = $s.Parent
                while ($p -and $p -ne $arr) { if ($p -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or $p -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) { $inCode = $true; break }; $p = $p.Parent }
                if (-not $inCode) { $names += [string]$s.Value }
            }
        }
        foreach ($n in $names) { if (-not $KnownFunctions.ContainsKey($n)) { $stale += $n } }
    }
    return @($stale)
}
$testAsts = @{}
$staleAll = @()
foreach ($f in $psFiles) {
    if ((Get-Rel $f) -notlike "tests\*") { continue }
    $stale = @(Get-StaleExtractNames $asts[$f] $userFunctions)
    foreach ($n in $stale) { $staleAll += ("{0}: {1}" -f (Get-Rel $f), $n) }
}
Assert-Equal "함수 꺼내 오기 목록의 이름이 모두 저장소에 정의돼 있다  $(@($staleAll) -join ' | ')" 0 @($staleAll).Count
$sampleStale = @'
foreach ($name in @("Exists-Func", "Gone-Func")) {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
}
'@
$t3 = $null; $e3 = $null
$sampleStaleAst = [System.Management.Automation.Language.Parser]::ParseInput($sampleStale, [ref]$t3, [ref]$e3)
Assert-Equal "점검 규칙 자체: 없는 이름만 잡는다" "Gone-Func" ((Get-StaleExtractNames $sampleStaleAst @{ "Exists-Func" = $true }) -join ",")

Write-Host ""
Write-Host "런타임에서 같은 이름의 함수를 두 파일에 정의하지 않았는지"
# 같은 함수를 두 곳에 두면 한쪽만 고치고 놓친다(주석에도 그런 사고가 적혀 있다). 나중에 읽힌 쪽이 이겨서 어느 쪽이 도는지도 헷갈린다.
$definedIn = @{}
foreach ($f in $psFiles) {
    if ((Get-Rel $f) -notlike "runtime\*") { continue }
    foreach ($fn in $asts[$f].FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        # 함수 안에 정의된 함수(중첩)는 바깥 함수에서만 보이므로 제외한다
        $p = $fn.Parent; $nested = $false
        while ($p) { if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $nested = $true; break }; $p = $p.Parent }
        if ($nested) { continue }
        if (-not $definedIn.ContainsKey($fn.Name)) { $definedIn[$fn.Name] = @() }
        $definedIn[$fn.Name] += (Get-Rel $f)
    }
}
# 의도해서 여러 곳에 둔 함수는 여기에 이유와 함께 적는다. (예: 독립 실행 스크립트마다 필요한 작은 로그 함수)
$allowDuplicateDefinition = @{
    "Log" = "스크립트마다 따로 도는 독립 실행 파일이라 각자 로그 함수를 가진다"
    "Write-WatchdogLog" = "ensure-agy-running.ps1 안에서만 쓰는 로그 함수"
    "ConvertTo-CwdList" = "뷰어(serve-viewer.ps1)는 위임 스크립트가 없어도 떠야 해서 사본을 두고, cwd-list.tests.ps1 이 common.ps1 과 같은 규칙인지 확인한다"
    "Test-WatcherAlive" = "start-agy.ps1(워처를 켜는 독립 스크립트)과 뷰어의 watcher-health.ps1 은 따로 도는 스크립트이고 서명도 다르다"
}
$dups = @()
foreach ($k in $definedIn.Keys) {
    $uniqueFiles = @($definedIn[$k] | Select-Object -Unique)
    if ($uniqueFiles.Count -gt 1 -and -not $allowDuplicateDefinition.ContainsKey($k)) { $dups += ("{0} -> {1}" -f $k, ($uniqueFiles -join ", ")) }
}
Assert-Equal "런타임 함수가 두 파일 이상에 정의돼 있지 않다  $(@($dups) -join ' | ')" 0 @($dups).Count

Write-Host ""
Write-Host "git 훅(.githooks)"
# 푸시 전 시험 훅: LF 여야 하고(CRLF 이면 sh 가 'bad interpreter' 로 실패) 첫 줄이 셸 지정이어야 한다.
$hook = Join-Path $repoRoot ".githooks\pre-push"
Assert-Equal "푸시 전 시험 훅(.githooks/pre-push)이 있다" $true (Test-Path -LiteralPath $hook)
if (Test-Path -LiteralPath $hook) {
    $hb = [System.IO.File]::ReadAllBytes($hook)
    $firstLine = [System.Text.Encoding]::UTF8.GetString($hb, 0, [Math]::Min(20, $hb.Length)) -split "`n" | Select-Object -First 1
    Assert-Equal "  첫 줄이 #!/bin/sh 이다(BOM 도 없다)" "#!/bin/sh" $firstLine
    $hookCr = 0; foreach ($x in $hb) { if ($x -eq 13) { $hookCr++ } }
    Assert-Equal "  줄바꿈이 LF 뿐이다(CR 없음)" 0 $hookCr
    $hookText = [System.Text.Encoding]::UTF8.GetString($hb)
    Assert-Equal "  run-all.ps1 을 부르고 실패하면 푸시를 막는다(exit 1)" $true (($hookText -like "*tests/run-all.ps1*") -and ($hookText -match 'exit 1'))
}
$attrs = Join-Path $repoRoot ".gitattributes"
$attrText = if (Test-Path -LiteralPath $attrs) { [System.IO.File]::ReadAllText($attrs) } else { "" }
Assert-Equal ".gitattributes 가 훅을 LF 로 고정한다" $true ($attrText -match '\.githooks/\*\s+text\s+eol=lf')
Assert-Equal ".gitattributes 가 .ps1 을 CRLF 로 고정한다" $true ($attrText -match '\*\.ps1\s+text\s+eol=crlf')

Write-Host ""
Write-Host "시험·스크립트가 보이는 콘솔 창을 만들지 않는지"
# WMI(Win32_Process.Create)로 프로세스를 만들면 기본으로 콘솔 창이 떴다 사라진다. 시험을 돌릴 때마다 창이 깜빡이던 원인이었다
# (tools\watch-console-windows.ps1 로 잡았다). 쓸 때는 ProcessStartupInformation(ShowWindow=0)을 같이 넘겨야 한다.
$wmiVisible = @()
foreach ($f in $psFiles) {
    $txt = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
    if ($txt -match 'Win32_Process' -and $txt -match 'MethodName\s+Create' -and $txt -notmatch 'ProcessStartupInformation') { $wmiVisible += (Get-Rel $f) }
}
$wmiVisible = @($wmiVisible | Where-Object { $_ -ne "tests\repo\script-hygiene.tests.ps1" })
Assert-Equal "WMI 로 프로세스를 만들 때 창 없이 만든다(ProcessStartupInformation)  $(@($wmiVisible) -join ', ')" 0 @($wmiVisible).Count

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
