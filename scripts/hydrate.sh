#!/usr/bin/env bash
# Claude adapter around the pinned core hydrate implementation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_HYDRATE="$WRAPPER_ROOT/vendor/scv-core/core/scripts/hydrate.sh"
STATE_INDEX="$WRAPPER_ROOT/adapter/scripts/state-index.sh"

[[ -x "$CORE_HYDRATE" ]] || {
  echo "ERROR: pinned SCV Core hydrate entrypoint is unavailable" >&2
  echo "       Run scripts/verify-core.sh from the plugin repository." >&2
  exit 1
}
[[ -x "$STATE_INDEX" ]] || {
  echo "ERROR: Claude state-index adapter is unavailable" >&2
  exit 1
}
target=
if [[ "${1:-}" == init && -n "${2:-}" ]]; then
  target=$2
fi

"$CORE_HYDRATE" "$@"

[[ -n "$target" ]] || exit 0
target="$(cd "$target" 2>/dev/null && pwd)" || {
  echo "ERROR: hydrated target cannot be resolved: $target" >&2
  exit 1
}
"$STATE_INDEX" --project-dir "$target" >/dev/null
