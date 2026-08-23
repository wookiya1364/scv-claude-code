#!/usr/bin/env bash
# settings-migrate.sh — .env 의 SCV 설정을 scv/scv_settings.json 두 벌로 옮긴다.
#
# 한 번만 돌리면 되고, 두 번 돌려도 같은 결과다.
#
# 원본 .env 는 **지우지 않는다.** 프로젝트가 원래 쓰던 파일이라 SCV 와 무관한
# 값이 같이 들어 있을 수 있다. 옮기는 것은 SCV 가 아는 키뿐이고, 나머지 줄은
# 손대지 않는다.
#
# 비밀값(토큰·채널 ID)은 무시 목록에 드는 별도 파일로 간다. 일반 설정은 커밋되는
# 파일로 간다. 어느 쪽인지는 lib/settings.sh 의 목록이 정한다.
#
# Usage:
#   settings-migrate.sh [--project-dir DIR] [--dry-run]
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

cd "$PROJECT_DIR" || { echo "✖ cannot enter $PROJECT_DIR" >&2; exit 1; }

ENV_FILE=".env"
PLAIN="scv/scv_settings.json"
SECRET="scv/scv_settings.secret.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "no .env here — nothing to migrate."
  exit 0
fi
if [[ -f "$PLAIN" || -f "$SECRET" ]]; then
  echo "settings files already exist — nothing was changed."
  echo "  (delete them first if you really want to re-run this)"
  exit 0
fi
[[ -d scv ]] || { echo "✖ no scv/ directory — hydrate the project first." >&2; exit 1; }

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'; }

emit() {  # <키 목록> — 있는 값만 JSON 객체로
  local keys="$1" key val first=1
  printf '{\n'
  for key in $keys; do
    val="$(_settings_from_env_file "$key" "$ENV_FILE")"
    [[ -n "$val" ]] || continue
    [[ $first -eq 1 ]] || printf ',\n'
    printf '  "%s": "%s"' "$key" "$(json_escape "$val")"
    first=0
  done
  [[ $first -eq 1 ]] || printf '\n'
  printf '}\n'
}

PLAIN_JSON="$(emit "$SCV_PLAIN_KEYS")"
SECRET_JSON="$(emit "$SCV_SECRET_KEYS")"

count_of() { printf '%s' "$1" | grep -c '^  "' || true; }
PN="$(count_of "$PLAIN_JSON")"; SN="$(count_of "$SECRET_JSON")"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "(dry-run — nothing written)"
  echo "  $PLAIN   ← $PN setting(s)"
  echo "  $SECRET  ← $SN secret(s)"
  exit 0
fi

printf '%s' "$PLAIN_JSON"  > "$PLAIN"
printf '%s' "$SECRET_JSON" > "$SECRET"
chmod 600 "$SECRET" 2>/dev/null || true

echo "migrated:"
echo "  $PLAIN   ← $PN setting(s)   (committed)"
echo "  $SECRET  ← $SN secret(s)    (git-ignored)"
echo "  $ENV_FILE was NOT touched — remove the SCV lines yourself once you are happy."

if ! git check-ignore -q "$SECRET" 2>/dev/null; then
  echo "" >&2
  echo "⚠ $SECRET is NOT ignored by git yet — add it to .gitignore before committing." >&2
fi
