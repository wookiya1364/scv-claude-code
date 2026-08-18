#!/usr/bin/env bash
# scv_autosync — the hook that closes a template-version gap on action start.
#
# The behavior under test is mostly about NOT running: never on a project that
# has not adopted SCV, never on a pre-2.x legacy (its migration deletes user
# docs after a conversation the hook must not skip), never re-entrantly, and
# never fatally. The one time it does run, it must converge in a single pass —
# an autosync that fires on every action is a different bug wearing the
# feature's name.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/scvroot.sh" ]]; then
      CORE="$(cd "$up/$sub" && pwd)"; break 2
    fi
  done
done
[[ -n "$CORE" ]] || { echo "test-autosync: payload not found from $HERE" >&2; exit 1; }
REMOTE_V="$(tr -d '[:space:]' < "$CORE/TEMPLATE_VERSION")"

PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; [[ $# -gt 1 ]] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

stamp_of() { sed -n 's/.*<!-- STANDARD:VERSION -->\(.*\)<!-- \/STANDARD:VERSION -->.*/\1/p' "$1" | head -n 1; }
set_stamp() {  # set_stamp <SCV.md> <version>
  # perl -pi, not sed -i: BSD sed reads the expression as a backup suffix and
  # dies with "invalid command code" — which took 12 of these cases down on
  # macOS while Linux stayed green, the exact platform split this repo keeps
  # relearning. run-dry.sh already standardized on perl for in-place edits.
  V="$2" perl -pi -e 's|<!-- STANDARD:VERSION -->[^<]*<!-- /STANDARD:VERSION -->|<!-- STANDARD:VERSION -->$ENV{V}<!-- /STANDARD:VERSION -->|' "$1"
}

mk_project() {  # hydrated, committed
  local d="$WORK/$1"
  mkdir -p "$d"
  ( cd "$d"
    git init -q . && git config user.email t@e && git config user.name t
    bash "$CORE/scripts/hydrate.sh" init . >/dev/null 2>&1
    git add -A && git commit -qm seed
  ) || { echo "mk_project $1 failed" >&2; exit 1; }
  printf '%s' "$d"
}

# call <project-dir> [env...] — source the lib and invoke the hook the way an
# action script does, capturing stderr (the hook's only reporting channel).
call() {
  local d="$1"; shift
  ( cd "$d" && env "$@" bash -c '
      set -uo pipefail
      source "'"$CORE"'/scripts/lib/scvroot.sh"
      scv_autosync "$(scv_root_dir)"
    ' ) 2>&1 >/dev/null
}

echo "=== T4 — a stale stamp is closed once, then never again ==="
P="$(mk_project conv)"
set_stamp "$P/scv/SCV.md" "2.0.0"
( cd "$P" && git commit -qam stale )
err="$(call "$P")"
grep -q "refreshed 2.0.0 → $REMOTE_V" <<<"$err" && pass "T4 the gap is reported and closed" \
                                                || fail "T4 no refresh happened" "$err"
[[ "$(stamp_of "$P/scv/SCV.md")" == "$REMOTE_V" ]] && pass "T4 the stamp now matches the payload" \
                                                   || fail "T4 the stamp did not converge"
err="$(call "$P")"
grep -q "refreshed" <<<"$err" && fail "T4 a second call refreshed again — no convergence" "$err" \
                              || pass "T4 the second call is a no-op"

echo "=== T4b — a partial refresh is honest: stamp holds, report says PARTIAL, retry converges ==="
P="$(mk_project dirty)"
set_stamp "$P/scv/SCV.md" "2.0.0"
( cd "$P" && git commit -qam stale && printf '\nlocal note\n' >> scv/PROMOTE.md )
err="$(call "$P")"
grep -q 'local note' "$P/scv/PROMOTE.md" && pass "T4b the uncommitted edit survived" \
                                         || fail "T4b autosync destroyed an uncommitted edit"
grep -q "DIRTY.*PROMOTE.md" <<<"$err" && pass "T4b the skipped file is surfaced on stderr" \
                                      || fail "T4b the refusal was hidden" "$err"
grep -q "PARTIAL" <<<"$err" && pass "T4b the report says PARTIAL, not refreshed" \
                            || fail "T4b a refused run was reported as a full refresh" "$err"
[[ "$(stamp_of "$P/scv/SCV.md")" == "2.0.0" ]] && pass "T4b the stamp did not advance past the refusal" \
                                               || fail "T4b the stamp advanced — the refusal would never be retried"
err="$(call "$P")"
grep -q "PARTIAL\|DIRTY" <<<"$err" && pass "T4b the next action retries instead of going silent" \
                                    || fail "T4b the refusal went silent on the second action" "$err"
( cd "$P" && git commit -qam keep >/dev/null 2>&1 )
err="$(call "$P")"
[[ "$(stamp_of "$P/scv/SCV.md")" == "$REMOTE_V" ]] && pass "T4b after the user commits, the retry converges" \
                                                   || fail "T4b no convergence after the dirt was committed"

echo "=== T5 — the four cases where it must not run ==="
D="$WORK/unadopted"; mkdir -p "$D/scv"
err="$(call "$D")"
[[ -z "$(ls -A "$D/scv")" ]] && pass "T5 an unadopted project is untouched (no auto-hydrate)" \
                             || fail "T5 autosync populated an empty scv/"

D="$WORK/legacy"; mkdir -p "$D/scv"
printf '# promote convention\n' > "$D/scv/PROMOTE.md"
err="$(call "$D")"
[[ ! -f "$D/scv/SCV.md" ]] && pass "T5 a pre-2.x legacy is not auto-migrated" \
                           || fail "T5 autosync migrated a legacy project without the conversation"
grep -qi "predate\|migration" <<<"$err" && pass "T5 the legacy project gets a pointer line" \
                                        || fail "T5 no pointer for the legacy project" "$err"

P="$(mk_project optout)"
set_stamp "$P/scv/SCV.md" "2.0.0"; ( cd "$P" && git commit -qam stale )
err="$(call "$P" SCV_AUTOSYNC=off)"
[[ "$(stamp_of "$P/scv/SCV.md")" == "2.0.0" ]] && pass "T5 SCV_AUTOSYNC=off is honored" \
                                               || fail "T5 the opt-out was ignored"
err="$(call "$P" SCV_AUTOSYNC_RUNNING=1)"
[[ "$(stamp_of "$P/scv/SCV.md")" == "2.0.0" ]] && pass "T5 the recursion guard is honored" \
                                               || fail "T5 re-entry ran anyway"

echo "=== T5e — a NEWER project stamp is never refreshed backward ==="
# A teammate updates the plugin first; this session still holds the old
# payload. Refreshing "to" the old version would have two machines silently
# reverting each other's templates forever. Caught in the field by a fixture
# stamped 9.9.9 that came back 2.1.0.
P="$(mk_project newer)"
set_stamp "$P/scv/SCV.md" "999.0.0"
( cd "$P" && git commit -qam future )
err="$(call "$P")"
[[ "$(stamp_of "$P/scv/SCV.md")" == "999.0.0" ]] && pass "T5e a newer stamp is left alone" \
                                                 || fail "T5e the project was downgraded to the payload's template"
grep -q "newer than this payload" <<<"$err" && pass "T5e the mismatch is reported, not hidden" \
                                            || fail "T5e no notice about the newer stamp" "$err"

echo "=== T6 — a failed refresh warns and lets the action continue ==="
P="$(mk_project broken)"
set_stamp "$P/scv/SCV.md" "2.0.0"; ( cd "$P" && git commit -qam stale )
chmod 555 "$P/scv"
rc=0; err="$(call "$P")" || rc=$?
chmod 755 "$P/scv"
[[ $rc -eq 0 ]] && pass "T6 the hook exits 0 when sync fails" \
                || fail "T6 a failed refresh broke the caller (rc=$rc)"
grep -q "failed" <<<"$err" && pass "T6 the failure is warned, not swallowed" \
                           || fail "T6 no warning on failure" "$err"

echo "=== T7 — workflow contents are never touched ==="
P="$(mk_project contents)"
mkdir -p "$P/scv/raw" "$P/scv/promote/x" "$P/scv/archive/y" "$P/scv/conversations"
printf 'raw material\n'   > "$P/scv/raw/a.md"
printf 'a plan\n'         > "$P/scv/promote/x/PLAN.md"
printf 'an archive\n'     > "$P/scv/archive/y/PLAN.md"
printf 'a conversation\n' > "$P/scv/conversations/c.md"
set_stamp "$P/scv/SCV.md" "2.0.0"
( cd "$P" && git add -A && git commit -qam stale )
# cksum, not md5sum: macOS has no md5sum, and with it missing BOTH sides of
# this comparison became the same xargs error — a false pass that read as
# "byte-identical" while checking nothing.
before="$(cd "$P" && find scv/raw scv/promote scv/archive scv/conversations -type f | sort | xargs cksum)"
call "$P" >/dev/null
after="$(cd "$P" && find scv/raw scv/promote scv/archive scv/conversations -type f | sort | xargs cksum)"
[[ "$before" == "$after" ]] && pass "T7 raw/promote/archive/conversations are byte-identical" \
                            || fail "T7 the automatic refresh modified workflow contents"

echo "=== T8 — an action script carries the hook end to end ==="
# Not just the lib in isolation: status.sh goes through scv_init_paths, so a
# stale project must come back fresh from one ordinary action run.
P="$(mk_project via-action)"
set_stamp "$P/scv/SCV.md" "2.0.0"; ( cd "$P" && git commit -qam stale )
( cd "$P" && bash "$CORE/scripts/status.sh" >/dev/null 2>"$WORK/action-err" ); rc=$?
[[ $rc -eq 0 ]] || fail "T8 status.sh failed (rc=$rc)" "$(cat "$WORK/action-err")"
[[ "$(stamp_of "$P/scv/SCV.md")" == "$REMOTE_V" ]] && pass "T8 one ordinary action closed the gap" \
                                                   || fail "T8 the action did not trigger the refresh"
# status.sh spawns readpath.sh several times, and each helper sources this
# library. The process-tree guard must collapse that to ONE check and ONE
# report — N reports per action was the cost bug the review measured.
n="$(grep -c 'scv: workflow docs refreshed' "$WORK/action-err" || true)"
[[ "$n" == "1" ]] && pass "T8 the refresh is checked and reported once per action" \
                  || fail "T8 the action produced $n refresh reports — the process-tree guard leaks"

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
