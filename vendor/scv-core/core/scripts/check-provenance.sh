#!/usr/bin/env bash
# Provenance gate — a pull request that changes code must carry the plan it came from.
#
# The guard hook and this check fail in opposite directions and neither replaces
# the other. The hook watches tool calls, so it catches a plan written by hand but
# never sees a write routed through a shell. This reads the resulting diff, so it
# catches whatever produced the change but only at merge time.
#
# It looks for plans ADDED by the pull request under scv/archive/, not under
# scv/promote/. The work action archives the plan before it opens the PR, so by
# the time this runs promote/ is empty — a check scoped there would have nothing
# to look at in exactly the pull requests it exists to inspect.
#
# Inputs (environment; a CI job supplies them):
#   BASE_REF   target branch name
#   HEAD_REF   source branch name
#   PR_TITLE   pull request title
#   BASE_SHA   optional; merge base to diff from (else derived from origin/BASE_REF)
#   SCV_PROVENANCE_EXEMPT  optional; colon-separated extra exempt path globs

set -uo pipefail

BASE_REF="${BASE_REF:-}"
HEAD_REF="${HEAD_REF:-}"
PR_TITLE="${PR_TITLE:-}"

note() { printf '%s\n' "$1"; }
pass() { note "$1"; exit 0; }
deny() { printf '::error::%s\n' "$1" >&2; printf '%s\n' "$1"; exit 1; }

# --- exemption 1: the release chain ----------------------------------------
# The promote workflow opens develop→stage and stage→main. Those carry no plan by
# definition. Blocking them stops every release, so this is checked first.
case "$BASE_REF" in
  stage|main) pass "provenance: release-chain pull request into ${BASE_REF} — exempt." ;;
esac

# --- exemption 2: the core-sync bot ----------------------------------------
case "$HEAD_REF" in
  chore/core-*) pass "provenance: automated Core sync branch ${HEAD_REF} — exempt." ;;
esac

# --- exemption 3: a declared exception, with a stated reason ----------------
# `[no-plan: reason]`. The bracket must hold text: requiring a reason is the whole
# point of the form, and an empty marker is not a declaration of anything.
if printf '%s' "$PR_TITLE" | grep -qE '\[no-plan:[[:space:]]*[^][:space:]][^]]*\]'; then
  reason="$(printf '%s' "$PR_TITLE" | sed -n 's/.*\[no-plan:[[:space:]]*\([^]]*\)\].*/\1/p')"
  pass "provenance: declared exception — ${reason}"
fi
if printf '%s' "$PR_TITLE" | grep -qE '\[no-plan[]:]'; then
  deny "This pull request carries a [no-plan] marker with no reason. Write it as [no-plan: why this change has no plan] — the reason is the point of the marker."
fi

# --- the diff ---------------------------------------------------------------
if [[ -n "${BASE_SHA:-}" ]]; then
  base="$BASE_SHA"
elif [[ -n "$BASE_REF" ]] && git rev-parse --verify --quiet "origin/$BASE_REF" >/dev/null; then
  base="$(git merge-base "origin/$BASE_REF" HEAD 2>/dev/null)"
fi
if [[ -z "${base:-}" ]]; then
  # Without a base there is nothing to compare. Say so and allow rather than
  # blocking every pull request on a shallow checkout.
  pass "provenance: no merge base available (shallow checkout?) — skipping."
fi

changed="$(git diff --name-only "$base"...HEAD 2>/dev/null)"
added="$(git diff --name-only --diff-filter=A "$base"...HEAD 2>/dev/null)"

# --- exemption 4: nothing but workflow files and prose ---------------------
# This list is the guard's exempt set. core/contracts/guard.md says the two must
# agree; if they drift the product states two definitions of "a code change".
is_exempt() {
  case "$1" in
    scv/*|*/scv/*) return 0 ;;
    *.md) return 0 ;;
    .gitignore|.gitattributes|LICENSE) return 0 ;;
    */.gitignore|*/.gitattributes|*/LICENSE) return 0 ;;
  esac
  local extra="${SCV_PROVENANCE_EXEMPT:-}"
  if [[ -n "$extra" ]]; then
    local IFS=':'
    for e in $extra; do
      [[ -n "$e" && "$1" == $e ]] && return 0
    done
  fi
  return 1
}

code_changed=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  is_exempt "$f" || { code_changed=1; break; }
done <<< "$changed"

[[ $code_changed -eq 1 ]] || pass "provenance: no code changed outside the workflow directory — exempt."

# --- the check --------------------------------------------------------------
plans="$(printf '%s\n' "$added" | grep -E '(^|/)scv/archive/[^/]+/PLAN\.md$' || true)"

if [[ -z "$plans" ]]; then
  deny "This pull request changes code but adds no archived plan.
Run the work action on a plan — it archives the plan and opens the PR with it —
or, if this change genuinely has no plan, put [no-plan: <reason>] in the title."
fi

# --- schema -----------------------------------------------------------------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CHECKER="$SCRIPT_DIR/check-frontmatter.sh"
violations=0
while IFS= read -r plan; do
  [[ -n "$plan" ]] || continue
  note "provenance: found $plan"
  if [[ -x "$CHECKER" || -f "$CHECKER" ]]; then
    bash "$CHECKER" --plan "$plan" || violations=$((violations + 1))
  fi
done <<< "$plans"

[[ $violations -eq 0 ]] || deny "The archived plan's frontmatter does not satisfy the PLAN schema (see above)."

pass "provenance: ok."
