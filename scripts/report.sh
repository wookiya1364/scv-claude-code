#!/usr/bin/env bash
# /scv:report entry point.
# Usage: report.sh "<phase>" <status> [--summary "TEXT"] [--attempt N] [--event EVENT]
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/retry.sh
source "$SCRIPT_DIR/lib/retry.sh"
# shellcheck source=notifiers/common.sh
source "$SCRIPT_DIR/notifiers/common.sh"

usage() {
  cat <<'EOF'
Usage: report.sh "<phase-name>" <status> [options]

Arguments:
  phase-name    Quoted if it contains spaces (e.g. "Phase 2 — voice core")
  status        passed | failed | info

Options:
  --summary "TEXT"   Human-readable summary (failure cause or success highlights)
  --attempt N        Attempt count (default 1)
  --event EVENT      Force a specific event (phase-complete | e2e-failure | daily-summary | error-alert)

Env (from project .env):
  NOTIFIER_PROVIDER            slack | discord (required)
  <PROVIDER>_BOT_TOKEN         authentication
  <PROVIDER>_CHANNEL_ID*       channel routing
  NOTIFIER_DRY_RUN=1           skip API calls, print payloads to stderr
EOF
}

# --- Parse positional args ---------------------------------------------------
if [[ $# -lt 2 ]]; then
  usage >&2
  exit 1
fi

PHASE="$1"; shift
STATUS="$1"; shift

case "$STATUS" in
  passed|failed|info) ;;
  -h|--help) usage; exit 0 ;;
  *)
    echo "✖ Invalid status: $STATUS (expected passed | failed | info)" >&2
    exit 1
    ;;
esac

SUMMARY=""
ATTEMPT=1
EVENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary) SUMMARY="$2"; shift 2 ;;
    --attempt) ATTEMPT="$2"; shift 2 ;;
    --event)   EVENT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "✖ Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# --- Load env + choose notifier ---------------------------------------------
env_load

if [[ -z "${NOTIFIER_PROVIDER:-}" ]]; then
  echo "✖ NOTIFIER_PROVIDER not set in .env (use: slack | discord)" >&2
  exit 1
fi

ADAPTER="$SCRIPT_DIR/notifiers/${NOTIFIER_PROVIDER}.sh"
if [[ ! -f "$ADAPTER" ]]; then
  echo "✖ Unknown NOTIFIER_PROVIDER: $NOTIFIER_PROVIDER (no adapter at $ADAPTER)" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ADAPTER"

notifier_validate_env || exit 1

# --- Resolve event + channel -------------------------------------------------
[[ -z "$EVENT" ]] && EVENT=$(infer_event_from_status "$STATUS")
if [[ -z "$EVENT" ]]; then
  echo "✖ Cannot determine event for status='$STATUS'. Pass --event EVENT explicitly." >&2
  exit 1
fi

CHANNEL=$(notifier_resolve_channel "$EVENT") || exit 1

# --- Collect render inputs ---------------------------------------------------
: "${PROJECT_NAME:=$(basename "$PWD")}"
GIT_SHORT="n/a"
if command -v git >/dev/null 2>&1 && git rev-parse --short HEAD >/dev/null 2>&1; then
  GIT_SHORT=$(git rev-parse --short HEAD)
fi

# Duration from test-results/results.json if present
DURATION="n/a"
if [[ -f "test-results/results.json" ]]; then
  secs=$(jq -r '.stats.duration // empty' test-results/results.json 2>/dev/null || true)
  if [[ -n "$secs" ]]; then
    secs_int=$(printf '%.0f' "$(echo "$secs / 1000" | bc -l 2>/dev/null || echo 0)")
    if [[ "$secs_int" -gt 0 ]]; then
      DURATION="$((secs_int / 60))m $((secs_int % 60))s"
    fi
  fi
fi

export PHASE STATUS ATTEMPT SUMMARY GIT_SHORT DURATION
export PROJECT="$PROJECT_NAME"
export DISCORD_STATUS_HINT="$STATUS"   # informs discord.sh color

RENDERED=$(bash "$SCRIPT_DIR/render-template.sh")
TITLE=$(echo "$RENDERED" | jq -r '.title')
BODY=$(echo "$RENDERED" | jq -r '.body')

# --- Post message ------------------------------------------------------------
THREAD_REF=$(notifier_post_message "$CHANNEL" "$TITLE" "$BODY") || {
  echo "ERROR post_message_failed" >&2
  exit 1
}

# --- Collect + upload artifacts (threaded) -----------------------------------
UPLOAD_COUNT=0
UPLOAD_FAIL=0
RETRY_MAX="${NOTIFIER_RETRY_MAX:-3}"

if [[ -d "test-results" ]]; then
  ARTIFACTS=$("$SCRIPT_DIR/collect-artifacts.sh" "$STATUS" || true)
  if [[ -n "$ARTIFACTS" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      [[ ! -f "$f" ]] && continue
      if retry "$RETRY_MAX" notifier_upload_file "$CHANNEL" "$f" "$THREAD_REF"; then
        UPLOAD_COUNT=$((UPLOAD_COUNT + 1))
      else
        UPLOAD_FAIL=$((UPLOAD_FAIL + 1))
        echo "⚠  Artifact upload failed after $RETRY_MAX attempts: $f" >&2
        # Queue for later retry
        mkdir -p "test-results/report-queue"
        qfile="test-results/report-queue/$(date +%s)-$(basename "$f").json"
        jq -n --arg c "$CHANNEL" --arg p "$f" --arg t "$THREAD_REF" --arg prov "$NOTIFIER_PROVIDER" \
          '{provider:$prov, channel:$c, file:$p, thread_ref:$t, queued_at:(now|todate)}' > "$qfile"
      fi
    done <<< "$ARTIFACTS"
  fi
fi

if [[ $UPLOAD_COUNT -gt 0 ]]; then
  echo "  → uploaded $UPLOAD_COUNT artifact(s) to thread" >&2
fi

echo "OK $THREAD_REF"
