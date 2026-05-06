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
_latest() {
  # Usage: _latest <pattern_args...>
  # shellcheck disable=SC2068
  find "$TR" -maxdepth 6 -type f \( $@ \) -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -n 1 | cut -d' ' -f2-
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
