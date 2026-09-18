# samjil AI Agent Skills

[![skills.sh](https://img.shields.io/badge/skills.sh-compatible-blue)](https://skills.sh)

Antigravity(agy) 및 Claude Code 등 AI 코딩 에이전트를 위한 공용 스킬 모음입니다.  
[skills.sh](https://skills.sh) 오픈소스 에이전트 스킬 규약(Agent Skills Specification)을 준수합니다.

---

## 📦 포함된 스킬 목록

| 스킬 | 설명 |
|---|---|
| [`samjil-handoff/`](samjil-handoff/) | Claude ↔ Antigravity(agy) 간 파일 기반 비동기 대화 채널 규약 및 자율 개설 프로토콜 |
| [`samjil-delegate-agy/`](samjil-delegate-agy/) | 복잡도/비용 판단에 따른 Antigravity CLI(agy) 작업 위임 기준 및 inbox/outbox 전달 규약 |

---

## 🏗️ 아키텍처 설계 원칙

1. **저장소(`samjil/skills`)는 소스 코드 및 설치 패키지 전용**:
   - Git 저장소는 개발 및 배포용으로만 사용되며, 에이전트 스킬로 직접 연결되지 않습니다.
2. **순수 스킬 정의(`SKILL.md`)만 에이전트에 등록**:
   - **Claude Code**: `~/.claude/skills/<스킬명>` (정션 링크)
   - **Antigravity (AGY)**: `~/.agents/skills/<스킬명>/SKILL.md`
   - 에이전트 디렉터리에는 불필요한 스크립트나 웹 파일을 두지 않고 순수 스킬 정의만 깔끔하게 유지합니다.
3. **부속 도구/스크립트/웹 파일은 `~/.samjil/`에서 통합 관리**:
   - 웹 뷰어 서버 및 위임 실행 워처 등 추가 실행 도구는 `~/.samjil/` 아래에 안전하게 격리되어 관리됩니다.
   - 에이전트 간 대화 기록(`~/.samjil/samjil-handoff/<프로젝트>/msg/`)은 스킬을 삭제하거나 업데이트해도 **100% 영구 보존**됩니다.

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
*(에이전트끼리 대화하면서 생성된 대화 기록(`~/.samjil/samjil-handoff/`)은 사용자의 소중한 자산이므로 제거 시에도 절대 삭제되지 않고 영구 보존됩니다.)*

---

## 🛠️ 부속 도구 실행

설치 후 `~/.samjil/` 디렉터리에서 바로 실행할 수 있습니다:

- **🤝 통합 웹 대시보드 뷰어 (Handoff & Delegate QA)**:
  ```powershell
  ~\.samjil\viewer\serve-viewer.ps1
  # 또는
  ~\.samjil\viewer\serve-viewer.bat
  ```
  실행 시 로컬 브라우저(`http://127.0.0.1:8787`)에서 탭 전환을 통해:
  - **Handoff 탭**: 프로젝트별 핸드오프 대화 타임라인, 상태 배지, 마크다운 본문 실시간 열람
  - **Delegate QA 탭**: Antigravity CLI 위임 내역, 프롬프트, 답변, 토큰 사용량, 소요시간 실시간 확인

- **⚡ Antigravity CLI 위임 워처 시작/재시작**:
  ```powershell
  ~\.samjil\delegate-agy\scripts\start-agy.ps1
  ```
  실행 시 `~/.samjil/delegate-agy/runtime/inbox`를 감시하며 Claude로부터 위임받은 작업을 `agy` CLI로 자동 처리하고 응답을 반환합니다.

- **🛑 Antigravity CLI 위임 워처 안전 중지**:
  ```powershell
  ~\.samjil\delegate-agy\scripts\stop-agy.ps1
  ```

---

## 💡 지원 에이전트
- **Google Antigravity**: `~/.gemini/config/skills.json` (`~/.agents/skills`)을 통한 전역 자동 감지
- **Claude Code**: `~/.claude/skills/` 전역 스킬 자동 감지
- **Cursor / Windsurf / Cline**: `~/.agents/skills` 또는 `npx skills add`를 통한 지원
