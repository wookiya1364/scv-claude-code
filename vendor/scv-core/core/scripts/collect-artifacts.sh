#!/usr/bin/env bash
# Collect artifact file paths for a given status, per TESTING.md rules.
# Prints one absolute path per line to stdout. Silent if no artifacts.
#
# Usage: collect-artifacts.sh <status>
#   status: passed | failed | info
set -euo pipefail

STATUS="${1:-info}"
TR="test-results"

if [[ ! -d "$TR" ]]; then
  exit 0
fi

# Find the most recent matching file (by mtime).
# BSD (macOS) and GNU (Linux) compatible — `find -printf` is GNU-only,
# so we hand the list to `ls -t` which sorts by mtime on both.
_latest() {
  # Usage: _latest <pattern_args...>
  local matches
  # shellcheck disable=SC2068
  matches=$(find "$TR" -maxdepth 6 -type f \( $@ \) 2>/dev/null)
  [[ -z "$matches" ]] && return 0
  printf '%s\n' "$matches" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -n 1
}

SCREENSHOT=$(_latest -name "*.png")
VIDEO=$(_latest -name "*.webm" -o -name "*.mp4")

emit() {
  local f="$1"
  [[ -n "$f" && -f "$f" ]] && echo "$f"
}

case "$STATUS" in
  passed)
    emit "$SCREENSHOT"
    emit "$VIDEO"
    ;;
  info)
    emit "$SCREENSHOT"
    ;;
  failed)
    emit "$SCREENSHOT"
    emit "$VIDEO"
    # Truncated log tail (max 20KB) for failure context.
    LOG=$(_latest -name "*.log")
    if [[ -n "$LOG" && -f "$LOG" ]]; then
      mkdir -p "$TR/.snippets"
      SNIPPET="$TR/.snippets/$(basename "$LOG").tail.txt"
      tail -c 20480 "$LOG" > "$SNIPPET"
      echo "$SNIPPET"
    fi
    ;;
  *)
    emit "$SCREENSHOT"
    ;;
esac
