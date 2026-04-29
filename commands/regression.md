---
description: "Run accumulated regression across scv/archive/**/TESTS.md (and optionally promote/) with supersede/obsolete skip graph. On failure, triage each slug via AskUserQuestion (regression / obsolete / flaky)."
argument-hint: "[<slug-prefix>]"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/regression.sh:*)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/report.sh:*)"
  - "Bash"
  - "AskUserQuestion"
  - "Read"
  - "Edit"
---

# /scv:regression

You — Claude — drive the accumulated regression: **run every archived TESTS that hasn't been superseded or marked obsolete, then triage any failures with the user**.

## Language preference

Resolve the user's preferred language with this priority, then use it for ALL user-facing output (AskUserQuestion text, triage prompts, summaries):

1. `~/.claude/settings.json` (or project `.claude/settings.json` / `.claude/settings.local.json`) — `language` key (Claude Code official).
2. Project `.env` — `SCV_LANG` (set by `/scv:help`'s first-time setup).
3. Auto-detect from the user's most recent message language.
4. Default to English.

Technical identifiers stay as-is: file paths, slash command names, frontmatter keys (`status`, `obsoleted_at`, `obsoleted_by`, `supersedes`), env var names, SCV terms (`promote`, `archive`, `obsolete`, `flaky`). If both `settings.json language` and `.env SCV_LANG` are unset, suggest `/scv:help` once to lock the preference (don't block — fall back to auto-detect / English for now).

**Non-negotiable rules:**
- **Archived TESTS.md 본문은 절대 수정하지 않는다.** Obsolete 마킹은 오직 해당 archived 폴더의 PLAN.md frontmatter (`status`, `obsoleted_at`, `obsoleted_by`) 3 필드로만.
- **supersedes 선언된 slug 를 강제 실행하지 않는다** — 이미 사전에 의도된 skip 이다.
- **`--ci` 모드에서는 AskUserQuestion 호출 금지.** exit code 로만 판정.
- **여러 실패를 한 번에 묶어 triage 하지 않는다.** 각 slug 는 독립적으로 질의 (triage 결정이 slug 마다 다르기 때문).
- supersedes 선언 없는 실패를 사용자 승인 없이 obsolete 로 자동 분류 금지.

## Step 0 — 실행

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/regression.sh" $ARGUMENTS
```

헤더 키를 파싱: `MODE:`, `TODAY:`, `SCOPE:`, `TAG_FILTER:`, `TOTAL_SLUGS:`, `SKIPPED_SUPERSEDED:`, `SKIPPED_OBSOLETE:`, `SKIPPED_SCENARIOS:`, `EXECUTED_SLUGS:`, `PASSED_SLUGS:`, `FAILED_SLUGS:`. 블록: `=== skip list ===`, `=== execution ===`, `=== summary ===`. 실패가 있으면 `failed_slugs:` 라인 이 있음.

## Step 1 — 전부 pass 경로

`FAILED_SLUGS: 0` 이면:

1. 사용자에게 **2~4줄 요약** (TOTAL_SLUGS / EXECUTED_SLUGS / PASSED_SLUGS / SKIPPED_*). skip 내역 있으면 `[superseded]` · `[obsolete]` · `[scenario-skipped]` 개수만 한 줄.
2. `AskUserQuestion` (선택): "이 회귀 결과를 팀에 알릴까요?"
   - Yes → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/report.sh "accumulated-regression" passed --event regression-summary --summary "<n> slugs passed, <m> skipped (superseded/obsolete)"`
   - No → 종료

## Step 2 — 실패 있음 → slug 별 3-way triage

각 `failed_slugs` 의 slug 에 대해 **한 개씩 독립** AskUserQuestion. 아래 양식 그대로:

```
Question: "'<slug>' 의 TESTS 가 실패했습니다. 어떻게 처리할까요?"

Options:
[1] "regression — 진짜 회귀. 현재 코드를 고치겠다"
    description:
    "archived TESTS 는 이전에 통과했었는데 지금 깨졌다는 의미입니다. 최근 변경 중 하나가
     '<slug>' 의 feature 를 의도치 않게 건드렸을 가능성이 높습니다.

     Claude 의 동작:
     - 이 slug 의 파일은 전혀 수정하지 않습니다.
     - 원하면 실패 output 을 분석해 '이 라인이 문제인 듯' 수준의 제안만 제공.
     - 실제 코드 수정은 사용자가 수행 (/scv:work 나 직접 편집).
     - 고친 뒤 /scv:regression 재실행해 green 확인."

[2] "obsolete — 이 TESTS 는 지금 의도적으로 깨진 것이 맞다"
    description:
    "'<slug>' 은 더 이상 운영되는 feature 가 아니며, 회귀 스위트에서 영구 제외해야
     합니다. 이미 신규 계획을 작성할 때 supersedes 선언을 빠뜨렸거나, 환경 변화로
     불가피하게 폐기되는 경우 사용합니다.

     구체적으로 무엇이 변경되나요?
     - scv/archive/<slug>/PLAN.md frontmatter 에만 3 필드가 추가됩니다:
         status: done → obsolete
         obsoleted_at: <오늘 날짜>
         obsoleted_by: manual     (런타임 triage 경로니까 'manual' 고정)
     - TESTS.md · ARCHIVED_AT.md · 다른 파일은 절대 건드리지 않음 (불변 archive 원칙).

     이 마킹이 왜 필요한가요?
     - 이후 /scv:regression 이 '<slug>' 의 TESTS 를 영구 skip 하게 됩니다.
     - 1년 뒤 누가 archive 를 열람해도 '왜 이 TESTS 가 안 돌아가나?' 가 PLAN 본문에
       남아 있어 git history 없이도 맥락 추적 가능.
     - status 가 'done' 인 채로 남으면 '완료된 현역 feature' 로 오해 받을 수 있음."

[3] "flaky — 환경 문제. 재시도하겠다"
    description:
    "테스트 자체가 불안정하거나 외부 의존성 (네트워크, 시간대, 공용 자원) 때문에
     실패했을 가능성. Claude 가 이 slug 만 최대 2회 재실행:
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/regression.sh --only <slug>
     - 2회 안에 pass → 'flaky resolved on retry N' 로 기록 후 진행
     - 여전히 실패 → 이 3-way 다이얼로그를 다시 띄움."
```

답변 처리:

- **[1] regression**: 어떤 파일도 수정하지 않음. 사용자에게 "failed output tail 을 함께 분석해 드릴까요?" 한 번 제안 (원하면 `Read`/`Grep` 으로 소스 탐색, 수정은 제안만). triage log 에 `[regression] <slug>` 기록.
- **[2] obsolete**: 아래 파일 수정 절차 수행
  1. `Read` `scv/archive/<slug>/PLAN.md`
  2. `Edit` 로 frontmatter 3 필드 조정:
     - `status: done` → `status: obsolete`
     - `obsoleted_at: <TODAY>` 추가 (없으면)
     - `obsoleted_by: manual` 추가 (없으면)
  3. TESTS.md · ARCHIVED_AT.md 는 절대 touch 하지 않음
  4. 사용자에게 한 줄 보고: "Marked `<slug>` as obsolete (PLAN.md frontmatter only)."
  5. triage log 에 `[obsolete] <slug>` 기록
- **[3] flaky**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/regression.sh --only <slug> --quiet` 실행 (최대 2회). pass 면 `[flaky→pass on retry N] <slug>` 기록. 2회 다 fail 이면 3-way 다이얼로그 재호출.

## Step 3 — 최종 요약

triage log 를 누적해 `=== triage log ===` 블록으로 사용자에게 출력:

```
=== triage log ===
[regression] 20260301-sspark-payment-bug
[obsolete]   20260115-kmlee-legacy-login
[flaky→pass on retry 1] 20260201-tester-network-test
```

`AskUserQuestion` (선택): "이 회귀 결과를 팀에 알릴까요?"
- Yes + 여전히 regression 이 남아 있음 → `--event regression-failure`
- Yes + 전부 obsolete/flaky 로 처리됨 → `--event regression-summary`
- No → 종료

## Flag semantics

- `<slug-prefix>` — 부분 매칭으로 대상 축소 (archive + promote). 생략하면 전부.
- `--tag <x>` — PLAN.md 의 `tags:` 배열에 `<x>` 가 포함된 slug 만.
- `--include-promote` — 기본은 archive 만. 이 플래그 시 `scv/promote/**/TESTS.md` 도 실행 대상에 추가 (archive 되기 전 작업 중인 계획까지 회귀에 포함).
- `--include-obsolete` — `status: obsolete` 인 slug 도 강제 실행 (감사·재검증 목적).
- `--only <slug>` / `--skip <slug>` — 반복 가능. 정확 매칭.
- `--ci` — AskUserQuestion 없음, 실패 시 exit 2, `test-results/regression-summary.json` 자동 생성.
- `--quiet` — 성공 scenario 의 줄림 출력. `/scv:work` 의 Step 9a pre-flight 에서 사용.
- `--json <path>` — JSON 요약을 명시 경로에 기록 (`--ci` 가 아닐 때도).
- `--timeout <sec>` — scenario 당 타임아웃. 기본 300.

## Never

- archived TESTS.md · ARCHIVED_AT.md 본문 수정.
- supersedes 선언된 slug 를 runner 바깥에서 별도로 실행.
- `--ci` 모드에서 AskUserQuestion 발동.
- 여러 실패를 한 번의 AskUserQuestion 에 묶어 처리.
- supersedes 선언 없는 실패를 사용자 답변 없이 obsolete 로 자동 마킹.
