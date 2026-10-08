---
name: samjil-delegate-agy
description: "사용자 컴퓨터에 agy 워처(~/.samjil/delegate-agy/scripts/start-agy.ps1)가 떠 있으면, 작업을 난이도로 나눠서 Claude는 '설계'와 '가장 어려운 수준'만 직접 처리하고 나머지(약간 어려움 이하의 구현·디자인 구현·글쓰기·분석 등)는 Antigravity CLI(agy)에 파일 기반으로 위임해서 Claude quota를 아낀다. 코딩뿐 아니라 디자인도 같은 기준(디자인 방향·시스템 설계는 직접, 그 명세대로의 구현은 위임)이다. agy 결과는 반드시 검토하고, Claude가 직접 했을 때의 수준에 못 미치면 그대로 쓰지 않고 피드백을 담아 만족할 때까지 재위임한다. 그 밖의 직접 처리 예외는 맥락 필요/실수 비용 큼/Claude 전용 도구 필요/왕복보다 빠름이다. 프로젝트 폴더 코딩 위임은 대화당 폴더를 한 번 확인받고 이후 자동 위임한다. 위임 사실은 매번 짧게 밝히고, 워처가 응답하지 않으면 직접 처리로 폴백한다. superpower 등 다른 스킬이 하위 작업을 서브에이전트(Agent/Task 도구)로 열려는 시점에도 이 분담 판단이 서브에이전트 스폰보다 먼저 적용된다."
---

# samjil-delegate-agy: Antigravity CLI 위임 (설계·최고 난이도는 직접, 나머지는 위임 + 필수 검토)

## 핵심 원칙

사용자의 목표는 **Claude quota 절약**이면서 **결과 품질 유지**다. 그래서 작업을 난이도로 나눠서 분담한다.
판단 기준은 "이 작업이 위임할 만한가"가 아니라 **"이 작업(또는 이 조각)이 설계이거나 가장 어려운 수준인가"** 이다.

| 난이도 | 누가 | 예 |
|---|---|---|
| **설계** | Claude 직접 | 아키텍처·구조 결정, 요구사항 해석, 트레이드오프 비교, 디자인 방향·시스템 설계 |
| **가장 어려운 수준** | Claude 직접 | Claude가 보기에 이 작업에서 가장 까다로운 조각 (복잡한 알고리즘·동시성·상태 설계, 핵심 화면의 완성도 등) |
| **약간 어려움 이하** (약간 어려움 / 보통 / 쉬움) | **agy에 위임** | 설계가 정해진 뒤의 구현, 보통 난이도의 버그 수정·리팩토링·테스트, 명세가 있는 UI 구현, 문서·번역·정리 |

- **분야와 상관없이 같은 기준이다.** 코딩, 디자인, 글쓰기, 분석, 잡무 모두 "설계와 가장 어려운 수준은 직접, 나머지는 agy"다.
- **큰 작업은 조각으로 쪼개서 분담한다.** 한 작업 안에서도 Claude가 설계와 가장 어려운 조각을 맡고, 나머지 조각은 설계 명세와 함께 agy에 넘긴다. (예: Claude가 모듈 구조와 인터페이스를 설계 → agy가 각 모듈 구현 → Claude가 검토)
- 난이도는 Claude가 작업 내용을 보고 판단한다. 약간 어려움인지 가장 어려움인지 애매하면 일단 위임하되 검토를 엄격히 하고, 아래 검토 루프에서 같은 문제로 거듭 미달하면 "가장 어려운 수준"으로 재분류해 직접 처리한다.

> **agy 결과는 검토 없이 쓰지 않는다.** 직접 처리했을 때의 수준에 못 미치면 그대로 쓰지 않고, 만족할 때까지 반복해서 고치게 한다. (자세한 규칙은 아래 "결과 처리: 필수 검토와 반복" 참고)

## 직접 처리 대상 (이 5가지에 해당할 때만 Claude가 직접)

1. **이 대화의 맥락이 필요한 것** — 첨부파일, 이전 턴의 논의, Claude가 읽은 파일, 프로젝트 문서. (agy는 매번 빈 상태로 시작한다. 맥락을 프롬프트에 다 적어줄 수 있으면 그렇게 해서 위임해도 된다.)
2. **설계, 그리고 가장 어려운 수준의 작업** — 아키텍처 결정, 요구사항이 모호해 되물어야 하는 것, 트레이드오프 비교, 사용자 의도 파악, 디자인 방향·시스템 설계, 그리고 위 표의 "가장 어려운 수준"에 해당하는 조각.
3. **틀리면 비용이 큰 것** — 보안/인증/결제/키 관리, 마이그레이션, 되돌리기 어려운 변경, **정확한 최신 사실이 중요한 질문**(agy는 웹 검색 없이 답하므로 사실 주장은 신뢰하지 않는다).
4. **Claude 전용 도구가 필요한 것** — 웹 검색/브라우저, 데스크탑 제어, MCP 커넥터, 프로젝트 문서 읽기·쓰기, 아티팩트 발행, 문서 생성 스킬(docx/xlsx/pptx/pdf).
5. **위임 왕복(수십 초~수 분)보다 직접 하는 게 확실히 빠른 아주 사소한 것** — 한 줄 답변, 파일 하나 grep.

## 다른 스킬이 서브에이전트를 열려는 시점에도 적용

`superpower` 류처럼 스킬 자신이 하위 작업을 Agent/Task 도구로 서브에이전트에 맡기는
방식으로 동작하는 스킬을 쓸 때도, **그 서브에이전트를 실제로 열기 전에** 이 스킬의
난이도 분담 판단을 먼저 적용한다. "다른 스킬이 시켜서"는 위임을 건너뛸 이유가 아니다.
Claude가 스스로 서브에이전트를 열려는 경우도 같다 — 서브에이전트도 Claude quota를 쓴다.

- 서브에이전트에 시키려는 하위 작업이 위 "직접 처리 대상" 5가지에 해당하지 않으면
  (= 설계도 가장 어려운 수준도 아니면), Claude 서브에이전트(Agent 도구) 대신 agy에
  위임한다 — 하위 작업의 지시문과 필요한 맥락을 그대로 agy 위임 지시문으로 옮기면 된다.
- 설계나 가장 어려운 수준의 하위 작업은 Claude가 직접(또는 Claude 서브에이전트로) 처리한다.
- 대상 4번("Claude 전용 도구가 필요한 것")은 그 하위 작업 자체가 웹 검색/브라우저/
  데스크탑 제어/MCP 커넥터/아티팩트 등 Claude 전용 도구를 실제로 써야 할 때만
  해당한다. 단지 "지금 서브에이전트 구조로 짜여 있다"는 이유만으로는 예외가 아니다.
- 난이도가 애매하면 일단 위임하고 결과를 엄격히 검토한다 (핵심 원칙과 동일).
- 서브에이전트 대신 위임한 결과도 아래 "결과 처리: 필수 검토와 반복"을 그대로 따른다.
- 위임했다면 다른 경우와 똑같이 "(agy에게 위임하고 Claude가 검토한 결과입니다)"로 짧게 밝힌다.
- 직접 처리 대상에 해당해서 Claude 서브에이전트를 그대로 쓰면, 어떤 사유 때문인지 한 줄로 밝힌다.
- 사용자가 Claude 서브에이전트를 명시적으로 요구했으면 그대로 따른다. 사용자 지시가 이 스킬보다 우선이다.

**agy로 옮길 때 주의할 점**

- 워처는 한 번에 하나씩 순서대로 처리한다. 병렬 서브에이전트 여러 개를 agy로 옮기면 대기시간이
  합산되므로 한 배치에 2~3개까지만 묶고, 나머지는 결과를 보며 이어서 보낸다.
- 워처의 agy 호출 한도(현재 600초)를 넘기면 결과 없이 중단된다. "코드베이스 전체에서 ~ 찾기"처럼
  서브에이전트라면 한 번에 맡겼을 넓은 작업은 폴더나 모듈 단위로 쪼개서 보낸다.
- agy가 실패하거나 한도를 넘기면 Claude가 직접 처리한다. 이때 서브에이전트로 되돌아갈지는 다시
  직접 처리 대상 5가지로 판단한다. 사유가 없으면 이 대화에서 직접 처리하는 쪽이 기본이다.

## 위임 대상 (넓게 — 예시일 뿐, 목록에 없어도 설계·가장 어려운 수준·직접 처리 대상이 아니면 위임)

여기 나온 작업이라도 그 안에서 **설계 부분과 가장 어려운 조각은 Claude가 직접** 하고, 나머지를 위임한다.

- **코딩**: 설계가 정해진 기능 구현, 버그 수정, 테스트 작성, 리팩토링, 보일러플레이트/설정 파일, 코드베이스 구조 분석·요약, 마이그레이션 스크립트 초안
- **디자인 구현**: 아래 "디자인 작업의 분담"에 따라 Claude가 정한 디자인 명세대로 하는 HTML/CSS/컴포넌트 구현, 반복 UI 요소, 반응형·접근성 보완, 스타일 정리
- **글쓰기·문서**: README/주석/docstring, 커밋 메시지, 변경 로그, 사용법 설명, 정리·요약, 번역, 문체 다듬기, 이름 짓기(변수/함수/파일)
- **변환·가공**: 데이터 포맷 변환(JSON↔CSV↔YAML), 정규식 작성, SQL 초안, 스키마·타입 정의 생성, 대량 텍스트 치환 규칙
- **분석**: 로그/스택트레이스 해석, 에러 메시지 원인 추정, 코드 리뷰 1차 훑기, 의존성 목록 정리
- **잡무**: 단순 계산, 목록 만들기, 체크리스트 초안, 스크립트(bash/PowerShell/python) 작성, 아이디어 브레인스토밍 초안

## 디자인 작업의 분담

웹 화면·UI 디자인도 같은 기준이다. **디자인을 통째로 agy에 맡기지 않는다.** "알아서 예쁘게 만들어줘" 같은 지시는
설계를 agy에 넘기는 것이므로 하지 않는다.

- **Claude가 직접**: 디자인 방향과 디자인 시스템 설계(색 팔레트, 타이포그래피, 간격 스케일, 레이아웃 구조, 컴포넌트 구성,
  인터랙션·모션 원칙), 그리고 가장 어려운 수준의 시각·인터랙션 부분(핵심 화면의 완성도, 복잡한 애니메이션 등).
- **agy에 위임**: 위 명세에 따른 구현 — HTML/CSS/컴포넌트 작성, 반복되는 UI 요소, 반응형 처리, 접근성 속성 보완, 스타일 정리.
- 위임 지시문에는 **명세를 구체적인 값으로 담는다**(색상 코드, 폰트, 간격 단위, 레이아웃 규칙, 지켜야 할 파일/클래스 이름).
  agy가 명세에 없는 디자인 결정을 새로 내리지 않게 한다.
- 결과 검토는 아래 필수 검토 규칙을 따른다. 디자인은 명세 준수, 화면 간 일관성, 가독성, 반응형, 접근성을 본다.
  렌더링 결과를 확인할 수 있는 도구(브라우저·스크린샷)가 있으면 코드만 보지 말고 실제 화면까지 확인한다.

## 결과 처리: 필수 검토와 반복

**agy가 돌려준 내용은 어떤 경우에도 검토 없이 사용하거나 사용자에게 전달하지 않는다.** 검토를 생략하거나 대충 훑는 것은 금지다.

1. **기준은 "Claude가 직접 처리했다면 냈을 수준"이다.** 그보다 미달이면 그대로 쓰지 않는다. 다음을 확인한다.
   - 요구사항과 설계 명세를 모두 충족했는가, 빠뜨리거나 임의로 바꾼 부분은 없는가
   - 정확성: 코드는 실제로 읽어서 논리·엣지 케이스·기존 코드와의 일관성을 보고, 실행할 수 있으면 빌드·테스트를 돌린다
   - `@cwd` 폴더에서 직접 수정한 작업은 바뀐 파일 목록과 diff를 확인해 범위 밖의 변경이나 삭제가 없는지 본다
   - 품질: 문서·글은 어색한 표현과 오류, 디자인은 위 "디자인 작업의 분담"의 검토 항목
   - **사실 주장(수치, 최신 정보, 인용)은 그대로 옮기지 않는다.** 사용자 원칙상 확실한 근거가 있는 것만 전달해야 하므로, 검증할 수 없으면 그 부분은 빼거나 Claude가 직접 확인한다.
2. **미달이면 구체적인 피드백을 붙여 다시 위임한다.** 무엇이 왜 부족한지, 기대하는 결과가 무엇인지를 적는다.
   같은 작업의 후속이면 `@session`(아래 "여러 작업을 이어서 위임")으로 이어서 보내 agy가 맥락을 유지하게 한다.
3. **만족할 만한 수준이 될 때까지 검토 → 피드백 → 재위임을 반복한다.** 미달 결과를 "일단 쓰고 넘어가기"는 하지 않는다.
4. **반복이 소용없으면 직접 마무리한다.** 같은 문제로 연속 3회 재위임해도 개선이 없거나 피드백 반영이 안 되면, 그 조각은
   "가장 어려운 수준"으로 재분류해 Claude가 직접 처리하고 사용자에게 한 줄로 알린다. (quota 절약보다 품질이 우선이다.)
5. 사소한 오류(오타, 한두 줄 수정)는 다시 위임하지 않고 Claude가 바로 고쳐도 된다. 왕복 비용이 고치는 비용보다 크기 때문이다.

**위임 사실은 매번 답변에 한 줄로 밝힌다**: `(agy에게 위임하고 Claude가 검토한 결과입니다)` 또는
`(agy가 \`<폴더경로>\` 폴더에 직접 접근해 처리하고 Claude가 검토한 결과입니다)`. 재위임을 반복했거나 Claude가 직접 고친
부분이 있으면 그 사실도 한 줄에 덧붙인다(예: "2회 재위임 후 일부 직접 보완"). 자동화되어도 투명성은 유지한다.

## 사전 조건 및 런타임 자동 확인/설치

- `mcp__remote-devices__*` 도구가 이 세션에 있어야 한다. 없으면 위임 없이 바로 직접 처리.
- **위임 런타임 환경 확인:**
  이 스킬의 실행 스크립트와 런타임은 사용자 홈 디렉터리의 `~/.samjil/delegate-agy/`에 위치합니다.
  작업을 수행하기 전, `~/.samjil/delegate-agy/scripts/sub/watch-agy.ps1` 또는 `start-agy.ps1`이 존재하는지 확인합니다.
  만약 존재하지 않는다면(스킬 규약만 단독 설치된 경우), 에이전트가 임의로 외부 스크립트를 내려받거나 실행하지 않고, 사용자에게 런타임 환경 구성이 필요함을 안내합니다:
  > "Antigravity 위임 워처 런타임(~/.samjil/delegate-agy/)이 감지되지 않았습니다. 저장소의 install.ps1을 실행하여 런타임을 구성해 주세요."
- **위임 런타임 폴더(`~/.samjil/delegate-agy/runtime`)를 찾는다.**
  독립 스킬 구조에서는 사용자 홈 디렉터리의 `~/.samjil/delegate-agy/runtime`을 사용한다.
  (원격 장치 마운트 환경에서는 `~/mnt/` 아래를 자동 탐색한다.)
  아래 코드 블록은 각각 독립된 `device_bash` 호출이라 변수가 이어지지 않으므로, `$BASE`가
  필요한 블록마다 이 탐색을 맨 앞에 넣는다.

```bash
BASE=""
[ -d "$HOME/.samjil/delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/samjil-delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/samjil-delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/agent-delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/agent-delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/delegate/runtime/inbox" ] && BASE="$HOME/.samjil/delegate/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.agent-delegate/runtime/inbox" ] && BASE="$HOME/.agent-delegate/runtime"
if [ -z "$BASE" ]; then
  BASE=$(find ~/mnt -maxdepth 6 -type d \( -path "*/.samjil/delegate-agy/runtime" -o -path "*/.samjil/samjil-delegate-agy/runtime" -o -path "*/.samjil/agent-delegate-agy/runtime" -o -path "*/.samjil/delegate/runtime" -o -path "*/.agent-delegate/runtime" \) 2>/dev/null | head -1)
fi
if [ -z "$BASE" ]; then
  for f in $(find ~/mnt -maxdepth 6 -type f -path "*/watch-agy.ps1" 2>/dev/null); do
    r="$(dirname "$(dirname "$f")")"; [ -d "$r/runtime/inbox" ] && BASE="$r/runtime" && break
  done
fi
[ -z "$BASE" ] && echo "위임 런타임 폴더(~/.samjil/delegate-agy/runtime)를 찾지 못함" && exit 1
echo "found: $BASE"
```

  찾지 못하면(마운트가 안 됐거나 워처가 없으면) 위임 없이 바로 직접 처리로 폴백한다.
- 워처 생존 확인: `$BASE/logs/heartbeat/` 안의 `hb_*.txt` 파일 중 가장 최근 것의
  나이가 300초 이내면 정상 (PC 이름은 알 수 없으니 글롭으로 찾는다 - PC마다 독립 실행이라
  보통 파일이 하나뿐이다). 오래됐으면 워치독(`ensure-agy-running.ps1`)이 2분 안에 자동
  복구하므로, 한 번 더 시도해보고 그래도 안 되면 직접 처리로 폴백하면서 "워처가 꺼져 있는
   것 같다(~/.samjil/delegate-agy/scripts/start-agy.ps1 실행 필요)"고 한 번만 알린다.

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

agy는 기본적으로 매번 빈 상태로 시작한다(이 스킬 맨 위 "직접 처리 대상 1번"이 그래서
있는 것). 하지만 **같은 큰 작업을 여러 단계로 나눠서 계속 위임**하거나, **검토에서 미달이 나와
피드백과 함께 재위임**해야 할 때는 지시문
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
[ -d "$HOME/.samjil/delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/samjil-delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/samjil-delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/agent-delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/agent-delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/delegate/runtime/inbox" ] && BASE="$HOME/.samjil/delegate/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.agent-delegate/runtime/inbox" ] && BASE="$HOME/.agent-delegate/runtime"
if [ -z "$BASE" ]; then
  BASE=$(find ~/mnt -maxdepth 6 -type d \( -path "*/.samjil/delegate-agy/runtime" -o -path "*/.samjil/samjil-delegate-agy/runtime" -o -path "*/.samjil/agent-delegate-agy/runtime" -o -path "*/.samjil/delegate/runtime" -o -path "*/.agent-delegate/runtime" \) 2>/dev/null | head -1)
fi
if [ -z "$BASE" ]; then
  for f in $(find ~/mnt -maxdepth 6 -type f -path "*/watch-agy.ps1" 2>/dev/null); do
    r="$(dirname "$(dirname "$f")")"; [ -d "$r/runtime/inbox" ] && BASE="$r/runtime" && break
  done
fi
[ -z "$BASE" ] && echo "위임 런타임 폴더(~/.samjil/delegate-agy/runtime)를 찾지 못함" && exit 1

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
[ -d "$HOME/.samjil/delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/samjil-delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/samjil-delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/agent-delegate-agy/runtime/inbox" ] && BASE="$HOME/.samjil/agent-delegate-agy/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.samjil/delegate/runtime/inbox" ] && BASE="$HOME/.samjil/delegate/runtime"
[ -z "$BASE" ] && [ -d "$HOME/.agent-delegate/runtime/inbox" ] && BASE="$HOME/.agent-delegate/runtime"
if [ -z "$BASE" ]; then
  BASE=$(find ~/mnt -maxdepth 6 -type d \( -path "*/.samjil/delegate-agy/runtime" -o -path "*/.samjil/samjil-delegate-agy/runtime" -o -path "*/.samjil/agent-delegate-agy/runtime" -o -path "*/.samjil/delegate/runtime" -o -path "*/.agent-delegate/runtime" \) 2>/dev/null | head -1)
fi
if [ -z "$BASE" ]; then
  for f in $(find ~/mnt -maxdepth 6 -type f -path "*/watch-agy.ps1" 2>/dev/null); do
    r="$(dirname "$(dirname "$f")")"; [ -d "$r/runtime/inbox" ] && BASE="$r/runtime" && break
  done
fi
[ -z "$BASE" ] && echo "위임 런타임 폴더(~/.samjil/delegate-agy/runtime)를 찾지 못함" && exit 1

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

`watch-agy.ps1`이 `$ModelPriority` 배열에 따라 `--model`을 직접 지정해 호출한다(현재 Gemini 계열). 위임할 때 모델을 지정할 필요는 없다. 결과는 `~/.samjil/delegate-agy/runtime/logs/usage.csv`(작업별), `usage_summary.csv`(모델별 집계), `data/qa-*.jsonl`에 자동 기록된다. 이 위임 기록과 Handoff 인수인계 내역은 통합 대시보드(`~/.samjil/viewer/serve-viewer.ps1` / http://127.0.0.1:8787)에서 브라우저 탭으로 실시간 확인할 수 있다.

## 구현 상세 (시행착오 기록 - 재발견 방지용)

- 지시문은 반드시 `<<'CLAUDE_TASK_EOF'` 처럼 **따옴표 붙은 heredoc**으로 써서 `$`, backtick이 셸에서 해석되지 않게 한다.
- agy 응답 JSON 스키마(2026-09 확인): `{conversation_id, status, response, duration_seconds, num_turns, usage:{input_tokens, output_tokens, thinking_tokens, cache_read_tokens, total_tokens}}`. model/cost 필드는 없어서 워처가 `--model`을 직접 지정하는 방식으로 모델명을 기록한다.
- `--cwd` 플래그는 agy.exe에 존재하지 않는다. 대상 폴더는 `--add-dir`로 추가한다(워처가 처리).
- `-p`는 값을 직접 받아야 한다(stdin 단독 사용 불가). 프롬프트의 큰따옴표는 워처가 호출 직전에 `\"`로 자동 이스케이프한다.
- 응답 파일 맨 앞에 UTF-8 BOM(`\ufeff`)이 붙어 있을 수 있으니 그대로 사용자에게 옮기기 전에 신경 쓴다.

## 독립 실행 및 다른 브리지와의 구분

이 스킬은 Antigravity CLI(agy) 전용 위임 스킬이며, 외부 브리지 도구 없이 스킬 내의 `scripts/start-agy.ps1`을 실행하여 독립적으로 워처를 가동할 수 있다. 목적이 quota 분산이므로 Claude Code CLI로 위임하는 것은 의미가 없다.
