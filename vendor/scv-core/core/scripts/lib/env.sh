#!/usr/bin/env bash
# Environment loading and validation utilities.

env_load() {
  # SCV 설정을 프로세스 환경으로 불러온다. 호출부 열 곳이 그다음 ${VAR} 로 읽는다 —
  # 변수 이름도 의미도 바꾸지 않는다. 바뀌는 것은 값이 어디서 오느냐뿐이다.
  #
  # 저장소가 둘이면 섞지 않는다. 새 설정 파일이 하나라도 있으면 그쪽만 본다 —
  # 두 곳을 합치면 "이 값이 어디서 왔지" 가 다시 시작된다. 그것이 이 이사를
  # 하는 이유였다.
  local _lib_dir
  _lib_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || _lib_dir=""
  if [[ -n "$_lib_dir" && -f "$_lib_dir/settings.sh" ]]; then
    # shellcheck source=settings.sh
    source "$_lib_dir/settings.sh"
  fi

  local _plain="${SCV_SETTINGS_FILE:-scv/scv_settings.json}"
  local _secret="${SCV_SETTINGS_SECRET_FILE:-scv/scv_settings.secret.json}"

  if [[ ! -f "$_plain" && ! -f "$_secret" ]]; then
    # 이사가 안 됐다. .env 는 읽지 않는다 — 그것이 이 이사의 목적이었다.
    # 다만 조용히 기본값으로 떨어뜨리지도 않는다. 한 액션에 한 번 알린다.
    _settings_warn_unmigrated || true
    return 0
  fi

  # 설정에서 새로 내보낸 키를 적어 둔다 — 호출 전에 이미 환경에 있던 키(사용자가 직접
  # export 한 값)는 적지 않는다. 회귀 실행기가 이 목록을 보고 자식 검사에는 설정값을
  # 넘기지 않는다: 아카이브 계약은 "설정 없음" 을 전제하고 짜였고, 이 저장소에 설정
  # 파일이 생긴 날 열 개가 실행기 안에서만 붉었다. 사용자가 직접 export 한 값은 그대로 흐른다.
  SCV_ENV_LOADED_KEYS=""
  local _key _val _pj _sj _pm _sm _from_s _from_p
  # 두 파일을 한 번씩 읽고 모든 키를 jq 한 번으로 꺼낸다 — 키마다 settings_get 을 부르면 jq 를
  # 키 수만큼(47개) 띄워, 빈 저장소에서도 한 번에 약 2초(맥)가 들었다. 우선순위 · 비밀 키 규칙은
  # settings_get 과 같다: 환경 > 비밀 파일 > 일반 파일, 비밀 키는 일반 파일에서 읽지 않는다.
  _pj="$(_settings_slurp "$SCV_SETTINGS_FILE")"
  _sj="$(_settings_slurp "$SCV_SETTINGS_SECRET_FILE")"
  _settings_warn_unmigrated
  _pm="$(settings_lookup_many_json "$_pj" "$SCV_PLAIN_KEYS $SCV_SECRET_KEYS")"
  _sm="$(settings_lookup_many_json "$_sj" "$SCV_PLAIN_KEYS $SCV_SECRET_KEYS")"
  for _key in $SCV_PLAIN_KEYS $SCV_SECRET_KEYS; do
    _settings_map_get "$_sm" "$_key" "$_sj"; _from_s="$_SCV_MAP_VALUE"
    _from_p=""
    if settings_is_secret "$_key"; then
      _settings_map_get "$_pm" "$_key" "$_pj"
      if [[ -n "$_SCV_MAP_VALUE" ]]; then
        echo "scv: $_key is a secret and must not live in $SCV_SETTINGS_FILE (that file is committed) — the value was IGNORED; move it to $SCV_SETTINGS_SECRET_FILE." >&2
      fi
    else
      _settings_map_get "$_pm" "$_key" "$_pj"; _from_p="$_SCV_MAP_VALUE"
    fi
    # settings_resolve 와 같은 순서(환경 > 비밀 > 일반) — 키마다 $(...) 를 피하려고 그 자리에서 고른다.
    _val="${!_key:-}"; [[ -n "$_val" ]] || _val="$_from_s"; [[ -n "$_val" ]] || _val="$_from_p"
    [[ -n "$_val" ]] || continue
    [[ -n "${!_key+x}" ]] || SCV_ENV_LOADED_KEYS="${SCV_ENV_LOADED_KEYS:+$SCV_ENV_LOADED_KEYS }$_key"
    export "$_key=$_val"
  done
  return 0
}

# env_settings_unset_args — env_load 가 설정 파일에서 새로 내보낸 키마다 "-u" 와 "KEY" 를 한 줄씩 낸다.
# 자식 프로세스(회귀 검사, pr-helper 의 증거 재실행)는 설정을 보지 않는다 — 아카이브 계약의 전제.
# 사용자가 직접 export 한 키는 SCV_ENV_LOADED_KEYS 에 없으므로 그대로 흐른다. 호출자 둘(regression.sh,
# pr-helper.sh)이 같은 함수를 쓴다 — 0.54.0 에는 regression.sh 안에만 있어 pr-helper 가 같은 누출을 탔다.
# @pure
env_settings_unset_args() {
  local k
  for k in ${SCV_ENV_LOADED_KEYS:-}; do printf -- '-u\n%s\n' "$k"; done
}

env_require() {
  # Usage: env_require VAR1 VAR2 ...
  # Returns non-zero and prints missing vars to stderr.
  local missing=()
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "✖ Missing required env vars: ${missing[*]}" >&2
    return 1
  fi
  return 0
}

env_default() {
  # Usage: env_default VAR default_value
  # Sets VAR to default_value if empty.
  local var="$1" default="$2"
  if [[ -z "${!var:-}" ]]; then
    export "$var"="$default"
  fi
}
