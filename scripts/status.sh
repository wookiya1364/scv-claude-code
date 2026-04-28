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
