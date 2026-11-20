#!/usr/bin/env bash
# ask-mode.sh — 묻기 모드(SCV_ASK_MODE)를 ends ↔ all 로 바꾼다 (0.97.0+, 계획 20261120-wookiya1364-lean-loop).
#
#   ask-mode.sh            설정 파일의 값을 뒤집는다(all → ends, ends → all)
#   ask-mode.sh ends|all   그 값으로 정한다
#
# 출력: ASK_MODE: <전> -> <후>   (설정 파일 scv/scv_settings.json 의 값)
#       ENV_VALUE: <값>       환경 변수 SCV_ASK_MODE 가 있으면 — 그 값이 설정 파일보다 우선한다
#       EFFECT: next-turn        다음 사람 턴의 안내 줄부터 바뀐다
# 쓰기는 settings-set.sh 하나로만 한다(다른 키는 그대로). 판단은 lib/choices.sh 의 순수 함수.
# Exit: 0 바꿈 · 2 잘못된 인자 · 1 쓰기 실패
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/choices.sh
source "$SCRIPT_DIR/lib/choices.sh" || exit 1
ARG="${1:-}"
# 파일 값만 읽는다 — 설정 읽기는 환경 변수를 먼저 보므로 그 변수를 뺀 채 읽는다.
CUR="$(env -u SCV_ASK_MODE bash "$SCRIPT_DIR/settings-set.sh" --get SCV_ASK_MODE 2>/dev/null || true)"
CUR="$(scv_ask_mode "$CUR")"
NEXT="$(scv_ask_mode_next "$CUR" "$ARG")"
if [[ -z "$NEXT" ]]; then
  echo "ask-mode.sh: 인자는 ends 또는 all (없으면 뒤집기) — 받은 값: $ARG" >&2
  exit 2
fi
bash "$SCRIPT_DIR/settings-set.sh" "SCV_ASK_MODE=$NEXT" >/dev/null || { echo "ask-mode.sh: 설정 파일에 쓰지 못함" >&2; exit 1; }
printf 'ASK_MODE: %s -> %s\n' "$CUR" "$NEXT"
if [[ -n "${SCV_ASK_MODE:-}" ]]; then printf 'ENV_VALUE: %s\n' "$(scv_ask_mode "$SCV_ASK_MODE")"; fi
printf 'EFFECT: next-turn\n'
exit 0
