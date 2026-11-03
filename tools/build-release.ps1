# build-release.ps1
# 저장소 그대로를 배포용 zip 으로 만든다. 별도 배포 사본은 없다 - 저장소가 곧 배포본이다.
#   Build-Release.cmd 더블클릭                  # 저장소의 dist\ 폴더에 만들고 탐색기로 보여 준다
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-release.ps1 -OutDir <폴더>   # -OutDir 을 빼면 dist\
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-release.ps1 -OutDir <폴더> -Working   # 커밋 안 한 변경(새 파일 포함)도 담는다
# git archive 로 만든다: .gitattributes 의 export-ignore 로 개발용 파일(tests · docs · .githooks 등)이 빠지고, *.ps1/*.cmd 는 CRLF 로 내려간다.
# 기본은 HEAD(커밋된 것)이고 VERSION 에 커밋 해시·날짜가 들어간다. -Working 은 임시 인덱스로 작업 폴더를 담으며(실제 인덱스는 건드리지 않는다) VERSION 이 채워지지 않는다.
# Agensi 는 zip 하나를 받아 안의 SKILL.md 를 찾는다(2개 이상이면 스킬 팩). 맨 위 폴더는 samjil-skills/ 로 둔다.
# 만든 뒤 점검: 실행 파일(.exe/.dll 등) · 50MB 초과 · 비밀 값 패턴 · 개인 경로가 있으면 경고한다.
param(
    [string]$OutDir = "",   # 비우면 저장소의 dist\ 폴더
    [switch]$Working,
    [switch]$Open           # 다 만들면 탐색기에서 zip 을 보여 준다(더블클릭용 Build-Release.cmd 가 쓴다)
)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $repoRoot "dist" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
Push-Location $repoRoot
try {
    $stamp = Get-Date -Format "yyyy-MM-dd"
    $tmpIndex = $null
    if ($Working) {
        $tmpIndex = Join-Path ([System.IO.Path]::GetTempPath()) ("samjil-index-" + [guid]::NewGuid().ToString("N"))
        $env:GIT_INDEX_FILE = $tmpIndex
        try {
            & git read-tree HEAD
            & git add -A
            $treeish = (& git write-tree).Trim()
        } finally {
            Remove-Item Env:\GIT_INDEX_FILE -ErrorAction SilentlyContinue
            Remove-Item -Force -LiteralPath $tmpIndex -ErrorAction SilentlyContinue
        }
        $label = "working"
    } else {
        $dirty = @(& git status --porcelain)
        if ($dirty.Count -gt 0) { Write-Warning "커밋하지 않은 변경 $($dirty.Count)개는 담기지 않습니다. 담으려면 -Working 을 쓰거나 먼저 커밋하세요." }
        $treeish = "HEAD"
        $label = (& git rev-parse --short HEAD).Trim()
    }
    $zipPath = Join-Path $OutDir ("samjil-skills-$stamp-$label.zip")
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -Force -LiteralPath $zipPath }
    & git archive --format=zip --prefix=samjil-skills/ -o $zipPath $treeish
    if ($LASTEXITCODE -ne 0) { throw "git archive 실패" }
} finally { Pop-Location }

# ---- 점검 ----
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
$warn = New-Object System.Collections.ArrayList
try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
    $skills = @($names | Where-Object { $_ -match '/SKILL\.md$' })
    Write-Host ("파일 {0}개, SKILL.md {1}개: {2}" -f $names.Count, $skills.Count, (($skills | ForEach-Object { ($_ -split '/')[1] }) -join ", "))
    foreach ($n in ($names | Where-Object { $_ -match '\.(exe|dll|dmg|msi)$' })) { [void]$warn.Add("실행 파일 형식: $n (Agensi 는 exe/dll/dmg 를 거부합니다)") }
    foreach ($n in ($names | Where-Object { $_ -match '(^|/)(\.DS_Store|Thumbs\.db)$' })) { [void]$warn.Add("OS 잡파일: $n") }
    foreach ($e in $zip.Entries) {
        if ($e.Length -eq 0 -or $e.Length -gt 2MB -or $e.FullName -match '\.(png|ico)$') { continue }
        $sr = New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::UTF8)
        try { $txt = $sr.ReadToEnd() } finally { $sr.Dispose() }
        if ($txt -match '(?i)(api[_-]?key|secret|password|token)\s*[:=]\s*["''][A-Za-z0-9_\-]{16,}') { [void]$warn.Add("비밀 값처럼 보이는 문자열: $($e.FullName)") }
        if ($txt -match '(?i)C:\\Users\\(username)\\|/Users/username/') { [void]$warn.Add("개인 경로: $($e.FullName)") }
    }
} finally { $zip.Dispose() }
$size = (Get-Item -LiteralPath $zipPath).Length
Write-Host ("크기 {0:N0} 바이트" -f $size)
if ($size -gt 50MB) { [void]$warn.Add("50MB 를 넘습니다 (Agensi 웹 업로드 한도)") }
foreach ($w in $warn) { Write-Warning $w }
Write-Host $zipPath
if ($Open) { Start-Process explorer.exe -ArgumentList "/select,`"$zipPath`"" }
