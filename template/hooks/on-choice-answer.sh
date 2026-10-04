#!/usr/bin/env bash
# on-choice-answer.sh — host hook template (SCV Core, v0.65.0+).
#
# Purpose: the user just answered the host's choice tool (contracts/choices.md) in
# the middle of a turn. An answer can change what the turn is about, so the
# rewritten request registered before it may be stale. Record that the answer came
# after the turn's last registration; the write gate (guard Rule P) then asks for a
# fresh registration — or a one-line `register --keep` when the scope is unchanged —
# before the next editor write.
#
# Contract (see docs/wrapper-integration.md §6 "Hook seam" in scv-core):
#   - Registration is WRAPPER-OWNED: register this template for the event that
#     fires after the host's choice tool returns the user's answer (for a host
#     with hook events per tool, the post-tool event matched to that tool). A host
#     without a choice tool registers nothing — the gate then never asks for this.
#   - stdin carries ONE JSON object; `session_id` (whose turn) and `agent_id`
#     (present only inside a subagent — ignored) are read. Nothing else.
#   - The wrapper should export SCV_CORE_ROOT; without it, the template falls back
#     to its in-payload location.
#
# NON-BLOCKING GUARANTEE: this hook never fails or blocks the session — invalid
# JSON, missing jq, no turn, switch off, or an un-hydrated project → exit 0 with
# nothing written and nothing printed.
set -u

[[ -d scv ]] || exit 0
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
_scv_mp="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}/scripts/model-prompting.sh"
[[ -f "$_scv_mp" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(head -c 1048576 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0
_scv_sid="$(printf '%s' "$INPUT" | jq -r 'try (.session_id // empty)' 2>/dev/null || true)"
_scv_agent="$(printf '%s' "$INPUT" | jq -r 'try (.agent_id // empty)' 2>/dev/null || true)"
[[ -z "$_scv_agent" ]] || exit 0

if [[ -n "$_scv_sid" ]]; then
  bash "$_scv_mp" answered --session "$_scv_sid" >/dev/null 2>&1 || true
else
  bash "$_scv_mp" answered >/dev/null 2>&1 || true
fi
exit 0
