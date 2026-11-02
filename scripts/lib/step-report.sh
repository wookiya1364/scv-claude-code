#!/usr/bin/env bash
# lib/step-report.sh — 계획 단계 보고 안내 한 줄의 순수부. 읽기 · 출력은 scripts/step-report.sh 가 맡는다.
#
# '언제 알리나'는 코어(work · codegen 규약과 이 한 줄), '어떤 도구로'는 래퍼 호스트 설정 SCV_STEP_TOOL 이다
# (사용자 결정 2026-11-02, 계획 20261102-wookiya1364-step-report).

# @pure
# 역할: "계획<TAB>상태" 줄들 중 구현 중(in_progress · testing)인 계획 이름 하나를 고른다 — 여럿이면 마지막 줄(줄은 이름순으로 받는다 — 날짜가 앞이라 가장 최근)
# 종류: 고르기
# 예: $'20260101-a-x\tplanned\n20260102-a-y\tin_progress' → "20260102-a-y"
# 예: $'20260101-a-x\ttesting\n20260103-a-z\tin_progress' → "20260103-a-z"
# 예: $'20260101-a-x\tplanned' → ""
scv_step_active_plan() {
  local line slug status pick=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    slug="${line%%$'\t'*}"; status="${line#*$'\t'}"
    case "$status" in
      in_progress|testing) pick="$slug" ;;
    esac
  done <<< "${1:-}"
  printf '%s' "$pick"
}

# @pure
# 역할: 단계 보고 도구 이름과 구현 중인 계획 이름으로 매 턴 안내 한 줄을 만든다 — 둘 중 하나라도 비면 아무것도 내지 않는다
# 종류: 조립
# 예: "demo_step" "20260102-a-y" → "[SCV 단계] 구현 중: 20260102-a-y — 이 세션에 demo_step 도구가 있으면, 단계를 시작할 때 · 끝낼 때 · 막혔을 때(이유 한 줄) 바로 알려라(plan=20260102-a-y, step=번호, state=doing|done|blocked). 본문: protocols/work.md 'Step progress'"
# 예: "" "20260102-a-y" → ""
# 예: "demo_step" "" → ""
scv_step_line() {
  local tool="${1:-}" plan="${2:-}"
  [[ -n "$tool" && -n "$plan" ]] || return 0
  printf "[SCV 단계] 구현 중: %s — 이 세션에 %s 도구가 있으면, 단계를 시작할 때 · 끝낼 때 · 막혔을 때(이유 한 줄) 바로 알려라(plan=%s, step=번호, state=doing|done|blocked). 본문: protocols/work.md 'Step progress'" "$plan" "$tool" "$plan"
}
