#!/usr/bin/env bash
# effort-class.sh — judge how much execution weight a plan needs, deterministically.
#
# Usage: effort-class.sh <plan-dir | PLAN.md path>
#
# Output (stdout, one value per line):
#   EFFORT_CLASS: standard | heavy | orchestration
#   EFFORT_REASON: <one line naming exactly the rule that fired>
#   EFFORT_ESCALATION: armed | normal
#
# Read-only: judges, never writes. Exit 0 on a judgment; exit 1 only when the
# input is missing.
#
# The rules are the survivors of a backtest against every archived plan in
# this repository (14 plans, 13 hits). Rules that sounded plausible and were
# REFUTED by that data are deliberately absent: scenario counts (0-scenario
# plans went heavy four times while a 21-scenario plan stayed standard),
# guardrail counts (anti-correlated), and any predicted "light" band (zero
# examples exist — an invented threshold would miss in the expensive
# direction). Keep it that way: a new signal earns its place by re-running the
# backtest, not by sounding reasonable.
#
#   R0  frontmatter `effort_class:` declared      -> that value (user override)
#   R1  frontmatter `parallel_groups:` declared   -> orchestration
#   R2  the plan speaks of wrapper follow-ups     -> heavy
#   R3  otherwise                                 -> standard
#
# R2 greps the WHOLE plan on purpose. A section-scoped variant (only
# Goals/path/Exit) scored the same 13/14 on the backtest but its one miss was
# UNDER-provisioned; the whole-file grep's one miss is a plan that merely
# discusses wrappers in its guardrails and reads as heavy — bounded waste,
# never a quality risk. When the asymmetry is the tie-breaker, the cheap miss
# wins. The known over-read has an escape hatch: declare `effort_class:`.
#
# Escalation pre-arming: two or more of {wrapper follow-up, adversarial or
# mutation verification demanded, raw material >= 9000 bytes} arms one-step
# auto-promotion for the executing protocol. This is a hint, not a band: the
# single backtest miss (a heavy that turned out to need fan-out verification)
# carried all three markers, but the raw-size cut sits 1,140 bytes from its
# nearest neighbor — a single-point fit that may hint, and must not classify.

set -uo pipefail

IN="${1:-}"
[[ -n "$IN" ]] || { echo "usage: effort-class.sh <plan-dir | PLAN.md>" >&2; exit 1; }

if [[ -d "$IN" ]]; then
  PLAN="$IN/PLAN.md"
  DIR="$IN"
else
  PLAN="$IN"
  DIR="$(dirname "$IN")"
fi
[[ -f "$PLAN" ]] || { echo "effort-class: no PLAN.md at $PLAN" >&2; exit 1; }
TESTS="$DIR/TESTS.md"

# The frontmatter is the first --- ... --- block; signals declared there must
# not be confused with the template's commented-out examples (# parallel_groups:).
# tr strips CR first: a CRLF plan otherwise hides every frontmatter signal —
# and a hidden parallel_groups is an under-provision, the expensive direction.
frontmatter() { tr -d '\r' < "$PLAN" | awk '/^---$/{n++; next} n==1{print} n>=2{exit}'; }

# ---- R0: an explicit declaration always wins ---------------------------------
# Three separate expressions, not one alternation: BSD sed has no \| in a
# basic regex — the exact platform split that once put both guard rules to
# sleep on one OS while the other stayed green, and this repository has now
# stepped in twice.
declared="$(frontmatter | sed -n \
  -e 's/^effort_class:[[:space:]]*\(standard\)[[:space:]]*$/\1/p' \
  -e 's/^effort_class:[[:space:]]*\(heavy\)[[:space:]]*$/\1/p' \
  -e 's/^effort_class:[[:space:]]*\(orchestration\)[[:space:]]*$/\1/p' | head -n 1)"
# A declaration that does not parse is a user intent this script cannot honor —
# swallowing it silently would read as the override having worked. Say so once.
declared_any="$(frontmatter | sed -n 's/^effort_class:[[:space:]]*\(.*\)$/\1/p' | head -n 1)"
if [[ -n "$declared_any" && -z "$declared" ]]; then
  echo "effort-class: ignoring invalid effort_class "$declared_any" — valid values are standard|heavy|orchestration (case-sensitive)" >&2
fi

# ---- signals ------------------------------------------------------------------
has_parallel=0
frontmatter | grep -qE '^parallel_groups:' && has_parallel=1

cross_repo=0
grep -qiE 'wrapper|래퍼' "$PLAN" && cross_repo=1

adversarial=0
if grep -qiE 'adversarial|적대|mutation|변이' "$PLAN" 2>/dev/null \
   || { [[ -f "$TESTS" ]] && grep -qiE 'adversarial|적대|mutation|변이' "$TESTS" 2>/dev/null; }; then
  adversarial=1
fi

# raw_sources sizes: paths are repository-relative; the plan folder sits at
# <root>/scv/{promote|archive}/<slug>, so the root is three levels up. A file
# that is not there counts zero — absence must never fail the judgment.
ROOT="$(cd "$DIR/../../.." 2>/dev/null && pwd || true)"
raw_bytes=0
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  # The size is only a hint, so a path that steps outside the repository is
  # simply not counted — no "../" resolution, ever. Without this, a crafted
  # raw_sources entry sizes arbitrary files through scv/raw/../.. (proven in
  # review with a 20KB file outside the tree).
  case "/$rel/" in */../*) continue ;; esac
  f="$ROOT/$rel"
  if [[ -n "$ROOT" && -f "$f" ]]; then
    sz=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    raw_bytes=$(( raw_bytes + ${sz:-0} ))
  fi
done < <(frontmatter | sed -n 's/^[[:space:]]*-[[:space:]]*\(scv\/raw\/[^[:space:]]*\)$/\1/p')

# ---- band ----------------------------------------------------------------------
if [[ -n "$declared" ]]; then
  cls="$declared"
  reason="declared effort_class: $declared in frontmatter — the declaration always wins"
elif [[ $has_parallel -eq 1 ]]; then
  cls="orchestration"
  reason="parallel_groups declared — independent surfaces contracted to run and verify in parallel"
elif [[ $cross_repo -eq 1 ]]; then
  cls="heavy"
  reason="the plan speaks of wrapper follow-ups — the change ships beyond this repository"
else
  cls="standard"
  reason="no parallel surfaces and no wrapper follow-up — a single-plan implementation"
fi

# ---- escalation hint ------------------------------------------------------------
markers=$(( cross_repo + adversarial + (raw_bytes >= 9000 ? 1 : 0) ))
if [[ $markers -ge 2 ]]; then
  esc="armed"
else
  esc="normal"
fi

printf 'EFFORT_CLASS: %s\n' "$cls"
printf 'EFFORT_REASON: %s\n' "$reason"
printf 'EFFORT_ESCALATION: %s\n' "$esc"
