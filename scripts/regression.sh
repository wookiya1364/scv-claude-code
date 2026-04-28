#!/usr/bin/env bash
# regression.sh — accumulated regression runner for SCV archived (and optionally
# promote) TESTS.md. Reads supersedes / supersedes_scenarios from every PLAN.md
# to build a skip graph, then executes the remaining TESTS commands.
#
# Usage:
#   regression.sh [<slug-prefix>]
#                 [--tag <x>] [--include-promote] [--include-obsolete]
#                 [--only <slug>] [--skip <slug>] [--ci] [--quiet]
#                 [--json <path>] [--timeout <sec>]
#
# Exit codes:
#   0  all passed (or nothing to run)
#   1  one or more failed (interactive mode)
#   2  one or more failed (--ci mode)
#   3  structural error (e.g., supersedes cycle, unreadable files)
#
# This script is a pure executor. All user interaction (AskUserQuestion triage
# for failures) is driven by commands/regression.md — NOT here.

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"

PROMOTE_DIR="${PROMOTE_DIR:-scv/promote}"
ARCHIVE_DIR="${ARCHIVE_DIR:-scv/archive}"

# ---- flag defaults ----
SLUG_PREFIX=""
TAG_FILTER=""
INCLUDE_PROMOTE=0
INCLUDE_OBSOLETE=0
CI_MODE=0
QUIET=0
JSON_PATH=""
TIMEOUT=300
ONLY_LIST=()
SKIP_LIST=()

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

# ---- flag parsing ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)               TAG_FILTER="$2"; shift 2 ;;
    --include-promote)   INCLUDE_PROMOTE=1; shift ;;
    --include-obsolete)  INCLUDE_OBSOLETE=1; shift ;;
    --only)              ONLY_LIST+=("$2"); shift 2 ;;
    --skip)              SKIP_LIST+=("$2"); shift 2 ;;
    --ci)                CI_MODE=1; shift ;;
    --quiet)             QUIET=1; shift ;;
    --json)              JSON_PATH="$2"; shift 2 ;;
    --timeout)           TIMEOUT="$2"; shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    -*)                  echo "Unknown flag: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$SLUG_PREFIX" ]]; then SLUG_PREFIX="$1"
      else echo "Multiple slug prefixes not supported: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

TODAY=$(date +%Y-%m-%d)
AUTHOR=""
if command -v git >/dev/null 2>&1; then
  raw_name=$(git config user.name 2>/dev/null || true)
  if [[ -n "$raw_name" ]]; then
    AUTHOR=$(printf '%s' "$raw_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-_')
  fi
fi
[[ -z "$AUTHOR" ]] && AUTHOR="unknown"

# Auto-detect CI environment when --ci is not explicit. Industry convention:
# GitHub Actions / GitLab CI / CircleCI / Jenkins all set CI=true. Honoring
# this means users (and SCV docs) don't need to remember --ci.
if [[ $CI_MODE -eq 0 && "${CI:-}" == "true" ]]; then
  CI_MODE=1
fi

if [[ $INCLUDE_PROMOTE -eq 1 ]]; then SCOPE="archive+promote"; else SCOPE="archive"; fi

# ---- enumeration helpers ----

enumerate_targets() {
  shopt -s nullglob
  for d in "$ARCHIVE_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local name; name=$(basename "$d")
    echo "archive|$name|$d"
  done
  if [[ $INCLUDE_PROMOTE -eq 1 ]]; then
    for d in "$PROMOTE_DIR"/*/; do
      [[ -d "$d" ]] || continue
      local name; name=$(basename "$d")
      echo "promote|$name|$d"
    done
  fi
  shopt -u nullglob
}

# Check whether a slug matches the positional prefix filter (substring match)
matches_prefix() {
  local slug="$1"
  [[ -z "$SLUG_PREFIX" ]] && return 0
  [[ "$slug" == *"$SLUG_PREFIX"* ]]
}

# Check whether the PLAN.md tags contain the filter
matches_tag() {
  local plan="$1"
  [[ -z "$TAG_FILTER" ]] && return 0
  [[ ! -f "$plan" ]] && return 1
  local tags; tags=$(yaml_get_list "$plan" tags | tr '\n' ' ')
  printf ' %s ' "$tags" | grep -qF " $TAG_FILTER "
}

# Check --only / --skip list membership
in_list() {
  local needle="$1"; shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# ---- supersede graph ----
# Scans every PLAN.md (archive + promote, regardless of --include-promote)
# and emits lines of the form:
#   SLUG          <victim-slug>\t<by-slug>
#   SCENARIO      <victim-slug>:T<n>\t<by-slug>
build_supersede_skip_list() {
  shopt -s nullglob
  local plans=()
  for d in "$ARCHIVE_DIR"/*/ "$PROMOTE_DIR"/*/; do
    [[ -f "${d}PLAN.md" ]] && plans+=("${d}PLAN.md")
  done
  shopt -u nullglob

  for p in "${plans[@]}"; do
    local by; by=$(yaml_get "$p" slug)
    [[ -z "$by" ]] && by=$(basename "$(dirname "$p")")

    while IFS= read -r victim; do
      [[ -z "$victim" ]] && continue
      printf 'SLUG\t%s\t%s\n' "$victim" "$by"
    done < <(yaml_get_list "$p" supersedes)

    while IFS= read -r victim; do
      [[ -z "$victim" ]] && continue
      printf 'SCENARIO\t%s\t%s\n' "$victim" "$by"
    done < <(yaml_get_list "$p" supersedes_scenarios)
  done
}

# Return slugs with status: obsolete in archive
get_obsolete_slugs() {
  shopt -s nullglob
  for d in "$ARCHIVE_DIR"/*/; do
    local plan="${d}PLAN.md"
    [[ -f "$plan" ]] || continue
    local st; st=$(yaml_get "$plan" status)
    if [[ "$st" == "obsolete" ]]; then
      basename "$d"
    fi
  done
  shopt -u nullglob
}

# Detect cycles in slug-level supersedes (A→B and B→A).
# Emits cycle pairs to stderr. Returns 1 if any cycle found.
detect_supersede_cycles() {
  local pairs_file="$1"
  # Lines: SLUG<TAB>victim<TAB>by — treat as directed edge by→victim
  local cycles=0
  local edges; edges=$(awk -F'\t' '$1=="SLUG" {print $3" "$2}' "$pairs_file")
  # Map: key="A B" edge exists
  declare -A edge_set=()
  while IFS=' ' read -r a b; do
    [[ -z "$a" || -z "$b" ]] && continue
    edge_set["$a $b"]=1
  done <<< "$edges"
  # Check: is there also b→a for any a→b?
  for key in "${!edge_set[@]}"; do
    local a b; a="${key% *}"; b="${key#* }"
    if [[ -n "${edge_set["$b $a"]:-}" && "$a" < "$b" ]]; then
      echo "WARN: supersedes cycle detected between '$a' and '$b' — both will be skipped" >&2
      cycles=$((cycles+1))
    fi
  done
  return $cycles
}

# ---- TESTS.md parsing ----

# Extract the commands from `## 실행 방법` section.
# Prefers the first fenced code block; falls back to raw section text.
read_test_command() {
  local tests="$1"
  [[ -f "$tests" ]] || return 1
  awk '
    BEGIN { in_section=0; in_fence=0; has_fence=0; buf=""; plain="" }
    /^## /{ if (in_section) { exit } }
    /^## 실행 방법[[:space:]]*$/ { in_section=1; next }
    in_section {
      if (!in_fence && /^[[:space:]]*```/) {
        in_fence=1; has_fence=1; next
      }
      if (in_fence && /^[[:space:]]*```[[:space:]]*$/) {
        in_fence=0; next
      }
      if (in_fence) { buf = buf $0 "\n"; next }
      if (!has_fence && $0 !~ /^[[:space:]]*$/ && $0 !~ /^<!--/) {
        plain = plain $0 "\n"
      }
    }
    END {
      if (buf != "") { printf "%s", buf; exit }
      if (plain != "") { printf "%s", plain }
    }
  ' "$tests"
}

# ---- output helpers ----

emit_header() {
  echo "MODE: regression"
  echo "TODAY: $TODAY"
  echo "AUTHOR: $AUTHOR"
  echo "SCOPE: $SCOPE"
  if [[ -n "$TAG_FILTER" ]]; then echo "TAG_FILTER: $TAG_FILTER"; else echo "TAG_FILTER: none"; fi
}

# ---- main orchestration ----
main() {
  # 1. enumerate raw targets
  local raw_targets=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    raw_targets+=("$line")
  done < <(enumerate_targets)

  # 2. apply filters: prefix, tag, --only, --skip
  local targets=()
  for line in "${raw_targets[@]}"; do
    IFS='|' read -r src slug dir <<< "$line"
    matches_prefix "$slug" || continue
    matches_tag "${dir}PLAN.md" || continue
    if [[ ${#ONLY_LIST[@]} -gt 0 ]]; then
      in_list "$slug" "${ONLY_LIST[@]}" || continue
    fi
    if [[ ${#SKIP_LIST[@]} -gt 0 ]]; then
      in_list "$slug" "${SKIP_LIST[@]}" && continue
    fi
    targets+=("$line")
  done

  # 3. build skip graph (scan ALL plans, not just filtered targets)
  local pairs_file; pairs_file=$(mktemp)
  build_supersede_skip_list > "$pairs_file"

  declare -A skip_slug_by=()
  declare -A skip_scenario_by=()

  while IFS=$'\t' read -r kind victim by; do
    [[ -z "$kind" ]] && continue
    if [[ "$kind" == "SLUG" ]]; then
      skip_slug_by["$victim"]="$by"
    elif [[ "$kind" == "SCENARIO" ]]; then
      skip_scenario_by["$victim"]="$by"
    fi
  done < "$pairs_file"

  # 4. obsolete skip
  declare -A obsolete_slugs=()
  if [[ $INCLUDE_OBSOLETE -eq 0 ]]; then
    while IFS= read -r s; do
      [[ -z "$s" ]] && continue
      obsolete_slugs["$s"]=1
    done < <(get_obsolete_slugs)
  fi

  # 5. cycle detection (warn only)
  detect_supersede_cycles "$pairs_file" || true
  rm -f "$pairs_file"

  # 6. emit header + skip block
  emit_header

  local total_slugs=${#targets[@]}
  local skipped_superseded=0
  local skipped_obsolete=0
  local skipped_scenarios=${#skip_scenario_by[@]}

  for line in "${targets[@]}"; do
    IFS='|' read -r src slug dir <<< "$line"
    if [[ -n "${skip_slug_by[$slug]:-}" ]]; then skipped_superseded=$((skipped_superseded+1)); fi
    if [[ -n "${obsolete_slugs[$slug]:-}" ]]; then skipped_obsolete=$((skipped_obsolete+1)); fi
  done

  echo "TOTAL_SLUGS: $total_slugs"
  echo "SKIPPED_SUPERSEDED: $skipped_superseded"
  echo "SKIPPED_OBSOLETE: $skipped_obsolete"
  echo "SKIPPED_SCENARIOS: $skipped_scenarios"

  echo ""
  echo "=== skip list (superseded / obsolete / scenario-level) ==="
  local any_skip=0
  for slug in "${!skip_slug_by[@]}"; do
    echo "[superseded] $slug  ← by ${skip_slug_by[$slug]}"
    any_skip=1
  done
  for key in "${!skip_scenario_by[@]}"; do
    echo "[scenario-skipped] $key  ← by ${skip_scenario_by[$key]}"
    any_skip=1
  done
  for slug in "${!obsolete_slugs[@]}"; do
    echo "[obsolete] $slug"
    any_skip=1
  done
  [[ $any_skip -eq 0 ]] && echo "(none)"

  # 7. execute
  echo ""
  echo "=== execution ==="

  local passed=0 failed=0 executed=0
  local failed_slugs=()
  declare -A slug_outcome=()        # slug → pass|fail|skipped
  declare -A slug_output_tail=()    # slug → last-20-lines

  local idx=0
  for line in "${targets[@]}"; do
    IFS='|' read -r src slug dir <<< "$line"
    idx=$((idx+1))
    if [[ -n "${skip_slug_by[$slug]:-}" || -n "${obsolete_slugs[$slug]:-}" ]]; then
      slug_outcome["$slug"]="skipped"
      [[ $QUIET -eq 0 ]] && echo "[$idx/$total_slugs] $slug — SKIPPED"
      continue
    fi
    executed=$((executed+1))
    local tests="${dir}TESTS.md"
    local plan="${dir}PLAN.md"
    if [[ ! -f "$tests" ]]; then
      echo "[$idx/$total_slugs] $slug — NO TESTS.md (skipping)"
      slug_outcome["$slug"]="skipped"
      continue
    fi
    local cmd; cmd=$(read_test_command "$tests")
    if [[ -z "$cmd" ]]; then
      echo "[$idx/$total_slugs] $slug — TESTS.md has empty '## 실행 방법' (skipping)"
      slug_outcome["$slug"]="skipped"
      continue
    fi

    # Build scenario-skip env hint for TESTS.md that honors it
    local skipped_T_for_slug=""
    for key in "${!skip_scenario_by[@]}"; do
      if [[ "$key" == "$slug:T"* ]]; then
        local tnum="${key#$slug:}"
        if [[ -n "$skipped_T_for_slug" ]]; then
          skipped_T_for_slug="$skipped_T_for_slug,$tnum"
        else
          skipped_T_for_slug="$tnum"
        fi
      fi
    done

    if [[ ! -f "$plan" ]]; then
      echo "WARN: $slug has no PLAN.md — treating as active, running anyway" >&2
    fi

    echo "[$idx/$total_slugs] $slug"
    if [[ $QUIET -eq 0 ]]; then
      local first_line; first_line=$(printf '%s\n' "$cmd" | sed -n '1p')
      echo "  running: ${first_line:0:80}"
    fi

    local out_file; out_file=$(mktemp)
    local rc=0
    local before_ts; before_ts=$(date +%s)
    if [[ -n "$skipped_T_for_slug" ]]; then
      SCV_SKIPPED_SCENARIOS="$skipped_T_for_slug" timeout "$TIMEOUT" bash -c "$cmd" >"$out_file" 2>&1 || rc=$?
    else
      timeout "$TIMEOUT" bash -c "$cmd" >"$out_file" 2>&1 || rc=$?
    fi
    local after_ts; after_ts=$(date +%s)
    local dur=$((after_ts - before_ts))

    if [[ $rc -eq 0 ]]; then
      passed=$((passed+1))
      slug_outcome["$slug"]="pass"
      [[ $QUIET -eq 0 ]] && echo "  ✓ passed (${dur}s)"
    else
      failed=$((failed+1))
      failed_slugs+=("$slug")
      slug_outcome["$slug"]="fail"
      if [[ $rc -eq 124 ]]; then
        echo "  ✗ FAILED — timeout after ${TIMEOUT}s"
      else
        echo "  ✗ FAILED (exit $rc, ${dur}s)"
      fi
      local tail_out; tail_out=$(tail -c 20480 "$out_file" | tail -n 20)
      slug_output_tail["$slug"]="$tail_out"
      echo "  --- output tail ---"
      printf '%s\n' "$tail_out" | sed 's/^/  /'
      echo "  --- end ---"
    fi
    rm -f "$out_file"
  done

  # 8. summary
  echo ""
  echo "=== summary ==="
  echo "EXECUTED_SLUGS: $executed"
  echo "PASSED_SLUGS: $passed"
  echo "FAILED_SLUGS: $failed"
  if [[ $failed -gt 0 ]]; then
    echo "failed_slugs: ${failed_slugs[*]}"
  fi

  # 9. optional JSON output
  local final_json_path="$JSON_PATH"
  if [[ $CI_MODE -eq 1 && -z "$final_json_path" ]]; then
    mkdir -p test-results
    final_json_path="test-results/regression-summary.json"
  fi
  if [[ -n "$final_json_path" ]]; then
    emit_json_summary "$final_json_path" "$passed" "$failed" "$executed" \
      "$total_slugs" "$skipped_superseded" "$skipped_obsolete" "$skipped_scenarios" \
      "${failed_slugs[@]:-}"
    echo "JSON summary: $final_json_path"
  fi

  # 10. exit code
  if [[ $failed -gt 0 ]]; then
    if [[ $CI_MODE -eq 1 ]]; then exit 2; else exit 1; fi
  fi
  exit 0
}

emit_json_summary() {
  local path="$1"; shift
  local passed="$1"; shift
  local failed="$1"; shift
  local executed="$1"; shift
  local total="$1"; shift
  local sk_sup="$1"; shift
  local sk_obs="$1"; shift
  local sk_scn="$1"; shift
  # remaining args are failed slugs (possibly empty string if none)
  local failed_arr="["
  local first=1
  for s in "$@"; do
    [[ -z "$s" ]] && continue
    if [[ $first -eq 1 ]]; then first=0; else failed_arr="$failed_arr,"; fi
    failed_arr="$failed_arr\"$s\""
  done
  failed_arr="$failed_arr]"

  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
{
  "mode": "regression",
  "date": "$TODAY",
  "author": "$AUTHOR",
  "scope": "$SCOPE",
  "tag_filter": "${TAG_FILTER:-}",
  "total_slugs": $total,
  "executed_slugs": $executed,
  "passed_slugs": $passed,
  "failed_slugs_count": $failed,
  "skipped_superseded": $sk_sup,
  "skipped_obsolete": $sk_obs,
  "skipped_scenarios": $sk_scn,
  "failed_slugs": $failed_arr
}
EOF
}

main
