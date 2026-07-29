#!/usr/bin/env bash
# Delegate shared state-index semantics to the pinned, host-neutral Core.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WRAPPER_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
CORE_STATE_INDEX="$WRAPPER_ROOT/vendor/scv-core/core/scripts/state-index.sh"

[[ -x "$CORE_STATE_INDEX" ]] || {
  echo "ERROR: vendored Core state-index resolver is missing: $CORE_STATE_INDEX" >&2
  exit 1
}

exec "$CORE_STATE_INDEX" "$@"
