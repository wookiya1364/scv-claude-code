#!/usr/bin/env bash
# status.sh — human-readable SCV project status.
#
# Shows:
#   1. Raw changes since last scv/readpath.json snapshot (added / modified / removed)
#   2. Active plans under scv/promote/
#
# Flags:
#   --ack        After printing diff, overwrite scv/readpath.json with current state
#                (useful to defer /scv:promote without the banner nagging)
#   --verbose    Show every changed path (default: collapse if >10 per bucket)
#
# Exit codes:
#   0 — printed status successfully (regardless of whether changes found)

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
READPATH="$SCRIPT_DIR/readpath.sh"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/attachments.sh
source "$SCRIPT_DIR/lib/attachments.sh"
env_load 2>/dev/null || true

ACK=0
VERBOSE=0
RAW_DIR="${RAW_DIR:-scv/raw}"
STATE_FILE="${STATE_FILE:-scv/readpath.json}"
PROMOTE_DIR="${PROMOTE_DIR:-scv/promote}"
ARCHIVE_DIR="${ARCHIVE_DIR:-scv/archive}"

for a in "$@"; do
  case "$a" in
    --ack)     ACK=1 ;;
    --verbose) VERBOSE=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown flag: $a" >&2; exit 1 ;;
  esac
done

PROJECT_PWD="$(pwd)"

echo "──────────────────────────────────────────────────────────────────────"
echo " SCV Status — $PROJECT_PWD"
echo "──────────────────────────────────────────────────────────────────────"
echo ""

# ---------- [1] raw diff ----------

echo "[scv/raw — changes since last index]"

if [[ ! -d "$RAW_DIR" ]]; then
  echo "  (directory does not exist — run /scv:help to check hydrate status)"
else
  FIRST_RUN=0
  [[ ! -f "$STATE_FILE" ]] && FIRST_RUN=1

  DIFF_OUT=$(RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" diff || true)

  if [[ -z "$DIFF_OUT" ]]; then
    echo "  no changes since last index."
  else
    if [[ $FIRST_RUN -eq 1 ]]; then
      echo "  (first run — no scv/readpath.json yet; treating all raw files as NEW)"
    fi

    # Count + render each bucket
    A_LINES=$(printf '%s\n' "$DIFF_OUT" | grep -E '^A	' || true)
    M_LINES=$(printf '%s\n' "$DIFF_OUT" | grep -E '^M	' || true)
    R_LINES=$(printf '%s\n' "$DIFF_OUT" | grep -E '^R	' || true)
    A_N=$( [[ -z "$A_LINES" ]] && echo 0 || printf '%s\n' "$A_LINES" | wc -l )
    M_N=$( [[ -z "$M_LINES" ]] && echo 0 || printf '%s\n' "$M_LINES" | wc -l )
    R_N=$( [[ -z "$R_LINES" ]] && echo 0 || printf '%s\n' "$R_LINES" | wc -l )

    render_bucket() {
      local label="$1" lines="$2" count="$3" formatter="$4"
      echo "  $label $count"
      [[ $count -eq 0 ]] && return
      local shown=0
      local limit=10
      [[ $VERBOSE -eq 1 ]] && limit=1000000
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        shown=$((shown+1))
        if [[ $shown -gt $limit ]]; then
          local rest=$((count - limit))
          echo "    … (+$rest more — rerun with --verbose to see all)"
          break
        fi
        "$formatter" "$line"
      done <<< "$lines"
    }

    fmt_A() {
      local p s m
      IFS=$'\t' read -r _ p s m <<< "$1"
      printf '    · %s  (%s bytes)\n' "$p" "$s"
    }
    fmt_M() {
      local p os ns om nm
      IFS=$'\t' read -r _ p os ns om nm <<< "$1"
      printf '    · %s  (%s → %s bytes)\n' "$p" "$os" "$ns"
    }
    fmt_R() {
      local p s m
      IFS=$'\t' read -r _ p s m <<< "$1"
      printf '    · %s  (was %s bytes)\n' "$p" "$s"
    }

    render_bucket "+ added   :" "$A_LINES" "$A_N" fmt_A
    render_bucket "* modified:" "$M_LINES" "$M_N" fmt_M
    render_bucket "- removed :" "$R_LINES" "$R_N" fmt_R

    echo ""
    echo "  → Review & refine : /scv:promote"
    echo "  → Or defer        : /scv:status --ack   (marks current state as baseline)"
  fi

  if [[ $ACK -eq 1 ]]; then
    echo ""
    echo "[--ack] updating $STATE_FILE ..."
    RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" update
  fi
fi

echo ""

# ---------- [2] promote plans ----------

echo "[scv/promote — active plans]"

if [[ ! -d "$PROMOTE_DIR" ]]; then
  echo "  (directory does not exist)"
else
  count=0
  # Flat .md files (legacy / simple plans)
  for f in "$PROMOTE_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    count=$((count+1))
    echo "  · $f"
  done
  # Directory-based plans — prefer PLAN.md, fall back to index.md
  for d in "$PROMOTE_DIR"/*/; do
    [[ -d "$d" ]] || continue
    if [[ -f "${d}PLAN.md" ]]; then
      count=$((count+1))
      echo "  · ${d}PLAN.md"
    elif [[ -f "${d}index.md" ]]; then
      count=$((count+1))
      echo "  · ${d}index.md"
    fi
  done
  [[ $count -eq 0 ]] && echo "  (empty)"
fi

echo ""

# ---------- [3] docs graph ----------

echo "[docs graph (graphify skill)]"
# Skill presence
GRAPHIFY_SKILL="missing"
for candidate in \
  "$HOME/.claude/skills/graphify/SKILL.md" \
  "$HOME/.claude/plugins/cache/"*/skills/graphify/SKILL.md; do
  if [[ -f "$candidate" ]]; then
    GRAPHIFY_SKILL="available"
    break
  fi
done
# Graph status
if [[ "$GRAPHIFY_SKILL" == "missing" ]]; then
  echo "  skill not installed — /scv:promote will run without graph optimization"
else
  GRAPH_DIR=".graphify/docs/graphify-out"
  if [[ ! -d "$GRAPH_DIR" ]]; then
    echo "  status: missing  — /scv:promote will build on first run"
  elif [[ ! -f "$STATE_FILE" ]]; then
    echo "  status: built    (no readpath baseline yet)"
  else
    graph_mt=$(stat -c %Y "$GRAPH_DIR" 2>/dev/null || echo 0)
    state_mt=$(stat -c %Y "$STATE_FILE" 2>/dev/null || echo 0)
    if [[ "$graph_mt" -ge "$state_mt" ]]; then
      echo "  status: built    (up to date with readpath baseline)"
    else
      echo "  status: stale    — /scv:promote will auto-refresh"
    fi
  fi
fi

echo ""

# ---------- [4] archive ----------

echo "[scv/archive — completed plans]"

if [[ ! -d "$ARCHIVE_DIR" ]]; then
  echo "  (directory does not exist)"
else
  archived=0
  for d in "$ARCHIVE_DIR"/*/; do
    [[ -d "$d" ]] || continue
    archived=$((archived+1))
  done
  if [[ $archived -eq 0 ]]; then
    echo "  (empty — no plans archived yet)"
  else
    echo "  $archived entry(ies)"
  fi
fi

echo ""

# ---------- [5] epic progress ----------
# Aggregate every PLAN.md under archive + promote by `epic:` field.
# Reports per-epic counters: archived (kind=feature), in promote (kind=feature),
# refactor status (any kind=refactor present?), retirement count (kind=retirement).
# Skips plans without epic.

echo "[epics — progress]"

declare -A EPIC_FEAT_ARCHIVED=()
declare -A EPIC_FEAT_PROMOTE=()
declare -A EPIC_REFACTOR_ARCHIVED=()
declare -A EPIC_REFACTOR_PROMOTE=()
declare -A EPIC_RETIREMENT_DONE=()
declare -A EPIC_SLUGS=()

scan_plan() {
  local plan="$1" loc="$2"
  [[ -f "$plan" ]] || return
  local epic kind
  epic=$(yaml_get "$plan" epic)
  [[ -z "$epic" ]] && return
  kind=$(yaml_get "$plan" kind)
  [[ -z "$kind" ]] && kind="feature"
  EPIC_SLUGS["$epic"]=1
  case "$kind:$loc" in
    feature:archive)    EPIC_FEAT_ARCHIVED["$epic"]=$((${EPIC_FEAT_ARCHIVED["$epic"]:-0}+1)) ;;
    feature:promote)    EPIC_FEAT_PROMOTE["$epic"]=$((${EPIC_FEAT_PROMOTE["$epic"]:-0}+1)) ;;
    refactor:archive)   EPIC_REFACTOR_ARCHIVED["$epic"]=$((${EPIC_REFACTOR_ARCHIVED["$epic"]:-0}+1)) ;;
    refactor:promote)   EPIC_REFACTOR_PROMOTE["$epic"]=$((${EPIC_REFACTOR_PROMOTE["$epic"]:-0}+1)) ;;
    retirement:archive) EPIC_RETIREMENT_DONE["$epic"]=$((${EPIC_RETIREMENT_DONE["$epic"]:-0}+1)) ;;
  esac
}

shopt -s nullglob
for d in "$ARCHIVE_DIR"/*/; do scan_plan "${d}PLAN.md" "archive"; done
for d in "$PROMOTE_DIR"/*/; do scan_plan "${d}PLAN.md" "promote"; done
shopt -u nullglob

if [[ ${#EPIC_SLUGS[@]} -eq 0 ]]; then
  echo "  (no epics — no PLAN.md frontmatter has 'epic:' field)"
else
  # Sort epic slugs for stable output
  for epic in $(printf '%s\n' "${!EPIC_SLUGS[@]}" | LC_ALL=C sort); do
    feat_arc=${EPIC_FEAT_ARCHIVED["$epic"]:-0}
    feat_prm=${EPIC_FEAT_PROMOTE["$epic"]:-0}
    feat_total=$((feat_arc + feat_prm))
    refac_arc=${EPIC_REFACTOR_ARCHIVED["$epic"]:-0}
    refac_prm=${EPIC_REFACTOR_PROMOTE["$epic"]:-0}
    ret_done=${EPIC_RETIREMENT_DONE["$epic"]:-0}

    # State summary
    state=""
    if [[ $feat_prm -gt 0 ]]; then
      state="${feat_arc}/${feat_total} archived, ${feat_prm} in promote"
    else
      state="${feat_arc}/${feat_total} archived"
    fi
    if [[ $refac_arc -gt 0 ]]; then
      state="${state}, refactor done"
    elif [[ $refac_prm -gt 0 ]]; then
      state="${state}, refactor in progress"
    elif [[ $feat_arc -gt 0 && $feat_prm -eq 0 ]]; then
      state="${state}, refactor pending"
    fi
    if [[ $ret_done -gt 0 ]]; then
      state="${state}, ${ret_done} retirement"
    fi

    # Status icon
    icon="·"
    if [[ $refac_arc -gt 0 && $feat_prm -eq 0 ]]; then
      icon="✓"     # epic complete (all features archived + refactor done)
    elif [[ $feat_prm -gt 0 || $refac_prm -gt 0 ]]; then
      icon="…"     # in progress
    elif [[ $feat_arc -gt 0 && $refac_arc -eq 0 ]]; then
      icon="!"     # features all archived but refactor pending
    fi
    echo "  $icon epic $epic: $state"
  done
fi

echo ""

# ---------- [6] PR attachments (orphan branch storage) ----------
echo "[scv-attachments — PR media storage]"
backend="${SCV_ATTACHMENTS_BACKEND:-git-orphan}"
retention="${SCV_ATTACHMENTS_RETENTION_DAYS:-3}"
echo "  backend: $backend · retention: ${retention} day(s)"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  status_line=$(attachments_status 2>/dev/null || echo "active=? stale=? total_size_bytes=?")
  active=$(printf '%s' "$status_line" | sed -n 's/.*active=\([^ ]*\).*/\1/p')
  stale=$(printf '%s' "$status_line" | sed -n 's/.*stale=\([^ ]*\).*/\1/p')
  total=$(printf '%s' "$status_line" | sed -n 's/.*total_size_bytes=\([0-9]*\).*/\1/p')
  total_mb="?"
  if [[ -n "$total" && "$total" =~ ^[0-9]+$ ]]; then
    total_mb=$((total / 1024 / 1024))MB
  fi
  echo "  active: ${active:-?} entries · stale: ${stale:-?} · total: $total_mb"
else
  echo "  (not in a git repo — skipped)"
fi

echo ""
