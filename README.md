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
  - **창 없이 백그라운드로 켜기** (직접 실행할 때): `serve-viewer.bat`/`serve-viewer.ps1`은 콘솔 창을 띄우고 브라우저 탭도 엽니다(그 창을 닫으면 뷰어가 꺼집니다). 창도 탭도 없이 켜려면 아래 중 하나를 씁니다. 뷰어는 켜질 때 워처도 창 없이 함께 켜므로 **뷰어와 워처가 둘 다 꺼져 있어도 한 번이면 둘 다 백그라운드로 켜집니다.**
    - **이미 열려 있는 터미널에서:** `~\.samjil\viewer\ensure-viewer-running.ps1` — 새 창이 뜨지 않고 `STARTED`(방금 켬) 또는 `ALIVE`(이미 떠 있음)가 출력됩니다. 이미 떠 있으면 아무것도 하지 않습니다. `-CheckOnly`는 켜지 않고 `ALIVE`/`DEAD`만 알려 주고, `-Port 9000`으로 포트를 바꿀 수 있습니다.
    - **더블클릭 / 바로 가기 / 시작 프로그램:** `~\.samjil\viewer\start-viewer-hidden.vbs` — `wscript.exe`(창이 없는 프로그램)가 위 스크립트를 숨김 실행하므로 깜빡임도 없습니다. 윈도우 시작 때 자동으로 켜려면 이 파일의 바로 가기를 `shell:startup` 폴더에 넣으면 됩니다. 켜진 뒤에는 브라우저에서 `http://127.0.0.1:8787`을 직접 여세요.
    - **워처만:** `~\.samjil\delegate-agy\scripts\start-agy.ps1 -Hidden`(옵션이 없으면 `-NoExit` 콘솔 창이 뜹니다).
    - **끄기:** 창이 없어서 Ctrl+C 로 끌 수 없으므로 뷰어는 `ensure-viewer-running.ps1 -Stop`(`-Port`로 지정한 포트의 뷰어만 끕니다), 워처는 `stop-agy.ps1`을 씁니다.
    - 원리: 숨김 실행(`WScript.Shell.Run(명령, 0)`, 실패하면 `Start-Process -WindowStyle Hidden`)을 쓰고, 뷰어가 시작할 때 꺼진 워처를 켜는 것도 `start-agy.ps1 -Hidden`입니다. Windows Terminal 이 기본 터미널일 때는 파워셸 프로세스의 `MainWindowHandle`이 0 으로 나와서 창이 떠 있어도 "창 없음"으로 보이므로, 시험은 보이는 터미널/콘솔 창을 `EnumWindows`로 직접 셉니다.
  - **대시보드**: 지금 `agy`가 무엇을 하는지(작업 중 / 대기 / 워처 꺼짐 / 서버 연결 끊김. 작업 중이면 모델과 경과 시간)와 최근 위임 결과 띠, **확인 필요**(처리 대기 중인 인수인계 메시지, 최근 24시간 안에 실패한 위임), 위임과 인수인계를 합친 시간순 최근 활동, 누적 통계와 모델별 분포
  - **위임 실행 기록·에이전트 인수인계의 사이드바(Claude Desktop 프로젝트 → 대화 세션)**: 프로젝트 이름은 **Claude Desktop 앱 코드 탭의 사이드바 그룹 이름**(예: `ma::healthketch-webview`)이고, 프로젝트를 누르면 아래로 펼쳐져 그 그룹에 담긴 **Claude 대화 세션**(Desktop 에 보이는 세션 제목)이 나옵니다. 세션을 고르면 그 세션에서 보낸 위임 질문·답변(인수인계는 그 세션이 주고받은 메시지)이 본문에 보입니다. 펼침 상태는 브라우저에 기억합니다. **정렬**은 사이드바의 `정렬`에서 고릅니다: `날짜 최신순`(기본), `날짜 오래된순`, `이름순`, `이름 역순`, `Desktop 순서`(앱 사이드바에 둔 순서). 그룹에 담지 않은 세션은 `그룹 없음`, 어느 세션의 것인지 찾지 못한 기록은 `연결 안 됨`(아래에 예전 `@session` 이름 또는 인수인계 채널 이름별로 묶임)에 맨 뒤로 모입니다. 위임 기록 본문 맨 위에는 선택한 범위 안의 **agy 세션**(`@session` 이름) 칩이 나와 다시 좁혀 볼 수 있습니다. 주소는 `#/qa?project=<그룹 id>&session=<세션 id>&agy=<agy 세션 이름>`, `#/handoff?project=<그룹 id>&session=<세션 id>`.
    - **어느 세션의 기록인지 찾는 법**: 위임 기록·인수인계 메시지에는 Claude 세션 id 가 적혀 있지 않아서, 뷰어가 Claude 대화 기록(`~/.claude/projects/*/<세션 id>.jsonl`)에서 **위임 작업 ID(`claude_…`)와 인수인계 메시지 파일 이름(`0003-a2c-….md`)이 처음 나온 세션**을 찾습니다(포크한 세션은 원본 기록을 복사하므로 가장 이른 언급의 세션이 주인). 그룹·세션 목록은 `%APPDATA%\Claude\claude_desktop_config.json`(그룹 이름·배치만 읽고 다른 설정은 읽지 않음)과 `claude-code-sessions\*\*\local_*.json` 에서 읽습니다. 대화 기록은 수백 MB 라서 뷰어가 `scan-claude-links.ps1` 을 **창 없는 별도 프로세스**로 돌려(15초 넘게 지난 색인일 때 `/api/claude/tree` 요청이 시작) `<데이터 폴더>/claude-links.json` 색인을 늘려 갑니다(처음 약 10초, 이후엔 새로 쌓인 줄만 읽음). 이 모든 읽기는 읽기 전용이고 응답에는 그룹·세션 제목 같은 목록만 담습니다.
  - **위임 실행 기록 카드**: 모델·상태 필터와 검색. 카드 맨 윗줄에서 모델명과 소요 시간을 강조하고, 실패한 작업도 시도한 모델을 표시
    - 카드 본문은 **질문 / 답변** 두 줄입니다. **과정**은 `agy`가 질문과 답변 사이에 한 일, 즉 부른 도구 목록인데, 카드 맨 윗줄 오른쪽의 **`과정 13` 버튼**(숫자는 단계 수)으로 뺐습니다. 버튼을 **누르면 창(모달)**이 열려 단계 목록을 보여 줍니다(단계 번호 · 시각 · 한글 도구 설명 · 실제 대상 · 영어 라벨, 그리고 그 단계에서 `agy`가 적은 **생각**과 진행 **설명**). 창은 `Esc`, 바깥 클릭, `닫기`로 닫습니다. 단계 목록은 창을 열 때 처음 그리므로 카드가 수십 개여도 화면에는 버튼만 올라옵니다. 마우스를 올리면 `도구 호출 23번 · 명령 실행 9 · 파일 읽기 6 …` 요약이 보입니다. 볼 내용이 없으면(대기 중, 과정 미기록, 도구를 쓰지 않은 위임, `agy` 대화 기록 정리됨) 버튼이 비활성이고 이유가 마우스를 올리면 나옵니다.
    - **펼침 기본값**: 맨 위(가장 최근) 카드의 **답변만** 펼치고, 나머지는 질문·답변 모두 접은 채로 시작합니다. 직접 열거나 닫은 구역은 5초 자동 갱신 뒤에도 그대로 유지됩니다(페이지를 새로고침하면 기본값으로 돌아갑니다).
    - **`agy`의 말**: `agy`가 도구를 고르면서 적은 생각(`생각`, 영어 원문, 500자까지)과, 도구를 부르며 알린 진행 설명(`설명`, 있을 때만, 300자까지)을 단계마다 보여 줍니다. 진행 중인 카드는 "지금:" 줄 아래에 가장 최근 생각을 3줄까지 보이고, 응답에 생각이 없으면 더 앞 응답의 생각을 보입니다. 이 글들도 `process` 항목에 함께 저장됩니다(`think`, `say`). 번역은 하지 않습니다.
    - **한글로 번역** (두 방법): `agy`의 생각·설명·도구 라벨이 영어로 나온 단계가 있으면 과정 창 위쪽에 번역 버튼이 나옵니다(규칙 파일 `~/.gemini/config/GEMINI.md`로 한글을 요구해도 생각은 영어가 섞여 나오는 일이 잦아서 만든 기능입니다). 번역은 AI가 한 것이라 틀릴 수 있어서 화면에 번역본임을 표시합니다. 번역해 둔 글이 있으면 `원문 | agy 번역 | 브라우저 번역` 버튼으로 오갑니다.
        - **`agy로 번역`**: 서버가 `agy`(`gemini-3.8-flash-low`)에게 번역시킵니다. 품질이 좋고 코드·경로·식별자를 번역하지 않도록 지시할 수 있지만, 30초~1분 걸리고 `agy` 사용량을 씁니다(생각 7개 약 3천 자에 30초, 약 2만 토큰 — 대부분 `agy`의 기본 입력입니다). 번역은 숨김 창의 보조 스크립트(`sub/process-translate.ps1`)가 하므로 뷰어는 멈추지 않고, 결과는 `<데이터 폴더>/process-ko/<대화 ID>.json`에 캐시되어 다음부터는 어느 브라우저에서든 창을 열면 바로 보입니다. `agy`는 읽기 전용(`--mode plan`)·빈 임시 폴더에서 호출하고 입력 안의 지시는 따르지 않도록 프롬프트에 적어 둡니다. 이 호출도 `agy` 대화를 하나 만들어서 `agy` 대화 목록에 남고, 워처가 작업을 처리하는 도중에 번역하면 `agy` 쪽 일이 잠시 겹칩니다. 진행 중이던 작업에 새 단계가 생기면 `agy로 새 단계 번역`으로 새 단계만 번역합니다.
        - **`브라우저로 번역`**: 브라우저에 내장된 번역(Translator API, 영어→한국어)을 씁니다. 무료이고 빠르며 서버·`agy`를 거치지 않지만, 품질이 낮을 수 있고 지시를 줄 수 없습니다. 그래서 백틱(`` ` ``)으로 감싼 코드 표기(`top_words` 같은 것)가 번역 뒤에도 남아 있는지 확인하며 세 단계로 시도합니다: ① 글을 그대로 번역해 코드 표기가 모두 남았으면 사용 ② 아니면 코드를 자리표시자(`XQ1X`)로 바꿔 번역한 뒤 되돌림(모델이 대소문자·공백을 흐트러뜨려도 받아 줍니다) ③ 그래도 안 되면 문장별로 나눠 되는 문장만 번역하고 나머지 문장은 원문으로 둠(한 칸에 한글과 영어가 섞임). 끝내 못 쓴 칸은 원문으로 두고, 안내에 이유(코드 표기가 사라짐 / 빈 번역 / 번역기 오류와 그 메시지)와 번역기가 돌려준 글의 예를 보여 줍니다. 일부만 번역된 상태면 버튼이 `브라우저로 이어서 번역`으로 바뀌고 남은 칸만 번역합니다. Chrome 계열 데스크톱 브라우저에서만 버튼이 나오고, 처음에는 언어 팩(번역 모델)을 내려받을 수 있습니다(진행률 표시). 10초 안에 지원 여부에 답하지 않거나 영어→한국어를 지원하지 않는 브라우저면 이유를 보이고 멈추지 않습니다. 결과는 그 브라우저의 `localStorage`에만 최근 40개 대화까지 남습니다(서버에는 저장하지 않습니다).
    - **상대 경로**: 과정 목록과 진행 중 카드의 "지금:" 줄에서, 질문의 `@cwd` 폴더 아래 경로는 폴더 이름을 빼고 `src\a.py`처럼 보입니다(폴더 자체는 `.`, 명령 안에 적힌 경로도 같습니다). `@cwd` 밖의 경로와 `@cwd`가 없는 위임은 전체 경로 그대로이고, 마우스를 올리면 줄이기 전의 전체 경로와 `@cwd`가 보입니다. 기록(`process`)에는 항상 전체 경로가 저장됩니다.
    - **과정 기록**: 워처가 작업을 마칠 때 `agy`의 대화 기록(`~/.gemini/antigravity-cli/brain/<대화 ID>/.system_generated/logs/transcript_full.jsonl`)에서 도구 호출을 읽어 `qa-YYYY-MM.jsonl` 기록의 `process` 항목에 저장합니다(최대 400번, 코드 본문 같은 큰 인자는 빼고 대상만). `agy`의 대화 기록이 없어져도 과정이 남습니다. 도구를 쓰지 않았으면 `[]`, 대화 기록을 못 읽었으면 `null`입니다.
    - 이 기능 이전에 만든 옛 기록은 `process`가 없어서, `과정` 버튼을 **눌러 창을 열 때만** `/api/delegate/process?id=<대화 ID>`로 `agy` 대화 기록에서 읽어 옵니다(대화 기록이 정리됐으면 그렇게 안내하고, 읽기에 실패하면 창에서 `다시 시도`를 누를 수 있습니다). 진행 중인 카드의 창은 열어 둔 채로 5초마다 새 단계가 이어 붙고(스크롤 위치 유지), 작업이 끝나면 완료 기록의 과정으로 이어집니다. 진행 중인 카드의 `지금:` 줄에는 마지막 호출의 한글 도구 설명과 실제 대상이 나옵니다.
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
    - **동시 실행**: 워처는 지시파일마다 작업자 프로세스(`sub/agy-task-worker.ps1`, 보이지 않는 창)를 따로 띄워 **동시에 최대 3개**(`watch-agy.ps1 -MaxParallel N` 또는 환경변수 `AGY_MAX_PARALLEL`, 1이면 예전처럼 하나씩)를 돌립니다. **같은 `@session` 이름이면서 작업 폴더(`@cwd`, 세션에 저장된 폴더 포함)가 겹치는**(같은 폴더이거나 상위·하위 폴더, 폴더가 없는 것도 겹침으로 봅니다) 작업끼리만 차례로 하고, 세션이 다르면 같은 폴더여도, 같은 세션이어도 폴더가 서로 다르면 함께 돕니다. 세션이 없는 작업은 서로 독립입니다. 돌고 있는 작업마다 `logs/running/<작업 ID>.json`(작업자 PID·세션·폴더·모델·대화 ID)이 있고, 뷰어는 이것으로 "처리 중"인 작업을 모두 보여 줍니다. 작업자가 끝내지 못하고 사라지면 그 작업은 실패로 남기고 다시 시도하지 않습니다. `usage.csv`·기록 저장소·세션 파일·`watcher.log`는 이름 있는 뮤텍스로 한 번에 하나씩만 쓰고, `watcher.log` 줄에는 `[작업 ID]`가 붙습니다. **주의**: 같은 `@session` 이름을 서로 다른 폴더에서 동시에 쓰면 agy 대화는 하나라서 서로 섞일 수 있고, 새 대화를 시작하는 작업이 동시에 여럿이면 멈춤 점검이 "새 대화가 둘 이상"이라 꺼지고 절대 마감(30분)만 적용될 수 있습니다.
    - **`@cwd: <폴더>`는 여러 줄 가능** — 폴더마다 한 줄씩 쓰면 워처가 폴더마다 `--add-dir`를 한 번씩 넘깁니다(저장소와 문서 폴더처럼 폴더가 여럿 필요한 작업용). 줄 순서는 유지하고 같은 경로(대소문자·끝의 `\` 무시)는 한 번만 씁니다. 없는 폴더가 하나라도 있으면 `agy`를 부르지 않고 실패하며 오류에 없는 폴더가 모두 적힙니다. `@session`으로 이어가는 호출에 `@cwd`가 하나라도 있으면 이번 목록만 쓰고(합치지 않음), 하나도 없으면 세션에 저장된 목록을 씁니다. 한 줄짜리와 `cwd`가 문자열인 예전 세션 파일은 그대로 동작합니다. 뷰어는 폴더 목록을 모두 보이고(과정 창의 작업 폴더 줄, 경로 줄이기는 폴더가 여럿이면 폴더 이름부터), 상대 경로 이미지는 첫 번째 폴더 기준으로 찾습니다.
    - **`@session: <이름>`** — 같은 이름으로 다시 보내면 agy의 이전 대화를 이어갑니다. `@cwd`는 세션에 저장되므로 이어갈 때는 생략해도 됩니다.
    - **`@model: <ID>`** — 이번 호출에 쓸 모델을 고릅니다(아래 모델 선택).
  - **모델 선택**: 지시파일 맨 위에 `@model: <ID>`를 쓰면 이번 호출에 그 모델 하나만 씁니다(`gemini-3.8-flash-high|medium|low` 등 Gemini 계열). 쓰지 않으면 기본 우선순위(`gemini-3.8-flash-high`부터, 쿼터 초과 시 다음 모델)입니다. 고른 모델이 쿼터 초과·사용 불가면 다른 모델로 자동 전환하지 않고 실패로 기록하며, 허용 목록에 없는 값은 `agy`를 부르지 않고 바로 실패합니다. 이어가는 세션(`@session:`)은 시작할 때의 모델을 유지하므로 다른 모델을 지정하면 오류입니다. `samjil-delegate-agy` 스킬은 난이도에 따라 Claude가 모델을 고르고, 지정한 모델이 실패하면 사용자에게 묻습니다.
  - **상태 확인**: `ensure-agy-running.ps1 -CheckOnly -StaleThresholdSeconds 0`은 켜지 않고 `ALIVE`(종료 코드 0) / `DEAD`(1) / `MANUAL_STOP`(2)만 알려 줍니다. `samjil-delegate-agy` 스킬이 위임 직전에 이것으로 확인하고, 꺼져 있으면 사용자에게 켜도 되는지 먼저 묻습니다.

- **🛑 Antigravity CLI 위임 워처 안전 중지**:
  ```powershell
  ~\.samjil\delegate-agy\scripts\stop-agy.ps1
  ```
  처리 중인 작업(동시에 돌던 것 모두)은 끊지 않고, 전부 끝난 뒤 워처가 스스로 종료됩니다. 정지 신호 뒤에는 새 작업을 받지 않습니다.

---

## 🧪 테스트

위임 워처의 마감/멈춤 판정은 PowerShell 스크립트로 검증합니다(Pester 불필요). 실패하면 종료 코드 1을 돌려줍니다:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\agy-progress.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\delegate-agy\invoke-agy-once.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File testsepo\script-hygiene.tests.ps1
```

- `agy-progress.tests.ps1`: 대화 찾기, 마지막 활동 시각, 멈춤 판정 경계값 등 단위 테스트 (몇 초)
- `invoke-agy-once.tests.ps1`: 가짜 `agy`로 기다리는 루프를 끝까지 돌리는 통합 테스트 (약 1~2분). 임시 폴더에 `agy.exe`로 복사한 `powershell.exe`를 쓰므로 실제 `agy`는 건드리지 않습니다.
- `model-select.tests.ps1`: `@model:` 지시어 해석, 모델 검증(허용 목록·이어가는 세션), 가짜 `agy`로 후보 선택과 폴백 없음 확인 (약 20초)
- `watch-agy-parallel.e2e.tests.ps1`: 임시 런타임과 가짜 agy(자는 시간을 지시문으로 정함)로 동시 실행 규칙을 확인합니다 — 세션 없는 작업끼리 동시에 돎(표시 파일 PID·모델), 같은 세션+같은 폴더는 차례로, 같은 세션이어도 폴더가 다르면 동시에, 세션이 다르면 같은 폴더여도 동시에, 상위·하위 폴더는 겹침, 동시 한도 3, 작업자가 사라지면 실패 처리, 정지 신호 뒤 도는 작업을 기다렸다가 종료, 로그에 `[작업 ID]` 표시 (약 2분). 실제 워처는 건드리지 않습니다.
- `watch-agy-model.e2e.tests.ps1`: 임시 런타임으로 `watch-agy.ps1`을 실제로 띄워 `@model:`이 메인 루프 끝까지 이어지는지(처리 결과·`usage.csv`·`agy` 호출 기록) 확인합니다 (약 1분). 실제 워처는 건드리지 않습니다.
- `cwd-list.tests.ps1`: `@cwd` 여러 폴더의 세션 파일 저장·읽기(`Write-Session`/`Read-Session`: 배열 저장, 예전 문자열 형식 읽기·이어가기), 폴더 목록 규칙(`ConvertTo-CwdList`, 중복·순서·빈 값)과 뷰어 사본이 같은 규칙인지, 세션 고정 규칙(`Resolve-TaskCwds`: 이번 호출에 `@cwd`가 있으면 이번 목록만) (몇 초)
- `pending-cwd.tests.ps1`: 뷰어의 `/api/delegate/pending`이 `@cwd` 여러 줄을 폴더 배열(`cwd`)로 돌려주는지 — 두 폴더·한 폴더·없음·중복·본문 중간의 `@cwd`, JSON 배열 모양 (몇 초)
- `claude-sessions.tests.ps1`: Claude Desktop 그룹·세션 읽기(그룹 순서·중복·삭제된 그룹·보관 세션)와 위임 작업 ID·메시지 파일 이름 색인(가장 이른 언급이 주인, 증분 스캔, 덜 쓴 마지막 줄, 줄어든 파일, 수 MB 한 줄, 한글) — 가짜 Desktop·대화 기록 폴더만 씁니다
- `claude-tree-api.tests.ps1`: `/api/claude/tree` — 임시 뷰어에서 응답 모양(배열·객체), 스캔 시작 규칙(신선하면 안 띄움), 깨진 색인, Desktop 폴더 없음 (약 1분)
- `qa-tree.tests.js`(node): 위임 기록 트리 — 항목→(프로젝트, 세션) 판정, 트리 만들기·검색·선택 필터, 사이드바 정렬(`sortTreeNodes`), agy 세션 칩(`qaAgySessionsOf`)
- `handoff-tree.tests.js`(node): 인수인계 트리 — 메시지 파일 찾기, 연결·"연결 안 됨" 채널 노드, 세션별 메시지 모으기
- `cwd-list.tests.js`(node): 화면의 `@cwd` 처리 — 폴더 목록 읽기(문자열·배열·빈 배열), 맨 위 `@cwd` 줄들, 폴더가 여럿일 때 경로 줄이기(폴더 이름부터), 과정 창 옵션
- `ensure-viewer.tests.ps1`: `ensure-viewer-running.ps1`(창·탭 없이 뷰어 켜기) — 명령줄 구성, 포트별 뷰어 구분, 꺼져 있을 때 DEAD/NONE, 같은 포트의 다른 프로그램은 뷰어로 보지 않기, 임시 포트에 `-NoAgent` 뷰어를 숨김 실행해 `STARTED`·새로 보이는 터미널/콘솔 창 0개(`EnumWindows`로 셈)·cmd 창 없음, 두 번째는 `ALIVE`이고 또 켜지 않음, `-Stop`이 그 포트의 뷰어만 끄고 진짜 뷰어(8787)는 건드리지 않음, **뷰어와 워처가 둘 다 꺼진 임시 런타임에서 한 번에 켜면 워처까지 켜지고 새 창이 0개이며 `-NoExit` 워처가 없음**(뷰어가 `start-agy.ps1`을 `-Hidden` 없이 부르던 때는 이 시험이 실패함을 확인), `start-agy.ps1 -Hidden`, `start-viewer-hidden.vbs` (약 40초)
- `ensure-check-only.tests.ps1`: `ensure-agy-running.ps1 -CheckOnly`의 `ALIVE`/`DEAD`/`MANUAL_STOP` 판정
- `process-translate.tests.ps1`: 과정 번역 보조 스크립트(`process-translate.ps1`) — 한글이 이미 든 칸·이미 번역한 칸 건너뛰기, 덩어리 나누기, 답에서 JSON 꺼내기와 검증, 캐시 읽기·쓰기, 가짜 `agy`로 끝까지(읽기 전용 호출, 캐시 재사용, 새 단계만 번역, 대화 기록 없음, 깨진 답, 시간 초과) (몇 초)
- `agy-process.tests.ps1`: `agy` 대화 기록에서 과정(도구 호출 목록)을 읽는 `Read-AgyProcessSteps` 테스트 — 도구별 대상, 생각·진행 설명(`think`/`say`)과 글자 수 상한, 시각 변환, 이어 읽기(쓰는 중인 마지막 줄·파일이 바뀐 경우), 상한, BOM, 깨진 줄, 경로 문자가 든 대화 ID 거절 (몇 초)
- `qa-store.tests.ps1`: 기록 저장소(`qa-*.jsonl`) 쓰기 경로 — 작업자가 끝날 때 전체 기록을 읽지 않고 그 작업 한 건만 덧붙이는지(`Complete-TaskQaRecord`: 질문·답·토큰, `index.json` 갱신, 이미 들어간 작업은 중복 없음, 오류 경로, usage 행이 없을 때 전체 동기화로 물러남), 끊긴 줄 뒤에 새 기록이 같은 줄로 이어 붙지 않는지(`Add-QaLine`), 꼬리 중복 검사(`Test-QaTaskIdInShardTail`), 작업자 경로에서 `Update-QAReport`를 더 부르지 않는지 (몇 초)
- `testsepo\script-hygiene.tests.ps1`: 스크립트 점검(저장소 전체) — `.ps1` 의 BOM 규칙(런타임·시험은 있음, install/uninstall 은 없음), 줄바꿈이 섞이거나 CR 만 있는 줄, 깨진 글자, 문법 오류, 합치다 남은 충돌 표시, 함수 결과를 `@()` 없이 받아 `.Count`/`.Length`/`[ ]` 로 쓰는 위험한 모양(원소가 하나면 5.1 이 배열을 풀어 값이 빈다), 이 점검 규칙이 위험한 모양을 실제로 잡는지 (몇 초)

뷰어의 워처 자동 점검:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\watcher-health.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\viewer\serve-viewer-autostart.tests.ps1
```

- `watcher-health.tests.ps1`: 켜짐/꺼짐 판정(잠금 PID, PID 재사용, 하트비트와의 관계), 재시작 결정, 점검 주기, 켜기 요청 처리, `ensure`에 넘기는 인자 단위 테스트 (몇 초)
- `process-translate-api.tests.ps1`: 뷰어의 과정 번역 상태(`Get-ProcessTranslationState`)와 시작(`Start-ProcessTranslation`) — running/done/none/error/unavailable, 실제로 숨김 창 보조 스크립트를 띄워 끝까지, 캐시 재사용, 대화 기록이 정리된 뒤에도 번역 유지, 멈춘 표시 파일 (몇 초)
- `progress-detail.tests.ps1`: 진행 중인 카드의 서버 쪽 데이터(`Get-AgyProgress`) — 도구 12종의 대상, 최근 생각(마지막 응답에 없으면 앞 응답에서)·진행 설명, 백그라운드 표시, 과정 목록의 증분 읽기 (몇 초)
- `serve-viewer-autostart.tests.ps1`: `serve-viewer.ps1`을 실제로 띄우고 점검 주기를 3초로 줄여, 꺼져 있을 때 `ensure`를 띄우는지·살아 있거나 수동 정지면 안 띄우는지·그동안 다른 요청에 응답하는지·켜기 API(GET 405, 헤더 없는 POST 403, 켜져 있으면 already-running, 꺼져 있으면 started)를 확인합니다 (약 1분). 임시 폴더와 가짜 스크립트만 쓰며 실제 워처/뷰어는 건드리지 않습니다.

뷰어의 화면 쪽 텍스트 정리는 `node`로 검증합니다(`app.js`에서 함수 원문을 꺼내 실행하므로 복사본이 아닙니다):

```powershell
node tests\viewer\preview-text.tests.js
node tests\viewer\progress-text.tests.js
node tests\viewer\process-text.tests.js
```

- `preview-text.tests.js`: 질문·답변 미리보기에서 `merge_intervals`, `~/.samjil`, `src/*.ts`의 `_ ~ *`를 지우지 않고, `@cwd`/`@session`/`@model` 지시어 줄을 건너뛰는지
- `progress-text.tests.js`: 진행 중인 카드의 "지금:" 줄(한글 도구 설명 + 실제 대상 + 영어 라벨)과 그 아래 `agy`의 생각·설명, HTML 이스케이프
- `process-text.tests.js`: 과정 줄의 상태(`resolveProcessState`: 저장됨·대기·읽는 중·읽기 실패·정리됨, 버튼의 단계 수와 비활성 여부)와 창 안의 목록(번호·시각·도구·대상), 번역 버튼 줄(`agy로 번역`·`브라우저로 번역`·보기 전환·새 단계·다시 시도)과 번역본 적용, 브라우저 번역(코드 보호·되돌리기, 가짜 번역기로 칸별 진행·실패·이미 번역한 칸 건너뛰기), `@cwd` 아래 경로를 상대 경로로 줄이기(슬래시·대소문자·이름만 비슷한 폴더·정규식 특수문자), 400번 안내, HTML 이스케이프

---

## 💡 지원 에이전트
- **Google Antigravity**: 전역 플러그인(`~/.gemini/config/plugins/samjil-skills/`) 및 단일 스킬 정션을 통한 전역 자동 감지
- **Claude Code**: `~/.claude/skills/` 전역 스킬 자동 감지
- **Cursor / Windsurf / Cline**: `~/.agents/skills` 또는 `npx skills add`를 통한 지원
