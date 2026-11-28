#!/usr/bin/env bash
# lib/plan-link.sh — 계획 밖 요구를 다루는 순수부. 파일 읽기 · 쓰기는 scripts/plan-link.sh.
#
# 같은 목표의 요구는 기존 계획에 단계를 넣고(append), 다른 목표의 요구는 기존 계획 A 를 보류로 바꾸고
# 새 계획 B 에 "끝나면 A 로 돌아감"을 적는다(pause · link). B 가 끝나면 A 를 다시 진행 중으로 돌린다(resume).
# 모든 변경은 PLAN.md 의 `## 변경 이력` 에 한 줄씩 남아, 계획 파일 하나로 멈춤 · 이유 · 복귀가 보인다.
# bash 3.2(맥 기본)에서도 돈다 — mapfile · 연관 배열 · ${v,,} 를 쓰지 않는다.
# 계획 20261109-wookiya1364-plan-pause-and-return.

# @pure
# 역할: PLAN.md 글의 앞머리에서 한 칸의 값을 꺼낸다 — 칸이 없거나 앞머리가 없으면 빈 값
# 종류: 꺼내기
# 예: $'---\nstatus: paused\npaused_by: b\n---\n# a' "paused_by" → "b"
# 예: $'---\nstatus: paused\n---' "return_to" → ""
# 예: "# a" "status" → ""
scv_plan_fm_get() {
  local text="${1:-}" key="${2:-}" line n=0 v
  [[ "$text" == ---* ]] || return 0
  while IFS= read -r line; do
    n=$((n + 1))
    (( n == 1 )) && continue
    [[ "$line" == "---" ]] && return 0
    if [[ "$line" == "$key:"* ]]; then
      v="${line#"$key":}"; v="${v# }"; v="${v#\"}"; v="${v%\"}"
      printf '%s' "$v"
      return 0
    fi
  done <<< "$text"
}

# @pure
# 역할: PLAN.md 글의 앞머리에서 한 칸을 바꾼다 — 칸이 없으면 앞머리 끝(닫는 --- 바로 앞)에 새로 둔다
# 종류: 변환
# 예: $'---\nstatus: planned\n---\n# a' "status" "paused" → $'---\nstatus: paused\n---\n# a'
# 예: $'---\nstatus: paused\n---\n# a' "paused_by" "b" → $'---\nstatus: paused\npaused_by: b\n---\n# a'
# 예: "# a" "status" "paused" → "# a"
# 앞머리가 없으면(첫 줄이 --- 가 아니면) 글을 그대로 돌려준다.
scv_plan_fm_set() {
  local text="${1:-}" key="${2:-}" val="${3:-}" line out="" n=0 in_fm=0 has=0 placed=0 body
  [[ "$text" == ---* ]] || { printf '%s' "$text"; return 0; }
  [[ -n "$(scv_plan_fm_has "$text" "$key")" ]] && has=1
  # 줄은 += 로 붙이고 끝의 줄바꿈은 마지막 글자만 보고 뗀다 — out="$out…" 은 붙일 때마다 글 전체를 다시 펼치고,
  # ${text%줄바꿈} 은 줄바꿈으로 끝나지 않는 글을 처음까지 훑어, 글이 4배면 시간이 8배를 넘었다(아래 네 함수도 같다).
  body="$text"; [[ "${text: -1}" == $'\n' ]] && body="${text%?}"
  while IFS= read -r line; do
    n=$((n + 1))
    if (( n == 1 )); then out="$line"; in_fm=1; continue; fi
    if (( in_fm )); then
      if [[ "$line" == "---" ]]; then
        in_fm=0
        (( has || placed )) || { out="$out"$'\n'"$key: $val"; placed=1; }
      elif [[ "$line" == "$key:"* ]]; then
        line="$key: $val"
      fi
    fi
    out+=$'\n'"$line"
  done <<< "$body"
  [[ "$text" == *$'\n' ]] && out="$out"$'\n'
  printf '%s' "$out"
}

# @pure
# 역할: PLAN.md 글의 앞머리에 그 칸이 있으면 "1" 을 낸다 — 값이 비어 있어도 칸이 있으면 "1"
# 종류: 판정
# 예: $'---\nstatus: paused\nresume_at:\n---' "resume_at" → "1"
# 예: $'---\nstatus: paused\n---' "resume_at" → ""
# 예: "# a" "status" → ""
scv_plan_fm_has() {
  local text="${1:-}" key="${2:-}" line n=0
  [[ "$text" == ---* ]] || return 0
  while IFS= read -r line; do
    n=$((n + 1))
    (( n == 1 )) && continue
    [[ "$line" == "---" ]] && return 0
    [[ "$line" == "$key:"* ]] && { printf '1'; return 0; }
  done <<< "$text"
}

# @pure
# 역할: PLAN.md 글의 앞머리에서 한 칸의 줄을 지운다 — 칸이 없으면 글을 그대로 돌려준다
# 종류: 변환
# 예: $'---\nstatus: paused\npaused_by: b\n---\n# a' "paused_by" → $'---\nstatus: paused\n---\n# a'
# 예: $'---\nstatus: paused\n---' "paused_by" → $'---\nstatus: paused\n---'
# 예: "# a" "status" → "# a"
scv_plan_fm_drop() {
  local text="${1:-}" key="${2:-}" line out="" n=0 in_fm=0 body
  [[ "$text" == ---* ]] || { printf '%s' "$text"; return 0; }
  body="$text"; [[ "${text: -1}" == $'\n' ]] && body="${text%?}"
  while IFS= read -r line; do
    n=$((n + 1))
    if (( n == 1 )); then out="$line"; in_fm=1; continue; fi
    if (( in_fm )); then
      [[ "$line" == "---" ]] && in_fm=0
      (( in_fm )) && [[ "$line" == "$key:"* ]] && continue
    fi
    out+=$'\n'"$line"
  done <<< "$body"
  [[ "$text" == *$'\n' ]] && out="$out"$'\n'
  printf '%s' "$out"
}

# @pure
# 역할: PLAN.md 글의 `## 변경 이력` 절 끝에 사건 하나를 붙인다 — 첫 줄은 "- " 항목, 나머지 줄은 "  - " 하위 항목, 사건 사이는 빈 줄. 절이 없으면 `## Links` 앞(없으면 글 끝)에 새로 만든다
# 종류: 조립
# 예: $'# a\n\n## 변경 이력\n\n- 1\n\n## Links\n' $'2\n이유: x' → $'# a\n\n## 변경 이력\n\n- 1\n\n- 2\n  - 이유: x\n\n## Links\n'
# 예: $'# a\n\n## Links\n' "1" → $'# a\n\n## 변경 이력\n\n- 1\n\n## Links\n'
# 예: "# a" "1" → $'# a\n\n## 변경 이력\n\n- 1'
scv_plan_history_add() {
  local text="${1:-}" entry="${2:-}" line out="" first=1 in_hist=0 has_hist=0 has_links=0 pending="" done_ins=0 block="" el n=0 body
  while IFS= read -r el; do
    n=$((n + 1))
    if (( n == 1 )); then block="- $el"; else block="$block"$'\n'"  - $el"; fi
  done <<< "$entry"
  case "$text" in *$'\n'"## 변경 이력"*|"## 변경 이력"*) has_hist=1 ;; esac
  case "$text" in *$'\n'"## Links"*|"## Links"*) has_links=1 ;; esac
  body="$text"; [[ "${text: -1}" == $'\n' ]] && body="${text%?}"
  while IFS= read -r line; do
    if (( has_hist )); then
      if (( in_hist )) && (( ! done_ins )) && [[ "$line" == "## "* ]]; then
        out="$out"$'\n\n'"$block$pending"; pending=""; done_ins=1; in_hist=0
      elif (( in_hist )) && [[ -z "$line" ]]; then
        pending="$pending"$'\n'; continue
      elif (( in_hist )) && [[ -n "$pending" ]]; then
        out+="$pending"; pending=""
      fi
      [[ "$line" == "## 변경 이력" ]] && in_hist=1
    elif (( has_links )) && (( ! done_ins )) && [[ "$line" == "## Links" ]]; then
      if (( first )); then out=$'## 변경 이력\n\n'"$block"$'\n'; else out="$out"$'\n'"## 변경 이력"$'\n\n'"$block"$'\n'; fi
      done_ins=1
      out="$out"$'\n'"$line"; first=0; continue
    fi
    if (( first )); then out="$line"; first=0; else out+=$'\n'"$line"; fi
  done <<< "$body"
  if (( ! done_ins )); then
    if (( has_hist )); then
      out="$out"$'\n\n'"$block"
    else
      out="$out"$'\n\n'"## 변경 이력"$'\n\n'"$block"
    fi
  fi
  [[ "$text" == *$'\n' ]] && out="$out"$'\n'
  printf '%s' "$out"
}

# @pure
# 역할: PLAN.md 글의 Suggested path(옛 계획은 Steps) 단계를 "번호<탭>표시<탭>글" 줄로 꺼낸다 — 표시는 done · doing · blocked · 빈 값
# 종류: 꺼내기
# 예: $'## Suggested path\n\n1. [x] 준비 — a\n2. 만들기 — `b`\n\n## Links' → $'1\tdone\t준비 — a\n2\t\t만들기 — `b`'
# 예: $'## Steps\n1. 🔄 하기' → $'1\tdoing\t하기'
# 예: "# a" → ""
scv_plan_steps() {
  local text="${1:-}" line in_sec=0 out="" num rest mark
  local re='^([0-9]+)\. (.*)$'
  while IFS= read -r line; do
    if [[ "$line" == "## "* ]]; then
      in_sec=0
      [[ "$line" == "## Suggested path"* || "$line" == "## Steps"* ]] && in_sec=1
      continue
    fi
    (( in_sec )) || continue
    [[ "$line" =~ $re ]] || continue
    num="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"; mark=""
    case "$rest" in
      "[x] "*|"[X] "*) mark=done; rest="${rest:4}" ;;
      "✅ "*) mark=done; rest="${rest#✅ }" ;;
      "[~] "*) mark=doing; rest="${rest:4}" ;;
      "🔄 "*) mark=doing; rest="${rest#🔄 }" ;;
      "[!] "*) mark=blocked; rest="${rest:4}" ;;
      "⛔ "*) mark=blocked; rest="${rest#⛔ }" ;;
    esac
    [[ -n "$out" ]] && out="$out"$'\n'
    out="$out$num"$'\t'"$mark"$'\t'"$rest"
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: Suggested path 의 after 번 단계 뒤에 새 단계를 끼우고 뒤 단계 번호를 하나씩 민다 — after 가 마지막 번호 이상이면 맨 끝, 0 이면 맨 앞
# 종류: 변환
# 예: $'## Suggested path\n\n1. [x] a\n2. b\n\n## Links' 1 "c" → $'## Suggested path\n\n1. [x] a\n2. c\n3. b\n\n## Links'
# 예: $'## Suggested path\n1. a' 5 "c" → $'## Suggested path\n1. a\n2. c'
# 예: $'## Suggested path\n1. a' 0 "c" → $'## Suggested path\n1. c\n2. a'
# 단계 글은 바꾸지 않는다 — 번호만 민다. 끝난 단계([x])도 글은 그대로다.
scv_plan_insert_step() {
  local text="${1:-}" after="${2:-0}" step="${3:-}" line out="" first=1 in_sec=0 last=0 num rest body
  local re='^([0-9]+)\. (.*)$'
  local row
  while IFS= read -r row; do [[ -n "$row" ]] && last="${row%%$'\t'*}"; done <<< "$(scv_plan_steps "$text")"
  (( after > last )) && after="$last"
  body="$text"; [[ "${text: -1}" == $'\n' ]] && body="${text%?}"
  while IFS= read -r line; do
    if [[ "$line" == "## "* ]]; then
      in_sec=0
      [[ "$line" == "## Suggested path"* || "$line" == "## Steps"* ]] && in_sec=1
    elif (( in_sec )) && [[ "$line" =~ $re ]]; then
      num="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
      if (( after == 0 && num == 1 )); then
        line="1. $step"$'\n'"2. $rest"
      elif (( num > after )); then
        line="$((num + 1)). $rest"
      elif (( num == after )); then
        line="$line"$'\n'"$((after + 1)). $step"
      fi
    fi
    if (( first )); then out="$line"; first=0; else out+=$'\n'"$line"; fi
  done <<< "$body"
  [[ "$text" == *$'\n' ]] && out="$out"$'\n'
  printf '%s' "$out"
}

# @pure
# 역할: 단계를 after 번 뒤에 끼운 뒤, 변경 이력의 진행 줄("- **날짜 진행** — M단계 …")에서 M 이 after 보다 크면 M+1 로 민다 — 옛 진행 기록이 새 단계에 붙지 않게(0.87.4). 진행 줄이 아닌 줄은 그대로
# 종류: 변환
# 예: $'- **d 진행** — 3a단계 막힘: k\n- **d 진행** — 2단계 끝: j' 2 → $'- **d 진행** — 4a단계 막힘: k\n- **d 진행** — 2단계 끝: j'
# 예: $'- **d 추가** — 1단계 뒤에 새 단계' 0 → $'- **d 추가** — 1단계 뒤에 새 단계'
# 예: $'# a\n본문 3단계' 1 → $'# a\n본문 3단계'
scv_plan_shift_progress() {
  local text="${1:-}" after="${2:-0}" line out="" first=1 head num tail body
  local re='^(- \*\*[^*]* 진행\*\* — )([0-9]+)([a-z]?단계 .*)$'
  body="$text"; [[ "${text: -1}" == $'\n' ]] && body="${text%?}"
  while IFS= read -r line; do
    if [[ "$line" =~ $re ]]; then
      head="${BASH_REMATCH[1]}"; num="${BASH_REMATCH[2]}"; tail="${BASH_REMATCH[3]}"
      (( num > after )) && line="$head$((num + 1))$tail"
    fi
    if (( first )); then out="$line"; first=0; else out+=$'\n'"$line"; fi
  done <<< "$body"
  [[ "$text" == *$'\n' ]] && out="$out"$'\n'
  printf '%s' "$out"
}

# @pure
# 역할: 끝난 단계 n 의 요건이 바뀌었을 때 맨 끝에 붙일 "다시 하기" 단계 글을 만든다 — 원래 단계의 " — " 뒤 꼬리는 그대로 둔다
# 종류: 조립
# 예: $'## Suggested path\n1. [x] 검사 추가 — `checkA`\n2. b' 1 → $'다시 하기: 검사 추가 — `checkA`'
# 예: $'## Suggested path\n1. [x] 준비' 1 → "다시 하기: 준비 — 1단계를 바뀐 요건으로 다시 함"
# 예: $'## Suggested path\n1. a' 3 → ""
scv_plan_redo_step() {
  local text="${1:-}" n="${2:-}" row rest name tail
  local found="" r2
  while IFS= read -r r2; do [[ "${r2%%$'\t'*}" == "$n" ]] && { found="$r2"; break; }; done <<< "$(scv_plan_steps "$text")"
  row="$found"
  [[ -n "$row" ]] || return 0
  rest="${row#*$'\t'}"; rest="${rest#*$'\t'}"
  if [[ "$rest" == *" — "* ]]; then
    name="${rest%% — *}"; tail="${rest#* — }"
  else
    name="$rest"; tail="${n}단계를 바뀐 요건으로 다시 함"
  fi
  printf '다시 하기: %s — %s' "$name" "$tail"
}

# @pure
# 역할: 계획 A 를 보류로 바꾼다 — status: paused · paused_by · resume_at 칸과 변경 이력 "보류" 사건 하나(먼저 할 계획 제목 · 다시 시작 단계 · 이유)
# 종류: 변환
# 예: $'---\nstatus: in_progress\n---\n# a' "b" "로그 정리" 2 "2026-11-09" "다른 목표" → $'---\nstatus: paused\npaused_by: b\nresume_at: 2\n---\n# a\n\n## 변경 이력\n\n- **2026-11-09 보류** — 먼저 할 계획: 로그 정리\n  - 다시 시작: 2단계부터\n  - 이유: 다른 목표'
# 예: "# a" "b" "b" 1 "2026-11-09" "x" → $'# a\n\n## 변경 이력\n\n- **2026-11-09 보류** — 먼저 할 계획: b\n  - 다시 시작: 1단계부터\n  - 이유: x'
scv_plan_mark_pause() {
  local text="${1:-}" by="${2:-}" title="${3:-}" at="${4:-}" day="${5:-}" why="${6:-}"
  text="$(scv_plan_fm_set "$text" status paused; printf x)"; text="${text%x}"
  text="$(scv_plan_fm_set "$text" paused_by "$by"; printf x)"; text="${text%x}"
  text="$(scv_plan_fm_set "$text" resume_at "$at"; printf x)"; text="${text%x}"
  scv_plan_history_add "$text" "**$day 보류** — 먼저 할 계획: $title"$'\n'"다시 시작: ${at}단계부터"$'\n'"이유: $why"
}

# @pure
# 역할: 새 계획 B 에 끝나면 돌아갈 계획 A 를 적는다 — return_to 칸과 변경 이력 "연결" 사건 하나(돌아갈 계획 제목 · 이유)
# 종류: 변환
# 예: $'---\nstatus: planned\n---\n# b' "a" "결제 화면" "2026-11-09" "다른 목표" → $'---\nstatus: planned\nreturn_to: a\n---\n# b\n\n## 변경 이력\n\n- **2026-11-09 연결** — 끝나면 돌아갈 계획: 결제 화면\n  - 이유: 다른 목표'
# 예: "# b" "a" "a" "2026-11-09" "x" → $'# b\n\n## 변경 이력\n\n- **2026-11-09 연결** — 끝나면 돌아갈 계획: a\n  - 이유: x'
scv_plan_link_return() {
  local text="${1:-}" to="${2:-}" title="${3:-}" day="${4:-}" why="${5:-}"
  text="$(scv_plan_fm_set "$text" return_to "$to"; printf x)"; text="${text%x}"
  scv_plan_history_add "$text" "**$day 연결** — 끝나면 돌아갈 계획: $title"$'\n'"이유: $why"
}

# @pure
# 역할: 보류였던 계획 A 를 진행 중으로 되돌린다 — paused_by · resume_at 칸을 지우고 변경 이력 "재개" 사건 하나(끝난 계획 제목 · 다시 시작 단계)
# 종류: 변환
# 예: $'---\nstatus: paused\npaused_by: b\nresume_at: 2\n---\n# a' "로그 정리" "2026-11-10" → $'---\nstatus: in_progress\n---\n# a\n\n## 변경 이력\n\n- **2026-11-10 재개** — 끝난 계획: 로그 정리\n  - 다시 시작: 2단계부터'
# 예: $'---\nstatus: paused\n---\n# a' "b" "2026-11-10" → $'---\nstatus: in_progress\n---\n# a\n\n## 변경 이력\n\n- **2026-11-10 재개** — 끝난 계획: b\n  - 다시 시작: 1단계부터'
scv_plan_mark_resume() {
  local text="${1:-}" title="${2:-}" day="${3:-}" at
  at="$(scv_plan_fm_get "$text" resume_at)"; [[ -n "$at" ]] || at=1
  text="$(scv_plan_fm_set "$text" status in_progress; printf x)"; text="${text%x}"
  text="$(scv_plan_fm_drop "$text" paused_by; printf x)"; text="${text%x}"
  text="$(scv_plan_fm_drop "$text" resume_at; printf x)"; text="${text%x}"
  scv_plan_history_add "$text" "**$day 재개** — 끝난 계획: $title"$'\n'"다시 시작: ${at}단계부터"
}

# @pure
# 역할: `## Goals / Non-Goals` 절에서 Goals 또는 Non-Goals 아래 항목들을 한 줄씩 꺼낸다
# 종류: 꺼내기
# 예: $'## Goals / Non-Goals\n\n- **Goals**\n  - 가\n- **Non-Goals**\n  - 나\n  - 다\n\n## X' "Non-Goals" → $'나\n다'
# 예: $'## Goals / Non-Goals\n- **Goals**\n  - 가' "Goals" → "가"
# 예: "# a" "Goals" → ""
scv_plan_goal_items() {
  local text="${1:-}" which="${2:-Goals}" line in_sec=0 in_list=0 out="" item
  while IFS= read -r line; do
    if [[ "$line" == "## "* ]]; then
      in_sec=0; in_list=0
      [[ "$line" == "## Goals"* ]] && in_sec=1
      continue
    fi
    (( in_sec )) || continue
    case "$line" in
      "- **$which**"*) in_list=1; continue ;;
      "- **"*) in_list=0; continue ;;
    esac
    (( in_list )) || continue
    [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*)$ ]] || continue
    item="${BASH_REMATCH[1]}"
    [[ -n "$out" ]] && out="$out"$'\n'
    out="$out$item"
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: 요건 글 하나를 맞대기 좋게 다듬는다 — 끝의 부정 말(안 함 · 하지 않음 · 않는다 · 금지)과 문장 부호 · 앞뒤 공백을 떼고, 단계 꼬리(" — " 뒤)를 뗀다
# 종류: 다듬기
# 예: "결제 한도 변경 안 함" → "결제 한도 변경"
# 예: "끝난 단계를 다시 쓰거나 지우는 일 — 아무거나" → "끝난 단계를 다시 쓰거나 지우는 일"
# 예: "  화면 만들기.  " → "화면 만들기"
scv_plan_norm_req() {
  local s="${1:-}" prev=""
  s="${s%% — *}"
  while [[ "$s" != "$prev" ]]; do
    prev="$s"
    s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
    s="${s%.}"; s="${s%。}"
    s="${s% 안 함}"; s="${s% 안 한다}"; s="${s% 하지 않음}"; s="${s% 하지 않는다}"; s="${s% 않음}"; s="${s% 않는다}"; s="${s% 금지}"
  done
  printf '%s' "$s"
}

# @pure
# 역할: 앞쪽 충돌 검사 — B 의 Goals 항목이 A 의 Non-Goals(충돌) 또는 A 의 남은 단계(겹침)와 글자로 겹치는 것을 한 줄씩 낸다
# 종류: 판정
# 예: $'## Goals / Non-Goals\n- **Non-Goals**\n  - 결제 한도 변경 안 함' $'## Goals / Non-Goals\n- **Goals**\n  - 결제 한도 변경' → "충돌 · A 가 하지 않기로 함: 결제 한도 변경 안 함 ↔ B 목표: 결제 한도 변경"
# 예: $'## Suggested path\n1. [x] 준비\n2. 화면 만들기 — `x`' $'## Goals / Non-Goals\n- **Goals**\n  - 화면 만들기' → $'겹침 · A 2단계: 화면 만들기 — `x` ↔ B 목표: 화면 만들기'
# 예: $'## Goals / Non-Goals\n- **Non-Goals**\n  - 가' $'## Goals / Non-Goals\n- **Goals**\n  - 나' → ""
# 글자 겹침(한쪽이 다른 쪽을 품음)만 본다 — 뜻의 충돌은 모델이 판단한다. 다듬은 글이 2자 미만이면 보지 않는다.
scv_plan_conflict_before() {
  local a="${1:-}" b="${2:-}" goal ng g n row num mark rest r i first=1
  local goals nongoals steps
  local -a ng_raw=() ng_norm=() st_num=() st_rest=() st_norm=()
  goals="$(scv_plan_goal_items "$b" Goals)"
  nongoals="$(scv_plan_goal_items "$a" Non-Goals)"
  steps="$(scv_plan_steps "$a")"
  # A 쪽 글은 목표마다 다시 다듬지 않는다 — 한 번만 다듬어 배열에 둔다.
  while IFS= read -r ng; do
    n="$(scv_plan_norm_req "$ng")"
    (( ${#n} >= 2 )) || continue
    ng_raw[${#ng_raw[@]}]="$ng"; ng_norm[${#ng_norm[@]}]="$n"
  done <<< "$nongoals"
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    num="${row%%$'\t'*}"; r="${row#*$'\t'}"; mark="${r%%$'\t'*}"; rest="${r#*$'\t'}"
    [[ "$mark" == done ]] && continue
    n="$(scv_plan_norm_req "$rest")"
    (( ${#n} >= 2 )) || continue
    st_num[${#st_num[@]}]="$num"; st_rest[${#st_rest[@]}]="$rest"; st_norm[${#st_norm[@]}]="$n"
  done <<< "$steps"
  (( ${#ng_norm[@]} + ${#st_norm[@]} )) || return 0
  # 답 줄은 큰 글 하나에 붙이지 않고 나오는 대로 낸다.
  while IFS= read -r goal; do
    g="$(scv_plan_norm_req "$goal")"
    (( ${#g} >= 2 )) || continue
    for (( i = 0; i != ${#ng_norm[@]}; i++ )); do
      n="${ng_norm[i]}"
      if [[ "$g" == *"$n"* || "$n" == *"$g"* ]]; then
        if (( first )); then first=0; else printf '\n'; fi
        printf '%s' "충돌 · A 가 하지 않기로 함: ${ng_raw[i]} ↔ B 목표: $goal"
      fi
    done
    for (( i = 0; i != ${#st_norm[@]}; i++ )); do
      n="${st_norm[i]}"
      if [[ "$g" == *"$n"* || "$n" == *"$g"* ]]; then
        if (( first )); then first=0; else printf '\n'; fi
        printf '%s' "겹침 · A ${st_num[i]}단계: ${st_rest[i]} ↔ B 목표: $goal"
      fi
    done
  done <<< "$goals"
}

# @pure
# 역할: 뒤쪽 충돌 검사 — B 가 바꾼 파일 경로가 A 의 끝나지 않은 단계 글에 나오면 "겹침 · A n단계 · 파일" 줄을 낸다
# 종류: 판정
# 예: $'## Suggested path\n1. [x] core/a.sh 고침\n2. core/a.sh 와 core/b.sh 손봄' $'core/a.sh\ncore/c.sh' → "겹침 · A 2단계 · core/a.sh"
# 예: $'## Suggested path\n1. 문서 고침' "core/a.sh" → ""
# 예: $'## Suggested path\n1. a' "" → ""
scv_plan_conflict_after() {
  local a="${1:-}" files="${2:-}" row num r mark rest f first=1
  local -a fl=()
  # 파일 목록은 단계마다 다시 줄로 나누지 않는다 — 한 번만 나눠 배열에 둔다.
  while IFS= read -r f; do
    [[ -n "$f" ]] && fl[${#fl[@]}]="$f"
  done <<< "$files"
  (( ${#fl[@]} )) || return 0
  # 답 줄은 큰 글 하나에 붙이지 않고 나오는 대로 낸다.
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    num="${row%%$'\t'*}"; r="${row#*$'\t'}"; mark="${r%%$'\t'*}"; rest="${r#*$'\t'}"
    [[ "$mark" == done ]] && continue
    for f in "${fl[@]}"; do
      if [[ "$rest" == *"$f"* ]]; then
        if (( first )); then first=0; else printf '\n'; fi
        printf '%s' "겹침 · A ${num}단계 · $f"
      fi
    done
  done <<< "$(scv_plan_steps "$a")"
}

# ── 두 일을 가르고 합친다 (계획 20261127-wookiya1364-dashboard-motion-cards-two-jobs) ──
# 진행 중인 계획 A 가 있는데 목표가 다른 일 B 가 오고 두 일이 같은 파일을 고치지 않으면, A 를 멈추지 않고 가른다:
# A 는 따로 만든 폴더에서 이어 가고 B 는 원래 폴더에서 한다. 둘 다 끝나면 합치고, 가를 때 적어 둔 확인 결과와
# 합친 뒤의 결과를 비교한다. 깃 · 확인 명령 · 파일 쓰기는 scripts/plan-link.sh.

# @pure
# 역할: 두 일을 갈라도 되는지 본다 — 새 일이 고칠 파일이 하던 계획의 남은 단계 글에 나오거나 하던 일이 고칠 파일과 같으면 "겹침 · …" 줄을, 새 일의 파일 목록이 비어 있으면 "알 수 없음 · …" 줄을 낸다(줄이 없으면 가를 수 있다)
# 종류: 판정
# 예: $'## Suggested path\n1. [x] a.sh 준비\n2. b.sh 손봄' "" "b.sh" → "겹침 · A 2단계 · b.sh"
# 예: $'## Suggested path\n1. 문서' "x.sh" $'x.sh\ny.sh' → "겹침 · 두 일이 함께 고침 · x.sh"
# 예: $'## Suggested path\n1. 문서' "" "" → "알 수 없음 · 새 일이 고칠 파일 목록이 비어 있다"
# 예: $'## Suggested path\n1. 문서' "a.sh" "b.sh" → ""
scv_plan_split_check() {
  local a="${1:-}" own="${2:-}" theirs="${3:-}" f g hits first=1 n=0
  while IFS= read -r f; do [[ -n "$f" ]] && n=$((n + 1)); done <<< "$theirs"
  if (( n == 0 )); then printf '%s' "알 수 없음 · 새 일이 고칠 파일 목록이 비어 있다"; return 0; fi
  hits="$(scv_plan_conflict_after "$a" "$theirs")"
  if [[ -n "$hits" ]]; then printf '%s' "$hits"; first=0; fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    while IFS= read -r g; do
      [[ -n "$g" && "$f" == "$g" ]] || continue
      if (( first )); then first=0; else printf '\n'; fi
      printf '%s' "겹침 · 두 일이 함께 고침 · $f"
    done <<< "$own"
  done <<< "$theirs"
}

# @pure
# 역할: 계획 글에 가름을 적는다 — split_with · split_on 칸과 변경 이력 "가름" 사건 하나. 따로 만든 폴더로 가는 계획(자리를 넘겨받음)에는 split_at · split_dir · split_branch · split_base 칸도 적는다
# 종류: 변환
# 예: $'---\nstatus: in_progress\n---\n# a' "b" "피해" 2 "2026-11-09 10:30" "다른 목표" "/w/r.split-a" "scv-split/a" "abc" → $'---\nstatus: in_progress\nsplit_with: b\nsplit_on: 2026-11-09 10:30\nsplit_at: 2\nsplit_dir: /w/r.split-a\nsplit_branch: scv-split/a\nsplit_base: abc\n---\n# a\n\n## 변경 이력\n\n- **2026-11-09 가름** — 함께 하는 일: 피해\n  - 가른 단계: 2단계\n  - 갈라진 때: 10:30\n  - 이 일의 자리: 따로 만든 폴더 /w/r.split-a\n  - 이유: 다른 목표'
# 예: $'---\nstatus: planned\n---\n# b' "a" "체력" 2 "2026-11-09 10:30" "다른 목표" → $'---\nstatus: planned\nsplit_with: a\nsplit_on: 2026-11-09 10:30\n---\n# b\n\n## 변경 이력\n\n- **2026-11-09 가름** — 함께 하는 일: 체력\n  - 갈라진 때: 10:30\n  - 이 일의 자리: 원래 폴더\n  - 이유: 다른 목표'
scv_plan_mark_split() {
  local text="${1:-}" with="${2:-}" title="${3:-}" at="${4:-}" on="${5:-}" why="${6:-}" dir="${7:-}" branch="${8:-}" base="${9:-}" entry
  text="$(scv_plan_fm_set "$text" split_with "$with"; printf x)"; text="${text%x}"
  text="$(scv_plan_fm_set "$text" split_on "$on"; printf x)"; text="${text%x}"
  entry="**${on%% *} 가름** — 함께 하는 일: $title"
  if [[ -n "$dir" ]]; then
    text="$(scv_plan_fm_set "$text" split_at "$at"; printf x)"; text="${text%x}"
    text="$(scv_plan_fm_set "$text" split_dir "$dir"; printf x)"; text="${text%x}"
    text="$(scv_plan_fm_set "$text" split_branch "$branch"; printf x)"; text="${text%x}"
    text="$(scv_plan_fm_set "$text" split_base "$base"; printf x)"; text="${text%x}"
    entry="$entry"$'\n'"가른 단계: ${at}단계"$'\n'"갈라진 때: ${on#* }"$'\n'"이 일의 자리: 따로 만든 폴더 $dir"
  else
    entry="$entry"$'\n'"갈라진 때: ${on#* }"$'\n'"이 일의 자리: 원래 폴더"
  fi
  scv_plan_history_add "$text" "$entry"$'\n'"이유: $why"
}

# @pure
# 역할: 확인 명령의 출력에서 값 줄("이름: 숫자로 시작하는 값")을 "이름<탭>값" 줄로 꺼낸다 — '#' 로 시작하는 줄과 이름이 60자를 넘는 줄은 건너뛰고, 같은 이름이 여러 번이면 마지막 값만 남긴다
# 종류: 꺼내기
# 예: $'보스: 10\n시험 통과' → $'보스\t10'
# 예: $'# 확인 명령 끝 코드 0 · 2026-11-09 10:30\n체력: 1,000\n체력: 900 남음' → $'체력\t900 남음'
# 예: $'12:30 시작\n상태: 통과' → ""
scv_plan_result_values() {
  local text="${1:-}" line name value i found out=""
  local -a names=() values=()
  local re='^[[:space:]]*([^:#[:space:]][^:]*):[[:space:]]+([-+]?[0-9].*)$'
  while IFS= read -r line; do
    [[ "$line" =~ $re ]] || continue
    name="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    name="${name%"${name##*[![:space:]]}"}"; value="${value%"${value##*[![:space:]]}"}"
    (( ${#name} <= 60 )) || continue
    found=0
    for (( i = 0; i != ${#names[@]}; i++ )); do
      if [[ "${names[i]}" == "$name" ]]; then values[i]="$value"; found=1; break; fi
    done
    (( found )) || { names[${#names[@]}]="$name"; values[${#values[@]}]="$value"; }
  done <<< "$text"
  for (( i = 0; i != ${#names[@]}; i++ )); do
    [[ -n "$out" ]] && out="$out"$'\n'
    out="$out${names[i]}"$'\t'"${values[i]}"
  done
  printf '%s' "$out"
}

# @pure
# 역할: 적어 둔 확인 결과 글의 첫 줄("# 확인 명령 끝 코드 N · …")에서 끝 코드를 꺼낸다 — 그 줄이 없으면 빈 값
# 종류: 꺼내기
# 예: $'# 확인 명령 끝 코드 0 · 2026-11-09 10:30\n보스: 10' → "0"
# 예: $'# 확인 명령 끝 코드 12 · x' → "12"
# 예: "보스: 10" → ""
scv_plan_result_code() {
  local first="${1%%$'\n'*}"
  local re='^# 확인 명령 끝 코드 ([0-9]+)( |$)'
  [[ "$first" =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
  return 0
}

# @pure
# 역할: 가를 때와 합친 뒤의 확인 결과를 비교한다 — 값 줄의 값이 달라진 것을 "이름 옛값 → 새값" 줄로 내고(한쪽에만 있는 이름은 없는 쪽을 "(없음)"으로), 통과와 실패가 바뀌었으면 "확인 명령 통과 → 실패" 줄을 낸다
# 종류: 판정
# 예: "보스: 10" "보스: 5" → "보스 10 → 5"
# 예: $'보스: 10\n체력: 1000' $'체력: 1000\n보스: 10' → ""
# 예: "보스: 10" "ok" → "보스 10 → (없음)"
# 예: $'# 확인 명령 끝 코드 0 · t\nok' $'# 확인 명령 끝 코드 1 · t\nok' → "확인 명령 통과 → 실패"
scv_plan_results_diff() {
  local old="${1:-}" new="${2:-}" ov nv row r2 name value other first=1 oc nc
  ov="$(scv_plan_result_values "$old")"; nv="$(scv_plan_result_values "$new")"
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    name="${row%%$'\t'*}"; value="${row#*$'\t'}"; other="(없음)"
    while IFS= read -r r2; do
      [[ "${r2%%$'\t'*}" == "$name" ]] && { other="${r2#*$'\t'}"; break; }
    done <<< "$nv"
    [[ "$other" == "$value" ]] && continue
    if (( first )); then first=0; else printf '\n'; fi
    printf '%s' "$name $value → $other"
  done <<< "$ov"
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    name="${row%%$'\t'*}"; value="${row#*$'\t'}"; other=""
    while IFS= read -r r2; do
      [[ "${r2%%$'\t'*}" == "$name" ]] && { other=1; break; }
    done <<< "$ov"
    [[ -n "$other" ]] && continue
    if (( first )); then first=0; else printf '\n'; fi
    printf '%s' "$name (없음) → $value"
  done <<< "$nv"
  oc="$(scv_plan_result_code "$old")"; nc="$(scv_plan_result_code "$new")"
  if [[ -n "$oc" && -n "$nc" ]] && { [[ "$oc" == 0 && "$nc" != 0 ]] || [[ "$oc" != 0 && "$nc" == 0 ]]; }; then
    if (( first )); then first=0; else printf '\n'; fi
    if [[ "$oc" == 0 ]]; then printf '%s' "확인 명령 통과 → 실패"; else printf '%s' "확인 명령 실패 → 통과"; fi
  fi
}

# @pure
# 역할: 계획 글에 합침을 적는다 — split_* 칸을 지우고 joined_with · joined_on 칸(달라진 결과가 있으면 joined_changed, 가른 단계가 있던 계획에는 joined_at 칸도)과 변경 이력 "합침" 사건 하나(함께 한 일 제목 · 같은 줄 충돌 없음 · 달라진 결과)를 둔다
# 종류: 변환
# 예: $'---\nstatus: in_progress\nsplit_with: b\nsplit_on: 2026-11-09 10:30\nsplit_at: 2\nsplit_dir: /w\nsplit_branch: s\nsplit_base: abc\n---\n# a' "b" "피해" "2026-11-09 11:00" "보스 10 → 5" → $'---\nstatus: in_progress\njoined_with: b\njoined_on: 2026-11-09 11:00\njoined_changed: 보스 10 → 5\njoined_at: 2\n---\n# a\n\n## 변경 이력\n\n- **2026-11-09 합침** — 함께 한 일: 피해\n  - 합친 때: 11:00\n  - 같은 줄 충돌 없음\n  - 달라진 결과 1개: 보스 10 → 5'
# 예: $'---\nstatus: planned\nsplit_with: a\nsplit_on: 2026-11-09 10:30\n---\n# b' "a" "체력" "2026-11-09 11:00" "" → $'---\nstatus: planned\njoined_with: a\njoined_on: 2026-11-09 11:00\n---\n# b\n\n## 변경 이력\n\n- **2026-11-09 합침** — 함께 한 일: 체력\n  - 합친 때: 11:00\n  - 같은 줄 충돌 없음\n  - 달라진 결과 없음'
scv_plan_mark_join() {
  local text="${1:-}" with="${2:-}" title="${3:-}" on="${4:-}" changed="${5:-}" note="${6:-}" at key line n=0 flat="" entry
  at="$(scv_plan_fm_get "$text" split_at)"
  for key in split_with split_on split_at split_dir split_branch split_base; do
    text="$(scv_plan_fm_drop "$text" "$key"; printf x)"; text="${text%x}"
  done
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n=$((n + 1)); flat="$flat${flat:+ · }$line"
  done <<< "$changed"
  text="$(scv_plan_fm_set "$text" joined_with "$with"; printf x)"; text="${text%x}"
  text="$(scv_plan_fm_set "$text" joined_on "$on"; printf x)"; text="${text%x}"
  if (( n )); then text="$(scv_plan_fm_set "$text" joined_changed "$flat"; printf x)"; text="${text%x}"; fi
  if [[ -n "$at" ]]; then text="$(scv_plan_fm_set "$text" joined_at "$at"; printf x)"; text="${text%x}"; fi
  entry="**${on%% *} 합침** — 함께 한 일: $title"$'\n'"합친 때: ${on#* }"$'\n'"같은 줄 충돌 없음"
  [[ -n "$note" ]] && entry="$entry"$'\n'"$note"
  if (( n )); then entry="$entry"$'\n'"달라진 결과 ${n}개: $flat"; else entry="$entry"$'\n'"달라진 결과 없음"; fi
  scv_plan_history_add "$text" "$entry"
}
