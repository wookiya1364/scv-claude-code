#!/usr/bin/env bash
# Claude adapter around the pinned core sync implementation.
#
# State resolution is read-only by default. An explicit non-dry sync finalizes
# verified legacy migration only after core sync succeeds, pointerizing only
# files that already exist; missing other-host pointers are never created.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_SYNC="$WRAPPER_ROOT/vendor/scv-core/core/scripts/sync.sh"
STATE_INDEX="$WRAPPER_ROOT/adapter/scripts/state-index.sh"
PROJECT_DIR=.
DRY_RUN=0
JOIN_MODE=0

[[ -x "$CORE_SYNC" ]] || {
  echo "ERROR: pinned SCV Core sync entrypoint is unavailable" >&2
  echo "       Run scripts/verify-core.sh from the plugin repository." >&2
  exit 1
}

args=("$@")
index=0
while (( index < ${#args[@]} )); do
  case "${args[$index]}" in
    --project-dir)
      (( index + 1 < ${#args[@]} )) || {
        echo "ERROR: --project-dir requires a path" >&2
        exit 2
      }
      PROJECT_DIR=${args[$((index + 1))]}
      index=$((index + 2))
      ;;
    --force|--id|--role|--workspace)
      (( index + 1 < ${#args[@]} )) || {
        echo "ERROR: ${args[$index]} requires a value" >&2
        exit 2
      }
      index=$((index + 2))
      ;;
    --join)
      (( index + 1 < ${#args[@]} )) || {
        echo "ERROR: --join requires a value" >&2
        exit 2
      }
      JOIN_MODE=1
      index=$((index + 2))
      ;;
    --dry-run)
      DRY_RUN=1
      index=$((index + 1))
      ;;
    -h|--help)
      exec "$CORE_SYNC" "$@"
      ;;
    *)
      index=$((index + 1))
      ;;
  esac
done

[[ -x "$STATE_INDEX" ]] || {
  echo "ERROR: Claude state-index adapter is unavailable" >&2
  exit 1
}

if (( DRY_RUN )); then
  "$STATE_INDEX" --project-dir "$PROJECT_DIR" --dry-run --migrate
  "$CORE_SYNC" "$@"
else
  # Validate legacy/canonical equivalence without writing. The core helper must
  # complete before a legacy file is backed up or replaced with a pointer.
  "$STATE_INDEX" --project-dir "$PROJECT_DIR" --dry-run --migrate
  "$CORE_SYNC" "$@"
  "$STATE_INDEX" \
    --project-dir "$PROJECT_DIR" \
    --migrate \
    --core-sync-succeeded
  if (( JOIN_MODE == 0 )) && [[ -x "$SCRIPT_DIR/apply-model-policy.sh" ]]; then
    echo
    echo "Model policy (from .env SCV_MODEL_POLICY):"
    SCV_PROJECT_DIR="$PROJECT_DIR" \
      "$SCRIPT_DIR/apply-model-policy.sh" --from-env 2>&1 |
      sed 's/^/  /'
  fi
  "$STATE_INDEX" --project-dir "$PROJECT_DIR"
fi
