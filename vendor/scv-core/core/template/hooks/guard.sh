#!/usr/bin/env bash
# Workspace guard — deny writes that no SCV action accounts for.
#
# Contract: core/contracts/guard.md. Read it before changing any rule here; the
# consistency test in the repo's tests/ reads the same file and fails when this
# script and the shipped documents disagree.
#
# Registration is the wrapper's job. It passes SCV_GUARD_MODE per hook entry so
# this file never names a host, an event, or a tool:
#
#   SCV_GUARD_MODE=mint        an action is starting — record a receipt, never deny
#   SCV_GUARD_MODE=gate-write  an editor-style write — may deny
#   SCV_GUARD_MODE=gate-bash   a shell command — mints on an action script, else may deny
#
# Optional environment, all supplied by the wrapper:
#   SCV_GUARD           off        disable entirely (process env only — never a file,
#                                  or the agent could exempt itself in one line)
#   SCV_GUARD_STATE     <dir>      where receipts live; defaults under the temp dir
#   SCV_GUARD_ACTIONS   <regex>    action ids the host may report (mint mode)
#   SCV_GUARD_SCRIPTS   <dir>      action scripts; a shell call into it mints
#   SCV_GUARD_EXEMPT    <paths>    colon-separated extra exempt paths (host config)
#   SCV_GUARD_RULE_B    off        keep Rule A only
#
# Failure policy: open. Any internal problem allows the action and prints one line
# to stderr. The host already proceeds when a hook is missing or times out, so an
# adversary deletes this file rather than corrupting it — closing on internal error
# buys almost nothing, while one bug here would deny every write in every project.
# Only an explicit rule match denies.

set -uo pipefail

allow()  { exit 0; }
notice() { printf 'scv-guard: %s\n' "$1" >&2; }
give_up() { notice "$1 — allowing"; exit 0; }

[[ "${SCV_GUARD:-}" == "off" ]] && allow

MODE="${SCV_GUARD_MODE:-gate-write}"

PAYLOAD="$(cat 2>/dev/null || true)"
[[ -n "$PAYLOAD" ]] || give_up "empty payload"

# ---------- payload reading -------------------------------------------------
# jq when present, python otherwise. Both are optional: with neither, allow.
if command -v jq >/dev/null 2>&1; then
  field() { printf '%s' "$PAYLOAD" | jq -r "$1 // empty" 2>/dev/null; }
elif command -v python3 >/dev/null 2>&1; then
  field() {
    printf '%s' "$PAYLOAD" | python3 -c '
import json, sys
path = sys.argv[1].lstrip(".").split(".")
try:
    cur = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for key in path:
    if not isinstance(cur, dict) or key not in cur:
        sys.exit(0)
    cur = cur[key]
if cur is None:
    sys.exit(0)
print(cur if isinstance(cur, str) else json.dumps(cur))
' "$1" 2>/dev/null
  }
else
  give_up "no JSON reader available"
fi

CWD="$(field '.cwd')"
[[ -n "$CWD" && -d "$CWD" ]] || CWD="$PWD"

# ---------- scope gate: inert wherever SCV is not adopted -------------------
# Walk up from the payload's directory. Testing `-d scv` against the current
# directory instead would silently disable the guard for any caller one level
# down, which is the failure a path-based check invites.
find_root() {
  local dir="$1"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    for name in scv .scv; do
      if [[ -d "$dir/$name" ]] \
         && [[ -d "$dir/$name/promote" || -d "$dir/$name/archive" \
            || -d "$dir/$name/raw" || -f "$dir/$name/PROMOTE.md" ]]; then
        printf '%s' "$dir/$name"; return 0
      fi
    done
    dir="$(dirname "$dir")"
  done
  return 1
}
SCV_ROOT="$(find_root "$CWD" || true)"
[[ -n "$SCV_ROOT" ]] || allow
PROJECT_ROOT="$(dirname "$SCV_ROOT")"

# ---------- receipts --------------------------------------------------------
STATE_DIR="${SCV_GUARD_STATE:-${TMPDIR:-/tmp}/scv-guard}"
SESSION="$(field '.session_id')"
[[ -n "$SESSION" ]] || SESSION="nosession"
# One receipt per (session, project): a receipt earned in one checkout must not
# unlock a different one.
if command -v cksum >/dev/null 2>&1; then
  PROJECT_KEY="$(printf '%s' "$PROJECT_ROOT" | cksum | tr -cd '0-9' | cut -c1-12)"
else
  PROJECT_KEY="$(printf '%s' "$PROJECT_ROOT" | tr -cd '[:alnum:]' | tail -c 24)"
fi
RECEIPT="$STATE_DIR/${SESSION}-${PROJECT_KEY}"

mint() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  printf '%s\n' "$1" >> "$RECEIPT" 2>/dev/null || true
}
has_receipt() { [[ -s "$RECEIPT" ]]; }

ACTIONS_RE="${SCV_GUARD_ACTIONS:-help|status|promote|work|codegen|deck|update|regression|report|sync|install-deps|workspace|handoff|set-models|routine}"

# ---------- mint mode: an action is starting --------------------------------
if [[ "$MODE" == "mint" ]]; then
  reported="$(field '.tool_input.skill')"
  [[ -n "$reported" ]] || reported="$(field '.command_name')"
  [[ -n "$reported" ]] || reported="$(field '.tool_input.command_name')"
  if [[ -n "$reported" ]]; then
    # Hosts spell the id with their own prefix; match the id itself.
    if printf '%s' "$reported" | grep -qE "(^|[^a-z-])(${ACTIONS_RE})([^a-z-]|$)"; then
      mint "$reported"
    fi
  fi
  allow
fi

# ---------- path extraction -------------------------------------------------
# Editor-style tools name the file. Patch-style tools do not: the whole patch
# arrives as one command string, and the target only appears inside it.
targets() {
  local p
  for key in '.tool_input.file_path' '.tool_input.path' '.tool_input.notebook_path'; do
    p="$(field "$key")"
    [[ -n "$p" ]] && printf '%s\n' "$p"
  done
  local cmd; cmd="$(field '.tool_input.command')"
  # Three separate expressions, not one alternation: BSD sed has no \| in a basic
  # regex, so the GNU form matched nothing on macOS and every patch sailed past
  # both rules while the Linux job stayed green.
  [[ -n "$cmd" ]] && printf '%s\n' "$cmd" | sed -n \
    -e 's/^\*\*\* Add File: //p' \
    -e 's/^\*\*\* Update File: //p' \
    -e 's/^\*\*\* Delete File: //p'
}

abspath() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *)  printf '%s/%s' "${CWD%/}" "$1" ;;
  esac
}

is_exempt() {
  local rel="$1"
  case "$rel" in
    *.md|.gitignore|.gitattributes|LICENSE) return 0 ;;
    */.gitignore|*/.gitattributes|*/LICENSE) return 0 ;;
  esac
  local extra="${SCV_GUARD_EXEMPT:-}"
  if [[ -n "$extra" ]]; then
    local IFS=':'
    for e in $extra; do
      [[ -n "$e" && "$rel" == $e ]] && return 0
    done
  fi
  return 1
}

deny() {
  # Collapse to one line, then escape only backslash and quote. Building the JSON
  # by hand keeps this dependency-free; the reasons are fixed strings from this
  # file, never user input.
  local msg
  msg="$(printf '%s' "$1" | tr '\n' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg"
  exit 0
}

PLAN_FILES='PLAN.md TESTS.md FEATURE_ARCHITECTURE.md'

# ---------- gate-bash: an action script mints; obvious writes are checked ----
if [[ "$MODE" == "gate-bash" ]]; then
  cmd="$(field '.tool_input.command')"
  [[ -n "$cmd" ]] || allow
  scripts_dir="${SCV_GUARD_SCRIPTS:-}"
  if [[ -n "$scripts_dir" ]] && printf '%s' "$cmd" | grep -qF -- "$scripts_dir"; then
    mint "script"
    allow
  fi
  # A patch delivered through a shell tool still names its target.
  :
fi

# ---------- Rule A: creating a plan file needs a receipt --------------------
while IFS= read -r raw; do
  [[ -n "$raw" ]] || continue
  abs="$(abspath "$raw")"
  base="${abs##*/}"
  case " $PLAN_FILES " in
    *" $base "*) ;;
    *) continue ;;
  esac
  # Only inside the workflow tree, and only creation.
  [[ "$abs" == "$SCV_ROOT/promote/"* ]] || continue
  [[ -e "$abs" ]] && continue
  has_receipt && continue
  deny "SCV guard: ${base} may not be created by hand. Run the promote action first — it scaffolds this file, consumes the raw material, and records where the plan came from. A hand-written plan folder looks identical but has no provenance."
done < <(targets)

# ---------- Rule B: writing outside the workflow tree needs a receipt -------
[[ "${SCV_GUARD_RULE_B:-on}" == "off" ]] && allow
has_receipt && allow

while IFS= read -r raw; do
  [[ -n "$raw" ]] || continue
  abs="$(abspath "$raw")"
  [[ "$abs" == "$SCV_ROOT"/* ]] && continue
  [[ "$abs" == "$PROJECT_ROOT"/* ]] || continue      # outside the tree: not ours
  rel="${abs#$PROJECT_ROOT/}"
  is_exempt "$rel" && continue
  deny "SCV guard: no SCV action has run in this session, so this edit to ${rel} is not accounted for. Run the work action on a plan, or declare a fast-path change, and this write proceeds. Any SCV action clears the block for the session."
done < <(targets)

allow
