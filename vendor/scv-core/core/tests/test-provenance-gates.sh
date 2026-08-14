#!/usr/bin/env bash
# The two merge-time gates, exercised against real repositories.
#
# Both scripts decide whether a pull request may land, both are vendored into
# every wrapper, and until now neither had a test. Their failure mode is quiet in
# both directions: a gate that stopped denying looks exactly like a repository
# where nobody happens to be violating it, and a gate that started denying
# everything is discovered by whoever it blocks first.
#
# Fixtures are real git repositories rather than stubbed diffs, because what is
# being tested includes how the scripts read a diff — merge-base resolution and
# path shape — and a stub would assert my reading of git rather than git's.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROV="$ROOT/core/scripts/check-provenance.sh"
VEND="$ROOT/core/scripts/check-vendor-provenance.sh"

PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; [[ $# -gt 1 ]] && printf '%s\n' "$2" | sed 's/^/      /'; FAIL=$((FAIL+1)); }

for f in "$PROV" "$VEND"; do
  [[ -f "$f" ]] || { echo "missing $f" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e

# ---- fixture ---------------------------------------------------------------
# Builds a repo with one base commit and one branch commit that adds the given
# files, then returns the base sha. BASE_SHA is passed to the scripts directly:
# the origin/<ref> path needs a remote, and what these cases are about is the
# decision, not the lookup that finds the base.
# The name is an argument, not a counter. A counter cannot work here: every
# call is made inside a command substitution, which runs in a subshell, so the
# increment is discarded and each fixture silently reuses — and overwrites — the
# first one. That version reported eight healthy gates because the assertions
# were all reading whichever repository was built last.
mkrepo() {  # mkrepo <name> <file>... ; echoes the repo dir
  local d="$TMP/$1"; shift
  [[ -e "$d" ]] && { echo "fixture name reused: $d" >&2; return 1; }
  mkdir -p "$d"
  # The whole subshell is silenced. Its stdout is part of this function's return
  # value, so one chatty git command appends itself to the path — and the caller
  # then cd's into a directory whose name begins with a git message.
  #
  # -f on the add, and no user config: `vendor/` is a conventional gitignore
  # entry, and a fixture whose files were quietly not staged commits nothing,
  # produces an empty diff, and is allowed by a gate that is working perfectly.
  ( cd "$d"
    git init -q .
    git config user.email t@e; git config user.name t
    git config core.excludesFile /dev/null
    echo seed > seed.txt
    git add -A -f && git commit -qm base
    # The base sha is kept OUTSIDE the work tree. Written inside it, `git add -A`
    # sweeps it into the branch commit, and a file named .base is not prose — so
    # the provenance gate saw a code change in every docs-only fixture and denied
    # it correctly, for a file the fixture had invented.
    git rev-parse HEAD > "$d.base"
    for f in "$@"; do
      mkdir -p "$(dirname "$f")"
      # A plan is not an arbitrary file: the gate validates its frontmatter after
      # finding it, so a placeholder body fails the schema and reads as "no plan".
      case "$f" in
        *PLAN.md) printf -- '---\ntitle: A thing\nslug: a-thing\nauthor: t\ncreated_at: 2026-08-13\nstatus: done\ntags: [test]\n---\n\nbody\n' > "$f" ;;
        *)        echo "x" > "$f" ;;
      esac
    done
    git add -A -f && git commit -qm change
  ) >/dev/null 2>&1
  printf '%s' "$d"
}

run() {  # run <script> <repo> <base-ref> <head-ref> <title> ; echoes ALLOW|DENY
  local s="$1" d="$2"
  if ( cd "$d" && BASE_SHA="$(cat "$d.base")" BASE_REF="$3" HEAD_REF="$4" PR_TITLE="$5" \
       bash "$s" >/dev/null 2>&1 ); then echo ALLOW; else echo DENY; fi
}

check() {  # check <name> <expected> <script> <repo> <base> <head> <title>
  local got; got="$(run "$3" "$4" "$5" "$6" "$7")"
  [[ "$got" == "$2" ]] && pass "$1" || fail "$1" "expected $2, got $got"
}

# ============================================================================
#  check-vendor-provenance.sh
# ============================================================================
echo "  -- vendor gate --"

VEND_FLAT="$(mkrepo vendor-flat vendor/scv-core/core.lock.json vendor/scv-core/core/actions.json)"
# The nested layout: a wrapper that keeps its plugin payload one level down. The
# script matches on shape, so both must be caught by the same rule.
VEND_NEST="$(mkrepo vendor-nested plugins/scv/vendor/scv-core/core.lock.json)"
NO_VEND="$(mkrepo no-vendor src/app.ts README.md)"

# The regression. 0.26.0 was vendored by hand inside chore/release-0.26.0, which
# is not the bot's branch — the bot's own pull request then arrived redundant and
# was closed. This is that pull request.
check "[V1] hand-vendoring on a release branch is denied" DENY \
  "$VEND" "$VEND_FLAT" develop chore/release-0.26.0 "chore: release 0.26.0"
check "[V2] the same, nested one level down" DENY \
  "$VEND" "$VEND_NEST" develop chore/release-0.26.0 "chore: release 0.26.0"

check "[V3] the sync bot's own branch is exempt" ALLOW \
  "$VEND" "$VEND_FLAT" develop chore/core-v0.26.0 "chore(core): sync scv-core v0.26.0"
check "[V4] the release chain into stage is exempt" ALLOW \
  "$VEND" "$VEND_FLAT" stage develop "chore: promote develop → stage"
check "[V5] the release chain into main is exempt" ALLOW \
  "$VEND" "$VEND_FLAT" main stage "chore: promote stage → main"
check "[V6] a declared exception with a reason passes" ALLOW \
  "$VEND" "$VEND_FLAT" develop fix/x "fix: adapt to the new contract [manual-vendor: contract change the bot cannot resolve]"
check "[V7] a bare marker with no reason is denied" DENY \
  "$VEND" "$VEND_FLAT" develop fix/x "fix: something [manual-vendor]"
check "[V8] a pull request that leaves the vendor tree alone passes" ALLOW \
  "$VEND" "$NO_VEND" develop fix/x "fix: something"

# A path merely containing the word must not trigger it — the rule is a directory
# boundary, not a substring.
NEAR="$(mkrepo near-miss docs/vendor-scv-core-notes.md src/vendorer.ts)"
check "[V9] a similarly-named path outside the vendor tree passes" ALLOW \
  "$VEND" "$NEAR" develop fix/x "docs: notes"

# ============================================================================
#  check-provenance.sh — no test existed for this until now
# ============================================================================
echo "  -- provenance gate --"

CODE="$(mkrepo code-only src/app.ts)"
CODE_PLAN="$(mkrepo code-with-plan src/app.ts scv/archive/20260813-a-thing/PLAN.md)"
DOCS="$(mkrepo docs-only README.md docs/guide.md)"
PLAN_ONLY="$(mkrepo plan-only scv/promote/20260813-a-thing/PLAN.md)"

check "[P1] code with no archived plan is denied" DENY \
  "$PROV" "$CODE" develop feat/x "feat: add a thing"
check "[P2] code with an archived plan passes" ALLOW \
  "$PROV" "$CODE_PLAN" develop feat/x "feat: add a thing"
check "[P3] prose-only changes pass" ALLOW \
  "$PROV" "$DOCS" develop docs/x "docs: rewrite the guide"
check "[P4] changes confined to the workflow directory pass" ALLOW \
  "$PROV" "$PLAN_ONLY" develop feat/x "chore: draft a plan"
check "[P5] the release chain is exempt" ALLOW \
  "$PROV" "$CODE" stage develop "chore: promote develop → stage"
check "[P6] the sync bot's branch is exempt" ALLOW \
  "$PROV" "$CODE" develop chore/core-v0.26.0 "chore(core): sync"
check "[P7] a declared exception with a reason passes" ALLOW \
  "$PROV" "$CODE" develop fix/x "fix: one-line typo [no-plan: typo in a comment]"
check "[P8] a bare marker with no reason is denied" DENY \
  "$PROV" "$CODE" develop fix/x "fix: something [no-plan]"

# ---- the gates are actually running ---------------------------------------
# Without this, a script that exits 0 on line 1 passes every ALLOW case above and
# the suite reports a healthy gate that decides nothing.
denials=0
for c in "[V1]" "[V7]" "[P1]" "[P8]"; do denials=$((denials+1)); done
if (( denials == 4 )) && [[ "$(run "$VEND" "$VEND_FLAT" develop chore/release-x "t")" == DENY ]] \
   && [[ "$(run "$PROV" "$CODE" develop feat/x "t")" == DENY ]]; then
  pass "[X] both gates deny something — neither is a no-op"
else
  fail "[X] a gate allowed everything it was given"
fi

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
