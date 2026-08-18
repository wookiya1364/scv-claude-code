#!/usr/bin/env bash
# tests-smell.sh — TESTS.md quality heuristic lint (v0.11.0+).
#
# Static check that flags TESTS likely to be passable by cheat code:
# - low scenario diversity
# - low assertion density per scenario
# - type-only assertion concentration
#
# Used by /scv:codegen Step 6.1. Warn-only — never blocks codegen.
#
# Usage:
#   tests-smell.sh <path/to/TESTS.md>
#
# Output (stdout):
#   TESTS_SMELL: clean | warnings
#   scenarios: <N>
#   assertions: <M>
#   [warnings:]
#   [  - <warning line>]
#
# Exit code: 0 always (warn-only). Exit 1 only on missing arg / file.

set -uo pipefail

TESTS_FILE="${1:-}"
if [[ -z "$TESTS_FILE" || ! -f "$TESTS_FILE" ]]; then
  echo "ERROR: tests-smell.sh requires an existing TESTS.md path" >&2
  exit 1
fi

# Scenario headings — match common patterns at H2 (##) or H3 (###):
#   ## T1. ..., ### T1. ..., ## E2E-001 ..., ## U-1 ..., ## UT-1 ..., ## Scenario 1
# v0.11.1: H3 (###) added — PROMOTE.md TESTS.md template uses ### per scenario.
scenarios=$(grep -cE '^#{2,3}[[:space:]]+(T[0-9]+|E2E-[0-9]+|U-[0-9]+|UT-[0-9]+|Scenario[[:space:]]+[0-9]+)' "$TESTS_FILE" 2>/dev/null || true)

# Assertion-style keywords (JS/TS, Python, Go, Java/JUnit, RSpec)
assertions=$(grep -cE 'expect\(|assert[A-Z]|\.toBe\(|\.toEqual\(|\.toMatch\(|should[A-Z]|assertEquals|assertTrue|assertFalse|assertThat' "$TESTS_FILE" 2>/dev/null || true)

# Type-only assertions: typeof.*toBe or typeof.*===.*"string"
type_only=$(grep -cE 'typeof[^.=]*\.toBe|typeof[^=]+===?[[:space:]]*"[a-z]+"' "$TESTS_FILE" 2>/dev/null || true)

warnings=()

if (( scenarios < 2 )); then
  warnings+=("low scenario diversity: only $scenarios scenario heading(s) — consider adding more cases")
fi

if (( scenarios > 0 )) && (( assertions < scenarios * 2 )); then
  warnings+=("low assertion density: $assertions assertions across $scenarios scenarios — recommend 2+ per scenario")
fi

if (( assertions > 0 )) && (( type_only * 2 > assertions )); then
  warnings+=("type-heavy assertions: $type_only of $assertions assertions are typeof checks — codegen may pass with empty stubs")
fi

# Durability smells (v0.29.0+). A TESTS.md outlives its pull request: the
# regression action replays How-to-run from the archive forever. Two patterns
# read fine at implementation time and go permanently red the moment the work
# is committed — four archived plans went that way before anyone noticed.
#
# (1) Pre-commit state assertions: `git diff --name-only HEAD` scoping ("this
# edit only touched X") is only true in the uncommitted working tree.
git_diff_asserts=$(grep -cE 'git diff (--name-only |--stat )?HEAD' "$TESTS_FILE" 2>/dev/null || true)
if (( git_diff_asserts > 0 )); then
  warnings+=("pre-commit state assertion: $git_diff_asserts \`git diff ... HEAD\` check(s) — true only before the work is committed, permanently false once archived")
fi

# (2) Referenced scripts that do not exist. Heuristic: resolve each
# path-looking token ending in .sh against the repo root (walk up from the
# TESTS file until a directory holding core/ or a .git marker). One archived
# plan called a test file that was never created, and stayed red from day one.
_root="$(cd "$(dirname "$TESTS_FILE")" && pwd)"
while [[ -n "$_root" && "$_root" != "/" ]]; do
  if [[ -d "$_root/core" || -d "$_root/.git" || -d "$_root/vendor/scv-core" ]]; then break; fi
  _root="$(dirname "$_root")"
done
if [[ -n "$_root" && "$_root" != "/" ]]; then
  while IFS= read -r _ref; do
    [[ -n "$_ref" ]] || continue
    [[ -f "$_root/$_ref" ]] || warnings+=("missing script reference: $_ref does not exist under $_root — an archived How-to-run would fail on it forever")
  done < <(grep -oE '(core|tests|scripts)/[A-Za-z0-9._/-]+\.sh' "$TESTS_FILE" 2>/dev/null | sort -u)
fi

if [[ ${#warnings[@]} -eq 0 ]]; then
  echo "TESTS_SMELL: clean"
else
  echo "TESTS_SMELL: warnings"
fi
echo "scenarios: $scenarios"
echo "assertions: $assertions"

if [[ ${#warnings[@]} -gt 0 ]]; then
  echo "warnings:"
  for w in "${warnings[@]}"; do
    echo "  - $w"
  done
fi

exit 0
