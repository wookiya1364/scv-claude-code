---
description: "Implement a scv/promote/<slug>/ plan. Reads PLAN.md + TESTS.md, proposes/loads Related Documents as needed, runs the tests, and optionally archives on success."
argument-hint: "[<slug>]"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/work.sh:*)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/readpath.sh:*)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/pr-helper.sh:*)"
  - "Bash"
  - "Skill(graphify)"
  - "AskUserQuestion"
  - "Read"
  - "Glob"
  - "Grep"
  - "Write"
  - "Edit"
---

# /scv:work

You — Claude — drive a promote plan to completion: **read PLAN.md + TESTS.md → implement → run tests → archive on success**. Full protocol in `scv/PROMOTE.md`.

**Non-negotiable rules:**
- Never delete or move files outside the scope of this plan.
- Never archive without either (a) tests passing AND user approval in this conversation, or (b) the user's earlier declarative pre-approval ("tests 통과하면 알아서 archive 해" 같은 형태).
- When implementing, respect the user's document-split guidance (see Step 3 below).
- Always run the tests — do not declare "done" based on reasoning alone.
- **Archived TESTS.md 본문은 절대 수정하지 않는다.** Obsolete 마킹은 오직 해당 archived 폴더의 PLAN.md frontmatter 3 필드 (`status: obsolete` · `obsoleted_at` · `obsoleted_by`) 로만.
- **supersede propagation 시 자동 마킹 금지** — 반드시 Step 9c 의 AskUserQuestion 경유, default 만 Yes 로 사전선택.

First, gather context:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/work.sh" $ARGUMENTS
```

Parse the header (`MODE:`, `TARGET_SLUG:`, `PLAN_FILE:`, `TESTS_FILE:`, `GRAPHIFY_SKILL:`, `GRAPH_STATUS:`) and the three content blocks (`=== active promote plans ===`, `=== related documents (from PLAN.md) ===`, `=== external refs (from PLAN.md frontmatter refs:) ===`).

## Protocol

### Step 0 — Archive short-circuit

If `MODE: archive`: the helper already moved the folder and wrote `ARCHIVED_AT.md`. Just report the `ARCHIVED:` line and stop. Do not continue with Steps 1+.

### Step 1 — Select target

- If `TARGET_SLUG: (none …)` → use `AskUserQuestion` to ask the user which plan from the list to work on. Re-invoke the helper with the chosen slug.
- If ambiguous (helper exit 2): show the matches, ask user to pick one via `AskUserQuestion`.

### Step 2 — Graph freshness check

Based on `GRAPHIFY_SKILL` + `GRAPH_STATUS`:

| GRAPHIFY_SKILL | GRAPH_STATUS | Action |
|---|---|---|
| `available` | `stale` | Ask user via `AskUserQuestion`: "docs graph is stale — refresh it first via `/scv:promote --graph-only`?" Default: **yes**. If yes, tell user the command (do NOT invoke `/scv:promote` yourself from here — they run it). If no, continue. |
| `available` | `missing` or `built` | Continue. |
| `missing` (skill) | any | Continue silently. |

### Step 3 — Load PLAN.md (required)

`Read` the `PLAN_FILE` path emitted by the helper. Summarize `Summary`, `Goals / Non-Goals`, `Steps` to the user in 3–5 bullets so they can confirm scope.

Also surface any **external refs** from the helper's `=== external refs ===` block (grouped by `type`, e.g. `[jira] 2`, `[pr] 1`). One line per type is enough — the user can follow links without Claude reading them.

**Document split judgment** (applied from now on, through implementation):

| Signal | Claude's action |
|---|---|
| User explicit: "분리해" / "split into ARCH.md" / `REQUIREMENTS.md 로 빼줘" | **Always split** — write the new file and trim PLAN.md accordingly. Ask before the actual write. |
| User explicit: "분리 마" / "keep it in one file" / "no split" | **Do not propose split**. Continue in PLAN.md even if it grows. |
| Neither (default) | Claude judges. If `Approach Overview` > ~50 lines, `Steps` > ~15, or implementation reveals a dense sub-topic (ARCH / REQUIREMENTS / API / MIGRATION / tests) — **propose** split via `AskUserQuestion`. User accepts or declines. |

### Step 4 — Load Related Documents (as needed)

Look at the helper's `=== related documents (from PLAN.md) ===` list.

- If empty → skip.
- If listed: **don't read them all by default** (token guard).
- Read individual entries only when:
  1. The user explicitly requests (e.g., "ARCH.md 도 보고 구현해"), **or**
  2. Claude judges the content of the current step needs that context (e.g., Step says "per API.md contract" — then Read API.md).
- Any file marked `(MISSING)` by the helper → note it in summary; ask user if they want it created.

### Step 5 — Load TESTS.md (required)

`Read` the `TESTS_FILE`. Extract:
- 실행 방법 (the actual test command(s))
- 통과 판정 criteria

If TESTS.md is missing or the 실행 방법 block is empty / ambiguous → **stop and ask**. Do not guess a test command.

### Step 6 — Implement

Follow `PLAN.md` `Steps` in order. For each step:
1. Describe the change to the user briefly (one sentence).
2. Use `Read` / `Edit` / `Write` as needed.
3. After each significant change, surface any document-split proposal per Step 3.

Update `PLAN.md` frontmatter `status:` as you progress:
- `planned` → `in_progress` when you start implementation
- `in_progress` → `testing` when code is complete and you're about to run TESTS

### Step 7 — Run TESTS

Execute the command(s) from `TESTS.md` 실행 방법 via the `Bash` tool. Capture output. Evaluate against 통과 판정.

- All scenarios pass + 통과 판정 met → proceed to Step 8.
- Any scenario fails → loop back to Step 6 to fix. **Do not archive.** Set frontmatter `status:` back to `in_progress`.

### Step 8 — Report results to the user

Summarize:
- Implementation: what changed (files, key decisions).
- Test results: each scenario pass/fail + overall verdict.
- Plan's `status:` now `testing` (or back to `in_progress` if failures).

### Step 9a — Regression pre-flight (선택)

조건: Step 7 에서 모든 TESTS 통과 + pre-declared archive 모드가 아님.

`AskUserQuestion`: "Archive 전에 누적 회귀(`scv/archive/` 전체) 를 돌려볼까요? PLAN 에 `supersedes` 선언된 slug 는 자동 skip 됩니다."

Options:
- **Yes, run `/scv:regression` now** (default) — 아래 커맨드 즉시 실행
- **Skip — just archive** — 바로 Step 9b 로
- **Let me review first** — 사용자 대기 (커맨드 중지)

Yes 선택 시:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/regression.sh --quiet
```

결과 처리:
- `FAILED_SLUGS: 0` → "회귀 녹색" 한 줄 보고 후 Step 9b 로.
- `FAILED_SLUGS: >0` → 실패 개수·slug 목록을 사용자에게 먼저 보고하고 **Step 9b 진행 여부를 재질의**:
  - "회귀가 실패했습니다. archive 를 중단하고 `/scv:regression` 으로 triage 먼저 진행" (권장)
  - "실패 무시하고 archive" (위험 — 사용자가 명시 승인한 경우만)
  - "지금은 archive 보류"

**pre-declared 모드** ("tests 통과하면 알아서 archive 해") 에서도 pre-flight 는 자동 실행하되, `FAILED_SLUGS: 0` 이면 질문 없이 Step 9b 로 계속.

### Step 9b — Archive decision

Only if tests fully passed in Step 7 (and Step 9a passed or was skipped):

| User posture | Action |
|---|---|
| Pre-declared ("tests 통과하면 알아서 archive 해" or similar, spoken earlier in this conversation) | Auto-invoke: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/work.sh <slug> --archive --reason="tests passed"`. Report the ARCHIVED: line. |
| No pre-declaration | Use `AskUserQuestion`: "All tests passed. Archive `<slug>` now?" with options: **Archive now** / **Keep in promote** / **Let me review first**. Proceed per answer. |
| User says no (keep in promote) | Update PLAN.md frontmatter `status: done` but leave the folder in `scv/promote/`. |

After a successful archive, remind the user:
- `scv/archive/<slug>/ARCHIVED_AT.md` has the archive record.
- Future `/scv:status` will no longer flag this plan.

### Step 9c — supersede propagation (새 · adopts A's supersedes 선언)

조건: Step 9b 에서 archive 가 **실제로** 일어났고, 방금 archive 된 PLAN.md 의 `supersedes:` 배열이 비어있지 않을 때.

절차:
1. `Read` `scv/archive/<A-slug>/PLAN.md` 의 frontmatter. `supersedes:` 배열을 파싱.
2. 각 B-slug 에 대해 **순차 처리**:
   - `scv/archive/<B-slug>/PLAN.md` 존재 확인. 없으면 stderr 경고 후 skip.
   - 이미 `status: obsolete` 면 skip (중복 마킹 방지).
   - 그 외에는 **AskUserQuestion 하나** (슬러그별 1회, default Yes):

**AskUserQuestion 양식 (그대로 사용)**

```
Question: "방금 archive 한 '<A-slug>' 가 supersedes 로 '<B-slug>' 를 선언했습니다.
           '<B-slug>' 를 obsolete 로 마킹할까요?"

Options:
[1] "Yes — obsolete 로 마킹 (권장)"
    description:
    "'<B-slug>' 은 더 이상 운영되는 feature 가 아니며 방금 작업한 '<A-slug>' 에 의해
     대체됐음을 기록합니다.

     구체적으로 무엇이 변경되나요?
     - scv/archive/<B-slug>/PLAN.md frontmatter 에만 3 필드가 추가됩니다:
         status: done → obsolete
         obsoleted_at: <오늘 날짜>
         obsoleted_by: <A-slug>
     - TESTS.md · ARCHIVED_AT.md · 다른 파일은 절대 건드리지 않음 (불변 archive 원칙).

     이 마킹이 왜 필요한가요?
     - /scv:regression 이 앞으로 '<B-slug>' 의 TESTS 를 영구 skip 합니다 (회귀 스위트에서 제외).
     - 1년 뒤 archive 를 열람해도 '왜 B 가 더 이상 안 돌아가나?' 가 PLAN 본문에 남아
       git history 없이도 맥락 추적 가능.
     - status 가 'done' 인 채로 남으면 '완료된 현역 feature' 로 오해 받을 수 있어서
       상태를 명확히 하기 위함.

     언제 Yes 를 고르면 안 되나요?
     - supersedes 선언을 실수로 한 것이면 [2] Skip 을 고르고, 이후 <A-slug>.PLAN.md 의
       supersedes 배열에서 '<B-slug>' 를 지우세요."

[2] "Skip — runtime skip 만"
    description:
    "'<B-slug>' 의 파일을 전혀 건드리지 않습니다. /scv:regression 은 여전히
     <A-slug>.supersedes 를 읽어 '<B-slug>' 를 skip 하지만, '<B-slug>'.status 는 'done'
     으로 남아서 archive 목록에서 '현역 feature' 처럼 보입니다. supersedes 선언을
     실수로 했거나, 나중에 다시 판단하고 싶을 때 고르세요."

[3] "Let me review archive/<B-slug>/ first"
    description:
    "이 전파 결정을 보류합니다. /scv:work 는 여기서 멈추지 않고 다음 supersede 대상으로
     계속 진행합니다. 이 slug 에 대한 마킹은 나중에 수동으로 하거나 /scv:regression
     triage 로 재진입하면 됩니다."

Default: [1] Yes (사전 선택)
```

답변 처리:
- **[1] Yes**: `Read` → `Edit` `scv/archive/<B-slug>/PLAN.md` frontmatter:
  - `status: done` → `status: obsolete`
  - 없으면 `obsoleted_at: <TODAY>` 추가
  - 없으면 `obsoleted_by: <A-slug>` 추가
  - 그 외 필드는 손대지 않음. TESTS.md · ARCHIVED_AT.md · 다른 파일 절대 touch 금지.
- **[2] Skip**: 아무 것도 수정하지 않음. 다음 slug 로 진행.
- **[3] Review**: 이 slug 는 보류. 다음 slug 로 진행.

모든 supersede 대상 처리 후 사용자에게 요약:
```
Propagated obsolete marking:
  ✓ <B-slug>    (marked obsolete, obsoleted_by: <A-slug>)
  — <C-slug>    (user chose Skip)
  ? <D-slug>    (user chose Review — not marked)
```

### Step 9d — PR 자동 생성 (선택, v0.2.0)

조건: Step 9b 에서 archive 가 실제로 일어났음.

**AskUserQuestion** (default Yes):

```
Question: "방금 archive 한 '<slug>' 를 PR 로 올릴까요?"
options:
[1] "Yes — PR 자동 생성 (권장)"
    description:
    "다음 단계가 자동으로 진행됩니다:
    - PLAN.md / TESTS.md / ARCHIVED_AT.md 의 핵심 섹션을 PR body 로 조립
    - test-results/ 의 스크린샷 (PNG/JPG) 을 .scv-pr-artifacts/<slug>/ 로 이동
      (test-results/ 폴더에서 빠짐 — 디스크 정리)
    - PR body 에 markdown 이미지로 임베드 (GitHub blob URL)
    - epic 이 있으면 base 브랜치 = epic/<epic-slug> (없으면 main).
      epic 브랜치가 origin 에 없으면 origin/main 에서 자동 생성.
    - 현재 feature 브랜치를 push + gh pr create 호출
    - PR URL 출력

    전제:
    - 현재 git 브랜치가 main 이 아닌 feature 브랜치
    - gh CLI 인증됨 (gh auth status)
    - test-results/ 의 스크린샷은 사용자가 미리 준비 (Playwright/CDP 등)

    비디오 첨부는 v0.3 으로 미뤄졌습니다 — 지금은 스크린샷만."

[2] "Skip — PR 은 따로 만들겠다"
    description:
    "SCV 가 PR 을 만들지 않습니다. 사용자가 나중에 직접 git/gh 로 만들거나,
    /scv:work 를 다시 호출해 이 단계만 재진입할 수 있습니다."
```

**[1] Yes 선택 시**:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pr-helper.sh <slug>
```

위 호출이 archive/<slug>/PLAN.md 의 `epic:` / `kind:` 를 읽어 base 브랜치를 결정하고 commit + push + gh pr create 까지 수행합니다. 출력 마지막 줄에 `PR created: <URL>` 이 나오면 사용자에게 그 URL 을 보고하세요.

실패 case:
- 현재 브랜치가 base 브랜치와 같음 (e.g., main 에서 호출) → 사용자에게 "feature 브랜치로 전환하세요" 안내. 이때 SCV 가 자동으로 브랜치 전환은 하지 않음 (사용자의 작업 컨텍스트 보호).
- gh CLI 미인증 → 사용자에게 `gh auth login` 안내.
- 변경사항 없음 (이미 commit·push 완료된 상태) → 그대로 gh pr create 만 수행.

**[2] Skip 선택 시**: 그대로 종료. epic refactor 안내 (Step 9e) 는 계속 진행.

### Step 9e — Epic 완료 시 refactor 안내 (선택)

방금 archive 한 PLAN 이 `epic:` 을 가지고 있고 `kind: feature` 일 때만 수행. 이 epic 의 모든 feature 가 archive 됐는지 검사:

```bash
# Glob 으로 scv/promote/*/PLAN.md 와 scv/archive/*/PLAN.md 의 epic 일치 + kind=feature 카운트
remaining_features_in_promote=$(grep -l "^epic: <epic-slug>$" scv/promote/*/PLAN.md 2>/dev/null | xargs -I{} grep -L "^kind: refactor$" {} 2>/dev/null | wc -l)
existing_refactor=$(grep -l "^epic: <epic-slug>$" scv/{archive,promote}/*/PLAN.md 2>/dev/null | xargs grep -l "^kind: refactor$" 2>/dev/null | wc -l)
```

조건이 모두 충족되면:
- `remaining_features_in_promote == 0` (epic 의 모든 feature 가 archive 됨)
- `existing_refactor == 0` (refactor PLAN 이 아직 없음)

→ 사용자에게 한 줄 알림 + AskUserQuestion:

```
"epic <epic-slug> 의 모든 feature 가 archive 됐습니다.
 PROMOTE.md §8e 에 따라 통합 refactor PLAN 을 만들 차례입니다.

 Question: "지금 refactor PLAN scaffold 를 만들까요?"
 options:
 [1] "Yes — refactor PLAN 만들기 (권장)"
     description:
     "scv/promote/<TODAY>-<author>-<epic-slug>-refactor/ 폴더에 PLAN.md +
      TESTS.md scaffold 생성. PLAN.md 에는 다음 frontmatter 가 자동 세팅:
        kind: refactor
        epic: <epic-slug>
        status: planned
      Summary 섹션엔 epic 의 7개 feature 슬러그를 자동 나열.
      이후 사용자와 대화로 통합 시점 발견된 정리 항목 채움."

 [2] "Later — 다음 기회에"
     description:
     "지금은 만들지 않습니다. 나중에 /scv:promote 로 만들거나 직접 폴더
      만들면 됩니다. epic 은 'refactor pending' 상태로 /scv:status 에 표시."
```

**[1] Yes 선택 시**: Claude 가 직접 폴더 + PLAN.md + TESTS.md scaffold 를 `Write` 도구로 생성. epic 의 archived feature 슬러그들을 자동으로 PLAN.md Summary 섹션에 포함.

**[2] Later**: 그대로 종료.

## Flag semantics

- `<slug>` — required for actual work; optional when you just want to list plans. Partial match supported (helper fuzzy-resolves suffixes).
- `--archive` — Skip implementation; move `promote/<slug>/` → `archive/<slug>/` and write `ARCHIVED_AT.md`. Useful for manually archiving plans whose tests passed outside `/scv:work`.
- `--reason="..."` — Used only with `--archive`; goes into `ARCHIVED_AT.md` body.

## Never

- Archive without tests passing (or without explicit user override).
- Read Related Documents beyond what the step needs.
- Skip the test execution and declare done.
- Silently split or merge documents — always confirm with the user.
