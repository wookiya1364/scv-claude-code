#!/usr/bin/env bash
# bash 4+ required (associative arrays). macOS ships 3.2 — auto-escalate to brew bash.
if (( BASH_VERSINFO[0] < 4 )); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$_b" ]] && exec "$_b" "$0" "$@"
  done
  echo "Error: SCV requires bash 4+. Install via 'brew install bash'." >&2
  exit 1
fi

# regression.sh — accumulated regression runner for SCV archived (and optionally
# promote) TESTS.md. Reads supersedes / supersedes_scenarios from every PLAN.md
# to build a skip graph, then executes the remaining TESTS commands.
#
# Usage:
#   regression.sh [<slug-prefix>]
#                 [--tag <x>] [--include-promote] [--include-obsolete]
#                 [--only <slug>] [--skip <slug>] [--ci] [--quiet]
#                 [--dry] [--changed <a,b,…>]     # v0.51.0: 계획·영향만 보기 / 영향 조회 대상 지정
#                 [--json <path>] [--timeout <sec>] [--no-memo]
#
# Exit codes:
#   0  all passed (or nothing to run)
#   1  one or more failed (interactive mode)
#   2  one or more failed (--ci mode)
#   3  structural error (e.g., supersedes cycle, unreadable files)
#
# This script is a pure executor. All user interaction for failure triage is
# driven by references/protocols/regression.md — NOT here.

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"
# shellcheck source=lib/regression-memo.sh
source "$SCRIPT_DIR/lib/regression-memo.sh"
env_load 2>/dev/null || true

# ---- flag defaults ----
SCV_TARGET=""            # optional leading module dir (monorepo), e.g. FE
SLUG_PREFIX=""
TAG_FILTER=""
INCLUDE_PROMOTE=0
INCLUDE_OBSOLETE=0
CI_MODE=0
QUIET=0
DRY=0
CHANGED_LIST=""
JSON_PATH=""
# 블록 하나(또는 메모된 게이트 하나)의 상한. 코어 검사 전부를 도는 게이트는 한 번만 돌지만 검사가 47개
# (0.50.0 기준 약 290초)라 300 으로는 게이트 자체가 잘려 "검사 실패" 로 보였다 — 세 보관 계약이 같은
# 게이트로 붉게 떴다. --timeout 으로 바꿀 수 있다. 0.64.0 — 검사 57개가 맥 로컬 약 650초라 600 으로도 같은 게이트가 잘렸다
# (종료 코드 124 — 세 보관 계약이 붉게, 2026-10-02 확인). 검사가 늘어 온 속도를 보고 1200 으로.
TIMEOUT=1200
MEMO=1                 # suite-gate memoization (v0.34.0): identical whole-suite calls run once per run
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
    --no-memo)           MEMO=0; shift ;;
    --dry)               DRY=1; shift ;;                       # v0.51.0: 계획·영향만 찍고 실행하지 않는다
    --changed)           CHANGED_LIST="$2"; shift 2 ;;         # v0.51.0: 쉼표 구분 경로 — 영향 조회 대상 (없으면 git diff)
    -h|--help)           usage; exit 0 ;;
    -*)                  echo "Unknown flag: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$SCV_TARGET" && -z "$SLUG_PREFIX" ]] && scv_target_path "$1" >/dev/null 2>&1; then
        SCV_TARGET="$1"          # leading module dir (monorepo): regression.sh FE
      elif [[ -z "$SLUG_PREFIX" ]]; then SLUG_PREFIX="$1"
      else echo "Multiple slug prefixes not supported: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

# Resolve scv/ (monorepo-nested aware; optional leading module target) →
# PROMOTE_DIR/ARCHIVE_DIR. Without this, /scv:work FE <slug>'s Step-9a regression
# pre-flight would run against the wrong scv and pass without testing (false green).
scv_init_paths "$SCV_TARGET"

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
# v0.11.0+ — Tries scv/archive/INDEX.yaml first (fast path, frontmatter-only).
# Falls back to per-PLAN.md scan when INDEX is absent (older projects, fresh repos).
# Known limitation: INDEX may lag if archive folders were created outside /scv:work --archive;
# fallback path is exact. /scv:work always regenerates INDEX on archive, so drift is rare.
get_obsolete_slugs() {
  local index_file="$ARCHIVE_DIR/INDEX.yaml"
  if [[ -f "$index_file" ]]; then
    awk '
      /^  - slug:/ {
        if (cur != "" && obs == 1) print cur
        cur = $3; obs = 0
        next
      }
      /^    status:[[:space:]]*obsolete/ { obs = 1 }
      END { if (cur != "" && obs == 1) print cur }
    ' "$index_file"
    return
  fi
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

# Extract the commands from `## How to run` (or legacy `## 실행 방법`) section.
# Prefers the first fenced code block; falls back to raw section text.
# Both heading variants are accepted for backwards compat with v0.3.x archived
# TESTS.md (Korean) and v0.4+ template (English).
read_test_command() {
  local tests="$1"
  [[ -f "$tests" ]] || return 1
  awk '
    BEGIN { in_section=0; in_fence=0; has_fence=0; buf=""; plain="" }
    /^## /{ if (in_section) { exit } }
    /^## (How to run|실행 방법)[[:space:]]*$/ { in_section=1; next }
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

# Run a command with GNU-timeout-compatible exit code 124 without requiring
# GNU coreutils on macOS. Python is already an optional SCV runtime dependency;
# if no timeout-capable runner exists, execute directly instead of making every
# regression fail with command-not-found.
# run_scenario_clean <cmd> — spawn one scenario in a CLEAN environment: this
# runner's own scv_autosync marked the process tree "already checked"
# (SCV_AUTOSYNC_RUNNING=1, via scv_init_paths), and a child scenario
# inheriting that mark sees the very hook it may be testing no-op itself —
# the archived autosync contract read 10/11 red inside the runner while
# passing 21/21 outside. Only the runner's own mark is dropped; everything
# the user exported (SCV_AUTOSYNC=off included) passes through untouched,
# and the mark stays set in THIS process so the runner's helpers still
# check once. Callers may prefix SCV_SKIPPED_SCENARIOS=... — the same
# temp-export mechanism run_with_timeout already relies on.
# ---- suite-gate memoization (v0.34.0) ----
# 22 of 28 archived contracts end with "run the whole suite" — the same three
# commands, byte for byte, repeated per slug. Within ONE run their verdict cannot
# differ, so each distinct gate command runs once and later blocks reuse its
# exit code. Only these exact invocations are memoized; everything else in a
# block runs as written, so a contract's own assertions are never skipped.
#   bash core/tests/run-dry.sh            (any redirection / || fail after it)
#   bash tests/run.sh
#   for t in core/tests/test-*.sh; do bash "$t" ... ; done   (the loop as a unit)
# --no-memo (or SCV_REGRESSION_MEMO=off) restores per-slug execution.
declare -A MEMO_RC=()
declare -A MEMO_USES=()      # 공유 시험 키 → 이번 회귀에서 쓴 계획 수
declare -A MEMO_OUT=()       # 공유 시험 키 → 그 출력 파일(실패한 계획에 꼬리를 보여 준다)
declare -A MEMO_OK_SLUG=()   # 공유 결과를 써도 되는 계획
MEMO_TABLE=""
MEMO_DIR=""
MEMO_HITS=0
MEMO_GATES=0
memo_gate_run() {  # memo_gate_run <key> <command> — run once (in THIS shell, so the cache persists); count reuse
  local key="$1" cmd="$2"
  if [[ -z "${MEMO_RC[$key]+x}" ]]; then
    local rc=0
    local -a unset_args=(); while IFS= read -r a; do unset_args+=("$a"); done < <(env_settings_unset_args)
    run_with_timeout "$TIMEOUT" env -u SCV_AUTOSYNC_RUNNING \
      -u SCV_DIR -u RAW_DIR -u STATE_FILE -u PROMOTE_DIR -u ARCHIVE_DIR "${unset_args[@]}" \
      bash -c "$cmd" >/dev/null 2>&1 || rc=$?
    MEMO_RC[$key]=$rc
    MEMO_GATES=$((MEMO_GATES+1))
    [[ $QUIET -eq 0 ]] && echo "  ↺ suite gate [$key] ran once (exit $rc) — later contracts reuse it"
  else
    MEMO_HITS=$((MEMO_HITS+1))
  fi
  return 0
}
# memo_prepare_block <block> — runs (once) every gate the block mentions. Must be
# called in the main shell: a command substitution would fork and lose the cache.
memo_prepare_block() {
  local line key
  while IFS= read -r line || [[ -n "$line" ]]; do
    if scv_reg_is_core_loop "$line"; then
      if [[ -n "${MEMO_RC[core-tests]+x}" && -n "$MEMO_TABLE" ]]; then
        MEMO_USES[core-tests]=$(( ${MEMO_USES[core-tests]:-0} + 1 ))
      else
        memo_gate_run core-tests 'for t in core/tests/test-*.sh; do bash "$t" >/dev/null 2>&1 || exit 1; done'
      fi
    else
      # 시험 파일 하나를 부르는 줄 — 회귀 시작 때 한 번씩 동시에 돌려 둔 결과를 쓴다(memo_prerun_shared).
      while IFS= read -r key; do
        [[ -n "$key" && -n "${MEMO_RC[$key]+x}" ]] && MEMO_USES[$key]=$(( ${MEMO_USES[$key]:-0} + 1 ))
      done <<< "$(scv_reg_collect_keys "$line")"
    fi
  done <<< "$1"
}
memo_rewrite_block() {  # stdin: block → stdout: block with memoized gates replaced by their cached exit
  local line rc tail
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^([[:space:]]*)for[[:space:]]+t[[:space:]]+in[[:space:]]+core/tests/test-\*\.sh\;[[:space:]]*do[[:space:]]+bash[[:space:]]+\"\$t\"(.*)done[[:space:]]*$ ]]; then
      rc="${MEMO_RC[core-tests]:-}"
      if [[ -n "$rc" ]]; then
        tail="${BASH_REMATCH[2]}"; tail="${tail%%;*}"
        printf '%s( exit %s )%s\n' "${BASH_REMATCH[1]}" "$rc" "${tail//\$t/core/tests}"; continue
      fi
    fi
    printf '%s\n' "$(scv_reg_rewrite_line "$line" "$MEMO_TABLE")"
  done
}
# memo_prerun_shared <targets…> — 회귀 대상 계획들의 블록에서 '시험 파일 하나를 부르는 줄'을 모아
# 같은 줄은 한 번만, 여러 개를 동시에 돌려 MEMO_RC 에 코드를 남긴다(2026-11-01 — 같은 시험이
# 계획마다 반복돼 회귀가 49분 넘게 미완). 장면 건너뛰기가 있는 계획 · 다른 폴더로 옮겨 가는 계획은
# 공유 결과를 쓰지 않는다(MEMO_OK_SLUG 에 없음). `# scv-test: serial` 표시 시험은 동시 실행 뒤 하나씩.
memo_prerun_shared() {
  local line src slug dir tests cmd text="" key k
  for line in "$@"; do
    IFS='|' read -r src slug dir <<< "$line"
    [[ -n "${skip_slug_by[$slug]:-}" || -n "${obsolete_slugs[$slug]:-}" ]] && continue
    tests="${dir}TESTS.md"; [[ -f "$tests" ]] || continue
    cmd="$(read_test_command "$tests")"; [[ -n "$cmd" ]] || continue
    for k in "${!skip_scenario_by[@]}"; do [[ "$k" == "$slug:T"* ]] && continue 2; done
    scv_reg_block_memo_ok "$cmd" || continue
    MEMO_OK_SLUG[$slug]=1
    text+="$cmd"$'\n'
  done
  local -a keys=() serial=() core_keys=()
  while IFS= read -r key; do [[ -n "$key" ]] && keys+=("$key"); done < <(scv_reg_collect_keys "$text")
  # '코어 시험 전부' 반복 줄은 시험 파일 하나하나로 나눠 같이 동시에 돈다 — 한 덩어리로 돌면 하나씩
  # 차례로라 13분쯤 걸렸다(2026-11-01). 반복 줄의 결과는 그중 하나라도 실패하면 1.
  local l has_loop=0 f
  while IFS= read -r l || [[ -n "$l" ]]; do scv_reg_is_core_loop "$l" && { has_loop=1; break; }; done <<< "$text"
  if [[ $has_loop -eq 1 ]]; then
    for f in core/tests/test-*.sh; do
      [[ -f "$f" ]] || continue
      key="bash $f"; core_keys+=("$key")
      [[ $'\n'"$(printf '%s\n' "${keys[@]}")"$'\n' == *$'\n'"$key"$'\n'* ]] || keys+=("$key")
    done
  fi
  [[ ${#keys[@]} -gt 0 ]] || return 0
  MEMO_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scv-regression-memo.XXXXXX")"
  local jobs="${SCV_TEST_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}" i=0 file
  [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || jobs=4
  [[ $QUIET -eq 0 ]] && echo "  ↺ shared tests: ${#keys[@]} distinct, $jobs at a time"
  for (( i = 0; i != ${#keys[@]}; i++ )); do
    key="${keys[i]}"; file="${key#bash }"; file="${file%% *}"
    if [[ -f "$file" ]] && head -30 "$file" | grep -q '^# scv-test: serial'; then serial+=("$i"); continue; fi
    while (( $(jobs -rp | wc -l) >= jobs )); do wait -n; done
    # 0.81.0+ — 겹쳐 도는 묶음 안은 하나씩(SCV_TEST_JOBS=1): 묶음마다 다시 코어 수만큼 돌면 동시에 100개 넘게 겹쳐
    # 컴퓨터가 멈춘 듯 느려지고(부하 75 / 코어 11, 2026-11-04) 시간 한도 시험이 흔들렸다. 혼자 다시 도는 아래 단계는 그대로.
    ( rc=0; SCV_TEST_JOBS=1 run_scenario_clean "$key" >"$MEMO_DIR/$i.out" 2>&1 || rc=$?; echo "$rc" > "$MEMO_DIR/$i.rc" ) &
  done
  wait
  # 동시에 돌다 실패한 시험은 다 끝난 뒤 혼자 한 번 더 — 시간 한도를 재는 시험이 다른 시험과 겹쳐 느려져
  # 떨어진 것을 하나씩 돌던 예전 판정과 같게 맞춘다(2026-11-01: 실체 보여 주기 T11 60초 한도가 66초).
  # 혼자 돌아도 실패하면 그대로 실패다.
  local -a again=()
  local serial_set=" ${serial[*]} "
  for (( i = 0; i != ${#keys[@]}; i++ )); do
    [[ "$serial_set" == *" $i "* ]] && continue
    [[ "$(cat "$MEMO_DIR/$i.rc" 2>/dev/null || echo 1)" == 0 ]] || again+=("$i")
  done
  for i in "${serial[@]}" "${again[@]}"; do
    ( rc=0; run_scenario_clean "${keys[i]}" >"$MEMO_DIR/$i.out" 2>&1 || rc=$?; echo "$rc" > "$MEMO_DIR/$i.rc" )
  done
  [[ $QUIET -eq 0 && ${#again[@]} -gt 0 ]] && echo "  ↺ reran ${#again[@]} failed shared test(s) alone"
  MEMO_TABLE=""
  for (( i = 0; i != ${#keys[@]}; i++ )); do
    MEMO_RC[${keys[i]}]="$(cat "$MEMO_DIR/$i.rc" 2>/dev/null || echo 1)"
    MEMO_OUT[${keys[i]}]="$MEMO_DIR/$i.out"
    MEMO_TABLE+="${keys[i]}"$'\t'"${MEMO_RC[${keys[i]}]}"$'\n'
  done
  if [[ ${#core_keys[@]} -gt 0 ]]; then
    MEMO_RC[core-tests]=0
    for key in "${core_keys[@]}"; do [[ "${MEMO_RC[$key]}" == 0 ]] || { MEMO_RC[core-tests]=1; break; }; done
  fi
}
run_scenario_clean() {
  # The runner's own marks, and nothing else: the autosync re-entry guard plus
  # the five path marks scv_init_paths exports (SCV_DIR RAW_DIR STATE_FILE
  # PROMOTE_DIR ARCHIVE_DIR). Inherited, those make a scenario's temp-project
  # helpers resolve THIS repo's scv/ — an archived contract that runs run-dry
  # died inside the runner only (plain-answers-enforcement T6, 0.31.0).
  # Plus every key env_load exported from the settings file (SCV_LANG …): the
  # archived contracts assume "no settings", and ten of them went red inside the
  # runner the day this repo grew a settings file (0.54.0). Keys the user exported
  # before starting the runner are not in that list and still pass through.
  local -a unset_args=(); while IFS= read -r a; do unset_args+=("$a"); done < <(env_settings_unset_args)
  run_with_timeout "$TIMEOUT" env -u SCV_AUTOSYNC_RUNNING \
    -u SCV_DIR -u RAW_DIR -u STATE_FILE -u PROMOTE_DIR -u ARCHIVE_DIR "${unset_args[@]}" \
    bash -c "$1"
}

run_with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    command timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    command gtimeout "$seconds" "$@"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import subprocess
import sys

seconds = float(sys.argv[1])
try:
    result = subprocess.run(sys.argv[2:], timeout=seconds)
except subprocess.TimeoutExpired:
    raise SystemExit(124)
raise SystemExit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
' "$seconds" "$@"
  else
    echo "WARN: no timeout runner found; executing without a timeout" >&2
    "$@"
  fi
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

  # 6b. 영향 조회 (v0.51.0+, 정보만 — 실행 선택은 바꾸지 않는다): 변경 파일이 있으면 SCV 그래프로
  #     함께 바뀌는 파일·얽힌 계획·결정을 앞단에 보인다. --changed a,b 가 없으면 git 작업 트리의 변경 파일.
  local changed=""
  if [[ -n "$CHANGED_LIST" ]]; then changed="$(printf '%s' "$CHANGED_LIST" | tr ',' '\n')"
  elif command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    changed="$( { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | grep -v '^scv/' | LC_ALL=C sort -u | head -20 )"
  fi
  if [[ -n "${changed//[[:space:]]/}" && -f "$SCRIPT_DIR/graph.sh" ]]; then
    echo ""
    echo "=== impact (scv graph) ==="
    # shellcheck disable=SC2086
    bash "$SCRIPT_DIR/graph.sh" impact $changed 2>/dev/null || echo "(graph unavailable)"
    # Graft 어댑터 (v0.51.0+, 선택): graft 가 있고 그래프가 있으면 정적 영향 범위를 그 아래에 덧붙인다. 없으면 줄도 없다.
    if [[ -f "$SCRIPT_DIR/graft.sh" ]]; then
      local graft_out; graft_out="$(bash "$SCRIPT_DIR/graft.sh" blast 2>/dev/null || true)"
      if [[ -n "${graft_out//[[:space:]]/}" ]]; then echo ""; echo "=== impact (graft blast) ==="; printf '%s\n' "$graft_out"; fi
    fi
  fi
  if [[ $DRY -eq 1 ]]; then
    echo ""
    echo "DRY: no test was executed (--dry)"
    return 0
  fi

  # 7. execute
  echo ""
  echo "=== execution ==="

  local passed=0 failed=0 executed=0
  local failed_slugs=()
  declare -A slug_outcome=()        # slug → pass|fail|skipped
  declare -A slug_output_tail=()    # slug → last-20-lines

  if [[ $MEMO -eq 1 && "${SCV_REGRESSION_MEMO:-on}" != "off" ]]; then
    memo_prerun_shared "${targets[@]}"
  fi

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
      echo "[$idx/$total_slugs] $slug — TESTS.md has empty '## How to run' / '## 실행 방법' (skipping)"
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
    local orig_cmd="$cmd"
    if [[ $MEMO -eq 1 && "${SCV_REGRESSION_MEMO:-on}" != "off" && -n "${MEMO_OK_SLUG[$slug]:-}" ]]; then
      memo_prepare_block "$cmd"
      cmd="$(printf '%s\n' "$cmd" | memo_rewrite_block)"
    fi
    if [[ -n "$skipped_T_for_slug" ]]; then
      SCV_SKIPPED_SCENARIOS="$skipped_T_for_slug" \
        run_scenario_clean "$cmd" >"$out_file" 2>&1 || rc=$?
    else
      run_scenario_clean "$cmd" >"$out_file" 2>&1 || rc=$?
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
      # 공유로 한 번 돈 시험이 실패했으면 그 출력 꼬리도 보인다 — 이 계획의 블록엔 '( exit N )' 만 남아 있다.
      local sk
      while IFS= read -r sk; do
        [[ -n "$sk" && -n "${MEMO_RC[$sk]+x}" && "${MEMO_RC[$sk]}" != 0 && -n "${MEMO_OK_SLUG[$slug]:-}" ]] || continue
        echo "  --- shared test: $sk (exit ${MEMO_RC[$sk]}) ---"
        tail -n 10 "${MEMO_OUT[$sk]}" 2>/dev/null | sed 's/^/  /'
      done < <(
        scv_reg_collect_keys "$orig_cmd"
        # '코어 시험 전부' 반복 줄이 실패했으면 그 안에서 실패한 시험 파일들을
        while IFS= read -r cl || [[ -n "$cl" ]]; do
          if scv_reg_is_core_loop "$cl" && [[ "${MEMO_RC[core-tests]:-0}" != 0 ]]; then
            for ck in "${!MEMO_RC[@]}"; do [[ "$ck" == "bash core/tests/"* ]] && printf '%s\n' "$ck"; done
            break
          fi
        done <<< "$orig_cmd"
      )
    fi
    rm -f "$out_file"
  done

  # 8. summary
  echo ""
  echo "=== summary ==="
  echo "EXECUTED_SLUGS: $executed"
  local gen_used=0 gen_hits=0 uk
  for uk in "${!MEMO_USES[@]}"; do gen_used=$((gen_used + 1)); gen_hits=$((gen_hits + ${MEMO_USES[$uk]} - 1)); done
  echo "MEMOIZED_GATES: $((MEMO_GATES + gen_used)) (reused $((MEMO_HITS + gen_hits)) time(s))"
  [[ -n "$MEMO_DIR" && -d "$MEMO_DIR" && "${SCV_REGRESSION_KEEP:-}" != 1 ]] && rm -rf "$MEMO_DIR"
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
