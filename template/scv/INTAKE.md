---
name: intake
version: 1.0.0
status: active
last_updated: 2026-04-17
applies_to: []
owners: ["@team"]
tags: [standard, core, process, protocol]
standard_version: 1.0.0
merge_policy: overwrite
---

# INTAKE — 프로젝트 인터뷰 프로토콜

> **이 문서는 프로세스입니다. 프로젝트가 달라져도 내용이 변하지 않습니다.**
> 각 프로젝트는 아래 순서대로 Claude 와 대화하며 다른 표준 문서들(DOMAIN, ARCHITECTURE, DESIGN, …)을 zero-base 에서 채워갑니다.

## 0. 불변 원칙

1. **추측 금지** — 사용자의 명시적 답변 없이 어떤 섹션도 채우지 않는다. "이럴 것이다"로 쓰지 않는다.
2. **한 번에 하나** — 섹션 하나 완성 → 사용자 확인 → 다음 섹션. 일괄 채우기 금지.
3. **모호하면 추가 질문** — "예/아니오" 또는 구체 값이 나올 때까지 끝까지 따라 묻는다.
4. **역참조 충돌 시 즉시 중단** — 새로 합의한 내용이 기존 문서와 충돌하면, 어느 쪽을 수정할지부터 결정한다.
5. **모든 draft 해제는 사용자 확인으로** — Claude 가 임의로 `status: draft` → `active` 전환 금지.
6. **구현 금지 조건** — 표준 문서 중 어느 하나라도 `status: draft` 면 기능 구현을 시작하지 않는다. 먼저 이 INTAKE 를 돌려 해당 문서를 완성한다.
7. **기존 진행 상태 존중 (resume 규칙)** — INTAKE 를 "시작" 하라는 요청이 와도, **먼저 모든 표준 문서의 `status` 를 확인한다**. `active` 또는 `N/A` 인 문서는 이미 완료(또는 문서화 미채택 — adoption)로 보고 **해당 단계를 건너뛴다**. **`draft` 인 문서부터만** 이어서 진행. 단계 0 (프로젝트 개요) 도 DOMAIN 과 ARCHITECTURE 가 `active` 또는 `N/A` 면 완료로 간주하고 skip. **사용자가 명시적으로 "처음부터 다시" 요청하지 않는 한 절대로 step 0 부터 재시작하지 않는다**.

## 1. 전체 흐름 (단계별)

| 단계 | 대상 | 필수/선택 | 예상 시간 | 완료 판정 (resume 시 skip 기준) |
|---|---|---|---|---|
| **-1 (Pre)** | `scv/raw/` 에 **기존 자료 투입** | 권장 | 가변 | — (항상 선택) |
| 0 | 프로젝트 개요 수집 | 필수 | ~15분 | DOMAIN + ARCHITECTURE 둘 다 `status: active` 또는 `N/A` 면 완료 |
| 1 | `DOMAIN.md` | 필수 | 30~60분 | `status: active` 또는 `N/A` (adoption 모드에서 문서화 미채택) |
| 2 | `ARCHITECTURE.md` | 필수 | 30~60분 | `status: active` 또는 `N/A` |
| 3 | `DESIGN.md` | UI 있으면 필수 | 30~60분 | `status: active` 또는 `N/A` (UI 없음 또는 adoption) |
| 4 | `AGENTS.md` | AI 구성요소 있으면 | 30~60분 | `status: active` 또는 `N/A` (AI 없음 또는 adoption) |
| 5 | `TESTING.md` | 필수 | 20~40분 | `status: active` 또는 `N/A` |
| 6 | `REPORTING.md` | 필수 | 10분 | `status: active` 또는 `N/A` |

> **N/A 의 의미**: adoption 모드에서 hydrate 직후 모든 표준 문서는 `N/A` 로 시드됩니다. INTAKE resume check 는 `N/A` 를 "이 프로젝트에선 문서화 미채택" 으로 해석해 **해당 단계를 건너뜁니다**. 특정 subsystem 을 문서화하기로 결정해 `N/A → draft` 로 사용자가 직접 올리면, 그때부터 INTAKE 가 해당 문서를 채우도록 안내합니다.

각 단계마다 Claude 는 **해당 문서의 `How to elicit` 섹션을 그대로 따라 묻습니다.** 이 INTAKE 는 상위 순서만 정의합니다.

### 시작 시 Claude 가 먼저 할 일 (resume check)

1. `scv/{DOMAIN,ARCHITECTURE,DESIGN,AGENTS,TESTING,REPORTING}.md` 각각의 frontmatter `status` 를 확인한다.
2. 단계 0~6 을 위 "완료 판정" 기준으로 분류 → `done_steps` / `pending_steps` 로 나눈다.
3. **사용자에게 A/B 선택지를 명시적으로 제시한다** (자동 resume 금지):

   ```
   현재 INTAKE 진행 상태를 확인했습니다.
     active (완료)       : <active 문서 이름들>
     N/A    (문서화 미채택): <N/A 문서 이름들 — adoption 모드 기본>
     draft  (미완료)      : <draft 문서 이름들>

   어떻게 진행할까요?
     [A] 이어서 진행 — 미완료(draft) 인 <first draft> 부터 시작. active/N/A
         문서는 건드리지 않음. (일반적으로 이것이 맞습니다)
     [B] 처음부터 다시 — 단계 0 (프로젝트 개요) 부터 모든 문서를 재검토.
         기존 active 문서도 다시 질문. 큰 방향 전환이 있을 때만 선택.
   ```

4. 사용자 답변:
   - **A** → `draft` 첫 단계부터 진행. `active` / `N/A` 문서는 절대 수정하지 않음. `draft` 가 하나도 없으면 "pending 없음 — 모든 문서가 active 또는 N/A" 로 응답하고 대기.
   - **B** → step 0 부터 시작. 단, 기존 문서 내용을 **덮어쓰기 전 반드시 사용자 확인**. `status` 는 사용자가 명시 승인하기 전까지 그대로 유지.
   - **답이 모호하면** 다시 묻는다. 추측으로 진행 금지.
5. 전부 `active` 또는 `N/A` 이면 "모든 INTAKE 문서가 이미 완료(active) 또는 미채택(N/A) 입니다. 특정 문서를 `draft` 로 올려 문서화를 시작하고 싶다면 이름을 알려주세요" 로 응답하고 대기.

## 1.5. Pre-step — scv/raw/ 투입 (권장)

프로젝트에 **이미 존재하는 자료**(회의록·외부 사양서·디자인 스케치·경쟁사 분석·사용자 인터뷰 녹취 등)가 있다면, 단계 0 전에 `scv/raw/` 에 던져 넣으세요.

1. `scv/raw/README.md` 사용법 숙지 (아무거나 던져도 됨)
2. 자료 투입 → git commit
3. Claude 는 단계 0 시작 시 raw 자료를 먼저 훑어본 뒤 질문을 시작

**왜 하는가**: 팀이 오랫동안 쌓아온 맥락을 Claude 가 한번에 훑어 읽고, 사용자의 답변을 맹목적으로 받는 대신 "아, 이전 회의록에서 X 라고 하셨는데 여전히 유효한가요?" 같은 **근거 있는 질문**이 가능해집니다.

## 2. 단계 0 — 프로젝트 개요 (가장 먼저)

Claude 가 차례대로 묻는다:

1. "이 프로젝트가 **한 문장으로** 무엇을 하나요?"
2. "주요 사용자는 누구이며, 어떤 환경에서 사용하나요? (최대 3개 페르소나)"
3. "6개월 뒤 **무엇이 존재해야** 성공이라고 말할 수 있나요?" (관찰 가능한 결과물)
4. "이미 존재하는 유사 시스템이 있나요? (있다면 왜 이걸 새로 만드나요?)"
5. "기술적 제약은 무엇인가요?" (예: 언어/프레임워크 고정, 폐쇄망 운영, 레거시 연동)
6. "이 프로젝트에 **AI 에이전트(LLM/STT/TTS)** 가 포함되나요?"
   - YES → 4단계 `AGENTS.md` 실행 예정
   - NO → 4단계 건너뜀
7. "사용자 대면 **UI/웹/앱** 이 있나요?"
   - YES → 3단계 `DESIGN.md` 실행 예정
   - NO → 3단계 건너뜀

답변 기록 위치: `DOMAIN.md` 의 "미션/범위", `DESIGN.md` 의 페르소나(해당 시), `ARCHITECTURE.md` 의 "제약".

**사용자 확인**: "개요 합의 끝. DOMAIN 부터 시작할까요?"

## 3. 단계 1 ~ 6 진입 규칙

각 단계 시작 시:

1. 대상 문서를 연다
2. 해당 문서의 `## How to elicit` 섹션을 **순서대로** 묻는다
3. 답변을 해당 문서의 `## Structure` 빈 자리에 기록한다
4. `## Completion criteria` 체크리스트를 완성했는지 확인한다
5. 충족되면 사용자에게 "이 문서 `status: active` 로 승격해도 될까요?" 묻고 **사용자 승인 시에만** frontmatter 수정
6. 다음 단계로

중간에 사용자가 "잠시, X 는 다시 얘기하자" 고 하면 즉시 멈춘다. 시간이 오래 걸려도 한 단계에서 강제로 다음으로 넘어가지 않는다.

## 4. 단계 간 의존성

- 1(DOMAIN) 의 용어집이 있어야 2(ARCHITECTURE) 의 서비스 경계가 도메인 언어로 표현 가능
- 1~2 없이 3(DESIGN) 진행 불가 (무엇을 그릴지 모름)
- 4(AGENTS) 는 1(DOMAIN) 의 유스케이스가 선행되어야 에이전트 책임을 정의 가능
- 5(TESTING) 는 1~4 의 관찰 가능한 결과를 E2E 시나리오로 변환
- 6(REPORTING) 은 문서가 아니라 **설정** 이므로 마지막에 확인만

## 5. 완료 조건

이 INTAKE 가 "완료" 되려면:

- [ ] 필수 문서 전체 `status: active`
- [ ] AI 있는 프로젝트라면 `AGENTS.md` 도 `status: active`
- [ ] 각 문서의 `## Completion criteria` 체크리스트 전부 만족
- [ ] 사용자가 명시적으로 "**구현을 시작해도 좋다**" 고 확인

완료 후에야 Ralph Loop (`/ralph-loop` — **외부 커맨드. SCV 플러그인이 제공하지 않음**: `ralph-template-scv.md` 를 `~/.claude/ralph-template.md` 로 복사해야 사용 가능) 실행을 허용한다.

## 6. 재방문

프로젝트 도중 **요구사항 변경**이 생기면:

1. 변경 범위에 해당하는 단계를 **다시 연다** (이 INTAKE 를 처음부터 돌릴 필요 없음)
2. 해당 문서의 `status` 를 `active` → `in_revision` 으로 낮춘다 (옵션)
3. 변경 반영 후 다시 `active`
4. `CHANGELOG.md` (프로젝트 로컬) 에 기록 — "YYYY-MM-DD: <문서> 개정, 이유"

## 7. 관련 모듈

<!-- MODULES:AUTO START applies_to=intake -->
<!-- MODULES:AUTO END -->
