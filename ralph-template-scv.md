# Ralph Loop 실행 템플릿 (SCV 연동판)

이 템플릿은 SCV 업무방식에 맞춘 Ralph Loop 실행 규칙입니다.
프로젝트별 설정은 프로젝트 루트의 `scv/RALPH_PROMPT.md`(얇은 진입점)에 정의합니다.
**모든 명세의 원천은 프로젝트 루트 `scv/` 디렉토리의 표준 문서**입니다.

> 이 파일은 `~/.claude/ralph-template.md` 를 대체하도록 설계되었습니다.
> `cp ralph-template-scv.md ~/.claude/ralph-template.md` 로 교체하세요.

---

## 선행 조건 (구현 시작 전 반드시 확인)

**모든 필수 표준 문서가 `status: active` 여야 구현 루프를 돈다.** 하나라도 `status: draft` 면 다음 지시를 먼저 수행:

1. `scv/INTAKE.md` 를 읽고 해당 단계(draft 문서에 대응하는)를 사용자와 대화로 진행한다.
2. 문서를 채운 뒤 사용자 승인 하에 `status: draft` → `active`.
3. 그 후에만 아래 구현 루프로 진입.

**draft 상태를 방치하고 구현을 시작하지 않는다.**

## 핵심 원칙: 될 때까지 수정 → 테스트 → 보고

**모든 작업은 "한번 하고 넘어가는 것"이 아니라 "정상 동작할 때까지 반복"해야 한다.**

- 코드를 작성했으면 반드시 실행하여 동작을 확인한다.
- 에러가 나면 원인을 분석하고 수정한 뒤 다시 테스트한다.
- 테스트가 실패하면 실패 원인을 파악하고 코드를 수정한 뒤 재실행한다.
- 한번에 성공하면 좋지만, 실패해도 될 때까지 반복한다.
- 수정·검증마다 **`/scv:report` 슬래시 커맨드를 호출**하여 협업툴에 진행 상황을 보고한다 (스크린샷/비디오 포함).
- 이 규칙은 Phase 구분과 무관하게 **모든 작업에 적용**된다.

---

## 실행 흐름

1. **진입점 읽기**: `scv/RALPH_PROMPT.md` 를 읽는다. 이 파일은 표준 문서 경로, focus_phase, 패키지 매니저, 빌드/테스트 명령을 명시한다.
2. **표준 문서 전부 읽기 (필수 + 조건부)**: `scv/CLAUDE.md` 의 인덱스 순서대로 각 문서의 **현재 내용** 을 읽는다:
   - `scv/INTAKE.md` — 프로세스 확인 (수정 금지)
   - `scv/DOMAIN.md`, `scv/ARCHITECTURE.md` — 필수, 프로젝트별 내용
   - `scv/DESIGN.md` — UI 있는 프로젝트면 필수
   - `scv/AGENTS.md` — AI 에이전트 있으면 필수
   - `scv/TESTING.md`, `scv/REPORTING.md` — 필수 설정
   - `scv/promote/**` — 승격된 주제·계획 문서 (필요 시 해당 promote 만 로드)
3. **Phase 목표 결정**: `scv/RALPH_PROMPT.md` 의 `focus_phase` 와 `scv/TESTING.md` 의 E2E 시나리오 카탈로그를 비교해 이번 이터레이션 목표를 정한다.
4. **반복 실행**: 매 반복마다 파일 상태를 확인하고, 미완료 항목 1~3개씩 진행한다.
5. **Phase 완료·실패 알림**: **반드시 `/scv:report` 슬래시 커맨드**로만 보낸다. 직접 API 호출 금지.

---

## 수정 → 테스트 → 보고 루프 (모든 작업에 적용)

### 기능 구현 시
1. 코드 작성 (먼저 관련 표준 문서 재확인)
2. 서버/앱 실행하여 동작 확인
3. 실패 시: 로그 확인 → 원인 분석 → 코드 수정 → 2번으로
4. 성공 시: 다음 작업으로

### E2E 테스트 시
1. `scv/TESTING.md` 의 시나리오 카탈로그에서 해당 E2E 확인
2. Playwright 또는 Chrome DevTools MCP 로 테스트 실행
3. 검증 실패 시:
   - **테스트 아티팩트 경로를 `scv/TESTING.md` 규칙으로 확인** (아래 "아티팩트 경로" 섹션)
   - `/scv:report "<phase>" failed --summary "<원인>" --attempt <N>` 호출
   - 원인 분석 → 코드 수정 → 1번으로
4. 검증 통과 시:
   - `/scv:report "<phase>" passed --summary "<통과 항목>" --attempt <N>` 호출

### 아티팩트 경로 (TESTING.md 규칙)

`/scv:report` 의 `collect-artifacts.sh` 가 자동 수집하는 경로:
- Playwright: `test-results/**/*.{png,webm,mp4,zip}`
- Chrome DevTools MCP: `test-results/mcp/**`
- 로그: `test-results/logs/*.log` (실패 시 tail 20KB 자동 첨부)

**아티팩트가 없으면** `--summary` 에 `[아티팩트 없음: <사유>]` 를 명시하라. 말없이 생략 금지.

---

## /scv:report 호출 규칙

**Claude 는 Slack/Discord API 를 직접 호출하지 않는다.** 항상 슬래시 커맨드 경유:

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
- 패키지 매니저는 `scv/RALPH_PROMPT.md` 에 명시된 것을 사용.
- LLM 호출 시 `/no_think` 태그 사용 (Qwen 등 thinking 비활성화가 필요한 모델).

---

## 종료 조건

`<promise>DONE</promise>` 은 다음 조건을 **모두** 만족한 후에만 출력하라:

1. 모든 Phase 가 완료됨 — 각 Phase 의 `scv/TESTING.md` 성공 기준 통과
2. `scv/RALPH_PROMPT.md` 의 모든 검증 항목 통과
3. 각 Phase 완료 직후 `/scv:report "<phase>" passed` 호출 결과가 `OK <thread_ref>` 였음 (즉, 협업툴에 실제로 전송됨)
4. E2E 테스트가 있다면 모든 시나리오 통과 (실패 상태에서 DONE 출력 금지)
5. `scv/AGENTS.md` 의 분포 테스트·골든셋이 통과율 임계치 이상

---

## 실행 명령어

```
/ralph-loop "~/.claude/ralph-template.md 를 읽고 실행 흐름을 따르라. 프로젝트 설정은 RALPH_PROMPT.md, 표준 명세는 scv/*.md, 보고는 /scv:report 슬래시 커맨드를 사용한다." --max-iterations 35 --completion-promise "DONE"
```
