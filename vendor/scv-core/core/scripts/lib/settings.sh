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
SCV_LANG SCV_PROMOTE_LANG SCV_PLAIN_LANGUAGE SCV_PLAIN_MAX_SENTENCES SCV_ALWAYS_ON
SCV_FORCE_HELP SCV_DELEGATE_EFFORT SCV_RESUME_RECAP
NOTIFIER_PROVIDER NOTIFIER_DRY_RUN NOTIFIER_RETRY_MAX SCV_PR_NOTIFY
SCV_PR_PLATFORM SCV_PR_BASE GITLAB_HOST
SCV_ATTACHMENTS_BACKEND SCV_ATTACHMENTS_BRANCH SCV_ATTACHMENTS_RETENTION_DAYS
SCV_ATTACHMENTS_SCOPE SCV_ATTACHMENTS_SLUG SCV_ATTACHMENTS_RERUN_TIMEOUT SCV_EVIDENCE_MIN_SECONDS
SCV_GIF_FPS SCV_GIF_MAX_SECONDS SCV_GIF_WIDTH
SCV_EFFORT_MODE SCV_FAST_PATH_LINE_THRESHOLD SCV_STATUS_CACHE_TTL SCV_MODEL_POLICY
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

# _settings_warn_unmigrated — .env 에 SCV 값이 **설정 파일과 다르게** 남아 있으면 한 번 알린다.
#
# 0.34.0 부터 설정 파일은 액션 시작 때 자동으로 생기고 .env 값도 그때 옮겨진다.
# 그러니 "파일이 없다" 는 알림 사유가 아니다. 사유는 하나 — 사람이 나중에 .env 를
# 고쳤는데 SCV 는 설정 파일을 읽어 그 변경이 닿지 않는 경우. 값이 같으면 조용하다.
_settings_warn_unmigrated() {
  [[ -z "${SCV_SETTINGS_UNMIGRATED_WARNED:-}" ]] || return 0
  local file="${SCV_SETTINGS_ENV_FILE:-.env}" key envv cur plain_json secret_json differing=""
  [[ -f "$file" ]] || return 0
  plain_json="$(_settings_slurp "$SCV_SETTINGS_FILE")"
  secret_json="$(_settings_slurp "$SCV_SETTINGS_SECRET_FILE")"
  for key in $SCV_PLAIN_KEYS $SCV_SECRET_KEYS; do
    grep -qE "^[[:space:]]*${key}=" "$file" 2>/dev/null || continue
    envv="$(_settings_from_env_file "$key" "$file")"
    if settings_is_secret "$key"; then cur="$(settings_lookup_json "$secret_json" "$key")"
    else cur="$(settings_lookup_json "$plain_json" "$key")"; fi
    [[ "$envv" == "$cur" ]] || differing="$differing $key"
  done
  [[ -n "$differing" ]] || return 0
  export SCV_SETTINGS_UNMIGRATED_WARNED=1
  echo "scv: .env holds SCV values that differ from $SCV_SETTINGS_FILE (${differing# }) — .env is NO LONGER read; the settings file is what SCV uses." >&2
  echo "     Edit the settings file (or: bash \"\$CLAUDE_PLUGIN_ROOT/scripts/settings-set.sh\" KEY=VALUE) and remove the SCV lines from .env." >&2
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
  _settings_read_into "$SCV_SETTINGS_FILE"; plain_json="$_SCV_READ_VALUE"
  _settings_read_into "$SCV_SETTINGS_SECRET_FILE"; secret_json="$_SCV_READ_VALUE"

  _settings_warn_unmigrated
  if [[ -n "$plain_json" || -n "$secret_json" ]]; then
    _settings_index_lookup secret "$secret_json" "$key"; from_secret="$_SCV_MAP_VALUE"
    if settings_is_secret "$key"; then
      # 비밀 키가 일반 파일에 있으면 읽지 않는다. 값은 절대 찍지 않는다 —
      # 경고 문구가 유출 경로가 되면 안 된다.
      _settings_index_lookup plain "$plain_json" "$key"
      if [[ -n "$_SCV_MAP_VALUE" ]]; then
        echo "scv: $key is a secret and must not live in $SCV_SETTINGS_FILE (that file is committed) — the value was IGNORED; move it to $SCV_SETTINGS_SECRET_FILE." >&2
      fi
      _SCV_MAP_VALUE=""
    else
      _settings_index_lookup plain "$plain_json" "$key"; from_plain="$_SCV_MAP_VALUE"
    fi
  fi

  settings_resolve "$from_env" "$from_secret" "$from_plain" "$default"
}

# settings_lookup_many_json <json> <키들(공백으로)>
#
# settings_lookup_json 을 키마다 부르면 jq 를 키 수만큼 띄운다(47개 — 맥에서 한 번에 약 2초,
# 매 턴 훅이 여러 번 부른다). 한 번의 jq 로 '<키><TAB><값>' 줄을 낸다. 값 규칙은
# settings_lookup_json 과 같다(없음 · null · false 는 줄 없음, 문자열은 그대로, 나머지는 tostring).
# 값에 탭 · 줄바꿈이 있으면 값 대신 \001 한 글자를 내어 부른 쪽이 settings_lookup_json 으로 다시 읽게 한다.
# 디스크를 만지지 않는다 — 인자로 받은 텍스트만 본다.
# @deterministic
settings_lookup_many_json() {
  local json="${1:-}" keys="${2:-}"
  [[ -n "$json" && -n "$keys" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$json" | jq -r --arg ks "$keys" '
    if type == "object" then
      . as $o | ([$ks | splits("\\s+")] | map(select(. != "")))[] as $k
      | ($o[$k] // empty) | (if type == "string" then . else tostring end)
      | if test("[\t\n\r]") then "\($k)\t\u0001" else "\($k)\t\(.)" end
    else empty end' 2>/dev/null || true
}

# _settings_map_get <map> <키> <json> — settings_lookup_many_json 이 낸 줄에서 값 하나를
# 변수 _SCV_MAP_VALUE 에 넣는다(없으면 빈 문자열). 프로세스를 띄우지 않는다 — 키마다
# $(...) 로 부르면 그것만으로 수십 번 fork 한다. 표시(\001)를 만나면 그 키만
# settings_lookup_json 으로 다시 읽는다.
_settings_map_get() {
  local map=$'\n'"${1:-}"$'\n' key="${2:-}" json="${3:-}" rest
  _SCV_MAP_VALUE=""
  [[ -n "$key" ]] || return 0
  rest="${map#*$'\n'"$key"$'\t'}"
  [[ "$rest" != "$map" ]] || return 0
  _SCV_MAP_VALUE="${rest%%$'\n'*}"
  # 같은 키가 또 나오면(JSON 문서가 여럿 이어 붙은 파일) settings_lookup_json 은 값을 줄마다 모두 낸다 — 그쪽으로 다시 읽는다.
  if [[ "$_SCV_MAP_VALUE" == $'\001' || "$rest" == *$'\n'"$key"$'\t'* ]]; then _SCV_MAP_VALUE="$(settings_lookup_json "$json" "$key")"; fi
  return 0
}

# settings_index_json <json> — 설정 JSON 의 모든 키를 '<키><TAB><값>' 줄로 낸다(jq 한 번).
# settings_lookup_many_json 과 같은 값 규칙 · 같은 표시(\001: 그 키는 settings_lookup_json 으로 다시 읽는다)이고,
# 키 목록 대신 파일에 있는 키 전부를 낸다 — settings_get 은 목록 밖의 키도 읽는다. 이름 모양(영문 · 숫자 · _)이
# 아닌 키는 내지 않는다(그런 키는 _settings_index_lookup 이 늘 다시 읽는다). NUL 이 든 값도 표시로 —
# 다시 읽어야 $(...) 의 경고까지 지금과 같다. jq 가 없으면 아무것도 내지 않는다.
# 디스크를 만지지 않는다 — 인자로 받은 텍스트만 본다.
# @deterministic
settings_index_json() {
  local json="${1:-}"
  [[ -n "$json" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$json" | jq -r '
    if type == "object" then
      to_entries[] | select(.key | test("^[A-Za-z_][A-Za-z0-9_]*$"))
      | .key as $k | (.value // empty) | (if type == "string" then . else tostring end)
      | if test("[\t\n\r\u0000]") then "\($k)\t\u0001" else "\($k)\t\(.)" end
    else empty end' 2>/dev/null || true
}

# _settings_read_into <file> — 파일 내용을 변수 _SCV_READ_VALUE 에 넣는다. _settings_slurp 를 $(...) 로 받은 것과
# 같은 값(없음 · 심볼릭 링크 · 못 읽음은 빈 문자열, 끝 줄바꿈은 지운다)이지만 프로세스를 띄우지 않는다.
# NUL 이 든 파일은 _settings_slurp 로 읽는다($(...) 가 내는 경고까지 같게).
_settings_read_into() {
  local f="${1:-}" v=""
  _SCV_READ_VALUE=""
  [[ -n "$f" && -f "$f" && ! -L "$f" ]] || return 0
  if IFS= read -r -d '' v 2>/dev/null < "$f"; then
    _SCV_READ_VALUE="$(_settings_slurp "$f")"
    return 0
  fi
  while [[ "$v" == *$'\n' ]]; do v="${v%$'\n'}"; done
  _SCV_READ_VALUE="$v"
  return 0
}

# 펼친 표 자리(프로세스 안에서만 — 디스크에 쓰지 않는다). _SRC 는 표를 만든 파일 내용, _SET 은 만들었는지.
_SCV_IDX_PLAIN_SRC=""; _SCV_IDX_PLAIN_MAP=""; _SCV_IDX_PLAIN_SET=""
_SCV_IDX_SECRET_SRC=""; _SCV_IDX_SECRET_MAP=""; _SCV_IDX_SECRET_SET=""

# _settings_index_lookup <plain|secret> <json> <key> — 값을 _SCV_MAP_VALUE 에. settings_lookup_json 을 $(...) 로
# 받은 것과 같은 값이다. 그 파일의 표가 같은 내용으로 이미 있으면 다시 쓰고, 없으면 만든다(jq 한 번). $(...) 안에서
# 만든 표는 그 하위 셸과 함께 사라지므로, 여러 번 읽는 스크립트는 처음에 settings_preload 를 부른다.
_settings_index_lookup() {
  local which="${1:-}" json="${2:-}" key="${3:-}"
  _SCV_MAP_VALUE=""
  [[ -n "$json" && -n "$key" ]] || return 0
  if ! command -v jq >/dev/null 2>&1 || [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    _SCV_MAP_VALUE="$(settings_lookup_json "$json" "$key")"
    return 0
  fi
  if [[ "$which" == "secret" ]]; then
    if [[ -z "$_SCV_IDX_SECRET_SET" || "$json" != "$_SCV_IDX_SECRET_SRC" ]]; then
      _SCV_IDX_SECRET_MAP="$(settings_index_json "$json")"; _SCV_IDX_SECRET_SRC="$json"; _SCV_IDX_SECRET_SET=1
    fi
    _settings_map_get "$_SCV_IDX_SECRET_MAP" "$key" "$json"
  else
    if [[ -z "$_SCV_IDX_PLAIN_SET" || "$json" != "$_SCV_IDX_PLAIN_SRC" ]]; then
      _SCV_IDX_PLAIN_MAP="$(settings_index_json "$json")"; _SCV_IDX_PLAIN_SRC="$json"; _SCV_IDX_PLAIN_SET=1
    fi
    _settings_map_get "$_SCV_IDX_PLAIN_MAP" "$key" "$json"
  fi
}

# settings_preload — 두 설정 파일의 표를 지금 셸에 만들어 둔다. settings_get 을 $(...) 안에서 여러 번 부르는
# 스크립트가 처음에 한 번 부른다 — 하위 셸은 이 표를 물려받아 jq 를 다시 띄우지 않는다. 값은 바꾸지 않는다:
# 파일이 나중에 바뀌면 내용이 달라 표를 새로 만든다. 어떤 실패도 0.
settings_preload() {
  local pj sj
  _settings_read_into "$SCV_SETTINGS_FILE"; pj="$_SCV_READ_VALUE"
  _settings_read_into "$SCV_SETTINGS_SECRET_FILE"; sj="$_SCV_READ_VALUE"
  [[ -n "$pj" ]] && _settings_index_lookup plain "$pj" SCV_PRELOAD
  [[ -n "$sj" ]] && _settings_index_lookup secret "$sj" SCV_PRELOAD
  _SCV_MAP_VALUE=""
  return 0
}

# settings_has <key>
#
# 값이 있으면 0, 없으면 1. 진단 화면처럼 "설정됐는지" 만 궁금한 자리에 쓴다.
settings_has() {
  [[ -n "$(settings_get "${1:-}")" ]]
}

# ---------------------------------------------------------------- 효과: 파일을 보장한다
# settings_defaults_json — 배포본의 기본값+설명 JSON(예시 파일) 본문. 없으면 빈 문자열.
settings_defaults_json() {
  local lib_dir; lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _settings_slurp "$lib_dir/../../template/scv/scv_settings.example.json"
}

# _settings_json_strip_underscore <json> — `_` 로 시작하는 키(설명)를 뺀 JSON.
# 있는 파일에 병합할 때 쓴다: 사용자가 설명 키를 지웠으면 다시 넣지 않는다.
_settings_json_strip_underscore() {
  local json="${1:-}"
  [[ -n "$json" ]] || { printf '{}'; return 0; }
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq 'if type=="object" then with_entries(select(.key | startswith("_") | not)) else . end' 2>/dev/null || printf '%s' "$json"
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
print(json.dumps({k:v for k,v in d.items() if not k.startswith("_")}, indent=2, ensure_ascii=False) if isinstance(d,dict) else json.dumps(d))' 2>/dev/null || printf '%s' "$json"
  else
    printf '%s' "$json"
  fi
}

# _settings_env_overlay <keys> [env_file] — .env 에 값이 있는 키만 {"K":"V"} 로.
# 이사 전용 파서(_settings_from_env_file)만 쓴다 — .env 는 source 하지 않는다.
_settings_env_overlay() {
  local keys="${1:-}" file="${2:-.env}" key val first=1
  printf '{'
  [[ -f "$file" ]] && for key in $keys; do
    val="$(_settings_from_env_file "$key" "$file")"
    [[ -n "$val" ]] || continue
    [[ $first -eq 1 ]] || printf ','
    printf '"%s":"%s"' "$key" "$(printf '%s' "$val" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    first=0
  done
  printf '}'
}

# _settings_write_json <target> <json> — 유효한 JSON 일 때만 원자적으로 쓴다. 심볼릭 링크 거부.
_settings_write_json() {
  local target="$1" json="$2" tmp
  [[ -L "$target" ]] && { echo "scv: $target is a symlink — not writing through it" >&2; return 1; }
  mkdir -p "$(dirname "$target")" 2>/dev/null || true
  tmp="${target}.tmp.$$"
  printf '%s\n' "$json" > "$tmp" || { rm -f "$tmp"; return 1; }
  if command -v jq >/dev/null 2>&1; then jq -e . "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
  elif command -v python3 >/dev/null 2>&1; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
  fi
  mv "$tmp" "$target"
}

# _settings_secret_ignored — 비밀 파일이 git 에서 무시되는지. 무시 줄이 없으면
# hydrate 가 하듯 .gitignore 에 한 줄 더한 뒤 다시 확인한다. git 이 아니면 1.
_settings_secret_ignored() {
  local rel="${SCV_SETTINGS_SECRET_FILE:-scv/scv_settings.secret.json}"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  git check-ignore -q "$rel" 2>/dev/null && return 0
  if [[ ! -L .gitignore ]] && ! grep -qxF "$rel" .gitignore 2>/dev/null; then
    { [[ -f .gitignore ]] && [[ -n "$(tail -c1 .gitignore 2>/dev/null)" ]] && echo; echo "# --- appended by scv settings-ensure (secrets must never be committed) ---"; echo "$rel"; } >> .gitignore 2>/dev/null || return 1
  fi
  git check-ignore -q "$rel" 2>/dev/null
}

# settings_ensure [project_dir]
#
# 설정 파일이 항상 있게 한다 — 액션 시작마다 부른다.
#   없으면: 공개 키 전부 = 기본값(+ 설명), .env 에 있는 값 우선  → 만든다
#   있으면: 없는 키만 더한다 (사용자 값 불변, `_` 설명 키는 재추가 안 함)
#   비밀 파일: 없고 git 이 무시한다고 확인될 때만 만든다 (비밀 키 전부 빈 값 + .env 값)
# 출력은 바뀐 것이 있을 때 한 줄. hydrate 되지 않은 폴더(PROMOTE.md 없음)는 건드리지 않는다.
settings_ensure() {
  local proj="${1:-.}" scv_sub="${SCV_DIR_NAME:-scv}"
  [[ -d "$proj/$scv_sub" ]] || return 0   # hydrate 여부는 호출부(autosync)가 본다; 직접 부르면 scv/ 만 있으면 된다
  local defaults; defaults="$(settings_defaults_json)"
  [[ -n "$defaults" ]] || return 0
  ( cd "$proj" || exit 0
    local plain="${SCV_SETTINGS_FILE:-scv/scv_settings.json}" secret="${SCV_SETTINGS_SECRET_FILE:-scv/scv_settings.secret.json}"
    local merged user_json overlay n_env
    if [[ ! -f "$plain" ]]; then
      overlay="$(_settings_env_overlay "$SCV_PLAIN_KEYS" .env)"
      merged="$(settings_merge_defaults "$overlay" "$defaults")"
      n_env="$(printf '%s' "$overlay" | grep -o '":"' | wc -l | tr -d ' ')"
      if _settings_write_json "$plain" "$merged"; then
        echo "scv: settings file created — $plain (every SCV key with its default; $n_env value(s) taken from .env; _doc explains each key)" >&2
      fi
    elif [[ ! -L "$plain" ]]; then
      user_json="$(_settings_slurp "$plain")"
      merged="$(settings_merge_defaults "$user_json" "$(_settings_json_strip_underscore "$defaults")")"
      if [[ -n "$merged" && "$(printf '%s' "$merged" | tr -d '[:space:]')" != "$(printf '%s' "$user_json" | tr -d '[:space:]')" ]]; then
        # 키 수가 늘었을 때만 쓴다 — 형식만 다른 재정렬은 사용자 파일을 건드릴 이유가 아니다
        local before after
        before="$(printf '%s' "$user_json" | grep -o '"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*:' | wc -l | tr -d ' ')"
        after="$(printf '%s' "$merged" | grep -o '"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*:' | wc -l | tr -d ' ')"
        if [[ "$after" -gt "$before" ]] && _settings_write_json "$plain" "$merged"; then
          echo "scv: settings file gained $((after - before)) new key(s) — $plain (your values untouched)" >&2
        fi
      fi
    fi
    if [[ ! -f "$secret" ]]; then
      if _settings_secret_ignored; then
        local sdefaults; sdefaults="$(_settings_slurp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../template/scv/scv_settings.secret.example.json")"
        overlay="$(_settings_env_overlay "$SCV_SECRET_KEYS" .env)"
        merged="$(settings_merge_defaults "$overlay" "$sdefaults")"
        if _settings_write_json "$secret" "$merged"; then
          chmod 600 "$secret" 2>/dev/null || true
          echo "scv: secret settings file created — $secret (git-ignored; tokens and channel IDs go here)" >&2
        fi
      else
        [[ -n "${SCV_SETTINGS_SECRET_NOTICED:-}" ]] || echo "scv: $secret not created — git does not ignore it here (no git repo, or .gitignore could not be extended); add 'scv/scv_settings.secret.json' to .gitignore and re-run an action" >&2
        export SCV_SETTINGS_SECRET_NOTICED=1
      fi
    fi
  )
  return 0
}
