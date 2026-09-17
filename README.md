# samjil AI Agent Skills

[![skills.sh](https://img.shields.io/badge/skills.sh-compatible-blue)](https://skills.sh)

Antigravity(agy) 및 Claude Code 등 AI 코딩 에이전트를 위한 공용 스킬 모음입니다.  
[skills.sh](https://skills.sh) 오픈소스 에이전트 스킬 규약(Agent Skills Specification)을 준수합니다.

---

## 📦 포함된 스킬 목록

| 스킬 | 설명 |
|---|---|
| [`agent-handoff/`](agent-handoff/) | Claude ↔ Antigravity(agy) 간 파일 기반 비동기 대화 채널 규약 및 자율 개설 프로토콜 |
| [`agent-delegate-agy/`](agent-delegate-agy/) | 복잡도/비용 판단에 따른 Antigravity CLI(agy) 작업 위임 기준 및 inbox/outbox 전달 규약 |

---

## 🚀 설치 방법

### 방법 1. `skills.sh` 표준 CLI (Node.js 환경)

```bash
# 전체 스킬 설치
npx skills add samjil/skills

# 또는 특정 스킬만 설치
npx skills add samjil/skills --skill agent-handoff
```

### 방법 2. PowerShell 원클릭 웹 설치 (Windows 전용, git/npm 불필요)

저장소를 clone하지 않아도, 새 PC에서 터미널을 열고 아래 한 줄만 실행하면 최신 스킬이 전역 설치됩니다:

```powershell
irm https://raw.githubusercontent.com/samjil/skills/main/install.ps1 | iex
```

### 방법 3. 로컬 저장소에서 설치

저장소를 clone한 후:

```powershell
.\install.ps1
```

---

## 🗑️ 스킬 제거 (Uninstallation)

설치와 마찬가지로 원클릭으로 안전하게 제거할 수 있습니다:

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
*(에이전트끼리 대화하면서 생성된 대화 기록(`~/.samjil/agent-handoff/`)은 사용자의 소중한 자산이므로 제거 시에도 절대 삭제되지 않고 영구 보존됩니다.)*

---

## 🛠️ 내장 부속 도구

별도의 외부 브리지 도구 없이 스킬 저장소 자체에 독립 실행 도구가 내장되어 있습니다:

- **🤝 에이전트 대화 웹 뷰어**:
  ```powershell
  .\agent-handoff\viewer\serve-handoff.bat
  ```
  실행 시 로컬 브라우저(`http://127.0.0.1:8787`)에서 프로젝트별 핸드오프 대화 타임라인, 상태 배지, 마크다운 본문을 실시간으로 열람할 수 있습니다.

- **⚡ Antigravity CLI 위임 워처**:
  ```powershell
  .\agent-delegate-agy\scripts\start-agy.bat
  ```
  실행 시 `~/.samjil/agent-delegate-agy/runtime/inbox`를 감시하며 Claude로부터 위임받은 작업을 `agy` CLI로 자동 처리하고 응답을 반환합니다.

---

## 💡 지원 에이전트
- **Google Antigravity**: `~/.gemini/config/skills.json`을 통한 전역 자동 감지 (Auto-Discovery)
- **Claude Code**: `~/.claude/skills/` 전역 스킬 자동 설치 및 동기화
- **Cursor / Windsurf / Cline**: `npx skills add`를 통한 프로젝트/전역 자동 배치
