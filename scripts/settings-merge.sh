#!/usr/bin/env bash
# settings-merge.sh — SCV 가 새로 추가한 설정 키만 프로젝트 설정에 더한다.
#
# **사용자가 이미 정한 값은 절대 바꾸지 않는다.** 값이 기본값과 달라도, 빈
# 문자열이어도 그대로 둔다. 업데이트할 때마다 설정이 되돌아가면 곤란하다.
#
# 예: 사용자가 SCV_TEST=local 로 두었고 SCV 기본값이 online 이면, 병합 후에도
# local 이다. SCV 가 새 키를 하나 추가했으면 그 키만 더해진다.
#
# 프로젝트에 설정 파일이 없으면 아무것도 하지 않는다 — 빈 파일을 만들어 두면
# "이사했다" 로 오인되어 이사 안내가 사라진다.
#
# Usage:
#   settings-merge.sh [--project-dir DIR] [--dry-run]
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh"

PROJECT_DIR="."
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="${2:-.}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "✖ unknown argument: $1" >&2; exit 2 ;;
  esac
done

DEFAULTS_FILE="$SCRIPT_DIR/../template/scv/scv_settings.example.json"
[[ -f "$DEFAULTS_FILE" ]] || { echo "no shipped defaults — nothing to merge."; exit 0; }

cd "$PROJECT_DIR" || { echo "✖ cannot enter $PROJECT_DIR" >&2; exit 1; }
TARGET="${SCV_SETTINGS_FILE:-scv/scv_settings.json}"

if [[ ! -f "$TARGET" ]]; then
  echo "no $TARGET yet — nothing to merge (run settings-migrate.sh first, or create it)."
  exit 0
fi
[[ -L "$TARGET" ]] && { echo "✖ $TARGET is a symlink — refusing to write through it." >&2; exit 1; }

USER_JSON="$(cat "$TARGET" 2>/dev/null || true)"
DEFAULTS_JSON="$(_settings_json_strip_underscore "$(cat "$DEFAULTS_FILE" 2>/dev/null || true)")"  # 설명 키(_)는 사용자가 지웠으면 다시 넣지 않는다
MERGED="$(settings_merge_defaults "$USER_JSON" "$DEFAULTS_JSON")"

# 병합이 실패했거나 결과가 이상하면 손대지 않는다. 설정을 잃느니 그대로가 낫다.
if [[ -z "$MERGED" ]]; then
  echo "✖ merge produced nothing — $TARGET was NOT touched." >&2
  exit 1
fi

keys_of() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r 'if type=="object" then keys[] else empty end' 2>/dev/null || true
  else
    printf '%s' "$1" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
if isinstance(d,dict):
    for k in sorted(d): print(k)' 2>/dev/null || true
  fi
}
ADDED="$(comm -13 <(keys_of "$USER_JSON" | sort) <(keys_of "$MERGED" | sort) 2>/dev/null || true)"
N="$(printf '%s' "$ADDED" | grep -c . || true)"

if [[ "${N:-0}" -eq 0 ]]; then
  echo "$TARGET is already up to date — nothing added."
  exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "(dry-run) would add $N key(s) to $TARGET:"
  printf '%s\n' "$ADDED" | sed 's/^/  + /'
  exit 0
fi

printf '%s\n' "$MERGED" > "$TARGET"
echo "added $N new key(s) to $TARGET (existing values untouched):"
printf '%s\n' "$ADDED" | sed 's/^/  + /'
