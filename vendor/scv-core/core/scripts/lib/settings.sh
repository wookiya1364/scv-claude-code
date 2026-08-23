#!/usr/bin/env bash
# settings.sh — SCV 설정을 읽는 단 하나의 입구.
#
# 왜 있나: 지금 설정은 프로젝트 루트 .env 에 있고, 읽는 방법이 자리마다 다르다.
# 어떤 곳은 파일 전체를 환경으로 불러오고, 어떤 곳은 직접 뒤진다. 규칙이 하나가
# 아니라서 한 곳을 고쳐도 다른 곳이 그대로 남는다.
#
# 순수부와 효과부를 가른다.
#   settings_resolve      순수 — 후보 넷을 받아 하나를 고른다. 우선순위가 여기에만 있다
#   settings_lookup_json  결정적 변환 — JSON 텍스트와 키를 받아 값을 낸다. 디스크를 안 만진다
#   settings_get          효과 — 파일을 읽어 위 둘에 넘긴다. 이 함수만 디스크를 만진다
#
# core/tests/test-settings.sh 의 정적 검사가 이 경계를 기계로 강제한다.
#
# 값을 찾는 순서는 언제나 같다:
#   환경변수 → 비밀 설정 → 일반 설정 → 기본값
#
# 환경변수가 맨 위인 이유: 스크립트끼리 값을 넘기는 데 이미 40개 넘게 쓰고 있고
# 테스트도 그 방식으로 돈다. 없애려는 것은 *설정 파일* 이지 환경변수가 아니다.

# ---------------------------------------------------------------- 키 분류

# 비밀 설정 — scv/scv_settings.secret.json 에만 둔다. 이 파일은 무시 목록에 있다.
#
# 토큰 셋은 진짜 비밀이고, 채널 ID 열은 엄밀히 비밀은 아니지만 조직 내부
# 식별자다. 같은 쪽에 둔다 — 애매하면 안전한 쪽이다.
#
# 이 목록이 하는 일이 둘이다: 이전 절차가 값을 어느 파일로 보낼지 정하고,
# 일반 설정 파일에 비밀 키가 들어 있으면 경고하고 무시한다.
SCV_SECRET_KEYS="SLACK_BOT_TOKEN DISCORD_BOT_TOKEN GITLAB_TOKEN
SLACK_CHANNEL_ID SLACK_CHANNEL_ID_PHASE_COMPLETE SLACK_CHANNEL_ID_DAILY_SUMMARY
SLACK_CHANNEL_ID_ERROR_ALERT SLACK_CHANNEL_ID_E2E_FAILURE
DISCORD_CHANNEL_ID DISCORD_CHANNEL_ID_PHASE_COMPLETE DISCORD_CHANNEL_ID_DAILY_SUMMARY
DISCORD_CHANNEL_ID_ERROR_ALERT DISCORD_CHANNEL_ID_E2E_FAILURE"

# 일반 설정 — scv/scv_settings.json (커밋된다).
SCV_PLAIN_KEYS="PROJECT_NAME SCV_DIR
SCV_LANG SCV_PROMOTE_LANG SCV_PLAIN_LANGUAGE SCV_PLAIN_MAX_SENTENCES
NOTIFIER_PROVIDER NOTIFIER_DRY_RUN NOTIFIER_RETRY_MAX
SCV_PR_PLATFORM GITLAB_HOST
SCV_ATTACHMENTS_BACKEND SCV_ATTACHMENTS_BRANCH SCV_ATTACHMENTS_RETENTION_DAYS
SCV_ATTACHMENTS_SCOPE SCV_ATTACHMENTS_SLUG SCV_ATTACHMENTS_RERUN_TIMEOUT
SCV_GIF_FPS SCV_GIF_MAX_SECONDS SCV_GIF_WIDTH
SCV_EFFORT_MODE SCV_FAST_PATH_LINE_THRESHOLD SCV_STATUS_CACHE_TTL
JIRA_BASE_URL LINEAR_BASE_URL CONFLUENCE_BASE_URL"

# settings_is_secret <key> — 비밀 키면 0, 아니면 1. 순수하다 (문자열 비교뿐).
# @pure
settings_is_secret() {
  local key="${1:-}" k
  [[ -n "$key" ]] || return 1
  for k in $SCV_SECRET_KEYS; do
    [[ "$k" == "$key" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------- 순수: 우선순위

# settings_resolve <env_val> <secret_val> <plain_val> <default_val>
#
# 넷 중 처음으로 비어 있지 않은 값을 낸다. 넷 다 비어 있으면 빈 문자열.
#
# 이 순서가 이 파일 한 곳에만 적혀 있다는 것이 요점이다. 지금은 자리마다 제각각
# 이고 일부는 순서가 다르다.
#
# 순수하다 — 파일도 시각도 무작위도 네트워크도 만지지 않는다.
# @pure
settings_resolve() {
  local e="${1:-}" s="${2:-}" p="${3:-}" d="${4:-}"
  if [[ -n "$e" ]]; then printf '%s\n' "$e"; return 0; fi
  if [[ -n "$s" ]]; then printf '%s\n' "$s"; return 0; fi
  if [[ -n "$p" ]]; then printf '%s\n' "$p"; return 0; fi
  printf '%s\n' "$d"
}

# ---------------------------------------------- 결정적 변환: 기본값 채우기(병합)

# settings_merge_defaults <user_json> <defaults_json>
#
# 사용자 설정에 **없는 키만** 기본값에서 가져와 더한 JSON 을 낸다.
#
# 규칙은 세 줄이고, 첫 줄이 전부다.
#   1. 사용자에게 이미 있는 키는 **절대 건드리지 않는다.** 값이 기본값과 달라도,
#      빈 문자열이어도 그대로 둔다. 업데이트가 사용자 설정을 바꾸면 곤란하다.
#   2. 기본값에만 있는 키는 더한다.
#   3. 사용자에게만 있는 키는 지우지 않는다. SCV 가 모르는 키여도 남긴다.
#
# 디스크를 만지지 않는다 — 텍스트 둘을 받아 텍스트 하나를 낸다.
# 어느 쪽이 깨져 있으면 사용자 원본을 그대로 낸다. 병합하다 설정을 잃느니
# 아무것도 안 하는 편이 낫다.
# @deterministic
settings_merge_defaults() {
  local user="${1:-}" defaults="${2:-}"
  [[ -n "$defaults" ]] || { printf '%s' "$user"; return 0; }
  [[ -n "$user" ]] || user='{}'

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$user" | jq --argjson d "$(printf '%s' "$defaults" | jq -c . 2>/dev/null || echo '{}')" '
      if type == "object" then ($d + .) else . end
    ' 2>/dev/null || printf '%s' "$user"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    SCV_MERGE_USER="$user" SCV_MERGE_DEFAULTS="$defaults" python3 -c '
import json, os, sys
raw_user = os.environ.get("SCV_MERGE_USER", "")
try:
    user = json.loads(raw_user) if raw_user.strip() else {}
    defaults = json.loads(os.environ.get("SCV_MERGE_DEFAULTS", "") or "{}")
except Exception:
    sys.stdout.write(raw_user); sys.exit(0)
if not isinstance(user, dict) or not isinstance(defaults, dict):
    sys.stdout.write(raw_user); sys.exit(0)
merged = dict(defaults)
merged.update(user)          # 사용자 값이 이긴다 — 기본값은 빈 자리만 채운다
print(json.dumps(merged, indent=2, ensure_ascii=False))
' 2>/dev/null || printf '%s' "$user"
    return 0
  fi

  # 파서가 없다 — 병합하지 않는다. 사용자 원본이 그대로 남는 편이 안전하다.
  printf '%s' "$user"
}

# ------------------------------------------------- 결정적 변환: JSON 에서 값 꺼내기

# settings_lookup_json <json_text> <key>
#
# 최상위 키 하나의 값을 문자열로 낸다. 없으면 빈 문자열, exit 0.
# 중첩된 객체·배열은 보지 않는다 — 설정은 평평하다.
#
# 값이 없는 것과 값이 빈 문자열인 것은 둘 다 빈 출력이다. 설정에서 그 둘을 구분할
# 이유가 없고, 구분하려 들면 호출부마다 처리가 갈린다.
#
# 깨진 JSON, 배열, 최상위가 문자열인 경우 — 전부 빈 문자열 + exit 0. 죽지 않는다.
# 설정 하나 때문에 진행 중인 명령이 멈추면 안 된다.
#
# 디스크를 만지지 않는다 — 인자로 받은 텍스트만 본다.
# @deterministic
settings_lookup_json() {
  local json="${1:-}" key="${2:-}"
  [[ -n "$json" && -n "$key" ]] || return 0

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r --arg k "$key" '
      if type == "object" then (.[$k] // empty) else empty end
      | if type == "string" then . else tostring end
    ' 2>/dev/null || true
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    SCV_LOOKUP_KEY="$key" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
v = d.get(os.environ.get("SCV_LOOKUP_KEY", ""))
if v is None:
    sys.exit(0)
if isinstance(v, bool):
    print("true" if v else "false")
elif isinstance(v, (int, float, str)):
    print(v)
' <<< "$json" 2>/dev/null || true
    return 0
  fi

  # 파서가 없다 — 값을 지어내느니 아무것도 내지 않는다. 호출부는 기본값으로 간다.
  return 0
}

# ---------------------------------------------------------------- 효과: 파일 읽기

# 설정 파일 자리. scv/ 아래에 둔다 — 프로젝트 루트의 .env 와 섞이지 않게.
SCV_SETTINGS_FILE="${SCV_SETTINGS_FILE:-scv/scv_settings.json}"
SCV_SETTINGS_SECRET_FILE="${SCV_SETTINGS_SECRET_FILE:-scv/scv_settings.secret.json}"

# _settings_slurp <file> — 파일 내용을 낸다. 없으면 빈 문자열. 심볼릭 링크는
# 읽지 않는다 (가리키는 대상은 우리 소유가 아니다).
_settings_slurp() {
  local f="${1:-}"
  [[ -n "$f" && -f "$f" && ! -L "$f" ]] || return 0
  cat "$f" 2>/dev/null || true
}

# _settings_from_env_file <key> [file] — **이사 전용.**
#
# 설정을 읽는 경로가 아니다. settings-migrate.sh 가 옛 .env 에서 값을 꺼내
# 새 파일로 옮길 때만 쓴다. 평소 읽기는 이 함수를 거치지 않는다.
#
# 파일을 source 하지 않는다. 사용자의 .env 는 unset 변수를 참조하거나($ 를 담은
# 비밀값 포함) 할 수 있고, nounset 이 켜진 호출부에서 source 하면 스크립트 전체가
# 죽는다 — 그리고 `|| true` 로는 그 죽음을 못 잡는다.
_settings_from_env_file() {
  local key="${1:-}" file="${2:-.env}"
  [[ -n "$key" && -f "$file" ]] || return 0
  # 마지막 정의가 이긴다 — source 했을 때와 같은 규칙.
  sed -n "s/^[[:space:]]*${key}=[[:space:]]*//p" "$file" 2>/dev/null \
    | tail -n 1 \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//" \
    || true
}

# _settings_env_has_scv_keys — 프로젝트 루트 .env 에 SCV 설정이 남아 있으면 0.
#
# 값을 읽기 위한 함수가 아니다. **이사하지 않은 프로젝트를 알아채기 위한** 것이다.
_settings_env_has_scv_keys() {
  local file="${SCV_SETTINGS_ENV_FILE:-.env}" key
  [[ -f "$file" ]] || return 1
  for key in $SCV_PLAIN_KEYS $SCV_SECRET_KEYS; do
    grep -qE "^[[:space:]]*${key}=" "$file" 2>/dev/null && return 0
  done
  return 1
}

# _settings_warn_unmigrated — 이사가 안 됐으면 한 번만 알린다.
#
# 값을 조용히 기본값으로 떨어뜨리면, 사용자는 알림이 안 가거나 언어가 바뀐 뒤에야
# 알아챈다. 조용한 실패는 안 된다. 한 액션에 한 번만 찍는다.
_settings_warn_unmigrated() {
  [[ -z "${SCV_SETTINGS_UNMIGRATED_WARNED:-}" ]] || return 0
  _settings_env_has_scv_keys || return 0
  export SCV_SETTINGS_UNMIGRATED_WARNED=1
  echo "scv: SCV settings now live in $SCV_SETTINGS_FILE — your .env is NO LONGER read." >&2
  echo "     .env still holds SCV keys, so SCV is running on DEFAULTS right now." >&2
  echo "     Move them once:  bash \"\$CLAUDE_PLUGIN_ROOT/scripts/settings-migrate.sh\"" >&2
  echo "     (your .env is not modified; secrets go to $SCV_SETTINGS_SECRET_FILE, which is git-ignored)" >&2
}

# settings_get <key> [default]
#
# 설정 하나를 읽는다. 이것이 유일한 입구다 — 직접 파일을 뒤지지 말 것.
#
# 읽는 곳은 두 JSON 뿐이다. 프로젝트 루트의 .env 는 **읽지 않는다** — 그것이
# 이 이사의 목적이었다. 아직 .env 에 설정이 남아 있으면 값을 가져오는 대신
# 한 번 알린다.
#
# 이 함수만 디스크를 만진다. 우선순위 판단은 순수 함수가 한다.
settings_get() {
  local key="${1:-}" default="${2:-}"
  [[ -n "$key" ]] || return 0

  local from_env="${!key:-}"
  local from_secret="" from_plain=""

  local plain_json secret_json
  plain_json="$(_settings_slurp "$SCV_SETTINGS_FILE")"
  secret_json="$(_settings_slurp "$SCV_SETTINGS_SECRET_FILE")"

  if [[ -z "$plain_json" && -z "$secret_json" ]]; then
    _settings_warn_unmigrated
  else
    from_secret="$(settings_lookup_json "$secret_json" "$key")"
    if settings_is_secret "$key"; then
      # 비밀 키가 일반 파일에 있으면 읽지 않는다. 값은 절대 찍지 않는다 —
      # 경고 문구가 유출 경로가 되면 안 된다.
      if [[ -n "$(settings_lookup_json "$plain_json" "$key")" ]]; then
        echo "scv: $key is a secret and must not live in $SCV_SETTINGS_FILE (that file is committed) — the value was IGNORED; move it to $SCV_SETTINGS_SECRET_FILE." >&2
      fi
    else
      from_plain="$(settings_lookup_json "$plain_json" "$key")"
    fi
  fi

  settings_resolve "$from_env" "$from_secret" "$from_plain" "$default"
}

# settings_has <key>
#
# 값이 있으면 0, 없으면 1. 진단 화면처럼 "설정됐는지" 만 궁금한 자리에 쓴다.
settings_has() {
  [[ -n "$(settings_get "${1:-}")" ]]
}
