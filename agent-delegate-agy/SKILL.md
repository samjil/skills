---
name: agent-delegate-agy
description: "사용자 컴퓨터에 agy 워처(~/.samjil/agent-delegate-agy/scripts/start-agy.bat)가 떠 있으면, 높은 모델 성능이 필요 없는 작업은 기본적으로 전부 Antigravity CLI(agy)에 파일 기반으로 위임해서 Claude quota를 아낀다. 위임이 기본값이고 직접 처리는 예외(맥락 필요/판단 필요/실수 비용 큼/Claude 전용 도구 필요/왕복보다 빠름)다. 프로젝트 폴더 코딩 위임은 대화당 폴더를 한 번 확인받고 이후 자동 위임한다. 위임 사실은 매번 짧게 밝히고, 워처가 응답하지 않으면 직접 처리로 폴백한다."
---

# agent-delegate-agy: Antigravity CLI 위임 (기본값 = 위임)

## 핵심 원칙

사용자의 목표는 **Claude quota 절약**이다. 그래서 판단 기준은 "이 작업이 위임할 만한가"가 아니라 **"이 작업이 정말 Claude여야만 하는가"** 이다.

> **높은 모델 성능이 필요 없는 작업은 기본적으로 전부 agy에게 위임한다.**
> 직접 처리는 아래 "직접 처리 예외" 5가지에 해당할 때만이다.

망설여지면 위임한다. agy 결과가 부실하면 그때 Claude가 보완하면 되고, 그래도 왕복 한 번 값이 Claude가 처음부터 다 하는 것보다 싸다.

## 직접 처리 예외 (이 5가지에 해당할 때만 Claude가 직접)

1. **이 대화의 맥락이 필요한 것** — 첨부파일, 이전 턴의 논의, Claude가 읽은 파일, 프로젝트 문서. (agy는 매번 빈 상태로 시작한다. 맥락을 프롬프트에 다 적어줄 수 있으면 그렇게 해서 위임해도 된다.)
2. **판단·설계·조율이 필요한 것** — 아키텍처 결정, 요구사항이 모호해 되물어야 하는 것, 트레이드오프 비교, 사용자 의도 파악.
3. **틀리면 비용이 큰 것** — 보안/인증/결제/키 관리, 마이그레이션, 되돌리기 어려운 변경, **정확한 최신 사실이 중요한 질문**(agy는 웹 검색 없이 답하므로 사실 주장은 신뢰하지 않는다).
4. **Claude 전용 도구가 필요한 것** — 웹 검색/브라우저, 데스크탑 제어, MCP 커넥터, 프로젝트 문서 읽기·쓰기, 아티팩트 발행, 문서 생성 스킬(docx/xlsx/pptx/pdf).
5. **위임 왕복(수십 초~수 분)보다 직접 하는 게 확실히 빠른 아주 사소한 것** — 한 줄 답변, 파일 하나 grep.

## 위임 대상 (넓게 — 예시일 뿐, 목록에 없어도 위 5가지가 아니면 위임)

- **코딩**: 범위가 명확한 기능 구현, 버그 수정, 테스트 작성, 리팩토링, 보일러플레이트/설정 파일, 코드베이스 구조 분석·요약, 마이그레이션 스크립트 초안
- **글쓰기·문서**: README/주석/docstring, 커밋 메시지, 변경 로그, 사용법 설명, 정리·요약, 번역, 문체 다듬기, 이름 짓기(변수/함수/파일)
- **변환·가공**: 데이터 포맷 변환(JSON↔CSV↔YAML), 정규식 작성, SQL 초안, 스키마·타입 정의 생성, 대량 텍스트 치환 규칙
- **분석**: 로그/스택트레이스 해석, 에러 메시지 원인 추정, 코드 리뷰 1차 훑기, 의존성 목록 정리
- **잡무**: 단순 계산, 목록 만들기, 체크리스트 초안, 스크립트(bash/PowerShell/python) 작성, 아이디어 브레인스토밍 초안

## 결과 처리

- agy 결과는 **초안으로 받아서 Claude가 가볍게 검수한 뒤** 사용한다. 명백히 틀렸거나 요구를 벗어났으면 Claude가 고치거나 다시 위임한다.
- **사실 주장(수치, 최신 정보, 인용)은 그대로 옮기지 않는다.** 사용자 원칙상 확실한 근거가 있는 것만 전달해야 하므로, 검증할 수 없으면 그 부분은 빼거나 Claude가 직접 확인한다.
- 위임했으면 **매번 답변에 한 줄로 밝힌다**: `(agy에게 위임한 결과입니다)` 또는 `(agy가 \`<폴더경로>\` 폴더에 직접 접근해 처리한 결과입니다)`. 자동화되어도 투명성은 유지한다.

## 사전 조건 및 런타임 자동 확인/설치

- `mcp__remote-devices__*` 도구가 이 세션에 있어야 한다. 없으면 위임 없이 바로 직접 처리.
- **위임 런타임 환경 자동 확인 및 설치:**
  이 스킬의 실행 스크립트와 런타임은 `~/.samjil/agent-delegate-agy/`에 위치합니다.
  작업을 수행하기 전, `~/.samjil/agent-delegate-agy/scripts/watch-agy.ps1` 또는 `start-agy.bat`이 존재하는지 확인합니다.
  만약 존재하지 않는다면(`npx skills` 등으로 스킬 파일만 설치된 경우), 터미널 도구를 통해 다음 명령어를 **자동 1회 실행**하여 samjil 런타임 환경을 즉시 설치하고 작업을 계속 진행합니다:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/samjil/skills/main/install.ps1 | iex"
  ```
- **위임 런타임 폴더(`~/.samjil/agent-delegate-agy/runtime`)를 찾는다.**
  독립 스킬 구조에서는 사용자 홈 디렉터리의 `~/.samjil/agent-delegate-agy/runtime`을 사용한다.
  (원격 장치 마운트 환경에서는 `~/mnt/` 아래를 자동 탐색한다.)
  아래 코드 블록은 각각 독립된 `device_bash` 호출이라 변수가 이어지지 않으므로, `$BASE`가
  필요한 블록마다 이 탐색을 맨 앞에 넣는다.

```bash
BASE=""
[ -d "$HOME/.samjil/agent-delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/agent-delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/delegate/runtime/inbox" ] && BASE="$HOME/.samjil/delegate/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.agent-delegate/runtime/inbox" ] && BASE="$HOME/.agent-delegate/runtime"
if [ -z "$BASE" ]; then
  BASE=$(find ~/mnt -maxdepth 6 -type d \( -path "*/.samjil/agent-delegate-agy/runtime" -o -path "*/.samjil/delegate/runtime" -o -path "*/.agent-delegate/runtime" \) 2>/dev/null | head -1)
fi
if [ -z "$BASE" ]; then
  for f in $(find ~/mnt -maxdepth 6 -type f -path "*/watch-agy.ps1" 2>/dev/null); do
    r="$(dirname "$(dirname "$f")")"; [ -d "$r/runtime/inbox" ] && BASE="$r/runtime" && break
  done
fi
[ -z "$BASE" ] && echo "위임 런타임 폴더(~/.samjil/agent-delegate-agy/runtime)를 찾지 못함" && exit 1
echo "found: $BASE"
```

  찾지 못하면(마운트가 안 됐거나 워처가 없으면) 위임 없이 바로 직접 처리로 폴백한다.
- 워처 생존 확인: `$BASE/logs/heartbeat/` 안의 `hb_*.txt` 파일 중 가장 최근 것의
  나이가 300초 이내면 정상 (PC 이름은 알 수 없으니 글롭으로 찾는다 - PC마다 독립 실행이라
  보통 파일이 하나뿐이다). 오래됐으면 워치독(`ensure-agy-running.ps1`)이 2분 안에 자동
  복구하므로, 한 번 더 시도해보고 그래도 안 되면 직접 처리로 폴백하면서 "워처가 꺼져 있는
   것 같다(~/.samjil/agent-delegate-agy/scripts/start-agy.bat 실행 필요)"고 한 번만 알린다.

```bash
H=$(ls -t "$BASE/logs/heartbeat"/hb_*.txt 2>/dev/null | head -1)
[ -n "$H" ] && echo "heartbeat age: $(( $(date +%s) - $(stat -c %Y "$H") ))s"
```

## 프로젝트 폴더 코딩 위임 (`@cwd`)

실제 소스 파일을 agy가 읽고/쓰게 하려면 지시문 맨 위에 `@cwd: <대상 폴더 절대경로>`를 쓴다. (`@cwd`는 agy의 공식 옵션이 아니라 이 브리지의 자체 규칙 — 워처가 이 줄을 파싱해 `--add-dir`로 실행한다.)

**폴더 확인 규칙**
- 폴더를 **추측하거나 임의로 고르지 않는다.** 이 대화에서 사용자가 명시했거나 확인해준 폴더만 쓴다. 없거나 모호하면 먼저 묻는다.
- 한 번 확인된 폴더는 **같은 대화 안에서는 계속 유효**하다. 새 대화가 시작되면 다시 확인받는다.
- **첫 확인 시에만 위험 고지**: 워처는 `--dangerously-skip-permissions`로 동작해서 agy가 승인 없이 그 폴더의 파일을 읽고/쓰고/삭제하고 임의 명령을 실행할 수 있다. git 등으로 되돌릴 수 있는 상태인지 한 줄로 확인한다.
- 확인 후에는 그 폴더에 대한 적합한 코딩 하위작업을 **매번 묻지 않고 자동 위임**한다.

## 여러 작업을 이어서 위임 (`@session`)

agy는 기본적으로 매번 빈 상태로 시작한다(이 스킬 맨 위 "직접 처리 예외 1번"이 그래서
있는 것). 하지만 **같은 큰 작업을 여러 단계로 나눠서 계속 위임**해야 할 때는 지시문
맨 위에 `@session: <이름>`을 추가하면 agy 쪽 대화가 이어진다 — 이전에 agy가 읽은
파일, 내린 판단, 만든 결정을 다시 설명 안 해도 된다.

```
@session: 결제모듈-리팩토링
@cwd: C:\project
이어서 다음 파일도 같은 방식으로 고쳐줘.
```

- **언제 쓰나**: 하나의 목표를 여러 번의 위임으로 쪼개서 진행할 때(예: "1단계: 구조
  분석해줘" → "2단계: 방금 분석한 대로 A 파일 고쳐줘" → "3단계: 이어서 B 파일도").
  각 위임이 서로 완전히 독립적이면(위 "위임 대상" 예시 대부분처럼) `@session` 없이
  매번 새로 시작하는 게 더 낫다 — 불필요하게 이전 대화를 끌고 가면 토큰만 늘어난다.
- **이름 짓기**: 그 작업을 나타내는 짧고 구체적인 이름(`결제모듈-리팩토링`처럼)을
  **같은 대화 안에서 일관되게** 쓴다. `@cwd` 폴더 확인 규칙과 마찬가지로 이름을
  임의로 짓지 말고, 새 작업 묶음을 시작할 때는 사용자에게 확인하거나 명확한 새 이름을
  쓴다.
- **`@cwd`는 세션에 고정(sticky)된다.** 첫 호출에서만 주면 이후 같은 세션 호출에서
  생략해도 자동으로 이어서 적용된다.
- 세션이 오래돼서 agy 쪽에서 만료됐더라도 걱정할 필요 없다 — 워처가 자동으로 새
  세션을 시작하고 계속 진행한다(사용자에게 보이는 동작 차이 없음).

## 실행 방법

```bash
set -e
BASE=""
[ -d "$HOME/.samjil/agent-delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/agent-delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/delegate/runtime/inbox" ] && BASE="$HOME/.samjil/delegate/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.agent-delegate/runtime/inbox" ] && BASE="$HOME/.agent-delegate/runtime"
[ -z "$BASE" ] && BASE=$(find ~/mnt -maxdepth 6 -type d \( -path "*/.samjil/agent-delegate-agy/runtime" -o -path "*/.samjil/delegate/runtime" -o -path "*/.agent-delegate/runtime" \) 2>/dev/null | head -1)
[ -z "$BASE" ] && for f in $(find ~/mnt -maxdepth 6 -type f -path "*/watch-agy.ps1" 2>/dev/null); do r="$(dirname "$(dirname "$f")")"; [ -d "$r/runtime/inbox" ] && BASE="$r/runtime" && break; done
[ -z "$BASE" ] && echo "위임 런타임 폴더(~/.samjil/agent-delegate-agy/runtime)를 찾지 못함" && exit 1

TASK_ID="claude_$(date +%s)_$RANDOM"
cat > "$BASE/inbox/$TASK_ID.md" <<'CLAUDE_TASK_EOF'
@cwd: C:\Users\username\workspace\my-project
<지시문 - 자기완결적으로. 필요한 맥락은 명시적으로 다 포함할 것>
CLAUDE_TASK_EOF

OUT="$BASE/outbox/$TASK_ID.response.md"
ERR="$BASE/outbox/$TASK_ID.error.log"
echo "submitted: $TASK_ID"
for i in $(seq 1 50); do
  if [ -s "$OUT" ]; then echo "===RESULT==="; cat "$OUT"; exit 0; fi
  if [ -s "$ERR" ]; then echo "===ERROR==="; cat "$ERR"; exit 1; fi
  sleep 3
done
echo "===TIMEOUT==="; exit 2
```

폴더 접근이 필요 없는 작업이면 `@cwd:` 줄만 빼면 된다.

**여러 개를 한 번에 위임**할 수도 있다(서로 독립적인 작업일 때). 워처는 **한 번에 하나씩 순서대로** 처리하므로 총 대기시간은 합산된다 — 한 배치에 2~3개까지만 묶는다.

```bash
set -e
BASE=""
[ -d "$HOME/.samjil/agent-delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/agent-delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/delegate/runtime/inbox" ] && BASE="$HOME/.samjil/delegate/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.agent-delegate/runtime/inbox" ] && BASE="$HOME/.agent-delegate/runtime"
[ -z "$BASE" ] && BASE=$(find ~/mnt -maxdepth 6 -type d \( -path "*/.samjil/agent-delegate-agy/runtime" -o -path "*/.samjil/delegate/runtime" -o -path "*/.agent-delegate/runtime" \) 2>/dev/null | head -1)
[ -z "$BASE" ] && for f in $(find ~/mnt -maxdepth 6 -type f -path "*/watch-agy.ps1" 2>/dev/null); do r="$(dirname "$(dirname "$f")")"; [ -d "$r/runtime/inbox" ] && BASE="$r/runtime" && break; done
[ -z "$BASE" ] && echo "위임 런타임 폴더(~/.samjil/agent-delegate-agy/runtime)를 찾지 못함" && exit 1

STAMP=$(date +%s)_$RANDOM
T1="claude_${STAMP}_a"; T2="claude_${STAMP}_b"
cat > "$BASE/inbox/$T1.md" <<'EOF_A'
<작업 1>
EOF_A
cat > "$BASE/inbox/$T2.md" <<'EOF_B'
<작업 2>
EOF_B

for i in $(seq 1 50); do
  ok=1
  for T in "$T1" "$T2"; do
    [ -s "$BASE/outbox/$T.response.md" ] || [ -s "$BASE/outbox/$T.error.log" ] || ok=0
  done
  [ "$ok" = 1 ] && break
  sleep 3
done
for T in "$T1" "$T2"; do
  echo "===== $T"
  cat "$BASE/outbox/$T.response.md" 2>/dev/null \
    || cat "$BASE/outbox/$T.error.log" 2>/dev/null \
    || echo "(아직 처리 중)"
done
```

**타임아웃 처리:** `device_bash` 한 호출은 최대 180000ms(3분)다. 코딩 작업은 이보다 오래 걸릴 수 있다. 타임아웃이 나도 **워처는 사용자 컴퓨터에서 계속 돌고 있으므로 작업은 진행 중이다.**
1. 작업을 다시 제출하지 않는다.
2. 잠시 후 같은 `$TASK_ID`의 `outbox/$TASK_ID.response.md`가 생겼는지만 확인하는 짧은 `device_bash` 호출을 다시 한다.

## agy 모델과 로그

`watch-agy.ps1`이 `$ModelPriority` 배열에 따라 `--model`을 직접 지정해 호출한다(현재 Gemini 계열). 위임할 때 모델을 지정할 필요는 없다. 결과는 `~/.samjil/agent-delegate-agy/runtime/logs/usage.csv`(작업별), `usage_summary.csv`(모델별 집계), `data/qa-*.jsonl`에 자동 기록된다.

## 구현 상세 (시행착오 기록 - 재발견 방지용)

- 지시문은 반드시 `<<'CLAUDE_TASK_EOF'` 처럼 **따옴표 붙은 heredoc**으로 써서 `$`, backtick이 셸에서 해석되지 않게 한다.
- agy 응답 JSON 스키마(2026-09 확인): `{conversation_id, status, response, duration_seconds, num_turns, usage:{input_tokens, output_tokens, thinking_tokens, cache_read_tokens, total_tokens}}`. model/cost 필드는 없어서 워처가 `--model`을 직접 지정하는 방식으로 모델명을 기록한다.
- `--cwd` 플래그는 agy.exe에 존재하지 않는다. 대상 폴더는 `--add-dir`로 추가한다(워처가 처리).
- `-p`는 값을 직접 받아야 한다(stdin 단독 사용 불가). 프롬프트의 큰따옴표는 워처가 호출 직전에 `\"`로 자동 이스케이프한다.
- 응답 파일 맨 앞에 UTF-8 BOM(`\ufeff`)이 붙어 있을 수 있으니 그대로 사용자에게 옮기기 전에 신경 쓴다.

## 독립 실행 및 다른 브리지와의 구분

이 스킬은 Antigravity CLI(agy) 전용 위임 스킬이며, 외부 브리지 도구 없이 스킬 내의 `scripts/start-agy.bat`을 실행하여 독립적으로 워처를 가동할 수 있다. 목적이 quota 분산이므로 Claude Code CLI로 위임하는 것은 의미가 없다.
