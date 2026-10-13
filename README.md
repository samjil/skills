# samjil AI Agent Skills

[![skills.sh](https://img.shields.io/badge/skills.sh-compatible-blue)](https://skills.sh)

Antigravity(agy) 및 Claude Code 등 AI 코딩 에이전트를 위한 공용 스킬 모음입니다.  
[skills.sh](https://skills.sh) 오픈소스 에이전트 스킬 규약(Agent Skills Specification)을 준수합니다.

---

## 📦 포함된 스킬 목록

| 스킬 | 설명 |
|---|---|
| [`samjil-handoff/`](samjil-handoff/) | Claude ↔ Antigravity(agy) 간 파일 기반 비동기 대화 채널 규약 및 자율 개설 프로토콜 |
| [`samjil-delegate-agy/`](samjil-delegate-agy/) | 난이도별 분담(설계·가장 어려운 수준은 Claude 직접, 나머지는 Antigravity CLI(agy) 위임 + 결과 필수 검토·반복) 기준 및 inbox/outbox 전달 규약 |

---

## 🏗️ 아키텍처 설계 원칙

1. **저장소(`samjil/skills`)는 소스 코드 및 설치 패키지 전용**:
   - Git 저장소는 개발 및 배포용으로만 사용되며, 에이전트 스킬로 직접 연결되지 않습니다.
2. **순수 스킬 정의(`SKILL.md`)만 에이전트에 등록**:
   - **Claude Code**: `~/.claude/skills/<스킬명>` (단일 스킬 정션 링크)
   - **Antigravity (AGY)**: `~/.gemini/config/plugins/samjil-skills/` (전역 플러그인 및 단일 스킬 정션 링크) & `~/.agents/skills/<스킬명>/SKILL.md`
   - 에이전트 디렉터리에는 불필요한 스크립트나 웹 파일을 두지 않고 순수 스킬 정의만 깔끔하게 유지합니다.
3. **부속 도구/스크립트/웹 파일은 `~/.samjil/`에서 통합 관리**:
   - 웹 뷰어 서버 및 위임 실행 워처 등 추가 실행 도구는 `~/.samjil/` 아래에 안전하게 격리되어 관리됩니다.
   - 에이전트 간 대화 기록(`~/.samjil/handoff/<프로젝트>/msg/`)은 스킬을 삭제하거나 업데이트해도 **100% 영구 보존**됩니다.

---

## 🚀 설치 방법

### 방법 1. PowerShell 원클릭 웹 설치 (Windows 전용, git/npm 불필요)

저장소를 clone하지 않아도, 터미널에서 아래 한 줄만 실행하면 최신 스킬과 부속 도구가 전역 설치됩니다:

```powershell
irm https://raw.githubusercontent.com/samjil/skills/main/install.ps1 | iex
```

### 방법 2. 로컬 저장소에서 설치

저장소를 clone한 후:

```powershell
.\install.ps1
```

### 방법 3. `skills.sh` 표준 CLI (Node.js 환경)

```bash
# 전체 스킬 전역 설치
npx skills add samjil/skills -g

# 또는 특정 스킬만 설치
npx skills add samjil/skills -g --skill samjil-handoff
```
> 💡 `npx skills`로 설치하더라도 스킬 디렉터리에는 순수 `SKILL.md`만 깔끔하게 설치되며, 최초 작업 시 AI가 부속 도구 및 런타임 환경(`~/.samjil/`)을 자동으로 구성합니다.

---

## 🗑️ 스킬 제거 (Uninstallation)

설치된 스킬 및 부속 도구를 원클릭으로 클린하게 제거할 수 있습니다:

### 원격 웹 원라이너 제거
```powershell
irm https://raw.githubusercontent.com/samjil/skills/main/uninstall.ps1 | iex
```

### 로컬 저장소에서 제거
```powershell
.\uninstall.ps1
# 또는
.\install.ps1 -Uninstall
```
*(에이전트끼리 대화하면서 생성된 대화 기록(`~/.samjil/handoff/`)은 사용자의 소중한 자산이므로 제거 시에도 절대 삭제되지 않고 영구 보존됩니다. 예전 이름의 폴더 `samjil-handoff/`, `agent-handoff/`도 마찬가지입니다.)*

---

## 🛠️ 부속 도구 실행

설치 후 `~/.samjil/` 디렉터리에서 바로 실행할 수 있습니다:

- **🤝 통합 웹 대시보드 뷰어 (Handoff & Delegate QA)**:
  ```powershell
  ~\.samjil\viewer\serve-viewer.ps1
  # 또는
  ~\.samjil\viewer\serve-viewer.bat
  ```
  실행 시 로컬 브라우저(`http://127.0.0.1:8787`, `127.0.0.1` 전용)가 열리고, 왼쪽 메뉴로 세 화면을 오갑니다. 5초마다 자동으로 갱신됩니다.
  - **대시보드**: 지금 `agy`가 무엇을 하는지(작업 중 / 대기 / 워처 꺼짐 / 서버 연결 끊김. 작업 중이면 모델과 경과 시간)와 최근 위임 결과 띠, **확인 필요**(처리 대기 중인 인수인계 메시지, 최근 24시간 안에 실패한 위임), 위임과 인수인계를 합친 시간순 최근 활동, 누적 통계와 모델별 분포
  - **위임 실행 기록**: 세션별 목록, 모델·상태 필터와 검색. 카드 맨 윗줄에서 모델명과 소요 시간을 강조하고, 실패한 작업도 시도한 모델을 표시
  - **에이전트 인수인계**: 프로젝트별 메시지 타임라인, 방향·상태 필터, `BRIEF.md` 열람. 상태는 보냄 → 읽음 → 처리됨 → 확인함 진행 표시로 보여 줍니다
  - 색은 보낸 쪽을 뜻합니다: Claude는 황토, agy는 청록. 초록/빨강은 성공/실패에만 씁니다. 탭 아이콘 33은 삼짇날(음력 3월 3일)입니다.
  - **워처 자동 점검**: 뷰어가 60초마다(`-WatcherCheckSeconds`, 기본 60, 0이면 끔) 워처가 살아 있는지 보고, 꺼져 있으면 `ensure-agy-running.ps1`로 **창 없이** 다시 켭니다(20초 뒤 한 번 더 확인한 뒤 실행하고 `runtime/logs/watchdog.log`에 기록). `stop-agy.ps1`로 일부러 끈 상태(`manual_stop.flag`)면 켜지 않고, 화면에도 "수동 정지"로 보입니다. 브라우저 탭이 닫혀 있어도 뷰어 서버만 떠 있으면 동작하며, `-NoAgent`로 뷰어를 띄우면 이 기능도 꺼집니다.
  - **켜기 버튼**: 사이드바 하단 상태 줄에서 워처가 꺼져 있을 때만 `켜기`가 보입니다. 누르면 기다리지 않고(재확인 0초) 창 없이 바로 켜고, 켜질 때까지 "켜는 중…"으로 보여 줍니다. `stop-agy`로 끈 상태여도 직접 누른 것이므로 켭니다. 30초 안에 켜지지 않으면 `watcher.log`를 보라는 안내가 나옵니다. 서버는 전용 헤더가 있는 POST만 받습니다(다른 웹 페이지가 몰래 호출하지 못하게).
  - 켜짐/꺼짐은 하트비트가 아니라 워처가 시작할 때 적는 PID 잠금 파일로 판단합니다. 워처는 `agy` 호출을 기다리는 동안(최대 30분) 하트비트를 쓰지 않으므로, 하트비트만 보면 일하는 중인 워처를 꺼진 것으로 잘못 보기 때문입니다. 뷰어는 시작할 때 한 번 워처를 켜고(보이는 콘솔 창), 이후 자동 점검이나 켜기 버튼으로 켜는 워처는 창이 없습니다.
  - 뷰어는 `ensure-agy-running.ps1`을 `-StaleThresholdSeconds 0`으로 부릅니다. 그 스크립트는 기본적으로 "하트비트가 300초 안이면 살아 있음"으로 보는데, 워처 창을 닫아도 하트비트 파일은 남아서 죽은 직후 최대 5분은 아무것도 하지 않았기 때문입니다(뷰어가 PID로 이미 죽었다고 확인한 뒤에 부르므로 그 유예를 끕니다).

- **⚡ Antigravity CLI 위임 워처 시작/재시작**:
  ```powershell
  ~\.samjil\delegate-agy\scripts\start-agy.ps1
  ```
  실행 시 `~/.samjil/delegate-agy/runtime/inbox`를 감시하며 Claude로부터 위임받은 작업을 `agy` CLI로 자동 처리하고 응답을 반환합니다.
  - 이미 워처가 떠 있으면 정상 종료를 요청하고 **처리 중인 작업이 끝나기를 기다린 뒤** 새 워처로 교체합니다. 기본 대기는 30초이고, 그 안에 끝나지 않으면 새 워처를 띄우지 않고 중단합니다. 긴 작업이 돌고 있으면 `-WaitSeconds 900`처럼 늘리세요.
  - **마감 규칙**: `agy` 호출 하나는 최대 1800초(30분)까지 기다립니다. 그 전이라도 `agy`의 대화 기록에 새 단계가 300초 동안 없으면 멈춘 것으로 보고 중단하며, 이유를 실패 메시지에 남깁니다. 단계가 계속 쌓이는 동안은 끊지 않습니다. 10분을 넘기는 호출은 600초마다 `runtime/logs/watcher.log`에 `진행 점검` 줄을 남깁니다.
  - **지시파일 지시어**: 지시파일(`inbox`에 넣는 파일) 맨 위의 `@이름: 값` 줄입니다. 순서는 상관없고 여러 줄을 쓸 수 있으며, `@`로 시작하지 않는 첫 줄부터가 실제 질문입니다.
    - **`@cwd: <폴더>`** — `cwd`는 **c**urrent **w**orking **d**irectory(현재 작업 폴더)의 약자입니다. 원래는 프로그램이 지금 "서 있는" 폴더(셸의 `pwd`)라는 뜻이지만, 여기서는 **agy가 읽고 쓸 프로젝트 폴더를 알려 주는 줄**입니다. 이름과 달리 agy의 작업 폴더를 바꾸지는 않습니다. agy는 워처의 런타임 폴더에서 실행되고, 이 폴더는 `--add-dir`로 접근 허용만 추가됩니다(agy에는 `--cwd` 옵션이 없음). 폴더가 필요 없는 작업이면 이 줄을 빼면 되고, 경로가 없는 폴더면 `지정한 @cwd 경로를 찾을 수 없습니다`로 실패합니다.
      헷갈리면 이렇게 기억하세요: **`@cwd` = agy의 `--add-dir`(접근을 허용할 폴더 추가)**. `cwd`라는 이름은 `subprocess`의 `cwd=`처럼 "작업 폴더를 옮긴다"는 관례를 따랐을 뿐이고, 같은 일을 표준적으로 부르는 이름은 `--add-dir`입니다(이름은 바꾸지 않고 `@cwd`를 유지하기로 했습니다).
    - **`@session: <이름>`** — 같은 이름으로 다시 보내면 agy의 이전 대화를 이어갑니다. `@cwd`는 세션에 저장되므로 이어갈 때는 생략해도 됩니다.
    - **`@model: <ID>`** — 이번 호출에 쓸 모델을 고릅니다(아래 모델 선택).
  - **모델 선택**: 지시파일 맨 위에 `@model: <ID>`를 쓰면 이번 호출에 그 모델 하나만 씁니다(`gemini-3.8-flash-high|medium|low` 등 Gemini 계열). 쓰지 않으면 기본 우선순위(`gemini-3.8-flash-high`부터, 쿼터 초과 시 다음 모델)입니다. 고른 모델이 쿼터 초과·사용 불가면 다른 모델로 자동 전환하지 않고 실패로 기록하며, 허용 목록에 없는 값은 `agy`를 부르지 않고 바로 실패합니다. 이어가는 세션(`@session:`)은 시작할 때의 모델을 유지하므로 다른 모델을 지정하면 오류입니다. `samjil-delegate-agy` 스킬은 난이도에 따라 Claude가 모델을 고르고, 지정한 모델이 실패하면 사용자에게 묻습니다.
  - **상태 확인**: `ensure-agy-running.ps1 -CheckOnly -StaleThresholdSeconds 0`은 켜지 않고 `ALIVE`(종료 코드 0) / `DEAD`(1) / `MANUAL_STOP`(2)만 알려 줍니다. `samjil-delegate-agy` 스킬이 위임 직전에 이것으로 확인하고, 꺼져 있으면 사용자에게 켜도 되는지 먼저 묻습니다.

- **🛑 Antigravity CLI 위임 워처 안전 중지**:
  ```powershell
  ~\.samjil\delegate-agy\scripts\stop-agy.ps1
  ```
  처리 중인 작업은 끊지 않고, 끝난 뒤 워처가 스스로 종료됩니다.

---

## 🧪 테스트

위임 워처의 마감/멈춤 판정은 PowerShell 스크립트로 검증합니다(Pester 불필요). 실패하면 종료 코드 1을 돌려줍니다:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-progress.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\invoke-agy-once.tests.ps1
```

- `agy-progress.tests.ps1`: 대화 찾기, 마지막 활동 시각, 멈춤 판정 경계값 등 단위 테스트 (몇 초)
- `invoke-agy-once.tests.ps1`: 가짜 `agy`로 기다리는 루프를 끝까지 돌리는 통합 테스트 (약 1~2분). 임시 폴더에 `agy.exe`로 복사한 `powershell.exe`를 쓰므로 실제 `agy`는 건드리지 않습니다.
- `model-select.tests.ps1`: `@model:` 지시어 해석, 모델 검증(허용 목록·이어가는 세션), 가짜 `agy`로 후보 선택과 폴백 없음 확인 (약 20초)
- `watch-agy-model.e2e.tests.ps1`: 임시 런타임으로 `watch-agy.ps1`을 실제로 띄워 `@model:`이 메인 루프 끝까지 이어지는지(처리 결과·`usage.csv`·`agy` 호출 기록) 확인합니다 (약 1분). 실제 워처는 건드리지 않습니다.
- `ensure-check-only.tests.ps1`: `ensure-agy-running.ps1 -CheckOnly`의 `ALIVE`/`DEAD`/`MANUAL_STOP` 판정

뷰어의 워처 자동 점검:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\watcher-health.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\serve-viewer-autostart.tests.ps1
```

- `watcher-health.tests.ps1`: 켜짐/꺼짐 판정(잠금 PID, PID 재사용, 하트비트와의 관계), 재시작 결정, 점검 주기, 켜기 요청 처리, `ensure`에 넘기는 인자 단위 테스트 (몇 초)
- `serve-viewer-autostart.tests.ps1`: `serve-viewer.ps1`을 실제로 띄우고 점검 주기를 3초로 줄여, 꺼져 있을 때 `ensure`를 띄우는지·살아 있거나 수동 정지면 안 띄우는지·그동안 다른 요청에 응답하는지·켜기 API(GET 405, 헤더 없는 POST 403, 켜져 있으면 already-running, 꺼져 있으면 started)를 확인합니다 (약 1분). 임시 폴더와 가짜 스크립트만 쓰며 실제 워처/뷰어는 건드리지 않습니다.

---

## 💡 지원 에이전트
- **Google Antigravity**: 전역 플러그인(`~/.gemini/config/plugins/samjil-skills/`) 및 단일 스킬 정션을 통한 전역 자동 감지
- **Claude Code**: `~/.claude/skills/` 전역 스킬 자동 감지
- **Cursor / Windsurf / Cline**: `~/.agents/skills` 또는 `npx skills add`를 통한 지원
