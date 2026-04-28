#!/usr/bin/env bash
# Validate frontmatter of all SCV docs in a project directory.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"

PROJECT_DIR="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: check-frontmatter.sh [--project-dir PATH]"; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

REQUIRED_KEYS=(name version status last_updated standard_version merge_policy)
# N/A is valid: adoption-mode hydrate seeds standard docs as N/A so
# the promote/work loop can run without enforcing full INTAKE.
# planned/in_progress/testing/done/obsolete are PLAN.md states (see PROMOTE.md §9).
# obsolete marks a plan that has been superseded and is skipped by /scv:regression.
VALID_STATUS="draft active deprecated N/A planned in_progress testing done obsolete"
VALID_POLICY="overwrite preserve merge-on-markers"
VIOLATIONS=0

check_file() {
  local file="$1"
  local rel="${file#$PROJECT_DIR/}"

  # Frontmatter must exist
  if ! grep -q "^---" "$file"; then
    echo "✖ $rel: no frontmatter"
    VIOLATIONS=$((VIOLATIONS + 1))
    return
  fi

  for key in "${REQUIRED_KEYS[@]}"; do
    if ! yaml_has_key "$file" "$key"; then
      echo "✖ $rel: missing required key '$key'"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done

  local status policy
  status=$(yaml_get "$file" "status")
  policy=$(yaml_get "$file" "merge_policy")

  # Use space-padded exact match so values with "/" (e.g. N/A) work correctly
  if [[ -n "$status" ]] && ! printf ' %s ' "$VALID_STATUS" | grep -qF " $status "; then
    echo "✖ $rel: invalid status '$status' (expected: $VALID_STATUS)"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
  if [[ -n "$policy" ]] && ! echo "$VALID_POLICY" | grep -qw "$policy"; then
    echo "✖ $rel: invalid merge_policy '$policy' (expected: $VALID_POLICY)"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
}

STANDARD_DOCS=(INTAKE PROMOTE ARCHITECTURE DESIGN DOMAIN AGENTS TESTING REPORTING RALPH_PROMPT)
for doc in "${STANDARD_DOCS[@]}"; do
  f="$PROJECT_DIR/scv/$doc.md"
  [[ -f "$f" ]] && check_file "$f"
done

shopt -s nullglob
for f in "$PROJECT_DIR/scv/promote"/*.md; do
  check_file "$f"
done
for f in "$PROJECT_DIR/scv/promote"/*/PLAN.md; do
  check_file "$f"
done
for f in "$PROJECT_DIR/scv/promote"/*/index.md; do
  check_file "$f"
done
shopt -u nullglob

if [[ $VIOLATIONS -gt 0 ]]; then
  echo ""
  echo "→ $VIOLATIONS violation(s) found"
  exit 1
fi

echo "✓ All frontmatter valid"
