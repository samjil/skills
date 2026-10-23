# handoff-lib.ps1
# samjil-handoff 채널(<채널 루트>\<프로젝트>\ 의 INDEX.md, msg\NNNN-방향-슬러그.md)을 읽고 쓰는 공용 함수 모음입니다.
# dot-source 해서 씁니다: . (Join-Path $PSScriptRoot "handoff-lib.ps1")
#   - 워처(watch-agy.ps1 의 핸드오프 펌프): agy 회신을 채널에 기록한다
#   - Claude Stop 훅(handoff-stop-hook.ps1): agy 회신이 왔는지 본다
#   - 뷰어(serve-viewer.ps1): 메시지 머리말(모델)과 자동 이어가기 상태를 읽는다
# 규약 본문은 samjil-handoff 스킬에 있습니다. 여기서는 그 규약을 어기지 않게만 쓴다:
#   - 원장(INDEX.md)은 통째로 다시 쓰지 않는다. 줄 하나만 덧붙이거나 한 줄의 상태 칸 하나만 바꾼다(읽은 뒤 바로 쓴다).
#   - 남이 쓴 메시지 파일은 고치지 않는다. 새 파일(CreateNew)로만 쓴다.
#   - 표 사이에 빈 줄을 넣지 않는다.

$script:HandoffStatusWords = @("보냄", "읽음", "처리됨", "확인함", "보류")

function Write-HandoffLog([string]$Message) {
    if (Get-Command Log -CommandType Function -ErrorAction SilentlyContinue) { Log $Message }
}

# --------------------------------------------------------------------------------------------
# 채널 찾기
# --------------------------------------------------------------------------------------------

# 채널 루트: 환경변수 AGENT_HANDOFF_ROOT -> ~/.samjil/handoff -> (예전) ~/.samjil/samjil-handoff. 있는 첫 곳, 없으면 기본 경로.
function Get-HandoffRootDir {
    $cands = @()
    if ($env:AGENT_HANDOFF_ROOT) { $cands += $env:AGENT_HANDOFF_ROOT }
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    if ($home_) {
        $cands += (Join-Path $home_ ".samjil/handoff")
        $cands += (Join-Path $home_ ".samjil/samjil-handoff")
    }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c -PathType Container) { return $c } }
    if ($cands.Count -gt 0) { return $cands[0] }
    return ""
}

function Find-HandoffChannelDir([string]$Name) {
    if (-not $Name -or $Name.Contains("..") -or $Name.Contains("/") -or $Name.Contains("\")) { return $null }
    $root = Get-HandoffRootDir
    if (-not $root) { return $null }
    $d = Join-Path $root $Name
    if (Test-Path -LiteralPath $d -PathType Container) { return $d }
    return $null
}

# 채널로 볼 수 있는 폴더(INDEX.md 가 있는 것)의 전체 경로 목록. templates/viewer/scripts 는 채널이 아니다.
function Get-HandoffChannelDirs {
    $root = Get-HandoffRootDir
    if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    $out = @()
    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        if (@("templates", "viewer", "scripts") -contains $d.Name) { continue }
        if (Test-Path -LiteralPath (Join-Path $d.FullName "INDEX.md") -PathType Leaf) { $out += $d.FullName }
    }
    return @($out)
}

# 채널의 세션 ID들: BRIEF.md 의 "세션 ID: `ID1`, `ID2`" 줄에서 백틱으로 감싼 값을 모두 읽는다. 세션 전용 채널(폴더 이름이 저장소와 달라도 되는 채널)이
# 이 줄로 자기 세션을 알린다. 세션을 이어서 다시 열면(resume) 세션 ID 가 바뀌므로 여러 개를 적을 수 있게 했다.
# 줄이 없거나 자리표시자(<...>)뿐이면 빈 배열.
function Get-HandoffBriefSessionIds([string]$ChannelDir) {
    $brief = Join-Path $ChannelDir "BRIEF.md"
    if (-not (Test-Path -LiteralPath $brief -PathType Leaf)) { return @() }
    $out = @()
    try {
        $text = [System.IO.File]::ReadAllText($brief, [System.Text.Encoding]::UTF8)
        $line = [regex]::Match($text, '세션\s*ID\*{0,2}\s*[:：]([^\r\n]*)')
        if ($line.Success) {
            foreach ($m in [regex]::Matches($line.Groups[1].Value, '`([^`]+)`')) {
                $id = $m.Groups[1].Value.Trim()
                if ($id -and -not $id.StartsWith("<") -and ($out -notcontains $id)) { $out += $id }
            }
        }
    } catch {}
    return @($out)
}

# 첫 번째 세션 ID(없으면 빈 문자열). 예전 호출과의 호환용.
function Get-HandoffBriefSessionId([string]$ChannelDir) {
    $ids = @(Get-HandoffBriefSessionIds $ChannelDir)
    if ($ids.Count -gt 0) { return [string]$ids[0] }
    return ""
}

# $Path 가 $Base 와 같거나 그 아래인지(대소문자·구분자·끝의 \ 무시).
function Test-HandoffPathUnder([string]$Path, [string]$Base) {
    if (-not $Path -or -not $Base) { return $false }
    $norm = { param($s) ($s -replace '/', '\').TrimEnd([char]92).ToLowerInvariant() }
    $a = & $norm $Path; $b = & $norm $Base
    if (-not $a -or -not $b) { return $false }
    return ($a -eq $b) -or $a.StartsWith($b + "\")
}

# 작업 폴더(Claude 세션의 cwd)에서 채널을 찾는다.
# 1) 세션 ID 를 받았으면 먼저: BRIEF.md 의 "세션 ID"(여러 개 가능) 중 하나가 같고 "저장소 경로" 가 cwd 와 같거나 그 위인 채널. 둘 다 맞아야 한다 —
#    세션 전용 채널은 폴더 이름이 저장소 이름과 달라도(예: skills--handoff-test) 그 세션에서만 찾아진다.
# 2) 없으면 이름으로: 채널 폴더 이름은 작업 저장소 폴더 이름과 같게 둔다는 규약이라
#    cwd 의 폴더 이름과 그 위 세 단계까지(워크트리·하위 폴더에서 열어도 찾도록) 본다.
function Resolve-HandoffChannelForCwd([string]$Cwd, [string]$SessionId = "") {
    if (-not $Cwd) { return $null }
    if ($SessionId) {
        foreach ($d in @(Get-HandoffChannelDirs)) {
            if (@(Get-HandoffBriefSessionIds $d) -notcontains $SessionId) { continue }
            $repo = Get-HandoffRepoPath $d
            if ($repo -and (Test-HandoffPathUnder $Cwd $repo)) { return $d }
        }
    }
    $p = $Cwd.TrimEnd([char]92, [char]47)
    for ($i = 0; $i -lt 4 -and $p; $i++) {
        $leaf = Split-Path -Leaf $p
        if ($leaf) {
            $dir = Find-HandoffChannelDir $leaf
            if ($dir -and (Test-Path -LiteralPath (Join-Path $dir "INDEX.md") -PathType Leaf)) { return $dir }
        }
        $parent = Split-Path -Parent $p
        if (-not $parent -or $parent -eq $p) { break }
        $p = $parent
    }
    return $null
}

# 채널의 작업 저장소 경로: BRIEF.md 의 "저장소 경로: `경로`" 줄. 폴더가 실제로 있을 때만 돌려준다.
function Get-HandoffRepoPath([string]$ChannelDir) {
    $brief = Join-Path $ChannelDir "BRIEF.md"
    if (-not (Test-Path -LiteralPath $brief -PathType Leaf)) { return $null }
    try {
        $text = [System.IO.File]::ReadAllText($brief, [System.Text.Encoding]::UTF8)
        $m = [regex]::Match($text, '저장소\s*경로\*{0,2}\s*[:：]\s*\*{0,2}\s*`([^`]+)`')
        if ($m.Success) {
            $p = $m.Groups[1].Value.Trim()
            if ($p -and -not $p.StartsWith("<") -and (Test-Path -LiteralPath $p -PathType Container)) { return $p }
        }
    } catch {}
    return $null
}

# --------------------------------------------------------------------------------------------
# 채널 잠금(이 PC 안에서 INDEX 번호·행 쓰기가 겹치지 않게). 못 잡아도 멈추지 않고 진행한다(번호는 CreateNew 로 한 번 더 지킨다).
# --------------------------------------------------------------------------------------------
function Invoke-HandoffLock([string]$ChannelDir, [scriptblock]$Block, [int]$TimeoutSeconds = 10) {
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = [BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ChannelDir.ToLowerInvariant().TrimEnd([char]92, [char]47)))).Replace("-", "")
    } finally { $sha.Dispose() }
    $mutex = New-Object System.Threading.Mutex($false, "Local\samjil-handoff-$hash")
    $got = $false
    try {
        try { $got = $mutex.WaitOne($TimeoutSeconds * 1000) } catch [System.Threading.AbandonedMutexException] { $got = $true }
        & $Block
    } finally {
        if ($got) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
}

# --------------------------------------------------------------------------------------------
# 원장(INDEX.md)
# --------------------------------------------------------------------------------------------

# 한 줄 -> @{ Num; Time; Dir; Title; Status } . 표의 데이터 행이 아니면 $null.
function ConvertFrom-HandoffIndexLine([string]$Line) {
    $m = [regex]::Match($Line, '^\s*\|\s*(\d{4})\s*\|(.*)\|\s*$')
    if (-not $m.Success) { return $null }
    $cells = @($m.Groups[2].Value.Split([char]124) | ForEach-Object { $_.Trim() })   # 번호 뒤: 시각, 방향, 제목..., 상태
    if ($cells.Count -lt 4) { return $null }
    $titleCells = @($cells[2..($cells.Count - 2)])                  # 제목(제목 안에 | 가 있으면 여러 칸)
    return @{
        Num    = $m.Groups[1].Value
        Time   = $cells[0]
        Dir    = $cells[1]
        Title  = ($titleCells -join "|")
        Status = $cells[$cells.Count - 1]
    }
}

function Read-HandoffIndex([string]$ChannelDir) {
    $p = Join-Path $ChannelDir "INDEX.md"
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return @() }
    $rows = @()
    $text = $null
    try {
        $fs = New-Object System.IO.FileStream($p, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try { $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true); $text = $sr.ReadToEnd() } finally { $fs.Dispose() }
    } catch { return @() }
    foreach ($line in @($text -split "\r?\n")) {
        $r = ConvertFrom-HandoffIndexLine $line
        if ($r) { $rows += [pscustomobject]$r }
    }
    return @($rows)
}

# 원장 파일을 "읽고 바로 쓰는" 한 번의 작업으로 고친다. $Mutator 는 줄 목록(List[string])을 받아 고치고 $true(바뀜)/$false 를 돌려준다.
# 줄바꿈 모양(CRLF/LF), BOM, 끝의 줄바꿈 유무를 그대로 지킨다. 읽은 뒤 상대가 바꾼 값을 덮지 않도록 읽는 즉시 쓴다.
function Edit-HandoffIndexFile([string]$IndexPath, [scriptblock]$Mutator) {
    for ($try = 0; $try -lt 5; $try++) {
        $fs = $null
        try {
            $fs = New-Object System.IO.FileStream($IndexPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
            $bytes = New-Object byte[] ([int]$fs.Length)
            $got = 0
            while ($got -lt $bytes.Length) { $n = $fs.Read($bytes, $got, $bytes.Length - $got); if ($n -le 0) { break }; $got += $n }
            $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $offset = if ($bom) { 3 } else { 0 }
            $text = [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
            $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
            $endsWithNl = ($text.Length -gt 0 -and $text.EndsWith("`n"))
            $lines = New-Object 'System.Collections.Generic.List[string]'
            if ($text.Length -gt 0) {
                $body = if ($endsWithNl) { $text.Substring(0, $text.Length - 1) } else { $text }
                if ($body.EndsWith("`r")) { $body = $body.Substring(0, $body.Length - 1) }
                foreach ($l in @($body -split "\r?\n")) { $lines.Add($l) }
            }
            $changed = & $Mutator $lines
            if (-not $changed) { return $false }
            $out = ($lines -join $nl) + $nl
            $outBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($out)
            if ($bom) { $outBytes = [byte[]](@(0xEF, 0xBB, 0xBF) + $outBytes) }
            [void]$fs.Seek(0, [System.IO.SeekOrigin]::Begin)
            $fs.SetLength(0)
            $fs.Write($outBytes, 0, $outBytes.Length)
            $fs.Flush()
            return $true
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds (80 * ($try + 1))
        } finally {
            if ($fs) { $fs.Dispose() }
        }
    }
    return $false
}

# 메시지 한 건의 상태 칸만 바꾼다. 바꿨으면 $true(이미 그 상태이거나 행이 없으면 $false).
function Set-HandoffStatus([string]$ChannelDir, [string]$Num, [string]$Status) {
    if ($script:HandoffStatusWords -notcontains $Status) { return $false }
    $idx = Join-Path $ChannelDir "INDEX.md"
    if (-not (Test-Path -LiteralPath $idx -PathType Leaf)) { return $false }
    $script:__hoNum = $Num; $script:__hoStatus = $Status
    # 잠금 블록은 자식 범위라 안에서 대입한 값은 밖에 남지 않는다. 블록의 출력으로 돌려받는다.
    $result = Invoke-HandoffLock $ChannelDir {
        Edit-HandoffIndexFile $idx {
            param($lines)
            $hit = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $r = ConvertFrom-HandoffIndexLine $lines[$i]
                if (-not $r -or $r.Num -ne $script:__hoNum) { continue }
                if ($r.Status -eq $script:__hoStatus) { return $false }
                $cells = $lines[$i].Split([char]124)           # '' | 번호 | 시각 | 방향 | 제목 | 상태 | ''
                $cells[$cells.Length - 2] = " " + $script:__hoStatus + " "
                $lines[$i] = ($cells -join "|")
                $hit = $true
                break
            }
            return $hit
        }
    }
    return [bool]$result
}

# --------------------------------------------------------------------------------------------
# 메시지 파일
# --------------------------------------------------------------------------------------------

# 머리말(--- 사이의 "키: 값")을 해시테이블로. 없으면 빈 해시테이블.
function Read-HandoffFrontMatter([string]$Path) {
    $h = @{}
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $h }
    try {
        $lines = @(Get-Content -LiteralPath $Path -TotalCount 60 -Encoding UTF8 -ErrorAction Stop)
    } catch { return $h }
    if ($lines.Count -eq 0) { return $h }
    $first = ([string]$lines[0]).TrimStart([char]0xFEFF).Trim()
    if ($first -ne "---") { return $h }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $l = [string]$lines[$i]
        if ($l.Trim() -eq "---") { break }
        $m = [regex]::Match($l, '^\s*([^:：#\s][^:：]*?)\s*[:：]\s*(.*?)\s*$')
        if (-not $m.Success) { continue }
        $v = $m.Groups[2].Value
        $v = [regex]::Replace($v, '\s+#\s.*$', '')           # 줄 끝 주석
        $v = $v.Trim().Trim('"').Trim("'").Trim()
        $h[$m.Groups[1].Value] = $v
    }
    return $h
}

# 메시지 머리말에 모델이 없으면 넣는다(이미 있으면 그대로 둔다). 머리말이 없는 파일은 건드리지 않는다. 넣었으면 $true.
# 모델(`모델:`)과 노력(`노력:`)을 각각 따로 본다: 이미 있는 것은 그대로 두고 없는 것만 넣는다. 하나라도 넣었으면 $true.
function Set-HandoffMessageModel([string]$Path, [string]$Model, [string]$Effort = "") {
    if ((-not $Model -and -not $Effort) -or -not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = (New-Object System.Text.UTF8Encoding($false)).GetString($bytes, $(if ($hasBom) { 3 } else { 0 }), $bytes.Length - $(if ($hasBom) { 3 } else { 0 }))
    $m = [regex]::Match($text, '\A(---[ \t]*\r?\n)((?:.*?\r?\n)*?)(---[ \t]*(?:\r?\n|\z))')
    if (-not $m.Success) { return $false }
    $eol = if ($m.Groups[1].Value.EndsWith("`r`n")) { "`r`n" } else { "`n" }
    $add = ""
    if ($Model -and -not [regex]::IsMatch($m.Groups[2].Value, '(?m)^\s*모델\s*[:：]')) { $add += "모델: $Model" + $eol }
    if ($Effort -and -not [regex]::IsMatch($m.Groups[2].Value, '(?m)^\s*노력\s*[:：]')) { $add += "노력: $Effort" + $eol }
    if (-not $add) { return $false }
    $new = $m.Groups[1].Value + $m.Groups[2].Value + $add + $m.Groups[3].Value
    $text = $new + $text.Substring($m.Length)
    $out = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
    if ($hasBom) { $out = [byte[]](@(0xEF, 0xBB, 0xBF) + $out) }
    [System.IO.File]::WriteAllBytes($Path, $out)
    return $true
}

function Get-HandoffMessageFile([string]$ChannelDir, [string]$Num) {
    $msgDir = Join-Path $ChannelDir "msg"
    if (-not (Test-Path -LiteralPath $msgDir -PathType Container)) { return $null }
    $f = @(Get-ChildItem -LiteralPath $msgDir -Filter "$Num-*.md" -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1)
    if ($f.Count -gt 0) { return $f[0] }
    return $null
}

function ConvertTo-HandoffSlug([string]$Title) {
    $s = [regex]::Replace([string]$Title, '[^A-Za-z0-9가-힣_-]+', '-').Trim('-')
    if ($s.Length -gt 40) { $s = $s.Substring(0, 40).Trim('-') }
    if (-not $s) { $s = "reply" }
    return $s.ToLowerInvariant()
}

# 다음 번호: msg\ 의 가장 큰 번호와 원장의 가장 큰 번호 중 큰 쪽 + 1 (스킬 규약: 쓰기 직전에 실제로 조회).
function Get-HandoffNextNumber([string]$ChannelDir) {
    $max = 0
    $msgDir = Join-Path $ChannelDir "msg"
    if (Test-Path -LiteralPath $msgDir -PathType Container) {
        foreach ($f in @(Get-ChildItem -LiteralPath $msgDir -Filter "*.md" -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -match '^(\d{4})-') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } }
        }
    }
    foreach ($r in @(Read-HandoffIndex $ChannelDir)) { $n = [int]$r.Num; if ($n -gt $max) { $max = $n } }
    return ($max + 1)
}

# 새 메시지를 쓰고 원장에 한 줄 붙인다. 번호(문자열 4자리)를 돌려준다. 실패하면 $null.
#   $Dir: c2a | a2c. $Body 는 "## 요약" 부터 시작하는 본문(머리말은 여기서 붙인다).
function Add-HandoffMessage([string]$ChannelDir, [string]$Dir, [string]$Title, [string]$Body, [string]$ReplyTo = "", [string]$Model = "", [bool]$Auto = $false, [string]$Status = "보냄") {
    if (@("c2a", "a2c") -notcontains $Dir) { return $null }
    if ($Model -eq "(session)") { $Model = "" }          # 세션 이어가기 자리표시자는 모델명이 아니다
    $msgDir = Join-Path $ChannelDir "msg"
    New-Item -ItemType Directory -Force -Path $msgDir | Out-Null
    $idx = Join-Path $ChannelDir "INDEX.md"
    $cleanTitle = ([string]$Title -replace '[\r\n|]+', ' ' -replace '\s{2,}', ' ').Trim()
    if (-not $cleanTitle) { $cleanTitle = "(제목 없음)" }
    # 잠금 블록은 자식 범위라 안에서 대입한 값은 밖에 남지 않는다. 블록의 출력(마지막 줄)으로 번호를 돌려받는다.
    $num = Invoke-HandoffLock $ChannelDir {
        $made = $null
        for ($try = 0; $try -lt 20 -and -not $made; $try++) {
            $n = (Get-HandoffNextNumber $ChannelDir) + $try
            $numStr = ("{0:D4}" -f $n)
            $now = Get-Date -Format "yyyy-MM-dd HH:mm"
            $head = @("---", "번호: $numStr", "방향: $Dir", "시각: $now", "제목: $cleanTitle")
            if ($ReplyTo) { $head += "답장대상: $ReplyTo" }
            if ($Model) { $head += "모델: $Model" }
            if ($Auto) { $head += "자동: 예" }
            $head += "---"
            $content = (($head -join "`n") + "`n`n" + ([string]$Body).Trim() + "`n")
            $file = Join-Path $msgDir ("{0}-{1}-{2}.md" -f $numStr, $Dir, (ConvertTo-HandoffSlug $cleanTitle))
            $fs = $null
            $created = $false
            try {
                $fs = New-Object System.IO.FileStream($file, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
                $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($content)
                $fs.Write($bytes, 0, $bytes.Length)
                $created = $true
            } catch [System.IO.IOException] {
                $created = $false        # 같은 번호의 파일이 방금 생겼다: 다음 번호로
            } finally { if ($fs) { $fs.Dispose() } }
            if (-not $created) { continue }
            $script:__hoRow = ("| {0} | {1} | {2} | {3} | {4} |" -f $numStr, $now, $Dir, $cleanTitle, $Status)
            [void](Edit-HandoffIndexFile $idx {
                param($lines)
                while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) { $lines.RemoveAt($lines.Count - 1) }
                if ($lines.Count -eq 0) {
                    foreach ($h in @("# INDEX — 메시지 원장", "| 번호 | 시각 | 방향 | 제목 | 상태 |", "|---|---|---|---|---|")) { $lines.Add($h) }
                }
                $lines.Add($script:__hoRow)
                return $true
            })
            $made = $numStr
        }
        return $made
    }
    if (-not $num) { return $null }
    return [string]$num
}

# --------------------------------------------------------------------------------------------
# 자동 이어가기 상태 (AUTO.json = 상태, AUTO.off = 끄기 표시)
#   채널 폴더 안에 둔다: 펌프(워처)·Stop 훅·뷰어가 같은 파일을 본다.
# --------------------------------------------------------------------------------------------
$script:HandoffAutoWindowMinutes = 60

function Get-HandoffMaxRounds {
    if ($env:AGY_HANDOFF_MAX_ROUNDS -match '^\d+$' -and [int]$env:AGY_HANDOFF_MAX_ROUNDS -gt 0) { return [int]$env:AGY_HANDOFF_MAX_ROUNDS }
    return 6
}

# 끄기 표시: 채널 폴더의 AUTO.off, 또는 채널 루트의 AUTO.off(전체 끄기).
function Test-HandoffAutoDisabled([string]$ChannelDir) {
    if (Test-Path -LiteralPath (Join-Path $ChannelDir "AUTO.off")) { return $true }
    $root = Split-Path -Parent $ChannelDir
    if ($root -and (Test-Path -LiteralPath (Join-Path $root "AUTO.off"))) { return $true }
    return $false
}

function Read-HandoffAutoState([string]$ChannelDir) {
    $s = @{ dispatches = @(); halted = $false; halted_at = ""; halted_reason = ""; hook_blocks = @{} }
    $p = Join-Path $ChannelDir "AUTO.json"
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $s }
    try {
        $o = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($o.dispatches) {
            $s.dispatches = @(@($o.dispatches) | Where-Object { $_ } | ForEach-Object {
                @{ num = [string]$_.num; task_id = [string]$_.task_id; at = [string]$_.at; done = [bool]$_.done; tier = [string]$_.tier }
            })
        }
        $s.halted = [bool]$o.halted
        $s.halted_at = [string]$o.halted_at
        $s.halted_reason = [string]$o.halted_reason
        if ($o.hook_blocks) { foreach ($pr in $o.hook_blocks.PSObject.Properties) { $s.hook_blocks[[string]$pr.Name] = [int]$pr.Value } }
    } catch {}
    return $s
}

# 임시 파일에 쓴 뒤 바꿔 끼운다(읽는 쪽이 쓰다 만 파일을 보지 않게).
function Write-HandoffAutoState([string]$ChannelDir, $State) {
    $p = Join-Path $ChannelDir "AUTO.json"
    $tmp = $p + ".tmp"
    $disp = @(@($State.dispatches) | Where-Object { $_ } | ForEach-Object {
        [ordered]@{ num = [string]$_.num; task_id = [string]$_.task_id; at = [string]$_.at; done = [bool]$_.done; tier = [string]$_.tier }
    })
    # 오래된 기록은 버린다(최근 40건만)
    if ($disp.Count -gt 40) { $disp = @($disp[($disp.Count - 40)..($disp.Count - 1)]) }
    $blocks = [ordered]@{}
    foreach ($k in @($State.hook_blocks.Keys | Sort-Object)) { $blocks[[string]$k] = [int]$State.hook_blocks[$k] }
    $obj = [ordered]@{
        dispatches    = $disp
        halted        = [bool]$State.halted
        halted_at     = [string]$State.halted_at
        halted_reason = [string]$State.halted_reason
        hook_blocks   = $blocks
    }
    $json = $obj | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $p -Force
}

# AUTO.json 을 "읽고 고치고 쓰기" 한 번으로. $Edit 는 상태 해시테이블을 받아 그 자리에서 고친다(펌프·훅·뷰어가 서로 덮어쓰지 않게 채널 잠금 안에서).
function Update-HandoffAutoState([string]$ChannelDir, [scriptblock]$Edit) {
    Invoke-HandoffLock $ChannelDir {
        $s = Read-HandoffAutoState $ChannelDir
        [void](& $Edit $s)
        Write-HandoffAutoState $ChannelDir $s
    }
}

# 지금부터 $Minutes 분 안의 펌프 위임 횟수(한 대화 줄기의 왕복 수로 센다).
function Get-HandoffRounds($State, [int]$Minutes = 60) {
    $cut = (Get-Date).AddMinutes(-$Minutes)
    $n = 0
    foreach ($d in @($State.dispatches)) {
        if (-not $d) { continue }
        $t = [datetime]::MinValue
        if ([datetime]::TryParse([string]$d.at, [ref]$t) -and $t -ge $cut) { $n++ }
    }
    return $n
}

# --------------------------------------------------------------------------------------------
# 뷰어용 요약
# --------------------------------------------------------------------------------------------

# 메시지 파일 머리말에서 뷰어가 쓰는 것만(모델 · 답장대상 · 자동). 파일 수정 시각이 같으면 캐시를 쓴다($Cache 는 호출하는 쪽이 들고 있는 해시테이블).
function Get-HandoffMessageMeta([string]$Path, [hashtable]$Cache = $null) {
    $empty = @{ model = ""; effort = ""; replyTo = ""; auto = $false }
    if (-not $Path) { return $empty }
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) { return $empty }
    $stamp = $item.LastWriteTimeUtc.Ticks
    if ($Cache -and $Cache.ContainsKey($Path) -and $Cache[$Path].stamp -eq $stamp) { return $Cache[$Path].meta }
    $h = Read-HandoffFrontMatter $Path
    $mdl = [string]$h["모델"]
    if ($mdl -eq "(session)") { $mdl = "" }
    $meta = @{ model = $mdl; effort = [string]$h["노력"]; replyTo = [string]$h["답장대상"]; auto = ([string]$h["자동"] -eq "예") }
    if ($Cache) { $Cache[$Path] = @{ stamp = $stamp; meta = $meta } }
    return $meta
}

# 채널의 자동 이어가기 상태 요약(뷰어 API 용).
function Get-HandoffAutoSummary([string]$ChannelDir) {
    $s = Read-HandoffAutoState $ChannelDir
    $inFlight = @(@($s.dispatches) | Where-Object { $_ -and -not $_.done } | ForEach-Object { [pscustomobject]@{ num = [string]$_.num; taskId = [string]$_.task_id; at = [string]$_.at } })
    # 메시지 번호 -> 위임 작업 ID. 화면이 보냄·읽음 메시지의 진행 과정을 그 위임에서 찾아 보여 주고, 끝난 메시지도 과정을 열 수 있게 한다(최근 30건).
    $dispatches = @(@($s.dispatches) | Where-Object { $_ } | Select-Object -Last 30 | ForEach-Object { [pscustomobject]@{ num = [string]$_.num; taskId = [string]$_.task_id; at = [string]$_.at; done = [bool]$_.done; tier = [string]$_.tier } })
    return [pscustomobject]@{
        dispatches    = $dispatches
        enabled       = (-not (Test-HandoffAutoDisabled $ChannelDir))
        halted        = [bool]$s.halted
        haltedReason  = [string]$s.halted_reason
        haltedAt      = [string]$s.halted_at
        rounds        = [int](Get-HandoffRounds $s $script:HandoffAutoWindowMinutes)
        maxRounds     = [int](Get-HandoffMaxRounds)
        windowMinutes = [int]$script:HandoffAutoWindowMinutes
        inFlight      = $inFlight
    }
}

# 뷰어 버튼 동작: on(끄기 표시 지움) · off(AUTO.off 만듦) · reset(멈춤 해제 + 위임 기록·막은 횟수 비움). 알 수 없는 동작은 $false.
function Set-HandoffAutoAction([string]$ChannelDir, [string]$Action) {
    switch ($Action) {
        "on"    { Remove-Item -LiteralPath (Join-Path $ChannelDir "AUTO.off") -Force -ErrorAction SilentlyContinue; return $true }
        "off"   { New-Item -ItemType File -Force -Path (Join-Path $ChannelDir "AUTO.off") | Out-Null; return $true }
        "reset" {
            Update-HandoffAutoState $ChannelDir {
                param($s)
                $s.halted = $false; $s.halted_at = ""; $s.halted_reason = ""
                $s.hook_blocks = @{}
                # 진행 중인 위임은 남기고(끝나면 회신해야 한다), 끝난 위임 기록만 비워 왕복 수를 0으로 되돌린다
                $s.dispatches = @(@($s.dispatches) | Where-Object { $_ -and -not $_.done })
            }
            return $true
        }
        default { return $false }
    }
}
