#!/usr/bin/env bash
# Validate frontmatter of all SCV docs in a project directory.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"

PROJECT_DIR="."
SINGLE_PLAN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    # Check one file against the PLAN schema. The provenance gate uses this so
    # the schema lives here only — a second implementation would drift from this
    # one and the two would disagree about what a valid plan is.
    --plan)        SINGLE_PLAN="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: check-frontmatter.sh [--project-dir PATH] [--plan FILE]"; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Two schemas, because two kinds of file live under scv/.
#
# Workflow docs (PROMOTE.md / REPORTING.md) are shipped templates and carry the
# standard-doc header. Promotion plans carry the PLAN schema declared in
# scv/PROMOTE.md §4 — a completely different key set. This script used to apply
# the standard-doc keys to plans too, which meant every plan an author wrote
# from the documented template failed the check. Nothing caught it because the
# only callers are tests whose fixtures were hand-built with the standard-doc
# keys instead of the PLAN template.
STANDARD_DOC_KEYS=(name version status last_updated standard_version merge_policy)
PLAN_KEYS=(title slug author created_at status tags)
# Status vocabularies are per-schema too. A merged list would let a plan claim
# `status: draft` and a workflow doc claim `status: testing` — the two lifecycles
# have nothing in common. PLAN states are PROMOTE.md §9; N/A stays valid for
# workflow docs because scv/REPORTING.md seeds that way.
STANDARD_DOC_STATUS="draft active deprecated N/A"
PLAN_STATUS="planned in_progress testing done obsolete"
VALID_POLICY="overwrite preserve merge-on-markers"
# PLAN.md frontmatter `kind` (optional; defaults to feature when absent).
# See PROMOTE.md §8d/§8e for epic/refactor flow, §8c for retirement.
VALID_KIND="feature refactor retirement"
VIOLATIONS=0

check_file() {
  local file="$1"
  local schema="${2:-standard-doc}"
  local rel="${file#$PROJECT_DIR/}"
  local -a required

  local valid_status
  case "$schema" in
    plan) required=("${PLAN_KEYS[@]}");         valid_status="$PLAN_STATUS" ;;
    *)    required=("${STANDARD_DOC_KEYS[@]}"); valid_status="$STANDARD_DOC_STATUS" ;;
  esac

  # Frontmatter must exist
  if ! grep -q "^---" "$file"; then
    echo "✖ $rel: no frontmatter"
    VIOLATIONS=$((VIOLATIONS + 1))
    return
  fi

  for key in "${required[@]}"; do
    if ! yaml_has_key "$file" "$key"; then
      echo "✖ $rel: missing required key '$key'"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done

  local status policy kind
  status=$(yaml_get "$file" "status")
  policy=$(yaml_get "$file" "merge_policy")
  kind=$(yaml_get "$file" "kind")

  # Use space-padded exact match so values with "/" (e.g. N/A) work correctly
  if [[ -n "$status" ]] && ! printf ' %s ' "$valid_status" | grep -qF " $status "; then
    echo "✖ $rel: invalid status '$status' (expected: $valid_status)"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
  if [[ -n "$policy" ]] && ! echo "$VALID_POLICY" | grep -qw "$policy"; then
    echo "✖ $rel: invalid merge_policy '$policy' (expected: $VALID_POLICY)"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
  # kind is optional; only validate when present (PLAN.md frontmatter only)
  if [[ -n "$kind" ]] && ! echo "$VALID_KIND" | grep -qw "$kind"; then
    echo "✖ $rel: invalid kind '$kind' (expected: $VALID_KIND)"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
}

if [[ -n "$SINGLE_PLAN" ]]; then
  if [[ ! -f "$SINGLE_PLAN" ]]; then
    echo "✖ $SINGLE_PLAN: no such file"
    exit 1
  fi
  PROJECT_DIR="$(dirname "$SINGLE_PLAN")"
  check_file "$SINGLE_PLAN" plan
  if [[ $VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "→ $VIOLATIONS violation(s) found"
    exit 1
  fi
  echo "✓ $SINGLE_PLAN: frontmatter valid"
  exit 0
fi

# Workflow docs SCV still ships (TEMPLATE_VERSION 2.0.0 dropped the
# standard-doc scaffolding; only these remain frontmatter-checked).
for doc in PROMOTE REPORTING; do
  f="$PROJECT_DIR/scv/$doc.md"
  [[ -f "$f" ]] && check_file "$f"
done

# Only the documented plan form is linted. scv/PROMOTE.md §3 defines a promotion
# as a folder holding PLAN.md; flat scv/promote/*.md and */index.md appear
# nowhere in that contract, so this script has no schema to hold them to and
# does not invent one.
# Archived plans are linted too. They used to be skipped, which meant a repo with
# an empty promote/ passed with "all valid" while every plan it had ever shipped
# went unchecked — the work action archives before opening the PR, so promote/ is
# empty at exactly the moment the check matters.
shopt -s nullglob
for f in "$PROJECT_DIR/scv/promote"/*/PLAN.md "$PROJECT_DIR/scv/archive"/*/PLAN.md; do
  check_file "$f" plan
done
shopt -u nullglob

if [[ $VIOLATIONS -gt 0 ]]; then
  echo ""
  echo "→ $VIOLATIONS violation(s) found"
  exit 1
fi

echo "✓ All frontmatter valid"
