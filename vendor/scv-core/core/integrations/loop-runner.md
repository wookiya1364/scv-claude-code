# Ralph Loop 실행 템플릿 (SCV 외부 연동판)

이 템플릿은 SCV 업무방식에 맞춘 Ralph Loop 실행 규칙입니다.
**모든 명세의 원천은 `scv/promote/<slug>/` 의 PLAN.md / TESTS.md 와
`scv/SCV.md` 인덱스**입니다. 루프 진입 프롬프트(무엇에 집중할지, 패키지
매니저, 빌드/테스트 명령 등)는 **사용자가 자유 형식으로 직접 작성**합니다 —
SCV 가 정해주는 전용 설정 파일은 없습니다.

> 이 파일은 `<host-config>/loop-template.md` 를 대체하도록 설계되었습니다.
> `cp loop-runner.md <host-config>/loop-template.md` 로 교체하세요.

---

## 선행 조건 (구현 시작 전 반드시 확인)

**구현 루프는 `scv/promote/<slug>/` 계획 단위로 돈다.** 대상 slug 의
PLAN.md(Guardrails / Exit criteria 포함)와 TESTS.md 가 없으면 먼저
`/scv:promote` 로 계획을 만든 뒤 진입한다.

**계획 없이 즉흥 구현을 시작하지 않는다.**

## 핵심 원칙: 될 때까지 수정 → 테스트 → 보고

**모든 작업은 "한번 하고 넘어가는 것"이 아니라 "정상 동작할 때까지 반복"해야 한다.**

- 코드를 작성했으면 반드시 실행하여 동작을 확인한다.
- 에러가 나면 원인을 분석하고 수정한 뒤 다시 테스트한다.
- 테스트가 실패하면 실패 원인을 파악하고 코드를 수정한 뒤 재실행한다.
- 한번에 성공하면 좋지만, 실패해도 될 때까지 반복한다.
- 수정·검증마다 **`/scv:report` Claude Code 스킬을 호출**하여 협업툴에 진행 상황을 보고한다 (스크린샷/비디오 포함).
- 이 규칙은 Phase 구분과 무관하게 **모든 작업에 적용**된다.

---

## 실행 흐름

1. **진입 프롬프트 읽기**: 사용자가 자유 형식으로 작성한 루프 지시문(이번
   루프의 대상 slug, 패키지 매니저, 빌드/테스트 명령)을 읽는다.
2. **계획 문서 읽기**: `scv/SCV.md` 인덱스를 확인한 뒤 대상
   `scv/promote/<slug>/` 의 PLAN.md / TESTS.md (있으면
   FEATURE_ARCHITECTURE.md, Related Documents)를 읽는다.
3. **이터레이션 목표 결정**: PLAN.md 의 Exit criteria 와 TESTS.md 의
   시나리오 목록을 비교해 이번 이터레이션 목표를 정한다.
4. **반복 실행**: 매 반복마다 파일 상태를 확인하고, 미완료 항목 1~3개씩 진행한다.
   **매 반복의 구현 단계는 `/scv:work <slug>` 로 시작한다** — 루프 전체에 한 번이
   아니라 반복마다다. 새 세션을 띄우는 하네스라면 첫 반복에서만 얻은 승인이 다음
   반복에 남지 않아, 작업 공간 가드가 2 회차부터 쓰기를 거부한다.
5. **Phase 완료·실패 알림**: **반드시 `/scv:report` Claude Code 스킬**로만 보낸다. 직접 API 호출 금지.

---

## 수정 → 테스트 → 보고 루프 (모든 작업에 적용)

### 기능 구현 시
1. 코드 작성 (먼저 대상 PLAN.md 의 Guardrails 재확인)
2. 서버/앱 실행하여 동작 확인
3. 실패 시: 로그 확인 → 원인 분석 → 코드 수정 → 2번으로
4. 성공 시: 다음 작업으로

### E2E 테스트 시
1. TESTS.md 의 시나리오 목록에서 해당 E2E 확인
2. Playwright 또는 Chrome DevTools MCP 로 테스트 실행
3. 검증 실패 시:
   - **테스트 아티팩트 경로를 아래 "아티팩트 경로" 규칙으로 확인**
   - `/scv:report "<phase>" failed --summary "<원인>" --attempt <N>` 호출
   - 원인 분석 → 코드 수정 → 1번으로
4. 검증 통과 시:
   - `/scv:report "<phase>" passed --summary "<통과 항목>" --attempt <N>` 호출

### 아티팩트 경로 (SCV 아티팩트 계약)

`/scv:report` 의 `collect-artifacts.sh` 가 자동 수집하는 경로:
- Playwright: `test-results/**/*.{png,webm,mp4,zip}`
- Chrome DevTools MCP: `test-results/mcp/**`
- 로그: `test-results/logs/*.log` (실패 시 tail 20KB 자동 첨부)

**아티팩트가 없으면** `--summary` 에 `[아티팩트 없음: <사유>]` 를 명시하라. 말없이 생략 금지.

---

## /scv:report 호출 규칙

**Claude Code 는 Slack/Discord API 를 직접 호출하지 않는다.** 항상 `/scv:report` 스킬 경유:

```
/scv:report "<phase-name>" <status> [--summary "TEXT"] [--attempt N] [--event EVENT]
```

### 인자

- `<phase-name>` — 공백 포함 시 반드시 큰따옴표로 감싸라. 예: `"Phase 2 — 음성 코어"`
- `<status>` — `passed` / `failed` / `info`
- `--summary "TEXT"` — 실패 원인, 성공 항목 요약. 한국어 권장
- `--attempt N` — 몇 차 시도인지 (성공하든 실패하든 카운트)
- `--event EVENT` — REPORTING.md 의 이벤트 키 강제 지정 (기본은 status 에서 자동 추론)

### 출력 확인

- 성공: `OK <thread_ref>` — 이 ref 는 다음 첨부가 같은 스레드에 묶이는 데 쓰인다
- 실패: `ERROR <reason>` 와 non-zero 종료 — 즉시 재시도하지 말고, 로그를 확인해 원인(토큰/채널/네트워크)을 판별

---

## 환경 변수 (.env)

프로젝트 `.env` 에 반드시 포함:

```bash
# 공통
PROJECT_NAME=<project>
NOTIFIER_PROVIDER=slack      # 또는 discord

# Slack (NOTIFIER_PROVIDER=slack 일 때)
SLACK_BOT_TOKEN=xoxb-...
SLACK_CHANNEL_ID=C0XXXXX0
SLACK_CHANNEL_ID_PHASE_COMPLETE=C0XXXXX1
SLACK_CHANNEL_ID_E2E_FAILURE=C0XXXXX2

# Discord (NOTIFIER_PROVIDER=discord 일 때)
DISCORD_BOT_TOKEN=...
DISCORD_CHANNEL_ID=...
DISCORD_CHANNEL_ID_PHASE_COMPLETE=...
DISCORD_CHANNEL_ID_E2E_FAILURE=...
```

실제 값은 `.env.example` 을 참고해서 채우고, `.env` 는 절대 커밋하지 않는다.

---

## 공통 규칙

- 매 반복에서 파일 시스템 상태를 확인하라. 이미 존재하는 파일은 건너뛰거나 필요 시 수정만.
- `git commit` 은 Phase 별 1회. 메시지는 한국어 Angular 컨벤션.
- 패키지 매니저는 사용자의 진입 프롬프트에 명시된 것을 사용.
- LLM 호출 시 `/no_think` 태그 사용 (Qwen 등 thinking 비활성화가 필요한 모델).

---

## 종료 조건

`<promise>DONE</promise>` 은 다음 조건을 **모두** 만족한 후에만 출력하라:

1. 모든 Phase 가 완료됨 — 대상 계획의 TESTS.md 성공 기준 통과
2. PLAN.md 의 Exit criteria (있으면) 전부 충족
3. 각 Phase 완료 직후 `/scv:report "<phase>" passed` 호출 결과가 `OK <thread_ref>` 였음 (즉, 협업툴에 실제로 전송됨)
4. E2E 테스트가 있다면 모든 시나리오 통과 (실패 상태에서 DONE 출력 금지)

---

## 실행 명령어

```
loop-runner "<host-config>/loop-template.md 를 읽고 실행 흐름을 따르라. 대상 계획은 scv/promote/<slug>/ 의 PLAN.md·TESTS.md, 보고는 /scv:report Claude Code 스킬을 사용한다." --max-iterations 35 --completion-promise "DONE"
```
