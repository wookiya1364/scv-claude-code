#!/usr/bin/env bash
# Surface project metadata + scv/raw inventory + existing promote/archive
# + raw diff + graphify skill availability for /scv:promote.
# This script is read-only; it only prints context for Claude to work with.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
READPATH="$SCRIPT_DIR/readpath.sh"

RAW_DIR="${RAW_DIR:-scv/raw}"
PROMOTE_DIR="${PROMOTE_DIR:-scv/promote}"
ARCHIVE_DIR="${ARCHIVE_DIR:-scv/archive}"
STATE_FILE="${STATE_FILE:-scv/readpath.json}"

MODE="promote"       # promote | dry-run | graph-only

for a in "$@"; do
  case "$a" in
    --dry-run)    MODE="dry-run" ;;
    --graph-only) MODE="graph-only" ;;
  esac
done

echo "MODE: $MODE"
echo "TODAY: $(date +%Y-%m-%d)"

# Author suggestion: git config user.name → lowercase, spaces → dashes
AUTHOR=""
if command -v git >/dev/null 2>&1; then
  raw_name=$(git config user.name 2>/dev/null || true)
  if [[ -n "$raw_name" ]]; then
    AUTHOR=$(printf '%s' "$raw_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-_')
  fi
fi
[[ -z "$AUTHOR" ]] && AUTHOR="unknown"
echo "AUTHOR: $AUTHOR"

# Extract STANDARD:VERSION value from scv/CLAUDE.md if present
# (marker name kept as STANDARD:* for backward compatibility; internal-only)
if [[ -f scv/CLAUDE.md ]]; then
  ver=$(awk '
    {
      s = index($0, "<!-- STANDARD:VERSION -->")
      if (s > 0) {
        rest = substr($0, s + length("<!-- STANDARD:VERSION -->"))
        e = index(rest, "<!-- /STANDARD:VERSION -->")
        if (e > 0) {
          print substr(rest, 1, e - 1)
          exit
        }
      }
    }' scv/CLAUDE.md)
  echo "STANDARD_VERSION: ${ver:-unknown}"
fi

# Graphify skill availability (best-effort check — user/global skill dir)
GRAPHIFY_SKILL="missing"
for candidate in \
  "$HOME/.claude/skills/graphify/SKILL.md" \
  "$HOME/.claude/plugins/cache/"*/skills/graphify/SKILL.md; do
  if [[ -f "$candidate" ]]; then
    GRAPHIFY_SKILL="available"
    break
  fi
done
echo "GRAPHIFY_SKILL: $GRAPHIFY_SKILL"

# Graph status: compare .graphify/docs/graphify-out/ mtime vs readpath.json mtime
GRAPH_STATUS="n/a"
if [[ "$GRAPHIFY_SKILL" == "available" ]]; then
  GRAPH_DIR=".graphify/docs/graphify-out"
  if [[ ! -d "$GRAPH_DIR" ]]; then
    GRAPH_STATUS="missing"
  elif [[ ! -f "$STATE_FILE" ]]; then
    # No readpath yet — if graph exists, consider it fresh (nothing to compare)
    GRAPH_STATUS="built"
  else
    # Compare mtimes
    graph_mt=$(stat -c %Y "$GRAPH_DIR" 2>/dev/null || echo 0)
    state_mt=$(stat -c %Y "$STATE_FILE" 2>/dev/null || echo 0)
    if [[ "$graph_mt" -ge "$state_mt" ]]; then
      GRAPH_STATUS="built"
    else
      GRAPH_STATUS="stale"
    fi
  fi
fi
echo "GRAPH_STATUS: $GRAPH_STATUS"

# Graph-only mode: stop here after emitting metadata. Claude then decides
# whether to invoke the graphify skill based on GRAPH_STATUS + GRAPHIFY_SKILL.
if [[ "$MODE" == "graph-only" ]]; then
  exit 0
fi

echo ""
echo "=== scv/raw inventory ==="
RAW_FILE_COUNT=0
RAW_TOPDIR_COUNT=0
declare -A RAW_TOPDIRS=()
if [[ -d "$RAW_DIR" ]]; then
  found=0
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    [[ "$f" == "$RAW_DIR/README.md" ]] && continue
    found=1
    RAW_FILE_COUNT=$((RAW_FILE_COUNT + 1))
    # Track top-level subdirs of scv/raw/ as a cheap "topic cluster" signal.
    # E.g. scv/raw/2026-04-24-meeting/notes.md → topic=2026-04-24-meeting
    rel="${f#$RAW_DIR/}"
    if [[ "$rel" == */* ]]; then
      top="${rel%%/*}"
      RAW_TOPDIRS["$top"]=1
    else
      RAW_TOPDIRS["__root__"]=1
    fi
    size=$(wc -c <"$f" 2>/dev/null | tr -d ' ' || echo '?')
    mt=$(date -r "$f" +%Y-%m-%d 2>/dev/null || echo '?')
    echo "- $f  (${size}B, modified $mt)"
  done < <(find "$RAW_DIR" -type f 2>/dev/null | LC_ALL=C sort)
  [[ $found -eq 0 ]] && echo "(empty)"
  RAW_TOPDIR_COUNT=${#RAW_TOPDIRS[@]}
else
  echo "($RAW_DIR does not exist — nothing to promote)"
fi

# Split-suggestion heuristic
# Triggers when raw scope looks "big enough" to warrant 5~7 way split:
#   raw_files > 7  OR  topic_clusters >= 3
# This is a hint only — Claude must still confirm with AskUserQuestion (see commands/promote.md Step 3).
SUGGEST_SPLIT="no"
SPLIT_REASON=""
if [[ $RAW_FILE_COUNT -gt 7 ]]; then
  SUGGEST_SPLIT="yes"
  SPLIT_REASON="raw 파일 ${RAW_FILE_COUNT}개 (>7 임계치)"
fi
if [[ $RAW_TOPDIR_COUNT -ge 3 ]]; then
  SUGGEST_SPLIT="yes"
  if [[ -n "$SPLIT_REASON" ]]; then
    SPLIT_REASON="$SPLIT_REASON, 토픽 클러스터 ${RAW_TOPDIR_COUNT}개 (>=3)"
  else
    SPLIT_REASON="토픽 클러스터 ${RAW_TOPDIR_COUNT}개 (>=3)"
  fi
fi
echo ""
echo "RAW_FILE_COUNT: $RAW_FILE_COUNT"
echo "RAW_TOPIC_CLUSTERS: $RAW_TOPDIR_COUNT"
echo "SUGGEST_SPLIT: $SUGGEST_SPLIT"
if [[ -n "$SPLIT_REASON" ]]; then
  echo "SPLIT_REASON: $SPLIT_REASON"
fi

echo ""
echo "=== scv/raw changes since last index ==="
if [[ -x "$READPATH" && -d "$RAW_DIR" ]]; then
  RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" diff || true
  # Also print a summary line
  RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" status-counts
else
  echo "(readpath.sh unavailable or raw dir missing)"
fi

echo ""
echo "=== existing promote folders ==="
if [[ -d "$PROMOTE_DIR" ]]; then
  found=0
  for m in "$PROMOTE_DIR"/*.md; do
    [[ -f "$m" ]] || continue
    found=1
    echo "- $m"
  done
  for d in "$PROMOTE_DIR"/*/; do
    [[ -d "$d" ]] || continue
    if [[ -f "${d}PLAN.md" ]]; then
      found=1
      # Extract title from frontmatter if present
      title=$(awk '/^title:/{sub(/^title: */, ""); gsub(/"/, ""); print; exit}' "${d}PLAN.md" 2>/dev/null)
      if [[ -n "$title" ]]; then
        echo "- ${d}PLAN.md  — $title"
      else
        echo "- ${d}PLAN.md"
      fi
    elif [[ -f "${d}index.md" ]]; then
      found=1
      echo "- ${d}index.md"
    fi
  done
  [[ $found -eq 0 ]] && echo "(none)"
else
  echo "($PROMOTE_DIR does not exist)"
fi

echo ""
echo "=== existing archive folders ==="
if [[ -d "$ARCHIVE_DIR" ]]; then
  archived=0
  for d in "$ARCHIVE_DIR"/*/; do
    [[ -d "$d" ]] || continue
    archived=$((archived+1))
    echo "- $d"
  done
  [[ $archived -eq 0 ]] && echo "(empty)"
else
  echo "($ARCHIVE_DIR does not exist)"
fi
