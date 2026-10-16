# SQLite 이전 설계

작성일: 2026-10-16 · 상태: 승인됨(2026-10-16), 구현 계획: docs/superpowers/plans/2026-10-16-sqlite-migration.md

## 1. 목적과 범위

위임 기록(QA 샤드·`index.json`), 사용량(`usage.csv`), agy 세션(세션 파일 27개)을 SQLite 한 파일로 옮긴다.

- 동시 쓰기를 이름 있는 뮤텍스(`Invoke-WithRuntimeLock`) 대신 SQLite(WAL)에 맡긴다.
- 같은 `task_id`의 중복 방지를 꼬리 검사(`Test-QaTaskIdInShardTail`, `Test-QaTaskIdInRecentShards`) 대신 기본키로 보장한다.
- 파일이 늘어날 때의 읽기 비용(샤드 전체 스캔)을 증분 조회로 줄인다.

범위 밖: handoff 대화 기록(`~/.samjil/handoff/**`), 뷰어 화면 디자인, 접근 방식을 `winsqlite3.dll` 외로 바꾸는 일.

### 결정 사항(사용자 확인 완료)

| 항목 | 결정 |
|---|---|
| 범위 | 위임 기록 + 사용량 + 세션 |
| 접근 | Windows 내장 `winsqlite3.dll`을 C# P/Invoke(`Add-Type`)로 호출 |
| 전환 | 한 번에 가져오고 원본은 보관 |
| 뷰어 읽기 | 지금과 같은 모양의 기록을 API로 |
| CSV | 필요할 때 만드는 내보내기 스크립트로 |
| 구조 | 공용 DB 모듈(`agy-db.ps1`) 하나를 모든 스크립트가 짧게 열고 닫는 방식 |

검토했다가 채택하지 않은 안: 뷰어가 DB를 독점하는 서비스 프로세스(뷰어가 꺼지면 기록 불가), 파일 유지 + DB는 색인(쓰기 경로가 두 배).

## 2. 저장 구조

DB 파일: `runtime/logs/agy.db` (WAL 모드). `logs/data`는 뷰어가 `/data/`로 그대로 내보내는 폴더라 DB 를 거기 두지 않는다.

### `tasks` (작업 한 건당 한 줄)

지금의 위임 기록 한 줄과 `usage.csv` 한 행을 합친 표다. `New-QaRecord`가 정하는 필드를 그대로 열로 둔다.

- 열 목록은 `New-QaRecord`의 필드와 `usage.csv`의 열을 1:1로 대응시킨다(구현 계획의 첫 작업에서 두 정의를 읽어 확정하고, 빠지는 필드가 없음을 시험으로 지킨다).
- `task_id` TEXT PRIMARY KEY
- `timestamp`, `model`, `status`, 사용량(토큰) 열, `session`, `session_id`
- `question`, `answer` TEXT
- `process` TEXT (도구 목록 JSON). NULL(모름)과 `[]`(없음)을 구별해 저장한다.
- `source` TEXT (`qa` | `usage-csv` 등 출처)
- `updated_seq` INTEGER NOT NULL, 인덱스 있음 (증분 조회 기준)

### `agy_sessions`

`name` TEXT PRIMARY KEY, `conversation_id`, `cwd`(JSON 배열), `model`, `created_at`, `last_used_at`, `turn_count`. 30일 지난 세션 정리는 `DELETE` 한 줄이다.

### `meta`

`key`/`value`. 스키마 버전, 이전 시각, 이전 건수.

## 3. 공용 DB 모듈 `agy-db.ps1`

위치: `runtime/delegate-agy/scripts/sub/agy-db.ps1`.

- **C# 래퍼:** `sqlite3_open_v2`, `prepare_v2`, `bind_text/int64/null`, `step`, `column_*`, `finalize`, `close_v2`, `busy_timeout`, `exec`만 좁게 감싼다. 문자열은 UTF-8로 넘기고 받는다.
- **컴파일 캐시:** `Add-Type` 컴파일은 느려서 프로세스마다 하지 않는다. 컴파일한 어셈블리를 `~/.samjil/cache/agy-sqlite.dll`에 저장하고 코드 해시가 같으면 `Add-Type -Path`로 불러온다.
- **`winsqlite3.dll`이 없으면** 시작할 때 분명한 오류로 멈춘다.
- **연결:** 필요할 때 열고 바로 닫는다. 열 때 `journal_mode=WAL`, `busy_timeout=10000`. 뷰어는 읽기 전용 연결을 쓴다.
- **세션 함수:** `Read-Session`, `Write-Session`, `Remove-StaleSessions`는 이름과 인자를 유지하고 안쪽만 DB로 바꾼다.

## 4. 쓰기 흐름

- `log-qa`와 워처의 `Complete-TaskQaRecord`는 먼저 `New-QaRecord`로 필드 순서·문자열 변환·20000자 자르기를 거친다. 알 수 없는 키는 지금처럼 오류다.
- 저장은 `BEGIN IMMEDIATE` 트랜잭션 하나에서 `INSERT ... ON CONFLICT(task_id) DO UPDATE`로 한다. 값은 모두 `bind`로 넘긴다(SQL 문자열 이어 붙이기 금지).
- **합치기 규칙:** 워처는 상태·사용량을, `log-qa`는 질문·답·과정을 채운다. 들어온 값이 NULL이면 기존 값을 지우지 않는다.
- 같은 트랜잭션에서 `updated_seq`를 `MAX+1`로 올린다.
- 사용량은 작업이 끝날 때 `InsertOnly`로 먼저 넣고(먼저 쓴 행이 남음), 질문·답·과정은 `FillIfIncomplete`로 채운다. "끝난 기록"은 `answer IS NOT NULL` 이고 뷰어 API 는 그것만 낸다.
- 위임 기록 경로에서는 `Invoke-WithRuntimeLock`을 쓰지 않는다. 워처의 `Log()`가 로그 파일 자르기에 쓰므로 함수는 남긴다.
- **안전망:** `busy_timeout`을 넘겨 실패하면 기록을 `runtime/logs/data/pending/<task_id>.json`에 쓴다. 다음에 DB를 열 때 `pending`을 먼저 가져오고 지운다.

## 5. 읽기 흐름

- 뷰어 API: `GET /api/qa/records?since=<updated_seq>&limit=<n>`는 지금과 같은 모양의 기록 배열과 최대 `updated_seq`를 돌려준다.
- 화면의 `loadAllQa`는 `index.json`과 샤드 대신 이 API를 부른다. 처음에는 전부, 이후에는 마지막 번호 이후만 받는다. 레코드 모양이 같으므로 화면 렌더링은 바뀌지 않는다.
- `handoff-pump.ps1`은 `usage.csv`와 세션 폴더 읽기를 `tasks`·`agy_sessions` 질의로 바꾼다.
- CSV 내보내기: `tools/export-usage-csv.ps1 [-Since] [-Out]`.
- `usage_summary.csv`(모델별 집계)는 더 이상 만들지 않는다. `export-usage-csv.ps1 -Summary`가 대신한다. 보관 기간은 기록과 같이 12개월이다.

## 6. 이전·되돌리기 (`tools/migrate-to-sqlite.ps1`)

**이전**

1. 워처와 뷰어가 도는 중이면 멈추라고 알리고 중단한다.
2. 샤드·`index.json`·`usage.csv`·세션 파일을 하나의 트랜잭션으로 가져온다. `usage.csv`는 `task_id`로 `tasks`에 합친다. 짝이 없는 줄은 사용량만 있는 행(`answer IS NULL`)으로 넣는다. 워처가 켜질 때의 보충(`Sync-QaStore`)이 예전처럼 채운다.
3. 원본 건수와 DB 건수를 비교하고 기록 일부를 필드 단위로 대조한다. 하나라도 어긋나면 DB 파일을 지우고 원본은 그대로 둔 채 실패로 끝낸다.
4. 통과하면 원본을 `runtime/logs/legacy-<날짜>/`로 옮기고 `meta`에 이전 시각·건수를 적는다. 두 번째 실행은 이미 이전했음을 알리고 끝난다.

**되돌리기** `-Rollback`: `legacy-*`를 원위치로 되돌리고 DB에만 있는 새 기록은 옛 형식(샤드·CSV)으로 내보낸다. 코드에는 옛 형식 읽기를 남기지 않으므로, 되돌리려면 코드 커밋도 함께 되돌린다.

## 7. 시험

- DB 모듈: 한글·따옴표·20000자 경계 라운드트립, NULL과 `[]` 구별, 업서트 합치기, 중복 `task_id`.
- 동시성: 프로세스 8개 동시 쓰기에서 손실 0, 오류 0.
- 안전망: DB를 잠가 둔 채 쓰기 → `pending` 파일 생성 → 잠금 해제 후 다음 열기에서 가져옴.
- 이전: 합성 원본으로 가져오기, 건수 불일치 시 중단, 재실행, 되돌리기. 실제 데이터는 복사본으로만 점검한다.
- API: `since` 증분과 레코드 모양이 이전과 같은지.
- 기존 시험(QA 기록, 뷰어, 위생 규칙)을 새 저장소에 맞게 고친다.
- `tests/repo/script-hygiene.tests.ps1`: 새 .ps1은 BOM + CRLF.

## 8. 배포

- `sync-installed.ps1`에 `agy-db.ps1`을 등록한다.
- 워처가 읽는 스크립트이므로 변경 시 워처 재시작 안내 대상에 넣고, 뷰어 API 변경은 뷰어 재시작 안내 대상에 넣는다.
- 이전은 `tools/migrate-to-sqlite.ps1`을 사용자가 워처·뷰어를 멈춘 뒤 한 번 실행한다. 다른 PC는 각자 한 번 실행한다(채널 기록은 PC별).

## 9. 구현 순서

1. DB 모듈과 시험 (네이티브 호출·`Add-Type` 위험을 먼저 확인)
2. 쓰기 경로 교체 (`log-qa`, 워처)
3. 세션 함수 교체
4. 뷰어 API와 화면
5. `handoff-pump`
6. 이전·되돌리기·내보내기 스크립트
7. 문서와 sync 등록

## 10. 위험

| 위험 | 대응 |
|---|---|
| P/Invoke 시그니처 실수로 크래시 | 1단계에서 래퍼만 단독 시험, 좁은 함수 집합 |
| PowerShell 5.1에서 `Add-Type` 컴파일 실패·지연 | 어셈블리 캐시, 실패 시 명확한 오류 |
| 이전 중 쓰기가 겹침 | 사전 점검에서 워처·뷰어 실행 중이면 중단 |
| DB 손상 | WAL, 이전 후 원본 보관, `pending` 안전망 |
| 두 PC에서 같은 DB 공유 | 하지 않는다(채널 기록은 PC별) |
