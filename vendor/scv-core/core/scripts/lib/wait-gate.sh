#!/usr/bin/env bash
# lib/wait-gate.sh — 오래 도는 일은 뒤에서: 앞에서 오래 기다리는 호출을 가른다(계획 20261125-wookiya1364-visible-evidence-background).
#
# 모델이 오래 도는 일을 앞에서 기다리는 동안 사용자가 새 요청을 넣으면 하던 일이 끊긴다(2026-11-25 실제 세션: 200초 대기 중에
# 끊김, 사용자: "계획이 끝까지 완료되는 경우가 적어진다"). 가드가 도구를 부르기 전에 이 판정을 돌려, 긴 대기 값이나 잠자기로
# 기다리는 셸 명령을 거절하고 뒤에서 돌리라고 안내한다. 판정은 받은 글만 본다 — 읽기 · 거절은 가드가 한다.

# @pure
# 역할: 도구 입력이 앞에서 오래 기다리는 호출인지 가른다 — 긴 대기 값이면 wait, 뒤로 보내지 않은 셸 명령이 잠자기로 기다리면 sleep, 아니면 none
# 종류: 판정/gate
# 예: 200000 "" "" → "wait"
# 예: 5000 "" "" → "none"
# 예: "" "" "sleep 120 && tail log" → "sleep"
# 예: "" true "sleep 120 && tail log" → "none"
# 예: "" "" "until grep -q DONE log; do sleep 15; done" → "sleep"
# 예: "" "" "sleep 2; echo ok" → "none"
# 예: "" "" "echo 잠자기 sleepy" → "none"
# <대기 값(ms)> <뒤로 보냄 true|빈 값> <셸 명령> [<대기 한도 ms — 기본 60000> <잠자기 한도 초 — 기본 30>] → none | wait | sleep.
# 기다림 루프(until · while 안의 잠자기)는 길이와 상관없이 잡는다 — 끝날 때까지 앞을 붙잡는 꼴이다. 뒤로 보낸 명령은 건드리지 않는다.
scv_wait_kind() {
  local ms="${1:-}" bg="${2:-}" cmd="${3:-}" maxms="${4:-60000}" maxs="${5:-30}" rest n
  local re_loop='(^|[;&|[:space:](])(until|while)[[:space:]].*[;&|[:space:]]sleep[[:space:]]'
  local re_sleep='(^|[;&|[:space:](])sleep[[:space:]]+([0-9]+)'
  if [[ "$ms" =~ ^[0-9]+$ ]] && (( 10#$ms >= maxms )); then printf 'wait'; return 0; fi
  if [[ "$bg" == true || -z "$cmd" ]]; then printf 'none'; return 0; fi
  if [[ "$cmd" =~ $re_loop ]]; then printf 'sleep'; return 0; fi
  rest="$cmd"
  while [[ "$rest" =~ $re_sleep ]]; do
    n="${BASH_REMATCH[2]}"
    if (( 10#$n >= maxs )); then printf 'sleep'; return 0; fi
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
  printf 'none'
}

# @pure
# 역할: 앞에서 오래 기다리는 호출을 거절할 때의 글을 만든다 — 종류가 none 이거나 모르는 값이면 빈 값
# 종류: 조립/gate
# 예: wait → "[SCV 뒤에서] 오래 도는 일을 앞에서 기다리는 호출이다(대기 값이 길다) — 사용자가 새 요청을 넣으면 하던 일이 끊긴다. 일은 뒤에서 돌리고(끝나면 알림이 온다), 지금 할 수 있는 다른 일을 하거나 턴을 끝내라. 결과는 알림이 온 뒤에 읽는다. 60초보다 짧은 확인은 된다. 끄기: 설정 SCV_BACKGROUND_FIRST=off."
# 예: sleep → "[SCV 뒤에서] 오래 도는 일을 앞에서 기다리는 호출이다(잠자기로 기다리는 명령) — 사용자가 새 요청을 넣으면 하던 일이 끊긴다. 일은 뒤에서 돌리고(끝나면 알림이 온다), 지금 할 수 있는 다른 일을 하거나 턴을 끝내라. 결과는 알림이 온 뒤에 읽는다. 60초보다 짧은 확인은 된다. 끄기: 설정 SCV_BACKGROUND_FIRST=off."
# 예: none → ""
scv_wait_reason() {
  local why=""
  case "${1:-}" in
    wait) why="대기 값이 길다" ;;
    sleep) why="잠자기로 기다리는 명령" ;;
    *) return 0 ;;
  esac
  printf '%s' "[SCV 뒤에서] 오래 도는 일을 앞에서 기다리는 호출이다($why) — 사용자가 새 요청을 넣으면 하던 일이 끊긴다. 일은 뒤에서 돌리고(끝나면 알림이 온다), 지금 할 수 있는 다른 일을 하거나 턴을 끝내라. 결과는 알림이 온 뒤에 읽는다. 60초보다 짧은 확인은 된다. 끄기: 설정 SCV_BACKGROUND_FIRST=off."
}
