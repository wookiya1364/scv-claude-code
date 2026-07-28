#!/usr/bin/env bash
# drift-detect.sh — Detect drift between code and PLAN.md/TESTS.md (v0.11.3+).
#
# For each active promote slug:
#   - If PLAN.md has scope: → compare `git diff --name-only HEAD` against globs.
#     Files outside scope = drift candidate.
#   - Else (no scope) → run TESTS.md's "How to run" command. Fail = drift candidate.
#
# Promote-only (archive is immutable). Read-only (no file modifications).
#
# Usage:
#   drift-detect.sh                # all active promote slugs
#   drift-detect.sh <slug-suffix>  # specific slug (fuzzy)
#
# Output (stdout, multi-record):
#   === <slug> ===
#   SCOPE_DEFINED: yes|no
#   SCOPE_GLOBS: "<g1>" "<g2>" ...                  (if defined)
#   SCOPE_OUTSIDE_FILES: <count>                     (if defined)
#     <file>
#   SCOPE_INSIDE_CHANGES: <count>                    (if defined)
#     <file>
#   TESTS_RUN: pass|fail|skipped|not_executed        (if no scope or as supplement)
#     <tail of failure output>
#   DRIFT: yes|no|unknown
#
# Exit code: 0 always.

set -uo pipefail
shopt -s globstar nullglob

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"

PROMOTE_DIR="${PROMOTE_DIR:-scv/promote}"
TARGET_SLUG="${1:-}"

matches_globs() {
  local file="$1"; shift
  local pattern
  for pattern in "$@"; do
    # shellcheck disable=SC2254
    case "$file" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

process_slug() {
  local slug_dir="$1"
  local slug
  slug="$(basename "$slug_dir")"
  local plan="$slug_dir/PLAN.md"
  local tests="$slug_dir/TESTS.md"

  echo "=== $slug ==="

  if [[ ! -f "$plan" ]]; then
    echo "DRIFT: unknown (no PLAN.md)"
    return
  fi

  local scope_globs=()
  if grep -q '^scope:' "$plan" 2>/dev/null; then
    echo "SCOPE_DEFINED: yes"
    while IFS= read -r line; do
      [[ -n "$line" ]] && scope_globs+=("$line")
    done < <(yaml_get_list "$plan" scope 2>/dev/null)

    if [[ ${#scope_globs[@]} -eq 0 ]]; then
      echo "SCOPE_GLOBS: (empty list — treated as no-scope)"
      echo "DRIFT: unknown"
      return
    fi

    # Print globs quoted for clarity
    local quoted=""
    for g in "${scope_globs[@]}"; do
      quoted+=" \"$g\""
    done
    echo "SCOPE_GLOBS:$quoted"

    local outside=() inside=()
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      if matches_globs "$file" "${scope_globs[@]}"; then
        inside+=("$file")
      else
        outside+=("$file")
      fi
    done < <(git diff --name-only HEAD 2>/dev/null)

    echo "SCOPE_OUTSIDE_FILES: ${#outside[@]}"
    for f in "${outside[@]}"; do echo "  $f"; done
    echo "SCOPE_INSIDE_CHANGES: ${#inside[@]}"
    for f in "${inside[@]}"; do echo "  $f"; done

    if [[ ${#outside[@]} -gt 0 ]]; then
      echo "DRIFT: yes"
    else
      echo "DRIFT: no"
    fi
  else
    echo "SCOPE_DEFINED: no"

    if [[ ! -f "$tests" ]]; then
      echo "TESTS_RUN: skipped (no TESTS.md)"
      echo "DRIFT: unknown"
      return
    fi

    local cmd
    cmd=$(awk '
      /^## (How to run|실행 방법)/ { in_section=1; next }
      /^## / { in_section=0 }
      in_section && /^```/ { in_code = !in_code; next }
      in_section && in_code { print }
    ' "$tests" 2>/dev/null | head -1)

    if [[ -z "$cmd" ]]; then
      echo "TESTS_RUN: skipped (no run command in TESTS.md)"
      echo "DRIFT: unknown"
      return
    fi

    local out
    if out=$(bash -c "$cmd" 2>&1); then
      echo "TESTS_RUN: pass"
      echo "DRIFT: no"
    else
      echo "TESTS_RUN: fail"
      echo "$out" | tail -5 | sed 's/^/  /'
      echo "DRIFT: yes"
    fi
  fi
}

if [[ -n "$TARGET_SLUG" ]]; then
  matches=("$PROMOTE_DIR"/*"$TARGET_SLUG"*)
  if [[ ${#matches[@]} -eq 0 || ! -d "${matches[0]}" ]]; then
    echo "ERROR: no promote slug matches '$TARGET_SLUG' under $PROMOTE_DIR/" >&2
    exit 2
  fi
  process_slug "${matches[0]}"
else
  any=0
  for d in "$PROMOTE_DIR"/*/; do
    [[ -d "$d" ]] || continue
    process_slug "$d"
    any=1
  done
  if [[ $any -eq 0 ]]; then
    echo "(no active promote slugs under $PROMOTE_DIR/)"
  fi
fi

exit 0
