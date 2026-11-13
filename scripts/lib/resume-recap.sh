#!/usr/bin/env bash
# resume-recap.sh — 비운 직후 되찾기 블록의 문자열부 (v0.47.0+).
#
# 왜 있나: 대화를 지우거나 컨텍스트가 압축되거나 세션을 재개하면, 그 다음 턴의 모델은
# 방금까지 하던 계획·결정·대화를 모른다. 저널과 결정 로그에는 다 남아 있는데 다시
# 읽어 주는 것이 없었다. 세션 시작 훅 템플릿(template/hooks/on-session-start.sh)이
# 그 일을 하고, 여기는 그 훅의 순수부다 — 스위치 해석, 머리말, 활성 대화 고르기.
#
# 여기 있는 것: 문자열을 받아 문자열을 돌려주는 함수 셋. 파일·표준출력·명령 실행은
# 전부 훅이 한다. 순수성 검사(check-purity.sh)가 그 경계를 지킨다.
#
# 코어는 호스트 중립이다 — 이 파일은 이벤트 이름도 matcher 값도 모른다. 어느 경우에
# 훅이 뜰지는 래퍼의 등록이 정한다.

# shellcheck source=switch.sh
declare -F scv_switch >/dev/null 2>&1 || source "${BASH_SOURCE[0]%/*}/switch.sh"

# 스위치 해석 — off 만 끈다. 값이 없거나 다른 값이면 켜져 있다. 기존 세 스위치
# (쉬운말·항상 라우팅·preflight)와 같은 규칙이라야 사용자가 규칙을 하나만 기억한다.
# 두 훅이 서로의 lib 에 묶이지 않게, 공용 구현은 어느 기능의 것도 아닌 lib/switch.sh 에 둔다.
# 같은 규칙의 구현은 lib/switch.sh 의 scv_switch 하나다 — 이 이름은 기존 호출을 위해 남긴다.
scv_resume_switch() { scv_switch "$@"; }

# @pure
# 역할: 컨텍스트가 비워진 이유 한 줄 머리말을 만든다 — source 값이 있으면 그대로 보여 주고 없으면 일반 문구
# 종류: 조립
# 예: clear → $'[SCV resume] The context was just reset (source: clear). Nothing was lost — below is what this project was in the\nmiddle of: active plans, recent decisions, and the active conversation. Continue\nfrom here instead of asking the user to repeat themselves. Switch:\nscv/scv_settings.json SCV_RESUME_RECAP=off.'
# 예: '' → $'[SCV resume] The context was just reset. Nothing was lost — below is what this project was in the\nmiddle of: active plans, recent decisions, and the active conversation. Continue\nfrom here instead of asking the user to repeat themselves. Switch:\nscv/scv_settings.json SCV_RESUME_RECAP=off.'
# 머리말 — 무슨 일로 비워졌는지 한 줄. 입력은 호스트가 stdin JSON 으로 준 source 값
# (있으면). 값이 없거나 모르는 값이면 일반 문구로 간다 — 호스트마다 값이 다를 수 있고,
# 여기서 값을 열거해 두면 코어가 호스트를 아는 셈이 된다. 값은 있으면 그대로 보여 줄 뿐.
scv_resume_header() {
  local src="${1:-}" why
  src="${src//[[:space:]]/}"
  src="${src//\"/}"
  if [[ -n "$src" ]]; then
    why="The context was just reset (source: ${src})."
  else
    why="The context was just reset."
  fi
  printf '%s\n' \
    "[SCV resume] ${why} Nothing was lost — below is what this project was in the" \
    "middle of: active plans, recent decisions, and the active conversation. Continue" \
    "from here instead of asking the user to repeat themselves. Switch:" \
    "scv/scv_settings.json SCV_RESUME_RECAP=off."
}

# @pure
# 역할: 전문으로 실을 대화 하나를 고른다 — 구현 중인 계획에 이어진 대화 가운데 가장 최근에 손댄 것, 없으면 표시가 active 이고 기준 초 안에 손댄 것 가운데 가장 최근 것(동률이면 뒤 줄)
# 종류: 고르기
# 예: $'a.md\tactive\t100\nb.md\tpromoted\t50' "b.md" 200 300 → "b.md"
# 예: $'a.md\tactive\t100\nb.md\tpromoted\t50' "" 200 300 → "a.md"
# 예: $'a.md\tactive\t100' "" 1000 300 → ""
# 예: $'a.md\tactive\t5\nb.md\tactive\t9\nc.md\tdone\t99' "" 0 0 → "b.md"
# <"경로<TAB>표시<TAB>손댄 시각" 줄들> <계획에 이어진 경로 줄들> <지금 시각(에포크 초)> <기준 초> → 경로 하나(없으면 빈 글).
# 전에는 표시가 active 인 가장 최근 것만 골랐다. 끝난 대화가 active 로 남고, 일하던 대화는 계획으로 넘어가며 표시가
# 바뀌어 빠졌다(2026-11-13: active 7개가 모두 4 ~ 35일 전에 끝난 대화였다). 계획에 이어진 대화는 표시와 날짜를 보지 않는다.
# 시각은 정수로 견준다. 손댄 시각을 모르면(0) 오래됐다고 보지 않는다. 기준 초가 0 이하면 날짜를 보지 않는다.
# 숫자인지는 무늬(case)로 본다 — 정규식으로 줄마다 보면 나머지 대화 고르기가 1.22배 느려졌다(2026-11-13 재는 검사).
scv_resume_pick() {
  local lines="${1:-}" linked="${2:-}" now="${3:-0}" max="${4:-0}" path status mtime best="" best_m=-1 nl=$'\n'
  case "$now" in ''|*[!0-9]*) now=0 ;; esac
  case "$max" in ''|*[!0-9]*) max=0 ;; esac
  if [[ -n "$linked" ]]; then
    while IFS=$'\t' read -r path status mtime; do
      [[ -n "$path" && "$nl$linked$nl" == *"$nl$path$nl"* ]] || continue
      case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
      if (( mtime >= best_m )); then best="$path"; best_m="$mtime"; fi
    done <<< "$lines"
    [[ -n "$best" ]] && { printf '%s' "$best"; return 0; }
  fi
  while IFS=$'\t' read -r path status mtime; do
    [[ -n "$path" && "$status" == "active" ]] || continue
    case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
    (( max > 0 && mtime > 0 && now - mtime > max )) && continue
    if (( mtime >= best_m )); then best="$path"; best_m="$mtime"; fi
  done <<< "$lines"
  [[ -n "$best" ]] && printf '%s' "$best"
  return 0
}

# @pure
# 역할: 고른 경로를 뺀 나머지 active 경로들을 한 줄씩 낸다 — 기준 초보다 오래 손대지 않은 것은 빼고(그것은 따로 알린다)
# 종류: 고르기
# 예: $'a.md\tactive\t5\nb.md\tactive\t9' b.md → "a.md"
# 예: $'a.md\tactive\t5\nb.md\tactive\t900' b.md 1000 300 → ""
# 나머지 활성 대화 — 고른 것을 뺀 active 경로들을 한 줄에 하나씩. 전문은 싣지 않고
# 경로만 — 가장 최근 것 하나만 전문이라는 것이 계획의 결정이다.
scv_resume_other_active() {
  local lines="${1:-}" chosen="${2:-}" now="${3:-0}" max="${4:-0}" line path status mtime
  case "$now" in ''|*[!0-9]*) now=0 ;; esac
  case "$max" in ''|*[!0-9]*) max=0 ;; esac
  while IFS=$'\t' read -r path status mtime; do
    [[ -n "$path" && "$status" == "active" ]] || continue
    [[ "$path" == "$chosen" ]] && continue
    case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
    (( max > 0 && mtime > 0 && now - mtime > max )) && continue
    printf '%s\n' "$path"
  done <<< "$lines"
  return 0
}

# @pure
# 역할: 표시가 active 인데 기준 초보다 오래 손대지 않은 대화의 경로들을 한 줄씩 낸다(고른 경로는 빼고) — 끝났을 가능성이 큰 대화
# 종류: 고르기
# 예: $'a.md\tactive\t5\nb.md\tactive\t900' "" 1000 300 → "a.md"
# 예: $'a.md\tactive\t5' a.md 1000 300 → ""
# 예: $'a.md\tactive\t0\nb.md\tdone\t5' "" 1000 300 → ""
scv_resume_stale() {
  local lines="${1:-}" chosen="${2:-}" now="${3:-0}" max="${4:-0}" path status mtime
  case "$now$max" in ''|*[!0-9]*) return 0 ;; esac
  [[ -n "$now" && -n "$max" ]] || return 0
  (( max > 0 )) || return 0
  while IFS=$'\t' read -r path status mtime; do
    [[ -n "$path" && "$status" == "active" && "$path" != "$chosen" ]] || continue
    case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
    (( mtime > 0 && now - mtime > max )) && printf '%s\n' "$path"
  done <<< "$lines"
  return 0
}
