#!/usr/bin/env bash
# The regression runner runs scenarios in a CLEAN environment.
#
# The runner starts by asking "are the workflow docs stale?" once, and marks
# "already checked" (SCV_AUTOSYNC_RUNNING=1) so its own helpers do not repeat
# the check. That mark used to leak into every scenario the runner spawned —
# and a scenario that TESTS the autosync hook saw the hook no-op itself into
# 10/11 red while the same suite passed 21/21 standalone. These cases pin the
# hygiene down from both sides: the runner's own mark must not reach a
# scenario, and everything else — the user's own env, the runner's one-check
# convergence, the --ci contract — must keep working exactly as before.
#
# Sentinels are CANARY-*-9f3a-style tokens, per the self-trapping-test lesson
# in test-sync-dirty.sh.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/regression.sh" ]]; then
      CORE="$(cd "$up/$sub" && pwd)"; break 2
    fi
  done
done
[[ -n "$CORE" ]] || { echo "test-regression-env: payload not found from $HERE" >&2; exit 1; }
RUNNER="$CORE/scripts/regression.sh"
HYDRATE="$CORE/scripts/hydrate.sh"
REMOTE_V="$(tr -d '[:space:]' < "$CORE/TEMPLATE_VERSION")"

PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; [[ $# -gt 1 ]] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

stamp_of() { sed -n 's/.*<!-- STANDARD:VERSION -->\(.*\)<!-- \/STANDARD:VERSION -->.*/\1/p' "$1" | head -n 1; }
set_stamp() {  # perl, not sed -i (BSD portability)
  V="$2" perl -pi -e 's|<!-- STANDARD:VERSION -->[^<]*<!-- /STANDARD:VERSION -->|<!-- STANDARD:VERSION -->$ENV{V}<!-- /STANDARD:VERSION -->|' "$1"
}

mk_project() {  # hydrated project, committed
  local d="$WORK/$1"
  mkdir -p "$d"
  ( cd "$d"
    git init -q . && git config user.email t@e && git config user.name t
    bash "$HYDRATE" init . >/dev/null 2>&1
    git add -A >/dev/null 2>&1 && git commit -qm seed >/dev/null 2>&1
  ) || { echo "mk_project $1 failed" >&2; exit 1; }
  printf '%s' "$d"
}

# mk_fake_slug <project> <slug> <command...> — plant an archived contract whose
# ## How to run is exactly the given command line.
mk_fake_slug() {
  local proj="$1" slug="$2"; shift 2
  local dir="$proj/scv/archive/$slug"
  mkdir -p "$dir"
  cat > "$dir/PLAN.md" <<EOF
---
title: $slug
slug: $slug
author: tester
created_at: 2026-08-19
status: done
kind: feature
lang: korean
---

# $slug
EOF
  cat > "$dir/TESTS.md" <<EOF
# Test Plan — $slug

## How to run

\`\`\`bash
$*
\`\`\`

## Pass criteria

- exit 0
EOF
}

# run_runner <project> [runner args...] — invoke the runner the way a user
# does, from the project dir, with this test's own env untouched.
run_runner() {
  local proj="$1"; shift
  ( cd "$proj" && bash "$RUNNER" "$@" </dev/null 2>&1 )
}

echo "=== T1 — a scenario never sees the runner's internal mark ==="
P="$(mk_project t1)"
mk_fake_slug "$P" "20260819-tester-env-probe" \
  '[[ -z "${SCV_AUTOSYNC_RUNNING:-}" ]]'
out="$(run_runner "$P")"
grep -q 'FAILED_SLUGS: 0' <<<"$out" && pass "T1 the scenario ran without SCV_AUTOSYNC_RUNNING" \
                                    || fail "T1 the runner's mark leaked into the scenario" "$out"

echo "=== T5 — the runner's path marks never reach a scenario (0.31.0) ==="
P="$(mk_project t5)"
mk_fake_slug "$P" "20260821-tester-path-probe" \
  '[[ -z "${SCV_DIR:-}${RAW_DIR:-}${STATE_FILE:-}${PROMOTE_DIR:-}${ARCHIVE_DIR:-}" ]]'
out="$(run_runner "$P")"
grep -q 'FAILED_SLUGS: 0' <<<"$out" && pass "T5 the scenario ran without SCV_DIR/RAW_DIR/STATE_FILE/PROMOTE_DIR/ARCHIVE_DIR" \
                                    || fail "T5 a runner path mark leaked into the scenario" "$out"

echo "=== T2 — the user's own environment still passes through ==="
P="$(mk_project t2)"
mk_fake_slug "$P" "20260819-tester-user-env" \
  '[[ "${USER_CANARY:-}" == "9f3a" && "${SCV_AUTOSYNC:-}" == "off" ]]'
out="$( cd "$P" && USER_CANARY=9f3a SCV_AUTOSYNC=off bash "$RUNNER" </dev/null 2>&1 )"
grep -q 'FAILED_SLUGS: 0' <<<"$out" && pass "T2 user-set variables reach the scenario untouched" \
                                    || fail "T2 the hygiene stripped more than the runner's own mark" "$out"

echo "=== T3 — the runner's own autosync converges once (re-entry guard intact) ==="
P="$(mk_project t3)"
mk_fake_slug "$P" "20260819-tester-benign" 'true'
set_stamp "$P/scv/SCV.md" "2.0.0"
( cd "$P" && git commit -qam stale )
out="$(run_runner "$P")"
n="$(grep -c 'refreshed 2.0.0' <<<"$out" || true)"
[[ "$n" == "1" ]] && pass "T3 first run reports exactly one refresh (no helper duplication)" \
                  || fail "T3 refresh reported $n times on the first run" "$out"
[[ "$(stamp_of "$P/scv/SCV.md")" == "$REMOTE_V" ]] && pass "T3 the stamp converged to the payload version" \
                                                   || fail "T3 the stamp did not converge"
out="$(run_runner "$P")"
grep -q 'refreshed' <<<"$out" && fail "T3 the second run refreshed again — no convergence" "$out" \
                              || pass "T3 the second run is a no-op"

echo "=== T4 — the real contract passes inside the runner: sync-autopilot ==="
REPO_ROOT="$(cd "$CORE/.." && pwd)"
if [[ -d "$REPO_ROOT/scv/archive/20260818-wookiya1364-sync-autopilot" ]]; then
  out="$( cd "$REPO_ROOT" && bash "$RUNNER" --only 20260818-wookiya1364-sync-autopilot --quiet </dev/null 2>&1 )"
  grep -q 'FAILED_SLUGS: 0' <<<"$out" && pass "T4 the sync-autopilot contract is green inside the runner" \
                                      || fail "T4 the contract still fails inside the runner" "$(tail -n 15 <<<"$out")"
else
  pass "T4 skipped — sync-autopilot archive not present in this checkout (wrapper projection)"
fi

echo "=== T5 — the --ci contract is unchanged ==="
P="$(mk_project t5a)"
mk_fake_slug "$P" "20260819-tester-ci-pass" 'true'
( cd "$P" && bash "$RUNNER" --ci </dev/null >/dev/null 2>&1 )
rc=$?
[[ $rc -eq 0 ]] && pass "T5 --ci with a passing suite exits 0, asking nothing" \
                || fail "T5 --ci pass fixture exited $rc"
P="$(mk_project t5b)"
mk_fake_slug "$P" "20260819-tester-ci-fail" 'false'
( cd "$P" && bash "$RUNNER" --ci </dev/null >/dev/null 2>&1 )
rc=$?
[[ $rc -eq 2 ]] && pass "T5 --ci with a failing suite exits 2, asking nothing" \
                || fail "T5 --ci fail fixture exited $rc (expected 2)"

echo "=== T6 — the suite and the library are untouched: standalone stays green ==="
out="$(env -u SCV_AUTOSYNC_RUNNING bash "$CORE/tests/test-autosync.sh" 2>&1 | tail -n 2)"
grep -q 'failed: 0' <<<"$out" && pass "T6 test-autosync.sh standalone is still 21/21" \
                              || fail "T6 the standalone suite broke" "$out"

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
