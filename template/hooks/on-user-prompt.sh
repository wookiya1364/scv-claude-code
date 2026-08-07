#!/usr/bin/env bash
# on-user-prompt.sh — host hook template (SCV Core, v0.22.0+).
#
# Purpose: capture EVERY user prompt (free conversation included — turns that
# never invoke an action:*) into the committed team journal.
#
# Contract (see docs/wrapper-integration.md §6 "Hook seam" in scv-core):
#   - The host agent's user-prompt-submit hook event (e.g. the event named
#     `UserPromptSubmit`) pipes ONE JSON object to stdin containing a `prompt`
#     string field. This template extracts `.prompt` and appends it via
#     journal-append.sh, whose redaction filter runs BEFORE anything is
#     written (password/token/secret/api-key/Bearer/AKIA → [REDACTED]).
#   - Registration/installation is WRAPPER-OWNED — Core ships only this
#     template and the contract (same ownership boundary as update/set-models).
#   - The wrapper should export SCV_CORE_ROOT (the materialized core/ dir);
#     without it, the template falls back to its in-payload location.
#
# NON-BLOCKING GUARANTEE: this hook never fails the session. Invalid JSON,
# empty prompt, missing jq/python3, or an un-hydrated project → exit 0, no
# write. Wrappers copying this template must preserve that guarantee.
set -u

# Un-hydrated / non-SCV project → nothing to journal.
[[ -d scv ]] || exit 0

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
JOURNAL_APPEND="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}/scripts/journal-append.sh"
[[ -f "$JOURNAL_APPEND" ]] || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

PROMPT=""
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$INPUT" | jq -r 'try (.prompt // empty)' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    p = d.get("prompt", "")
    sys.stdout.write(p if isinstance(p, str) else "")
except Exception:
    pass' 2>/dev/null || true)"
fi
[[ -n "$PROMPT" ]] || exit 0   # invalid JSON or no prompt → quietly skip

printf '%s\n' "$PROMPT" | bash "$JOURNAL_APPEND" --speaker user >/dev/null 2>&1 || true
exit 0
