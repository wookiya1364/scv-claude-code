#!/usr/bin/env bash
# bash 4+ required (associative arrays). macOS ships 3.2 — auto-escalate to brew bash.
if (( BASH_VERSINFO[0] < 4 )); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$_b" ]] && exec "$_b" "$0" "$@"
  done
  echo "Error: SCV requires bash 4+. Install via 'brew install bash'." >&2
  exit 1
fi

# Surface project metadata + scv/raw inventory + existing promote/archive
# + raw diff + docs-graph freshness (scripts/graph.sh) for /scv:promote.
# This script is read-only; it only prints context for Claude Code to work with.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
READPATH="$SCRIPT_DIR/readpath.sh"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh"
# shellcheck source=lib/author.sh
source "$SCRIPT_DIR/lib/author.sh"
env_load 2>/dev/null || true

MODE="promote"       # promote | dry-run | graph-only
SCV_TARGET=""

while (( $# )); do
  case "$1" in
    --dry-run)    MODE="dry-run" ;;
    --graph-only) MODE="graph-only" ;;
    --topic)      shift ;;   # value-taking flag: consume its SLUG so the value
                             # is not mistaken for a module target below
    --topic=*)    ;;         # inline form — nothing extra to consume
    -*)           ;;         # other/unknown flags ignored (forward-compat)
    *)
      if [[ -z "$SCV_TARGET" ]] && scv_target_path "$1" >/dev/null 2>&1; then
        SCV_TARGET="$1"
      fi
      ;;
  esac
  shift
done

# Resolve scv/ for this context (optional module target, e.g. `promote FE`).
scv_init_paths "$SCV_TARGET"

echo "MODE: $MODE"
echo "TODAY: $(date +%Y-%m-%d)"

# Author suggestion — unified resolution via lib/author.sh (v0.22.0+):
# git config user.name → $GIT_AUTHOR_NAME → $USER → unknown, slugged for
# filenames. Same signal journal-append.sh and the record protocols use.
AUTHOR="$(scv_author)"
echo "AUTHOR: $AUTHOR"

# Extract STANDARD:VERSION from the shared index or a wrapper-declared legacy
# fallback. The shared index always wins when both exist.
# (marker name kept as STANDARD:* for backward compatibility; internal-only)
SCV_INDEX_PATH="$(scv_state_index_path "$SCV_DIR")"
if [[ -f "$SCV_INDEX_PATH" ]]; then
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
    }' "$SCV_INDEX_PATH")
  echo "STANDARD_VERSION: ${ver:-unknown}"
fi

# SCV 자체 그래프 (v0.51.0+). 낡았으면 여기서 자동으로 다시 만든다(bash+jq, 목표 2초 안).
# jq 가 없으면 unavailable, SCV_GRAPH=off 면 off — 어느 쪽도 이 스크립트를 막지 않는다.
GRAPH_DIR="scv/.graph"
GRAPH_STATUS="$(bash "$SCRIPT_DIR/graph.sh" ensure 2>/dev/null | sed -n 's/^GRAPH_STATUS: //p' | head -1)"
[[ -n "$GRAPH_STATUS" ]] || GRAPH_STATUS="unavailable"
echo "GRAPH_STATUS: $GRAPH_STATUS"
[[ "$GRAPH_STATUS" == "built" ]] && echo "GRAPH_DIR: $GRAPH_DIR"
# Graft 어댑터 (v0.51.0+, 선택): 있으면 ready — 계획 제목이 정해진 뒤 graft.sh ask 로 후보를 볼 수 있다.
_graft_out="$(bash "$SCRIPT_DIR/graft.sh" status 2>/dev/null)"
_graft="$(printf '%s\n' "$_graft_out" | sed -n 's/^GRAFT_STATUS: //p' | head -1)"
echo "GRAFT_STATUS: ${_graft:-absent}"
# 안내 한 줄 (0.55.0) — graft.sh 가 낸 그대로. 문구는 lib/graft.sh 한 곳.
printf '%s\n' "$_graft_out" | grep '^GRAFT_NOTICE: ' | head -1

# Graph-only mode: stop here after ensuring the graph (the graph is built above; nothing to decide).
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
    [[ "${f##*/}" == ".gitkeep" ]] && continue
    # Consumed docs live under stale/ — they are not promote sources by
    # default and must not inflate the split heuristic. Listed separately below.
    [[ "$f" == "$RAW_DIR/stale/"* ]] && continue
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
# Triggers when raw scope looks "big enough" to warrant a multi-way split:
#   raw_files > 7  OR  topic_clusters >= 3
# The actual split count is content-driven — Claude Code judges each topic cluster
# and proposes a number (could be 2, 3, 8, whatever fits) in the user question.
# This is a hint only (see references/protocols/promote.md Step 3).
SUGGEST_SPLIT="no"
SPLIT_REASON=""
if [[ $RAW_FILE_COUNT -gt 7 ]]; then
  SUGGEST_SPLIT="yes"
  SPLIT_REASON="${RAW_FILE_COUNT} raw files (>7 threshold)"
fi
if [[ $RAW_TOPDIR_COUNT -ge 3 ]]; then
  SUGGEST_SPLIT="yes"
  if [[ -n "$SPLIT_REASON" ]]; then
    SPLIT_REASON="$SPLIT_REASON, ${RAW_TOPDIR_COUNT} topic clusters (>=3)"
  else
    SPLIT_REASON="${RAW_TOPDIR_COUNT} topic clusters (>=3)"
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
echo "=== scv/raw/stale (consumed docs) ==="
RAW_STALE_COUNT=0
if [[ -x "$READPATH" ]]; then
  STALE_REFS=$(RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" refs 2>/dev/null || true)
  if [[ -n "$STALE_REFS" ]]; then
    while IFS=$'\t' read -r p slugs _cmt _at; do
      [[ -z "$p" ]] && continue
      RAW_STALE_COUNT=$((RAW_STALE_COUNT + 1))
      echo "- $p  ← ${slugs:-?}"
    done <<< "$STALE_REFS"
  else
    echo "(none)"
  fi
else
  echo "(readpath.sh unavailable)"
fi
echo ""
echo "RAW_STALE_COUNT: $RAW_STALE_COUNT"

# Content staleness of consumed docs (heuristic; Claude Code verifies
# semantically before reusing a flagged doc as a promote source).
RAW_OUTDATED_COUNT=0
if [[ -x "$READPATH" && $RAW_STALE_COUNT -gt 0 ]]; then
  OUTDATED_OUT=$(RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" outdated 2>/dev/null || true)
  OC_LINES=$(printf '%s\n' "$OUTDATED_OUT" | grep -E '^OUTDATED-CANDIDATE	' || true)
  if [[ -n "$OC_LINES" ]]; then
    RAW_OUTDATED_COUNT=$(printf '%s\n' "$OC_LINES" | grep -c .)
  fi
fi
echo "RAW_OUTDATED_COUNT: $RAW_OUTDATED_COUNT"
if [[ $RAW_OUTDATED_COUNT -gt 0 ]]; then
  echo "=== outdated candidates (verify against current code before reuse) ==="
  printf '%s\n' "$OC_LINES"
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
