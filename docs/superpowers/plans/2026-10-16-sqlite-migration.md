# SQLite 이전 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 위임 기록(`qa-*.jsonl`)·사용량(`usage.csv`)·agy 세션(`sessions\*.json`)을 SQLite 한 파일(`runtime\logs\agy.db`)로 옮기고, 뷰어는 같은 모양의 기록을 API 로 읽게 한다.

**Architecture:** 공용 모듈 `agy-db.ps1` 이 Windows 내장 `winsqlite3.dll`(C# P/Invoke, 컴파일 결과는 `~\.samjil\cache`에 캐시)을 감싸고, 워처·작업자·`log-qa.ps1`·`handoff-pump.ps1`·뷰어가 이것을 짧게 열고 닫는다. 동시 쓰기는 WAL + `BEGIN IMMEDIATE` + `busy_timeout`이 맡고, 같은 작업 ID 의 중복은 기본키(`ON CONFLICT`)가 막는다. 뷰어는 `GET /api/qa/records?since=<갱신 번호>`로 예전 jsonl 한 줄과 같은 모양의 기록을 증분으로 받는다.

**Tech Stack:** Windows PowerShell 5.1(C# 5 컴파일러), `winsqlite3.dll`(3.43), 브라우저 JS(`runtime/viewer/web/app.js`), node(JS 시험).

**Spec:** `docs/superpowers/specs/2026-10-16-sqlite-migration-design.md` (아래 "스펙과 달라진 점"을 함께 읽는다)

## 스펙과 달라진 점 (코드를 읽고 정한 것 — 실행 전에 스펙 문서에도 반영한다, Task 6)

- **DB 위치는 `runtime\logs\agy.db`** (스펙의 `logs\data\agy.db`가 아니다). 뷰어가 `logs\data`를 `/data/` 정적 경로로 그대로 내보내서, 거기에 두면 DB 파일이 HTTP 로 노출된다.
- **`source='usage-csv'` 행은 없다.** `usage.csv`에만 있고 기록(jsonl)에 없는 작업은 "사용량만 있고 아직 답이 비어 있는 행"(`answer IS NULL`)으로 가져온다. 예전에도 워처가 켜질 때 `Sync-QaStore`가 이런 작업을 기록으로 채웠고, 지금도 `Sync-QaStore`가 같은 일을 한다.
- **"끝난 기록" = `answer IS NOT NULL`.** 워처는 작업이 끝날 때 사용량 행을 먼저 넣고(`Write-UsageRow`), 지시파일을 `processed`로 옮긴 직후 질문·답·과정을 채운다(`Complete-TaskQaRecord`). 뷰어 API 는 끝난 기록만 내보낸다.
- **`Invoke-WithRuntimeLock`은 남긴다.** 위임 기록 경로에서는 쓰지 않지만 `watch-agy.ps1`의 `Log()`가 로그 파일 자르기에 쓴다.
- **`usage_summary.csv`(모델별 집계)는 만들지 않는다.** 필요할 때 `tools\export-usage-csv.ps1 -Summary`로 만든다. `usage.csv`의 3000줄 자르기도 없어지고, 보관 기간은 기록과 같이 12개월(`Remove-QaRecordsOlderThan`)이다.
- **`Write-Session`의 이름 키**는 예전 세션 파일 이름 규칙(금지 문자 `_`, 100자, 대소문자 무시)을 그대로 쓴다(`Get-AgySessionKey`).

## Global Constraints

- 답변·주석·화면 문구는 한국어. 기존 코드의 주석 밀도·이름·관용구를 따른다.
- **커밋·푸시는 사용자의 명시 승인이 있을 때만 한다. 푸시는 별도 단계. PR 은 만들지 않는다.** 이 계획의 각 작업은 "작업 폴더에 둔다"로 끝내고, 커밋은 모든 작업이 끝난 뒤 사용자 승인으로 한 번에 한다(Task 7).
- 커밋 메시지에 `Co-Authored-By` 줄을 넣지 않는다(사용자 규칙이 시스템 알림보다 우선).
- 푸시 전 훅(`.githooks/pre-push`)은 사용자가 시험을 요청하지 않으면 시험 없이 푸시한다. `PREPUSH_TESTS`·`PREPUSH_FULL`을 임의로 붙이지 않는다. 내 변경을 검증하려고 `tests\run-all.ps1`을 돌리는 것은 훅과 별개로 한다.
- 새·바뀐 `.ps1` 은 **UTF-8 BOM + CRLF**(Windows PowerShell 5.1). `.githooks/pre-push` 는 LF·BOM 없음. Write 도구로 만든 `.ps1` 은 LF·BOM 없음이므로 만든 직후 `Set-BomCrlf`(아래 도우미)로 바꾼다.
- Windows PowerShell 5.1 함정: 함수가 돌려주는 배열은 풀리므로 호출하는 쪽에서 `@()`로 감싼다; 비어 있는 명령 출력을 `[string]`으로 바꾸면 `$null`이 아니라 `""`; C# 은 5 문법까지(`$""`, `?.`, 식 본문 멤버 쓰지 않는다); 문자열의 `` `u{...} `` 이스케이프는 없다.
- 소스를 고친 뒤에는 `sync-installed.ps1`로 `~\.samjil` 설치본을 맞춘다. 단, 이 작업에서는 **DB 이전 전에 설치본을 동기화하지 않는다**(옛 워처와 새 작업자가 섞인다). 순서는 Task 7 의 "이 PC 에 적용"을 따른다.
- 다른 세션이 작업 중인 파일은 건드리지 않는다(`git status`로 내 변경만 있는지 확인).
- 웹 화면(`app.js`)을 바꾸므로 `frontend-design` 스킬의 원칙(화면 깜빡임·불필요한 재렌더 최소화, 기존 시각 언어 유지)을 따른다. 이 계획의 화면 변경은 데이터 로딩 방식뿐이고 보이는 모양은 그대로다.

## 작업 도우미 (저장소에 넣지 않는다)

CRLF·BOM 을 지키며 함수·줄 범위를 지우거나 바꾼다. 스크래치패드(예: `$env:TEMP\psedit.ps1`)에 만들어 `. $psedit`로 불러 쓴다. 단순한 한 곳 수정은 Edit 도구가 BOM·CRLF 를 보존하므로 Edit 를 쓴다.

```powershell
# psedit.ps1
$ErrorActionPreference = "Stop"

function Read-EditFile([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $skip = if ($bom) { 3 } else { 0 }
    $text = [Text.Encoding]::UTF8.GetString($bytes, $skip, $bytes.Length - $skip)
    return @{ Text = $text.Replace("`r`n", "`n"); Bom = $bom; Crlf = $text.Contains("`r`n") }
}

function Save-EditFile([string]$Path, $File, [string]$Text) {
    $t = if ($File.Crlf) { $Text.Replace("`n", "`r`n") } else { $Text }
    [IO.File]::WriteAllText($Path, $t, (New-Object Text.UTF8Encoding($File.Bom)))
}

function Get-FunctionRange([string]$Text, [string]$Name, [bool]$WithComments) {
    $tokens = $null; $errs = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errs)
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true)
    if (-not $fn) { throw "함수를 찾지 못했습니다: $Name" }
    $start = $fn.Extent.StartOffset
    $end = $fn.Extent.EndOffset
    if ($WithComments) {
        while ($start -ge 2) {
            $prevStart = $Text.LastIndexOf("`n", $start - 2) + 1
            $prev = $Text.Substring($prevStart, $start - $prevStart)
            if ($prev.Trim().StartsWith('#')) { $start = $prevStart } else { break }
        }
    }
    return @{ Start = $start; End = $end }
}

# 함수를 (바로 위에 붙은 # 주석 줄과 함께) 지운다.
function Remove-PsFunction([string]$Path, [string[]]$Names) {
    $f = Read-EditFile $Path
    $t = $f.Text
    foreach ($n in $Names) {
        $r = Get-FunctionRange $t $n $true
        $end = $r.End
        while ($end -lt $t.Length -and ($t[$end] -eq "`n" -or $t[$end] -eq "`r")) { $end++ }
        $t = $t.Remove($r.Start, $end - $r.Start)
    }
    Save-EditFile $Path $f $t
}

# 함수 본문만 바꾼다(위의 주석은 그대로 둔다).
function Set-PsFunction([string]$Path, [string]$Name, [string]$NewText) {
    $f = Read-EditFile $Path
    $r = Get-FunctionRange $f.Text $Name $false
    $new = $NewText.Replace("`r`n", "`n").TrimEnd("`n")
    Save-EditFile $Path $f ($f.Text.Remove($r.Start, $r.End - $r.Start).Insert($r.Start, $new))
}

# StartRegex 에 맞는 줄(정확히 한 곳)부터 그 줄 포함 처음으로 EndRegex 에 맞는 줄까지를 NewText 로 바꾼다. NewText 가 빈 글자면 지운다.
function Replace-PsLineRange([string]$Path, [string]$StartRegex, [string]$EndRegex, [string]$NewText) {
    $f = Read-EditFile $Path
    $lines = New-Object System.Collections.ArrayList
    $lines.AddRange(@($f.Text.Split("`n")))
    $starts = @(0..($lines.Count - 1) | Where-Object { ([string]$lines[$_]).TrimEnd("`r") -match $StartRegex })
    if ($starts.Count -ne 1) { throw "시작 줄이 정확히 한 곳이어야 합니다($($starts.Count)곳): $StartRegex" }
    $s = $starts[0]; $e = -1
    for ($i = $s; $i -lt $lines.Count; $i++) { if (([string]$lines[$i]).TrimEnd("`r") -match $EndRegex) { $e = $i; break } }
    if ($e -lt 0) { throw "끝 줄을 찾지 못했습니다: $EndRegex" }
    $lines.RemoveRange($s, $e - $s + 1)
    if ($NewText -ne "") { $lines.InsertRange($s, @($NewText.Replace("`r`n", "`n").TrimEnd("`n").Split("`n"))) }
    Save-EditFile $Path $f (($lines.ToArray()) -join "`n")
}

# Regex 에 맞는 줄을 모두 지우고, 지운 줄 수가 ExpectedCount 와 다르면 아무것도 쓰지 않고 멈춘다.
function Remove-PsLines([string]$Path, [string]$Regex, [int]$ExpectedCount) {
    $f = Read-EditFile $Path
    $lines = @($f.Text.Split("`n"))
    $keep = @($lines | Where-Object { -not (([string]$_).TrimEnd("`r") -match $Regex) })
    $removed = $lines.Count - $keep.Count
    if ($removed -ne $ExpectedCount) { throw "지운 줄 수가 다릅니다: 기대 $ExpectedCount / 실제 $removed ($Regex)" }
    Save-EditFile $Path $f ($keep -join "`n")
}

# 새로 만든 파일을 UTF-8 BOM + CRLF 로 바꾼다.
function Set-BomCrlf([string[]]$Paths) {
    foreach ($p in $Paths) {
        $t = [IO.File]::ReadAllText($p).Replace("`r`n", "`n").Replace("`n", "`r`n")
        [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($true)))
    }
}

# 파싱 오류가 없는지 본다.
function Test-PsSyntax([string]$Path) {
    $tokens = $null; $errs = $null
    [void][Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errs)
    if (@($errs).Count -gt 0) { throw ("문법 오류 {0}건: {1}" -f @($errs).Count, $errs[0].Message) }
}
```

이후 단계의 `$repo` 는 `D:\Repos\github.com\samjil\skills` 이다.

## 파일 구조

| 파일 | 책임 | 작업 |
|---|---|---|
| `runtime/delegate-agy/scripts/sub/agy-db.ps1` (새) | SQLite 래퍼·스키마·기록(tasks)·세션·meta·뷰어 API 본문 | Task 1 |
| `runtime/delegate-agy/scripts/sub/common.ps1` | 파일 저장 함수 제거, `New-QaRecord`·세션 함수를 DB 위로 | Task 2 |
| `runtime/delegate-agy/scripts/sub/log-qa.ps1` | DB 에 `InsertOnly`로 기록 | Task 2 |
| `runtime/delegate-agy/scripts/sub/watch-agy.ps1` | 사용량·기록 마무리·보충·보관 정리를 DB 로 | Task 3 |
| `runtime/delegate-agy/scripts/sub/handoff-pump.ps1` | 사용량 행·세션 모델을 DB 에서 | Task 3 |
| `runtime/viewer/serve-viewer.ps1` | `/api/qa/records`, 세션 조회, 데이터 폴더 감지 | Task 4 |
| `runtime/viewer/web/app.js`, `index.html` | `loadAllQa`를 증분 API 로 | Task 4 |
| `tools/export-usage-csv.ps1` (새) | 필요할 때 CSV 내보내기 | Task 5 |
| `tools/migrate-to-sqlite.ps1` (새) | 한 번에 가져오기·검증·원본 보관·되돌리기 | Task 5 |
| `sync-installed.ps1`, `uninstall.ps1`, README, SKILL.md, 스펙 | 후속 정리와 문서 | Task 6 |
| `tests/delegate-agy/agy-db.tests.ps1` (새) 외 | 시험 | 각 작업 |

검증된 시제품: `docs/superpowers/plans/2026-10-16-sqlite-migration.assets/` 의 `agy-db.ps1.txt`(모듈)와 `agy-db.tests.ps1.txt`(56개 시험, 임시 폴더에서 전부 통과를 확인했다. 컴파일 첫 실행 약 0.5초, 캐시 적중 시 약 0.25초, 6개 프로세스 동시 쓰기 120건 손실 0). Task 1 은 이 두 파일을 제자리에 복사한다.

---

### Task 1: DB 모듈 `agy-db.ps1`

**Files:**
- Create: `runtime/delegate-agy/scripts/sub/agy-db.ps1` (자산 `agy-db.ps1.txt`를 복사)
- Create: `tests/delegate-agy/agy-db.tests.ps1` (자산 `agy-db.tests.ps1.txt`를 복사)

**Interfaces:**
- Produces (이후 작업이 쓴다): `Initialize-AgySqlite`, `Open-AgyDb [string]$Path [int]$BusyMs` → `[AgySqlite.Db]`(`Execute($sql,[object[]]$args)`→변경 행 수, `Query($sql,[object[]]$args)`→`List<Dictionary<string,object>>`, `Dispose()`), `Invoke-AgyDbTransaction $Db [scriptblock]$Body`, `Test-AgyDbTransient $ErrorRecord`, `$script:QaRecordFields`, `Save-QaRecord $Db [IDictionary]$Record [string]$Mode('Upsert'|'InsertOnly'|'FillIfIncomplete')`→`[bool]`, `Write-QaRecordToDb [string]$DbPath $Record [string]$Mode`→`'saved'|'skipped'|'pending'`, `Save-PendingQaRecord`, `Import-PendingQaRecords`, `Get-AgyPendingDir`, `Get-QaTaskRow [string]$DbPath [string]$TaskId`→행 객체 또는 `$null`, `Get-QaIncompleteRows [string]$DbPath`→행 객체 배열, `Remove-QaRecordsOlderThan [string]$DbPath [int]$Months`→지운 수, `Get-QaRecordsJson [string]$DbPath [long]$Since`→JSON 글자, `Get-AgySessionKey`, `Get-AgySessionRow $Db $Key`, `Set-AgySessionRow $Db $Key $ConversationId $Cwd $Model $CreatedAt $LastUsedAt $TurnCount`, `Get-AgySession [string]$DbPath [string]$Name`, `Remove-AgySessionsOlderThan [string]$DbPath [int]$Days`, `ConvertFrom-AgyJsonArray`, `ConvertTo-AgyProcessJson`, `ConvertTo-AgyJsonString`, `Get-AgyMeta`/`Set-AgyMeta $Db`.
- 환경변수 `AGY_DB_CACHE_DIR`: 컴파일 캐시 폴더 재정의(시험용). 기본 `~\.samjil\cache`.

- [ ] **Step 1: 작업 도우미 만들기**

위 "작업 도우미"의 `psedit.ps1` 을 `$env:TEMP\psedit.ps1` 로 저장한다(Write 도구).

- [ ] **Step 2: 모듈과 시험을 제자리에 복사하고 BOM + CRLF 로 맞춘다**

```powershell
$repo = "D:\Repos\github.com\samjil\skills"
. "$env:TEMP\psedit.ps1"
$assets = Join-Path $repo "docs\superpowers\plans\2026-10-16-sqlite-migration.assets"
Copy-Item (Join-Path $assets "agy-db.ps1.txt") (Join-Path $repo "runtime\delegate-agy\scripts\sub\agy-db.ps1") -Force
Copy-Item (Join-Path $assets "agy-db.tests.ps1.txt") (Join-Path $repo "tests\delegate-agy\agy-db.tests.ps1") -Force
Set-BomCrlf @((Join-Path $repo "runtime\delegate-agy\scripts\sub\agy-db.ps1"), (Join-Path $repo "tests\delegate-agy\agy-db.tests.ps1"))
Test-PsSyntax (Join-Path $repo "runtime\delegate-agy\scripts\sub\agy-db.ps1")
```

- [ ] **Step 3: 시험을 돌린다**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-db.tests.ps1`
Expected: 마지막 줄 `통과 56 / 실패 0`, 약 5초.

- [ ] **Step 4: 위생 시험이 새 파일을 받아들이는지 본다**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 -Only hygiene`
Expected: 실패 0. 실패하면 메시지가 말하는 BOM·CRLF·줄 끝 문제를 `Set-BomCrlf`로 고친다.

- [ ] **Step 5: 작업 폴더에 둔다 (커밋하지 않는다)**

`git status --short` 에 `agy-db.ps1`, `agy-db.tests.ps1`, `docs/superpowers/**` 만 새로 보이는지 확인한다.

---

### Task 2: 공용 함수(common.ps1)·log-qa.ps1 을 DB 위로

**Files:**
- Modify: `runtime/delegate-agy/scripts/sub/common.ps1`
- Modify: `runtime/delegate-agy/scripts/sub/log-qa.ps1`
- Modify: `tests/delegate-agy/cwd-list.tests.ps1` (전체 교체)

**Interfaces:**
- Consumes: Task 1 의 `Get-AgySession`, `Open-AgyDb`, `Invoke-AgyDbTransaction`, `Get-AgySessionRow`, `Set-AgySessionRow`, `Get-AgySessionKey`, `Remove-AgySessionsOlderThan`, `Write-QaRecordToDb`, `$script:QaRecordFields`.
- Produces: 전역 변수 계약 `$AgyDbPath`(이 파일을 dot-source 하는 스크립트가 정의). `Read-Session [string]$Name`→세션 객체(`name, conversation_id, cwd[], model, created_at, last_used_at, turn_count`) 또는 `$null`, `Write-Session [string]$Name [string]$ConversationId [string[]]$Cwd [string]$Model`, `Remove-StaleSessions [int]$MaxAgeDays`, `New-QaRecord`(그대로), `Invoke-WithRuntimeLock`(그대로).
- 없어지는 함수: `Get-QaShardFiles`, `Get-QaShardPath`, `Add-QaLine`, `Test-QaTaskIdInShardTail`, `Test-QaTaskIdInRecentShards`, `Add-QaRecordUnlocked`, `Get-SafeSessionFileName`, `Get-SessionPath`.

- [ ] **Step 1: 지우거나 바꾸기 전에 쓰는 곳을 확인한다**

Run (Grep 도구): 패턴 `Get-QaShardFiles|Get-QaShardPath|Add-QaLine|Test-QaTaskIdIn|Add-QaRecordUnlocked|Get-SafeSessionFileName|Get-SessionPath|ConvertTo-ReadableJson` 를 `runtime/`, `tools/`, `tests/`, `*.ps1`(저장소 루트)에서 찾는다.
Expected: `runtime/delegate-agy/scripts/sub/common.ps1`(정의), `watch-agy.ps1`(Task 3 에서 바꿈), `tests/delegate-agy/cwd-list.tests.ps1`·`qa-store.tests.ps1`(이 계획이 다시 쓴다)뿐이다. `ConvertTo-ReadableJson` 은 남긴다(Task 5 되돌리기가 쓴다). 다른 곳이 나오면 그 곳도 이 계획의 해당 작업에서 처리한다.

- [ ] **Step 2: common.ps1 에서 파일 저장 함수와 세션 파일 함수를 지운다**

```powershell
$repo = "D:\Repos\github.com\samjil\skills"
. "$env:TEMP\psedit.ps1"
$c = Join-Path $repo "runtime\delegate-agy\scripts\sub\common.ps1"
Remove-PsFunction -Path $c -Names @('Get-QaShardFiles','Get-QaShardPath','Add-QaLine','Test-QaTaskIdInShardTail','Test-QaTaskIdInRecentShards','Add-QaRecordUnlocked','Get-SafeSessionFileName','Get-SessionPath')
Test-PsSyntax $c
```

- [ ] **Step 3: 세션 함수 세 개를 DB 위로 바꾼다**

```powershell
Set-PsFunction -Path $c -Name 'Read-Session' -NewText @'
function Read-Session([string]$Name) {
    try { return (Get-AgySession $AgyDbPath $Name) } catch { return $null }
}
'@

Set-PsFunction -Path $c -Name 'Write-Session' -NewText @'
function Write-Session([string]$Name, [string]$ConversationId, [string[]]$Cwd, [string]$Model) {
    $key = Get-AgySessionKey $Name
    $db = Open-AgyDb $AgyDbPath
    try {
        # 읽고-고쳐-쓰는 구간을 한 트랜잭션으로 묶는다: 같은 세션을 두 작업자가 거의 동시에 마쳐도 횟수가 하나씩 늘어난다
        Invoke-AgyDbTransaction $db {
            $existing = Get-AgySessionRow $db $key
            $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $createdAt = if ($existing -and $existing.created_at) { [string]$existing.created_at } else { $now }
            $turnCount = 1
            if ($existing -and $existing.turn_count) { $turnCount = [int]$existing.turn_count + 1 }

            # 세션을 이어가는 호출은 실제 모델명을 모르고 "(session)" 자리표시자만 넘어옵니다
            # (watch-agy.ps1의 Invoke-AgyWithFallback 참고). 그걸 그대로 덮어쓰면 세션을 시작할 때
            # 기록해둔 진짜 모델명이 다음 호출부터 영영 사라지므로, 그럴 땐 기존 값을 유지합니다.
            $resolvedModel = $Model
            if ((-not $resolvedModel) -or ($resolvedModel -eq "(session)")) {
                if ($existing -and $existing.model) { $resolvedModel = [string]$existing.model }
            }
            Set-AgySessionRow $db $key $ConversationId @(ConvertTo-CwdList $Cwd) $resolvedModel $createdAt $now $turnCount
        }
    } finally { $db.Dispose() }
}
'@

Set-PsFunction -Path $c -Name 'Remove-StaleSessions' -NewText @'
function Remove-StaleSessions([int]$MaxAgeDays = 30) {
    try { [void](Remove-AgySessionsOlderThan $AgyDbPath $MaxAgeDays) } catch {}
}
'@
Test-PsSyntax $c
```

- [ ] **Step 4: `New-QaRecord`가 칸 목록을 모듈과 같이 쓰게 하고, 머리말·주석을 고친다**

```powershell
Replace-PsLineRange -Path $c -StartRegex '^\s+\$fields = @\(''timestamp''' -EndRegex '''process''\)\s*$' -NewText '    $fields = $script:QaRecordFields    # 칸 목록은 agy-db.ps1 에 있다(저장소와 뷰어 API 가 같은 목록을 쓴다)'

Replace-PsLineRange -Path $c -StartRegex '^# common\.ps1\s*$' -EndRegex '^#   \$SessionsDir\s' -NewText @'
# common.ps1
# watch-agy.ps1과 log-qa.ps1이 함께 쓰는 헬퍼 모음입니다(위임 기록 틀, 세션 연속성, 폴더 목록 규칙).
# dot-source해서 씁니다: `. (Join-Path $PSScriptRoot "common.ps1")`
#
# 기록과 세션은 SQLite(runtime\logs\agy.db)에 있고, 접근은 같은 폴더의 agy-db.ps1 이 맡습니다. 이 파일은 그 위에 도메인 규칙만 얹습니다.
#
# 왜 따로 뺐는가: 예전에 이 함수들이 두 파일에 복사돼 있었는데, 한쪽만 고치고 다른 쪽을
# 놓치면 같은 버그(예: ETS 속성이 붙은 문자열을 그대로 직렬화해 레코드가 수십 MB로
# 부풀던 문제)가 조용히 재발할 수 있었습니다. 한 곳에서만 관리하도록 통합했습니다.
#
# 이 파일을 dot-source하는 스크립트는 아래 변수를 먼저 정의해 둬야 합니다:
#   $AgyDbPath  - runtime\logs\agy.db 경로
'@

Replace-PsLineRange -Path $c -StartRegex '^# 세션 하나당 파일 하나' -EndRegex '^# 대한 동시 쓰기 경쟁은' -NewText @'
# 세션 하나당 agy_sessions 표의 한 줄(agy.db)로 관리합니다. 작업자가 여럿 동시에 돌 수 있어서 읽고-고쳐-쓰는 구간(Write-Session)은
# DB 트랜잭션(BEGIN IMMEDIATE) 안에서 합니다. 예전의 세션 파일은 tools\migrate-to-sqlite.ps1 이 한 번에 가져옵니다.
'@
Test-PsSyntax $c
```

Edit 도구로 두 군데를 더 고친다.

1. `common.ps1` 에서 old_string `# PowerShell 5.1의 ConvertTo-Json은 한글 등 비ASCII 문자를 유니코드 이스케이프로 바꿔버려서` 를 아래로 바꾼다(앞에 모듈 불러오기를 끼운다):

```powershell
# DB 접근 모듈(agy-db.ps1). 이 파일과 같은 폴더에 있다.
$agyDbModule = Join-Path $PSScriptRoot "agy-db.ps1"
if (-not (Test-Path -LiteralPath $agyDbModule)) { $agyDbModule = Join-Path (Split-Path $PSScriptRoot -Parent) "agy-db.ps1" }
. $agyDbModule

# PowerShell 5.1의 ConvertTo-Json은 한글 등 비ASCII 문자를 유니코드 이스케이프로 바꿔버려서
```

2. old_string `# 기록 저장소(qa-*.jsonl)에 넣을 레코드 하나를 만든다.` → new_string `# 기록 저장소(agy.db 의 tasks 표)에 넣을 레코드 하나를 만든다.`

- [ ] **Step 5: log-qa.ps1 을 DB 로 쓰게 바꾼다**

Edit 도구로 `runtime/delegate-agy/scripts/sub/log-qa.ps1` 을 고친다.

(a) 머리 주석 한 줄: old_string `# watch-agy.ps1가 관리하는 것과 같은 기록 저장소(runtime\logs\data\qa-*.jsonl)에` → new_string `# watch-agy.ps1가 관리하는 것과 같은 기록 저장소(runtime\logs\agy.db 의 tasks 표)에`

(b) 사용량 주석: old_string `# usage.csv/usage_summary.csv는 건드리지 않습니다 (그건 watch-agy.ps1이 실제 agy CLI` 로 시작하는 3줄(`# 호출의 토큰/비용을 집계하는 원장이라, 성격이 다른 MCP 호출을 섞으면 집계가 왜곡됩니다).` 까지)을 Replace-PsLineRange 로 바꾼다:

```powershell
Replace-PsLineRange -Path (Join-Path $repo "runtime\delegate-agy\scripts\sub\log-qa.ps1") -StartRegex '^# usage\.csv/usage_summary\.csv는 건드리지 않습니다' -EndRegex '^# 호출의 토큰/비용을 집계' -NewText @'
# 이 기록은 토큰·소요시간 칸이 비어 있고 source 칸이 채워져 있습니다. 모델별 사용량 집계(tools\export-usage-csv.ps1 -Summary)는
# source 가 빈 행(워처가 실제 agy CLI 를 부른 작업)만 세므로, 성격이 다른 MCP 호출이 섞여 집계가 왜곡되지 않습니다.
'@
```
끝 줄 정규식이 맞지 않으면 파일에서 해당 주석 3줄의 마지막 줄 일부를 읽어 `-EndRegex` 를 고친다.

(c) 경로 변수: old_string
```
$DataDir     = Join-Path $RuntimeDir "logs\data"
$QaIndexFile = Join-Path $DataDir "index.json"
$QaShardMaxBytes = 5MB
```
→ new_string
```
$AgyDbPath = Join-Path $RuntimeDir "logs\agy.db"
```

(d) old_string `New-Item -ItemType Directory -Force -Path $DataDir | Out-Null\n\nif (-not $TaskId) {` 의 `New-Item ... $DataDir` 한 줄을 지운다. 줄이 정확히 `New-Item -ItemType Directory -Force -Path $DataDir | Out-Null` 하나뿐이므로 Edit 로 그 줄만 old_string 으로 잡아 빈 글자로 바꾼다.

(e) 공용 함수 주석: old_string `# ConvertTo-ReadableJson / Get-QaShardFiles / Get-QaShardPath는 watch-agy.ps1과 공유합니다` → new_string `# New-QaRecord / Truncate-Text 등은 watch-agy.ps1과 공유합니다`

(f) 저장 부분: old_string 의 `$shardPath = Invoke-WithRuntimeLock {` 부터 `Write-Host "기록 저장: task_id=$TaskId source=$Source -> $shardPath"` 까지 (끝 `}` 포함 한 블록)를 Replace-PsLineRange 로 바꾼다:

```powershell
Replace-PsLineRange -Path (Join-Path $repo "runtime\delegate-agy\scripts\sub\log-qa.ps1") -StartRegex '^\$shardPath = Invoke-WithRuntimeLock \{' -EndRegex '^Write-Host "기록 저장:' -NewText @'
# 같은 작업 ID 가 이미 있으면 덮어쓰지 않고 오류로 알린다(InsertOnly). DB 를 잠깐 못 쓰면 pending 폴더에 두었다가 다음 기록 때 가져온다.
$result = Write-QaRecordToDb $AgyDbPath $rec 'InsertOnly'
if ($result -eq 'skipped') { throw "이미 존재하는 task_id입니다: $TaskId" }
$note = if ($result -eq 'pending') { " (DB 가 잠겨 있어 pending 폴더에 두었습니다. 다음 기록 때 가져옵니다)" } else { "" }
Write-Host "기록 저장: task_id=$TaskId source=$Source -> $AgyDbPath$note"
'@
Test-PsSyntax (Join-Path $repo "runtime\delegate-agy\scripts\sub\log-qa.ps1")
```

- [ ] **Step 6: `cwd-list.tests.ps1` 을 DB 기준으로 다시 쓴다 (Write 후 `Set-BomCrlf`)**

`tests/delegate-agy/cwd-list.tests.ps1` 전체를 아래로 바꾼다.

```powershell
# @cwd 여러 폴더: 세션 저장/읽기(common.ps1, SQLite)와 뷰어(serve-viewer.ps1)의 폴더 목록 규칙 테스트. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\cwd-list.tests.ps1
# 임시 폴더의 DB 만 씁니다. 실제 기록(runtime\logs\agy.db)은 건드리지 않습니다(몇 초).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}
function Assert-True($name, $cond) { Assert-Equal $name $true [bool]$cond }

function Get-FunctionText($path, $name) {
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name 를 $path 에서 찾지 못했습니다." }
    return $fn.Extent.Text
}

# 창 없이 PowerShell 을 띄워 종료 코드와 출력(UTF-8)을 돌려준다
function Invoke-HiddenPs([string[]]$ArgumentList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = (@($ArgumentList | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
    try { $p.StandardInput.Close() } catch {}
    $p.WaitForExit()
    $text = [string]$outTask.Result + [string]$errTask.Result
    $code = $p.ExitCode
    $p.Dispose()
    return @{ Code = $code; Out = $text }
}

$commonPath = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\common.ps1"
$viewerPath = Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"

$work = Join-Path ([IO.Path]::GetTempPath()) ("cwd-list-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
$AgyDbPath = Join-Path $work "logs\agy.db"
. $commonPath
# 뷰어의 같은 이름 함수(사본)는 다른 이름으로 불러 와서 비교한다
Invoke-Expression ((Get-FunctionText $viewerPath "ConvertTo-CwdList").Replace("function ConvertTo-CwdList", "function ConvertTo-CwdListViewer"))

Write-Host "뷰어의 ConvertTo-CwdList 는 common.ps1 의 것과 같은 규칙이다(사본이 어긋나지 않게)"
$cases = @(
    @($null), @(""), @("D:\a"), @("D:\a", "D:\b"), @("D:\Repo", "d:\repo\", "D:\REPO/", "D:\other"),
    @("  D:\x  ", "", "   ", $null, "D:\y"), @("\"), @("/", "\"), @("C:\"), @("C:\", "c:")
)
$same = $true; $diff = ""
foreach ($c in $cases) {
    $a = (@(ConvertTo-CwdList $c) -join "|")
    $b = (@(ConvertTo-CwdListViewer $c) -join "|")
    if ($a -ne $b) { $same = $false; $diff += " [$($c -join ',')]: common=$a viewer=$b" }
}
Assert-Equal "  여러 입력에서 두 함수의 결과가 같다$diff" $true $same

try {
    Write-Host "세션: 폴더 목록 저장"
    Write-Session -Name "multi" -ConversationId "conv-1" -Cwd @("D:\a\repo", "D:\b\docs") -Model "gemini-3.8-flash-medium"
    $s = Read-Session "multi"
    Assert-Equal "폴더 둘을 cwd 배열로 저장한다" "D:\a\repo|D:\b\docs" (@($s.cwd) -join "|")
    Assert-Equal "  나머지 항목은 그대로(대화 id·모델·횟수)" "conv-1|gemini-3.8-flash-medium|1" ("{0}|{1}|{2}" -f $s.conversation_id, $s.model, $s.turn_count)
    Write-Session -Name "one" -ConversationId "conv-2" -Cwd @("D:\only") -Model "m"
    Assert-Equal "폴더가 하나여도 배열로 저장한다" "D:\only|1" ("{0}|{1}" -f (@((Read-Session "one").cwd) -join "|"), @((Read-Session "one").cwd).Count)
    Write-Session -Name "none" -ConversationId "conv-3" -Cwd @() -Model "m"
    Assert-Equal "폴더가 없으면 빈 배열" 0 @((Read-Session "none").cwd).Count
    Write-Session -Name "dup" -ConversationId "conv-4" -Cwd @("D:\a", "d:\A\", "D:\b") -Model "m"
    Assert-Equal "저장할 때도 중복을 한 번만 남긴다" "D:\a|D:\b" (@((Read-Session "dup").cwd) -join "|")
    Write-Session -Name "strarg" -ConversationId "conv-5" -Cwd "D:\single-string" -Model "m"
    Assert-Equal "문자열 하나를 넘겨도(예전 호출 방식) 배열 하나로 저장한다" "D:\single-string|1" ("{0}|{1}" -f (@((Read-Session "strarg").cwd) -join "|"), @((Read-Session "strarg").cwd).Count)

    Write-Host "세션: 이어가기"
    Write-Session -Name "multi" -ConversationId "conv-1b" -Cwd @("D:\a\repo") -Model "(session)"
    $s2 = Read-Session "multi"
    Assert-Equal "이어간 뒤 횟수가 늘고 모델 자리표시자는 기존 모델을 지우지 않는다" "2|gemini-3.8-flash-medium|conv-1b" ("{0}|{1}|{2}" -f $s2.turn_count, $s2.model, $s2.conversation_id)
    Assert-Equal "  폴더는 이번 목록으로 바뀐다" "D:\a\repo" (@($s2.cwd) -join "|")
    Assert-Equal "  처음 만든 시각은 그대로" $s.created_at $s2.created_at
    Assert-Equal "이름은 대소문자를 가리지 않는다" "conv-1b" (Read-Session "MULTI").conversation_id
    Assert-Equal "없는 세션은 null(= 새 세션)" $true ($null -eq (Read-Session "없는-세션"))

    Write-Host "이어가기 규칙(세션 고정)"
    Assert-Equal "예전처럼 문자열 하나로 들어온 폴더도 목록 하나로 풀린다" "D:\legacy\proj" (@(Resolve-TaskCwds @() "D:\legacy\proj") -join "|")
    Assert-Equal "  이번 호출에 @cwd 가 있으면 예전 폴더는 쓰지 않는다" "D:\new" (@(Resolve-TaskCwds @("D:\new") "D:\legacy\proj") -join "|")
    $sess = Read-Session "dup"
    Assert-Equal "이번 호출에 @cwd 가 없으면 세션의 두 폴더를 그대로 쓴다" "D:\a|D:\b" (@(Resolve-TaskCwds @() $sess.cwd) -join "|")
    Assert-Equal "이번 호출에 @cwd 가 하나라도 있으면 이번 목록만 쓴다(합치지 않는다)" "D:\c" (@(Resolve-TaskCwds @("D:\c") $sess.cwd) -join "|")

    Write-Host "오래 안 쓴 세션 정리"
    $dbx = Open-AgyDb $AgyDbPath
    Invoke-AgyDbTransaction $dbx { Set-AgySessionRow $dbx "ancient" "c" @() "m" "2020-01-01 00:00:00" "2020-01-01 00:00:00" 1 }
    $dbx.Dispose()
    Remove-StaleSessions -MaxAgeDays 30
    Assert-Equal "30일 넘게 안 쓴 세션은 지워진다" $true ($null -eq (Read-Session "ancient"))
    Assert-Equal "  방금 쓴 세션은 남는다" "conv-1b" (Read-Session "multi").conversation_id

    Write-Host "log-qa.ps1 검증"
    $logQaScript = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\log-qa.ps1"
    $qFile = Join-Path $work "q.txt"
    $aFile = Join-Path $work "a.txt"
    [System.IO.File]::WriteAllText($qFile, "질문", [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($aFile, "답변", [System.Text.Encoding]::UTF8)
    $r1 = Invoke-HiddenPs @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $logQaScript, "-RuntimeDir", $work, "-TaskId", "task_log_qa_test", "-Source", "mcp", "-QuestionFile", $qFile, "-AnswerFile", $aFile)
    Assert-Equal "종료 코드 0" 0 $r1.Code
    Assert-True "출력에 '기록 저장:' 과 작업 ID 가 있다" ($r1.Out -match '기록 저장:\s*task_id=task_log_qa_test')
    Assert-True "  출력 끝이 DB 경로다" ($r1.Out -match '->\s*.+agy\.db')
    $row = Get-QaTaskRow $AgyDbPath "task_log_qa_test"
    Assert-Equal "  DB 에 질문·답·출처가 들어간다" "질문|답변|mcp" ("{0}|{1}|{2}" -f ([string]$row.question).Trim(), ([string]$row.answer).Trim(), $row.source)
    Assert-True "  끝난 기록(answer 가 NULL 이 아님)이다" ($null -ne $row.answer)
    $r2 = Invoke-HiddenPs @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $logQaScript, "-RuntimeDir", $work, "-TaskId", "task_log_qa_test", "-Source", "mcp", "-QuestionFile", $qFile, "-AnswerFile", $aFile)
    Assert-True "같은 작업 ID 를 또 기록하면 실패한다" ($r2.Code -ne 0)
    Assert-True "  이유가 '이미 존재'로 보인다" ($r2.Out -match '이미 존재')
    $json = ConvertFrom-Json -InputObject (Get-QaRecordsJson $AgyDbPath 0)
    Assert-Equal "  그래도 기록은 한 건뿐이다" 1 $json.total

    # uninstall.ps1 BOM 없음 검증
    $unPath = Join-Path $repoRoot "uninstall.ps1"
    $unBytes = [System.IO.File]::ReadAllBytes($unPath)
    $hasBom = ($unBytes.Length -ge 3 -and $unBytes[0] -eq 0xEF -and $unBytes[1] -eq 0xBB -and $unBytes[2] -eq 0xBF)
    Assert-Equal "uninstall.ps1 파일 맨 앞에 UTF-8 BOM 없음" $false $hasBom
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
```

```powershell
Set-BomCrlf @((Join-Path $repo "tests\delegate-agy\cwd-list.tests.ps1"))
```

- [ ] **Step 7: 시험을 돌린다**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\cwd-list.tests.ps1`
Expected: `통과 N / 실패 0`. 실패하면 메시지의 기대·실제를 보고 `common.ps1`·`log-qa.ps1`을 고친다(시험을 약하게 바꾸지 않는다).
Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-db.tests.ps1`
Expected: `통과 56 / 실패 0`.

- [ ] **Step 8: 작업 폴더에 둔다 (커밋하지 않는다)**

---

### Task 3: 워처(watch-agy.ps1)·핸드오프 펌프·관련 시험

**Files:**
- Modify: `runtime/delegate-agy/scripts/sub/watch-agy.ps1`
- Modify: `runtime/delegate-agy/scripts/sub/handoff-pump.ps1`
- Modify: `tests/delegate-agy/qa-store.tests.ps1` (전체 교체)
- Modify: `tests/delegate-agy/watch-agy-model.e2e.tests.ps1`
- Modify: `tests/handoff/handoff-pump.tests.ps1`

**Interfaces:**
- Consumes: Task 1·2 의 함수들.
- Produces (`watch-agy.ps1` 안): `$AgyDbPath`, `Write-UsageRow`(시그니처 그대로: `$taskId $model $attempts $triedModels $inputTokens $outputTokens $thinkingTokens $totalTokens $elapsedSec $status [string]$session [string]$sessionId`), `Initialize-QaStore`(보관 기간 정리), `New-QaRecordFromRow $r [string]$QuestionPath`(그대로), `Sync-QaStore`→채운 건수, `Complete-TaskQaRecord [string]$TaskId [string]$SourcePath [string]$DonePath`, `Update-QAReport`(= `Sync-QaStore`).
- 없어지는 것: `$UsageCsv`, `$SummaryCsv`, `$UsageCsvHeader`, `$script:FirstUsageRow`, `Write-UsageRowUnlocked`, `Update-UsageSummary(Unlocked)`, `$DataDir`, `$QaIndexFile`, `$QaShardMaxBytes`, `$SessionsDir`, `$script:QaKnownIds`, `$script:QaTotal`, `Update-QaIndex`, `Get-QaIndexTotal`, `Update-QAReportUnlocked`.
- handoff-pump 의 컨텍스트 해시가 `UsageCsv`·`SessionsDir` 대신 `DbPath` 를 받는다.

- [ ] **Step 1: 시험을 먼저 다시 쓴다 — `qa-store.tests.ps1` 전체 교체 (Write 후 `Set-BomCrlf`)**

```powershell
# 위임 기록 저장소(SQLite) 쓰기 경로 시험. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\qa-store.tests.ps1
# 작업자가 작업 하나를 끝낼 때 그 작업 한 건만 채우는지(Complete-TaskQaRecord), 사용량 행이 먼저 들어가는지(Write-UsageRow),
# 중복·오류 경로·보충(Sync-QaStore)·보관 기간 정리(Initialize-QaStore)를 확인합니다.
# 워처 본체는 실행하지 않고 watch-agy.ps1/common.ps1 에서 함수만 꺼내 임시 폴더에서 돌립니다. 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$subDir   = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

# --- 임시 런타임 ---
$work = Join-Path ([IO.Path]::GetTempPath()) ("qa-store-test-" + [Guid]::NewGuid().ToString("N"))
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
$RuntimeDir   = $work
$LogsDir      = Join-Path $work "logs"
$AgyDbPath    = Join-Path $LogsDir "agy.db"
$InboxDir     = Join-Path $work "inbox"
$OutboxDir    = Join-Path $work "outbox"
$ProcessedDir = Join-Path $work "processed"
$ComputerName = "TESTPC"
$QaKeepMonths = 12; $QaProcessMaxSteps = 400
foreach ($d in @($LogsDir, $InboxDir, $OutboxDir, $ProcessedDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
function Log($msg) { }

. (Join-Path $subDir "common.ps1")
. (Join-Path $subDir "agy-progress.ps1")

# --- watch-agy.ps1 에서 필요한 정의만 꺼내 옵니다(워처 본체는 실행하지 않음) ---
$tokens = $null; $errs = $null
$astWatch = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $subDir "watch-agy.ps1"), [ref]$tokens, [ref]$errs)
Assert-Equal "watch-agy.ps1 에 문법 오류가 없다" 0 @($errs).Count
foreach ($name in @("Write-UsageRow", "Initialize-QaStore", "New-QaRecordFromRow", "Sync-QaStore", "Update-QAReport", "Complete-TaskQaRecord")) {
    $fn = $astWatch.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "$name 를 watch-agy.ps1 에서 찾지 못했습니다." }
    Invoke-Expression $fn.Extent.Text
}

# 작업자 프로세스 하나가 하는 일을 흉내 낸다: 지시파일·응답을 두고 사용량 행을 쓴다
function New-TaskFixture([string]$Id, [string]$Status = "OK", [bool]$WithUsage = $true) {
    Set-Content -LiteralPath (Join-Path $InboxDir "$Id.md") -Value "질문 $Id" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $OutboxDir "$Id.response.md") -Value "답 $Id" -Encoding UTF8
    if (-not $WithUsage) { return }
    if ($Status -eq "OK") { Write-UsageRow $Id "gemini-x" 1 "gemini-x" 10 20 5 35 12.3 "OK" "" "" }
    else { Write-UsageRow $Id $null $null "gemini-x" $null $null $null $null $null "ERROR" "" "" }
}
function Complete-Fixture([string]$Id) {
    Complete-TaskQaRecord $Id (Join-Path $InboxDir "$Id.md") (Join-Path $ProcessedDir "$Id.md")
}
function Get-Done { return (ConvertFrom-Json -InputObject (Get-QaRecordsJson $AgyDbPath 0)) }

try {
    Write-Host "Write-UsageRow: 사용량 행이 먼저 들어간다 (아직 끝난 기록이 아니다)"
    New-TaskFixture "task-a"
    $row = Get-QaTaskRow $AgyDbPath "task-a"
    Assert-Equal "행이 생긴다" "gemini-x|10|20|5|35|OK|TESTPC" ("{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f $row.model, $row.input_tokens, $row.output_tokens, $row.thinking_tokens, $row.total_tokens, $row.status, $row.computer_name)
    Assert-Equal "  시각이 들어 있다" $true ([bool]$row.timestamp)
    Assert-Equal "  질문·답은 아직 NULL" $true (($null -eq $row.question) -and ($null -eq $row.answer))
    Assert-Equal "  끝난 기록은 0건(뷰어에 안 보인다)" 0 (Get-Done).total
    Write-UsageRow "task-a" "OTHER" 9 "x" 9 9 9 9 9 "ERROR" "" ""
    Assert-Equal "  같은 작업 ID 의 사용량 행을 또 쓰면 먼저 쓴 것이 남는다" "gemini-x" (Get-QaTaskRow $AgyDbPath "task-a").model

    Write-Host "Complete-TaskQaRecord: 작업 한 건을 채운다"
    Complete-Fixture "task-a"
    $row = Get-QaTaskRow $AgyDbPath "task-a"
    Assert-Equal "질문은 processed 로 옮긴 지시파일 내용" "질문 task-a" ([string]$row.question).Trim()
    Assert-Equal "  답은 outbox 응답 내용" "답 task-a" ([string]$row.answer).Trim()
    Assert-Equal "  사용량 칸이 그대로 있다" "gemini-x|10|OK" ("{0}|{1}|{2}" -f $row.model, $row.input_tokens, $row.status)
    Assert-Equal "  대화 id 가 없으면 과정은 NULL(= 모름)" $true ($null -eq $row.process)
    Assert-Equal "  지시파일은 processed 로 옮겨졌다" $true ((Test-Path (Join-Path $ProcessedDir "task-a.md")) -and -not (Test-Path (Join-Path $InboxDir "task-a.md")))
    Assert-Equal "  끝난 기록 1건" 1 (Get-Done).total
    New-TaskFixture "task-b"
    Complete-Fixture "task-b"
    Assert-Equal "두 번째 작업도 한 건만 늘어난다" 2 (Get-Done).total

    Write-Host "중복 방지"
    Set-Content -LiteralPath (Join-Path $OutboxDir "task-a.response.md") -Value "다른 답" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $InboxDir "task-a.md") -Value "다시 온 지시" -Encoding UTF8
    Complete-Fixture "task-a"
    Assert-Equal "이미 끝난 작업은 다시 채우지 않는다(먼저 채운 답이 남는다)" "답 task-a" ([string](Get-QaTaskRow $AgyDbPath "task-a").answer).Trim()
    Assert-Equal "  건수도 그대로" 2 (Get-Done).total
    New-TaskFixture "task-c"
    [void](Sync-QaStore)    # 워처가 켜지면서 사용량 행만 있는 작업을 먼저 채워 넣은 상황
    Assert-Equal "보충이 먼저 채운 작업" "답 task-c" ([string](Get-QaTaskRow $AgyDbPath "task-c").answer).Trim()
    Complete-Fixture "task-c"
    Assert-Equal "  그 뒤 작업자가 마무리해도 한 건이다" 3 (Get-Done).total

    Write-Host "오류로 일찍 끝나는 작업 (사용량 행에 빈 칸)"
    New-TaskFixture "task-e" "ERROR"
    Complete-Fixture "task-e"
    $e = Get-QaTaskRow $AgyDbPath "task-e"
    Assert-Equal "상태 ERROR 로 한 건 기록된다" "ERROR" $e.status
    Assert-Equal "  토큰 칸은 빈 문자열(NULL 이 아니다)" "" ([string]$e.total_tokens)
    Assert-Equal "  빈 문자열이다(NULL 아님)" $false ($null -eq $e.total_tokens)

    Write-Host "사용량 행을 쓰지 못한 경우: 마무리가 전체 보충으로 물러서고 오류 없이 끝난다"
    New-TaskFixture "task-f" "OK" $false
    $threw = $false
    try { Complete-Fixture "task-f" } catch { $threw = $true }
    Assert-Equal "예외 없이 끝난다" $false $threw
    Assert-Equal "  지시파일은 processed 로 옮겨졌다" $true (Test-Path (Join-Path $ProcessedDir "task-f.md"))
    Assert-Equal "  사용량 행이 없으니 기록도 없다" $true ($null -eq (Get-QaTaskRow $AgyDbPath "task-f"))

    Write-Host "Sync-QaStore: 사용량 행만 있는 작업을 채운다"
    foreach ($id in @("task-g", "task-h", "task-i")) { New-TaskFixture $id }
    Assert-Equal "미완료가 3건" 3 @(Get-QaIncompleteRows $AgyDbPath).Count
    Assert-Equal "채운 건수 3" 3 (Sync-QaStore)
    Assert-Equal "  다시 돌리면 0건" 0 (Sync-QaStore)
    Assert-Equal "  지시파일이 아직 inbox 에 있어 processed 에 없으면 질문은 안내 문구" $true (([string](Get-QaTaskRow $AgyDbPath "task-g").question) -like "*원본 지시파일을 찾을 수 없음*")
    Assert-Equal "  답은 outbox 응답" "답 task-g" ([string](Get-QaTaskRow $AgyDbPath "task-g").answer).Trim()

    Write-Host "Initialize-QaStore: 보관 기간이 지난 기록을 정리한다"
    [void](Write-QaRecordToDb $AgyDbPath ([ordered]@{ task_id = "ancient"; timestamp = "2019-01-01 00:00:00"; question = "q"; answer = "a" }) 'Upsert')
    Assert-Equal "정리 전에는 있다" $true ($null -ne (Get-QaTaskRow $AgyDbPath "ancient"))
    Initialize-QaStore
    Assert-Equal "12개월이 지난 기록은 사라진다" $true ($null -eq (Get-QaTaskRow $AgyDbPath "ancient"))
    Assert-Equal "  최근 기록은 남는다" $true ($null -ne (Get-QaTaskRow $AgyDbPath "task-a"))

    Write-Host "watch-agy.ps1 의 작업자 경로"
    $body = $astWatch.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq "Invoke-InboxTaskBody" }, $true)
    $cmds = $body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    Assert-Equal "Invoke-InboxTaskBody 안에서 전체 보충(Update-QAReport)을 부르지 않는다" 0 @($cmds | Where-Object { $_.GetCommandName() -eq "Update-QAReport" }).Count
    Assert-Equal "  모델별 요약 CSV 갱신(Update-UsageSummary)도 부르지 않는다(CSV 는 필요할 때 내보낸다)" 0 @($cmds | Where-Object { $_.GetCommandName() -eq "Update-UsageSummary" }).Count
    Assert-Equal "  마무리는 세 곳(@model 오류, @cwd 오류, 정상/실패 끝)에서 Complete-TaskQaRecord 로 한다" 3 @($cmds | Where-Object { $_.GetCommandName() -eq "Complete-TaskQaRecord" }).Count

    Write-Host "New-QaRecord: 기록 틀(워처와 log-qa.ps1 이 같이 쓴다)"
    $rw = New-QaRecord ([ordered]@{ answer = "a"; task_id = "t1"; question = "q"; status = "OK"; timestamp = "2026-10-16 10:00:00" })
    Assert-Equal "칸 순서는 틀을 따른다(넣은 순서와 무관)" "timestamp,task_id,status,question,answer" (@($rw.Keys) -join ",")
    Assert-Equal "log-qa 의 기록에만 있는 source 는 넣으면 들어간다" $true ((New-QaRecord ([ordered]@{ task_id = "t"; source = "mcp" })).Contains("source"))
    Assert-Equal "넣지 않은 칸(워처의 토큰 칸 등)은 빈 값으로 만들지 않는다" $false ($rw.Contains("input_tokens"))
    $threw = $false
    try { [void](New-QaRecord ([ordered]@{ task_id = "t"; qustion = "오타" })) } catch { $threw = $true }
    Assert-Equal "모르는 칸 이름(오타)은 오류다" $true $threw
    $etsFile = Join-Path $work "ets.txt"
    [System.IO.File]::WriteAllText($etsFile, "파일 내용", (New-Object System.Text.UTF8Encoding($false)))
    $etsText = Get-Content -Raw -LiteralPath $etsFile -Encoding UTF8
    $recEts = New-QaRecord ([ordered]@{ task_id = "t"; question = $etsText; answer = $etsText })
    Assert-Equal "Get-Content -Raw 의 숨은 속성이 붙은 글도 일반 문자열이 된다(직렬화가 작다)" $true ((ConvertTo-Json -InputObject $recEts -Compress).Length -lt 400)
    Assert-Equal "question 은 문자열 형식이다" "System.String" $recEts.question.GetType().FullName
    $long = "가" * 25000
    $recLong = New-QaRecord ([ordered]@{ task_id = "t"; question = $long; answer = $long })
    Assert-Equal "question 은 20000자에서 잘리고 안내가 붙는다" $true (($recLong.question.Length -gt 20000) -and ($recLong.question.Length -lt 20200) -and ($recLong.question -like "*일부 생략됨*"))
    Assert-Equal "process 는 그대로(배열 유지)" 2 @((New-QaRecord ([ordered]@{ task_id = "t"; process = @("a", "b") })).process).Count
    Assert-Equal "process 가 `$null 이면 `$null 그대로(= 모름)" $true ($null -eq (New-QaRecord ([ordered]@{ task_id = "t"; process = $null })).process)
    Assert-Equal "숫자도 문자열로(사용량 행처럼)" "System.String" (New-QaRecord ([ordered]@{ task_id = "t"; attempts = 2 })).attempts.GetType().FullName
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
```

```powershell
Set-BomCrlf @((Join-Path $repo "tests\delegate-agy\qa-store.tests.ps1"))
```

- [ ] **Step 2: 시험이 실패하는지 확인한다**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\qa-store.tests.ps1`
Expected: `Write-UsageRow` 등을 `watch-agy.ps1`에서 찾을 수 없거나(`Write-UsageRowUnlocked`만 있음) 새 시그니처로 실패한다. (옛 코드에서 통과하면 시험이 약한 것이므로 멈추고 점검한다.)

- [ ] **Step 3: watch-agy.ps1 — 변수와 사용량 함수를 바꾼다**

```powershell
$w = Join-Path $repo "runtime\delegate-agy\scripts\sub\watch-agy.ps1"
. "$env:TEMP\psedit.ps1"

# (a) 사용량 파일 변수 블록(UsageCsv·UsageMaxBytes·UsageKeepLines·SummaryCsv)을 지운다. 함수 Get-JsonField 는 이 블록 뒤에 있어 그대로 남는다.
Replace-PsLineRange -Path $w -StartRegex '^# --- 사용량\(모델/토큰/소요시간\) 기록 ---' -EndRegex '^\$SummaryCsv = ' -NewText @'
# --- 사용량(모델/토큰/소요시간) 기록 ---
# 사용량은 위임 기록 DB(agy.db 의 tasks 표)에 작업 끝에 한 행씩 쓴다. CSV 는 필요할 때 tools\export-usage-csv.ps1 로 만든다.

# 참고: agy.exe 응답 JSON에는 model, cost 필드가 없습니다 (CLI 자체 한계, 2026-09 확인).
#       cost_usd는 알아낼 방법이 없어 칸에서 뺐습니다. model은 우리가 --model로 직접
#       지정해서 성공한 값이므로 그대로 신뢰해서 기록합니다.
'@

# (b) usage.csv 헤더·FirstUsageRow 변수와 CSV 함수 둘을 지운다
Replace-PsLineRange -Path $w -StartRegex '^# usage\.csv의 정식 헤더입니다' -EndRegex '^\$script:FirstUsageRow = \$null' -NewText ''
Replace-PsLineRange -Path $w -StartRegex '^# usage\.csv 전체를 모델별로 집계해서' -EndRegex '^# usage\.csv 전체를 모델별로 집계해서' -NewText ''
Remove-PsFunction -Path $w -Names @('Write-UsageRowUnlocked', 'Update-UsageSummaryUnlocked')
Test-PsSyntax $w
```

- [ ] **Step 4: watch-agy.ps1 — 기록 저장소 구간(변수·함수)을 바꾼다**

```powershell
# (c) Q&A 저장소 머리 주석과 변수들
Replace-PsLineRange -Path $w -StartRegex '^# Q&A 기록 저장소 \(JSON Lines\)' -EndRegex '^\$script:QaTotal\s+= 0' -NewText @'
# 위임 기록 저장소 (SQLite: logs\agy.db, 접근은 agy-db.ps1)
# ----------------------------------------------------------------------------
#   tasks 표         : 작업 한 건이 한 줄. 사용량(토큰·모델)은 작업이 끝날 때 먼저 넣고(Write-UsageRow), 질문·답·과정은 지시파일을
#                      processed 로 옮긴 직후에 채운다(Complete-TaskQaRecord). 답이 채워진 줄이 "끝난 기록"이고 뷰어는 그것만 보인다.
#   agy_sessions 표  : @session: <이름> 으로 이어가는 agy 대화의 이름 <-> conversation_id (common.ps1 의 Read-Session/Write-Session).
#
# 화면은 뷰어(serve-viewer.ps1)가 이 DB 를 읽어 /api/qa/records 로 내보냅니다.
# ============================================================================

$AgyDbPath        = Join-Path $LogsDir "agy.db"
$QaKeepMonths     = 12     # 이보다 오래된 기록은 워처가 켜질 때 자동으로 지웁니다.
# 기록에 저장하는 "과정"(agy 가 부른 도구 목록)의 최대 개수. 한 작업이 100~수백 번 도구를 부르는 일이 있어
# 기록이 커지는 것을 막는다. 넘으면 앞쪽 이만큼만 남긴다.
$QaProcessMaxSteps = 400

$SessionMaxAgeDays = 30    # 이보다 오래 안 쓴 세션은 자동으로 정리합니다.
'@
```

이 범위에는 옛 `$DataDir`·`$QaIndexFile`·`$QaShardMaxBytes`·`$SessionsDir`·`$SessionMaxAgeDays`·`$script:QaKnownIds`·`$script:QaTotal` 줄이 모두 들어 있어 함께 사라지고, 쓰는 변수(`$QaKeepMonths`, `$QaProcessMaxSteps`, `$SessionMaxAgeDays`)는 위 새 글자에 다시 들어 있다. 확인: `Grep` 패턴 `\$SessionMaxAgeDays\s*=` 가 `watch-agy.ps1` 에서 정확히 한 번이어야 한다.

```powershell
# (d) 함수 교체
Set-PsFunction -Path $w -Name 'Initialize-QaStore' -NewText @'
function Initialize-QaStore {
    try {
        $removed = Remove-QaRecordsOlderThan $AgyDbPath $QaKeepMonths
        if ($removed -gt 0) { Log "보관 기간($QaKeepMonths 개월)이 지난 기록 $removed 건을 정리했습니다." }
    } catch {
        Log "기록 저장소 초기화 중 오류: $($_.Exception.Message)"
    }
}
'@

Set-PsFunction -Path $w -Name 'Sync-QaStore' -NewText @'
function Sync-QaStore {
    $added = 0
    try {
        foreach ($r in @(Get-QaIncompleteRows $AgyDbPath)) {
            if ([string]::IsNullOrWhiteSpace([string]$r.task_id)) { continue }
            $rec = New-QaRecordFromRow $r
            if ((Write-QaRecordToDb $AgyDbPath $rec 'FillIfIncomplete') -eq 'saved') { $added++ }
        }
    } catch {
        Log "기록 저장소 동기화 중 오류: $($_.Exception.Message)"
    }
    return $added
}
'@

Remove-PsFunction -Path $w -Names @('Update-QaIndex', 'Get-QaIndexTotal', 'Update-QAReportUnlocked', 'Update-UsageSummary')

Set-PsFunction -Path $w -Name 'Complete-TaskQaRecord' -NewText @'
function Complete-TaskQaRecord([string]$TaskId, [string]$SourcePath, [string]$DonePath) {
    Move-Item -Path $SourcePath -Destination $DonePath -Force
    try {
        $row = Get-QaTaskRow $AgyDbPath $TaskId
        if ($null -eq $row) { Update-QAReport; return }       # 사용량 행을 못 썼다: 있는 미완료 작업이라도 채워 둔다
        if ($null -ne $row.answer) { return }                  # 이미 채워졌다(워처가 켜질 때의 보충이 먼저 한 경우)
        $rec = New-QaRecordFromRow $row $DonePath
        if ((Write-QaRecordToDb $AgyDbPath $rec 'FillIfIncomplete') -eq 'pending') { Log "기록을 DB 에 바로 쓰지 못해 pending 폴더에 두었습니다: $TaskId" }
    } catch {
        Log "기록 저장소에 작업 한 건을 채우다 오류가 나서 전체 보충으로 대신합니다: $($_.Exception.Message)"
        Update-QAReport
    }
}
'@

Set-PsFunction -Path $w -Name 'Write-UsageRow' -NewText @'
function Write-UsageRow($taskId, $model, $attempts, $triedModels, $inputTokens, $outputTokens, $thinkingTokens, $totalTokens, $elapsedSec, $status, [string]$session = "", [string]$sessionId = "") {
    try {
        $rec = New-QaRecord ([ordered]@{
            timestamp       = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            computer_name   = $ComputerName
            task_id         = [string]$taskId
            model           = $model
            attempts        = $attempts
            tried_models    = $triedModels
            input_tokens    = $inputTokens
            output_tokens   = $outputTokens
            thinking_tokens = $thinkingTokens
            total_tokens    = $totalTokens
            elapsed_sec     = $elapsedSec
            status          = $status
            session         = $session
            session_id      = $sessionId
        })
        # 같은 작업 ID 의 사용량 행이 이미 있으면 먼저 쓴 것을 둔다(InsertOnly). DB 를 잠깐 못 쓰면 pending 폴더에 두었다가 다음에 가져온다.
        if ((Write-QaRecordToDb $AgyDbPath $rec 'InsertOnly') -eq 'pending') { Log "사용량 기록을 DB 에 바로 쓰지 못해 pending 폴더에 두었습니다: $taskId" }
    } catch {
        Log "사용량 기록 중 오류: $($_.Exception.Message)"
    }
}
'@

Set-PsFunction -Path $w -Name 'Update-QAReport' -NewText @'
function Update-QAReport { [void](Sync-QaStore) }
'@
Test-PsSyntax $w
```

- [ ] **Step 5: watch-agy.ps1 — 주석·호출부를 고친다**

```powershell
# 낡은 주석
Replace-PsLineRange -Path $w -StartRegex '^# 워처가 켜질 때 한 번만: 기존 기록을 읽어' -EndRegex '^# 워처가 켜질 때 한 번만: 기존 기록을 읽어' -NewText '# 워처가 켜질 때 한 번만: 보관 기간이 지난 기록을 정리합니다.'
Replace-PsLineRange -Path $w -StartRegex '^# usage\.csv 의 행 하나\(없는 칸은 빈 문자열\)로' -EndRegex '^# \$QuestionPath 를 주면' -NewText @'
# tasks 표의 행 하나(없는 칸은 NULL)로 완성된 기록 레코드를 만듭니다.
# Sync-QaStore(사용량 행만 있는 작업을 채움)와 작업자의 마무리(Complete-TaskQaRecord)가 같은 레코드를 만들도록 한 곳에 둡니다.
# $QuestionPath 를 주면 그 지시파일을 질문으로 쓰고, 안 주면 processed 폴더에서 작업 ID 로 찾습니다.
'@
Replace-PsLineRange -Path $w -StartRegex '^# usage\.csv에 있는데 아직 jsonl에 없는 작업을' -EndRegex '^# usage\.csv에 있는데 아직 jsonl에 없는 작업을' -NewText '# 사용량 행만 있고 질문·답이 아직 안 채워진 작업을 찾아서 채웁니다(워처가 켜질 때, 사라진 작업을 정리할 때).'
Replace-PsLineRange -Path $w -StartRegex '^# 작업자가 작업 하나를 끝낼 때의 마무리' -EndRegex '^# 이 작업의 usage 행을 이 프로세스가' -NewText @'
# 작업자가 작업 하나를 끝낼 때의 마무리: 지시파일을 processed 로 옮기고, 그 작업의 행(사용량 행은 Write-UsageRow 가 먼저 넣었다)에
# 질문·답·과정을 채운다. 작업자는 작업마다 새 프로세스라 전체 기록을 읽지 않고 이 한 건만 다룬다.
# 사용량 행이 없거나 채우다 오류가 나면 미완료 작업 전체를 채우는 보충(Update-QAReport)으로 물러선다.
'@
Replace-PsLineRange -Path $w -StartRegex '^# 위 세 함수는 usage\.csv·기록 저장소를 읽고' -EndRegex '^# 위 세 함수는 usage\.csv·기록 저장소를 읽고' -NewText '# 사용량 행(tasks 표)을 쓴다: 작업이 끝났을 때 한 번.'

# 호출부
Remove-PsLines -Path $w -Regex '^\s*Update-UsageSummary\s*$' -ExpectedCount 2
Replace-PsLineRange -Path $w -StartRegex '^Update-QAReport\s*$' -EndRegex '^Update-QAReport\s*$' -NewText @'
Initialize-QaStore
Update-QAReport
'@
Test-PsSyntax $w
```

Edit 도구로 단일 줄 네 곳을 고친다(각 old_string 은 파일에서 한 번만 나온다).

1. old_string `        $existingSession = Invoke-WithRuntimeLock { Read-Session $sessionName }` → new_string `        $existingSession = Read-Session $sessionName`
2. old_string `                Invoke-WithRuntimeLock { Write-Session -Name $sessionName -ConversationId $agyResult.ConversationId -Cwd $targetCwds -Model $agyResult.ModelUsed }` → new_string `                Write-Session -Name $sessionName -ConversationId $agyResult.ConversationId -Cwd $targetCwds -Model $agyResult.ModelUsed`
3. old_string `                        $sess = Invoke-WithRuntimeLock { Read-Session $taskSession }` → new_string `                        $sess = Read-Session $taskSession`
4. old_string `Invoke-HandoffPump @{ InboxDir = $InboxDir; OutboxDir = $OutboxDir; UsageCsv = $UsageCsv; SessionsDir = $SessionsDir }` → new_string `Invoke-HandoffPump @{ InboxDir = $InboxDir; OutboxDir = $OutboxDir; DbPath = $AgyDbPath }`

그리고 낡은 설명 줄 두 곳을 고친다.
- old_string `# usage.csv/usage_summary.csv 쪽에서 이미 "(모델 미확정/실패)"로 집계됩니다.` → new_string `# 사용량 행(tasks 표)에서 이미 "(모델 미확정/실패)"로 집계됩니다.`
- old_string `# 있었는지" 조회할 수 있도록 다른 실패와 똑같이 usage.csv/qa-jsonl에 남깁니다` → new_string `# 있었는지" 조회할 수 있도록 다른 실패와 똑같이 위임 기록 DB 에 남깁니다`

- [ ] **Step 6: 남은 옛 표현이 없는지 확인한다**

Run (Grep 도구): 패턴 `UsageCsv|SummaryCsv|UsageCsvHeader|FirstUsageRow|QaIndexFile|QaShardMaxBytes|SessionsDir|\$DataDir|QaKnownIds|QaTotal|Update-QaIndex|Get-QaIndexTotal|Update-UsageSummary|Write-UsageRowUnlocked|Update-QAReportUnlocked|Get-QaShard|Add-QaLine|qa-\*|index\.json` 를 `runtime/delegate-agy/scripts/sub/watch-agy.ps1` 에서 찾는다.
Expected: 일치 없음(주석에서 쓰는 `qa-YYYY-MM` 같은 옛 설명이 남아 있으면 이 단계에서 고친다).

- [ ] **Step 7: handoff-pump.ps1 — 사용량 행·세션 모델을 DB 에서**

```powershell
$hp = Join-Path $repo "runtime\delegate-agy\scripts\sub\handoff-pump.ps1"
Set-PsFunction -Path $hp -Name 'Get-HandoffUsageRow' -NewText @'
function Get-HandoffUsageRow([string]$DbPath, [string]$TaskId) {
    if (-not $DbPath) { return $null }
    try { return (Get-QaTaskRow $DbPath $TaskId) } catch { return $null }
}
'@
Set-PsFunction -Path $hp -Name 'Get-HandoffSessionModel' -NewText @'
function Get-HandoffSessionModel([string]$DbPath, [string]$SessionName) {
    if (-not $DbPath -or -not $SessionName) { return "" }
    try {
        $s = Get-AgySession $DbPath $SessionName
        if ($s -and $s.model -and [string]$s.model -ne "(session)") { return [string]$s.model }
    } catch {}
    return ""
}
'@
Replace-PsLineRange -Path $hp -StartRegex '^# usage\.csv 에서 이 작업의 행' -EndRegex '^# usage\.csv 에서 이 작업의 행' -NewText '# 위임 기록 DB(tasks 표)에서 이 작업의 사용량 행(가장 먼저 쓴 것). 없으면 $null.'
Test-PsSyntax $hp
```

Edit 도구로 두 호출을 고친다.
1. old_string `$usage = Get-HandoffUsageRow $Ctx.UsageCsv $taskId` → new_string `$usage = Get-HandoffUsageRow $Ctx.DbPath $taskId`
2. old_string `Get-HandoffSessionModel $Ctx.SessionsDir ("handoff-"` → new_string `Get-HandoffSessionModel $Ctx.DbPath ("handoff-"`

머리 주석에서 `usage.csv`를 말하는 곳이 있으면 Grep(`usage\.csv|UsageCsv|SessionsDir`)으로 찾아 "위임 기록 DB"로 고친다.

- [ ] **Step 8: handoff-pump 시험을 DB 기준으로 고친다**

`tests/handoff/handoff-pump.tests.ps1` 에서 Edit 도구로 다음을 바꾼다.

(a) old_string
```
$ctx = @{ InboxDir = (Join-Path $rt "inbox"); OutboxDir = (Join-Path $rt "outbox"); UsageCsv = (Join-Path $rt "logs\usage.csv"); SessionsDir = (Join-Path $rt "logs\sessions") }
```
→ new_string
```
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
$ctx = @{ InboxDir = (Join-Path $rt "inbox"); OutboxDir = (Join-Path $rt "outbox"); DbPath = (Join-Path $rt "logs\agy.db") }
```

(b) `$usageHeader = ...` 줄부터 `Add-UsageRow` 함수 끝(`}`)까지 5줄을 Replace-PsLineRange 로 바꾼다:

```powershell
. "$env:TEMP\psedit.ps1"
Replace-PsLineRange -Path (Join-Path $repo "tests\handoff\handoff-pump.tests.ps1") -StartRegex '^\$usageHeader = ' -EndRegex '^\}\s*$' -NewText @'
function Add-UsageRow([string]$TaskId, [string]$Model, [string]$Status) {
    [void](Write-QaRecordToDb $ctx.DbPath ([ordered]@{ timestamp = "2026-10-16 10:00:00"; computer_name = "PC"; task_id = $TaskId; model = $Model; attempts = 1; tried_models = $Model
        input_tokens = 10; output_tokens = 20; thinking_tokens = 5; total_tokens = 35; elapsed_sec = "12.3"; status = $Status; session = "handoff-my-app"; session_id = "conv1" }) 'InsertOnly')
}
'@
```
(이 범위의 끝 `^\}\s*$`는 `Add-UsageRow`의 닫는 중괄호 — 시작 줄 이후 처음 나오는 열 0 의 `}` 이다.)

(c) 머리 주석 3·4번째 줄의 `usage.csv` 표현을 "위임 기록 DB"로 고친다(Edit).

(d) old_string `    Write-Host "답변 모양 정리 (ConvertTo-HandoffReplyBody)"` 앞에 시험 블록을 끼운다:

```powershell
    Write-Host "Get-HandoffSessionModel: DB 의 세션 모델 (usage 행에 모델이 없을 때의 대비)"
    $dbS = Open-AgyDb $ctx.DbPath
    Invoke-AgyDbTransaction $dbS { Set-AgySessionRow $dbS "handoff-my-app" "conv1" @() "gemini-3.8-flash-low" "2026-10-16 09:00:00" "2026-10-16 09:00:00" 1 }
    Invoke-AgyDbTransaction $dbS { Set-AgySessionRow $dbS "handoff-other" "conv2" @() "(session)" "2026-10-16 09:00:00" "2026-10-16 09:00:00" 1 }
    $dbS.Dispose()
    Assert-Equal "세션에 저장된 모델을 돌려준다" "gemini-3.8-flash-low" (Get-HandoffSessionModel $ctx.DbPath "handoff-my-app")
    Assert-Equal "  자리표시자 (session) 는 모델로 쓰지 않는다" "" (Get-HandoffSessionModel $ctx.DbPath "handoff-other")
    Assert-Equal "  없는 세션은 빈 글자" "" (Get-HandoffSessionModel $ctx.DbPath "handoff-nothing")

    Write-Host "답변 모양 정리 (ConvertTo-HandoffReplyBody)"
```
(원래 줄이 새 블록의 마지막 줄로 되돌아오도록 Edit 의 new_string 끝에 포함했다.)

(e) 시험의 `finally`/마무리에서 `$env:AGY_DB_CACHE_DIR` 를 되돌리는 코드는 필요 없다(프로세스 종료와 함께 사라진다).

- [ ] **Step 9: e2e 시험을 DB 기준으로 고친다**

`tests/delegate-agy/watch-agy-model.e2e.tests.ps1` 을 Edit 로 고친다. 이 시험은 워처를 실제로 띄우므로 DB 모듈을 시험 프로세스도 불러야 한다.

(a) old_string `$watcher  = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\watch-agy.ps1"` → new_string
```
$watcher  = Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\watch-agy.ps1"
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-db.ps1")
```

(b) 기록 읽기 구간: `Write-Host "기록(qa jsonl)에 과정 저장"` 줄부터 `    Start-Sleep -Seconds 2\n}` 로 끝나는 while 블록까지를 Replace-PsLineRange 로 바꾼다.

```powershell
. "$env:TEMP\psedit.ps1"
Replace-PsLineRange -Path (Join-Path $repo "tests\delegate-agy\watch-agy-model.e2e.tests.ps1") -StartRegex '^\s*Write-Host "기록\(qa jsonl\)에 과정 저장"' -EndRegex '^\$qaLow = ' -NewText @'
    Write-Host "기록(DB)에 과정 저장"
$dbPath = Join-Path $rt "logs\agy.db"
$deadline2 = (Get-Date).AddSeconds(40)
$qaRows = @()
while ((Get-Date) -lt $deadline2) {
    $qaRows = @((ConvertFrom-Json -InputObject (Get-QaRecordsJson $dbPath 0)).records)
    if (@($qaRows | Where-Object { $_.task_id -like "e2e_*" }).Count -ge 4) { break }
    Start-Sleep -Seconds 2
}
$qaLow = $qaRows | Where-Object { $_.task_id -eq "e2e_low" } | Select-Object -First 1
'@
```
(끝 정규식이 `$qaLow = ` 줄을 범위에 넣으므로 새 글자 끝에 그 줄을 다시 넣었다.)

(c) 세션 읽기: old_string 의 `Read-SessionUntil` 함수 정의 전체(`function Read-SessionUntil([string]$path, [scriptblock]$ok) {` … `    return $obj\n    }`)를 Replace-PsLineRange 로 바꾼다.

```powershell
Replace-PsLineRange -Path (Join-Path $repo "tests\delegate-agy\watch-agy-model.e2e.tests.ps1") -StartRegex '^\s*function Read-SessionUntil\(\[string\]\$path' -EndRegex '^\s*return \$obj\s*$' -NewText @'
    function Read-SessionUntil([string]$name, [scriptblock]$ok) {
        $obj = $null
        $until = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $until) {
            try { $obj = Get-AgySession $dbPath $name } catch { $obj = $null }
            if ($obj -and (& $ok $obj)) { break }
            Start-Sleep -Milliseconds 300
        }
        return $obj
'@
```
(함수의 닫는 `}`는 범위 밖이라 그대로 남는다.)

그리고 호출부 세 곳을 Edit 한다.
1. old_string `    $sessFile = Join-Path $rt "logs\sessions\다폴더-세션.json"` → new_string 은 빈 글자(줄 삭제).
2. old_string `$sess = Read-SessionUntil $sessFile { param($o) @($o.cwd).Count -eq 2 }` → `$sess = Read-SessionUntil "다폴더-세션" { param($o) @($o.cwd).Count -eq 2 }`
3. old_string `$sess = Read-SessionUntil $sessFile { param($o) @($o.cwd).Count -eq 1 -and @($o.cwd)[0] -eq $dirC }` → `$sess = Read-SessionUntil "다폴더-세션" { param($o) @($o.cwd).Count -eq 1 -and @($o.cwd)[0] -eq $dirC }`
4. 설명 줄: old_string `Assert-Equal "  세션 파일의 cwd 는 두 폴더 배열"` → `Assert-Equal "  세션의 cwd 는 두 폴더 배열"`

(d) "예전 형식 세션 파일" 구간(`Write-Host "예전 형식 세션 파일(cwd 가 문자열)"` 부터 `Assert-Equal "  이어간 뒤 세션 파일은 배열 형식으로 …` 줄까지)을 Replace-PsLineRange 로 바꾼다.

```powershell
Replace-PsLineRange -Path (Join-Path $repo "tests\delegate-agy\watch-agy-model.e2e.tests.ps1") -StartRegex '^\s*Write-Host "예전 형식 세션 파일\(cwd 가 문자열\)"' -EndRegex '^\s*Assert-Equal "  이어간 뒤 세션 파일은 배열 형식으로' -NewText @'
    Write-Host "이미 저장된 세션을 이어간다 (폴더 하나, 횟수 2)"
    $dbSeed = Open-AgyDb $dbPath
    Invoke-AgyDbTransaction $dbSeed { Set-AgySessionRow $dbSeed "예전-세션" "conv-old" @($dirB) "gemini-3.8-flash-low" "2026-10-01 10:00:00" "2026-10-01 10:00:00" 2 }
    $dbSeed.Dispose()
    $r = Invoke-CwdTask "cwd_old" "@session: 예전-세션`n예전 세션을 이어갑니다"
    Assert-Equal "저장된 세션의 폴더 하나가 열린다" "dirs=$dirB" $r.Dirs[0]
    # 응답 파일이 먼저 생기고 세션은 그 직후에 쓰이므로, 횟수가 3이 될 때까지 잠깐 기다린다
    $oldAfter = Read-SessionUntil "예전-세션" { param($o) $o.turn_count -eq 3 }
    Assert-Equal "  이어간 뒤 폴더·폴더 수·횟수가 유지된다" "$dirB|1|3" ("{0}|{1}|{2}" -f (@($oldAfter.cwd) -join "|"), @($oldAfter.cwd).Count, $oldAfter.turn_count)
'@
```

(e) 사용량 구간: `Write-Host "사용량 기록 (usage.csv)"` 줄부터 `$row = { param($id) ... }` 줄까지를 Replace-PsLineRange 로 바꾼다.

```powershell
Replace-PsLineRange -Path (Join-Path $repo "tests\delegate-agy\watch-agy-model.e2e.tests.ps1") -StartRegex '^\s*Write-Host "사용량 기록 \(usage\.csv\)"' -EndRegex '^\s*\$row = \{ param\(\$id\)' -NewText @'
Write-Host "사용량 기록 (tasks 표)"
    $row = { param($id) Get-QaTaskRow $dbPath $id }
'@
```
이후 `(& $row "e2e_low").model` 등 단언은 그대로 쓴다(행 객체의 속성 이름이 같다).

```powershell
Test-PsSyntax (Join-Path $repo "tests\delegate-agy\watch-agy-model.e2e.tests.ps1")
Test-PsSyntax (Join-Path $repo "tests\handoff\handoff-pump.tests.ps1")
```

- [ ] **Step 10: 시험을 돌린다**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\qa-store.tests.ps1`
Expected: `통과 N / 실패 0`.
Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\handoff\handoff-pump.tests.ps1`
Expected: 실패 0.
Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 -Only watch-agy,agy-db,cwd-list,qa-store,handoff`
Expected: 모든 스위트 통과(e2e 약 1분 포함). 실패하면 그 스위트의 마지막 실패 줄로 원인을 좁힌다.

- [ ] **Step 11: 작업 폴더에 둔다 (커밋하지 않는다)**

---

### Task 4: 뷰어 — API·세션 조회·화면 로딩

**Files:**
- Modify: `runtime/viewer/serve-viewer.ps1`
- Modify: `runtime/viewer/web/app.js`
- Modify: `runtime/viewer/web/index.html`
- Create: `tests/viewer/qa-records-api.tests.ps1`
- Create: `tests/viewer/qa-records-merge.tests.js`
- Modify: `tests/viewer/pending-cwd.tests.ps1`
- Modify: `tests/viewer/serve-viewer-autostart.tests.ps1`

**Interfaces:**
- Consumes: Task 1 의 `Get-QaRecordsJson`, `Get-AgySession`.
- Produces: `GET /api/qa/records?since=<long>` → `{"records":[기록...],"seq":<long>,"total":<int>}`(끝난 기록만, `updated_seq` 오름차순; `since` 가 숫자가 아니면 0; DB 없으면 빈 목록). 화면 함수 `mergeQaRecords(base, incoming)`(task_id 기준으로 합친 새 배열)와 `qaSeq`.

- [ ] **Step 1: API 시험을 먼저 쓴다 (`tests/viewer/qa-records-api.tests.ps1`, Write 후 `Set-BomCrlf`)**

```powershell
# 뷰어의 위임 기록 API(/api/qa/records) 시험. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\qa-records-api.tests.ps1
# 임시 런타임 폴더(DB)로 뷰어를 -NoAgent 로 실제로 띄웁니다(진짜 뷰어·워처·기록은 건드리지 않습니다. 몇 초).

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$viewerScript = Join-Path $repoRoot "runtime\viewer\serve-viewer.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("qa-records-api-test-" + [Guid]::NewGuid().ToString("N"))
$rt = Join-Path $work "runtime"
foreach ($d in @("inbox", "outbox", "processed", "logs", "logs\data", "logs\heartbeat")) { New-Item -ItemType Directory -Force -Path (Join-Path $rt $d) | Out-Null }
New-Item -ItemType Directory -Force -Path (Join-Path $work "handoff") | Out-Null
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
$env:AGY_DELEGATE_RUNTIME = $rt
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-db.ps1")
$dbPath = Join-Path $rt "logs\agy.db"

function Get-Api([string]$Query) {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/qa/records$Query" -TimeoutSec 10
    $text = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    return @{ Status = [int]$resp.StatusCode; Text = $text; Json = (ConvertFrom-Json -InputObject $text); Headers = $resp.Headers }
}

$port = Get-Random -Minimum 30000 -Maximum 40000
$viewer = $null
try {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$viewerScript`"", "-NoBrowser", "-NoAgent", "-Port", $port,
        "-DataDir", "`"$(Join-Path $rt 'logs\data')`"", "-HandoffDir", "`"$(Join-Path $work 'handoff')`"")
    $viewer = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden -PassThru
    $up = $false
    for ($i = 0; $i -lt 40 -and -not $up; $i++) {
        Start-Sleep -Milliseconds 500
        try { $up = ((Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/status" -TimeoutSec 2).StatusCode -eq 200) } catch {}
    }
    Assert-Equal "뷰어가 응답한다" $true $up

    Write-Host "DB 가 아직 없을 때"
    $a = Get-Api "?since=0"
    Assert-Equal "빈 목록을 200 으로 돌려준다" "200|0|0|0" ("{0}|{1}|{2}|{3}" -f $a.Status, @($a.Json.records).Count, $a.Json.total, $a.Json.seq)

    Write-Host "기록이 있을 때"
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ timestamp = "2026-10-16 10:00:00"; computer_name = "PC"; task_id = "a1"; model = "m"; status = "OK"; question = "질문 `"하나`"`n둘째 줄"; answer = "답"; process = @([pscustomobject]@{ n = 1; tool = "run_command"; detail = "x" }) }) 'Upsert')
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ timestamp = "2026-10-16 10:05:00"; computer_name = "PC"; task_id = "a2"; model = "m"; status = "OK"; question = "q2"; answer = "a2" }) 'Upsert')
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ timestamp = "2026-10-16 10:10:00"; computer_name = "PC"; task_id = "a3-usage-only"; model = "m"; status = "OK" }) 'InsertOnly')
    $a = Get-Api "?since=0"
    Assert-Equal "끝난 기록 2건만 보인다(사용량만 있는 행은 숨는다)" "2|2" ("{0}|{1}" -f @($a.Json.records).Count, $a.Json.total)
    $byId = @{}; foreach ($r in @($a.Json.records)) { $byId[$r.task_id] = $r }
    Assert-Equal "  질문이 그대로(따옴표·줄바꿈)" "질문 `"하나`"`n둘째 줄" $byId["a1"].question
    Assert-Equal "  과정이 객체 배열로 나간다" "run_command" @($byId["a1"].process)[0].tool
    Assert-Equal "  값이 없는 칸(source·process)은 키가 없다" $false ($byId["a2"].PSObject.Properties.Name -contains "process")
    Assert-Equal "  Cache-Control: no-store" "no-store" ([string]$a.Headers["Cache-Control"])
    Assert-Equal "  JSON 콘텐츠 형식" $true ([string]$a.Headers["Content-Type"] -like "application/json*")
    $seq1 = [long]$a.Json.seq
    Assert-Equal "  seq 는 0 보다 크다" $true ($seq1 -gt 0)

    Write-Host "증분 조회"
    $b = Get-Api "?since=$seq1"
    Assert-Equal "since=seq 이면 새 기록 0건, total 은 그대로" "0|2|$seq1" ("{0}|{1}|{2}" -f @($b.Json.records).Count, $b.Json.total, $b.Json.seq)
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ task_id = "a3-usage-only"; question = "q3"; answer = "a3" }) 'FillIfIncomplete')
    $c = Get-Api "?since=$seq1"
    Assert-Equal "사용량만 있던 행이 채워지면 그 한 건만 새로 온다" "1|a3-usage-only|3" ("{0}|{1}|{2}" -f @($c.Json.records).Count, @($c.Json.records)[0].task_id, $c.Json.total)
    Assert-Equal "  seq 가 커진다" $true ([long]$c.Json.seq -gt $seq1)
    Assert-Equal "since 가 숫자가 아니면 0 으로 본다(전부)" 3 @((Get-Api "?since=abc").Json.records).Count
    Assert-Equal "since 가 없어도 전부" 3 @((Get-Api "").Json.records).Count
}
finally {
    if ($viewer -and -not $viewer.HasExited) { Stop-Process -Id $viewer.Id -Force -ErrorAction SilentlyContinue }
    $env:AGY_DELEGATE_RUNTIME = $null
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
```

```powershell
Set-BomCrlf @((Join-Path $repo "tests\viewer\qa-records-api.tests.ps1"))
```

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\qa-records-api.tests.ps1`
Expected: 첫 단언(`빈 목록을 200 으로`)부터 실패(404 또는 예외) — 라우트가 아직 없다.

- [ ] **Step 2: 뷰어 서버 — DB 모듈 불러오기, 경로, 데이터 폴더 감지**

Edit 로 `runtime/viewer/serve-viewer.ps1` 을 고친다.

(a) 데이터 폴더 감지: old_string
```
        if ($cand -and (Test-Path (Join-Path $cand "index.json"))) {
```
→ new_string
```
        # 위임 기록 DB(logs\agy.db)가 있거나, 이전 전의 index.json 이 있는 후보를 고른다
        if ($cand -and ((Test-Path (Join-Path $cand "index.json")) -or (Test-Path (Join-Path (Split-Path $cand -Parent) "agy.db")))) {
```

(b) DB 경로: old_string `$WatcherRuntimeDir = Get-WatcherRuntimeDir $DataDir` → new_string
```
$WatcherRuntimeDir = Get-WatcherRuntimeDir $DataDir
# 위임 기록·세션 DB. DataDir 이 <런타임>\logs\data 라서 한 단계 위(<런타임>\logs)에 있다. /data/ 로 내보내는 폴더 밖에 둔다.
$AgyDbPath = Join-Path (Split-Path $DataDir -Parent) "agy.db"
```

(c) 모듈 불러오기: old_string
```
# 워처와 같이 쓰는 도구 호출·과정 읽기 코드(agy-progress.ps1). 못 찾으면 진행 표시의 도구 설명과 과정 목록만 빠진다.
```
→ new_string
```
# 위임 기록·세션 DB 접근 모듈(agy-db.ps1). 못 찾으면 위임 기록 API 가 503 을 돌려주고 대기 작업의 세션 모델·대화 id 만 빠진다.
$agyDbLib = Find-DelegateScript "sub\agy-db.ps1"
if ($agyDbLib) { . $agyDbLib } else { Write-Warning "agy-db.ps1 을 찾지 못했습니다. 위임 기록을 읽을 수 없습니다." }
# 워처와 같이 쓰는 도구 호출·과정 읽기 코드(agy-progress.ps1). 못 찾으면 진행 표시의 도구 설명과 과정 목록만 빠진다.
```

(d) 라우트: old_string `} elseif ($urlPath -eq "/api/delegate/pending") {` → new_string
```
} elseif ($urlPath -eq "/api/qa/records") {

                # 위임 완료 기록. 화면은 처음에 since=0 으로 전부 받고, 이후엔 마지막으로 받은 seq 이후만 받는다.
                $params = Get-Utf8QueryParams $request.Url
                $qaSince = [long]0
                if ($params["since"]) { [void][long]::TryParse([string]$params["since"], [ref]$qaSince) }
                $qaJson = $null
                try { $qaJson = Get-QaRecordsJson $AgyDbPath $qaSince } catch { $qaJson = $null }
                if ($null -eq $qaJson) {
                    $response.StatusCode = 503
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("위임 기록 DB 를 읽지 못했습니다.")
                    $response.ContentType = "text/plain; charset=utf-8"
                } else {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($qaJson)
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Cache-Control", "no-store")
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } elseif ($urlPath -eq "/api/delegate/pending") {
```

(e) 대기 작업의 세션 조회 두 곳과 안 쓰는 변수. 먼저 old_string `                $sessionsDir = Join-Path $runtimeDir "logs\sessions"` 한 줄을 빈 글자로 바꾼다(Edit). 그다음 **Edit 도구로 두 블록을 통째로 old_string 으로 잡아 바꾼다.** 대기 작업 코드는 줄이 연속이므로(빈 줄 없음) 아래 old_string 이 그대로 맞는다. 맞지 않으면 `Read` 로 해당 줄(1296~1306행 근처)을 열어 들여쓰기를 확인한다.

old_string:
```
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
```
new_string:
```
                            if (-not $resolvedModel -and $sessionVal) {
                                try {
                                    $sObj = Get-AgySession $AgyDbPath $sessionVal
                                    if ($sObj) {
                                        if ($sObj.model) { $resolvedModel = [string]$sObj.model }
                                        if ($sObj.conversation_id) { $sessionId = [string]$sObj.conversation_id }
                                    }
                                } catch {}
                            }
```

old_string:
```
                                if (-not $convId -and $sessionVal) {
                                    $sFile2 = Join-Path $sessionsDir ("{0}.json" -f (($sessionVal -replace '[\\/:*?"<>|]', '_').Trim()))
                                    if (Test-Path -LiteralPath $sFile2) {
                                        try { $convId = [string]((Get-Content -LiteralPath $sFile2 -Raw -Encoding UTF8 | ConvertFrom-Json).conversation_id) } catch {}
                                    }
                                }
```
new_string:
```
                                if (-not $convId -and $sessionVal) {
                                    try { $sObj2 = Get-AgySession $AgyDbPath $sessionVal; if ($sObj2) { $convId = [string]$sObj2.conversation_id } } catch {}
                                }
```

```powershell
$sv = Join-Path $repo "runtime\viewer\serve-viewer.ps1"
. "$env:TEMP\psedit.ps1"
Test-PsSyntax $sv
```

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\qa-records-api.tests.ps1`
Expected: 실패 0.

- [ ] **Step 3: 대기 작업의 세션 조회를 시험에 반영한다 (`pending-cwd.tests.ps1`)**

Edit 로 `tests/viewer/pending-cwd.tests.ps1` 을 고친다.

(a) old_string `$utf8 = New-Object System.Text.UTF8Encoding($false)\nfunction Put-Inbox` 가 아니라 한 줄씩: old_string `function Put-Inbox([string]$name, [string]$text) { [System.IO.File]::WriteAllText((Join-Path $rt "inbox\$name.md"), $text, $utf8) }` → new_string
```
function Put-Inbox([string]$name, [string]$text) { [System.IO.File]::WriteAllText((Join-Path $rt "inbox\$name.md"), $text, $utf8) }

# 세션 s1 은 DB 에 모델·대화 id 가 있다(뷰어가 대기 작업에 세션의 모델과 대화 id 를 붙이는지 본다)
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-db.ps1")
$dbSeed = Open-AgyDb (Join-Path $rt "logs\agy.db")
Invoke-AgyDbTransaction $dbSeed { Set-AgySessionRow $dbSeed "s1" "conv-s1" @() "gemini-3.8-flash-low" "2026-10-16 09:00:00" "2026-10-16 09:00:00" 1 }
$dbSeed.Dispose()
```

(b) old_string `    Assert-Equal "  세션 이름도 읽힌다" "s1" $byId["t_dup"].session` → new_string
```
    Assert-Equal "  세션 이름도 읽힌다" "s1" $byId["t_dup"].session
    Assert-Equal "  DB 의 세션 모델과 대화 id 가 붙는다" "gemini-3.8-flash-low|conv-s1" ("{0}|{1}" -f $byId["t_dup"].model, $byId["t_dup"].session_id)
```

(c) 디렉터리 목록 `"logs\sessions"` 는 더 이상 필요 없으므로 old_string `"logs\heartbeat", "logs\sessions")` → new_string `"logs\heartbeat")`.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\pending-cwd.tests.ps1`
Expected: 실패 0.

- [ ] **Step 4: 자동 시작 시험의 데이터 폴더 표지를 DB 로 바꾼다**

`tests/viewer/serve-viewer-autostart.tests.ps1` 에서 old_string `Set-Content -Path (Join-Path $runtime "logs\data\index.json") -Value "[]" -Encoding UTF8` → new_string `Set-Content -Path (Join-Path $runtime "logs\agy.db") -Value "" -NoNewline -Encoding ASCII    # 뷰어가 데이터 폴더를 고르는 표지(빈 파일도 빈 SQLite DB 로 읽힌다)`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\serve-viewer-autostart.tests.ps1`
Expected: 실패 0(약 1분).

- [ ] **Step 5: 화면 — 합치는 함수 시험을 먼저 쓴다 (`tests/viewer/qa-records-merge.tests.js`)**

```javascript
// 위임 기록 증분 합치기(mergeQaRecords) 테스트.
//   node tests/viewer/qa-records-merge.tests.js
// runtime/viewer/web/app.js 에서 함수 원문을 꺼내 그대로 실행합니다(복사본이 아니라서 앱 코드와 어긋나지 않음).
// 실패가 하나라도 있으면 종료 코드 1을 돌려줍니다.

"use strict";
const fs = require("fs");
const path = require("path");

const appJs = fs.readFileSync(path.join(__dirname, "..", "..", "runtime", "viewer", "web", "app.js"), "utf8");

function extractFunction(name) {
  const start = appJs.indexOf("function " + name + "(");
  if (start < 0) throw new Error(name + " 를 app.js 에서 찾지 못했습니다.");
  let i = appJs.indexOf("{", start), depth = 0;
  for (; i < appJs.length; i++) {
    if (appJs[i] === "{") depth++;
    else if (appJs[i] === "}") { depth--; if (depth === 0) return appJs.slice(start, i + 1); }
  }
  throw new Error(name + " 의 끝을 찾지 못했습니다.");
}

const mergeQaRecords = new Function(extractFunction("mergeQaRecords") + "; return mergeQaRecords;")();

let passed = 0, failed = 0;
function assertEqual(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) { passed++; console.log("  PASS  " + name); }
  else { failed++; console.log("  FAIL  " + name + "  (기대: " + e + " / 실제: " + a + ")"); }
}

const base = [{ task_id: "a", answer: "1" }, { task_id: "b", answer: "2" }];
const incoming = [{ task_id: "b", answer: "2-new" }, { task_id: "c", answer: "3" }];
const merged = mergeQaRecords(base, incoming);

assertEqual("새 기록은 더해지고 같은 task_id 는 새것으로 바뀐다", ["a:1", "b:2-new", "c:3"],
  merged.slice().sort(function (x, y) { return x.task_id < y.task_id ? -1 : 1; }).map(function (r) { return r.task_id + ":" + r.answer; }));
assertEqual("원본 배열은 바뀌지 않는다", [{ task_id: "a", answer: "1" }, { task_id: "b", answer: "2" }], base);
assertEqual("들어온 기록이 없으면 같은 내용", 2, mergeQaRecords(base, []).length);
assertEqual("기본 배열이 비어 있으면 들어온 것만", ["c"], mergeQaRecords([], [{ task_id: "c" }]).map(function (r) { return r.task_id; }));

console.log("");
console.log("통과 " + passed + " / 실패 " + failed);
process.exit(failed ? 1 : 0);
```

Run: `node tests/viewer/qa-records-merge.tests.js`
Expected: `mergeQaRecords 를 app.js 에서 찾지 못했습니다.` 로 실패.

- [ ] **Step 6: 화면 — `loadAllQa` 를 증분 API 로 바꾼다**

```powershell
$aj = Join-Path $repo "runtime\viewer\web\app.js"
. "$env:TEMP\psedit.ps1"

# 안 쓰게 되는 것: 샤드 변경 감지 키·jsonl 파싱
Replace-PsLineRange -Path $aj -StartRegex '^\s+function shardKeyOf\(index\) \{' -EndRegex '^  \}\s*$' -NewText ''
Replace-PsLineRange -Path $aj -StartRegex '^\s+function parseJsonl\(text\) \{' -EndRegex '^  \}\s*$' -NewText ''

# loadAllQa 와 그 위의 shardDataCache
Replace-PsLineRange -Path $aj -StartRegex '^  // 위임 완료 레코드 전체 로드' -EndRegex '^  \}\s*$' -NewText @'
  // 위임 완료 레코드 로드: 뷰어 API(/api/qa/records)에서 마지막으로 받은 갱신 번호(qaSeq) 이후의 기록만 받아 합친다.
  // 처음(또는 강제 새로고침)에는 since=0 으로 전부 받는다. 받은 건수가 서버의 전체 건수와 어긋나면(오래된 기록이 지워짐 등) 처음부터 다시 받는다.
  // task_id 가 같은 기록은 새것으로 바꿔 합친 새 배열을 돌려준다(원본은 바꾸지 않는다).
  function mergeQaRecords(base, incoming) {
    var byId = {};
    var order = [];
    base.forEach(function (r) {
      if (!Object.prototype.hasOwnProperty.call(byId, r.task_id)) { order.push(r.task_id); }
      byId[r.task_id] = r;
    });
    incoming.forEach(function (r) {
      if (!Object.prototype.hasOwnProperty.call(byId, r.task_id)) { order.push(r.task_id); }
      byId[r.task_id] = r;
    });
    return order.map(function (id) { return byId[id]; });
  }

  function loadAllQa(force) {
    var since = (force || allItems.length === 0) ? 0 : qaSeq;
    return fetchJson("/api/qa/records?since=" + since).then(function (res) {
      var recs = (res && Array.isArray(res.records)) ? res.records : [];
      var total = (res && typeof res.total === "number") ? res.total : recs.length;
      var items = (since === 0) ? recs : mergeQaRecords(allItems, recs);

      if (since > 0 && items.length !== total) {
        qaSeq = 0;
        return loadAllQa(true);
      }
      var changed = Boolean(force) || recs.length > 0 || items.length !== allItems.length;
      if (!changed) { return { changed: false }; }

      items.sort(function (a, b) {
        return String((b && b.timestamp) || "").localeCompare(String((a && a.timestamp) || ""));
      });
      allItems = items;
      qaSeq = (res && typeof res.seq === "number") ? res.seq : qaSeq;
      return { changed: true };
    });
  }
'@
```

Edit 로 두 군데를 더 고친다.
1. old_string `  var knownShardKey = "";       // QA 데이터 변경 감지 키` → new_string `  var qaSeq = 0;                // 위임 기록 API 에서 마지막으로 받은 갱신 번호`
2. `loadAllQa` 안에서 지운 `knownShardKey`·`shardDataCache` 를 `Grep`(패턴 `knownShardKey|shardKeyOf|shardDataCache|parseJsonl`, 파일 `app.js`)으로 확인한다. 일치가 없어야 한다. 남은 곳(예: `refresh(force)`)이 있으면 같은 의미로 정리한다.

`index.html` 의 `app.js?v=N` 을 `N+1` 로 올린다(Grep 으로 현재 값을 확인한 뒤 Edit).

```powershell
node --check $aj
```
Expected: 오류 없음.

Run: `node tests/viewer/qa-records-merge.tests.js`
Expected: `통과 4 / 실패 0`(마지막 줄 형식 `통과 N / 실패 M`).

- [ ] **Step 7: 화면을 실제로 확인한다**

미리보기 도구로 임시 데이터 뷰어를 띄워 확인한다(사용자의 운영 뷰어는 건드리지 않는다).

```powershell
$work = Join-Path $env:TEMP ("viewer-check-" + [Guid]::NewGuid().ToString("N"))
$rt = Join-Path $work "runtime"
foreach ($d in @("inbox", "outbox", "processed", "logs\data", "logs\heartbeat")) { New-Item -ItemType Directory -Force -Path (Join-Path $rt $d) | Out-Null }
New-Item -ItemType Directory -Force -Path (Join-Path $work "handoff") | Out-Null
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
. (Join-Path $repo "runtime\delegate-agy\scripts\sub\agy-db.ps1")
1..5 | ForEach-Object { [void](Write-QaRecordToDb (Join-Path $rt "logs\agy.db") ([ordered]@{ timestamp = ("2026-10-16 10:0{0}:00" -f $_); computer_name = "PC"; task_id = "demo$_"; model = "gemini-3.8-flash-high"; status = "OK"; session = "데모"; question = "데모 질문 $_"; answer = "데모 답 $_"; process = @() }) 'Upsert') }
$env:AGY_DELEGATE_RUNTIME = $rt
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$repo\runtime\viewer\serve-viewer.ps1`"","-NoBrowser","-NoAgent","-Port","8799","-DataDir","`"$rt\logs\data`"","-HandoffDir","`"$work\handoff`"")
```
그다음 `mcp__Claude_Browser__preview_start` 로 `http://127.0.0.1:8799` 를 열고 `read_page`/`get_page_text` 로 "위임 실행 기록" 탭에 카드 5건과 세션 "데모"가 보이는지, `read_console_messages` 에 오류가 없는지 확인한다. 이어서 다른 PowerShell 에서 6번째 기록을 DB 에 쓰고 5초 안에 화면에 늘어나는지(증분 갱신) 확인한다. 끝나면 8799 포트의 뷰어 프로세스를 종료하고(`Get-CimInstance Win32_Process` 로 명령줄에 `-Port 8799` 인 것) 임시 폴더를 지운다.

- [ ] **Step 8: 작업 폴더에 둔다 (커밋하지 않는다)**

---

### Task 5: 내보내기·이전 도구

**Files:**
- Create: `tools/export-usage-csv.ps1`
- Create: `tools/migrate-to-sqlite.ps1`
- Create: `tests/repo/db-tools.tests.ps1`

**Interfaces:**
- Consumes: Task 1·2 의 `agy-db.ps1`, `common.ps1`(`ConvertTo-CwdList`, `ConvertTo-ReadableJson`).
- Produces: `tools\export-usage-csv.ps1 [-RuntimeDir] [-Since yyyy-MM-dd] [-Out 경로] [-Summary]` → CSV 파일. `tools\migrate-to-sqlite.ps1 [-RuntimeDir] [-Rollback] [-SkipProcessCheck] [-VerifySamples 20]` → 종료 코드 0(성공/이미 이전함) 또는 1(실패·거부). 이전하면 `<런타임>\logs\agy.db` 가 생기고 원본이 `<런타임>\logs\legacy-<yyyyMMdd-HHmmss>\` 로 옮겨진다.

- [ ] **Step 1: 시험을 먼저 쓴다 (`tests/repo/db-tools.tests.ps1`, Write 후 `Set-BomCrlf`)**

```powershell
# tools\migrate-to-sqlite.ps1 · tools\export-usage-csv.ps1 시험. Pester 없이 돌아갑니다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\repo\db-tools.tests.ps1
# 가짜 예전 런타임(임시 폴더)만 씁니다. 이 PC 의 실제 기록은 건드리지 않습니다. 몇 초 걸립니다.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$migrate = Join-Path $repoRoot "tools\migrate-to-sqlite.ps1"
$export = Join-Path $repoRoot "tools\export-usage-csv.ps1"

$script:Failed = 0
$script:Passed = 0
function Assert-Equal($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:Passed++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL  $name  (기대: [$expected] / 실제: [$actual])" -ForegroundColor Red }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("db-tools-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$env:AGY_DB_CACHE_DIR = Join-Path $work "cache"
. (Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-db.ps1")
$utf8 = New-Object System.Text.UTF8Encoding($false)
function W([string]$path, [string]$text) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    [System.IO.File]::WriteAllText($path, $text, $utf8)
}
function Run-Ps([string[]]$ArgumentList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = (@($ArgumentList | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
    try { $p.StandardInput.Close() } catch {}
    $p.WaitForExit()
    $text = [string]$outTask.Result + [string]$errTask.Result
    $code = $p.ExitCode
    $p.Dispose()
    return @{ Code = $code; Out = $text }
}
function Run-Migrate($rt, [string[]]$Extra = @()) { return (Run-Ps (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $migrate, "-RuntimeDir", $rt, "-SkipProcessCheck") + $Extra)) }

# --- 가짜 예전 런타임 ---
$rt = Join-Path $work "rt"
$logs = Join-Path $rt "logs"; $data = Join-Path $logs "data"
$q1 = '{"timestamp":"2026-10-10 09:00:00","computer_name":"PC","task_id":"q1","model":"m1","attempts":"1","tried_models":"m1","input_tokens":"10","output_tokens":"20","thinking_tokens":"5","total_tokens":"35","elapsed_sec":"12.3","status":"OK","session":"s-a","session_id":"conv-a","question":"질문 1\n둘째 줄","answer":"답 1","process":[{"n":1,"tool":"run_command","detail":"x"},{"n":2,"tool":"write_to_file","detail":"y"}]}'
$q2 = '{"timestamp":"2026-10-10 10:00:00","computer_name":"PC","task_id":"q2","model":"","status":"ERROR","tried_models":"m1","question":"질문 2","answer":"실패 메시지","process":[]}'
$q3 = '{"timestamp":"2026-10-11 09:00:00","computer_name":"PC","task_id":"q3","source":"mcp","model":"m2","status":"OK","question":"질문 3","answer":"답 3"}'
$q4 = '{"timestamp":"2026-09-20 09:00:00","computer_name":"PC","task_id":"q4","model":"m1","status":"OK","question":"질문 4","answer":"답 4","process":null}'
$q5 = '{"timestamp":"2026-10-12 09:00:00","computer_name":"PC","task_id":"q5","status":"OK","question":"질문 5"}'
$q1dup = '{"timestamp":"2026-10-10 09:00:00","computer_name":"PC","task_id":"q1","model":"DUP","question":"중복","answer":"중복 답"}'
$broken = '{"timestamp":"x","task_id":"BROKEN","question":"끊긴'
W (Join-Path $data "qa-2026-10.jsonl") (($q1, $q2, $q3, $broken, $q5) -join "`r`n")
W (Join-Path $data "qa-2026-09.p2.jsonl") (($q4, $q1dup) -join "`r`n")
W (Join-Path $data "index.json") '{"total":6,"shards":[]}'
W (Join-Path $logs "usage.csv") ((
    "timestamp,computer_name,task_id,model,attempts,tried_models,input_tokens,output_tokens,thinking_tokens,total_tokens,elapsed_sec,status,session,session_id",
    "2026-10-10 09:00:00,PC,q1,m1,1,m1,10,20,5,35,12.3,OK,s-a,conv-a",
    "2026-10-10 10:00:00,PC,q2,,,m1,,,,,,ERROR,,",
    "2026-10-13 09:00:00,PC,only1,m3,1,m3,1,2,0,3,1.5,OK,,",
    "2026-10-13 10:00:00,PC,only2,,,m3,,,,,,ERROR,,") -join "`r`n")
W (Join-Path $logs "usage_summary.csv") "model,tasks_ok`r`nm1,2"
W (Join-Path $logs "sessions\a.json") '{ "name": "a", "conversation_id": "conv-a", "cwd": ["D:\\a", "D:\\b"], "model": "m1", "created_at": "2026-10-01 10:00:00", "last_used_at": "2026-10-10 09:00:00", "turn_count": 3 }'
W (Join-Path $logs "sessions\old.json") '{ "name": "old", "conversation_id": "conv-old", "cwd": "D:\\legacy", "model": "m1", "created_at": "2026-10-02 10:00:00", "last_used_at": "2026-10-09 09:00:00", "turn_count": 2 }'
W (Join-Path $logs "sessions\broken.json") '{ 깨진'
W (Join-Path $data "claude-links.json") '{"keep":"me"}'

try {
    Write-Host "이전"
    $r = Run-Migrate $rt
    Assert-Equal "종료 코드 0" 0 $r.Code
    Assert-Equal "  '이전을 마쳤습니다' 를 알린다" $true ($r.Out -like "*이전을 마쳤습니다*")
    Assert-Equal "  깨진 줄 1·중복 1·깨진 세션 1 을 알린다" $true (($r.Out -like "*깨진 줄 1*") -and ($r.Out -like "*중복 1*") -and ($r.Out -like "*깨진 세션 1*"))
    $dbPath = Join-Path $logs "agy.db"
    Assert-Equal "  agy.db 가 생겼다" $true (Test-Path $dbPath)
    $legacy = @(Get-ChildItem $logs -Directory -Filter "legacy-*")
    Assert-Equal "  원본이 legacy-* 폴더로 옮겨졌다" 1 $legacy.Count
    $inLegacy = @(Get-ChildItem $legacy[0].FullName -Recurse -File | ForEach-Object { $_.Name })
    Assert-Equal "  legacy 안에 샤드·index.json·usage.csv·usage_summary.csv·세션 파일이 있다" $true (($inLegacy -contains "qa-2026-10.jsonl") -and ($inLegacy -contains "qa-2026-09.p2.jsonl") -and ($inLegacy -contains "index.json") -and ($inLegacy -contains "usage.csv") -and ($inLegacy -contains "usage_summary.csv") -and ($inLegacy -contains "a.json"))
    Assert-Equal "  원래 자리에는 원본이 없다" $false ((Test-Path (Join-Path $data "qa-2026-10.jsonl")) -or (Test-Path (Join-Path $logs "usage.csv")) -or (Test-Path (Join-Path $logs "sessions")))
    Assert-Equal "  data 폴더의 다른 파일은 그대로다" $true (Test-Path (Join-Path $data "claude-links.json"))

    $all = ConvertFrom-Json -InputObject (Get-QaRecordsJson $dbPath 0)
    $by = @{}; foreach ($x in @($all.records)) { $by[$x.task_id] = $x }
    Assert-Equal "끝난 기록 5건(q1~q5, 중복·깨진 줄 제외)" 5 $all.total
    Assert-Equal "  q1: 먼저 나온 기록이 남는다(중복의 DUP 가 아님)" "m1|답 1" ("{0}|{1}" -f $by["q1"].model, $by["q1"].answer)
    Assert-Equal "  q1: 질문의 줄바꿈이 그대로" "질문 1`n둘째 줄" $by["q1"].question
    Assert-Equal "  q1: 과정 단계 2개" 2 @($by["q1"].process).Count
    Assert-Equal "  q2: process [] 는 '없음'(키가 있고 비어 있다)" "True|0" ("{0}|{1}" -f ($by["q2"].PSObject.Properties.Name -contains "process"), @($by["q2"].process).Count)
    Assert-Equal "  q3: source 가 mcp, process 키 없음" "mcp|False" ("{0}|{1}" -f $by["q3"].source, ($by["q3"].PSObject.Properties.Name -contains "process"))
    Assert-Equal "  q4: process null 은 '모름'(키 없음)" $false ($by["q4"].PSObject.Properties.Name -contains "process")
    Assert-Equal "  q5: 답이 없던 기록은 빈 문자열 답으로 끝난 기록이 된다" "" $by["q5"].answer
    Assert-Equal "usage.csv 에만 있던 작업 2건은 미완료 행으로 들어간다" "only1,only2" ((@(Get-QaIncompleteRows $dbPath) | ForEach-Object { $_.task_id } | Sort-Object) -join ",")
    Assert-Equal "  그 행의 사용량이 그대로" "m3|3" ("{0}|{1}" -f (Get-QaTaskRow $dbPath "only1").model, (Get-QaTaskRow $dbPath "only1").total_tokens)

    $sa = Get-AgySession $dbPath "a"
    Assert-Equal "세션 a: 폴더 둘·횟수" "D:\a|D:\b|3" ("{0}|{1}" -f (@($sa.cwd) -join "|"), $sa.turn_count)
    $so = Get-AgySession $dbPath "old"
    Assert-Equal "  cwd 가 문자열이던 예전 세션은 배열 하나로" "D:\legacy|1" ("{0}|{1}" -f (@($so.cwd) -join "|"), @($so.cwd).Count)
    Assert-Equal "  깨진 세션 파일은 건너뛴다" $true ($null -eq (Get-AgySession $dbPath "broken"))
    $dbm = Open-AgyDb $dbPath
    Assert-Equal "meta 에 이전 시각이 적힌다" $true ([bool](Get-AgyMeta $dbm "migrated_at"))
    $dbm.Dispose()

    Write-Host "다시 실행"
    $r = Run-Migrate $rt
    Assert-Equal "종료 코드 0 이고 '이미 이전했습니다'" "0|True" ("{0}|{1}" -f $r.Code, ($r.Out -like "*이미 이전했습니다*"))

    Write-Host "내보내기"
    $csv = Join-Path $work "usage.csv"
    $r = Run-Ps @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $export, "-RuntimeDir", $rt, "-Out", $csv)
    Assert-Equal "종료 코드 0" 0 $r.Code
    $rows = @(Import-Csv $csv -Encoding UTF8)
    Assert-Equal "  source 가 빈 행만(q1·q2·q4·q5·only1·only2 = 6건, mcp 인 q3 제외)" "6" $rows.Count
    Assert-Equal "  열 이름은 예전 usage.csv 와 같다" "timestamp,computer_name,task_id,model,attempts,tried_models,input_tokens,output_tokens,thinking_tokens,total_tokens,elapsed_sec,status,session,session_id" ((Get-Content $csv -TotalCount 1 -Encoding UTF8).Replace('"', '') -replace '^\xEF\xBB\xBF', '' -replace '^\uFEFF', '')
    $r = Run-Ps @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $export, "-RuntimeDir", $rt, "-Since", "2026-10-11", "-Out", $csv)
    $rows = @(Import-Csv $csv -Encoding UTF8)
    Assert-Equal "  -Since 2026-10-11 이후만(q5·only1·only2)" "3" $rows.Count
    $sum = Join-Path $work "summary.csv"
    $r = Run-Ps @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $export, "-RuntimeDir", $rt, "-Summary", "-Out", $sum)
    $srows = @(Import-Csv $sum -Encoding UTF8)
    $m1 = $srows | Where-Object { $_.model -eq "m1" }
    $unk = $srows | Where-Object { $_.model -eq "(모델 미확정/실패)" }
    Assert-Equal "  -Summary: m1 은 성공 2건(q1·q4)" "2" $m1.tasks_ok
    Assert-Equal "  -Summary: 모델 미확정은 실패 2건(q2·only2)" "2" $unk.tasks_error

    Write-Host "되돌리기"
    [void](Write-QaRecordToDb $dbPath ([ordered]@{ timestamp = "2026-10-15 09:00:00"; computer_name = "PC"; task_id = "newdb"; model = "m1"; status = "OK"; question = "새 질문"; answer = "새 답" }) 'Upsert')
    $dbn = Open-AgyDb $dbPath
    Invoke-AgyDbTransaction $dbn { Set-AgySessionRow $dbn "fresh" "conv-fresh" @("D:\f") "m1" "2026-10-15 09:00:00" "2026-10-15 09:00:00" 1 }
    $dbn.Dispose()
    $r = Run-Migrate $rt @("-Rollback")
    Assert-Equal "종료 코드 0 이고 '되돌렸습니다'" "0|True" ("{0}|{1}" -f $r.Code, ($r.Out -like "*되돌렸습니다*"))
    Assert-Equal "  원본 샤드·usage.csv·세션 파일이 제자리에 돌아왔다" $true ((Test-Path (Join-Path $data "qa-2026-10.jsonl")) -and (Test-Path (Join-Path $logs "usage.csv")) -and (Test-Path (Join-Path $logs "sessions\a.json")))
    Assert-Equal "  agy.db 는 이름이 바뀌어 보관된다" $true ((-not (Test-Path $dbPath)) -and (@(Get-ChildItem $logs -Filter "agy.db.rolledback-*").Count -eq 1))
    Assert-Equal "  DB 에만 있던 새 기록이 옛 형식 샤드로 내보내진다" $true (@(Get-ChildItem $data -Filter "qa-*.jsonl" | Where-Object { (Get-Content $_.FullName -Raw -Encoding UTF8) -like '*"task_id":"newdb"*' }).Count -ge 1)
    Assert-Equal "  DB 에만 있던 새 세션이 세션 파일로 내보내진다" $true (Test-Path (Join-Path $logs "sessions\fresh.json"))

    Write-Host "되돌린 뒤 다시 이전하면 새 기록도 이어진다"
    $r = Run-Migrate $rt
    Assert-Equal "종료 코드 0" 0 $r.Code
    $all2 = ConvertFrom-Json -InputObject (Get-QaRecordsJson (Join-Path $logs "agy.db") 0)
    Assert-Equal "  끝난 기록 6건(원래 5 + newdb)" 6 $all2.total
    Assert-Equal "  fresh 세션도 있다" "conv-fresh" (Get-AgySession (Join-Path $logs "agy.db") "fresh").conversation_id

    Write-Host "안전장치"
    $rt2 = Join-Path $work "rt2"
    $dbOther = Join-Path $rt2 "logs\agy.db"
    [void](Write-QaRecordToDb $dbOther ([ordered]@{ task_id = "x"; question = "q"; answer = "a" }) 'Upsert')
    W (Join-Path $rt2 "logs\data\qa-2026-10.jsonl") $q1
    $r = Run-Migrate $rt2
    Assert-Equal "이전 표시(meta) 없이 기록이 든 DB 는 덮어쓰지 않는다" "1|True" ("{0}|{1}" -f $r.Code, ($r.Out -like "*덮어쓰지 않습니다*"))
    Assert-Equal "  원본도 그대로" $true (Test-Path (Join-Path $rt2 "logs\data\qa-2026-10.jsonl"))
    $rt3 = Join-Path $work "rt3"
    New-Item -ItemType Directory -Force -Path (Join-Path $rt3 "logs") | Out-Null
    $r = Run-Migrate $rt3
    Assert-Equal "옮길 파일이 하나도 없어도 빈 DB 로 이전을 마친다" "0|True" ("{0}|{1}" -f $r.Code, (Test-Path (Join-Path $rt3 "logs\agy.db")))
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host ("통과 {0} / 실패 {1}" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
```

```powershell
Set-BomCrlf @((Join-Path $repo "tests\repo\db-tools.tests.ps1"))
```

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\repo\db-tools.tests.ps1`
Expected: 첫 실행에서 도구 파일이 없어 `이전` 단언부터 실패.

- [ ] **Step 2: `tools/export-usage-csv.ps1` (Write 후 `Set-BomCrlf`)**

```powershell
# 위임 기록 DB(runtime\logs\agy.db)의 사용량을 CSV 로 내보낸다. 평소에는 CSV 를 쓰지 않고, 필요할 때만 이 스크립트로 만든다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\export-usage-csv.ps1                          # 작업별 사용량 -> .\usage-export-<시각>.csv
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\export-usage-csv.ps1 -Summary                 # 모델별 집계   -> .\usage-summary-<시각>.csv
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\export-usage-csv.ps1 -Since 2026-10-01 -Out D:\x\usage.csv
# 워처가 실제 agy CLI 를 부른 작업(source 칸이 빈 행)만 센다. log-qa.ps1 이 남긴 MCP·bridge 기록(source 가 있는 행)은 토큰 칸이 비어
# 집계를 왜곡하므로 뺀다(예전 usage.csv 도 워처가 쓴 행만 담았다).

param(
    [string]$RuntimeDir = "",
    [string]$Since = "",
    [string]$Out = "",
    [switch]$Summary
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if (-not $RuntimeDir) {
    $RuntimeDir = if ($env:AGY_DELEGATE_RUNTIME) { $env:AGY_DELEGATE_RUNTIME } else { Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime" }
}
$dbPath = Join-Path $RuntimeDir "logs\agy.db"
if (-not (Test-Path -LiteralPath $dbPath)) { Write-Host "[x] 위임 기록 DB 가 없습니다: $dbPath" -ForegroundColor Red; exit 1 }

$repoRoot = Split-Path $PSScriptRoot -Parent
$module = @((Join-Path $repoRoot "runtime\delegate-agy\scripts\sub\agy-db.ps1"), (Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\sub\agy-db.ps1")) |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $module) { Write-Host "[x] agy-db.ps1 을 찾지 못했습니다." -ForegroundColor Red; exit 1 }
. $module

$cols = @('timestamp', 'computer_name', 'task_id', 'model', 'attempts', 'tried_models', 'input_tokens', 'output_tokens', 'thinking_tokens', 'total_tokens', 'elapsed_sec', 'status', 'session', 'session_id')
$sql = "SELECT " + ($cols -join ',') + " FROM tasks WHERE (source IS NULL OR source = '')"
$bind = @()
if ($Since) {
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParse($Since, [ref]$d)) { Write-Host "[x] -Since 는 yyyy-MM-dd 모양이어야 합니다: $Since" -ForegroundColor Red; exit 1 }
    $sql += " AND timestamp >= ?"
    $bind += $d.ToString('yyyy-MM-dd HH:mm:ss')
}
$sql += " ORDER BY timestamp"
$db = Open-AgyDb $dbPath
try { $dbRows = $db.Query($sql, [object[]]$bind) } finally { $db.Dispose() }

$rows = @(foreach ($r in $dbRows) {
    $o = [ordered]@{}
    foreach ($c in $cols) { $o[$c] = $(if ($null -eq $r[$c]) { '' } else { [string]$r[$c] }) }
    [pscustomobject]$o
})

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ($Summary) {
    if (-not $Out) { $Out = Join-Path (Get-Location) "usage-summary-$stamp.csv" }
    $groups = @($rows | Group-Object { if ($_.model) { $_.model } else { "(모델 미확정/실패)" } })
    $summaryRows = foreach ($g in $groups) {
        # 참고: Windows PowerShell 5.1에서는 Where-Object 결과가 1건뿐이면 배열이 아니라 단일 객체로 풀려서
        # .Count 가 없어지므로 @(...)로 감싸 항상 배열이 되게 한다.
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
    @($summaryRows) | Sort-Object -Property total_tokens -Descending | Export-Csv -Path $Out -NoTypeInformation -Encoding UTF8 -Force
    Write-Host ("모델별 집계 {0}개를 저장했습니다: {1}" -f @($summaryRows).Count, $Out)
} else {
    if (-not $Out) { $Out = Join-Path (Get-Location) "usage-export-$stamp.csv" }
    $rows | Export-Csv -Path $Out -NoTypeInformation -Encoding UTF8 -Force
    Write-Host ("작업별 사용량 {0}건을 저장했습니다: {1}" -f $rows.Count, $Out)
}
```

```powershell
Set-BomCrlf @((Join-Path $repo "tools\export-usage-csv.ps1"))
Test-PsSyntax (Join-Path $repo "tools\export-usage-csv.ps1")
```

- [ ] **Step 3: `tools/migrate-to-sqlite.ps1` (Write 후 `Set-BomCrlf`)**

```powershell
# 예전 파일 저장소(qa-*.jsonl, index.json, usage.csv, usage_summary.csv, sessions\*.json)를 SQLite(runtime\logs\agy.db)로 한 번에 옮긴다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\migrate-to-sqlite.ps1               # 이전 (워처·뷰어를 먼저 멈춘다)
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\migrate-to-sqlite.ps1 -Rollback     # 되돌리기
#   -RuntimeDir <폴더>   : 기본은 환경변수 AGY_DELEGATE_RUNTIME, 없으면 ~\.samjil\delegate-agy\runtime
#   -SkipProcessCheck    : 워처·뷰어가 떠 있는지 점검하지 않는다(시험용)
#
# 이전 순서: (1) 워처·뷰어가 떠 있으면 멈추라고 알리고 끝낸다 (2) 원본을 읽는다 (3) 임시 DB(agy.db.importing)에 넣는다
# (4) 건수를 맞춰 보고 기록 일부를 칸 단위로 대조한다 — 하나라도 어긋나면 임시 DB 를 지우고 원본은 그대로 둔 채 실패로 끝낸다
# (5) 통과하면 임시 DB 를 agy.db 로 바꾸고 원본을 logs\legacy-<시각>\ 로 옮긴다. 두 번 실행해도 안전하다(이미 이전했으면 알리고 끝).
# 되돌리기: 가장 최근 legacy-* 의 원본을 제자리로 돌리고, DB 에만 있던 새 기록·세션을 옛 형식으로 내보낸 뒤 agy.db 를 이름을 바꿔 보관한다.

param(
    [string]$RuntimeDir = "",
    [switch]$Rollback,
    [switch]$SkipProcessCheck,
    [int]$VerifySamples = 20
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Fail([string]$Message) { Write-Host "[x] $Message" -ForegroundColor Red; exit 1 }
function Info([string]$Message) { Write-Host $Message }

if (-not $RuntimeDir) {
    $RuntimeDir = if ($env:AGY_DELEGATE_RUNTIME) { $env:AGY_DELEGATE_RUNTIME } else { Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime" }
}
$logsDir = Join-Path $RuntimeDir "logs"
$dataDir = Join-Path $logsDir "data"
$sessionsDir = Join-Path $logsDir "sessions"
$usageCsv = Join-Path $logsDir "usage.csv"
$summaryCsv = Join-Path $logsDir "usage_summary.csv"
$indexJson = Join-Path $dataDir "index.json"
$dbPath = Join-Path $logsDir "agy.db"

$repoRoot = Split-Path $PSScriptRoot -Parent
$subDir = @((Join-Path $repoRoot "runtime\delegate-agy\scripts\sub"), (Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\sub")) |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ "common.ps1") } | Select-Object -First 1
if (-not $subDir) { Fail "common.ps1 / agy-db.ps1 을 찾지 못했습니다." }
. (Join-Path $subDir "common.ps1")     # agy-db.ps1, ConvertTo-CwdList, ConvertTo-ReadableJson

if (-not $SkipProcessCheck) {
    $busy = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'watch-agy\.ps1|serve-viewer\.ps1' })
    if ($busy.Count -gt 0) {
        Write-Host ("워처 또는 뷰어(작업자 포함)가 돌고 있습니다(PID: {0}). 쓰는 중에 옮기면 건수가 어긋나므로 먼저 멈춰 주세요:" -f (($busy | ForEach-Object { $_.ProcessId }) -join ", ")) -ForegroundColor Yellow
        Write-Host "  워처: powershell -NoProfile -ExecutionPolicy Bypass -File `"$env:USERPROFILE\.samjil\delegate-agy\scripts\stop-agy.ps1`""
        Write-Host "  뷰어: powershell -NoProfile -ExecutionPolicy Bypass -File `"$env:USERPROFILE\.samjil\viewer\ensure-viewer-running.ps1`" -Stop"
        exit 1
    }
}

# 예전 기록 한 줄(JSON 객체)을 DB 에 넣을 레코드로. 칸 목록에 없는 키는 버리고, 질문·답이 없으면 빈 글자로 둬서 "끝난 기록"이 되게 한다.
function ConvertTo-ImportRecord($o) {
    $rec = [ordered]@{}
    foreach ($k in $script:QaRecordFields) {
        $p = $o.PSObject.Properties[$k]
        if ($null -eq $p) { continue }
        if ($k -eq 'process') { $rec[$k] = $p.Value } else { $rec[$k] = [string]$p.Value }
    }
    if (-not $rec.Contains('question')) { $rec['question'] = '' }
    if (-not $rec.Contains('answer')) { $rec['answer'] = '' }
    return $rec
}

function Remove-DbFiles([string]$Path) {
    foreach ($suffix in @('', '-wal', '-shm')) { Remove-Item -LiteralPath ($Path + $suffix) -Force -ErrorAction SilentlyContinue }
}

function Invoke-Migrate {
    if (Test-Path -LiteralPath $dbPath) {
        $probe = Open-AgyDb $dbPath
        try {
            $done = Get-AgyMeta $probe 'migrated_at'
            $cnt = [int64]($probe.Query('SELECT (SELECT COUNT(*) FROM tasks) + (SELECT COUNT(*) FROM agy_sessions) AS n', $null))[0]['n']
        } finally { $probe.Dispose() }
        if ($done) { Write-Host "이미 이전했습니다($done). 할 일이 없습니다." -ForegroundColor Green; return }
        if ($cnt -gt 0) { Fail "agy.db 에 이미 기록이 있는데 이전 표시(meta)가 없습니다. 다른 방법으로 쓰이던 DB 일 수 있어 덮어쓰지 않습니다: $dbPath" }
        Remove-DbFiles $dbPath     # 비어 있는 DB(뷰어가 먼저 열어 만든 것)는 지운다
    }

    # --- 읽기 ---
    $records = [ordered]@{}
    $broken = 0; $dupes = 0; $noId = 0
    $shards = @(Get-ChildItem -LiteralPath $dataDir -Filter 'qa-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($f in $shards) {
        foreach ($line in [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)) {
            $t = $line.Trim().TrimStart([char]0xFEFF)
            if (-not $t) { continue }
            $o = $null
            try { $o = $t | ConvertFrom-Json } catch { $broken++; continue }
            if ($null -eq $o -or -not $o.task_id) { $noId++; continue }
            $id = [string]$o.task_id
            if ($records.Contains($id)) { $dupes++; continue }
            $records[$id] = ConvertTo-ImportRecord $o
        }
    }

    $usageOnly = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $usageCsv) {
        foreach ($r in @(Import-Csv -LiteralPath $usageCsv -Encoding UTF8)) {
            $id = [string]$r.task_id
            if (-not $id -or $records.Contains($id)) { continue }
            $rec = [ordered]@{}
            foreach ($k in @('timestamp', 'computer_name', 'task_id', 'model', 'attempts', 'tried_models', 'input_tokens', 'output_tokens', 'thinking_tokens', 'total_tokens', 'elapsed_sec', 'status', 'session', 'session_id')) { $rec[$k] = [string]$r.$k }
            [void]$usageOnly.Add($rec)
        }
    }

    $sessions = New-Object System.Collections.ArrayList
    $brokenSessions = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $sessionsDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $o = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
            if ($null -eq $o) { throw "빈 세션 파일" }
            [void]$sessions.Add([pscustomobject]@{
                Key            = (Get-AgySessionKey ([System.IO.Path]::GetFileNameWithoutExtension($f.Name)))
                ConversationId = [string]$o.conversation_id
                Cwd            = @(ConvertTo-CwdList $o.cwd)
                Model          = [string]$o.model
                CreatedAt      = [string]$o.created_at
                LastUsedAt     = [string]$o.last_used_at
                TurnCount      = $(if ($o.turn_count) { [int]$o.turn_count } else { 1 })
            })
        } catch { $brokenSessions++ }
    }

    # --- 임시 DB 에 넣기 ---
    $legacy = Join-Path $logsDir ('legacy-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $tmp = $dbPath + '.importing'
    Remove-DbFiles $tmp
    $db = Open-AgyDb $tmp
    $problem = $null
    try {
        foreach ($id in @($records.Keys | Sort-Object { [string]$records[$_]['timestamp'] })) { [void](Save-QaRecord $db $records[$id] 'InsertOnly') }
        foreach ($rec in $usageOnly) { [void](Save-QaRecord $db $rec 'InsertOnly') }
        foreach ($s in $sessions) {
            Invoke-AgyDbTransaction $db { Set-AgySessionRow $db $s.Key $s.ConversationId $s.Cwd $s.Model $s.CreatedAt $s.LastUsedAt $s.TurnCount }
        }

        # --- 검증 ---
        $nTasks = [int64]($db.Query('SELECT COUNT(*) AS n FROM tasks', $null))[0]['n']
        $nDone = [int64]($db.Query('SELECT COUNT(*) AS n FROM tasks WHERE answer IS NOT NULL', $null))[0]['n']
        $nSess = [int64]($db.Query('SELECT COUNT(*) AS n FROM agy_sessions', $null))[0]['n']
        $usageIds = @($usageOnly | ForEach-Object { $_['task_id'] } | Sort-Object -Unique)
        $expectTasks = $records.Count + $usageIds.Count
        $expectSess = @($sessions | ForEach-Object { $_.Key } | Sort-Object -Unique).Count
        if ($nTasks -ne $expectTasks) { $problem = "작업 건수가 다릅니다: 기대 $expectTasks / DB $nTasks" }
        elseif ($nDone -ne $records.Count) { $problem = "끝난 기록 건수가 다릅니다: 기대 $($records.Count) / DB $nDone" }
        elseif ($nSess -ne $expectSess) { $problem = "세션 건수가 다릅니다: 기대 $expectSess / DB $nSess" }
        else {
            $sampleIds = @()
            if ($records.Count -gt 0) { $sampleIds = @($records.Keys | Get-Random -Count ([Math]::Min($VerifySamples, $records.Count))) }
            $bad = @()
            foreach ($id in $sampleIds) {
                $row = $db.Query('SELECT * FROM tasks WHERE task_id=?', [object[]]@($id))[0]
                $rec = $records[$id]
                foreach ($k in $rec.Keys) {
                    $want = if ($k -eq 'process') { $(if ($null -eq $rec[$k]) { $null } else { ConvertTo-AgyProcessJson $rec[$k] }) } else { [string]$rec[$k] }
                    $got = $row[$k]
                    if (("$want" -ne "$got") -or (($null -eq $want) -ne ($null -eq $got))) { $bad += "$id.$k" }
                }
            }
            if ($bad.Count -gt 0) { $problem = "대조에서 어긋난 칸이 있습니다: " + ($bad[0..([Math]::Min(4, $bad.Count - 1))] -join ", ") }
        }
        if (-not $problem) {
            Set-AgyMeta $db 'migrated_at' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            Set-AgyMeta $db 'migrated_tasks' ([string]$nTasks)
            Set-AgyMeta $db 'migrated_sessions' ([string]$nSess)
            Set-AgyMeta $db 'legacy_dir' $legacy
        }
    } catch {
        $problem = "가져오다 오류가 났습니다: $($_.Exception.Message)"
    } finally {
        $db.Dispose()
    }
    if ($problem) {
        Remove-DbFiles $tmp
        Fail "이전을 중단했습니다(원본은 그대로입니다): $problem"
    }

    # --- 바꿔치기와 원본 보관 ---
    Remove-DbFiles $dbPath
    Move-Item -LiteralPath $tmp -Destination $dbPath
    foreach ($suffix in @('-wal', '-shm')) { Remove-Item -LiteralPath ($tmp + $suffix) -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $legacy | Out-Null
    foreach ($f in $shards) { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $legacy $f.Name) }
    foreach ($p in @($indexJson, $usageCsv, $summaryCsv)) {
        if (Test-Path -LiteralPath $p) { Move-Item -LiteralPath $p -Destination (Join-Path $legacy (Split-Path $p -Leaf)) }
    }
    if (Test-Path -LiteralPath $sessionsDir) { Move-Item -LiteralPath $sessionsDir -Destination (Join-Path $legacy 'sessions') }

    Write-Host ("이전을 마쳤습니다: 끝난 기록 {0}건, 사용량만 있는 작업 {1}건, 세션 {2}건" -f $records.Count, $usageIds.Count, $expectSess) -ForegroundColor Green
    Info ("  건너뜀 - 깨진 줄 {0}, 작업 ID 없는 줄 {1}, 중복 {2}, 깨진 세션 {3}" -f $broken, $noId, $dupes, $brokenSessions)
    Info "  원본 보관: $legacy"
    Info "  다음: 설치본을 동기화하고(sync-installed.ps1) 워처·뷰어를 다시 켜세요."
}

function Invoke-Rollback {
    $legacy = Get-ChildItem -LiteralPath $logsDir -Directory -Filter 'legacy-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $legacy) { Fail "되돌릴 원본(legacy-*)이 없습니다: $logsDir" }
    if (-not (Test-Path -LiteralPath $dbPath)) { Fail "agy.db 가 없습니다: $dbPath" }

    # 원본 샤드에 있는 작업 ID
    $legacyIds = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $legacy.FullName -Filter 'qa-*.jsonl' -File -ErrorAction SilentlyContinue)) {
        foreach ($line in [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)) {
            $t = $line.Trim().TrimStart([char]0xFEFF)
            if (-not $t) { continue }
            try { $o = $t | ConvertFrom-Json; if ($o -and $o.task_id) { $legacyIds[[string]$o.task_id] = $true } } catch {}
        }
    }

    # DB 에만 있는 새 기록·세션
    $newTasks = @(); $newSessions = @()
    $db = Open-AgyDb $dbPath
    try {
        foreach ($r in $db.Query('SELECT * FROM tasks WHERE answer IS NOT NULL ORDER BY timestamp', $null)) {
            if ($legacyIds.ContainsKey([string]$r['task_id'])) { continue }
            $rec = [ordered]@{}
            foreach ($k in $script:QaRecordFields) {
                $v = $r[$k]
                if ($null -eq $v) { continue }
                if ($k -eq 'process') { $rec[$k] = @(ConvertFrom-AgyJsonArray ([string]$v)) } else { $rec[$k] = [string]$v }
            }
            $newTasks += ,$rec
        }
        foreach ($s in $db.Query('SELECT name FROM agy_sessions', $null)) {
            $row = Get-AgySessionRow $db ([string]$s['name'])
            if ($row) { $newSessions += ,$row }
        }
    } finally { $db.Dispose() }

    # 원본을 제자리로
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    foreach ($f in @(Get-ChildItem -LiteralPath $legacy.FullName -File)) {
        $dest = if ($f.Name -like 'qa-*.jsonl' -or $f.Name -eq 'index.json') { $dataDir } else { $logsDir }
        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $dest $f.Name) -Force
    }
    $legSessions = Join-Path $legacy.FullName 'sessions'
    if (Test-Path -LiteralPath $legSessions) { Move-Item -LiteralPath $legSessions -Destination $sessionsDir -Force }

    # 새 기록 -> 옛 형식 샤드(qa-*.jsonl 이름이라 옛 코드와 뷰어가 읽는다)
    if ($newTasks.Count -gt 0) {
        $shard = Join-Path $dataDir ("qa-{0}.rollback.jsonl" -f (Get-Date -Format 'yyyy-MM'))
        $lines = @($newTasks | ForEach-Object { ConvertTo-ReadableJson $_ 6 })
        [System.IO.File]::AppendAllText($shard, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    }
    # 새 세션 -> 세션 파일 (옛 코드가 읽는 모양)
    New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null
    foreach ($s in $newSessions) {
        $path = Join-Path $sessionsDir ("{0}.json" -f $s.name)
        if (Test-Path -LiteralPath $path) { continue }
        $data = [ordered]@{ name = $s.name; conversation_id = $s.conversation_id; cwd = @($s.cwd); model = $s.model; created_at = $s.created_at; last_used_at = $s.last_used_at; turn_count = $s.turn_count }
        Set-Content -LiteralPath $path -Value (ConvertTo-ReadableJson $data 4 -Pretty) -Encoding UTF8
    }

    if (@(Get-ChildItem -LiteralPath $legacy.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) { Remove-Item -LiteralPath $legacy.FullName -Force -ErrorAction SilentlyContinue }
    $kept = $dbPath + '.rolledback-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Move-Item -LiteralPath $dbPath -Destination $kept
    foreach ($suffix in @('-wal', '-shm')) { Remove-Item -LiteralPath ($dbPath + $suffix) -Force -ErrorAction SilentlyContinue }

    Write-Host ("되돌렸습니다: DB 에만 있던 기록 {0}건, 세션 {1}건을 옛 형식으로 내보냈습니다." -f $newTasks.Count, $newSessions.Count) -ForegroundColor Green
    Info "  DB 는 보관했습니다: $kept"
    Info "  코드도 이전 커밋으로 되돌려야 옛 방식으로 돕니다."
}

if ($Rollback) { Invoke-Rollback } else { Invoke-Migrate }
exit 0
```

```powershell
Set-BomCrlf @((Join-Path $repo "tools\migrate-to-sqlite.ps1"))
Test-PsSyntax (Join-Path $repo "tools\migrate-to-sqlite.ps1")
```

- [ ] **Step 4: 시험을 돌리고 고친다**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\repo\db-tools.tests.ps1`
Expected: `통과 N / 실패 0`. 실패하면 마지막 실패 줄의 기대·실제로 도구를 고친다(시험의 기대값은 위 "이전 순서" 설명과 일치하는 동작이므로 시험이 틀린 것이 분명할 때만 고친다). 특히 확인할 곳: PowerShell 5.1 의 배열 풀림(`$rows.Count`), `ConvertFrom-Json` 의 배열 한 덩어리, 헤더 첫 줄의 BOM 제거 정규식.

- [ ] **Step 5: 위생 시험**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 -Only hygiene,db-tools`
Expected: 실패 0.

- [ ] **Step 6: 작업 폴더에 둔다 (커밋하지 않는다)**

---

### Task 6: 후속 정리 — 동기화·삭제기·문서·스펙

**Files:**
- Modify: `sync-installed.ps1`, `tests/repo/sync-installed.tests.ps1`
- Modify: `uninstall.ps1`
- Modify: `README.md`, `samjil-delegate-agy/SKILL.md`
- Modify: `docs/superpowers/specs/2026-10-16-sqlite-migration-design.md`

- [ ] **Step 1: 동기화 시험에 `agy-db.ps1` 사례를 먼저 넣는다**

`tests/repo/sync-installed.tests.ps1` 을 Edit 한다.

(a) old_string `W (Join-Path $src "runtime\delegate-agy\scripts\sub\watch-agy.ps1") "watch v1"` → new_string
```
W (Join-Path $src "runtime\delegate-agy\scripts\sub\watch-agy.ps1") "watch v1"
W (Join-Path $src "runtime\delegate-agy\scripts\sub\agy-db.ps1") "db v1"
```

(b) old_string `Write-Host "소스에서 지운 파일은 설치본에 남기고 알리기만 한다"` → new_string
```
Write-Host "agy-db.ps1 이 바뀌면 워처와 뷰어 재시작을 둘 다 알린다(둘 다 켜질 때 DB 모듈을 읽어 올린다)"
W (Join-Path $src "runtime\delegate-agy\scripts\sub\agy-db.ps1") "db v2"
$r = Run-Sync
Assert-Equal "  워처 재시작 안내가 있다" $true ($r.Out -like "*워처 스크립트가 바뀌었*")
Assert-Equal "  뷰어 재시작 안내도 있다" $true ($r.Out -like "*뷰어 본체 스크립트가 바뀌었습니다*")

Write-Host "소스에서 지운 파일은 설치본에 남기고 알리기만 한다"
```

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\repo\sync-installed.tests.ps1`
Expected: `뷰어 재시작 안내도 있다` 가 실패한다(아직 코드 전).

- [ ] **Step 2: `sync-installed.ps1` 을 고친다**

Edit 로:

(a) old_string `$viewerChanged = @($allChanged | Where-Object { ($_.Group -eq "웹 뷰어" -and ($viewerMain -contains $_.Rel)) -or ($_.Group -eq "handoff 스크립트" -and $_.Rel -eq "handoff-lib.ps1") })` → new_string
```
# 뷰어는 위임 기록 API 를 위해 agy-db.ps1(delegate-agy\scripts\sub)도 불러 오므로 그 파일이 바뀌어도 다시 켜야 한다
$viewerChanged = @($allChanged | Where-Object { ($_.Group -eq "웹 뷰어" -and ($viewerMain -contains $_.Rel)) -or ($_.Group -eq "handoff 스크립트" -and $_.Rel -eq "handoff-lib.ps1") -or ($_.Group -eq "delegate-agy 스크립트" -and $_.Rel -eq "sub\agy-db.ps1") })
```

(b) old_string `$files = @($vs, (Join-Path $InstallRoot "viewer\claude-sessions.ps1"), (Join-Path $InstallRoot "handoff\scripts\handoff-lib.ps1")) | Where-Object { Test-Path -LiteralPath $_ }` → new_string `$files = @($vs, (Join-Path $InstallRoot "viewer\claude-sessions.ps1"), (Join-Path $InstallRoot "handoff\scripts\handoff-lib.ps1"), (Join-Path $InstallRoot "delegate-agy\scripts\sub\agy-db.ps1")) | Where-Object { Test-Path -LiteralPath $_ }`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\repo\sync-installed.tests.ps1`
Expected: 실패 0.

- [ ] **Step 3: `uninstall.ps1` 이 DB 가 있을 때도 기록을 보존하게 한다**

Edit 로:

old_string
```
            $qaFiles = @(Get-ChildItem -LiteralPath (Join-Path $dd "runtime\logs\data") -Filter "qa-*.jsonl" -File -ErrorAction SilentlyContinue)
            if ($qaFiles.Count -gt 0) {
```
→ new_string
```
            $qaFiles = @(Get-ChildItem -LiteralPath (Join-Path $dd "runtime\logs\data") -Filter "qa-*.jsonl" -File -ErrorAction SilentlyContinue)
            $qaDb = Join-Path $dd "runtime\logs\agy.db"
            if ($qaFiles.Count -gt 0 -or (Test-Path -LiteralPath $qaDb)) {
```
old_string `Write-Host "[i] 위임 실행 기록($($qaFiles.Count)개 샤드)이 존재하여 로그를 안전하게 보존합니다:` → new_string `Write-Host "[i] 위임 실행 기록(DB 또는 $($qaFiles.Count)개 샤드)이 존재하여 로그를 안전하게 보존합니다:`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 -Only uninstall,hygiene,cwd-list`
Expected: 실패 0.

- [ ] **Step 4: 문서 — README·SKILL.md**

Grep 도구로 README 의 다음을 찾아 고친다(줄 번호는 바뀔 수 있다).

| 찾을 글 | 고칠 내용 |
|---|---|
| `` `qa-YYYY-MM.jsonl` 기록의 `process` 항목 `` | `` `agy.db`의 `tasks` 표 `process` 칸 `` |
| `한 줄짜리와 ``cwd``가 문자열인 예전 세션 파일은 그대로 동작합니다.` | `예전 세션 파일(``cwd``가 문자열이던 것 포함)은 ``tools\migrate-to-sqlite.ps1``이 배열로 바꿔 가져옵니다.` |
| `(처리 결과·``usage.csv``·``agy`` 호출 기록)` | `(처리 결과·``tasks`` 표의 사용량·``agy`` 호출 기록)` |
| `- ``cwd-list.tests.ps1``: ...` 줄 | `세션 저장·읽기(``Write-Session``/``Read-Session``: 배열 저장, 이어가기 횟수·모델 유지, 오래 안 쓴 세션 정리)`로, 예전 문자열 형식 읽기는 빼고 ``log-qa.ps1`` 의 DB 기록·중복 거부를 추가 |
| `- ``qa-store.tests.ps1``: ...` 줄 | `위임 기록 저장소(SQLite) 쓰기 경로 — 사용량 행 먼저(``Write-UsageRow``), 마무리가 그 한 건만 채우는지(``Complete-TaskQaRecord``), 먼저 채운 것이 남는 중복 방지, 사용량 행이 없을 때의 보충, ``Sync-QaStore``·보관 기간 정리, 작업자 경로에서 ``Update-QAReport``·``Update-UsageSummary`` 를 부르지 않는지 (몇 초)` |
| `usage.csv` 가 들어간 144행 근처 문장 | Read 로 그 문장 전체를 확인한 뒤, 파일 이름(`usage.csv`)만 "위임 기록 DB"로 바꾼다(문장의 뜻은 유지) |

새 시험을 README 시험 목록에 추가한다(기존 항목 모양을 따라):
- `agy-db.tests.ps1`: SQLite 래퍼·스키마·기록 3가지 저장 방식(`Upsert`/`InsertOnly`/`FillIfIncomplete`)·뷰어 API 본문(`Get-QaRecordsJson`)·세션·보관 정리, 프로세스 6개 동시 쓰기, DB 가 잠겼을 때 pending 으로 피했다가 가져오기 (몇 초)
- `qa-records-api.tests.ps1`: 뷰어 `/api/qa/records`(빈 DB, 끝난 기록만, `since` 증분, 숫자가 아닌 `since`) — 임시 DB 로 뷰어를 띄움
- `qa-records-merge.tests.js`: 화면의 증분 합치기 `mergeQaRecords`
- `db-tools.tests.ps1`: `migrate-to-sqlite.ps1`(이전·검증·원본 보관·재실행·되돌리기·안전장치)와 `export-usage-csv.ps1`

README 의 "개발 도구" 구역(Grep `## 개발 도구` 또는 `tools/` 를 소개한 곳)에 새 구역을 더한다:

```markdown
### 위임 기록 저장소 (SQLite)

위임 기록·사용량·agy 세션은 `~/.samjil/delegate-agy/runtime/logs/agy.db` 한 파일에 있습니다(예전의 `qa-*.jsonl`, `usage.csv`, `sessions/*.json` 대신). Windows 에 들어 있는 `winsqlite3.dll` 을 쓰므로 따로 설치할 것이 없고, 여러 프로세스가 동시에 읽고 써도 됩니다(WAL). DB 를 잠깐 못 쓸 때 쓰는 기록은 `logs/pending/` 에 두었다가 다음에 가져옵니다.

- **예전 파일을 옮기기** (한 번): 워처·뷰어를 멈춘 뒤 `powershell -NoProfile -ExecutionPolicy Bypass -File tools\migrate-to-sqlite.ps1`. 건수와 기록 일부를 대조해 어긋나면 원본을 그대로 두고 중단하고, 통과하면 원본을 `logs/legacy-<시각>/` 로 옮깁니다. 이미 옮겼으면 알리고 끝납니다. 이어서 `sync-installed.ps1` 로 설치본을 맞추고 워처·뷰어를 다시 켭니다.
- **되돌리기**: `tools\migrate-to-sqlite.ps1 -Rollback` (코드도 이전 커밋으로 되돌려야 옛 방식으로 돕니다).
- **CSV 가 필요할 때**: `tools\export-usage-csv.ps1` (작업별) 또는 `-Summary` (모델별 집계). `-Since 2026-10-01`, `-Out <경로>` 도 쓸 수 있습니다.
```

`samjil-delegate-agy/SKILL.md` 한 줄: old_string
```
결과는 `~/.samjil/delegate-agy/runtime/logs/usage.csv`(작업별), `usage_summary.csv`(모델별 집계), `data/qa-*.jsonl`에 자동 기록된다(모델 칸에는 실제로 쓴 모델이 들어간다).
```
→ new_string
```
결과는 `~/.samjil/delegate-agy/runtime/logs/agy.db`(SQLite, 작업별 사용량·질문·답·과정)에 자동 기록된다(모델 칸에는 실제로 쓴 모델이 들어간다). CSV 가 필요하면 `tools\export-usage-csv.ps1` 로 만든다.
```

- [ ] **Step 5: 스펙에 달라진 점을 반영한다**

`docs/superpowers/specs/2026-10-16-sqlite-migration-design.md` 를 Edit 한다.
- `## 2. 저장 구조` 의 `DB 파일: \`runtime/logs/data/agy.db\` (WAL 모드).` → `DB 파일: \`runtime/logs/agy.db\` (WAL 모드). \`logs/data\`는 뷰어가 \`/data/\`로 그대로 내보내는 폴더라 DB 를 거기 두지 않는다.`
- `## 4. 쓰기 흐름` 의 `위임 기록 경로에서는 \`Invoke-WithRuntimeLock\`을 쓰지 않는다. 다른 호출자가 없어지면 함수를 지운다.` → `위임 기록 경로에서는 \`Invoke-WithRuntimeLock\`을 쓰지 않는다. 워처의 \`Log()\`가 로그 파일 자르기에 쓰므로 함수는 남긴다.`
- `## 6. 이전·되돌리기` 의 2번 `짝이 없는 줄은 \`source='usage-csv'\`로 따로 넣는다.` → `짝이 없는 줄은 사용량만 있는 행(\`answer IS NULL\`)으로 넣는다. 워처가 켜질 때의 보충(\`Sync-QaStore\`)이 예전처럼 채운다.`
- 쓰기 흐름에 한 줄 추가: `- 사용량은 작업이 끝날 때 \`InsertOnly\`로 먼저 넣고(먼저 쓴 행이 남음), 질문·답·과정은 \`FillIfIncomplete\`로 채운다. "끝난 기록"은 \`answer IS NOT NULL\` 이고 뷰어 API 는 그것만 낸다.`
- `## 5. 읽기 흐름` 에 한 줄 추가: `- \`usage_summary.csv\`(모델별 집계)는 더 이상 만들지 않는다. \`export-usage-csv.ps1 -Summary\`가 대신한다. 보관 기간은 기록과 같이 12개월이다.`
- 머리의 `상태: 사용자 승인 대기(스펙 검토)` → `상태: 승인됨(2026-10-16), 구현 계획: docs/superpowers/plans/2026-10-16-sqlite-migration.md`

- [ ] **Step 6: 작업 폴더에 둔다 (커밋하지 않는다)**

---

### Task 7: 전체 검증과 이 PC 에 적용

**Files:** (코드 변경 없음)

- [ ] **Step 1: 옛 표현이 남지 않았는지 저장소 전체에서 확인한다**

Run (Grep 도구): 패턴 `qa-\*\.jsonl|UsageCsv|usage_summary|Update-UsageSummary|Add-QaRecordUnlocked|Get-QaShard|Test-QaTaskIdIn|Get-SessionPath|Get-SafeSessionFileName|logs\\sessions|QaIndexFile` 를 `runtime/`, `tools/`, `tests/`, `*.md`(저장소 루트와 `samjil-*/`), `*.ps1`(저장소 루트)에서 찾는다(`docs/superpowers/**` 와 `tools/migrate-to-sqlite.ps1`·`tests/repo/db-tools.tests.ps1`·`tests/viewer/*`의 마이그레이션 설명은 의도된 언급이다).
Expected: 의도된 언급(이전 도구, 이전 시험, 스펙·계획 문서, README 의 이전 안내)만 남는다. 그 밖은 고친다.

- [ ] **Step 2: 전체 시험**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1`
Expected: 모든 스위트 통과(약 3~4분; 기존 27개 + 새 4개). 실패하면 그 스위트를 `-Only 이름 -Parallel 1`로 다시 돌려 원인을 좁히고 고친다.

- [ ] **Step 3: 이 PC 에서 이전할 준비를 확인하고 사용자에게 알린다**

현재 상태를 읽기 전용으로 확인한다.
```powershell
$rt = "$env:USERPROFILE\.samjil\delegate-agy\runtime"
(Get-Content "$rt\logs\data\index.json" -Raw -Encoding UTF8 | ConvertFrom-Json).total   # 이전 전 기록 건수(기대값 기록)
@(Get-ChildItem "$rt\logs\sessions" -Filter *.json).Count                              # 세션 파일 수
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'watch-agy\.ps1|serve-viewer\.ps1' } | Select-Object ProcessId, @{n='cmd';e={$_.CommandLine.Substring(0,[Math]::Min(120,$_.CommandLine.Length))}}
```
그리고 사용자에게 "이 PC 의 워처·뷰어를 멈추고 이전해도 되는지" 선택 팝업으로 묻는다. **승인 없이 운영 워처·뷰어를 멈추거나 이전을 실행하지 않는다.**

- [ ] **Step 4: (사용자 승인 후) 이 PC 에 적용한다 — 이 순서를 지킨다**

1. 콘솔 창 감시기가 꺼져 있고 agy 위임이 곧 있을 예정이면 다시 켠다(`tools\watch-console-windows.ps1`, 작업 스케줄러 등록은 하지 않는다).
2. 돌고 있는 위임 작업이 없는지 확인한다(`~\.samjil\delegate-agy\runtime\logs\running\*.json` 없음). 있으면 끝날 때까지 기다린다.
3. 워처 정지: `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.samjil\delegate-agy\scripts\stop-agy.ps1"` / 뷰어 정지: `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.samjil\viewer\ensure-viewer-running.ps1" -Stop`
4. 이전: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\migrate-to-sqlite.ps1` — 출력의 "끝난 기록 N건"이 3단계 전의 `index.json` 건수와 같은지 확인한다(깨진 줄·중복으로 줄었다면 출력의 건너뜀 숫자와 맞는지).
5. 설치본 동기화: `powershell -NoProfile -ExecutionPolicy Bypass -File sync-installed.ps1` (이 시점에는 워처·뷰어가 꺼져 있다).
6. 워처·뷰어 시작: `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.samjil\delegate-agy\scripts\start-agy.ps1" -Hidden` / `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.samjil\viewer\ensure-viewer-running.ps1"`
7. 확인: `http://127.0.0.1:8787/api/qa/records?since=0` 의 `total` 이 4단계 건수와 같고, 화면의 위임 실행 기록에 카드와 세션이 이전과 같이 보인다(브라우저 도구로 `get_page_text`). 워처 로그(`~\.samjil\delegate-agy\runtime\logs\watcher.log`)에 오류가 없는지 본다.
8. 간단한 위임을 하나 보내 끝까지 도는지 확인한다(예: `@model: gemini-3.8-flash-low` 로 "OK 라고만 답하세요" 지시파일을 inbox 에 둔다). 응답이 오고 화면에 새 카드가 5초 안에 뜨는지, `agy.db` 에 `answer`가 채워졌는지 확인한다.

문제가 생기면 `tools\migrate-to-sqlite.ps1 -Rollback` 과 코드 되돌리기(`git checkout`으로 이전 커밋의 설치본 동기화)를 안내한다.

- [ ] **Step 5: 커밋은 사용자 승인 뒤 한 번에**

`git status --short` 로 변경 목록을 보여 주고, 사용자가 "커밋해 줘"라고 하면 한 커밋으로 묶는다(메시지 예: `feat(db): 위임 기록·사용량·세션을 SQLite 한 파일로 옮긴다`). `Co-Authored-By` 를 넣지 않는다. 푸시는 별도 요청이 있을 때 하고, 훅 시험은 사용자가 시험을 명시할 때만 켠다.

---

## 자체 점검 (계획 작성자용)

**스펙 대응:** 저장 구조(§2)=Task 1; 공용 모듈·컴파일 캐시(§3)=Task 1; 쓰기 흐름·합치기·`updated_seq`·pending 안전망(§4)=Task 1·2·3; 읽기 흐름·API·CSV(§5)=Task 1·4·5; 이전·검증·원본 보관·되돌리기(§6)=Task 5; 시험(§7)=각 작업; 배포(§8)=Task 6·7; 구현 순서(§9)와 위험(§10)=Task 1 이 먼저 네이티브 호출과 `Add-Type` 위험을 해소한다(시제품으로 이미 확인).

**스펙에서 의도적으로 바뀐 점:** 위 "스펙과 달라진 점"에 모두 적었고 Task 6 Step 5 가 스펙을 고친다.

**타입·이름 일관성:** `Write-QaRecordToDb` 모드 문자열(`Upsert`/`InsertOnly`/`FillIfIncomplete`)과 반환 값(`saved`/`skipped`/`pending`)은 Task 1 정의와 Task 2·3 사용이 같다. `Get-QaTaskRow`·`Get-QaIncompleteRows`·`Get-QaRecordsJson`·`Get-AgySession` 의 인자 순서는 `(DbPath, ...)`로 통일. 세션 객체의 속성 이름(`conversation_id`, `cwd`, `model`, `created_at`, `last_used_at`, `turn_count`)은 예전 JSON 과 같아 호출부(`Resolve-TaskCwds $x $session.cwd` 등)가 그대로 동작한다.
