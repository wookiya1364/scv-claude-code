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
  local text="${1:-}" key="${2:-}" val="${3:-}" line out="" n=0 in_fm=0 has=0 placed=0
  [[ "$text" == ---* ]] || { printf '%s' "$text"; return 0; }
  [[ -n "$(scv_plan_fm_has "$text" "$key")" ]] && has=1
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
    out="$out"$'\n'"$line"
  done <<< "${text%$'\n'}"
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
  local text="${1:-}" key="${2:-}" line out="" n=0 in_fm=0
  [[ "$text" == ---* ]] || { printf '%s' "$text"; return 0; }
  while IFS= read -r line; do
    n=$((n + 1))
    if (( n == 1 )); then out="$line"; in_fm=1; continue; fi
    if (( in_fm )); then
      [[ "$line" == "---" ]] && in_fm=0
      (( in_fm )) && [[ "$line" == "$key:"* ]] && continue
    fi
    out="$out"$'\n'"$line"
  done <<< "${text%$'\n'}"
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
  local text="${1:-}" entry="${2:-}" line out="" first=1 in_hist=0 has_hist=0 has_links=0 pending="" done_ins=0 block="" el n=0
  while IFS= read -r el; do
    n=$((n + 1))
    if (( n == 1 )); then block="- $el"; else block="$block"$'\n'"  - $el"; fi
  done <<< "$entry"
  case "$text" in *$'\n'"## 변경 이력"*|"## 변경 이력"*) has_hist=1 ;; esac
  case "$text" in *$'\n'"## Links"*|"## Links"*) has_links=1 ;; esac
  while IFS= read -r line; do
    if (( has_hist )); then
      if (( in_hist )) && (( ! done_ins )) && [[ "$line" == "## "* ]]; then
        out="$out"$'\n\n'"$block$pending"; pending=""; done_ins=1; in_hist=0
      elif (( in_hist )) && [[ -z "$line" ]]; then
        pending="$pending"$'\n'; continue
      elif (( in_hist )) && [[ -n "$pending" ]]; then
        out="$out$pending"; pending=""
      fi
      [[ "$line" == "## 변경 이력" ]] && in_hist=1
    elif (( has_links )) && (( ! done_ins )) && [[ "$line" == "## Links" ]]; then
      if (( first )); then out=$'## 변경 이력\n\n'"$block"$'\n'; else out="$out"$'\n'"## 변경 이력"$'\n\n'"$block"$'\n'; fi
      done_ins=1
      out="$out"$'\n'"$line"; first=0; continue
    fi
    if (( first )); then out="$line"; first=0; else out="$out"$'\n'"$line"; fi
  done <<< "${text%$'\n'}"
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
  local text="${1:-}" after="${2:-0}" step="${3:-}" line out="" first=1 in_sec=0 last=0 num rest
  local re='^([0-9]+)\. (.*)$'
  local row
  while IFS= read -r row; do [[ -n "$row" ]] && last="${row%%$'\t'*}"; done <<< "$(scv_plan_steps "$text")"
  (( after > last )) && after="$last"
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
    if (( first )); then out="$line"; first=0; else out="$out"$'\n'"$line"; fi
  done <<< "${text%$'\n'}"
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
  local a="${1:-}" b="${2:-}" goal ng g n out="" row num mark rest r
  local goals nongoals steps
  goals="$(scv_plan_goal_items "$b" Goals)"
  nongoals="$(scv_plan_goal_items "$a" Non-Goals)"
  steps="$(scv_plan_steps "$a")"
  while IFS= read -r goal; do
    g="$(scv_plan_norm_req "$goal")"
    (( ${#g} >= 2 )) || continue
    while IFS= read -r ng; do
      n="$(scv_plan_norm_req "$ng")"
      (( ${#n} >= 2 )) || continue
      if [[ "$g" == *"$n"* || "$n" == *"$g"* ]]; then
        [[ -n "$out" ]] && out="$out"$'\n'
        out="${out}충돌 · A 가 하지 않기로 함: $ng ↔ B 목표: $goal"
      fi
    done <<< "$nongoals"
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      num="${row%%$'\t'*}"; r="${row#*$'\t'}"; mark="${r%%$'\t'*}"; rest="${r#*$'\t'}"
      [[ "$mark" == done ]] && continue
      n="$(scv_plan_norm_req "$rest")"
      (( ${#n} >= 2 )) || continue
      if [[ "$g" == *"$n"* || "$n" == *"$g"* ]]; then
        [[ -n "$out" ]] && out="$out"$'\n'
        out="${out}겹침 · A ${num}단계: $rest ↔ B 목표: $goal"
      fi
    done <<< "$steps"
  done <<< "$goals"
  printf '%s' "$out"
}

# @pure
# 역할: 뒤쪽 충돌 검사 — B 가 바꾼 파일 경로가 A 의 끝나지 않은 단계 글에 나오면 "겹침 · A n단계 · 파일" 줄을 낸다
# 종류: 판정
# 예: $'## Suggested path\n1. [x] core/a.sh 고침\n2. core/a.sh 와 core/b.sh 손봄' $'core/a.sh\ncore/c.sh' → "겹침 · A 2단계 · core/a.sh"
# 예: $'## Suggested path\n1. 문서 고침' "core/a.sh" → ""
# 예: $'## Suggested path\n1. a' "" → ""
scv_plan_conflict_after() {
  local a="${1:-}" files="${2:-}" row num r mark rest f out=""
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    num="${row%%$'\t'*}"; r="${row#*$'\t'}"; mark="${r%%$'\t'*}"; rest="${r#*$'\t'}"
    [[ "$mark" == done ]] && continue
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if [[ "$rest" == *"$f"* ]]; then
        [[ -n "$out" ]] && out="$out"$'\n'
        out="${out}겹침 · A ${num}단계 · $f"
      fi
    done <<< "$files"
  done <<< "$(scv_plan_steps "$a")"
  printf '%s' "$out"
}
