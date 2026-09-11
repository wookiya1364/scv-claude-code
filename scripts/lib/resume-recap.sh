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

# @pure
# 스위치 해석 — off 만 끈다. 값이 없거나 다른 값이면 켜져 있다. 기존 세 스위치
# (쉬운말·항상 라우팅·preflight)와 같은 규칙이라야 사용자가 규칙을 하나만 기억한다.
# force-help.sh 의 함수와 규칙이 같지만 일부러 따로 둔다 — 두 훅이 서로 묶이지 않게.
scv_resume_switch() {
  local v="${1:-}"
  v="${v//[[:space:]]/}"
  v="${v//\"/}"
  v="${v//\'/}"
  case "$v" in
    [Oo][Ff][Ff]) printf 'off' ;;
    *)            printf 'on'  ;;
  esac
}

# @pure
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
# 활성 대화 고르기 — "경로<TAB>status<TAB>mtime" 줄 목록에서 status 가 active 인 것 중
# mtime 이 가장 큰 경로 하나를 낸다. 없으면 아무것도 내지 않는다.
# mtime 은 정수(에포크 초). 비교는 산술로 — 문자열 비교는 자릿수가 다르면 틀린다.
# 동률이면 뒤에 온 줄이 이긴다 — 훅은 파일명 순으로 주므로 이름(타임스탬프)이 큰 쪽.
scv_resume_pick_active() {
  local lines="${1:-}" line path status mtime best="" best_m=-1
  while IFS=$'\t' read -r path status mtime; do
    [[ -n "$path" && "$status" == "active" ]] || continue
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
    if (( mtime >= best_m )); then best="$path"; best_m="$mtime"; fi
  done <<< "$lines"
  [[ -n "$best" ]] && printf '%s' "$best"
  return 0
}

# @pure
# 나머지 활성 대화 — 고른 것을 뺀 active 경로들을 한 줄에 하나씩. 전문은 싣지 않고
# 경로만 — 가장 최근 것 하나만 전문이라는 것이 계획의 결정이다.
scv_resume_other_active() {
  local lines="${1:-}" chosen="${2:-}" line path status mtime
  while IFS=$'\t' read -r path status mtime; do
    [[ -n "$path" && "$status" == "active" ]] || continue
    [[ "$path" == "$chosen" ]] && continue
    printf '%s\n' "$path"
  done <<< "$lines"
  return 0
}
