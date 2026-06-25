#!/usr/bin/env bash
# workspace.sh — multi-repo nesting detection + identity readers.
#
# Design invariant (the "detachable additive overlay" rule):
#   Local SCV must never DEPEND on workspace state. This lib only READS local
#   files + local frontmatter (no network), and mode is recomputed on every
#   call (never a one-way migration). When the workspace root is absent or
#   unreachable, callers must gracefully degrade — local behavior stays
#   byte-identical to standalone SCV.
#
# Modes:
#   SINGLE — no populated SCV:WORKSPACE block and no scv/WORKSPACE.yaml.
#            Every pre-existing repo resolves here. Behaves exactly as today.
#   ROOT   — this repo owns scv/WORKSPACE.yaml (the umbrella registry).
#   CHILD  — scv/CLAUDE.md's SCV:WORKSPACE block declares a non-empty root:.
#
# Sourced by commands that opt into workspace awareness. Sourcing it has no
# side effects; nothing here runs until a function is called.

_WS_LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=merge.sh
source "$_WS_LIB_DIR/merge.sh"

# Config (env-overridable, matching SCV's soft-default convention).
SCV_DIR="${SCV_DIR:-scv}"
WS_CLAUDE="${WS_CLAUDE:-$SCV_DIR/CLAUDE.md}"
WS_MANIFEST="${WS_MANIFEST:-$SCV_DIR/WORKSPACE.yaml}"

_ws_block() {
  # Print the SCV:WORKSPACE block body (between markers) of the local scv/CLAUDE.md.
  [[ -f "$WS_CLAUDE" ]] || return 0
  extract_marker_block "$WS_CLAUDE" "SCV:WORKSPACE START" "SCV:WORKSPACE END"
}

_ws_field() {
  # Usage: _ws_field <key> — print a scalar field from the workspace block.
  # Skips HTML-comment and code-fence lines; tolerates indentation and quotes.
  local key="$1"
  _ws_block | awk -v k="$key" '
    index($0, "<!--") > 0 { next }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (index(line, k":") == 1) {
        val = substr(line, length(k) + 2)
        sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]+$/, "", val)
        gsub(/^"/, "", val); gsub(/"$/, "", val)
        print val
        exit
      }
    }'
}

scv_repo_id()   { _ws_field repo_id; }
scv_role()      { _ws_field role; }
scv_root()      { _ws_field root; }
scv_workspace() {
  # From the SCV:WORKSPACE block (a CHILD's join value). If empty (e.g. a ROOT,
  # which has no block value), fall back to WORKSPACE.yaml's workspace_id.
  local v; v="$(_ws_field workspace)"
  if [[ -z "$v" && -f "$WS_MANIFEST" ]]; then
    v="$(awk '/^workspace_id:[[:space:]]*/{sub(/^workspace_id:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$WS_MANIFEST")"
  fi
  printf '%s\n' "$v"
}

scv_resolve_mode() {
  # Print SINGLE | ROOT | CHILD. Always exits 0. Pure-local, no network.
  if [[ -f "$WS_MANIFEST" ]]; then
    echo ROOT
    return 0
  fi
  if [[ -n "$(scv_root)" ]]; then
    echo CHILD
    return 0
  fi
  echo SINGLE
}

scv_is_multi() {
  # Return 0 (true) when ROOT or CHILD, 1 when SINGLE.
  [[ "$(scv_resolve_mode)" != "SINGLE" ]]
}

scv_root_path() {
  # Resolve the local working-copy path of the root scv repo (CHILD only).
  #   root: is a filesystem path that exists       -> print it
  #   root: is a git URL with a populated cache dir -> print the cache path
  # Print nothing and return 1 when unresolvable (caller must degrade).
  local root ws cache
  root="$(scv_root)"
  [[ -n "$root" ]] || return 1
  if [[ -d "$root" ]]; then
    echo "$root"
    return 0
  fi
  ws="$(scv_workspace)"; ws="${ws:-default}"
  cache="${SCV_CACHE_DIR:-$HOME/.cache/scv}/$ws/root"
  if [[ -d "$cache" ]]; then
    echo "$cache"
    return 0
  fi
  return 1
}

scv_root_reachable() {
  # Return 0 when the root working copy is locally available, 1 otherwise.
  # The single gate for "can we do cross-repo work, or must we degrade?".
  scv_root_path >/dev/null 2>&1
}
