#!/usr/bin/env bash
# pr-flow.sh — PR 도구(pr-helper.sh)의 순수 판단 (v0.63.0+).
#
#   scv_pr_base_branch   PR 을 어느 브랜치로 열까 — 에픽 > 설정 SCV_PR_BASE > origin 기본 브랜치 > main
#   scv_pr_stray_changes 커밋 안 된 변경 중 PR 도구가 올리지 않을 것 — 있으면 PR 도구는 아무것도 하지 않고 멈춘다
#
# 읽기(git 상태 · 설정)와 쓰기(스테이징 · 커밋 · 푸시)는 pr-helper.sh 가 한다. 여기는 문자열만 다룬다.

# @pure
# <에픽> <SCV_PR_BASE 값> <origin 기본 브랜치> → 대상 브랜치. 설정 값의 공백 · 따옴표는 뺀다.
scv_pr_base_branch() {
  local epic="${1:-}" setting="${2:-}" head="${3:-}"
  setting="${setting//[[:space:]]/}"; setting="${setting//\"/}"; setting="${setting//\'/}"
  if [[ -n "$epic" ]]; then printf 'epic/%s' "$epic"
  elif [[ -n "$setting" ]]; then printf '%s' "$setting"
  elif [[ -n "$head" ]]; then printf '%s' "$head"
  else printf 'main'
  fi
}

# @pure
# <상태 기록> <허용 경로들 — 줄마다 하나, 끝이 / 면 폴더> → 허용 밖 경로, 줄마다 하나.
# 상태 기록은 `git -c core.quotepath=off status --porcelain -z` 의 NUL 을 줄바꿈으로 바꾼 것이다 — 경로가 그대로 온다
# (따옴표 · 8진수 이스케이프 없음 — 한글 폴더도, 이름 안의 " -> " 도 그대로). 이름 바뀜 · 복사(R/C)는 다음 줄이 원래
# 경로라 두 쪽을 모두 본다 — 코드를 SCV 폴더로 옮긴 변경은 지워지는 쪽이 밖이다. 경로 안의 줄바꿈은 지원하지 않는다.
scv_pr_stray_changes() {
  local records="${1:-}" allowed="${2:-}" line path xy orig_next=0 a ok
  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( orig_next )); then
      path="$line"; orig_next=0
    else
      [[ ${#line} -gt 3 ]] || continue
      xy="${line:0:2}"; path="${line:3}"
      [[ "$xy" == *[RC]* ]] && orig_next=1
    fi
    [[ -n "$path" ]] || continue
    ok=0
    while IFS= read -r a || [[ -n "$a" ]]; do
      [[ -n "$a" ]] || continue
      if [[ "$a" == */ ]]; then
        [[ "$path" == "$a"* || "$path/" == "$a" ]] && ok=1
      else
        [[ "$path" == "$a" ]] && ok=1
      fi
      (( ok )) && break
    done <<< "$allowed"
    (( ok )) || printf '%s\n' "$path"
  done <<< "$records"
  return 0
}
