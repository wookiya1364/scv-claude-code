#!/usr/bin/env bash
# env-set.sh — one KEY=VALUE in .env, every other line untouched.
#
# The cases here are not arbitrary. lib/env.sh:9-11 documents that a real .env may
# hold `${VAR}` references and $-containing secrets, and the recipe this script
# replaces (core/template/.env.example.scv, removed) used sed — which rewrites a
# value containing `&`, `/` or a backslash. Those are the regressions worth pinning.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_SET="$ROOT/core/scripts/env-set.sh"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; printf '      expected |%s|\n      got      |%s|\n' "${3-}" "${2-}"; FAIL=$((FAIL + 1)); }
eq() { [[ "$2" == "$3" ]] && pass "$1" || fail "$1" "$2" "$3"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "=== [1] create / append / replace ==="

P="$WORK/a"; mkdir -p "$P"
bash "$ENV_SET" SCV_LANG=korean --project-dir "$P" >/dev/null
eq "absent file is created" "$(cat "$P/.env")" "SCV_LANG=korean"

bash "$ENV_SET" SCV_PROMOTE_LANG=japanese --project-dir "$P" >/dev/null
eq "a new key appends" "$(cat "$P/.env")" "SCV_LANG=korean
SCV_PROMOTE_LANG=japanese"

bash "$ENV_SET" SCV_LANG=english --project-dir "$P" >/dev/null
eq "an existing key is replaced in place" "$(cat "$P/.env")" "SCV_LANG=english
SCV_PROMOTE_LANG=japanese"

echo "=== [2] unrelated lines survive byte for byte ==="

P="$WORK/b"; mkdir -p "$P"
printf '%s\n' \
  'DATABASE_URL=postgres://u:p@h/db?x=${DB_NAME}' \
  'NOTE=hello world  two  spaces' \
  '# a comment' \
  '' \
  'SCV_LANG=korean' > "$P/.env"
BEFORE="$(sed -n '1,4p' "$P/.env")"
bash "$ENV_SET" SCV_LANG=french --project-dir "$P" >/dev/null
eq "\${} reference, doubled spaces, comment and blank line preserved" \
  "$(sed -n '1,4p' "$P/.env")" "$BEFORE"
eq "only the target key changed" "$(sed -n '5p' "$P/.env")" "SCV_LANG=french"

echo "=== [3] values sed would have mangled ==="

P="$WORK/c"; mkdir -p "$P"
for value in 'a&b/c\d' 'x  y' '$HOME/literal' 'has=an=equals' '' ; do
  bash "$ENV_SET" "TRICKY=$value" --project-dir "$P" >/dev/null
  eq "round-trips |$value|" "$(bash "$ENV_SET" --get TRICKY --project-dir "$P")" "$value"
done

echo "=== [4] --get and --unset ==="

P="$WORK/d"; mkdir -p "$P"
eq "--get on a missing file is empty, exit 0" "$(bash "$ENV_SET" --get NOPE --project-dir "$P")" ""
bash "$ENV_SET" A=1 --project-dir "$P" >/dev/null
bash "$ENV_SET" B=2 --project-dir "$P" >/dev/null
bash "$ENV_SET" --unset A --project-dir "$P" >/dev/null
eq "--unset removes only its key" "$(cat "$P/.env")" "B=2"
bash "$ENV_SET" --unset MISSING --project-dir "$P" >/dev/null 2>&1
eq "--unset of an absent key is a no-op" "$(cat "$P/.env")" "B=2"

# A key repeated in a user's file: `source` keeps the LAST assignment, but the
# guard rail that matters here is that we never silently drop a line the user can
# still see. Replace the first, leave the rest — the file stays readable.
P="$WORK/e"; mkdir -p "$P"
printf '%s\n' 'K=one' 'OTHER=x' 'K=two' > "$P/.env"
bash "$ENV_SET" K=three --project-dir "$P" >/dev/null
eq "a duplicated key replaces the first occurrence only" "$(cat "$P/.env")" "K=three
OTHER=x
K=two"

echo "=== [5] rejects bad input ==="

P="$WORK/f"; mkdir -p "$P"
bash "$ENV_SET" "BAD KEY=1" --project-dir "$P" >/dev/null 2>&1 \
  && fail "a key with a space must be rejected" || pass "a key with a space is rejected"
bash "$ENV_SET" "9LEADING=1" --project-dir "$P" >/dev/null 2>&1 \
  && fail "a key starting with a digit must be rejected" || pass "a key starting with a digit is rejected"
bash "$ENV_SET" "NOEQUALS" --project-dir "$P" >/dev/null 2>&1 \
  && fail "an argument without = must be rejected" || pass "an argument without = is rejected"
bash "$ENV_SET" --project-dir "$WORK/does-not-exist" A=1 >/dev/null 2>&1 \
  && fail "a missing project dir must be rejected" || pass "a missing project dir is rejected"

echo "=== [6] hygiene: mode preserved, no temp litter ==="

P="$WORK/g"; mkdir -p "$P"
bash "$ENV_SET" A=1 --project-dir "$P" >/dev/null
chmod 600 "$P/.env"
bash "$ENV_SET" A=2 --project-dir "$P" >/dev/null
MODE="$(stat -c '%a' "$P/.env" 2>/dev/null || stat -f '%Lp' "$P/.env" 2>/dev/null)"
eq "0600 survives a rewrite" "$MODE" "600"
eq "no temp files left beside .env" "$(find "$P" -name '.env.*' | wc -l | tr -d ' ')" "0"

# The whole point of this script is that the write goes through Bash, so a guard
# scoped to Write/Edit never sees it. If someone later reimplements it as an
# in-place edit the ordering hole at the top of help.md reopens silently.
#
# Strip comments before looking: env-set.sh's own header explains why it avoids
# `sed -i`, and a naive grep matches that sentence and fails on the fix itself.
if sed 's/#.*//' "$ENV_SET" | grep -q 'sed -i'; then
  fail "env-set.sh must not use sed -i (BSD/GNU incompatible)"
else
  pass "no sed -i outside comments"
fi

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
