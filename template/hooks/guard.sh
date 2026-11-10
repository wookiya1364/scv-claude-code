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
#   SCV_GUARD_MODE=gate-any    any tool (0.80.0+) — refuses every tool until this person's turn
#                              has called help (Rule H); never mints, never checks paths
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
#   SCV_HELP_FIRST_ALLOW <regex>   tool names Rule H lets through before help (host tools — the
#                                  wrapper names them; core never does)
#   SCV_GUARD_RULE_D    off        skip the function-declaration check (Rule D, 0.81.0+)
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
if command -v cksum >/dev/null 2>&1; then
  PROJECT_KEY="$(printf '%s' "$PROJECT_ROOT" | cksum | tr -cd '0-9' | cut -c1-12)"
else
  PROJECT_KEY="$(printf '%s' "$PROJECT_ROOT" | tr -cd '[:alnum:]' | tail -c 24)"
fi
RECEIPT="$STATE_DIR/${SESSION}-${PROJECT_KEY}"

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

ACTIONS_RE="${SCV_GUARD_ACTIONS:-help|status|promote|work|codegen|deck|update|regression|report|sync|install-deps|workspace|handoff|set-models|routine|dreams|mods-install|mods-remove|mods|channel}"

# ---------- help mark (0.80.0+) ---------------------------------------------
# Rule H needs to know that this person's turn has called help (or carried another SCV action).
# The decision and the turn record live in model-prompting.sh (helped / help-gate); this file only
# reports the moment an action starts. Best-effort: a failure here records nothing and denies nothing.
_scv_mp_dir="${SCV_GUARD_SCRIPTS:-}"; _scv_mp_dir="${_scv_mp_dir%%:*}"
[[ -n "$_scv_mp_dir" ]] || _scv_mp_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" 2>/dev/null && pwd)"
_scv_mp_sid="$(field '.session_id')"
_scv_mp_agent="$(field '.agent_id')"
mp_run() {
  [[ -f "$_scv_mp_dir/model-prompting.sh" && -d "$PROJECT_ROOT" ]] || return 0
  local -a a=("$@" --agent "$_scv_mp_agent")
  [[ -n "$_scv_mp_sid" ]] && a+=(--session "$_scv_mp_sid")
  (cd "$PROJECT_ROOT" && bash "$_scv_mp_dir/model-prompting.sh" "${a[@]}" 2>/dev/null | head -c 2048) || true
}
help_mark() { mp_run helped >/dev/null; }

# ---------- turn plan check (0.87.0+) ----------------------------------------
# 턴 끝 계획 기록 검사(scripts/turn-check.sh)의 도구 앞 몫: (1) 명령이 계획 기록 명령이면 이번 턴 영수증을 남긴다,
# (2) 쓰기 도구는 적힌 파일을, 셸 명령은 돌기 전 모습을 적어 이 세션이 쓴 파일만 세게 한다. 막지 않는다 — 어떤 실패도 그냥 넘어간다.
_scv_tc_sh="$_scv_mp_dir/turn-check.sh"
if [[ -f "$_scv_tc_sh" && "$SESSION" != nosession && -d "$PROJECT_ROOT" ]] \
   && { declare -F scv_tc_tool_kind >/dev/null 2>&1 || source "$_scv_mp_dir/lib/turn-check.sh" 2>/dev/null; }; then
  _scv_tc_cmd="$(field '.tool_input.command')"
  _scv_tc_paths=()
  for _scv_tc_k in '.tool_input.file_path' '.tool_input.path' '.tool_input.notebook_path'; do
    _scv_tc_p="$(field "$_scv_tc_k")"; [[ -n "$_scv_tc_p" ]] && _scv_tc_paths+=("$_scv_tc_p")
  done
  if [[ -n "$_scv_tc_cmd" ]]; then
    while IFS= read -r _scv_tc_p; do [[ -n "$_scv_tc_p" ]] && _scv_tc_paths+=("$_scv_tc_p"); done < <(
      printf '%s\n' "$_scv_tc_cmd" | grep -oE '(^|[;&|[:space:]])(cd|-C)[[:space:]]+"?/[^"[:space:];&|]+' 2>/dev/null \
        | sed -E 's/^.*(cd|-C)[[:space:]]+"?//' | head -n 10)
    (cd "$PROJECT_ROOT" && printf '%s' "$_scv_tc_cmd" | bash "$_scv_tc_sh" receipt --session "$SESSION" >/dev/null 2>&1) || true
  fi
  _scv_tc_tool="$(field '.tool_name')"
  [[ -n "$_scv_tc_tool" ]] && { (cd "$PROJECT_ROOT" && bash "$_scv_tc_sh" step --session "$SESSION" --tool "$_scv_tc_tool" >/dev/null 2>&1) || true; }
  # 도구 종류는 입력 칸 모양으로 정한다(도구 이름은 호스트마다 다름): 명령 글 → 셸, 경로 + 쓸 내용 → 쓰기, 그 밖 → 읽기.
  # 읽기 도구는 폴더도 파일도 세지 않지만, 앞 셸 명령의 정산을 위해 touch 는 늘 부른다.
  _scv_tc_body=""
  for _scv_tc_k in '.tool_input.content' '.tool_input.old_string' '.tool_input.new_string' '.tool_input.edits' '.tool_input.new_source'; do
    [[ -n "$(field "$_scv_tc_k")" ]] && { _scv_tc_body=1; break; }
  done
  _scv_tc_p1=""; [[ ${#_scv_tc_paths[@]} -gt 0 ]] && _scv_tc_p1="${_scv_tc_paths[0]}"
  _scv_tc_kind="$(scv_tc_tool_kind "$_scv_tc_cmd" "$_scv_tc_p1" "$_scv_tc_body")"
  (cd "$PROJECT_ROOT" && bash "$_scv_tc_sh" touch --session "$SESSION" --kind "$_scv_tc_kind" ${_scv_tc_paths[@]+"${_scv_tc_paths[@]}"} >/dev/null 2>&1) || true
fi
# ---------- /turn plan check ---------------------------------------------------
# A shell command that runs an SCV action's entry script (help.sh, work.sh, promote-helper.sh, ...)
# from an SCV install (a path with "scv" in it — a project's own help.sh does not count). The per-turn
# registration and other helper scripts live beside them and must not count.
is_action_script() {
  printf '%s' "$1" | grep -qE "scv[^[:space:]]*/(${ACTIONS_RE})(-helper)?\.sh([^a-z-]|$)"
}

# ---------- mint mode: an action is starting --------------------------------
if [[ "$MODE" == "mint" ]]; then
  reported="$(field '.tool_input.skill')"
  [[ -n "$reported" ]] || reported="$(field '.command_name')"
  [[ -n "$reported" ]] || reported="$(field '.tool_input.command_name')"
  if [[ -n "$reported" ]]; then
    # Hosts spell the id with their own prefix; match the id itself.
    if printf '%s' "$reported" | grep -qE "(^|[^a-z-])(${ACTIONS_RE})([^a-z-]|$)"; then
      mint "$reported"
      help_mark
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

# ---------- Rule H (0.80.0+): a person's turn calls help before any other tool ---
# The per-turn hook asks for help first, and asking was not enough: in a long working session the
# model went straight to the (enforced) registration and skipped help for more than ten turns.
# gate-any runs on every tool. The help call itself passes and marks the turn: an SCV skill call,
# or a shell command that runs an SCV action's entry script. Tools the wrapper names in
# SCV_HELP_FIRST_ALLOW pass. Everything else is refused until the turn is marked — at the first
# tool, before any answer is written, so nothing has to be redone.
if [[ "$MODE" == "gate-any" ]]; then
  _scv_skill="$(field '.tool_input.skill')"
  if [[ -n "$_scv_skill" ]] && printf '%s' "$_scv_skill" | grep -qE "(^|[^a-z-])(${ACTIONS_RE})([^a-z-]|$)"; then
    help_mark; allow
  fi
  _scv_cmd="$(field '.tool_input.command')"
  if [[ -n "$_scv_cmd" ]] && is_action_script "$_scv_cmd"; then help_mark; allow; fi
  _scv_tool="$(field '.tool_name')"
  if [[ -n "${SCV_HELP_FIRST_ALLOW:-}" && -n "$_scv_tool" ]] && printf '%s' "$_scv_tool" | grep -qxE -- "${SCV_HELP_FIRST_ALLOW}"; then
    allow
  fi
  _scv_hwhy="$(mp_run help-gate)"
  [[ -n "${_scv_hwhy//[[:space:]]/}" ]] && deny "$_scv_hwhy"
  allow
fi

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
        is_action_script "$cmd" && help_mark
        allow
      fi
    done
  fi
  # A patch delivered through a shell tool still names its target.
  :
fi

# ---------- Rule P (v0.62.0+): this turn's request must be registered first ---
# Model-prompting: every user message is rewritten by the answering model's
# guide and registered (scope + rewrite) before any editor-style write. The
# decision lives in model-prompting.sh gate (it prints a reason, or nothing);
# no prompting guides, no turn token, switch off, or any failure → no opinion.
# v0.65.0+: the decision also sees whose write this is and what it touches — the
# session id (each session judges by its own registration), the subagent id (a
# subagent received no person's message: no opinion), and whether any target is a
# project file outside the SCV tree (a registration whose scope forbids changes
# refuses those; SCV's own records stay writable).
if [[ "$MODE" == "gate-write" && "${SCV_GUARD_RULE_P:-on}" != "off" ]]; then
  _scv_mp_dir="${SCV_GUARD_SCRIPTS:-}"; _scv_mp_dir="${_scv_mp_dir%%:*}"
  [[ -n "$_scv_mp_dir" ]] || _scv_mp_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" 2>/dev/null && pwd)"
  if [[ -f "$_scv_mp_dir/model-prompting.sh" && -d "$PROJECT_ROOT" ]]; then
    _scv_mp_args=(gate --agent "$(field '.agent_id')")
    _scv_mp_sid="$(field '.session_id')"
    [[ -n "$_scv_mp_sid" ]] && _scv_mp_args+=(--session "$_scv_mp_sid")
    _scv_mp_code=0
    while IFS= read -r raw; do
      [[ -n "$raw" ]] || continue
      abs="$(abspath "$raw")"
      [[ "$abs" == "$PROJECT_ROOT"/* && "$abs" != "$SCV_ROOT"/* ]] && { _scv_mp_code=1; break; }
    done < <(targets)
    _scv_mp_args+=(--code "$_scv_mp_code")
    _scv_mp_why="$(cd "$PROJECT_ROOT" && bash "$_scv_mp_dir/model-prompting.sh" "${_scv_mp_args[@]}" 2>/dev/null | head -c 2048 || true)"
    [[ -n "${_scv_mp_why//[[:space:]]/}" ]] && deny "$_scv_mp_why"
  fi
fi

# ---------- Rule D (0.81.0+): every function declares pure or effect ---------
# A function written without `@pure` (role · kind · example) or `@effect` (one-line reason) was invisible to
# the catalog check, and a long session skipped the small ones. In gate-write mode the guard rebuilds the file
# as it will be after this edit and asks scripts/pure-declare.sh whether the edit adds a function that declares
# neither. The before/after build reads the payload only (Write content, Edit/MultiEdit replacements, a patch's
# added file); anything it cannot rebuild gets no opinion. SCV_GUARD_RULE_D=off disables this rule alone.
if [[ "$MODE" == "gate-write" && "${SCV_GUARD_RULE_D:-on}" != "off" ]] && command -v python3 >/dev/null 2>&1; then
  _scv_pd="$_scv_mp_dir/pure-declare.sh"
  if [[ -f "$_scv_pd" ]]; then   # 하위 에이전트가 쓰는 코드도 같다 — 누가 쓰든 함수는 선언을 갖는다
    _scv_pdw="$(mktemp -d "${TMPDIR:-/tmp}/scv-pd.XXXXXX" 2>/dev/null)" || _scv_pdw=""
    if [[ -n "$_scv_pdw" ]]; then
      # Writes "<rel path>\t<before file or ->\t<after file>" per rebuildable target.
      printf '%s' "$PAYLOAD" | python3 -c '
import json, os, sys
out, cwd, root = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    p = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = p.get("tool_input") or {}
def absp(x): return x if os.path.isabs(x) else os.path.join(cwd, x)
jobs = []
fp = ti.get("file_path") or ti.get("path")
if fp:
    a = absp(fp)
    old = open(a, encoding="utf-8", errors="replace").read() if os.path.isfile(a) else None
    new = None
    if isinstance(ti.get("content"), str):
        new = ti["content"]
    elif isinstance(ti.get("old_string"), str) and old is not None:
        new = old.replace(ti["old_string"], ti.get("new_string", ""), -1 if ti.get("replace_all") else 1)
    elif isinstance(ti.get("edits"), list) and old is not None:
        new = old
        for e in ti["edits"]:
            if isinstance(e, dict) and isinstance(e.get("old_string"), str):
                new = new.replace(e["old_string"], e.get("new_string", ""), -1 if e.get("replace_all") else 1)
    if new is not None:
        jobs.append((a, old, new))
cmd = ti.get("command") or ti.get("input") or ""
if isinstance(cmd, str) and "*** Add File: " in cmd:
    cur, buf = None, []
    for line in cmd.splitlines() + ["*** End"]:
        if line.startswith("*** "):
            if cur: jobs.append((absp(cur), None, "\n".join(buf) + "\n"))
            cur, buf = (line[len("*** Add File: "):].strip() if line.startswith("*** Add File: ") else None), []
        elif cur is not None and line.startswith("+"):
            buf.append(line[1:])
with open(os.path.join(out, "jobs.tsv"), "w") as j:
    for i, (a, old, new) in enumerate(jobs):
        if not a.startswith(root + "/"): continue
        bf = "-"
        if old is not None:
            bf = os.path.join(out, "b%d" % i); open(bf, "w").write(old)
        af = os.path.join(out, "a%d" % i); open(af, "w").write(new)
        j.write("%s\t%s\t%s\n" % (os.path.relpath(a, root), bf, af))
' "$_scv_pdw" "$CWD" "$PROJECT_ROOT" 2>/dev/null
      _scv_pdwhy=""
      if [[ -f "$_scv_pdw/jobs.tsv" ]]; then
        while IFS=$'\t' read -r _rel _bf _af; do
          [[ -n "$_rel" ]] || continue
          _a=(gate --file "$_rel" --after "$_af"); [[ "$_bf" != "-" ]] && _a+=(--before "$_bf")
          _w="$(cd "$PROJECT_ROOT" && bash "$_scv_pd" "${_a[@]}" 2>/dev/null | head -c 2048)"
          [[ -n "$_w" ]] && { _scv_pdwhy="$_w"; break; }
        done < "$_scv_pdw/jobs.tsv"
      fi
      rm -rf "$_scv_pdw" 2>/dev/null
      [[ -n "$_scv_pdwhy" ]] && deny "$_scv_pdwhy"
    fi
  fi
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
