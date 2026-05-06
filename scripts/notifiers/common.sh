#!/usr/bin/env bash
# Common utilities shared by notifier adapters.
#
# -----------------------------------------------------------------------------
# Adapter contract — each notifier (slack.sh, discord.sh, ...) must implement:
#
#   notifier_validate_env
#     Returns 0 if all required env vars are set, non-zero with stderr msg otherwise.
#
#   notifier_resolve_channel <event>
#     Prints the channel ID to use for the given event (e.g. phase-complete).
#     Falls back to <PROVIDER>_CHANNEL_ID if event-specific override is unset.
#     Returns non-zero if no channel can be resolved.
#
#   notifier_post_message <channel_id> <title> <body>
#     Posts a text/embed message. Prints the thread reference (ts / message id)
#     to stdout on success. Honors $NOTIFIER_DRY_RUN=1 by printing payload to
#     stderr and emitting a synthetic id.
#
#   notifier_upload_file <channel_id> <file_path> <thread_ref> [alt_text]
#     Uploads file as a threaded reply. Returns 0/1. Implemented in Phase 4.
# -----------------------------------------------------------------------------

# Lowercase event → uppercase underscore (phase-complete → PHASE_COMPLETE)
event_to_env_suffix() {
  echo "$1" | tr '[:lower:]-' '[:upper:]_'
}

# Infer event from status if --event not given
infer_event_from_status() {
  case "$1" in
    passed|info) echo "phase-complete" ;;
    failed)      echo "e2e-failure" ;;
    *)           echo "" ;;
  esac
}

is_dry_run() {
  [[ "${NOTIFIER_DRY_RUN:-0}" == "1" ]]
}

dry_run_stderr() {
  echo "=== DRY_RUN: $1 ===" >&2
  shift
  printf '%s\n' "$@" >&2
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "✖ Required command not found: $cmd" >&2
    return 1
  fi
}
