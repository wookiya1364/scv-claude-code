#!/usr/bin/env bash
# Exponential backoff retry.
# Usage: retry <max_attempts> <command...>
# Returns the exit code of the final attempt (0 on success, non-zero if all attempts fail).

retry() {
  local max="${1:-3}"; shift
  local attempt=1 delay=1 rc=0
  while true; do
    if "$@"; then
      return 0
    fi
    rc=$?
    if [[ $attempt -ge $max ]]; then
      return "$rc"
    fi
    echo "… retry $attempt/$max failed (rc=$rc), sleeping ${delay}s" >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}
