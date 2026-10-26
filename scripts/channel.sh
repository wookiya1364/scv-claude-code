#!/usr/bin/env bash
# channel.sh — /scv:channel 의 엔진: 설치된 SCV 를 개발 · 스테이징 · 운영 채널 사이에서 바꿔 끼운다 (0.71.0+).
#
# 규칙 전문은 코어 protocols/channel.md, 순수부는 lib/channel.sh(채널 → 브랜치, 바꿔 끼우기 단계). 여기는 양 끝의 부수효과:
# 지금 상태 읽기와 Claude Code CLI(`claude plugin …`) 실행. ~/.claude/plugins 를 직접 고치지 않고, 프로젝트 파일은 건드리지 않는다.
#
# 흐름: read_state(부수) → scv_channel_plan(순수) → branch_exists(부수, 지우기 전 확인) → run_steps(부수) → read_state(부수)
#
# Usage:
#   channel.sh                 # 지금 채널만 보인다 (아무것도 바꾸지 않음)
#   channel.sh dev|stage|prod  # 그 채널로 바꿔 끼운다
#
# Env (시험용):
#   SCV_CLAUDE_BIN            claude 실행 파일 (기본 claude)
#   SCV_CHANNEL_GIT_BIN       git 실행 파일 (기본 git) — 채널 브랜치가 있는지 확인
#   SCV_CHANNEL_URL           마켓 git 주소 (기본 https://github.com/wookiya1364/scv-claude-code.git)
#
# Output (stdout, 한 줄에 하나):
#   CHANNEL: <dev|stage|prod|other:…> <version|not-installed>
#   STEP: <claude plugin 인자들> ok|fail
#   RESULT: switched <from> <ver> -> <to> <ver> | already <to> <ver> | failed <step> | restored <from>
#   NEXT: <할 일 한 줄>
#
# Exit: 0 성공 · 이미 그 채널, 1 실패, 2 사용법 오류.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/channel.sh
source "$HERE/lib/channel.sh"

CLAUDE_BIN="${SCV_CLAUDE_BIN:-claude}"
GIT_BIN="${SCV_CHANNEL_GIT_BIN:-git}"
URL="${SCV_CHANNEL_URL:-https://github.com/wookiya1364/scv-claude-code.git}"
NAME=scv-claude-code
PLUGIN=scv

usage() { echo 'usage: channel.sh [dev | stage | prod]' >&2; exit 2; }

# step_args <단계 줄> → claude plugin 인자 (lib 의 추상 단계를 이 호스트의 명령으로)
step_args() {
  case "$1" in
    remove) echo "marketplace remove $NAME" ;;
    'add -') echo "marketplace add $URL" ;;
    add\ *) echo "marketplace add $URL#${1#add }" ;;
    install) echo "install $PLUGIN@$NAME" ;;
  esac
}

# read_state → "present ref version" 한 줄 (ref 없음은 '-', 버전 없음은 not-installed). 못 읽으면 1.
read_state() {
  local mk inst present ref ver
  mk="$("$CLAUDE_BIN" plugin marketplace list --json 2>/dev/null)" || return 1
  inst="$("$CLAUDE_BIN" plugin list --json 2>/dev/null)" || return 1
  printf '%s' "$mk" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  present=0; ref=-
  if printf '%s' "$mk" | jq -e --arg n "$NAME" 'any(.[]; .name == $n)' >/dev/null 2>&1; then
    present=1
    ref="$(printf '%s' "$mk" | jq -r --arg n "$NAME" '.[] | select(.name == $n) | .ref // "-"' | head -1)"
  fi
  ver="$(printf '%s' "$inst" | jq -r --arg id "$PLUGIN@$NAME" '
    (if type == "object" then .installed else . end) // [] | .[] | select(.id == $id) | .version // "unknown"' 2>/dev/null | head -1)"
  echo "$present $ref ${ver:-not-installed}"
}

# branch_exists <브랜치> — 지우기 전에 그 채널 브랜치가 원격에 있는지 본다 (없으면 아무것도 지우지 않는다)
branch_exists() {
  [[ -z "$1" ]] && return 0
  "$GIT_BIN" ls-remote --exit-code --heads "$URL" "$1" >/dev/null 2>&1
}

# run_steps <단계 줄들> → STEP: 줄들. 실패하면 그 단계 이름을 마지막 줄 "FAILED <단계>" 로 내고 1.
run_steps() {
  local step args out
  while IFS= read -r step; do
    [[ -n "$step" ]] || continue
    args="$(step_args "$step")"
    # shellcheck disable=SC2086 # 단계는 공백으로 나뉜 인자다(값에 공백 없음).
    if out="$("$CLAUDE_BIN" plugin $args 2>&1)"; then echo "STEP: $args ok"
    else echo "STEP: $args fail"; echo "FAILED $args"; return 1; fi
  done <<<"$1"
}

main() {
  local target=${1:-}
  [[ $# -le 1 ]] || usage
  command -v jq >/dev/null 2>&1 || { echo "RESULT: failed jq-missing"; echo "NEXT: jq 를 설치한다 (/scv:install-deps)"; return 1; }
  command -v "$CLAUDE_BIN" >/dev/null 2>&1 || { echo "RESULT: failed claude-cli-missing"; return 1; }

  local state present ref ver from
  state="$(read_state)" || { echo "RESULT: failed state-unreadable"; echo "NEXT: claude plugin list --json 이 읽히지 않는다 — Claude Code 버전을 확인한다"; return 1; }
  read -r present ref ver <<<"$state"
  [[ "$ref" == - ]] && ref=''
  from="$(scv_channel_of_ref "$ref")"
  echo "CHANNEL: $from $ver"
  [[ -n "$target" ]] || return 0

  local want steps out
  want="$(scv_channel_ref "$target")" || usage
  steps="$(scv_channel_plan "$present" "$ref" "$want")"
  if [[ -z "$steps" && "$ver" != not-installed ]]; then echo "RESULT: already $target $ver"; return 0; fi
  [[ -n "$steps" ]] || steps=install
  if ! branch_exists "$want"; then
    echo "RESULT: failed branch-missing $want"
    echo "NEXT: $want 브랜치가 아직 없다 — 래퍼의 채널 동기화가 처음 돈 뒤 다시 실행한다. 지금 설치는 그대로다"
    return 1
  fi

  if ! out="$(run_steps "$steps")"; then
    printf '%s\n' "$out" | grep -v '^FAILED '
    echo "RESULT: failed $(printf '%s\n' "$out" | sed -n 's/^FAILED //p')"
    # 지운 뒤 실패했으면 원래 채널로 되돌린다 — SCV 가 빠진 채로 두지 않는다.
    if [[ $present -eq 1 ]] && printf '%s\n' "$out" | grep -q '^STEP: marketplace remove .* ok'; then
      if run_steps "$(scv_channel_plan 0 '' "$ref")" >/dev/null; then echo "RESULT: restored $from"
      else echo "NEXT: 원래 채널로 되돌리지 못했다 — /plugin marketplace add $URL 다음 /plugin install $PLUGIN@$NAME"; fi
    fi
    return 1
  fi
  printf '%s\n' "$out"

  local after aver
  after="$(read_state)" || after="0 - not-installed"
  read -r _ _ aver <<<"$after"
  echo "RESULT: switched $from $ver -> $target $aver"
  echo "NEXT: 열린 세션에서 /reload-plugins 를 실행하거나 새 세션을 연다 — 그래야 바뀐 채널이 돈다"
}

# source 될 때는(시험) 함수만 싣는다.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; exit $?; fi
