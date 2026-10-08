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

- **⚡ Antigravity CLI 위임 워처 시작/재시작**:
  ```powershell
  ~\.samjil\delegate-agy\scripts\start-agy.ps1
  ```
  실행 시 `~/.samjil/delegate-agy/runtime/inbox`를 감시하며 Claude로부터 위임받은 작업을 `agy` CLI로 자동 처리하고 응답을 반환합니다.
  - 이미 워처가 떠 있으면 정상 종료를 요청하고 **처리 중인 작업이 끝나기를 기다린 뒤** 새 워처로 교체합니다. 기본 대기는 30초이고, 그 안에 끝나지 않으면 새 워처를 띄우지 않고 중단합니다. 긴 작업이 돌고 있으면 `-WaitSeconds 900`처럼 늘리세요.
  - **마감 규칙**: `agy` 호출 하나는 최대 1800초(30분)까지 기다립니다. 그 전이라도 `agy`의 대화 기록에 새 단계가 300초 동안 없으면 멈춘 것으로 보고 중단하며, 이유를 실패 메시지에 남깁니다. 단계가 계속 쌓이는 동안은 끊지 않습니다. 10분을 넘기는 호출은 600초마다 `runtime/logs/watcher.log`에 `진행 점검` 줄을 남깁니다.

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

---

## 💡 지원 에이전트
- **Google Antigravity**: 전역 플러그인(`~/.gemini/config/plugins/samjil-skills/`) 및 단일 스킬 정션을 통한 전역 자동 감지
- **Claude Code**: `~/.claude/skills/` 전역 스킬 자동 감지
- **Cursor / Windsurf / Cline**: `~/.agents/skills` 또는 `npx skills add`를 통한 지원
