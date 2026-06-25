#!/usr/bin/env bash
# workspace-helper.sh — friendly front-door mechanics for /scv:workspace.
#
# Wraps the low-level setup (sync --join / WORKSPACE.yaml / SCV:WORKSPACE block)
# so users never type long flags. Subcommands:
#   info        Print current mode + identity (for the command to branch on).
#   join        Join an umbrella as a CHILD (delegates to the tested sync --join).
#   init-root   Make this repo the umbrella ROOT (create scv/WORKSPACE.yaml).
#   detach      Clear the workspace link → back to SINGLE (reversible, lossless).

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/workspace.sh
source "$SCRIPT_DIR/lib/workspace.sh"   # also sources lib/merge.sh

die() { echo "✖ $*" >&2; exit 1; }

cmd_info() {
  if [[ ! -f "$WS_CLAUDE" ]]; then
    echo "MODE: NOT_HYDRATED"
    echo "HINT: run /scv:help first to hydrate this project"
    return 0
  fi
  local mode; mode="$(scv_resolve_mode)"
  echo "MODE: $mode"
  echo "REPO_ID: $(scv_repo_id)"
  echo "ROLE: $(scv_role)"
  echo "ROOT: $(scv_root)"
  echo "WORKSPACE: $(scv_workspace)"
  if [[ "$mode" == "CHILD" ]]; then
    if scv_root_reachable; then echo "ROOT_REACHABLE: yes"; else echo "ROOT_REACHABLE: no"; fi
  fi
}

cmd_join() {
  local root="" id="" role="" ws=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root) root="$2"; shift 2 ;;
      --id) id="$2"; shift 2 ;;
      --role) role="$2"; shift 2 ;;
      --workspace) ws="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ -n "$root" ]] || die "--root <git-url|path> required"
  local args=(--join "$root")
  [[ -n "$id" ]]   && args+=(--id "$id")
  [[ -n "$role" ]] && args+=(--role "$role")
  [[ -n "$ws" ]]   && args+=(--workspace "$ws")
  bash "$SCRIPT_DIR/sync.sh" "${args[@]}"
}

cmd_init_root() {
  [[ -f "$WS_CLAUDE" ]] || die "not a hydrated SCV project (run /scv:help first)"
  if [[ -f "$WS_MANIFEST" ]]; then
    echo "ℹ already a ROOT — $WS_MANIFEST exists. Edit its members."
    return 0
  fi
  local ex="$SCV_DIR/WORKSPACE.yaml.example"
  if [[ -f "$ex" ]]; then
    cp "$ex" "$WS_MANIFEST"
  else
    printf 'workspace_id: my-workspace\nmembers:\n  - id: \n    role: \n    url: \n' > "$WS_MANIFEST"
  fi
  echo "✓ created $WS_MANIFEST — this repo is now the workspace ROOT (umbrella)."
  echo "  Next: edit its members (one id/role/url per repo)."
}

cmd_detach() {
  [[ -f "$WS_CLAUDE" ]] || die "no scv/CLAUDE.md here"
  if has_marker_block "$WS_CLAUDE" "SCV:WORKSPACE START"; then
    replace_marker_block "$WS_CLAUDE" "SCV:WORKSPACE START" "SCV:WORKSPACE END" '```yaml
repo_id:
role:
root:
workspace:
```'
    echo "✓ detached — this repo is now SINGLE. Workspace features go dormant; everything local is unchanged."
    echo "  Re-join anytime with /scv:workspace (no migration, nothing lost)."
  else
    echo "ℹ already single (no SCV:WORKSPACE link)."
  fi
}

SUB="${1:-info}"; shift || true
case "$SUB" in
  info)      cmd_info ;;
  join)      cmd_join "$@" ;;
  init-root) cmd_init_root ;;
  detach)    cmd_detach ;;
  -h|--help) sed -n '2,12p' "$0" ;;
  *) die "unknown subcommand: $SUB (info|join|init-root|detach)" ;;
esac
