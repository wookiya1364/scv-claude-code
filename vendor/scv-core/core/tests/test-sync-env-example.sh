#!/usr/bin/env bash
# Root .env.example.scv auto-refresh — the one named exception to "root is
# user-owned and never touched".
#
# hydrate lays this file down at the project root; without a sync path, a
# project hydrated before a new .env option shipped (SCV_EFFORT_MODE, v0.29.0)
# never learns the option exists. The exception rides the EXISTING machinery:
# overwrite policy, dirty refusal against HEAD, --force override, the
# symlinked-scv/ skip, and the stamp gate. These cases pin the exception down
# from both sides — the file must refresh, and nothing else at the root may.
#
# Sentinels are CANARY-*-9f3a tokens, per the self-trapping-test lesson in
# test-sync-dirty.sh: a sentinel must be a string the real content can never
# legitimately contain.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/sync.sh" ]]; then
      CORE="$(cd "$up/$sub" && pwd)"; break 2
    fi
  done
done
[[ -n "$CORE" ]] || { echo "test-sync-env-example: payload not found from $HERE" >&2; exit 1; }
SYNC="$CORE/scripts/sync.sh"
HYDRATE="$CORE/scripts/hydrate.sh"
TMPL="$CORE/template/.env.example.scv"
REMOTE_V="$(tr -d '[:space:]' < "$CORE/TEMPLATE_VERSION")"

# The file this suite is about. If the template stops shipping it, every case
# below tests nothing — fail loudly instead.
[[ -f "$TMPL" ]] || { echo "test-sync-env-example: template/.env.example.scv is gone — retarget this suite" >&2; exit 1; }
TARGET=".env.example.scv"

PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; [[ $# -gt 1 ]] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

stamp_of() { sed -n 's/.*<!-- STANDARD:VERSION -->\(.*\)<!-- \/STANDARD:VERSION -->.*/\1/p' "$1" | head -n 1; }
set_stamp() {  # set_stamp <SCV.md> <version> — perl, not sed -i (BSD portability)
  V="$2" perl -pi -e 's|<!-- STANDARD:VERSION -->[^<]*<!-- /STANDARD:VERSION -->|<!-- STANDARD:VERSION -->$ENV{V}<!-- /STANDARD:VERSION -->|' "$1"
}

mk_project() {  # mk_project <name> [nogit] — hydrated project, committed unless nogit
  local d="$WORK/$1"
  mkdir -p "$d"
  ( cd "$d"
    if [[ "${2:-}" != "nogit" ]]; then
      git init -q .
      git config user.email t@e; git config user.name t
    fi
    bash "$HYDRATE" init . >/dev/null 2>&1
    if [[ "${2:-}" != "nogit" ]]; then
      git add -A >/dev/null 2>&1 && git commit -qm seed >/dev/null 2>&1
    fi
  ) || { echo "mk_project $1 failed" >&2; exit 1; }
  printf '%s' "$d"
}

# call <project-dir> — invoke scv_autosync the way an action script does,
# capturing stderr (the hook's only reporting channel). Subshell per call so
# SCV_AUTOSYNC_RUNNING never leaks between cases.
call() {
  local d="$1"; shift
  ( cd "$d" && bash -c '
      set -uo pipefail
      source "'"$CORE"'/scripts/lib/scvroot.sh"
      scv_autosync "$(scv_root_dir)"
    ' ) 2>&1 >/dev/null
}

echo "=== T1 — a stale example file is replaced with the latest template ==="
P="$(mk_project t1)"
( cd "$P" && printf '# CANARY-ENVOLD-9f3a\n' > "$TARGET" && git commit -qam old )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
cmp -s "$TMPL" "$P/$TARGET" && pass "T1 the file is byte-identical to the template" \
                            || fail "T1 the stale file was not refreshed"
grep -q "OVERWRITE $TARGET" <<<"$out" && pass "T1 the refresh is reported" \
                                      || fail "T1 no OVERWRITE report" "$out"

echo "=== T2 — an uncommitted edit refuses by name, holds the stamp, reports PARTIAL ==="
P="$(mk_project t2)"
set_stamp "$P/scv/SCV.md" "2.0.0"
( cd "$P" && git commit -qam stale && printf '\n# CANARY-ENVDIRTY-9f3a\n' >> "$TARGET" )
err="$(call "$P")"
grep -q 'CANARY-ENVDIRTY-9f3a' "$P/$TARGET" && pass "T2 the dirty file was not touched" \
                                            || fail "T2 the dirty file was overwritten — work lost"
grep -q "DIRTY.*$TARGET" <<<"$err" && pass "T2 the refusal names the file" \
                                   || fail "T2 no DIRTY report for $TARGET" "$err"
grep -q "PARTIAL" <<<"$err" && pass "T2 autosync reports PARTIAL" \
                            || fail "T2 no PARTIAL report" "$err"
[[ "$(stamp_of "$P/scv/SCV.md")" == "2.0.0" ]] && pass "T2 the stamp did not advance past the refusal" \
                                               || fail "T2 the stamp advanced while $TARGET was refused"

echo "=== T3 — a committed custom copy is replaced (git holds the old content) ==="
P="$(mk_project t3)"
( cd "$P" && printf '\n# CANARY-ENVCUSTOM-9f3a\n' >> "$TARGET" && git commit -qam custom )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
cmp -s "$TMPL" "$P/$TARGET" && pass "T3 the committed custom copy was replaced" \
                            || fail "T3 a committed (restorable) custom copy was not refreshed"
( cd "$P" && git show "HEAD:$TARGET" | grep -q 'CANARY-ENVCUSTOM-9f3a' ) \
  && pass "T3 the old content is recoverable from git history" \
  || fail "T3 git history does not hold the old content"

echo "=== T4 — a missing file is recreated ==="
P="$(mk_project t4)"
( cd "$P" && git rm -q "$TARGET" && git commit -qm removed )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
[[ -f "$P/$TARGET" ]] && cmp -s "$TMPL" "$P/$TARGET" && pass "T4 the missing file is recreated from the template" \
                                                     || fail "T4 the missing file was not recreated"
grep -q "NEW       $TARGET" <<<"$out" && pass "T4 the creation is reported as NEW" \
                                      || fail "T4 no NEW report" "$out"
P="$(mk_project t4b nogit)"
rm -f "$P/$TARGET"
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
[[ -f "$P/$TARGET" ]] && pass "T4 recreation works outside a git work tree too" \
                      || fail "T4 no-git recreation failed"

echo "=== T5 — .env itself is never touched ==="
P="$(mk_project t5)"
printf 'SECRET_TOKEN=CANARY-ENVREAL-9f3a\n' > "$P/.env"
( cd "$P" && printf '# CANARY-ENVOLD-9f3a\n' > "$TARGET" && git commit -qam old )
before="$(cksum < "$P/.env")"
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
after="$(cksum < "$P/.env")"
[[ "$before" == "$after" ]] && pass "T5 .env is byte-identical after sync" \
                            || fail "T5 sync modified .env"
cmp -s "$TMPL" "$P/$TARGET" && pass "T5 the example file still refreshed alongside" \
                            || fail "T5 the refresh did not happen in the .env fixture"

echo "=== T6 — a symlinked scv/ skips the root file with the rest of the pass ==="
P="$WORK/t6"; mkdir -p "$P" "$WORK/shared-scv6"
( cd "$P" && git init -q . && git config user.email t@e && git config user.name t )
( cd "$WORK" && cp -R "$(dirname "$(mk_project t6seed)")/t6seed/scv/." "$WORK/shared-scv6/" )
printf '# CANARY-ENVLINKED-9f3a\n' > "$P/$TARGET"
ln -s "$WORK/shared-scv6" "$P/scv"
( cd "$P" && git add -A >/dev/null 2>&1 && git commit -qm seed >/dev/null 2>&1 )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
grep -q 'CANARY-ENVLINKED-9f3a' "$P/$TARGET" && pass "T6 the root file is untouched under a symlinked scv/" \
                                             || fail "T6 sync refreshed the root file despite the symlinked scv/"
grep -q "WARN.*symlinked directory" <<<"$out" && pass "T6 the skip is reported" \
                                              || fail "T6 no WARN for the symlinked scv/" "$out"

echo "=== T7 — no other root file is created or modified ==="
P="$(mk_project t7)"
printf 'user content\n' > "$P/user-notes.txt"
printf 'dot content\n' > "$P/.userrc"
( cd "$P" && printf '# CANARY-ENVOLD-9f3a\n' > "$TARGET" && git add -A && git commit -qam old )
snap() {  # root entries + checksums, minus the one file allowed to change
  ( cd "$1" && find . -maxdepth 1 \( -type f -o -type l \) ! -name "$TARGET" | sort | while read -r f; do
      printf '%s %s\n' "$f" "$(cksum < "$f")"
    done )
}
before="$(snap "$P")"
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
after="$(snap "$P")"
[[ "$before" == "$after" ]] && pass "T7 every other root entry is byte-identical" \
                            || fail "T7 sync touched a root file other than $TARGET" "$(diff <(echo "$before") <(echo "$after") || true)"
cmp -s "$TMPL" "$P/$TARGET" && pass "T7 the example file itself did refresh" \
                            || fail "T7 the refresh did not happen in the root fixture"

echo "=== T8 — --force overrides the dirty refusal ==="
P="$(mk_project t8)"
( cd "$P" && printf '\n# CANARY-ENVDIRTY-9f3a\n' >> "$TARGET" )
out="$(bash "$SYNC" --project-dir "$P" --force "$TARGET" 2>&1)"
cmp -s "$TMPL" "$P/$TARGET" && pass "T8 --force replaced the dirty file" \
                            || fail "T8 --force did not override the refusal" "$out"

echo "=== T9 — after the user commits, the retry converges and the stamp advances ==="
P="$(mk_project t9)"
set_stamp "$P/scv/SCV.md" "2.0.0"
( cd "$P" && git commit -qam stale && printf '\n# CANARY-ENVDIRTY-9f3a\n' >> "$TARGET" )
bash "$SYNC" --project-dir "$P" >/dev/null 2>&1
( cd "$P" && git commit -qam keep >/dev/null 2>&1 )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
cmp -s "$TMPL" "$P/$TARGET" && pass "T9 the retry replaced the now-committed file" \
                            || fail "T9 the retry did not refresh the file"
[[ "$(stamp_of "$P/scv/SCV.md")" == "$REMOTE_V" ]] && pass "T9 the stamp advanced once nothing was refused" \
                                                   || fail "T9 the stamp did not converge to $REMOTE_V"

echo "=== T10 — autosync gates: unadopted and pre-2.x projects are never touched ==="
P="$WORK/t10a"; mkdir -p "$P"
( cd "$P" && git init -q . && git config user.email t@e && git config user.name t )
printf '# CANARY-ENVOLD-9f3a\n' > "$P/$TARGET"
( cd "$P" && git add -A && git commit -qm seed )
err="$(call "$P")"
grep -q 'CANARY-ENVOLD-9f3a' "$P/$TARGET" && pass "T10 an unadopted project keeps its file" \
                                          || fail "T10 autosync touched an unadopted project"
P="$(mk_project t10b)"
( cd "$P" && rm scv/SCV.md && printf '# CANARY-ENVOLD-9f3a\n' > "$TARGET" && git add -A && git commit -qam legacy )
err="$(call "$P")"
grep -q 'CANARY-ENVOLD-9f3a' "$P/$TARGET" && pass "T10 a pre-2.x legacy keeps its file (pointer only)" \
                                          || fail "T10 autosync migrated a pre-2.x legacy"
grep -q "predate\|pre-2\|interactive migration" <<<"$err" && pass "T10 the legacy pointer message is shown" \
                                                          || fail "T10 no pointer message for the legacy" "$err"

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
