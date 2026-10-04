#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: validate-host-profile.sh --profile FILE" >&2
}

PROFILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
[[ -n "$PROFILE" && -f "$PROFILE" ]] || { usage; exit 2; }

seen_keys=""
SCV_HOST_PROFILE_API=""
SCV_HOST_ID=""
SCV_HOST_LABEL=""
SCV_ACTION_TEMPLATE=""
SCV_ARGUMENT_STYLE=""
SCV_STATE_INDEX=""
SCV_LEGACY_STATE_INDEXES=""
SCV_ROOT_ENV=""
SCV_GRAPH_SKILL_PATHS=""
SCV_UPDATE_OWNER=""
SCV_MODEL_POLICY_OWNER=""
SCV_PROMPTING_GUIDES=""
SCV_AUTO_PROMPT_TAGS=""
SCV_CHOICE_TOOL=""
SCV_CHOICE_OFF_WHEN=""
SCV_SESSION_ENV=""
SCV_AUTO_PROMPT_PREFIX=""
SCV_AUTO_PROMPT_SUFFIX=""
line_no=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line_no=$((line_no + 1))
  [[ -z "$line" || "$line" == \#* ]] && continue
  [[ "$line" != *$'\r'* ]] || { echo "profile:$line_no: CR is not allowed" >&2; exit 1; }
  [[ "$line" == *=* ]] || { echo "profile:$line_no: expected KEY=VALUE" >&2; exit 1; }
  key="${line%%=*}"
  val="${line#*=}"
  if [[ ${#val} -ge 2 ]]; then
    if [[ "${val:0:1}" == "'" && "${val: -1}" == "'" ]] \
      || [[ "${val:0:1}" == '"' && "${val: -1}" == '"' ]]; then
      val="${val:1:${#val}-2}"
    fi
  fi
  case "$key" in
    SCV_HOST_PROFILE_API|SCV_HOST_ID|SCV_HOST_LABEL|SCV_ACTION_TEMPLATE|\
    SCV_ARGUMENT_STYLE|SCV_STATE_INDEX|SCV_LEGACY_STATE_INDEXES|SCV_ROOT_ENV|\
    SCV_GRAPH_SKILL_PATHS|SCV_UPDATE_OWNER|SCV_MODEL_POLICY_OWNER|\
    SCV_PROMPTING_GUIDES|SCV_AUTO_PROMPT_TAGS|SCV_CHOICE_TOOL|SCV_CHOICE_OFF_WHEN|\
    SCV_SESSION_ENV|SCV_AUTO_PROMPT_PREFIX|SCV_AUTO_PROMPT_SUFFIX) ;;
    *) echo "profile:$line_no: unknown key: $key" >&2; exit 1 ;;
  esac
  case "|$seen_keys|" in
    *"|$key|"*) echo "profile:$line_no: duplicate key: $key" >&2; exit 1 ;;
  esac
  seen_keys="${seen_keys:+$seen_keys|}$key"
  printf -v "$key" '%s' "$val"
done < "$PROFILE"

required=(
  SCV_HOST_PROFILE_API SCV_HOST_ID SCV_HOST_LABEL SCV_ACTION_TEMPLATE
  SCV_ARGUMENT_STYLE SCV_STATE_INDEX SCV_ROOT_ENV SCV_GRAPH_SKILL_PATHS
  SCV_UPDATE_OWNER SCV_MODEL_POLICY_OWNER
)
for key in "${required[@]}"; do
  case "|$seen_keys|" in
    *"|$key|"*) ;;
    *) echo "profile: missing key: $key" >&2; exit 1 ;;
  esac
done

[[ "$SCV_HOST_PROFILE_API" == "1" ]] \
  || { echo "profile: SCV_HOST_PROFILE_API must be 1" >&2; exit 1; }
[[ "$SCV_HOST_ID" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]] \
  || { echo "profile: invalid SCV_HOST_ID" >&2; exit 1; }
[[ -n "$SCV_HOST_LABEL" ]] \
  || { echo "profile: SCV_HOST_LABEL must not be empty" >&2; exit 1; }
[[ "$SCV_STATE_INDEX" == "SCV.md" ]] \
  || { echo "profile: SCV_STATE_INDEX must be SCV.md" >&2; exit 1; }
[[ "$SCV_ARGUMENT_STYLE" == "template-string" || "$SCV_ARGUMENT_STYLE" == "argv-array" ]] \
  || { echo "profile: SCV_ARGUMENT_STYLE must be template-string or argv-array" >&2; exit 1; }
[[ "$SCV_ROOT_ENV" =~ ^[A-Z][A-Z0-9_]*$ ]] \
  || { echo "profile: invalid SCV_ROOT_ENV" >&2; exit 1; }
[[ "$SCV_UPDATE_OWNER" == "adapter" ]] \
  || { echo "profile: SCV_UPDATE_OWNER must be adapter" >&2; exit 1; }
[[ "$SCV_MODEL_POLICY_OWNER" == "adapter" ]] \
  || { echo "profile: SCV_MODEL_POLICY_OWNER must be adapter" >&2; exit 1; }

# 선택 키 (0.59.0+): 모델별 프롬프팅 가이드 폴더. 경로 글자만 — 공백·셸 문자 없음.
if [[ -n "$SCV_PROMPTING_GUIDES" ]]; then
  [[ "$SCV_PROMPTING_GUIDES" =~ ^[A-Za-z0-9._/-]+$ ]] \
    || { echo "profile: invalid SCV_PROMPTING_GUIDES (path characters only)" >&2; exit 1; }
fi

# 선택 키 (0.63.0+): 자동 입력 태그 이름들 — 소문자 · 숫자 · 하이픈 이름을 공백으로 나눈 목록. 꺾쇠는 코어가 붙인다.
if [[ -n "$SCV_AUTO_PROMPT_TAGS" ]]; then
  _tags_re='^[a-z][a-z0-9-]*( [a-z][a-z0-9-]*)*$'   # 공백이 든 정규식은 변수로 — bash 3.2 · 5 가 같게 읽는다
  [[ "$SCV_AUTO_PROMPT_TAGS" =~ $_tags_re ]] \
    || { echo "profile: invalid SCV_AUTO_PROMPT_TAGS (tag names separated by single spaces)" >&2; exit 1; }
fi

# 선택 키 (0.64.0+): 호스트의 선택지 도구 이름 — 글자로 시작하는 이름 하나(글자 · 숫자 · _ · -, 64자까지). 공백 · 셸 문자 없음.
if [[ -n "$SCV_CHOICE_TOOL" ]]; then
  [[ "$SCV_CHOICE_TOOL" =~ ^[A-Za-z][A-Za-z0-9_-]{0,63}$ ]] \
    || { echo "profile: invalid SCV_CHOICE_TOOL (one tool name: a letter, then letters, digits, _ or -)" >&2; exit 1; }
fi

# 선택 키 (0.64.0+): 선택지 도구가 없는 실행을 알리는 환경 조건 — "환경 변수 이름=값" 하나(이름은 셸 변수 이름, 값은 글자 · 숫자 ·
# . _ : - 로 64자까지). 그 환경 변수가 그 값인 실행에서는 도구가 없는 것과 같다.
if [[ -n "$SCV_CHOICE_OFF_WHEN" ]]; then
  [[ "$SCV_CHOICE_OFF_WHEN" =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}=[A-Za-z0-9_.:-]{1,64}$ ]] \
    || { echo "profile: invalid SCV_CHOICE_OFF_WHEN (one NAME=VALUE: an environment variable name, then a plain value)" >&2; exit 1; }
fi

# 선택 키 (0.65.0+): 모델이 실행하는 셸 명령에 세션 id 를 담아 주는 환경 변수 이름 하나.
if [[ -n "$SCV_SESSION_ENV" ]]; then
  [[ "$SCV_SESSION_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}$ ]] \
    || { echo "profile: invalid SCV_SESSION_ENV (one environment variable name)" >&2; exit 1; }
fi

# 선택 키 (0.65.0+): 호스트가 자동 입력의 태그 블록 앞 · 뒤에 붙이는 글의 시작 — 한 줄의 평문(제어 문자 · 꺾쇠 없음, 200자까지),
# 앞뒤 공백 없음. 셸 코드가 아니라 글자 그대로 비교한다.
for key in SCV_AUTO_PROMPT_PREFIX SCV_AUTO_PROMPT_SUFFIX; do
  case "$key" in
    SCV_AUTO_PROMPT_PREFIX) val="$SCV_AUTO_PROMPT_PREFIX" ;;
    SCV_AUTO_PROMPT_SUFFIX) val="$SCV_AUTO_PROMPT_SUFFIX" ;;
  esac
  [[ -n "$val" ]] || continue
  if [[ ${#val} -gt 200 || "$val" == *[[:cntrl:]]* || "$val" == *'<'* || "$val" == *'>'* \
        || "$val" == [[:space:]]* || "$val" == *[[:space:]] ]]; then
    echo "profile: invalid $key (one line of plain text without angle brackets, at most 200 characters)" >&2; exit 1
  fi
done

template="$SCV_ACTION_TEMPLATE"
without_one="${template/\{action\}/}"
[[ "$without_one" != "$template" && "$without_one" != *"{action}"* ]] \
  || { echo "profile: SCV_ACTION_TEMPLATE needs exactly one {action}" >&2; exit 1; }
if [[ "$template" == *'$'* ]]; then
  [[ "$template" =~ ^\$[A-Za-z_][A-Za-z0-9_]*:\{action\}$ ]] \
    || { echo "profile: a dollar-prefixed action template must be \$name:{action}" >&2; exit 1; }
fi

for key in SCV_HOST_LABEL SCV_ACTION_TEMPLATE SCV_LEGACY_STATE_INDEXES SCV_GRAPH_SKILL_PATHS; do
  case "$key" in
    SCV_HOST_LABEL) val="$SCV_HOST_LABEL" ;;
    SCV_ACTION_TEMPLATE) val="$SCV_ACTION_TEMPLATE" ;;
    SCV_LEGACY_STATE_INDEXES) val="$SCV_LEGACY_STATE_INDEXES" ;;
    SCV_GRAPH_SKILL_PATHS) val="$SCV_GRAPH_SKILL_PATHS" ;;
  esac
  [[ "$val" != *'`'* && "$val" != *'$('* && "$val" != *';'* && "$val" != *'&'* ]] \
    || { echo "profile: unsafe data in $key" >&2; exit 1; }
done

legacy="$SCV_LEGACY_STATE_INDEXES"
if [[ -n "$legacy" ]]; then
  while IFS= read -r name; do
    [[ "$name" =~ ^[A-Za-z0-9._-]+\.md$ && "$name" != "SCV.md" ]] \
      || { echo "profile: invalid legacy state basename: $name" >&2; exit 1; }
  done < <(printf '%s\n' "$legacy" | tr '|' '\n')
fi

echo "host profile valid: $SCV_HOST_ID"
