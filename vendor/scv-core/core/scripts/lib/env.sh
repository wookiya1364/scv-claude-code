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

  local _key _val
  for _key in $SCV_PLAIN_KEYS $SCV_SECRET_KEYS; do
    _val="$(settings_get "$_key")"
    [[ -n "$_val" ]] || continue
    export "$_key=$_val"
  done
  return 0
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
