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
#   SCV_GUARD_SCRIPTS   <dirs>     action-script directories, colon-separated;
#                                  a shell call into any of them mints
#   SCV_GUARD_EXEMPT    <paths>    colon-separated extra exempt paths (host config)
#   SCV_GUARD_RULE_B    off        keep Rule A only
#
# Failure policy: open on two inputs, and only those two — an empty payload, and no
# JSON reader on the machine. Both print one line to stderr and allow. The host
# already proceeds when a hook is missing or times out, so an adversary deletes this
# file rather than corrupting it; closing on unreadable input buys almost nothing,
# while one bug here would deny every write in every project.
#
# The receipt store is the exception and it fails CLOSED — loudly. mint() stays
# best-effort (a broken store must not turn the mint hook into a denial), but a
# mint that cannot record prints one stderr line naming the store, and a gate
# that denies because the store is unusable names the store path and
# SCV_GUARD_STATE in its reason instead of telling the user to run an action —
# running one mints into the same broken store and cannot help. Closed is
# deliberate: a shell tool can chmod the store, and failing open there would
# let one command switch the guard off. Full account in core/contracts/guard.md.

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
#
# The path rule is shared with the stop-hook consumer through scripts/lib. Two
# copies would drift silently, and a drifted path does not fail loudly — it
# reads an empty receipt and quietly stops enforcing. The shared library is an
# optimisation, never a dependency: when it is absent this falls back to the
# identical inline computation, because a missing library must not change what
# this file denies.
_scv_force_lib="${SCV_CORE_ROOT:-$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." 2>/dev/null && pwd )}/scripts/lib/force-help.sh"
if [[ -f "$_scv_force_lib" ]]; then
  # shellcheck disable=SC1090
  source "$_scv_force_lib" 2>/dev/null || true
fi
if declare -F scv_force_project_key >/dev/null 2>&1; then
  PROJECT_KEY="$(scv_force_project_key "$PROJECT_ROOT")"
  RECEIPT="$(scv_force_receipt_file "$STATE_DIR" "$SESSION" "$PROJECT_KEY")"
elif command -v cksum >/dev/null 2>&1; then
  PROJECT_KEY="$(printf '%s' "$PROJECT_ROOT" | cksum | tr -cd '0-9' | cut -c1-12)"
  RECEIPT="$STATE_DIR/${SESSION}-${PROJECT_KEY}"
else
  PROJECT_KEY="$(printf '%s' "$PROJECT_ROOT" | tr -cd '[:alnum:]' | tail -c 24)"
  RECEIPT="$STATE_DIR/${SESSION}-${PROJECT_KEY}"
fi

# Minting stays best-effort — a broken store must not turn the mint hook into
# a denial — but it is no longer silent. Silence was the bug: with nothing
# recorded, has_receipt stays false for the whole session, both rules refuse
# everything, and the deny message used to say "run an action", which mints
# into the same broken store and cannot help.
mint() {
  if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
    notice "receipt store $STATE_DIR cannot be created — no receipt is being recorded (point SCV_GUARD_STATE at a writable directory)"
    return 0
  fi
  { printf '%s\n' "$1" >> "$RECEIPT"; } 2>/dev/null \
    || notice "receipt store $RECEIPT is not writable — no receipt is being recorded (point SCV_GUARD_STATE at a writable directory)"
}
has_receipt() { [[ -s "$RECEIPT" ]]; }
store_usable() {
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  [[ -w "$STATE_DIR" ]] || return 1
  # The directory can be fine while the receipt file itself is not — that
  # shape is just as unusable, and deserves the same honest deny reason.
  [[ ! -e "$RECEIPT" || -w "$RECEIPT" ]]
}

# Why a broken store fails CLOSED: the receipt's absence is what denies, and a
# shell tool can chmod the store — failing open here would let one command
# switch the guard off. The price of closing is paid in candor instead: the
# deny reason below names the store, not the workflow.
STORE_DENY_SUFFIX=""
store_deny_reason() {
  printf 'SCV guard: the receipt store at %s cannot be written, so no action can record itself and every guarded write is refused. This is a machine problem, not a workflow one — fix the directory permissions or point SCV_GUARD_STATE at a writable path.' "$STATE_DIR"
}

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
  # Collapse to one line, strip every remaining control character, then escape
  # backslash and quote. Building the JSON by hand keeps this dependency-free —
  # but the reason is NOT a fixed string: it embeds the payload's own path and
  # environment-derived values, and a raw control character in either would
  # make this output unparseable, which the host treats as no decision at all.
  # An attacker who can name a file can name it with a control character, so
  # the stripping is load-bearing, not cosmetic.
  local msg
  msg="$(printf '%s' "$1" | tr '\n' ' ' | LC_ALL=C tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg"
  exit 0
}

PLAN_FILES='PLAN.md TESTS.md FEATURE_ARCHITECTURE.md'

# ---------- gate-bash: an action script mints; obvious writes are checked ----
if [[ "$MODE" == "gate-bash" ]]; then
  cmd="$(field '.tool_input.command')"
  [[ -n "$cmd" ]] || allow
  # Colon-separated list; each entry keeps the original fixed-string match.
  # One directory was not enough in the field: an adapter's own action scripts
  # live outside the vendored core/scripts, and with a single value the
  # adapter-owned actions could never mint (the contract requires that they
  # can). A fixed string per entry stays deliberate — no globs, no regex, no
  # escaping surface.
  scripts_dirs="${SCV_GUARD_SCRIPTS:-}"
  if [[ -n "$scripts_dirs" ]]; then
    IFS=':' read -r -a _scv_mint_dirs <<< "$scripts_dirs"
    for _scv_dir in "${_scv_mint_dirs[@]}"; do
      # Trim, then require an absolute path. A whitespace-only entry (one
      # stray space in a hand-written list) is a fixed string every command
      # contains — it would mint on anything. A relative entry is a fragment
      # with the same problem. Absolute paths also mean a path that itself
      # contains ':' splits into pieces this filter drops, instead of into
      # loose substrings that match broadly.
      _scv_dir="${_scv_dir#"${_scv_dir%%[![:space:]]*}"}"
      _scv_dir="${_scv_dir%"${_scv_dir##*[![:space:]]}"}"
      [[ "$_scv_dir" == /* ]] || continue
      if printf '%s' "$cmd" | grep -qF -- "$_scv_dir"; then
        mint "script"
        allow
      fi
    done
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
  store_usable || deny "$(store_deny_reason)"
  deny "SCV guard: ${base} may not be created by hand. Run the promote action first — it scaffolds this file, consumes the raw material, and records where the plan came from. A hand-written plan folder looks identical but has no provenance."
done < <(targets)

# ---------- Rule B: writing outside the workflow tree needs a receipt -------
[[ "${SCV_GUARD_RULE_B:-on}" == "off" ]] && allow
has_receipt && allow
store_usable || STORE_DENY_SUFFIX="broken-store"

while IFS= read -r raw; do
  [[ -n "$raw" ]] || continue
  abs="$(abspath "$raw")"
  [[ "$abs" == "$SCV_ROOT"/* ]] && continue
  [[ "$abs" == "$PROJECT_ROOT"/* ]] || continue      # outside the tree: not ours
  rel="${abs#$PROJECT_ROOT/}"
  is_exempt "$rel" && continue
  [[ -n "$STORE_DENY_SUFFIX" ]] && deny "$(store_deny_reason)"
  deny "SCV guard: no SCV action has run in this session, so this edit to ${rel} is not accounted for. Run the work action on a plan, or declare a fast-path change, and this write proceeds. Any SCV action clears the block for the session."
done < <(targets)

allow
