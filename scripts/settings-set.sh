#!/usr/bin/env bash
# settings-set.sh — SCV 설정 하나를 쓴다. env-set.sh 를 대신한다.
#
# 어느 파일로 갈지는 사람이 고르지 않는다. 키가 비밀이면 무시되는 파일로,
# 아니면 커밋되는 파일로 자동으로 간다 — 실수로 토큰을 커밋하는 경로를 없앤다.
#
# 다른 키는 건드리지 않는다. 사용자가 넣어둔 값도, SCV 가 모르는 키도 그대로다.
#
# Usage:
#   settings-set.sh KEY=VALUE  [--project-dir PATH]   값을 넣거나 바꾼다
#   settings-set.sh --unset KEY [--project-dir PATH]  키를 지운다
#   settings-set.sh --get KEY   [--project-dir PATH]  현재 값을 찍는다 (없으면 빈 줄)
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh"

PROJECT_DIR="."
MODE="set"; KEY=""; VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      [[ $# -ge 2 ]] || { echo "settings-set.sh: --project-dir needs a path" >&2; exit 2; }
      PROJECT_DIR="$2"; shift 2 ;;
    --unset)
      [[ $# -ge 2 ]] || { echo "settings-set.sh: --unset needs a KEY" >&2; exit 2; }
      MODE="unset"; KEY="$2"; shift 2 ;;
    --get)
      [[ $# -ge 2 ]] || { echo "settings-set.sh: --get needs a KEY" >&2; exit 2; }
      MODE="get"; KEY="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) echo "settings-set.sh: unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ "$1" == *=* ]]; then KEY="${1%%=*}"; VALUE="${1#*=}"; MODE="set"
      else echo "settings-set.sh: expected KEY=VALUE, got: $1" >&2; exit 2; fi
      shift ;;
  esac
done

[[ -n "$KEY" ]] || { echo "settings-set.sh: no KEY given" >&2; exit 2; }
cd "$PROJECT_DIR" || { echo "settings-set.sh: cannot enter $PROJECT_DIR" >&2; exit 1; }

# 비밀 키는 무시되는 파일로 간다. 사람이 고르지 않는다.
if settings_is_secret "$KEY"; then
  TARGET="${SCV_SETTINGS_SECRET_FILE:-scv/scv_settings.secret.json}"
  IS_SECRET=1
else
  TARGET="${SCV_SETTINGS_FILE:-scv/scv_settings.json}"
  IS_SECRET=0
fi

if [[ "$MODE" == "get" ]]; then
  settings_get "$KEY"
  exit 0
fi

[[ -L "$TARGET" ]] && { echo "settings-set.sh: $TARGET is a symlink — refusing to write through it" >&2; exit 1; }
mkdir -p "$(dirname "$TARGET")" 2>/dev/null || true
[[ -f "$TARGET" ]] || printf '{}\n' > "$TARGET"

CURRENT="$(cat "$TARGET" 2>/dev/null || echo '{}')"

write_json() {  # stdin 으로 받은 JSON 을 자리에 쓴다
  local tmp="${TARGET}.tmp.$$"
  cat > "$tmp" || return 1
  # 결과가 유효한 JSON 일 때만 바꾼다. 깨진 파일로 덮어쓰면 설정을 통째로 잃는다.
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp" >/dev/null 2>&1 \
      || { rm -f "$tmp"; return 1; }
  fi
  mv "$tmp" "$TARGET"
  [[ $IS_SECRET -eq 1 ]] && chmod 600 "$TARGET" 2>/dev/null
  return 0
}

if command -v jq >/dev/null 2>&1; then
  if [[ "$MODE" == "unset" ]]; then
    printf '%s' "$CURRENT" | jq --arg k "$KEY" 'del(.[$k])' | write_json || {
      echo "settings-set.sh: write failed — $TARGET unchanged" >&2; exit 1; }
  else
    printf '%s' "$CURRENT" | jq --arg k "$KEY" --arg v "$VALUE" '.[$k] = $v' | write_json || {
      echo "settings-set.sh: write failed — $TARGET unchanged" >&2; exit 1; }
  fi
elif command -v python3 >/dev/null 2>&1; then
  SCV_SET_KEY="$KEY" SCV_SET_VALUE="$VALUE" SCV_SET_MODE="$MODE" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
if not isinstance(d, dict):
    d = {}
k = os.environ["SCV_SET_KEY"]
if os.environ["SCV_SET_MODE"] == "unset":
    d.pop(k, None)
else:
    d[k] = os.environ["SCV_SET_VALUE"]
print(json.dumps(d, indent=2, ensure_ascii=False))
' <<< "$CURRENT" | write_json || {
    echo "settings-set.sh: write failed — $TARGET unchanged" >&2; exit 1; }
else
  echo "settings-set.sh: needs jq or python3 to edit JSON safely — $TARGET unchanged" >&2
  exit 1
fi

if [[ "$MODE" == "unset" ]]; then
  echo "unset $KEY in $TARGET"
else
  # 비밀값은 화면에 찍지 않는다.
  if [[ $IS_SECRET -eq 1 ]]; then
    echo "set $KEY in $TARGET (value hidden; this file is git-ignored)"
  else
    echo "set $KEY=$VALUE in $TARGET"
  fi
fi
