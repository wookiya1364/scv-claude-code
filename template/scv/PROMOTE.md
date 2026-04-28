---
name: promote-protocol
version: 1.0.0
status: active
last_updated: 2026-04-20
applies_to: []
owners: ["@team"]
tags: [promote, protocol, process]
standard_version: 1.0.0
merge_policy: overwrite
---

# PROMOTE — 승격 문서 작성 규약

> **이 문서는 프로세스입니다.** 프로젝트마다 바뀌지 않습니다.
> `scv/raw/` 에 쌓인 자료를 정제해 `scv/promote/<slug>/` 로 승격하고, 구현 완료 후 `scv/archive/<slug>/` 로 이동시키는 전체 규약을 정의합니다.

---

## 1. 한 장 요약

```
scv/raw/ 투입 → /scv:promote (Claude 가 대화로 정제)
             → scv/promote/<YYYYMMDD>-<author>-<slug>/
                 ├── PLAN.md    (필수)
                 ├── TESTS.md   (필수)
                 └── 자유 확장 파일들 (선택)
             → /scv:work <slug> (구현 + 테스트)
             → scv/archive/<YYYYMMDD>-<author>-<slug>/ (완료 시 이동)
```

---

## 1.5. Adoption 모드에서의 사용 (기본 모드)

`hydrate.sh init .` (기본) 로 hydrate 했다면 이 모드입니다. 표준 문서 (DOMAIN, ARCHITECTURE, 등) 가 `status: N/A` 로 시드되고 **INTAKE 가 강제되지 않습니다**. promote 루프는 그대로 작동:

1. 작업할 **subsystem 단위**로 `scv/raw/` 에 자료 투입 (회의록·기획서·외부 스펙 등)
2. `/scv:promote` → `scv/promote/<YYYYMMDD>-<author>-<slug>/` 생성
3. PLAN.md 맨 앞부분 `Summary` / `Goals` 에 **이 계획이 다루는 범위 (scope)** 를 명시 (예: "결제 v2 subsystem only. 물류·프로모션은 out of scope")
4. 기존 Confluence 스펙이나 Jira 티켓은 `refs:` 로 연결 — **본문 재작성 불필요**
5. `/scv:work <slug>` 로 구현 → 테스트 → archive

특정 subsystem 을 정식 문서화하고 싶어지면, **그 부분만** `scv/DOMAIN.md` 등에서 해당 섹션을 scope 좁혀 `N/A → draft → active` 로 단계적으로 승격. 전체를 한꺼번에 채우지 않아도 됩니다.

> **대형 legacy 에 적용할 때의 현실적 경로** — 1 개 subsystem (예: 결제 리팩토링) 만 scope 잡아 1 달 SCV 사용 → 효과 확인 후 다른 팀·subsystem 으로 확산. 전체 시스템 INTAKE 는 비현실적이고 drift 만 유발.

---

## 2. 폴더 이름 규칙 (절대 규칙)

```
<YYYYMMDD>-<author>-<slug>/
```

- **YYYYMMDD** — 계획 생성일 (ISO 날짜)
- **author** — 작성자 식별자 (기본: `git config user.name`, 소문자·하이픈)
- **slug** — 주제 식별자 (kebab-case, 3~5 단어)

**예시**:
- `20260420-sspark-user-auth-refactor/`
- `20260421-kmlee-payment-api-v2/`
- `20260422-team-infra-migration/`

**왜 author 를 기본 포함하나**: 팀원 간 동일 slug 충돌 방지. `/scv:promote` 가 slug 제안 시 자동으로 date + author prefix 를 붙여줍니다.

---

## 3. 필수 파일 2개 + 자유 확장

모든 승격 폴더는 **PLAN.md + TESTS.md 두 파일은 반드시**. 나머지는 필요한 만큼 자유롭게.

```
20260420-sspark-user-auth/
├── PLAN.md          # 필수 — 계획 본문 + frontmatter
├── TESTS.md         # 필수 — 테스트 시나리오 + 패스 기준
├── REQUIREMENTS.md  # 선택 — 상세 요구사항 (규모 크면 분리)
├── ARCH.md          # 선택 — 아키텍처 설계
├── MIGRATION.md     # 선택 — 마이그레이션 전략
├── notes.md         # 선택 — 작업 메모·의사결정 기록
├── diagrams/        # 선택 — 다이어그램·스크린샷
└── attachments/     # 선택 — 외부 PDF, 레퍼런스
```

### 크기별 권장 구조

| 규모 | 구조 |
|---|---|
| ≤ 1일 작업 | `PLAN.md` + `TESTS.md` 만 |
| 2 ~ 5일 | 위 + `ARCH.md` **또는** `REQUIREMENTS.md` 중 하나 |
| 주 단위 | 필요한 만큼 자유 분화 (ARCH, REQUIREMENTS, API, MIGRATION, assets/ 등) |

작게 시작 → PLAN.md 의 Approach 섹션이 50 줄 넘어가면 "ARCH.md 로 분리할까요?" 를 `/scv:work` 가 자동 제안합니다.

---

## 4. PLAN.md 템플릿 (복사해서 쓰세요)

```markdown
---
title: 사용자 인증 플로우 리팩토링
slug: 20260420-sspark-user-auth-refactor
author: sspark
created_at: 2026-04-20
status: planned          # planned | in_progress | testing | done
tags: [auth, security]
raw_sources:
  - scv/raw/2026-04-18-auth-review/notes.md
refs:
  - type: jira
    id: PAY-1234
  - type: jira
    id: PAY-1235
  - type: confluence
    url: https://confluence.example.com/x/design-v2
  - type: pr
    url: https://github.com/org/repo/pull/567
# 거대 요구를 여러 feature 로 쪼갰을 때 같은 epic 으로 묶음 (개수는 raw 에 맞춰 결정. 자세한 건 §8d)
epic: 20260424-payment-overhaul
kind: feature                          # feature | refactor | retirement (기본 feature)
# 회귀 테스트에서 이 계획이 폐기하는 과거 slug/시나리오 (자세한 건 §8b)
supersedes:
  - 20260115-sspark-user-auth-v1      # v1 전체 대체 → v1 의 TESTS 는 회귀에서 영구 skip
supersedes_scenarios:
  - 20251201-kmlee-legacy-login:T3    # legacy-login 의 T3 시나리오만 폐기 (다른 T 는 계속 회귀)
---

# {{title}}

## Summary

1~3 문장으로 "무엇을 · 왜" 요약.

## Goals / Non-Goals

- **Goals**
  - ...
- **Non-Goals**
  - ...

## Approach Overview

5 ~ 15 줄의 전체 설계 요약. 이 섹션이 50 줄 넘어가면 → `ARCH.md` 로 분리 권장.

## Steps

1. ...
2. ...
3. ...

## Related Documents

<!-- 규모 있는 계획은 여기에 보조 파일 링크. 없으면 빈 섹션 유지. -->
<!-- 예:
- [`REQUIREMENTS.md`](./REQUIREMENTS.md) — 상세 요구사항
- [`ARCH.md`](./ARCH.md) — 아키텍처 설계
- [`MIGRATION.md`](./MIGRATION.md) — 마이그레이션 전략
-->

## Risks / Open Questions

- ...

## Links

- raw 원본: `scv/raw/...` (readpath.json 에서 consume)
- 관련 PR: (해당 시)
```

### frontmatter 필드

| 필드 | 필수 | 설명 |
|---|:-:|---|
| `title` | ✓ | 사람이 읽는 제목 (한 줄) |
| `slug` | ✓ | 폴더명과 정확히 일치 |
| `author` | ✓ | 작성자 (`git config user.name` 기반) |
| `created_at` | ✓ | ISO 날짜 |
| `status` | ✓ | `planned` / `in_progress` / `testing` / `done` |
| `tags` | ✓ | 키워드 배열 (검색/필터용) |
| `raw_sources` | — | 관련 raw 파일 경로 배열 (있으면 역추적 가능) |
| `refs` | — | 외부 참조 배열 (Jira / Linear / Confluence / PR 등). 아래 스펙 참조 |
| `supersedes` | — | 이 계획이 폐기(supersede)하는 **과거 slug 배열**. `/scv:regression` 이 해당 archived TESTS 전체를 영구 skip. 아래 §8b 참조 |
| `supersedes_scenarios` | — | **scenario 단위** 폐기. `<slug>:T<n>` 형식 문자열 배열. 예: `["20260115-sspark-auth-v1:T2"]` |
| `epic` | — | 거대한 사용자 요구를 여러 feature 로 쪼갰을 때 같은 epic slug 로 묶음 (분할 갯수는 raw 의 내용에 맞춰 Claude 가 제안 + 사용자 조정). `/scv:status` 가 epic 진척도 표시, `/scv:work` 의 PR 자동 생성이 epic 브랜치 기본값. 아래 §8d 참조 |
| `kind` | — | `feature` (기본) / `refactor` (epic 마무리 통합 정리) / `retirement` (순수 제거 — §8c). Claude 가 epic 흐름·refactor 안내에 사용 |

### `refs:` 스펙 — 벤더-중립 외부 참조

특정 벤더 이름을 frontmatter 최상위 키로 하드코딩하지 않고, **타입이 있는 배열**로 무제한 확장:

```yaml
refs:
  - type: jira          # 타입은 자유 문자열 (jira / linear / asana / notion / confluence / pr / slack-thread / ...)
    id: PAY-1234        # 티켓 ID — `.env` 의 <TYPE>_BASE_URL 로 URL 유추
  - type: jira
    id: PAY-1235        # 같은 type 여러 개 OK
  - type: confluence
    url: https://confluence.example.com/x/design-v2  # 직접 URL 도 가능
  - type: pr
    url: https://github.com/org/repo/pull/567
```

**규약:**

- **배열의 원소 간 제약 없음** — 같은 `type` 여러 개, 순서 자유
- 각 원소는 **`id` 만, `url` 만, 또는 둘 다** 가능
  - `id` 만 있고 `url` 없으면 `.env` 의 `<TYPE>_BASE_URL` 과 조합해 URL 유추 (설정 안 되어 있으면 ID 만 표시)
  - `url` 이 있으면 그대로 사용
- `type` 값은 자유. SCV 가 아는 타입은 렌더링 힌트 제공, 모르는 타입은 그냥 링크로 통과
- **아카이브 시 `refs:` 는 그대로 `ARCHIVED_AT.md` 에 보존** (감사 추적용)

**`.env` 에 base URL 설정 예시:**

```bash
JIRA_BASE_URL=https://company.atlassian.net
LINEAR_BASE_URL=https://linear.app/company
CONFLUENCE_BASE_URL=https://confluence.example.com
```

`/scv:work` 출력에서 같은 `type` 끼리 묶여 사람이 읽기 좋게 나옵니다:

```
[jira] 2 tickets
  · PAY-1234 → https://company.atlassian.net/browse/PAY-1234
  · PAY-1235 → https://company.atlassian.net/browse/PAY-1235
[confluence] 1 doc
  · https://confluence.example.com/x/design-v2
[pr] 1 PR
  · #567 → https://github.com/org/repo/pull/567
```

---

## 5. TESTS.md 템플릿

```markdown
# Test Plan — {{title}}

## 개요

어떤 동작을 · 어떻게 · 왜 검증하는지 1 단락 요약.

## 테스트 시나리오

### T1. 기본 로그인 성공

- **전제**: 등록된 사용자 계정 1개, 올바른 비밀번호 보유
- **실행**: `POST /api/login` with valid credentials
- **기대**: 200 OK + JWT 토큰 반환
- **Pass 기준**: 토큰 서명 유효, exp 가 1시간 이내

### T2. 비밀번호 오류 시 401

- **전제**: 등록된 계정
- **실행**: 틀린 비밀번호로 로그인
- **기대**: 401 Unauthorized
- **Pass 기준**: 토큰 반환 없음, 에러 메시지 고정 문구

## 실행 방법

```bash
npm run test:auth
```

## 통과 판정

- 모든 시나리오 Pass 기준 충족
- 코드 커버리지 ≥ 80%
- E2E (`npm run test:e2e -- auth`) 전부 통과

## Related Documents

<!-- 테스트가 많아 추가 분리한 경우:
- [`tests/e2e-scenarios.md`](./tests/e2e-scenarios.md) — E2E 시나리오 상세
- [`tests/load.md`](./tests/load.md) — 부하 테스트
-->
```

### TESTS.md 최소 요건 (Pass 판정 필수)

- [ ] **실행 방법**이 `bash` / `npm` / `pnpm` 등 명확한 커맨드로 적혀 있음
- [ ] **Pass 기준**이 각 시나리오마다 관찰 가능한 형태로 명시됨
- [ ] **통과 판정** 블록에 "전체 done 선언 조건" 이 있음

하나라도 모호하면 `/scv:work` 는 구현 시작 전에 사용자에게 질문합니다.

### 회귀 재실행을 염두에 둔 작성 가이드

TESTS.md 는 `/scv:work` 최초 구현 검증 + **archive 이후 `/scv:regression` 이 누적 회귀로 계속 호출**합니다. 두 가지 작성 패턴:

1. **통합 커맨드** (기본) — `## 실행 방법` 블록 하나로 전체 시나리오 일괄 검증.
   ```bash
   npm run test:auth        # T1~T5 전부 검증
   ```
2. **scenario 디스패치** (권장, 부분 skip 대응) — `T=$T_FILTER` 환경변수로 필터.
   ```bash
   if [[ "${T_FILTER:-all}" == "all" ]]; then
     npm run test:auth
   else
     npm run test:auth -- --grep "$T_FILTER"
   fi
   ```
   이 패턴을 쓰면 후속 계획이 `supersedes_scenarios: ["<slug>:T2"]` 로 T2 만 skip 하고 나머지는 회귀에서 계속 돌게 할 수 있음. 디스패치가 없으면 `/scv:regression` 은 scenario-level skip 을 지원할 수 없어서 경고 후 slug 전체 skip 으로 폴백.

---

## 6. Related Documents 규약

- PLAN.md · TESTS.md 두 파일 모두 **`## Related Documents` 섹션을 빈 채로라도 반드시** 포함
- 링크는 **상대경로** (같은 폴더 내): `[ARCH.md](./ARCH.md) — 한 줄 설명`
- `/scv:work` 는 이 섹션 밖의 파일은 **기본적으로 로드 안 함** (토큰 가드)
- 사용자가 명시 지시 (예: "ARCH 도 보고 구현해") 하면 추가 로드

### 언제 분리할지 (Claude 가 판단 기준)

| 신호 | 제안 |
|---|---|
| Approach Overview 50 줄 초과 | → `ARCH.md` |
| 요구사항이 bullet 20개 초과 | → `REQUIREMENTS.md` |
| API spec 이 10 엔드포인트 초과 | → `API.md` |
| 마이그레이션 단계가 5개 초과 | → `MIGRATION.md` |
| 테스트 시나리오 15개 초과 | → `tests/` 하위 분리 |

사용자가 **"분리해"** 라고 명시하면 판단 기준 무시하고 무조건 분리. **"분리하지 마"** 라고 하면 Claude 도 제안 중단.

---

## 7. `/scv:promote` 와 `/scv:work` 의 책임 분담

| 단계 | 커맨드 | 책임 |
|---|---|---|
| 1. raw 정리 | `/scv:promote` | 대화로 slug·title 확정 → 폴더 + PLAN + TESTS scaffold 생성 → `scv/readpath.json` update |
| 2. 구현·검증 | `/scv:work <slug>` | PLAN + TESTS 읽고 구현 → TESTS 실행 → 결과 보고 → Archive 여부 확인 |
| 3. Archive | `/scv:work` 또는 수동 | 테스트 통과 + 사용자 승인 시 `promote/<slug>/` → `archive/<slug>/` 로 폴더 이동 + `ARCHIVED_AT.md` 생성 |

---

## 8. Archive 규약

완료된 계획은 반드시 `scv/archive/` 로 이동합니다 (**토큰 효율** — `/scv:work` 가 활성 계획만 읽게).

```
scv/archive/
└── 20260420-sspark-user-auth/
    ├── PLAN.md
    ├── TESTS.md
    ├── REQUIREMENTS.md        # (있었던 자유 확장 파일들도 그대로)
    └── ARCHIVED_AT.md          # ⭐ archive 시 자동 생성
```

### ARCHIVED_AT.md (자동 생성)

```markdown
---
archived_at: 2026-04-25
archived_by: sspark
reason: tests passed
---

# Archive 기록

이 계획은 2026-04-25 에 archive 됐습니다.

## 완료 사유

- 모든 TESTS 시나리오 통과
```

`reason` 은 `/scv:work <slug> --archive --reason="..."` 인자로 넘길 수 있고, 생략하면 기본값 `tests passed` 가 들어갑니다. 본문 사유 블록도 `--reason` 값(생략 시 "모든 TESTS 시나리오 통과") 으로 채워집니다.

### Archive 이동 판정

| 상황 | 동작 |
|---|---|
| 테스트 통과 + 사용자 선언 ("archive 해") | 자동 mv |
| 테스트 통과 + 사용자 명시 사전 허용 ("되면 알아서 archive") | 자동 mv + 결과 보고 |
| 테스트 통과 + 사용자 지시 없음 | Claude 가 "archive 할까요?" 로 질의, 답변 대기 |
| 테스트 실패 | archive 금지, 수정 루프로 복귀 |

---

## 8b. Obsolete 규약 (회귀에서 영구 제외)

archived 된 계획의 TESTS.md 는 **절대 수정하지 않습니다**. 대신 "이 feature 는 더 이상 돌지 않아도 된다" 를 선언하는 3 경로:

| 경로 | 메커니즘 | 쓸 때 |
|---|---|---|
| **사전 선언** | 새 PLAN.md frontmatter 에 `supersedes: [<old-slug>, ...]` 또는 `supersedes_scenarios: ["<slug>:T<n>", ...]` | 작성 시점에 "내가 뭘 대체하는지" 아는 경우 |
| **자동 전파** | A 가 `/scv:work` 로 archive 되는 순간 Claude 가 `AskUserQuestion` (default Yes) 으로 "B 를 obsolete 로 마킹할까요?" 묻고 승인 시 B 의 PLAN.md frontmatter 만 수정 | supersedes 선언이 있으면 자동 안내되는 기본 경로 |
| **런타임 triage** | `/scv:regression` 실행 시 실패가 나면 `AskUserQuestion` 3-way: regression (코드 고침) / obsolete (지금 마킹) / flaky (재시도) | supersede 선언을 빠뜨렸거나, 환경 변화로 불가피하게 폐기되는 경우 |

### `obsolete` 란 — 용어 정의

- **의미**: "이 계획이 나타내는 feature 는 더 이상 운영되지 않는다. 회귀 스위트에서 영구 제외한다." 다른 계획(A)에 의해 대체되거나(`obsoleted_by: <A-slug>`), 후속 기능 없이 제거(`obsoleted_by: manual`) 됐음을 명시.
- **`done` 과의 차이**: `done` = "구현이 끝난 **현역** feature", `obsolete` = "한때 존재했지만 이제는 없는 feature".
- **`/scv:regression` 에 대한 효과**: `status: obsolete` slug 는 기본적으로 실행 대상에서 제외 (`--include-obsolete` 플래그 시 감사용으로 포함).
- **archive 에 파일이 남는 이유**: 역사 기록 + 감사 추적. obsolete 로 마킹해도 폴더·TESTS.md·ARCHIVED_AT.md 는 그대로 보존.

### 마킹 스펙 (3 경로 공통)

archived `scv/archive/<slug>/PLAN.md` frontmatter 에 **3 필드만** 추가:

```yaml
---
# 기존 필드들 (그대로 유지)
status: obsolete              # done → obsolete (덮어씀)
obsoleted_at: 2026-04-25
obsoleted_by: 20260425-sspark-user-auth-v2   # 자동 전파 경로면 대체자 slug, 런타임 triage 경로면 'manual'
---
```

TESTS.md · ARCHIVED_AT.md · 다른 파일은 **절대 수정 금지** (불변 archive 원칙). `/scv:regression` 이 런타임에 위 세 필드를 읽어 해당 slug 를 skip.

---

## 8c. Retirement-only plan 패턴 (후속 없는 순수 제거)

새 기능 없이 **기존 feature 를 떼어내기만 하는** 경우 — 새 커맨드 도입 없이 기존 promote/archive 루프로 표현:

```yaml
# scv/promote/20260424-sspark-retire-payment-v1/PLAN.md
---
title: Retire payment-v1 endpoints
slug: 20260424-sspark-retire-payment-v1
author: sspark
created_at: 2026-04-24
status: planned
kind: retirement                       # feature 가 아니라 retirement
tags: [retirement]
supersedes:
  - 20240101-kmlee-payment-v1
---

## Summary
payment-v1 (`/api/v1/pay/*`) 엔드포인트를 제거하고 410 Gone 을 반환.
클라이언트는 payment-v2 로 전환 완료.

## Steps
1. /api/v1/pay/* 라우트 핸들러 삭제
2. 410 Gone 응답 반환하는 catch-all 추가
3. 배포 후 access log 에서 잔여 호출 24h 모니터링
```

**TESTS.md** 는 "제거됐는지" 를 검증:

```markdown
## 실행 방법
```bash
curl -sf -o /dev/null -w "%{http_code}" "$API/api/v1/pay/charge" | grep -q 410
```

## 통과 판정
- 모든 /api/v1/pay/* 호출이 410 Gone 반환
```

`/scv:work` 가 이 retirement 계획을 통과 처리하면 Step 9c 에서 `payment-v1` 을 obsolete 로 마킹하도록 안내합니다. 새 커맨드 불요.

---

## 8d. Epic 브랜치 전략 (거대 요구를 여러 feature 로 쪼갰을 때)

사용자의 거대 요구를 한 promote 폴더로 받으면 **혼란스럽고 급격한 변화**가 됩니다. SCV 는 `/scv:promote` 단계에서 raw 자료를 분석해 "이건 여러 feature 로 나눌 만하다" 고 판단하면 분할을 제안합니다 (자동 분할 금지, 항상 사용자 확인).

**분할 갯수는 고정값이 아닙니다.** raw 자료의 실제 내용·토픽 다양성에 맞춰 Claude 가 적절한 갯수 (예: 2개, 4개, 8개 등) 와 후보 슬러그를 제안하고, 사용자가 최종 조정합니다. 아래 §8e 의 예시는 7 개로 쪼개진 케이스이지만 이건 **하나의 예시일 뿐 권장 표준이 아닙니다**.

분할된 feature 들은 같은 **`epic: <epic-slug>`** frontmatter 로 묶입니다.

### 작동 흐름

```
거대 요구 (raw 투입)
   │
   ▼  /scv:promote 가 분할 제안 → 사용자 승인
여러 promote 폴더 생성 (개수는 raw 의 내용에 맞춰), 모두 같은 epic
   │
   ▼  /scv:work <slug> 각각
feature 1 → archive → PR (base = epic/<epic-slug>)
feature 2 → archive → PR (base = epic/<epic-slug>)
...
feature N → archive → PR (base = epic/<epic-slug>)
   │
   ▼  (epic 의 모든 feature archive 시 SCV 가 자동 안내)
"epic <slug> feature 전부 완료. 통합 refactor PLAN 만들까요?"
   │
   ▼  refactor PLAN scaffold (kind: refactor) → /scv:work
   │
   ▼  archive → PR (base = epic/<epic-slug>)
   │
   ▼  사용자가 epic/<epic-slug> → main merge
```

### 핵심 규약

- **PR 의 base 브랜치는 `main` 이 아니라 `epic/<epic-slug>`**. epic 의 모든 PR (개수 무관) 이 한 통합 브랜치로 모임. main/stg/dev 직행 금지 — 단위 브랜치에서는 좋았지만 합치니 별로인 경우를 막기 위함.
- `epic/<epic-slug>` 브랜치는 첫 feature 의 PR 생성 시 SCV 가 자동 생성 권장 (`gh api` 또는 `git push origin main:epic/<slug>`). 이후 PR 들은 이 브랜치를 base 로.
- Epic 의 **마지막은 항상 refactor PLAN** (`kind: refactor`). 단위 기능 통합 후 코드 정리·중복 제거·이름 통일 단계. 이게 archive 돼야 epic 완료로 간주.
- Refactor PLAN 의 TESTS 는 보통 "기존 회귀가 여전히 green" + "통합 후 새 시나리오 (있으면)" 으로 구성.

### `/scv:status` 의 epic 진척도

```
[epics]
  epic 20260424-payment-overhaul: 4/7 archived, 2 in promote, refactor pending
  epic 20260415-search-revamp:    7/7 archived + refactor done → ready to merge
```

### 사용자가 직접 epic 으로 묶는 경우

`/scv:promote` 가 분할 제안을 안 했어도 사용자가 명시적으로 "이 promote 들은 같은 epic" 이라고 하면 PLAN.md frontmatter 에 `epic: <slug>` 를 직접 추가. SCV 가 그 시점부터 epic 으로 인식.

---

## 8e. Refactor PLAN 패턴

epic 의 모든 feature 가 archive 된 뒤 마지막에 **반드시** refactor PLAN 을 만듭니다 (epic 종료 조건).

```yaml
# scv/promote/20260430-sspark-payment-overhaul-refactor/PLAN.md
---
title: Payment overhaul — integration refactor
slug: 20260430-sspark-payment-overhaul-refactor
author: sspark
created_at: 2026-04-30
status: planned
kind: refactor                          # 핵심 — feature 가 아님
epic: 20260424-payment-overhaul         # 같은 epic 의 마지막 항목
tags: [refactor, integration]
---

## Summary

epic `payment-overhaul` 의 모든 feature (이 예시에선 auth-v2, charge-flow,
refund-flow, webhook-relay, audit-log, settlement-batch, partner-callback —
N 개. 실제 epic 마다 갯수 다름) 통합 후의 정리 단계. 단위 PR 시점엔 OK 였지만
합치고 보니 다음 항목들이 보임.

## Steps

1. feature 간 중복 helper 통합 (`utils/payment.ts`)
2. 명명 일관성 (`charge_id` vs `paymentId` 통일)
3. 공통 에러 코드 enum 추출
4. 통합 시점 발견된 race condition 1건 수정
5. 통합 회귀 테스트 (`/scv:regression --include-promote`)

## Related Documents

<!-- epic 폴더 7개의 PLAN.md 들 모두 참조 가능 -->
```

**TESTS.md** 는 보통 "기존 회귀 + 통합 시나리오 1~2개" 로 단순:

```markdown
## 실행 방법
\`\`\`bash
bash $CLAUDE_PLUGIN_ROOT/scripts/regression.sh --tag payment
npm run test:integration -- payment
\`\`\`
```

이 refactor 가 archive 돼야 SCV 가 "epic 완료" 로 간주합니다. archive 후 사용자가 `epic/<slug>` 브랜치를 main 에 merge.

---

## 9. frontmatter `status` 전이

```
planned → in_progress → testing → done → obsolete
              ↑                      │       ↑
              └──────────────────────┘       │  (새 계획의 supersedes 또는 수동 triage)
           (테스트 실패 시 되돌림)
```

- `/scv:work` 시작 시 `planned` → `in_progress` 로 갱신
- 구현 완료 직전 `testing` 으로 갱신
- 모든 TESTS 통과 + archive 이동 시 `done` (단, archive 후엔 PLAN.md 가 archive 쪽에 있음)
- `done → obsolete` 전이는 §8b 의 3 경로 (자동 전파 / 사전 선언 + 자동 / 런타임 triage). `in_progress`/`testing` 상태에선 obsolete 로 전이하지 않음 (미완성인 계획은 archive 자체가 없음)

---

## 10. 관련 모듈

<!-- MODULES:AUTO START applies_to=promote -->
<!-- MODULES:AUTO END -->
