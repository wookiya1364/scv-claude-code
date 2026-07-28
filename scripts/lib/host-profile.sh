#!/usr/bin/env bash
# Read the wrapper-supplied host profile as data. Never source or eval it.

_SCV_HOST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SCV_HOST_CORE_ROOT="$(cd "$_SCV_HOST_LIB_DIR/../.." && pwd)"
SCV_HOST_PROFILE="${SCV_HOST_PROFILE:-$_SCV_HOST_CORE_ROOT/host-profile.env}"

SCV_HOST_PROFILE_API="1"
SCV_HOST_ID="neutral"
SCV_HOST_LABEL="Claude Code"
SCV_ACTION_TEMPLATE="action:{action}"
SCV_ARGUMENT_STYLE="argv-array"
SCV_STATE_INDEX="SCV.md"
SCV_LEGACY_STATE_INDEXES=""
SCV_ROOT_ENV="CLAUDE_PLUGIN_ROOT"
SCV_GRAPH_SKILL_PATHS=""
SCV_UPDATE_OWNER="adapter"
SCV_MODEL_POLICY_OWNER="adapter"

_scv_profile_assign() {
  local key="$1" value="$2"
  case "$key" in
    SCV_HOST_PROFILE_API) SCV_HOST_PROFILE_API="$value" ;;
    SCV_HOST_ID) SCV_HOST_ID="$value" ;;
    SCV_HOST_LABEL) SCV_HOST_LABEL="$value" ;;
    SCV_ACTION_TEMPLATE) SCV_ACTION_TEMPLATE="$value" ;;
    SCV_ARGUMENT_STYLE) SCV_ARGUMENT_STYLE="$value" ;;
    SCV_STATE_INDEX) SCV_STATE_INDEX="$value" ;;
    SCV_LEGACY_STATE_INDEXES) SCV_LEGACY_STATE_INDEXES="$value" ;;
    SCV_ROOT_ENV) SCV_ROOT_ENV="$value" ;;
    SCV_GRAPH_SKILL_PATHS) SCV_GRAPH_SKILL_PATHS="$value" ;;
    SCV_UPDATE_OWNER) SCV_UPDATE_OWNER="$value" ;;
    SCV_MODEL_POLICY_OWNER) SCV_MODEL_POLICY_OWNER="$value" ;;
  esac
}

_scv_profile_unquote() {
  local value="$1"
  if [[ ${#value} -ge 2 ]]; then
    if [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]] \
      || [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s\n' "$value"
}

scv_host_profile_load() {
  [[ -f "$SCV_HOST_PROFILE" ]] || return 0
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%=*}"
    value="$(_scv_profile_unquote "${line#*=}")"
    _scv_profile_assign "$key" "$value"
  done < "$SCV_HOST_PROFILE"
}

scv_action_ref() {
  local action="$1"
  printf '%s\n' "${SCV_ACTION_TEMPLATE//\{action\}/$action}"
}

scv_state_index_path() {
  local scv_dir="${1:-scv}" legacy candidate
  candidate="$scv_dir/$SCV_STATE_INDEX"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  while IFS= read -r legacy; do
    [[ -n "$legacy" ]] || continue
    candidate="$scv_dir/$legacy"
    if [[ -f "$candidate" ]]; then
      scv_state_index_is_pointer "$candidate" && continue
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(printf '%s\n' "$SCV_LEGACY_STATE_INDEXES" | tr '|' '\n')
  printf '%s\n' "$scv_dir/$SCV_STATE_INDEX"
}

scv_state_index_is_pointer() {
  local file="$1"
  grep -q '<!-- SCV:HOST-POINTER target=SCV.md -->' "$file" 2>/dev/null
}

scv_state_index_broken_pointers() {
  local scv_dir="${1:-scv}"
  local canonical="$scv_dir/$SCV_STATE_INDEX"
  local candidate legacy
  [[ -f "$canonical" ]] && return 0
  while IFS= read -r legacy; do
    [[ -n "$legacy" ]] || continue
    candidate="$scv_dir/$legacy"
    if [[ -f "$candidate" ]] && scv_state_index_is_pointer "$candidate"; then
      printf '%s -> %s (missing)\n' "$candidate" "$canonical"
    fi
  done < <(printf '%s\n' "$SCV_LEGACY_STATE_INDEXES" | tr '|' '\n')
}

scv_state_index_conflicts() {
  local scv_dir="${1:-scv}"
  local canonical="$scv_dir/$SCV_STATE_INDEX"
  local baseline="" candidate legacy
  if [[ -f "$canonical" ]] && ! scv_state_index_is_pointer "$canonical"; then
    baseline="$canonical"
  fi
  while IFS= read -r legacy; do
    [[ -n "$legacy" ]] || continue
    candidate="$scv_dir/$legacy"
    [[ -f "$candidate" ]] || continue
    scv_state_index_is_pointer "$candidate" && continue
    if [[ -z "$baseline" ]]; then
      baseline="$candidate"
    elif ! cmp -s "$baseline" "$candidate"; then
      printf '%s <> %s\n' "$baseline" "$candidate"
    fi
  done < <(printf '%s\n' "$SCV_LEGACY_STATE_INDEXES" | tr '|' '\n')
}

scv_graph_skill_available() {
  local raw candidate
  [[ -n "$SCV_GRAPH_SKILL_PATHS" ]] || return 1
  while IFS= read -r raw; do
    [[ -n "$raw" ]] || continue
    candidate="${raw//\$HOME/$HOME}"
    if compgen -G "$candidate" >/dev/null 2>&1; then
      return 0
    fi
  done < <(printf '%s\n' "$SCV_GRAPH_SKILL_PATHS" | tr '|' '\n')
  return 1
}

scv_host_profile_load
