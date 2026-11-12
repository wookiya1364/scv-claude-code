#!/usr/bin/env bash
# lib/turn-check.sh — 턴 끝 계획 기록 검사의 순수부. 사진 찍기 · 파일 쓰기는 scripts/turn-check.sh.
#
# 무언가를 고친 턴은 계획에 기록이 남아야 끝난다: 턴 시작과 끝의 사진 차이로 바뀐 파일을 구하고,
# 그 턴에 성공한 plan-link 명령(영수증)과 이번 턴 요청 번호가 든 구조 줄이 계획에 생겼는지 본다.
# bash 3.2(맥 기본)에서도 돈다 — mapfile · 연관 배열 · ${v,,} 를 쓰지 않는다.
# 계획 20261109-wookiya1364-turn-plan-check.

# '하지 않음' 항목 꺼내기 · 다듬기는 lib/plan-link.sh 의 것을 쓴다.
declare -F scv_plan_goal_items >/dev/null 2>&1 || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plan-link.sh"

# @pure
# 역할: 도구가 돌린 명령 글이 계획 기록 명령(plan-link 의 기록 다섯 가지)인지 가려 영수증 한 줄을 낸다 — 이름만 적은 명령은 빈 값
# 종류: 판정
# 예: "bash /p/core/scripts/plan-link.sh progress a --step 1 --note x" → "plan-link progress"
# 예: $'cd /w && SCV_TODAY=2026-11-09 bash "/p/plan-link.sh" append a --after 1' → "plan-link append"
# 예: "echo plan-link.sh append; printf x" → ""
# 예: "bash plan-link.sh append a" → ""
# 앞에 `cd <폴더> &&` 하나와 `이름=값` 환경 설정은 허용한다. plan-link 경로는 / 로 시작하는 절대 경로여야 한다.
scv_tc_receipt() {
  local cmd="${1:-}" re
  # 첫 줄만 본다. 줄바꿈이 없는 긴 글에서 "첫 줄바꿈부터 지우기"는 길이의 제곱으로 느리다 — 있을 때만 자른다.
  [[ "$cmd" == *$'\n'* ]] && cmd="${cmd%%$'\n'*}"
  re='^[[:space:]]*(cd[[:space:]]+[^;&|]+(&&|;)[[:space:]]*)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*bash[[:space:]]+"?/[^"[:space:]]*/plan-link\.sh"?[[:space:]]+(append|pause|resume|progress|exempt)([[:space:]]|$)'
  if [[ "$cmd" =~ $re ]]; then
    printf 'plan-link %s' "${BASH_REMATCH[4]}"
  fi
}

# @pure
# 역할: 시작 사진과 끝 사진("경로<TAB>지문" 줄들)을 견줘 이번 턴에 바뀐 경로만 낸다 — 새로 생김 · 지문이 바뀜 · 사라짐
# 종류: 비교
# 예: $'a\t1\nb\t2' $'a\t1\nb\t3\nc\t9' → $'b\nc'
# 예: $'a\t1\nb\t2' $'a\t1' → "b"
# 예: $'a\t1' $'a\t1' → ""
scv_tc_diff() {
  local start="${1:-}" end="${2:-}" line path out="" seen=$'\n'
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ $'\n'"$start"$'\n' != *$'\n'"$line"$'\n'* ]]; then
      path="${line%%$'\t'*}"
      [[ "$seen" == *$'\n'"$path"$'\n'* ]] || { seen="$seen$path"$'\n'; out="$out$path"$'\n'; }
    fi
  done <<< "${end%$'\n'}"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path="${line%%$'\t'*}"
    if [[ $'\n'"$end" != *$'\n'"$path"$'\t'* ]]; then
      [[ "$seen" == *$'\n'"$path"$'\n'* ]] || { seen="$seen$path"$'\n'; out="$out$path"$'\n'; }
    fi
  done <<< "${start%$'\n'}"
  out="${out%$'\n'}"
  [[ -z "$out" ]] || printf '%s' "$out" | LC_ALL=C sort
}

# @pure
# 역할: 바뀐 경로 목록에서 SCV 기록 폴더 · graft 그래프와 호스트가 알려 준 설정 경로(: 로 이은 글롭)를 뺀다 — 계획 · 저널 · 대화는 '일'이 아니다
# 종류: 고르기
# 예: $'scv/promote/a/PLAN.md\nsrc/a.ts\nhost/settings.json\nREADME.md' "host/settings.json" → $'src/a.ts\nREADME.md'
# 예: $'graft/x.md\n.scv-pr-artifacts/a.png\nconf/a.toml' "conf/*" → ""
# 예: "" "" → ""
scv_tc_filter() {
  local paths="${1:-}" extra="${2:-}" p g out="" skip
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    case "$p" in
      scv/*|*/scv/*|graft/*|*/graft/*|.scv-pr-artifacts/*) continue ;;
    esac
    skip=0
    if [[ -n "$extra" ]]; then
      while IFS= read -r g; do
        [[ -n "$g" ]] || continue
        # shellcheck disable=SC2053
        if [[ "$p" == $g || "$p" == *:$g ]]; then skip=1; break; fi
      done <<< "${extra//:/$'\n'}"
    fi
    (( skip )) || out="$out$p"$'\n'
  done <<< "$paths"
  printf '%s' "${out%$'\n'}"
}

# @pure
# 역할: 기록 폴더의 실제 경로들 중 이 저장소 뿌리 아래에 있는 것을 '뺄 글롭'(: 로 이음)으로 바꾼다 — 기록 폴더를 다른 저장소로 연결해 둔 프로젝트에서 그 안 파일을 '일'로 세지 않으려고
# 종류: 변환
# 예: "/b" $'/b/core/raw\n/b/core/journal\n/x/y' → "core/raw/*:core/journal/*"
# 예: "/b" "/b" → "*"
# 예: "/b" "" → ""
scv_tc_record_globs() {
  local root="${1%/}" reals="${2:-}" r out=""
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    r="${r%/}"
    if [[ "$r" == "$root" ]]; then out="$out${out:+:}*"
    elif [[ "$r" == "$root"/* ]]; then out="$out${out:+:}${r#"$root"/}/*"; fi
  done <<< "$reals"
  printf '%s' "$out"
}

# @pure
# 역할: 도구 입력에 어떤 칸이 있는지로 이 도구가 파일을 쓰는지 가른다 — 명령 글이 있으면 shell, 경로와 쓸 내용이 있으면 write, 그 밖(읽기 · 찾기)은 read
# 종류: 판정
# 예: "ls" "" "" → "shell"
# 예: "" "/a/b.ts" "yes" → "write"
# 예: "" "/a/b.ts" "" → "read"
# 세 인자: 명령 글 · 파일 경로 · 쓸 내용이 있는지(비지 않으면 있음). 도구 이름은 보지 않는다(호스트마다 다름).
scv_tc_tool_kind() {
  local cmd="${1:-}" path="${2:-}" body="${3:-}"
  if [[ -n "$cmd" ]]; then printf 'shell'
  elif [[ -n "$path" && -n "$body" ]]; then printf 'write'
  else printf 'read'; fi
}

# @pure
# 역할: 저장소 맨 위 경로와 그 안의 상대 경로 줄들을 이어 절대 경로 줄들로 바꾼다
# 종류: 변환
# 예: "/r" $'a.ts\nsrc/b.ts' → $'/r/a.ts\n/r/src/b.ts'
# 예: "/r" "" → ""
scv_tc_abs_paths() {
  local root="${1%/}" paths="${2:-}" p out=""
  while IFS= read -r p; do
    [[ -n "$p" ]] && out="$out$root/$p"$'\n'
  done <<< "$paths"
  printf '%s' "${out%$'\n'}"
}

# @pure
# 역할: 경로 줄들 중 '이 세션이 쓴 파일' 목록에 있는 것만 남긴다 — 다른 세션이 같은 폴더에서 고친 파일을 뺀다
# 종류: 고르기
# 예: $'/r/a\n/r/b' $'/r/b\n/x/c' → "/r/b"
# 예: "/r/a" "" → ""
scv_tc_mine_only() {
  local paths="${1:-}" mine=$'\n'"${2:-}"$'\n' p out=""
  while IFS= read -r p; do
    [[ -n "$p" && "$mine" == *$'\n'"$p"$'\n'* ]] && out="$out$p"$'\n'
  done <<< "$paths"
  printf '%s' "${out%$'\n'}"
}

# @pure
# 역할: 계획 글에서 새로 생긴 줄들 중 구조 줄(이력 머리: 추가 · 보류 · 연결 · 재개 · 다시 하기 · 진행 · 예외)의 수를 센다
# 종류: 세기
# 예: $'- **2026-11-09 진행** — 6단계: x\n  - 요청: y (요청 ab12cd34)\n- **2026-11-09 10:00 선택** — 답: z' → "1"
# 예: $'- **2026-11-09 추가** — 7단계 뒤에 새 단계\n그냥 메모' → "1"
# 예: "그냥 메모" → "0"
scv_tc_struct_count() {
  local lines="${1:-}" l n=0 re
  re='^- \*\*[0-9]{4}-[0-9]{2}-[0-9]{2} (추가|보류|연결|재개|다시 하기|진행|예외)\*\* — '
  while IFS= read -r l; do
    [[ "$l" =~ $re ]] && n=$((n + 1))
  done <<< "$lines"
  printf '%s' "$n"
}

# @pure
# 역할: 계획 글에서 새로 생긴 줄들 중 이번 턴 요청 번호 꼬리 "(요청 <번호>)" 가 든 줄의 수를 센다
# 종류: 세기
# 예: $'  - 요청: 고쳐 줘 (요청 ab12cd34)\n- x' "ab12cd34" → "1"
# 예: $'  - 요청: 고쳐 줘 (요청 ab12cd34)' "ffff0000" → "0"
# 예: "x" "" → "0"
scv_tc_req_count() {
  local lines="${1:-}" id="${2:-}" l n=0
  [[ -n "$id" ]] || { printf '0'; return 0; }
  while IFS= read -r l; do
    [[ "$l" == *"(요청 $id)"* ]] && n=$((n + 1))
  done <<< "$lines"
  printf '%s' "$n"
}

# @pure
# 역할: 기록 줄에 붙일 요청 꼬리를 만든다 — 사용자 원문 앞부분(줄바꿈은 빈칸, 80자) + "(요청 <번호>)"
# 종류: 변환
# 예: "ab12cd34" "전사 체력 87로 수정해" → "요청: 전사 체력 87로 수정해 (요청 ab12cd34)"
# 예: "ab12cd34" $'두 줄\n요청' → "요청: 두 줄 요청 (요청 ab12cd34)"
# 예: "" "x" → ""
scv_tc_req_tag() {
  local id="${1:-}" text="${2:-}"
  [[ -n "$id" ]] || return 0
  text="${text//$'\r'/ }"; text="${text//$'\n'/ }"; text="${text//$'\t'/ }"
  while [[ "$text" == *"  "* ]]; do text="${text//  / }"; done
  text="${text# }"; text="${text% }"
  if (( ${#text} > 80 )); then text="${text:0:80}…"; fi
  [[ -n "$text" ]] || text="(원문 없음)"
  printf '요청: %s (요청 %s)' "$text" "$id"
}

# @pure
# 역할: 계획 안 일의 진행 한 줄(이력 항목)을 만든다 — 머리 줄(단계 · 시작/끝/막힘) + 요청 꼬리. 대시보드가 이 줄로 단계 상태를 센다. 상태를 안 주면 시작(0.87.4 — 끝은 직접 말할 때만)
# 종류: 조립
# 예: "2026-11-09" 6 done "2인 적 배수" "요청: x (요청 ab12cd34)" → $'**2026-11-09 진행** — 6단계 끝: 2인 적 배수\n요청: x (요청 ab12cd34)'
# 예: "2026-11-09" 1 doing "준비" "" → "**2026-11-09 진행** — 1단계 시작: 준비"
# 예: "2026-11-09" 1 "" "측정 중" "" → "**2026-11-09 진행** — 1단계 시작: 측정 중"
# 예: "2026-11-09" 2 blocked "키 없음" "" → "**2026-11-09 진행** — 2단계 막힘: 키 없음"
scv_tc_progress_entry() {
  local day="${1:-}" step="${2:-}" state="${3:-doing}" note="${4:-}" tag="${5:-}" word=시작
  case "$state" in done) word=끝 ;; blocked) word=막힘 ;; esac
  printf '**%s 진행** — %s단계 %s: %s' "$day" "$step" "$word" "$note"
  [[ -z "$tag" ]] || printf '\n%s' "$tag"
}

# @pure
# 역할: 항목 낱말들 중 메모 낱말에 있는 것의 수와 항목 낱말 수를 "겹친 수 전체 수"로 낸다 — 같은 낱말은 한 번만 센다
# 종류: 세기
# 예: "환불" "환불 버튼" → "1 1"
# 예: "가나 다라 마바 사아" "가나 사아 자차" → "2 4"
# 예: "" "가나" → "0 0"
scv_tc_overlap_count() {
  local item="${1:-}" text=" ${2:-} " w n=0 t=0 seen=" "
  for w in $item; do
    [[ "$seen" == *" $w "* ]] && continue
    seen="$seen$w "
    t=$((t + 1))
    [[ "$text" == *" $w "* ]] && n=$((n + 1))
  done
  printf '%s %s' "$n" "$t"
}

# @pure
# 역할: 덧붙이거나 진행으로 적으려는 글에 계획의 '하지 않음'(Non-Goals) 항목 낱말의 절반 이상이 들어 있으면 한 줄씩 낸다 — 겹치면 사용자에게 물을 일
# 종류: 판정
# 예: $'## Goals / Non-Goals\n- **Goals**\n  - 결제 버튼\n- **Non-Goals**\n  - 환불 기능' "환불 버튼 추가" → "충돌 · 하지 않기로 함: 환불 기능 ↔ 적으려는 글: 환불 버튼 추가"
# 예: $'## Goals / Non-Goals\n- **Non-Goals**\n  - 환불 기능' "결제 버튼 색" → ""
# 예: $'## Goals / Non-Goals\n- **Non-Goals**\n  - 답 모양 같은 output 규칙의 내용을 바꾸는 일' "시험 파일을 새 모양에 맞춤" → ""
# 예: "# a" "x" → ""
# 낱말 = 2자 이상, 조사 · 흔한 말(기능 · 추가 · 수정 · 변경 · 화면 · 단계 · 계획 · 사용자)은 뺀다. 항목 낱말의 절반 이상(겹친 수 × 2 ≥ 항목 낱말 수)일 때만 충돌 —
# 낱말 하나만 같은 글을 막지 않으려고(0.88.2). 뜻의 충돌은 모델이 판단한다.
scv_tc_nongoal_hits() {
  local plan="${1:-}" text="${2:-}" ng tw out="" n t
  tw="$(scv_tc_words "$text")"
  [[ -n "$tw" ]] || return 0
  while IFS= read -r ng; do
    [[ -n "$ng" ]] || continue
    read -r n t <<< "$(scv_tc_overlap_count "$(scv_tc_words "$(scv_plan_norm_req "$ng")")" "$tw")"
    if (( ${t:-0} > 0 && ${n:-0} * 2 >= t )); then
      [[ -n "$out" ]] && out="$out"$'\n'
      out="${out}충돌 · 하지 않기로 함: $ng ↔ 적으려는 글: $text"
    fi
  done <<< "$(scv_plan_goal_items "$plan" Non-Goals)"
  printf '%s' "$out"
}

# @pure
# 역할: 글을 맞대기용 낱말들로 나눈다 — 2자 이상, 끝 조사를 떼고, 흔한 말은 뺀다(빈칸으로 이음)
# 종류: 다듬기
# 예: "환불 버튼을 추가해" → "환불 버튼 추가해"
# 예: "결제 화면 기능" → "결제"
# 예: "x" → ""
scv_tc_words() {
  local t="${1:-}" w out="" c clean="" i=0 n step=8
  # 낱말 글자가 아닌 것을 빈칸으로 바꾼다 — 긴 글을 통째로 바꾸면 길이의 제곱으로 느려서(옛 셸은 훨씬 더)
  # 짧은 토막으로 잘라 바꾼다. 글자 하나짜리 무늬라 어디서 잘라도 답은 같다.
  [[ ${BASH_VERSINFO[0]} -ge 4 ]] && step=32
  n=${#t}
  while [[ $i -lt $n ]]; do c="${t:i:step}"; clean+="${c//[^[:alnum:]가-힣%]/ }"; i=$((i + step)); done
  for w in $clean; do
    case "$w" in
      *으로|*에서|*에게|*부터|*까지) w="${w%??}" ;;
      *은|*는|*이|*가|*을|*를|*의|*에|*로|*도|*만|*와|*과) w="${w%?}" ;;
    esac
    (( ${#w} >= 2 )) || continue
    case "$w" in 기능|추가|수정|변경|화면|단계|계획|사용자|하기|한다|있음|없음) continue ;; esac
    out+="${out:+ }$w"
  done
  printf '%s' "$out"
}

# @pure
# 역할: 호스트 설정 글에 대시보드(단계 보고 도구를 주는 모드)가 켜졌다는 표시가 있는지 가린다
# 종류: 판정
# 예: $'{"enabledPlugins": {"scv-dashboard@scv-mods": true}}' '"scv-dashboard@scv-mods": true' → "yes"
# 예: $'{"enabledPlugins": {"scv-dashboard@scv-mods": false}}' '"scv-dashboard@scv-mods": true' → "no"
# 예: "x" "" → "no"
scv_tc_step_on() {
  local text="${1:-}" mark="${2:-}"
  [[ -n "$mark" && "$text" == *"$mark"* ]] && { printf 'yes'; return 0; }
  printf 'no'
}

# @pure
# 역할: 계획 없이 해도 되는 정한 예외 종류인지 가린다 — 릴리스 · 동기화만
# 종류: 판정
# 예: "release" → "yes"
# 예: "sync" → "yes"
# 예: "misc" → "no"
scv_tc_exempt_ok() {
  case "${1:-}" in release|sync) printf 'yes' ;; *) printf 'no' ;; esac
}

# @pure
# 역할: 예외 기록 한 줄(이력 항목)을 만든다 — 종류 · 이유 + 요청 꼬리
# 종류: 조립
# 예: "2026-11-09" "release" "래퍼 0.86.0" "요청: x (요청 ab12cd34)" → $'**2026-11-09 예외** — release: 래퍼 0.86.0\n요청: x (요청 ab12cd34)'
scv_tc_exempt_entry() {
  local day="${1:-}" kind="${2:-}" why="${3:-}" tag="${4:-}"
  printf '**%s 예외** — %s: %s' "$day" "$kind" "$why"
  [[ -z "$tag" ]] || printf '\n%s' "$tag"
}

# @pure
# 역할: 선택 답 한 개를 계획 변경 이력 항목으로 만든다 — 답이 머리, 질문이 아래(각 120자)
# 종류: 조립
# 예: "2026-11-09" "10:24" "어떻게 할까요?" "추천대로" → $'**2026-11-09 10:24 선택** — 답: 추천대로\n질문: 어떻게 할까요?'
# 예: "2026-11-09" "10:24" $'두\n줄' "a" → $'**2026-11-09 10:24 선택** — 답: a\n질문: 두 줄'
scv_tc_choice_entry() {
  local day="${1:-}" hm="${2:-}" q="${3:-}" a="${4:-}"
  q="${q//$'\n'/ }"; a="${a//$'\n'/ }"
  (( ${#q} > 120 )) && q="${q:0:120}…"
  (( ${#a} > 120 )) && a="${a:0:120}…"
  printf '**%s %s 선택** — 답: %s\n질문: %s' "$day" "$hm" "$a" "$q"
}

# @pure
# 역할: 턴 끝 판정 — 바뀐 파일 · 영수증 · 새 구조 줄 · 요청 번호 줄 · 예외 · 진행 중 계획 수 · 막힌 횟수 · 단계 보고 필요/횟수 · 되돌아갈 계획으로 통과 여부를 정한다
# 종류: 판정/gate
# 예: 0 0 0 0 no 1 0 no 0 "" → "pass"
# 예: 2 1 1 1 no 1 0 no 0 "" → "pass"
# 예: 2 0 1 1 no 1 0 no 0 "" → "block in-plan"
# 예: 2 1 0 0 no 0 0 no 0 "" → "block no-plan"
# 예: 2 1 0 0 yes 0 0 no 0 "" → "pass"
# 예: 2 0 0 0 no 1 2 no 0 "" → "pass-unrecorded"
# 예: 2 1 1 1 no 1 0 yes 0 "" → "block step"
# 예: 2 1 1 1 no 1 0 yes 1 "" → "pass"
# 예: 2 1 1 1 no 1 0 no 0 "b" → "block return"
# 차례: 계획 기록 → 단계 보고 → 되돌아가기. 막힘이 2번 쌓이면 통과시키고 '계획 기록 없음'을 남긴다 — 호스트가 끝없는 막힘을 끊기 전에.
scv_tc_judge() {
  local changed="${1:-0}" receipts="${2:-0}" structs="${3:-0}" reqs="${4:-0}" exempt="${5:-no}" plans="${6:-0}" blocks="${7:-0}"
  local need_step="${8:-no}" steps="${9:-0}" orphan="${10:-}"
  (( changed > 0 )) || { printf 'pass'; return 0; }
  local recorded=0
  if (( receipts > 0 )) && { [[ "$exempt" == yes ]] || (( structs > 0 && reqs > 0 )); }; then recorded=1; fi
  if (( recorded )) && { [[ "$need_step" != yes ]] || (( steps > 0 )); } && [[ -z "$orphan" ]]; then printf 'pass'; return 0; fi
  (( blocks >= 2 )) && { printf 'pass-unrecorded'; return 0; }
  if (( ! recorded )); then
    if (( plans > 0 )); then printf 'block in-plan'; else printf 'block no-plan'; fi
  elif [[ "$need_step" == yes ]] && (( steps == 0 )); then printf 'block step'
  else printf 'block return'; fi
}

# @pure
# 역할: 막을 때 모델에게 줄 말을 만든다 — 무엇이 빠졌는지와 할 일 한 줄(명령 꼴 그대로)
# 종류: 조립
# 예: "in-plan" "a" 3 "/p/plan-link.sh" → $'[SCV 계획 기록] 이번 턴에 파일 3개가 바뀌었는데 계획 기록이 없다 — 계획 안 일이면: bash /p/plan-link.sh progress a --step 번호 --state doing --note "한 일" (단계가 끝났을 때만 --state done)\n계획 밖 일이면: bash /p/plan-link.sh append a --after 번호 --step "단계" --why "이유"'
# 예: "no-plan" "" 1 "/p/plan-link.sh" → $'[SCV 계획 기록] 이번 턴에 파일 1개가 바뀌었는데 진행 중 계획이 없다 — 계획을 만들어라(promote). 릴리스 · 동기화만 예외: bash /p/plan-link.sh exempt --kind release --why "이유"'
# 예: "step" "tool_x" 2 "/p/plan-link.sh" → "[SCV 단계 보고] 대시보드가 켜져 있다 — 이번 턴에 한 단계를 tool_x 로 알려라(시작 · 끝 · 막힘)."
# 예: "return" "b" 2 "/p/plan-link.sh" → "[SCV 되돌아가기] 계획 b 가 끝났는데 그것 때문에 보류한 계획이 아직 보류다 — bash /p/plan-link.sh resume b"
scv_tc_block_msg() {
  local kind="${1:-}" slug="${2:-}" n="${3:-0}" pl="${4:-plan-link.sh}"
  case "$kind" in
    in-plan) printf '[SCV 계획 기록] 이번 턴에 파일 %s개가 바뀌었는데 계획 기록이 없다 — 계획 안 일이면: bash %s progress %s --step 번호 --state doing --note "한 일" (단계가 끝났을 때만 --state done)\n계획 밖 일이면: bash %s append %s --after 번호 --step "단계" --why "이유"' "$n" "$pl" "$slug" "$pl" "$slug" ;;
    step) printf '[SCV 단계 보고] 대시보드가 켜져 있다 — 이번 턴에 한 단계를 %s 로 알려라(시작 · 끝 · 막힘).' "$slug" ;;
    return) printf '[SCV 되돌아가기] 계획 %s 가 끝났는데 그것 때문에 보류한 계획이 아직 보류다 — bash %s resume %s' "$slug" "$pl" "$slug" ;;
    *) printf '[SCV 계획 기록] 이번 턴에 파일 %s개가 바뀌었는데 진행 중 계획이 없다 — 계획을 만들어라(promote). 릴리스 · 동기화만 예외: bash %s exempt --kind release --why "이유"' "$n" "$pl" ;;
  esac
}

# @pure
# 역할: 계획 글 여러 개의 이력 · 단계 줄을 모아 정렬한 묶음으로 만든다 — 시작 · 끝 묶음의 차이가 '새로 생긴 줄'
# 종류: 변환
# 예: $'# a\n- **2026-11-09 진행** — 1단계: x\n본문\n  - 요청: y (요청 ab)' → $'  - 요청: y (요청 ab)\n- **2026-11-09 진행** — 1단계: x'
# 예: "본문만" → ""
scv_tc_plan_lines() {
  local text="${1:-}" l out=""
  while IFS= read -r l; do
    case "$l" in
      "- **"*|"  - "*) out="$out$l"$'\n' ;;
    esac
  done <<< "$text"
  [[ -z "$out" ]] || printf '%s' "${out%$'\n'}" | LC_ALL=C sort
}

# @pure
# 역할: 정렬된 두 묶음에서 뒤 묶음에만 있는 줄을 낸다 — 같은 줄이 늘어난 것도 센다
# 종류: 비교
# 예: $'a\nb' $'a\nb\nc' → "c"
# 예: $'a' $'a\na' → "a"
# 예: $'a\nb' $'a' → ""
scv_tc_new_lines() {
  local before="${1:-}" after="${2:-}" l rest out=""
  [[ -n "$after" ]] || return 0
  rest=$'\n'"$before"$'\n'
  while IFS= read -r l; do
    [[ -n "$l" ]] || continue
    if [[ "$rest" == *$'\n'"$l"$'\n'* ]]; then
      rest="${rest/$'\n'"$l"$'\n'/$'\n'}"
    else
      out="$out$l"$'\n'
    fi
  done <<< "$after"
  printf '%s' "${out%$'\n'}"
}
