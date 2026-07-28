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
    SCV_GRAPH_SKILL_PATHS|SCV_UPDATE_OWNER|SCV_MODEL_POLICY_OWNER) ;;
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
