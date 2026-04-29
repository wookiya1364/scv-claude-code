#!/usr/bin/env bash
# Dry-run regression for the SCV template.
# Hydrates a fresh project, exercises report (slack+discord), help, promote,
# and sync --dry-run. Asserts properties and exits non-zero on any failure.
#
# Usage: tests/run-dry.sh
set -uo pipefail

STANDARD_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HYDRATE="$STANDARD_ROOT/scripts/hydrate.sh"
SYNC="$STANDARD_ROOT/scripts/sync.sh"
CHECK_FRONT="$STANDARD_ROOT/scripts/check-frontmatter.sh"
REPORT="$STANDARD_ROOT/scripts/report.sh"
HELP_SH="$STANDARD_ROOT/scripts/help.sh"
HELP_CMD="$STANDARD_ROOT/commands/help.md"
READPATH_SH="$STANDARD_ROOT/scripts/readpath.sh"
STATUS_SH="$STANDARD_ROOT/scripts/status.sh"
STATUS_CMD="$STANDARD_ROOT/commands/status.md"
PROMOTE_HELPER="$STANDARD_ROOT/scripts/promote-helper.sh"
PROMOTE_CMD="$STANDARD_ROOT/commands/promote.md"
WORK_SH="$STANDARD_ROOT/scripts/work.sh"
WORK_CMD="$STANDARD_ROOT/commands/work.md"
REGRESSION_SH="$STANDARD_ROOT/scripts/regression.sh"
REGRESSION_CMD="$STANDARD_ROOT/commands/regression.md"
PR_HELPER="$STANDARD_ROOT/scripts/pr-helper.sh"
STATUS_SH="$STANDARD_ROOT/scripts/status.sh"
ATTACHMENTS_LIB="$STANDARD_ROOT/scripts/lib/attachments.sh"

# Counter files (so subshell pass/fail calls still aggregate correctly).
PASS_FILE=$(mktemp)
FAIL_FILE=$(mktemp)
FAILED_NAMES_FILE=$(mktemp)

pass() {
  printf '1\n' >> "$PASS_FILE"
  printf '  \033[32m✓\033[0m %s\n' "$1"
}
fail() {
  printf '1\n' >> "$FAIL_FILE"
  printf '%s\n' "$1" >> "$FAILED_NAMES_FILE"
  printf '  \033[31m✗\033[0m %s\n' "$1"
}

assert_file()        { [[ -f "$1" ]] && pass "file exists: ${1#"$APP/"}" || fail "file missing: ${1#"$APP/"}"; }
assert_contains()    { grep -qF -- "$2" "$1" && pass "contains: ${1#"$APP/"} ← '${2:0:60}'" || fail "does NOT contain: ${1#"$APP/"} ← '${2:0:60}'"; }
assert_out_contains(){ printf '%s' "$2" | grep -qF -- "$1" && pass "$3" || fail "$3 — got: $(printf '%s' "$2" | head -3)"; }
assert_ok_exit()     { [[ "$1" -eq 0 ]] && pass "$2" || fail "$2 (exit=$1)"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$PASS_FILE" "$FAIL_FILE" "$FAILED_NAMES_FILE"' EXIT
APP="$TMP/app"

echo "=== [1] Hydration ==="
"$HYDRATE" init "$APP" >/dev/null 2>&1

# Root files — SCV only creates scv/ + .env.example.scv + .gitignore merge
for f in .env.example.scv .gitignore; do
  assert_file "$APP/$f"
done
[[ ! -f "$APP/CLAUDE.md" ]] && pass "root CLAUDE.md NOT created (pure separation)" || fail "root CLAUDE.md was created — should be user-owned"
[[ ! -f "$APP/.env.example" ]] && pass "root .env.example NOT created (was never in template)" || fail "root .env.example leaked — should be .env.example.scv only"

# Non-destructive over existing user .env.example
EXIST_APP="$TMP/existing-app"
mkdir -p "$EXIST_APP"
cat > "$EXIST_APP/.env.example" <<'USEREX'
DATABASE_URL=postgresql://...
API_KEY=keep-this
USEREX
"$HYDRATE" init "$EXIST_APP" >/dev/null 2>&1
grep -qF "DATABASE_URL=postgresql" "$EXIST_APP/.env.example" \
  && pass "hydrate: existing user .env.example preserved (non-destructive)" \
  || fail "hydrate overwrote user's .env.example"
assert_file "$EXIST_APP/.env.example.scv"
grep -qF "NOTIFIER_PROVIDER" "$EXIST_APP/.env.example.scv" \
  && pass "hydrate: SCV env template created at .env.example.scv" \
  || fail "hydrate: .env.example.scv missing SCV vars"
# SCV env file must NOT reference the legacy /standard-report command name
grep -qF "/standard-report" "$EXIST_APP/.env.example.scv" \
  && fail ".env.example.scv still references legacy /standard-report" \
  || pass ".env.example.scv no longer references /standard-report (uses /scv:report)"

# scv/ hierarchy (now includes CLAUDE.md)
for f in CLAUDE.md INTAKE.md PROMOTE.md RALPH_PROMPT.md ARCHITECTURE.md DESIGN.md DOMAIN.md AGENTS.md TESTING.md REPORTING.md; do
  assert_file "$APP/scv/$f"
done
assert_file "$APP/scv/raw/README.md"
[[ -d "$APP/scv/archive" ]] && pass "scv/archive directory hydrated" || fail "scv/archive directory missing"
[[ -d "$APP/scv/promote" ]] && pass "scv/promote directory hydrated" || fail "scv/promote directory missing"

VERSION_NOW=$(tr -d '[:space:]' < "$STANDARD_ROOT/VERSION")
assert_contains "$APP/scv/CLAUDE.md" "<!-- STANDARD:VERSION -->${VERSION_NOW}<!-- /STANDARD:VERSION -->"
assert_contains "$APP/scv/CLAUDE.md" "<!-- STANDARD:SYNCED_AT -->$(date +%Y-%m-%d)<!-- /STANDARD:SYNCED_AT -->"
[[ ! -f "$APP/.gitignore.fragment" ]] && pass ".gitignore.fragment merged into .gitignore" || fail ".gitignore.fragment leaked"

echo
echo "=== [1b] Zero-base 템플릿 순수성 ==="
# 각 표준 문서에 How to elicit + Completion criteria 섹션 존재
for f in DOMAIN ARCHITECTURE DESIGN AGENTS TESTING REPORTING; do
  assert_contains "$APP/scv/$f.md" "How to elicit"
  assert_contains "$APP/scv/$f.md" "Completion criteria"
done
# INTAKE.md 의 프로세스 섹션
assert_contains "$APP/scv/INTAKE.md" "불변 원칙"
assert_contains "$APP/scv/INTAKE.md" "단계 0"
# 구체 예시가 핵심 표준 문서에서 제거됐는지
for term in Livekit Temporal "UC-001" Utterance dialog-llm; do
  hits=""
  for f in DOMAIN ARCHITECTURE DESIGN AGENTS TESTING REPORTING; do
    if grep -qF "$term" "$APP/scv/$f.md" 2>/dev/null; then
      hits+="scv/$f.md "
    fi
  done
  if [[ -z "$hits" ]]; then
    pass "example term absent from core docs: $term"
  else
    fail "example term '$term' still in: $hits"
  fi
done
# 상태: INTAKE/PROMOTE 는 active (process docs), 나머지는 default(adoption) 모드에서 N/A
intake_status=$(grep -E "^status:" "$APP/scv/INTAKE.md" | head -1 | awk '{print $2}')
[[ "$intake_status" == "active" ]] && pass "INTAKE status=active" || fail "INTAKE status should be active, got '$intake_status'"
promote_status=$(grep -E "^status:" "$APP/scv/PROMOTE.md" | head -1 | awk '{print $2}')
[[ "$promote_status" == "active" ]] && pass "PROMOTE status=active" || fail "PROMOTE status should be active, got '$promote_status'"
domain_status=$(grep -E "^status:" "$APP/scv/DOMAIN.md" | head -1 | awk '{print $2}')
[[ "$domain_status" == "N/A" ]] && pass "DOMAIN starts as N/A (adoption default)" || fail "DOMAIN should be N/A in adoption mode, got '$domain_status'"

echo
echo "=== [1c] Greenfield (--new) hydrate mode ==="
NEW_APP="$TMP/new-app"
"$HYDRATE" init "$NEW_APP" --new >/dev/null 2>&1
# In --new mode, standard docs stay as draft (INTAKE drives the flow)
for doc in DOMAIN ARCHITECTURE DESIGN AGENTS TESTING REPORTING RALPH_PROMPT; do
  st=$(grep -E "^status:" "$NEW_APP/scv/$doc.md" | head -1 | awk '{print $2}')
  [[ "$st" == "draft" ]] && pass "--new: $doc status=draft" || fail "--new: $doc should be draft, got '$st'"
done
# INTAKE/PROMOTE stay active in both modes (process docs)
intake_st=$(grep -E "^status:" "$NEW_APP/scv/INTAKE.md" | head -1 | awk '{print $2}')
[[ "$intake_st" == "active" ]] && pass "--new: INTAKE still active" || fail "--new: INTAKE should be active"
# Frontmatter validator must accept both N/A and draft
"$CHECK_FRONT" --project-dir "$APP" >/dev/null 2>&1     && pass "check-frontmatter passes adoption mode (N/A)"   || fail "check-frontmatter rejects adoption mode"
"$CHECK_FRONT" --project-dir "$NEW_APP" >/dev/null 2>&1 && pass "check-frontmatter passes greenfield mode (draft)" || fail "check-frontmatter rejects greenfield mode"

echo
echo "=== [1d] /scv:help hydrate recommendation shows BOTH modes ==="
EMPTY_DIR2=$(mktemp -d)
(
  cd "$EMPTY_DIR2"
  OUT=$(bash "$HELP_SH" 2>&1)
  assert_out_contains "default · adoption" "$OUT" "help(un-hydrated): shows default/adoption option"
  assert_out_contains "--new"       "$OUT"  "help(un-hydrated): shows --new option"
  assert_out_contains "adoption mode" "$OUT" "help(un-hydrated): mentions adoption mode"
  assert_out_contains "INTAKE"      "$OUT"  "help(un-hydrated): mentions INTAKE for --new"
)
rm -rf "$EMPTY_DIR2"

echo
echo "=== [2] Frontmatter validity ==="
if "$CHECK_FRONT" --project-dir "$APP" >/dev/null 2>&1; then
  pass "all template frontmatter valid"
else
  fail "template frontmatter invalid"
fi

echo
echo "=== [5] report dry-run (Slack) ==="
cat > "$APP/.env" <<'ENV'
PROJECT_NAME=test-proj
NOTIFIER_PROVIDER=slack
SLACK_BOT_TOKEN=xoxb-fake
SLACK_CHANNEL_ID=C0DEFAULT
SLACK_CHANNEL_ID_PHASE_COMPLETE=C0PASS
SLACK_CHANNEL_ID_E2E_FAILURE=C0FAIL
NOTIFIER_DRY_RUN=1
ENV
mkdir -p "$APP/test-results/E2E-001" "$APP/test-results/logs"
printf 'PNG' > "$APP/test-results/E2E-001/ss.png"
printf 'WEBM' > "$APP/test-results/E2E-001/video.webm"
yes "log line" 2>/dev/null | head -c 25000 > "$APP/test-results/logs/run.log"

(
  cd "$APP"
  OUT=$(bash "$REPORT" "Phase 2" passed --summary "all green" --attempt 1 2>&1)
  rc=$?
  assert_ok_exit "$rc" "slack/passed: exit 0"
  assert_out_contains "OK DRY-RUN-TS-" "$OUT" "slack/passed: thread_ref prefix"
  assert_out_contains "C0PASS" "$OUT" "slack/passed: routed to phase-complete channel"
  assert_out_contains "files.getUploadURLExternal" "$OUT" "slack/passed: file upload logged"
  assert_out_contains "uploaded 2 artifact(s)" "$OUT" "slack/passed: 2 artifacts uploaded (screenshot+video)"

  OUT=$(bash "$REPORT" "Phase 2" failed --summary "first-byte 1.2s" --attempt 3 2>&1)
  rc=$?
  assert_ok_exit "$rc" "slack/failed: exit 0"
  assert_out_contains "C0FAIL" "$OUT" "slack/failed: routed to e2e-failure channel"
  assert_out_contains "uploaded 3 artifact(s)" "$OUT" "slack/failed: 3 artifacts uploaded (+log tail)"
)

echo
echo "=== [6] report dry-run (Discord switch) ==="
sed -i 's/^NOTIFIER_PROVIDER=.*/NOTIFIER_PROVIDER=discord/' "$APP/.env"
cat >> "$APP/.env" <<'ENV'
DISCORD_BOT_TOKEN=fake-discord
DISCORD_CHANNEL_ID=111111111111111111
DISCORD_CHANNEL_ID_PHASE_COMPLETE=222222222222222222
ENV

(
  cd "$APP"
  OUT=$(bash "$REPORT" "Phase 1" info --summary "mid" 2>&1)
  rc=$?
  assert_ok_exit "$rc" "discord/info: exit 0"
  assert_out_contains "OK DRY-RUN-MID-" "$OUT" "discord/info: message id prefix"
  assert_out_contains "discord:messages" "$OUT" "discord/info: messages endpoint logged"
)

echo
echo "=== [7] Error handling ==="
(
  cd "$APP"
  grep -v "^NOTIFIER_PROVIDER=" "$APP/.env" > "$APP/.env.tmp" && mv "$APP/.env.tmp" "$APP/.env"
  OUT=$(bash "$REPORT" "X" passed 2>&1)
  rc=$?
  [[ "$rc" -ne 0 ]] && pass "missing NOTIFIER_PROVIDER: non-zero exit" || fail "missing NOTIFIER_PROVIDER should have failed"
  assert_out_contains "NOTIFIER_PROVIDER not set" "$OUT" "missing NOTIFIER_PROVIDER: stderr message"

  OUT=$(bash "$REPORT" "X" bogus 2>&1)
  rc=$?
  [[ "$rc" -ne 0 ]] && pass "invalid status: non-zero exit" || fail "invalid status should have failed"
  assert_out_contains "Invalid status: bogus" "$OUT" "invalid status: stderr message"
)

echo
echo "=== [9a] /scv:help self-onboarding ==="
HELP_CMD="$STANDARD_ROOT/commands/help.md"
HELP_SH="$STANDARD_ROOT/scripts/help.sh"
assert_file "$HELP_CMD"
assert_file "$HELP_SH"
[[ -x "$HELP_SH" ]] && pass "help script executable" || fail "help script not executable"

EMPTY_DIR=$(mktemp -d)
(
  cd "$EMPTY_DIR"
  OUT=$(bash "$HELP_SH" 2>&1)
  assert_out_contains "hydrate not done" "$OUT" "help: detects un-hydrated dir"
  assert_out_contains "Recommended next action" "$OUT" "help: prints recommended next action"
  assert_out_contains "hydrate.sh" "$OUT" "help: suggests hydrate.sh"
)
rm -rf "$EMPTY_DIR"

(
  cd "$APP"
  OUT=$(bash "$HELP_SH" 2>&1)
  assert_out_contains "hydrate complete" "$OUT" "help: detects hydrated dir"
  assert_out_contains "N/A" "$OUT" "help: lists N/A documents (adoption default)"
  assert_out_contains "/scv:status" "$OUT" "help: includes status"
  assert_out_contains "/scv:promote" "$OUT" "help: includes promote"
  assert_out_contains "/scv:work" "$OUT" "help: includes work"
  assert_out_contains "/scv:report" "$OUT" "help: includes report"
  assert_out_contains "/scv:sync" "$OUT" "help: includes sync"
)

echo
echo "=== [9b] /scv:promote helper ==="
PROMOTE_HELPER="$STANDARD_ROOT/scripts/promote-helper.sh"
PROMOTE_CMD="$STANDARD_ROOT/commands/promote.md"
assert_file "$PROMOTE_CMD"
assert_file "$PROMOTE_HELPER"
[[ -x "$PROMOTE_HELPER" ]] && pass "helper is executable" || fail "helper not executable"

# Seed raw materials in the new location
mkdir -p "$APP/scv/raw/2026-04-17-workshop"
cat > "$APP/scv/raw/2026-04-17-workshop/notes.md" <<'RAW'
# 워크숍 메모
온보딩 플로우 논의. 사용자가 가입 후 첫 15분에 무엇을 해야 하는가.
RAW
printf 'fakeimage' > "$APP/scv/raw/2026-04-17-workshop/whiteboard-01.jpg"
printf 'fakepdf' > "$APP/scv/raw/customer-interview.pdf"

(
  cd "$APP"
  OUT=$(bash "$PROMOTE_HELPER" --dry-run 2>&1)
  rc=$?
  assert_ok_exit "$rc" "promote-helper --dry-run exits 0"
  assert_out_contains "MODE: dry-run" "$OUT"       "helper surfaces --dry-run flag"
  assert_out_contains "TODAY:" "$OUT"              "helper prints TODAY"
  assert_out_contains "AUTHOR:" "$OUT"             "helper prints AUTHOR"
  assert_out_contains "STANDARD_VERSION:" "$OUT"   "helper prints STANDARD_VERSION"
  assert_out_contains "GRAPHIFY_SKILL:" "$OUT"     "helper prints GRAPHIFY_SKILL"
  assert_out_contains "GRAPH_STATUS:" "$OUT"       "helper prints GRAPH_STATUS"
  assert_out_contains "scv/raw changes since last index" "$OUT" "helper prints raw diff section"
  assert_out_contains "existing archive folders" "$OUT" "helper prints archive section"
  assert_out_contains "notes.md" "$OUT"            "helper lists raw .md file"
  assert_out_contains "whiteboard-01.jpg" "$OUT"   "helper lists raw image file"
  assert_out_contains "customer-interview.pdf" "$OUT" "helper lists raw pdf file"

  # --graph-only short-circuits (no inventory section)
  OUT=$(bash "$PROMOTE_HELPER" --graph-only 2>&1)
  assert_out_contains "MODE: graph-only" "$OUT"    "helper surfaces --graph-only flag"
  assert_out_contains "GRAPH_STATUS:" "$OUT"       "helper still prints GRAPH_STATUS in graph-only"
  printf '%s' "$OUT" | grep -qF "scv/raw inventory" \
    && fail "helper --graph-only should skip inventory section" \
    || pass "helper --graph-only skips inventory"
)

echo
echo "=== [11] readpath.sh (scan / diff / update) ==="
READPATH_SH="$STANDARD_ROOT/scripts/readpath.sh"
assert_file "$READPATH_SH"
[[ -x "$READPATH_SH" ]] && pass "readpath executable" || fail "readpath not executable"

# Use a dedicated raw sandbox to avoid disturbing APP's existing files
RP_APP="$TMP/rp-app"
mkdir -p "$RP_APP/scv/raw/subdir"
echo "readme guide" > "$RP_APP/scv/raw/README.md"
echo "notes v1"     > "$RP_APP/scv/raw/notes.md"
echo "sub content"  > "$RP_APP/scv/raw/subdir/inside.md"

(
  cd "$RP_APP"
  # scan emits valid-looking JSON
  OUT=$(bash "$READPATH_SH" scan 2>&1)
  assert_out_contains '"version": 1' "$OUT"                                  "readpath scan: version field"
  assert_out_contains '"files":'     "$OUT"                                  "readpath scan: files field"
  assert_out_contains 'scv/raw/notes.md' "$OUT"                              "readpath scan: includes notes.md"
  assert_out_contains 'scv/raw/subdir/inside.md' "$OUT"                      "readpath scan: recurses into subdir"
  printf '%s' "$OUT" | grep -qF 'scv/raw/README.md' \
    && fail "readpath scan: README.md should be skipped" \
    || pass "readpath scan: README.md skipped"

  # update creates state file
  bash "$READPATH_SH" update >/dev/null
  [[ -f scv/readpath.json ]] && pass "readpath update: state file created" || fail "readpath update: state file missing"

  # diff after update → no changes, exit 0
  bash "$READPATH_SH" diff >/dev/null
  rc=$?
  [[ "$rc" -eq 0 ]] && pass "readpath diff: no changes after update (exit 0)" || fail "readpath diff: expected exit 0, got $rc"

  # Add a file → A line + exit 2
  echo "newcontent" > scv/raw/new.pdf
  OUT=$(bash "$READPATH_SH" diff 2>&1)
  rc=$?
  [[ "$rc" -eq 2 ]] && pass "readpath diff: exit 2 on changes" || fail "readpath diff: expected exit 2, got $rc"
  assert_out_contains $'A\tscv/raw/new.pdf' "$OUT" "readpath diff: reports Added"

  # Modify existing file → M line
  echo "notes v2 extended" > scv/raw/notes.md
  OUT=$(bash "$READPATH_SH" diff 2>&1)
  assert_out_contains $'M\tscv/raw/notes.md' "$OUT" "readpath diff: reports Modified"

  # Remove a file → R line
  rm scv/raw/subdir/inside.md
  OUT=$(bash "$READPATH_SH" diff 2>&1)
  assert_out_contains $'R\tscv/raw/subdir/inside.md' "$OUT" "readpath diff: reports Removed"

  # status-counts
  OUT=$(bash "$READPATH_SH" status-counts 2>&1)
  assert_out_contains 'added=1 modified=1 removed=1 total=3' "$OUT" "readpath status-counts: correct tally"
)

echo
echo "=== [11b] /scv:status command ==="
STATUS_SH="$STANDARD_ROOT/scripts/status.sh"
STATUS_CMD="$STANDARD_ROOT/commands/status.md"
assert_file "$STATUS_SH"
assert_file "$STATUS_CMD"
[[ -x "$STATUS_SH" ]] && pass "status script executable" || fail "status script not executable"

(
  cd "$RP_APP"
  # Running /scv:status without --ack (state still has added/modified/removed)
  OUT=$(bash "$STATUS_SH" 2>&1)
  assert_out_contains "SCV Status" "$OUT"                   "status: header present"
  assert_out_contains "added   :" "$OUT"                    "status: added bucket"
  assert_out_contains "modified:" "$OUT"                    "status: modified bucket"
  assert_out_contains "removed :" "$OUT"                    "status: removed bucket"
  assert_out_contains "/scv:promote" "$OUT"                 "status: suggests /scv:promote"

  # --ack updates baseline
  bash "$STATUS_SH" --ack >/dev/null 2>&1
  OUT=$(bash "$STATUS_SH" 2>&1)
  assert_out_contains "no changes since last index" "$OUT"  "status --ack: baseline updated (subsequent run clean)"

  # Add a promote plan and verify it's listed
  mkdir -p scv/promote/sample-plan
  echo "# sample PLAN" > scv/promote/sample-plan/PLAN.md
  echo "# flat note"   > scv/promote/quick-note.md
  OUT=$(bash "$STATUS_SH" 2>&1)
  assert_out_contains "scv/promote/sample-plan/PLAN.md" "$OUT" "status: lists dir-based PLAN.md"
  assert_out_contains "scv/promote/quick-note.md" "$OUT"       "status: lists flat .md entry"
  assert_out_contains "[scv/archive" "$OUT"                    "status: includes archive section"
)

echo
echo "=== [11g] /scv:work command + helper ==="
WORK_SH="$STANDARD_ROOT/scripts/work.sh"
WORK_CMD="$STANDARD_ROOT/commands/work.md"
assert_file "$WORK_SH"
assert_file "$WORK_CMD"
[[ -x "$WORK_SH" ]] && pass "work.sh executable" || fail "work.sh not executable"

# command protocol content checks
assert_contains "$WORK_CMD" "PLAN.md"
assert_contains "$WORK_CMD" "TESTS.md"
assert_contains "$WORK_CMD" "Related Documents"
assert_contains "$WORK_CMD" "AskUserQuestion"
assert_contains "$WORK_CMD" "--archive"
assert_contains "$WORK_CMD" "in_progress"
assert_contains "$WORK_CMD" "document-split"

# Build a minimal promote plan in the hydrated APP and exercise work.sh
mkdir -p "$APP/scv/promote/20260420-wookiya1364-sample-feature"
cat > "$APP/scv/promote/20260420-wookiya1364-sample-feature/PLAN.md" <<'PLAN'
---
title: Sample Feature
slug: 20260420-wookiya1364-sample-feature
author: wookiya1364
created_at: 2026-04-20
status: planned
tags: [sample]
---

# Sample Feature

## Summary
minimal plan for tests.

## Steps
1. do a thing

## Related Documents
- [ARCH.md](./ARCH.md) — arch notes
PLAN
cat > "$APP/scv/promote/20260420-wookiya1364-sample-feature/TESTS.md" <<'TESTS'
# Test Plan
## 실행 방법
echo "ok"
## 통과 판정
- prints ok
TESTS

(
  cd "$APP"
  # [1] list plans (no slug)
  OUT=$(bash "$WORK_SH" 2>&1)
  assert_out_contains "MODE: prepare" "$OUT"                     "work: emits MODE prepare"
  assert_out_contains "TARGET_SLUG: (none" "$OUT"                "work: no slug → prompt expected"
  assert_out_contains "20260420-wookiya1364-sample-feature" "$OUT" "work: lists the sample plan"

  # [2] prepare with exact slug
  OUT=$(bash "$WORK_SH" 20260420-wookiya1364-sample-feature 2>&1)
  assert_out_contains "TARGET_SLUG: 20260420-wookiya1364-sample-feature" "$OUT" "work: resolves exact slug"
  assert_out_contains "PLAN_FILE:"  "$OUT"                        "work: emits PLAN_FILE"
  assert_out_contains "TESTS_FILE:" "$OUT"                        "work: emits TESTS_FILE"
  assert_out_contains "ARCH.md" "$OUT"                            "work: lists Related Document entry"
  assert_out_contains "(MISSING)" "$OUT"                          "work: flags missing Related Document"

  # [3] fuzzy slug match
  OUT=$(bash "$WORK_SH" sample-feature 2>&1)
  assert_out_contains "TARGET_SLUG: 20260420-wookiya1364-sample-feature" "$OUT" "work: fuzzy resolves slug suffix"

  # [4] unknown slug → exit 1
  bash "$WORK_SH" totally-missing-slug >/dev/null 2>&1
  [[ $? -eq 1 ]] && pass "work: unknown slug exits 1" || fail "work: unknown slug should exit 1"

  # [5] archive
  OUT=$(bash "$WORK_SH" sample-feature --archive --reason="tests passed" 2>&1)
  assert_out_contains "ARCHIVED:" "$OUT"                          "work --archive: reports ARCHIVED line"
  [[ -d scv/archive/20260420-wookiya1364-sample-feature ]]  && pass "work --archive: folder moved to archive" || fail "work --archive: folder not moved"
  [[ ! -d scv/promote/20260420-wookiya1364-sample-feature ]] && pass "work --archive: promote folder removed" || fail "work --archive: promote folder still present"
  [[ -f scv/archive/20260420-wookiya1364-sample-feature/ARCHIVED_AT.md ]] && pass "work --archive: ARCHIVED_AT.md written" || fail "work --archive: ARCHIVED_AT.md missing"
  assert_contains "$APP/scv/archive/20260420-wookiya1364-sample-feature/ARCHIVED_AT.md" "tests passed"

  # [6] archive again should fail (destination exists or no source)
  bash "$WORK_SH" sample-feature --archive >/dev/null 2>&1
  [[ $? -ne 0 ]] && pass "work --archive: idempotent reject" || fail "work --archive: should fail when already archived"
)

echo
echo "=== [11i] /scv:work refs: parsing & grouping ==="
mkdir -p "$APP/scv/promote/20260421-wookiya1364-refs-test"
cat > "$APP/scv/promote/20260421-wookiya1364-refs-test/PLAN.md" <<'PLAN'
---
title: Refs Schema Test
slug: 20260421-wookiya1364-refs-test
author: wookiya1364
created_at: 2026-04-21
status: planned
tags: [test]
refs:
  - type: jira
    id: PAY-1234
  - type: jira
    id: PAY-1235
  - type: confluence
    url: https://confluence.example.com/x/spec
  - type: pr
    url: https://github.com/org/repo/pull/567
---
# Refs Schema Test
## Steps
1. n/a
## Related Documents
PLAN
cat > "$APP/scv/promote/20260421-wookiya1364-refs-test/TESTS.md" <<'T'
# Test Plan
## 통과 판정
- ok
T

(
  cd "$APP"
  OUT=$(bash "$WORK_SH" refs-test 2>&1)
  assert_out_contains "external refs" "$OUT" "work: emits external refs section"
  assert_out_contains "[jira] 2"      "$OUT" "work refs: jira count = 2"
  assert_out_contains "id=PAY-1234"   "$OUT" "work refs: jira id PAY-1234"
  assert_out_contains "id=PAY-1235"   "$OUT" "work refs: jira id PAY-1235"
  assert_out_contains "[confluence] 1" "$OUT" "work refs: confluence count = 1"
  assert_out_contains "https://confluence.example.com/x/spec" "$OUT" "work refs: confluence url"
  assert_out_contains "[pr] 1"        "$OUT" "work refs: pr count = 1"
  # Verify no 'id=https://' prefix bug (url-only entries should show url cleanly)
  printf '%s' "$OUT" | grep -qF "id=https://" \
    && fail "work refs: url-only entry incorrectly prefixed with 'id='" \
    || pass "work refs: url-only entries rendered without id= prefix"
)

# Plan with no refs: section should produce "(none)"
mkdir -p "$APP/scv/promote/20260421-wookiya1364-no-refs"
cat > "$APP/scv/promote/20260421-wookiya1364-no-refs/PLAN.md" <<'PLAN'
---
title: No Refs
slug: 20260421-wookiya1364-no-refs
author: wookiya1364
created_at: 2026-04-21
status: planned
tags: []
---
# No Refs
## Related Documents
PLAN
cat > "$APP/scv/promote/20260421-wookiya1364-no-refs/TESTS.md" <<'T'
# Test Plan
T
(
  cd "$APP"
  OUT=$(bash "$WORK_SH" no-refs 2>&1)
  assert_out_contains "no refs: entries" "$OUT" "work refs: empty refs case rendered"
)

echo
echo "=== [11e] /scv:promote command protocol ==="
PROMOTE_CMD_FILE="$STANDARD_ROOT/commands/promote.md"
assert_contains "$PROMOTE_CMD_FILE" "Skill(graphify)"
assert_contains "$PROMOTE_CMD_FILE" "readpath.sh"
assert_contains "$PROMOTE_CMD_FILE" "GRAPH_STATUS"
assert_contains "$PROMOTE_CMD_FILE" "--graph-only"
assert_contains "$PROMOTE_CMD_FILE" "--dry-run"
assert_contains "$PROMOTE_CMD_FILE" "AskUserQuestion"
assert_contains "$PROMOTE_CMD_FILE" "<YYYYMMDD>-<AUTHOR>-<slug>"
assert_contains "$PROMOTE_CMD_FILE" "status: planned"

echo
echo "=== [11f] /scv:status docs graph section ==="
(
  cd "$RP_APP"
  OUT=$(bash "$STATUS_SH" 2>&1)
  assert_out_contains "[docs graph" "$OUT" "status: includes docs graph section"
  # Should show exactly one of: missing, built, stale, or skill-missing message
  printf '%s' "$OUT" | grep -qE 'status: (missing|built|stale)|skill not installed' \
    && pass "status: graph state reported (one of missing/built/stale/skill-missing)" \
    || fail "status: graph state not reported"
)

echo
echo "=== [11j] ARCHITECTURE.md perspective checklist + diagrams support ==="
ARCH="$APP/scv/ARCHITECTURE.md"
assert_contains "$ARCH" "관점 체크리스트"
assert_contains "$ARCH" "Logical"
assert_contains "$ARCH" "Deployment"
assert_contains "$ARCH" "Network"
assert_contains "$ARCH" "Security"
assert_contains "$ARCH" "Compliance"
assert_contains "$ARCH" "DR/BCP"
assert_contains "$ARCH" "AI/ML"
assert_contains "$ARCH" "Observability"
assert_contains "$ARCH" "폐쇄망"
assert_contains "$ARCH" "Mermaid"
assert_contains "$ARCH" "scv/architecture/assets/"
assert_contains "$ARCH" "Related Architecture Documents"
assert_contains "$ARCH" "RTO"

echo
echo "=== [11d] PROMOTE.md protocol doc ==="
assert_file "$APP/scv/PROMOTE.md"
assert_contains "$APP/scv/PROMOTE.md" "PROMOTE — 승격 문서 작성 규약"
assert_contains "$APP/scv/PROMOTE.md" "YYYYMMDD"
assert_contains "$APP/scv/PROMOTE.md" "PLAN.md"
assert_contains "$APP/scv/PROMOTE.md" "TESTS.md"
assert_contains "$APP/scv/PROMOTE.md" "Related Documents"
assert_contains "$APP/scv/PROMOTE.md" "Archive"

echo
echo "=== [11h] /scv:help stage-aware recommendations ==="
# Build a fresh hydrated sandbox with all docs active to exercise the
# recommendation priority: draft > raw-changes > active-plans > all-clean.
HA=$(mktemp -d)
bash "$HYDRATE" init "$HA" >/dev/null 2>&1
# Mark env + docs as active to pass those gates
cp "$HA/.env.example.scv" "$HA/.env"
sed -i 's/^NOTIFIER_PROVIDER=.*/NOTIFIER_PROVIDER=slack/' "$HA/.env"
sed -i 's|^SLACK_BOT_TOKEN=.*|SLACK_BOT_TOKEN=xoxb-fake|' "$HA/.env"
# Default hydrate = adoption mode (N/A). Force all to active for this test so
# downstream states (raw changes, plan priority) can be exercised without the
# draft-docs branch taking priority.
for d in DOMAIN ARCHITECTURE DESIGN AGENTS TESTING REPORTING RALPH_PROMPT; do
  sed -i '0,/^status:/{s#^status: .*#status: active#}' "$HA/scv/$d.md"
done

(
  cd "$HA"

  # [1] all clean → "준비 완료"
  OUT=$(bash "$HELP_SH" 2>&1)
  assert_out_contains "Ready — no immediate action" "$OUT"      "help/state-clean: ready message"

  # [2] add raw file → recommends /scv:promote
  echo "note" > scv/raw/note.md
  OUT=$(bash "$HELP_SH" 2>&1)
  assert_out_contains "Detected changes in scv/raw/" "$OUT"     "help/state-raw: detects raw changes"
  assert_out_contains "/scv:promote" "$OUT"                      "help/state-raw: suggests /scv:promote"

  # [3] ack baseline + add active plan → recommends /scv:work <slug>
  bash "$READPATH_SH" update >/dev/null
  mkdir -p scv/promote/20260420-wookiya1364-feature-x
  printf -- "---\ntitle: Feature X\nslug: 20260420-wookiya1364-feature-x\n---\n# X\n" \
    > scv/promote/20260420-wookiya1364-feature-x/PLAN.md
  OUT=$(bash "$HELP_SH" 2>&1)
  assert_out_contains "active promote plan" "$OUT"               "help/state-plan: detects active plans"
  assert_out_contains "/scv:work 20260420-wookiya1364-feature-x" "$OUT" \
                                                                  "help/state-plan: suggests /scv:work <slug>"
  assert_out_contains "scv/promote has 1 active plan" "$OUT"     "help: diagnosis includes plan count"

  # [4] archive entry shows in diagnosis
  mkdir -p scv/archive/20260418-wookiya1364-old-plan
  printf 'done' > scv/archive/20260418-wookiya1364-old-plan/ARCHIVED_AT.md
  OUT=$(bash "$HELP_SH" 2>&1)
  assert_out_contains "scv/archive has 1 completed plan" "$OUT"  "help: diagnosis includes archive count"

  # [5] priority: draft docs override raw/plan detection
  sed -i '0,/^status:/{s#^status: .*#status: draft#}' scv/DOMAIN.md
  OUT=$(bash "$HELP_SH" 2>&1)
  assert_out_contains "resume or"          "$OUT"                  "help/state-priority: draft docs take precedence (A/B prompt)"
  assert_out_contains "DOMAIN"             "$OUT"                   "help/state-priority: mentions specific draft doc"
  assert_out_contains "resume check"       "$OUT"                   "help/state-priority: references INTAKE resume procedure"
  printf '%s' "$OUT" | grep -qF "활성 promote 계획이" \
    && fail "help: draft priority violated (also showed active plan message)" \
    || pass "help: draft state suppresses active-plan recommendation"
)
rm -rf "$HA"

echo
echo "=== [11c] /scv:help banner for raw changes ==="
(
  cd "$RP_APP"
  # No changes right now → banner absent
  OUT=$(bash "$HELP_SH" 2>&1)
  printf '%s' "$OUT" | grep -qF '[scv/raw]' \
    && fail "help: banner should be absent when no changes" \
    || pass "help: no banner when raw clean"

  # Introduce a change → banner appears
  echo "brand new" > scv/raw/brand-new.md
  OUT=$(bash "$HELP_SH" 2>&1)
  assert_out_contains "[scv/raw]" "$OUT"           "help: banner appears when raw has changes"
  assert_out_contains "added"     "$OUT"           "help: banner reports added count"
)

echo
echo "=== [11k] /scv:regression — supersedes graph slug-level skip ==="
assert_file "$REGRESSION_SH"
[[ -x "$REGRESSION_SH" ]] && pass "regression.sh executable" || fail "regression.sh not executable"

REG_APP=$(mktemp -d)
mkdir -p "$REG_APP/scv/archive/20260101-tester-v1"
cat > "$REG_APP/scv/archive/20260101-tester-v1/PLAN.md" <<'EOF'
---
title: v1
slug: 20260101-tester-v1
status: done
tags: [core]
---
EOF
# v1's TESTS will exit 1 — if the sentinel ever runs, regression fails
cat > "$REG_APP/scv/archive/20260101-tester-v1/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 1
```
EOF

mkdir -p "$REG_APP/scv/archive/20260201-tester-v2"
cat > "$REG_APP/scv/archive/20260201-tester-v2/PLAN.md" <<'EOF'
---
title: v2
slug: 20260201-tester-v2
status: done
tags: [core]
supersedes:
  - 20260101-tester-v1
---
EOF
cat > "$REG_APP/scv/archive/20260201-tester-v2/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 0
```
EOF

(
  cd "$REG_APP"
  OUT=$(bash "$REGRESSION_SH" 2>&1)
  rc=$?
  assert_ok_exit "$rc" "regression: supersede graph skip → rc 0 (sentinel v1 never ran)"
  assert_out_contains "SKIPPED_SUPERSEDED: 1" "$OUT" "regression: SKIPPED_SUPERSEDED = 1"
  assert_out_contains "[superseded] 20260101-tester-v1" "$OUT" "regression: skip list names victim"
  assert_out_contains "by 20260201-tester-v2" "$OUT" "regression: skip list names the by-slug"
  assert_out_contains "PASSED_SLUGS: 1" "$OUT" "regression: only v2 executed (and passed)"
  assert_out_contains "EXECUTED_SLUGS: 1" "$OUT" "regression: executed count = 1"
)
rm -rf "$REG_APP"

echo
echo "=== [11l] /scv:regression — scenario-level skip ==="
REG_APP=$(mktemp -d)
mkdir -p "$REG_APP/scv/archive/20260101-a"
cat > "$REG_APP/scv/archive/20260101-a/PLAN.md" <<'EOF'
---
title: a
slug: 20260101-a
status: done
---
EOF
cat > "$REG_APP/scv/archive/20260101-a/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 0
```
EOF
mkdir -p "$REG_APP/scv/archive/20260201-b"
cat > "$REG_APP/scv/archive/20260201-b/PLAN.md" <<'EOF'
---
title: b
slug: 20260201-b
status: done
supersedes_scenarios:
  - 20260101-a:T2
  - 20260101-a:T3
---
EOF
cat > "$REG_APP/scv/archive/20260201-b/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 0
```
EOF

(
  cd "$REG_APP"
  OUT=$(bash "$REGRESSION_SH" 2>&1)
  assert_out_contains "SKIPPED_SCENARIOS: 2" "$OUT" "regression: SKIPPED_SCENARIOS = 2"
  assert_out_contains "[scenario-skipped] 20260101-a:T2" "$OUT" "regression: T2 skip line"
  assert_out_contains "[scenario-skipped] 20260101-a:T3" "$OUT" "regression: T3 skip line"
  # Slug-level execution proceeds (scenario skip is a hint via env var, slug still runs)
  assert_out_contains "EXECUTED_SLUGS: 2" "$OUT" "regression: both slugs still executed (scenario skip is env-hint only)"
)
rm -rf "$REG_APP"

echo
echo "=== [11m] /scv:regression — obsolete marking + --include-obsolete ==="
REG_APP=$(mktemp -d)
mkdir -p "$REG_APP/scv/archive/20260101-keep" "$REG_APP/scv/archive/20260201-old"
cat > "$REG_APP/scv/archive/20260101-keep/PLAN.md" <<'EOF'
---
title: keep
slug: 20260101-keep
status: done
---
EOF
cat > "$REG_APP/scv/archive/20260101-keep/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 0
```
EOF
cat > "$REG_APP/scv/archive/20260201-old/PLAN.md" <<'EOF'
---
title: old
slug: 20260201-old
status: obsolete
obsoleted_at: 2026-03-01
obsoleted_by: manual
---
EOF
# Sentinel: if obsolete-skip fails, this exit 1 would surface
cat > "$REG_APP/scv/archive/20260201-old/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 1
```
EOF

(
  cd "$REG_APP"
  OUT=$(bash "$REGRESSION_SH" 2>&1)
  rc=$?
  assert_ok_exit "$rc" "regression: obsolete auto-skip → rc 0"
  assert_out_contains "SKIPPED_OBSOLETE: 1" "$OUT" "regression: SKIPPED_OBSOLETE = 1"
  assert_out_contains "[obsolete] 20260201-old" "$OUT" "regression: obsolete skip list entry"

  # --include-obsolete brings it back; sentinel now fails
  OUT=$(bash "$REGRESSION_SH" --include-obsolete 2>&1)
  rc=$?
  [[ $rc -ne 0 ]] && pass "regression --include-obsolete: obsolete runs → rc != 0 (sentinel fail)" || fail "regression --include-obsolete: should surface obsolete failure"
  assert_out_contains "SKIPPED_OBSOLETE: 0" "$OUT" "regression --include-obsolete: SKIPPED_OBSOLETE = 0"
  assert_out_contains "FAILED_SLUGS: 1" "$OUT" "regression --include-obsolete: fail count surfaces"
)
rm -rf "$REG_APP"

echo
echo "=== [11n] /scv:regression — --tag filter ==="
REG_APP=$(mktemp -d)
for name in a b c; do
  mkdir -p "$REG_APP/scv/archive/$name"
  case "$name" in
    a) tags_block="tags:\n  - core" ;;
    b) tags_block="tags:\n  - core\n  - auth" ;;
    c) tags_block="tags:\n  - ui" ;;
  esac
  printf -- "---\ntitle: %s\nslug: %s\nstatus: done\n%s\n---\n" "$name" "$name" "$(printf "$tags_block")" > "$REG_APP/scv/archive/$name/PLAN.md"
  printf -- "## 실행 방법\n\`\`\`bash\nexit 0\n\`\`\`\n" > "$REG_APP/scv/archive/$name/TESTS.md"
done

(
  cd "$REG_APP"
  OUT=$(bash "$REGRESSION_SH" --tag core 2>&1)
  assert_out_contains "TOTAL_SLUGS: 2" "$OUT" "regression --tag core: narrows to 2 slugs"
  assert_out_contains "TAG_FILTER: core" "$OUT" "regression --tag core: header reflects filter"
  assert_out_contains "EXECUTED_SLUGS: 2" "$OUT" "regression --tag core: both executed"
)
rm -rf "$REG_APP"

echo
echo "=== [11o] /scv:regression — --include-promote ==="
REG_APP=$(mktemp -d)
mkdir -p "$REG_APP/scv/archive/20260101-arc" "$REG_APP/scv/promote/20260301-prm"
for dir in "$REG_APP/scv/archive/20260101-arc" "$REG_APP/scv/promote/20260301-prm"; do
  slug=$(basename "$dir")
  cat > "$dir/PLAN.md" <<EOF
---
title: $slug
slug: $slug
status: done
---
EOF
  cat > "$dir/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 0
```
EOF
done

(
  cd "$REG_APP"
  OUT=$(bash "$REGRESSION_SH" 2>&1)
  assert_out_contains "TOTAL_SLUGS: 1" "$OUT" "regression: default archive-only → 1 slug"
  assert_out_contains "SCOPE: archive" "$OUT" "regression: SCOPE header = archive"

  OUT=$(bash "$REGRESSION_SH" --include-promote 2>&1)
  assert_out_contains "TOTAL_SLUGS: 2" "$OUT" "regression --include-promote: now 2 slugs"
  assert_out_contains "SCOPE: archive+promote" "$OUT" "regression --include-promote: SCOPE reflects"
)
rm -rf "$REG_APP"

echo
echo "=== [11p] /scv:regression — --ci exit 2 + JSON summary ==="
REG_APP=$(mktemp -d)
mkdir -p "$REG_APP/scv/archive/20260101-fail"
cat > "$REG_APP/scv/archive/20260101-fail/PLAN.md" <<'EOF'
---
title: fail
slug: 20260101-fail
status: done
---
EOF
cat > "$REG_APP/scv/archive/20260101-fail/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 7
```
EOF

(
  cd "$REG_APP"
  bash "$REGRESSION_SH" --ci >/dev/null 2>&1
  rc=$?
  [[ $rc -eq 2 ]] && pass "regression --ci: exit 2 on failure" || fail "regression --ci: expected exit 2, got $rc"
  [[ -f test-results/regression-summary.json ]] && pass "regression --ci: JSON summary created at test-results/" || fail "regression --ci: JSON summary missing"
  grep -qF '"failed_slugs": ["20260101-fail"]' test-results/regression-summary.json \
    && pass "regression --ci: JSON names failed slug" \
    || fail "regression --ci: JSON missing failed slug"
  grep -qF '"failed_slugs_count": 1' test-results/regression-summary.json \
    && pass "regression --ci: JSON failed count" \
    || fail "regression --ci: JSON failed count wrong"
)
rm -rf "$REG_APP"

echo
echo "=== [11q] /scv:regression — TESTS.md 실행 방법 parsing (fenced-bash / fenced-plain / 평문) ==="
REG_APP=$(mktemp -d)
# Case 1: fenced-bash
mkdir -p "$REG_APP/scv/archive/c1-fenced-bash"
cat > "$REG_APP/scv/archive/c1-fenced-bash/PLAN.md" <<'EOF'
---
title: c1
slug: c1-fenced-bash
status: done
---
EOF
cat > "$REG_APP/scv/archive/c1-fenced-bash/TESTS.md" <<'EOF'
## 실행 방법
```bash
echo "c1 ran"
exit 0
```
EOF
# Case 2: fenced-plain (no language)
mkdir -p "$REG_APP/scv/archive/c2-fenced-plain"
cat > "$REG_APP/scv/archive/c2-fenced-plain/PLAN.md" <<'EOF'
---
title: c2
slug: c2-fenced-plain
status: done
---
EOF
cat > "$REG_APP/scv/archive/c2-fenced-plain/TESTS.md" <<'EOF'
## 실행 방법
```
echo "c2 ran"
exit 0
```
EOF
# Case 3: plain text (no fence)
mkdir -p "$REG_APP/scv/archive/c3-plain"
cat > "$REG_APP/scv/archive/c3-plain/PLAN.md" <<'EOF'
---
title: c3
slug: c3-plain
status: done
---
EOF
cat > "$REG_APP/scv/archive/c3-plain/TESTS.md" <<'EOF'
## 실행 방법

echo "c3 ran"
exit 0

## 통과 판정
- done
EOF

(
  cd "$REG_APP"
  OUT=$(bash "$REGRESSION_SH" 2>&1)
  assert_out_contains "PASSED_SLUGS: 3" "$OUT" "regression parse: all three TESTS.md variants parsed + passed"
  assert_out_contains "EXECUTED_SLUGS: 3" "$OUT" "regression parse: all executed"
)
rm -rf "$REG_APP"

echo
echo "=== [11r] /scv:regression — legacy archive without PLAN.md (fallback) ==="
REG_APP=$(mktemp -d)
mkdir -p "$REG_APP/scv/archive/legacy-no-plan"
# No PLAN.md — just TESTS.md (legacy pre-SCV archive)
cat > "$REG_APP/scv/archive/legacy-no-plan/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 0
```
EOF

(
  cd "$REG_APP"
  OUT=$(bash "$REGRESSION_SH" 2>&1)
  rc=$?
  assert_ok_exit "$rc" "regression legacy: runs even with no PLAN.md (exit 0)"
  assert_out_contains "legacy-no-plan" "$OUT" "regression legacy: slug appears in execution"
  assert_out_contains "PASSED_SLUGS: 1" "$OUT" "regression legacy: counted as pass"
)
rm -rf "$REG_APP"

echo
echo "=== [11s] commands/regression.md protocol content ==="
assert_file "$REGRESSION_CMD"
assert_contains "$REGRESSION_CMD" "AskUserQuestion"
assert_contains "$REGRESSION_CMD" "supersedes"
assert_contains "$REGRESSION_CMD" "obsolete"
assert_contains "$REGRESSION_CMD" "--ci"
assert_contains "$REGRESSION_CMD" "--include-promote"
assert_contains "$REGRESSION_CMD" "--include-obsolete"
assert_contains "$REGRESSION_CMD" "regression-summary"
assert_contains "$REGRESSION_CMD" "regression-failure"
assert_contains "$REGRESSION_CMD" "Never modify the body of an archived TESTS.md"
assert_contains "$REGRESSION_CMD" "regression — true regression"
assert_contains "$REGRESSION_CMD" "flaky — environmental issue"

echo
echo "=== [11t] commands/work.md Step 9c supersede propagation content ==="
assert_contains "$WORK_CMD" "Step 9a"
assert_contains "$WORK_CMD" "Step 9b"
assert_contains "$WORK_CMD" "Step 9c"
assert_contains "$WORK_CMD" "supersede propagation"
assert_contains "$WORK_CMD" "Regression pre-flight"
assert_contains "$WORK_CMD" "Yes — mark as obsolete"
assert_contains "$WORK_CMD" "Skip — runtime skip only"
assert_contains "$WORK_CMD" "status: done → obsolete"
assert_contains "$WORK_CMD" "TESTS.md, ARCHIVED_AT.md, and other files are never touched"
assert_contains "$WORK_CMD" "permanently skip"
assert_contains "$WORK_CMD" "Default: [1] Yes"

echo
echo "=== [11u] work.sh — ARCHIVED_AT propagates supersedes ==="
REG_APP=$(mktemp -d)
mkdir -p "$REG_APP/scv/promote/20260424-me-super" "$REG_APP/scv/archive"
cat > "$REG_APP/scv/promote/20260424-me-super/PLAN.md" <<'EOF'
---
title: super
slug: 20260424-me-super
author: me
created_at: 2026-04-24
status: planned
supersedes:
  - 20260101-old-one
  - 20260102-old-two
---
EOF
cat > "$REG_APP/scv/promote/20260424-me-super/TESTS.md" <<'EOF'
## 실행 방법
exit 0
EOF

(
  cd "$REG_APP"
  bash "$WORK_SH" 20260424-me-super --archive --reason="tests passed" >/dev/null 2>&1
  [[ -f scv/archive/20260424-me-super/ARCHIVED_AT.md ]] && pass "work --archive: ARCHIVED_AT.md present" || fail "work --archive: ARCHIVED_AT.md missing"
  grep -qF "supersedes:" scv/archive/20260424-me-super/ARCHIVED_AT.md \
    && pass "work --archive: ARCHIVED_AT has supersedes block" \
    || fail "work --archive: supersedes propagation missing"
  grep -qF -- "- 20260101-old-one" scv/archive/20260424-me-super/ARCHIVED_AT.md \
    && pass "work --archive: supersedes item 1 copied" \
    || fail "work --archive: first supersedes entry missing"
  grep -qF -- "- 20260102-old-two" scv/archive/20260424-me-super/ARCHIVED_AT.md \
    && pass "work --archive: supersedes item 2 copied" \
    || fail "work --archive: second supersedes entry missing"
)
rm -rf "$REG_APP"

echo
echo "=== [11v] promote-helper.sh — split heuristic signals ==="
SPLIT_APP=$(mktemp -d)
mkdir -p "$SPLIT_APP/scv/raw/topic-a" "$SPLIT_APP/scv/raw/topic-b" "$SPLIT_APP/scv/raw/topic-c"
for i in 1 2 3 4; do echo "x" > "$SPLIT_APP/scv/raw/topic-a/f$i.md"; done
echo "y" > "$SPLIT_APP/scv/raw/topic-b/g.md"
echo "z" > "$SPLIT_APP/scv/raw/topic-c/h.md"

(
  cd "$SPLIT_APP"
  OUT=$(bash "$PROMOTE_HELPER" --dry-run 2>&1)
  assert_out_contains "RAW_FILE_COUNT: 6" "$OUT"      "promote-helper: RAW_FILE_COUNT counted"
  assert_out_contains "RAW_TOPIC_CLUSTERS: 3" "$OUT"  "promote-helper: 3 top-level dirs counted as clusters"
  assert_out_contains "SUGGEST_SPLIT: yes" "$OUT"     "promote-helper: SUGGEST_SPLIT yes when clusters>=3"
  assert_out_contains "SPLIT_REASON:" "$OUT"          "promote-helper: SPLIT_REASON line present"
)
rm -rf "$SPLIT_APP"

# negative: small raw → no split suggested
SPLIT_APP=$(mktemp -d)
mkdir -p "$SPLIT_APP/scv/raw"
echo "x" > "$SPLIT_APP/scv/raw/single.md"
(
  cd "$SPLIT_APP"
  OUT=$(bash "$PROMOTE_HELPER" --dry-run 2>&1)
  assert_out_contains "SUGGEST_SPLIT: no" "$OUT"      "promote-helper: SUGGEST_SPLIT no for small raw"
)
rm -rf "$SPLIT_APP"

echo
echo "=== [11w] check-frontmatter.sh — kind validation ==="
FRONT_APP=$(mktemp -d)
"$HYDRATE" init "$FRONT_APP" >/dev/null 2>&1
mkdir -p "$FRONT_APP/scv/promote/20260424-tester-good"
cat > "$FRONT_APP/scv/promote/20260424-tester-good/PLAN.md" <<'EOF'
---
name: plan
version: 1.0.0
status: planned
last_updated: 2026-04-24
standard_version: 1.0.0
merge_policy: preserve
title: good
slug: 20260424-tester-good
kind: refactor
epic: epic-test
---
EOF
"$CHECK_FRONT" --project-dir "$FRONT_APP" >/dev/null 2>&1 \
  && pass "check-frontmatter: kind=refactor accepted" \
  || fail "check-frontmatter: rejected valid kind=refactor"

# bad kind
mkdir -p "$FRONT_APP/scv/promote/20260424-tester-bad"
cat > "$FRONT_APP/scv/promote/20260424-tester-bad/PLAN.md" <<'EOF'
---
name: plan
version: 1.0.0
status: planned
last_updated: 2026-04-24
standard_version: 1.0.0
merge_policy: preserve
title: bad
slug: 20260424-tester-bad
kind: nonsense
---
EOF
if "$CHECK_FRONT" --project-dir "$FRONT_APP" >/dev/null 2>&1; then
  fail "check-frontmatter: should reject kind=nonsense"
else
  pass "check-frontmatter: kind=nonsense rejected"
fi
rm -rf "$FRONT_APP"

echo
echo "=== [11x] /scv:status — epic progress section ==="
EPIC_APP=$(mktemp -d)
mkdir -p "$EPIC_APP/scv/archive/20260101-a-feat1" "$EPIC_APP/scv/archive/20260101-a-feat2" \
         "$EPIC_APP/scv/archive/20260101-a-refact" "$EPIC_APP/scv/promote/20260202-a-feat3" \
         "$EPIC_APP/scv/promote/20260301-b-feat1" "$EPIC_APP/scv/raw"

for f in 20260101-a-feat1 20260101-a-feat2; do
  cat > "$EPIC_APP/scv/archive/$f/PLAN.md" <<EOF
---
title: $f
slug: $f
status: done
epic: epic-payment
kind: feature
---
EOF
done
cat > "$EPIC_APP/scv/archive/20260101-a-refact/PLAN.md" <<'EOF'
---
title: refact
slug: 20260101-a-refact
status: done
epic: epic-payment
kind: refactor
---
EOF
cat > "$EPIC_APP/scv/promote/20260202-a-feat3/PLAN.md" <<'EOF'
---
title: feat3
slug: 20260202-a-feat3
status: planned
epic: epic-payment
kind: feature
---
EOF
cat > "$EPIC_APP/scv/promote/20260301-b-feat1/PLAN.md" <<'EOF'
---
title: search
slug: 20260301-b-feat1
status: planned
epic: epic-search
kind: feature
---
EOF

(
  cd "$EPIC_APP"
  OUT=$(bash "$STATUS_SH" 2>&1)
  assert_out_contains "[epics" "$OUT"                                   "status: epic section header present"
  assert_out_contains "epic epic-payment" "$OUT"                        "status: lists epic-payment"
  assert_out_contains "2/3 archived" "$OUT"                             "status: epic-payment shows 2/3 archived"
  assert_out_contains "1 in promote" "$OUT"                             "status: epic-payment shows 1 in promote"
  assert_out_contains "refactor done" "$OUT"                            "status: epic-payment refactor done"
  assert_out_contains "epic epic-search" "$OUT"                         "status: lists epic-search"
  assert_out_contains "0/1 archived" "$OUT"                             "status: epic-search shows 0/1 archived"
)

# no-epic case
NOEPIC_APP=$(mktemp -d)
mkdir -p "$NOEPIC_APP/scv/raw" "$NOEPIC_APP/scv/promote" "$NOEPIC_APP/scv/archive"
(
  cd "$NOEPIC_APP"
  OUT=$(bash "$STATUS_SH" 2>&1)
  assert_out_contains "no epics" "$OUT"                                 "status: empty epic list shows '(no epics)'"
)
rm -rf "$EPIC_APP" "$NOEPIC_APP"

echo
echo "=== [11y] pr-helper.sh — dry-run body assembly ==="
PR_APP=$(mktemp -d)
mkdir -p "$PR_APP/scv/archive/20260424-tester-feat" "$PR_APP/test-results"
cat > "$PR_APP/scv/archive/20260424-tester-feat/PLAN.md" <<'EOF'
---
title: Sample feature
slug: 20260424-tester-feat
author: tester
created_at: 2026-04-24
status: done
kind: feature
epic: epic-sample
---

## Summary

A small sample feature for PR helper testing.

## Goals / Non-Goals

- Goals: validate body assembly
- Non-Goals: real gh

## Steps

1. step one
2. step two

## Related Documents
EOF
cat > "$PR_APP/scv/archive/20260424-tester-feat/TESTS.md" <<'EOF'
# T
## 실행 방법
```bash
exit 0
```
## 통과 판정
- always passes
EOF
cat > "$PR_APP/scv/archive/20260424-tester-feat/ARCHIVED_AT.md" <<'EOF'
---
archived_at: 2026-04-28
archived_by: tester
reason: tests passed
---
EOF
echo "fakepng" > "$PR_APP/test-results/screenshot.png"

(
  cd "$PR_APP"
  OUT=$(bash "$PR_HELPER" 20260424-tester-feat --dry-run 2>&1)
  assert_out_contains "feat: Sample feature" "$OUT"            "pr-helper: title prefix=feat"
  assert_out_contains "epic/epic-sample" "$OUT"                "pr-helper: base branch is epic/<slug>"
  assert_out_contains "screenshot.png" "$OUT"                  "pr-helper: screenshot listed"
  assert_out_contains ".scv-pr-artifacts/20260424-tester-feat/screenshot.png" "$OUT" \
                                                                "pr-helper: body has artifact path"
  assert_out_contains "A small sample feature for PR helper testing" "$OUT" \
                                                                "pr-helper: PLAN summary embedded"
  assert_out_contains "Archived 2026-04-28 by tester" "$OUT"   "pr-helper: ARCHIVED_AT footer"
  assert_out_contains "Epic: \`epic-sample\`" "$OUT"           "pr-helper: epic footer"
)

# kind=refactor → title prefix "refactor:"
mkdir -p "$PR_APP/scv/archive/20260430-tester-refact"
cat > "$PR_APP/scv/archive/20260430-tester-refact/PLAN.md" <<'EOF'
---
title: Integration cleanup
slug: 20260430-tester-refact
status: done
kind: refactor
epic: epic-sample
---
## Summary
refactor only
## Steps
1. clean up
EOF
(
  cd "$PR_APP"
  OUT=$(bash "$PR_HELPER" tester-refact --dry-run 2>&1)
  assert_out_contains "refactor: Integration cleanup" "$OUT"   "pr-helper: kind=refactor → title prefix"
)

# kind=retirement → title prefix "chore:"
mkdir -p "$PR_APP/scv/archive/20260424-tester-retire"
cat > "$PR_APP/scv/archive/20260424-tester-retire/PLAN.md" <<'EOF'
---
title: Retire old API
slug: 20260424-tester-retire
status: done
kind: retirement
---
## Summary
remove old api
## Steps
1. delete
EOF
(
  cd "$PR_APP"
  OUT=$(bash "$PR_HELPER" tester-retire --dry-run 2>&1)
  assert_out_contains "chore: Retire old API" "$OUT"           "pr-helper: kind=retirement → chore prefix"
)
rm -rf "$PR_APP"

echo
echo "=== [11z] regression.sh — CI=true env auto-detect ==="
CI_APP=$(mktemp -d)
mkdir -p "$CI_APP/scv/archive/20260101-failing"
cat > "$CI_APP/scv/archive/20260101-failing/PLAN.md" <<'EOF'
---
title: failing
slug: 20260101-failing
status: done
---
EOF
cat > "$CI_APP/scv/archive/20260101-failing/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 7
```
EOF

(
  cd "$CI_APP"
  # CI=true alone (no --ci flag) should trigger CI mode:
  #  - exit 2 (not 1)
  #  - test-results/regression-summary.json created
  CI=true bash "$REGRESSION_SH" >/dev/null 2>&1
  rc=$?
  [[ $rc -eq 2 ]] && pass "regression: CI=true → exit 2 (CI mode auto-detected)" || fail "regression: CI=true expected exit 2, got $rc"
  [[ -f test-results/regression-summary.json ]] && pass "regression: CI=true → JSON summary auto-created" || fail "regression: JSON summary missing under CI=true"
)
rm -rf "$CI_APP"

echo
echo "=== [11ee] pr-helper.sh — 비디오 감지 (dry-run) ==="
PR_APP=$(mktemp -d)
mkdir -p "$PR_APP/scv/archive/20260429-test-feat" "$PR_APP/test-results"
cat > "$PR_APP/scv/archive/20260429-test-feat/PLAN.md" <<'EOF'
---
title: Video pickup test
slug: 20260429-test-feat
status: done
kind: feature
---
## Summary
sample
## Goals / Non-Goals
- Goals: x
## Steps
1. y
EOF
cat > "$PR_APP/scv/archive/20260429-test-feat/TESTS.md" <<'EOF'
## 실행 방법
```bash
exit 0
```
## 통과 판정
- ok
EOF
echo "fakewebm" > "$PR_APP/test-results/recording.webm"
echo "fakemp4" > "$PR_APP/test-results/demo.mp4"
echo "fakepng" > "$PR_APP/test-results/screenshot.png"

(
  cd "$PR_APP"
  git init -q -b main
  git remote add origin https://github.com/test/test.git
  OUT=$(bash "$PR_HELPER" 20260429-test-feat --dry-run 2>&1)
  assert_out_contains "Videos to attach" "$OUT"            "pr-helper: Videos section in dry-run"
  assert_out_contains "recording.webm" "$OUT"              "pr-helper: lists .webm"
  assert_out_contains "demo.mp4" "$OUT"                    "pr-helper: lists .mp4"
  assert_out_contains "scv-attachments" "$OUT"             "pr-helper: mentions orphan branch"
  assert_out_contains "SCV_VIDEO_PLACEHOLDER" "$OUT"       "pr-helper: body has video placeholder"
  assert_out_contains "screenshot.png" "$OUT"              "pr-helper: still lists screenshots"
)
rm -rf "$PR_APP"

echo
echo "=== [11ff] lib/attachments.sh — _get_github_owner_repo URL parsing ==="
bash <<'INNER_EOF'
source /home/zpsuk/바탕화면/work/labs/scv-claude-code/scripts/lib/attachments.sh
TMP=$(mktemp -d); cd "$TMP"; git init -q -b main

git remote add origin https://github.com/owner/repo.git
out=$(_get_github_owner_repo)
[[ "$out" == "owner/repo" ]] && echo PASS https-git || echo FAIL https-git "got=$out"

git remote set-url origin git@github.com:owner/repo.git
out=$(_get_github_owner_repo)
[[ "$out" == "owner/repo" ]] && echo PASS ssh-git || echo FAIL ssh-git "got=$out"

git remote set-url origin https://github.com/owner/repo
out=$(_get_github_owner_repo)
[[ "$out" == "owner/repo" ]] && echo PASS https-no-suffix || echo FAIL https-no-suffix "got=$out"

git remote set-url origin https://gitlab.com/owner/repo.git
_get_github_owner_repo >/dev/null && echo FAIL gitlab-rejected || echo PASS gitlab-rejected

cd /; rm -rf "$TMP"
INNER_EOF
PARSE_OUT=$(bash <<'INNER_EOF'
source /home/zpsuk/바탕화면/work/labs/scv-claude-code/scripts/lib/attachments.sh
TMP=$(mktemp -d); cd "$TMP"; git init -q -b main
for url in "https://github.com/owner/repo.git" "git@github.com:owner/repo.git" "https://github.com/owner/repo"; do
  if [[ -d .git ]]; then git remote remove origin 2>/dev/null; fi
  git remote add origin "$url"
  out=$(_get_github_owner_repo); echo "$url -> $out"
done
git remote set-url origin https://gitlab.com/owner/repo.git
if _get_github_owner_repo >/dev/null; then echo "gitlab-not-rejected"; else echo "gitlab-rejected"; fi
cd /; rm -rf "$TMP"
INNER_EOF
)
printf '%s' "$PARSE_OUT" | grep -qF "https://github.com/owner/repo.git -> owner/repo" && pass "attachments URL: https/.git → owner/repo" || fail "attachments URL: https/.git parse"
printf '%s' "$PARSE_OUT" | grep -qF "git@github.com:owner/repo.git -> owner/repo" && pass "attachments URL: ssh/.git → owner/repo" || fail "attachments URL: ssh/.git parse"
printf '%s' "$PARSE_OUT" | grep -qF "https://github.com/owner/repo -> owner/repo" && pass "attachments URL: https no-suffix → owner/repo" || fail "attachments URL: no-suffix parse"
printf '%s' "$PARSE_OUT" | grep -qF "gitlab-rejected" && pass "attachments URL: gitlab rejected" || fail "attachments URL: gitlab not rejected"

echo
echo "=== [11gg] lib/attachments.sh — backend dispatch + stub ==="
DISPATCH_OUT=$(bash <<'INNER_EOF'
source /home/zpsuk/바탕화면/work/labs/scv-claude-code/scripts/lib/attachments.sh
TMP=$(mktemp -d); cd "$TMP"; git init -q -b main
git remote add origin https://gitlab.com/x/y.git    # non-github, will fail anyway
SCV_ATTACHMENTS_BACKEND=invalid attachments_upload x 1 2>&1 | head -1
echo "---"
echo "fake" > /tmp/test.webm
SCV_ATTACHMENTS_BACKEND=s3 attachments_upload x 1 /tmp/test.webm 2>&1 | head -2
rm -f /tmp/test.webm
cd /; rm -rf "$TMP"
INNER_EOF
)
printf '%s' "$DISPATCH_OUT" | grep -qF "unknown SCV_ATTACHMENTS_BACKEND='invalid'" && pass "attachments dispatch: invalid backend rejected" || fail "attachments dispatch: invalid not rejected"
printf '%s' "$DISPATCH_OUT" | grep -qF "s3 backend not yet implemented" && pass "attachments dispatch: s3 stub warning" || fail "attachments dispatch: s3 stub missing"

echo
echo "=== [11hh] lib/attachments.sh — size guards ==="
SIZE_OUT=$(bash <<'INNER_EOF'
source /home/zpsuk/바탕화면/work/labs/scv-claude-code/scripts/lib/attachments.sh
TMP=$(mktemp -d); cd "$TMP"; git init -q -b main
git remote add origin https://github.com/test/test.git

# fake remote bare so push works
BARE=$(mktemp -d -t bare.XXX)
git init -q --bare "$BARE"
git remote set-url origin "$BARE"
echo init > README.md
git add README.md
git -c user.email=t@t -c user.name=t commit -q -m init
git push -q origin main 2>&1

# 51MB fake file
dd if=/dev/zero of=/tmp/big.webm bs=1024 count=$((51*1024)) 2>/dev/null

# patch URL parser to return owner/repo (real check would fail on bare path)
_get_github_owner_repo() { echo "test/test"; return 0; }
SCV_ATTACHMENTS_BRANCH=scv-attachments \
  attachments_upload size-test 99 /tmp/big.webm 2>&1 | grep -E '50MB|>50MB' | head -1

rm -f /tmp/big.webm
cd /; rm -rf "$TMP" "$BARE"
INNER_EOF
)
printf '%s' "$SIZE_OUT" | grep -qE 'WARN.*51MB|>50MB' && pass "attachments size: 50MB+ WARN" || fail "attachments size: 50MB+ WARN missing — got: $SIZE_OUT"

echo
echo "=== [11ii] lib/attachments.sh — manifest + cleanup with mock gh ==="
CLEAN_OUT=$(bash <<'INNER_EOF'
WORK=$(mktemp -d)
ORIGIN="$WORK/origin.git"
LOCAL="$WORK/repo"
git init -q --bare "$ORIGIN"
git init -q -b main "$LOCAL"
cd "$LOCAL"
git remote add origin "$ORIGIN"
echo init > README.md
git add README.md
git -c user.email=t@t -c user.name=t commit -q -m init
git push -q origin main

source /home/zpsuk/바탕화면/work/labs/scv-claude-code/scripts/lib/attachments.sh
_get_github_owner_repo() { echo "x/y"; return 0; }

echo "fake1" > /tmp/v1.webm
echo "fake2" > /tmp/v2.webm
SCV_ATTACHMENTS_BRANCH=scv-attachments attachments_upload merged-old 100 /tmp/v1.webm >/dev/null 2>&1
SCV_ATTACHMENTS_BRANCH=scv-attachments attachments_upload still-open 200 /tmp/v2.webm >/dev/null 2>&1

# Mock gh CLI
MOCK=$(mktemp -d)
cat > "$MOCK/gh" <<'GH'
#!/usr/bin/env bash
if [[ "$1 $2" == "pr view" ]]; then
  if [[ "$3" == "100" ]]; then
    closed=$(date -u -d '5 days ago' +%Y-%m-%dT%H:%M:%SZ)
    echo "{\"state\":\"MERGED\",\"closedAt\":\"$closed\"}"
  elif [[ "$3" == "200" ]]; then
    echo "{\"state\":\"OPEN\",\"closedAt\":null}"
  fi
fi
GH
chmod +x "$MOCK/gh"
PATH="$MOCK:$PATH" SCV_ATTACHMENTS_BRANCH=scv-attachments RETENTION_DAYS=3 \
  attachments_cleanup_stale 2>&1

# Verify orphan state
git fetch -q origin scv-attachments 2>/dev/null
git ls-tree -r origin/scv-attachments | awk '{print $4}'

cd /; rm -rf "$WORK" "$MOCK"
INNER_EOF
)
printf '%s' "$CLEAN_OUT" | grep -qF "DELETED merged-old" && pass "attachments cleanup: stale slug deleted" || fail "attachments cleanup: DELETED line missing"
printf '%s' "$CLEAN_OUT" | grep -qF "still-open/v2.webm" && pass "attachments cleanup: open PR preserved" || fail "attachments cleanup: open PR was deleted"
printf '%s' "$CLEAN_OUT" | grep -qF "merged-old/v1.webm" && fail "attachments cleanup: merged file still in tree" || pass "attachments cleanup: merged file removed from tree"

echo
echo "=== [11jj] commands/work.md — Step 9d retention AskUserQuestion content ==="
assert_contains "$WORK_CMD" "SCV_ATTACHMENTS_RETENTION_DAYS"
assert_contains "$WORK_CMD" "3 days (default"
assert_contains "$WORK_CMD" "7 days"
assert_contains "$WORK_CMD" "30 days"
assert_contains "$WORK_CMD" "Never"

echo
echo "=== [11kk] commands/work.md — Step 5b Playwright auto-detect content ==="
assert_contains "$WORK_CMD" "Step 5b"
assert_contains "$WORK_CMD" "playwright.config"
assert_contains "$WORK_CMD" "video: 'on'"

echo
echo "=== [11ll] commands/work.md — Step 9d video flow content ==="
assert_contains "$WORK_CMD" "scv-attachments orphan branch"
assert_contains "$WORK_CMD" "zero impact on the"
assert_contains "$WORK_CMD" "inline playback"

echo
echo "=== [11mm] lib/attachments.sh — v0.3.0 layout → v0.3.1 scv/ subdirectory 자동 migration ==="
MIGRATE_OUT=$(bash <<'INNER_EOF'
WORK=$(mktemp -d)
ORIGIN="$WORK/origin.git"
LOCAL="$WORK/repo"
git init -q --bare "$ORIGIN"
git init -q -b main "$LOCAL"
cd "$LOCAL"
git remote add origin "$ORIGIN"
echo init > README.md
git add README.md
git -c user.email=t@t -c user.name=t commit -q -m init
git push -q origin main

# Seed a v0.3.0 layout orphan branch on origin:
#   root/manifest.json + root/<slug>/<file> (NO scv/ subdir).
git worktree add --detach "$WORK/wt0" >/dev/null 2>&1
(
  cd "$WORK/wt0"
  git checkout --orphan scv-attachments >/dev/null 2>&1
  git rm -rf . >/dev/null 2>&1 || true
  echo "v0.3.0 init" > README.md
  printf '{"version":1,"entries":{"old-slug":{"pr_number":7,"added_at":"2026-04-01T00:00:00Z"}}}\n' > manifest.json
  mkdir -p old-slug
  echo "fake old video" > old-slug/legacy.webm
  git add README.md manifest.json old-slug
  git -c user.email=t@t -c user.name=t commit -q -m "v0.3.0 init"
  git push -q origin scv-attachments
)
git worktree remove --force "$WORK/wt0" >/dev/null 2>&1
git branch -D scv-attachments >/dev/null 2>&1

source /home/zpsuk/바탕화면/work/labs/scv-claude-code/scripts/lib/attachments.sh
_get_github_owner_repo() { echo "x/y"; return 0; }

# Trigger migration through a normal upload call (also adds new entry).
echo "fake1" > /tmp/post-mig.webm
SCV_ATTACHMENTS_BRANCH=scv-attachments \
  attachments_upload migrated-pr 42 /tmp/post-mig.webm 2>&1

# Idempotency: second upload must NOT create another migration commit.
echo "fake2" > /tmp/post-mig2.webm
SCV_ATTACHMENTS_BRANCH=scv-attachments \
  attachments_upload migrated-pr-2 43 /tmp/post-mig2.webm >/dev/null 2>&1

echo "---FILES---"
git ls-tree -r origin/scv-attachments | awk '{print $4}'
echo "---LOG---"
git log --format='%s' origin/scv-attachments

cd /; rm -rf "$WORK"
INNER_EOF
)

printf '%s' "$MIGRATE_OUT" | grep -qF "Migrated v0.3.0 layout → scv/" \
  && pass "attachments migrate: stderr notice emitted" \
  || fail "attachments migrate: stderr notice missing"

printf '%s' "$MIGRATE_OUT" | awk '/---FILES---/,/---LOG---/' | grep -qE '^scv/manifest\.json$' \
  && pass "attachments migrate: scv/manifest.json present on origin" \
  || fail "attachments migrate: scv/manifest.json absent"

printf '%s' "$MIGRATE_OUT" | awk '/---FILES---/,/---LOG---/' | grep -qE '^manifest\.json$' \
  && fail "attachments migrate: root manifest.json still in tree" \
  || pass "attachments migrate: root manifest.json removed"

printf '%s' "$MIGRATE_OUT" | awk '/---FILES---/,/---LOG---/' | grep -qE '^scv/old-slug/legacy\.webm$' \
  && pass "attachments migrate: legacy slug folder moved to scv/" \
  || fail "attachments migrate: legacy slug not under scv/"

printf '%s' "$MIGRATE_OUT" | awk '/---FILES---/,/---LOG---/' | grep -qE '^old-slug/' \
  && fail "attachments migrate: old root slug folder still in tree" \
  || pass "attachments migrate: old root slug folder removed"

printf '%s' "$MIGRATE_OUT" | grep -qF "Migrate v0.3.0 layout → scv/ subdirectory (v0.3.1)" \
  && pass "attachments migrate: commit message correct" \
  || fail "attachments migrate: commit message missing"

migrate_count=$(printf '%s' "$MIGRATE_OUT" | awk '/---LOG---/{flag=1;next} flag' | grep -c "Migrate v0.3.0 layout")
[[ "$migrate_count" == "1" ]] \
  && pass "attachments migrate: idempotent (exactly 1 migration commit)" \
  || fail "attachments migrate: expected 1 migration commit, got $migrate_count"

echo
echo "=== [11nn] lib/attachments.sh — attachments_status stale 정확 카운트 + 캐시 ==="
STATUS_OUT=$(bash <<'INNER_EOF'
WORK=$(mktemp -d)
ORIGIN="$WORK/origin.git"
LOCAL="$WORK/repo"
git init -q --bare "$ORIGIN"
git init -q -b main "$LOCAL"
cd "$LOCAL"
git remote add origin "$ORIGIN"
echo init > README.md
git add README.md
git -c user.email=t@t -c user.name=t commit -q -m init
git push -q origin main

source /home/zpsuk/바탕화면/work/labs/scv-claude-code/scripts/lib/attachments.sh
_get_github_owner_repo() { echo "x/y"; return 0; }

echo "f1" > /tmp/s1.webm; echo "f2" > /tmp/s2.webm; echo "f3" > /tmp/s3.webm
SCV_ATTACHMENTS_BRANCH=scv-attachments attachments_upload slug-merged-old 100 /tmp/s1.webm >/dev/null 2>&1
SCV_ATTACHMENTS_BRANCH=scv-attachments attachments_upload slug-open 200 /tmp/s2.webm >/dev/null 2>&1
SCV_ATTACHMENTS_BRANCH=scv-attachments attachments_upload slug-merged-recent 300 /tmp/s3.webm >/dev/null 2>&1

MOCK=$(mktemp -d)
make_real_mock() {
cat > "$MOCK/gh" <<'GH'
#!/usr/bin/env bash
if [[ "$1 $2" == "pr view" ]]; then
  case "$3" in
    100) c=$(date -u -d '5 days ago' +%Y-%m-%dT%H:%M:%SZ); echo "{\"state\":\"MERGED\",\"closedAt\":\"$c\"}" ;;
    200) echo '{"state":"OPEN","closedAt":null}' ;;
    300) c=$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ); echo "{\"state\":\"MERGED\",\"closedAt\":\"$c\"}" ;;
  esac
fi
GH
chmod +x "$MOCK/gh"
}
make_real_mock

rm -f /tmp/scv-attachments-status-x_y-3.json /tmp/scv-attachments-status-x_y-7.json

# 1) Cache miss → compute fresh count
echo "---FRESH-3---"
PATH="$MOCK:$PATH" SCV_ATTACHMENTS_BRANCH=scv-attachments SCV_ATTACHMENTS_RETENTION_DAYS=3 \
  _attachments_git_orphan_status

echo "---CACHE-FILE-3---"
[[ -f /tmp/scv-attachments-status-x_y-3.json ]] && echo "EXISTS" || echo "MISSING"

# 2) Cache hit verification: swap mock to "all OPEN" — would compute stale=0
# if recomputed. Cache hit must serve previous stale=1.
cat > "$MOCK/gh" <<'GH'
#!/usr/bin/env bash
[[ "$1 $2" == "pr view" ]] && echo '{"state":"OPEN","closedAt":null}'
GH
chmod +x "$MOCK/gh"
echo "---HIT-3---"
PATH="$MOCK:$PATH" SCV_ATTACHMENTS_BRANCH=scv-attachments SCV_ATTACHMENTS_RETENTION_DAYS=3 \
  _attachments_git_orphan_status

make_real_mock

# 3) retention=7 → separate cache key, fresh compute (PR 100 closed 5d < 7d → not stale)
echo "---FRESH-7---"
PATH="$MOCK:$PATH" SCV_ATTACHMENTS_BRANCH=scv-attachments SCV_ATTACHMENTS_RETENTION_DAYS=7 \
  _attachments_git_orphan_status

echo "---CACHE-FILE-7---"
[[ -f /tmp/scv-attachments-status-x_y-7.json ]] && echo "EXISTS" || echo "MISSING"

# 4) SHA mismatch → invalidate poisoned cache → recompute
python3 -c "import json; json.dump({'head_sha':'badbeef','stale':99}, open('/tmp/scv-attachments-status-x_y-3.json','w'))"
echo "---INVALIDATED-3---"
PATH="$MOCK:$PATH" SCV_ATTACHMENTS_BRANCH=scv-attachments SCV_ATTACHMENTS_RETENTION_DAYS=3 \
  _attachments_git_orphan_status

cd /; rm -rf "$WORK" "$MOCK" /tmp/scv-attachments-status-x_y-3.json /tmp/scv-attachments-status-x_y-7.json
INNER_EOF
)

printf '%s' "$STATUS_OUT" | awk '/---FRESH-3---/{f=1;next} /---CACHE-FILE-3---/{f=0} f' | grep -qE 'stale=1\b' \
  && pass "attachments status: fresh count retention=3 → stale=1" \
  || fail "attachments status: expected stale=1 at retention=3"

printf '%s' "$STATUS_OUT" | awk '/---CACHE-FILE-3---/{f=1;next} /---HIT-3---/{f=0} f' | grep -qF "EXISTS" \
  && pass "attachments status: cache file created" \
  || fail "attachments status: cache file not created"

printf '%s' "$STATUS_OUT" | awk '/---HIT-3---/{f=1;next} /---FRESH-7---/{f=0} f' | grep -qE 'stale=1\b' \
  && pass "attachments status: cache hit serves cached value (gh ignored)" \
  || fail "attachments status: cache miss (cache not used)"

printf '%s' "$STATUS_OUT" | awk '/---FRESH-7---/{f=1;next} /---CACHE-FILE-7---/{f=0} f' | grep -qE 'stale=0\b' \
  && pass "attachments status: retention=7 → stale=0 (separate cache key)" \
  || fail "attachments status: retention=7 expected stale=0"

printf '%s' "$STATUS_OUT" | awk '/---INVALIDATED-3---/{f=1;next} f' | grep -qE 'stale=1\b' \
  && pass "attachments status: SHA mismatch invalidates cache (recomputes)" \
  || fail "attachments status: stale SHA cache used (poisoning)"

echo
echo "=== [11oo] commands/work.md — Step 5b Playwright 표준화 + non-Playwright 안내 ==="
assert_contains "$WORK_CMD" "standard E2E framework is Playwright"
assert_contains "$WORK_CMD" "playwright.config.{ts,js,mjs,cjs}"
assert_contains "$WORK_CMD" "non-Playwright notice"
assert_contains "$WORK_CMD" "Cypress → Playwright"
assert_contains "$WORK_CMD" "Puppeteer → Playwright"
assert_contains "$WORK_CMD" "playwright.dev/docs/migrating-from-cypress"
assert_contains "$WORK_CMD" "playwright.dev/docs/puppeteer"
# Cypress 5c 가 v0.3.1 에서 제거됐는지 확인 (non-Playwright 는 안내만)
grep -qF "Step 5c — Cypress 비디오 자동 설정" "$WORK_CMD" \
  && fail "work.md: Cypress 5c 자동 감지 step 가 남아있음 (v0.3.1 stance: 안내만)" \
  || pass "work.md: Cypress 5c step 제거됨 (안내만 stance 일관)"

echo
echo "=== [11qq] commands/*.md — Language preference instruction (v0.4+) ==="
for cmd in help work promote regression status report sync; do
  CMD_FILE="$STANDARD_ROOT/commands/${cmd}.md"
  assert_contains "$CMD_FILE" "Language preference"
  assert_contains "$CMD_FILE" "SCV_LANG"
  assert_contains "$CMD_FILE" "Default to English"
done

# /scv:help 의 4지선다 first-time setup 흐름 검증
HELP_CMD="$STANDARD_ROOT/commands/help.md"
assert_contains "$HELP_CMD" "First-time language setup"
assert_contains "$HELP_CMD" "한국어 (Korean)"
assert_contains "$HELP_CMD" "日本語 (Japanese)"
assert_contains "$HELP_CMD" "Other — type a language"
assert_contains "$HELP_CMD" "Which language do you prefer for SCV output?"

# .env.example.scv 에 SCV_LANG 주석 존재
assert_contains "$STANDARD_ROOT/template/.env.example.scv" "SCV_LANG"

echo
echo "=== [11dd] PROMOTE.md — fast-path section (v0.2.1) ==="
PROMOTE_DOC="$STANDARD_ROOT/template/scv/PROMOTE.md"
assert_contains "$PROMOTE_DOC" "Fast-path"
assert_contains "$PROMOTE_DOC" "promote 없이 직접 PR"
assert_contains "$PROMOTE_DOC" "오타 수정"
assert_contains "$PROMOTE_DOC" "의존성 패치 버전"
assert_contains "$PROMOTE_DOC" "의심스러우면 정식 promote"
assert_contains "$PROMOTE_DOC" "검증을 건너뛰는 게 아닙니다"

echo
echo "=== [11aa] PROMOTE.md — epic / refactor / retirement docs ==="
PROMOTE_DOC="$STANDARD_ROOT/template/scv/PROMOTE.md"
assert_contains "$PROMOTE_DOC" "Epic 브랜치 전략"
assert_contains "$PROMOTE_DOC" "Refactor PLAN"
assert_contains "$PROMOTE_DOC" "epic/<epic-slug>"
assert_contains "$PROMOTE_DOC" "kind: refactor"
assert_contains "$PROMOTE_DOC" "kind: retirement"
assert_contains "$PROMOTE_DOC" "epic 의 모든 feature"
assert_contains "$PROMOTE_DOC" "supersedes_scenarios"

echo
echo "=== [11bb] commands/work.md — Step 9d/9e content ==="
assert_contains "$WORK_CMD" "Step 9d"
assert_contains "$WORK_CMD" "Step 9e"
assert_contains "$WORK_CMD" "auto-create PR"
assert_contains "$WORK_CMD" "pr-helper.sh"
assert_contains "$WORK_CMD" "All features of epic"
assert_contains "$WORK_CMD" "refactor PLAN scaffold"
assert_contains "$WORK_CMD" ".scv-pr-artifacts"

echo
echo "=== [11cc] commands/*.md — argument-hint minimization ==="
# After v0.2.0 cleanup, no --flag should appear in any argument-hint frontmatter line.
for f in "$STANDARD_ROOT/commands"/*.md; do
  hint=$(awk '/^argument-hint:/ {sub(/^argument-hint:[[:space:]]*/, ""); print; exit}' "$f")
  if printf '%s' "$hint" | grep -qE -- '--[a-z]'; then
    fail "command $(basename "$f"): argument-hint still exposes flag: $hint"
  else
    pass "command $(basename "$f"): argument-hint flag-free"
  fi
done

echo
echo "=== [10] sync --dry-run (version detection) ==="
# Force a local divergence on a preserve-policy file so sync reports SKIP
printf '\n<!-- local note: force divergence -->\n' >> "$APP/scv/AGENTS.md"
OUT=$("$SYNC" --project-dir "$APP" --dry-run 2>&1)
rc=$?
assert_ok_exit "$rc" "sync --dry-run: exit 0"
assert_out_contains "local=${VERSION_NOW} → remote=${VERSION_NOW}" "$OUT" "sync: version parity detected"
assert_out_contains "SKIP      scv/AGENTS.md" "$OUT" "sync: preserve policy honored (scv/ prefix)"

# Aggregate counters from temp files
PASS=$(wc -l < "$PASS_FILE" | tr -d ' ')
FAIL=$(wc -l < "$FAIL_FILE" | tr -d ' ')

echo
echo "============================================"
printf " \033[32mPASS: %d\033[0m   " "$PASS"
if [[ "$FAIL" -gt 0 ]]; then printf '\033[31mFAIL: %d\033[0m\n' "$FAIL"; else printf 'FAIL: 0\n'; fi
echo "============================================"

if [[ "$FAIL" -gt 0 ]]; then
  echo
  echo "Failed:"
  while IFS= read -r t; do printf '  - %s\n' "$t"; done < "$FAILED_NAMES_FILE"
  exit 1
fi
exit 0
