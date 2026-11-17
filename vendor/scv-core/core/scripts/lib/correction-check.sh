#!/usr/bin/env bash
# lib/correction-check.sh — 고쳐 달라는 턴 뒤에 "이 정정을 검사로 남길까요?"를 묻게 하는 안내(0.95.0+).
#
# 왜: 사용자가 고쳐 준 것은 지금까지 메모리 · 규칙 글로만 남았다. 글은 읽고도 안 따를 수 있고, 같은 정정을 또 하게 된다.
# 검사(시험 · 린트 · 훅)는 통과 못 하면 멈춘다 — 그래서 정정이 보이는 턴에 한 번, 검사로 남길지 사용자에게 묻게 한다.
# 고르는 것은 사용자다: 이 안내는 묻게 할 뿐 파일을 만들지 않는다.
#
# 언제 싣나: 사람 메시지에 고쳐 달라는 단서가 있고(scv_show_real_is_correction — 완료 뒤 수정 요구를 세는 그 판정),
# 직전 턴이 끝났고 그 턴이 파일을 바꿨을 때만. 그래서 세션 첫 턴 · 일을 안 한 턴 뒤의 "고쳐 줘"(새 요청)에는 싣지 않는다.
# 계획 20261117-wookiya1364-checks-not-comments 2단계.

# 정정 판정은 결과 보여 주기 판정(같은 폴더의 show-real.sh)의 것을 그대로 쓴다.
# shellcheck source=show-real.sh
source "$(dirname "${BASH_SOURCE[0]}")/show-real.sh"

# @pure
# 역할: 고쳐 달라는 말인지 · 직전 턴이 끝났는지 · 직전 턴이 바꾼 파일 수로, 검사로 남기기를 묻게 할 안내 한 줄을 낸다
# 종류: 조립/notice
# 예: 1 1 3 korean → "[SCV 정정] 직전 턴의 일을 고쳐 달라는 말로 보인다 — 고친 뒤, 같은 실수를 다시 막을 검사(시험 · 린트 · 훅)로 남길지 선택 창으로 물어라(보기: 검사로 남기기 · 넘어가기). 고르기 전에는 검사 파일을 만들지 않는다."
# 예: 1 1 3 english → "[SCV correction] This reads as a correction of the last turn's work — after fixing it, ask with the choice tool whether to keep it as a check (test · lint · hook) that stops the same mistake (options: keep as a check · skip). Create no check file before the answer."
# 예: 1 0 3 korean → ""
# 예: 1 1 0 korean → ""
# 예: 0 1 3 korean → ""
# <정정 0|1> <직전 턴 끝남 0|1> <직전 턴이 바꾼 파일 수> <언어> → 한 줄 | 빈 값.
scv_correction_notice() {
  local corr="${1:-0}" ended="${2:-0}" n="${3:-0}" lang="${4:-}"
  [[ "$corr" == 1 && "$ended" == 1 && "$n" =~ ^[1-9][0-9]*$ ]] || return 0
  case "$lang" in
    korean|ko) printf '%s' "[SCV 정정] 직전 턴의 일을 고쳐 달라는 말로 보인다 — 고친 뒤, 같은 실수를 다시 막을 검사(시험 · 린트 · 훅)로 남길지 선택 창으로 물어라(보기: 검사로 남기기 · 넘어가기). 고르기 전에는 검사 파일을 만들지 않는다." ;;
    *) printf '%s' "[SCV correction] This reads as a correction of the last turn's work — after fixing it, ask with the choice tool whether to keep it as a check (test · lint · hook) that stops the same mistake (options: keep as a check · skip). Create no check file before the answer." ;;
  esac
}
