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
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
