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
# 0.59.0+ 선택 키: 래퍼가 싣는 모델별 프롬프팅 가이드 폴더(코어 루트 기준 상대 경로 또는 절대 경로). 비면 기능이 조용하다.
SCV_PROMPTING_GUIDES=""
# 0.63.0+ 선택 키: 사람이 아니라 호스트가 보낸 입력(배경 작업 완료 알림 등)을 감싸는 태그 이름들, 공백으로 나눔.
# 입력이 이 태그 블록과 공백만으로 이뤄지면 자동 입력 — 새 턴을 열지 않는다(lib/model-prompting.sh scv_mp_prompt_kind).
# 비면 모든 입력이 사람 입력.
SCV_AUTO_PROMPT_TAGS=""
# 0.64.0+ 선택 키: 사용자에게 고르게 하는 호스트의 선택지 도구 이름(contracts/choices.md). 비면 결정은 지금처럼 번호 표로 묻는다.
SCV_CHOICE_TOOL=""
# 0.64.0+ 선택 키: 선택지 도구가 없는 실행(사람이 답할 수 없는 헤드리스 등)을 알리는 환경 조건 "이름=값". 그 환경 변수가
# 그 값이면 이 실행에서는 도구가 없는 것과 같다(choice-gate.sh). 비면 조건 없음.
SCV_CHOICE_OFF_WHEN=""

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
    SCV_PROMPTING_GUIDES) SCV_PROMPTING_GUIDES="$value" ;;
    SCV_AUTO_PROMPT_TAGS) SCV_AUTO_PROMPT_TAGS="$value" ;;
    SCV_CHOICE_TOOL) SCV_CHOICE_TOOL="$value" ;;
    SCV_CHOICE_OFF_WHEN) SCV_CHOICE_OFF_WHEN="$value" ;;
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
  grep -qxF '<!-- SCV:HOST-POINTER target=SCV.md -->' "$file" 2>/dev/null
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

# SCV_GRAPH_SKILL_PATHS (deprecated 0.51.0): still accepted from wrappers, ignored — the docs graph is built by scripts/graph.sh.

scv_host_profile_load
