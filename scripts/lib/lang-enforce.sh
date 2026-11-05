#!/usr/bin/env bash
# lib/lang-enforce.sh — 설정 언어(SCV_LANG) 강제의 순수부 (0.79.0+, 계획 lang-enforce-079).
# 효과(설정 · 원본 읽기, 위치 기록, 훅 출력)는 template/hooks/on-user-prompt.sh · on-lang-check.sh · on-stop.sh.
#
#   scv_lang_rule_line <언어>                    → 매 턴 맨 앞에 실을 언어 규칙 한 줄 | 빈 값(언어 없음 · english)
#   scv_lang_new_text <글 목록> <지난 id>          → "<마지막 id>\x1f<새 글>" — 지난 검사 뒤에 쓴 글만
#   scv_lang_fix_note <언어> <줄 수> <mid|final> [<걸린 줄>] → 교정 문구 한 줄(언어 이름 · 걸린 줄 포함, 0.82.0)
#   scv_lang_first_other <글> <언어>              → 설정 언어가 아닌 첫 줄(앞 60바이트) | 빈 값 (0.82.0)
#   scv_lang_stop_decide <최종 답 줄 수> <이미 전달 0|1> → block | ok
#   scv_lang_user_other <이번 턴 사용자 글>              → 1(사용자가 다른 언어를 요청하거나 다른 언어로 씀) | 0
#   scv_lang_drop_machine <글>                    → 기계 글 블록(알림 · 시스템 안내 · 명령 기록)을 뺀 글 (0.81.5)
#
# 판정 자체(다른 언어 줄 세기)는 lib/help-state.sh 의 scv_lint_lang_turn 이 한다 — 여기서 다시 만들지 않는다.
# 꺾쇠 글자는 쓰지 않는다 — 순수성 검사가 리다이렉션으로 본다.

# @pure
# 역할: 설정 언어로 쓴 언어 규칙 한 줄을 만든다 — 중간 보고까지 그 언어로 쓰라는 줄
# 종류: 조립
# 예: korean → "[SCV 언어] 사용자에게 보이는 글은 모두 한국어로 — 도구 사이 중간 보고 · 요약 포함(파일 · 코드 · 이름은 제 규칙대로). 다른 언어로 쓴 최종 답은 막힌다. 사용자가 이 턴에 다른 언어를 요청하면 그 언어."
# 예: english → ""
# 예: "" → ""
# <언어> → 한 줄 | 빈 값. 한국어는 한국어로, 다른 언어 이름은 영어 문장에 그 이름을 넣어 쓴다.
scv_lang_rule_line() {
  local lang="${1:-}"
  case "$lang" in
    ""|english|en) return 0 ;;
    korean|ko) printf '%s\n' "[SCV 언어] 사용자에게 보이는 글은 모두 한국어로 — 도구 사이 중간 보고 · 요약 포함(파일 · 코드 · 이름은 제 규칙대로). 다른 언어로 쓴 최종 답은 막힌다. 사용자가 이 턴에 다른 언어를 요청하면 그 언어." ;;
    *) printf '%s\n' "[SCV language] Write every message in $lang — including progress notes between tool calls. Code, paths and names stay as they are." ;;
  esac
}

# @pure
# 역할: 이번 턴 어시스턴트 글 목록에서 지난 검사 id 뒤에 쓴 글만 잇고, 마지막 id 와 함께 낸다
# 종류: 꺼내기
# 예: $'a\x1fold\nb\x1fnew' a → $'b\x1fnew'
# 예: $'a\x1fone\nb\x1ftwo' zz → $'b\x1fone\ntwo'
# 예: "" a → ""
# <글 목록: 줄마다 "id\x1f글(줄바꿈은 \x1e)"> <지난 id> → "<마지막 id>\x1f<새 글>" | 빈 값(목록이 비었음).
# 지난 id 가 목록에 없으면(새 턴이거나 처음) 목록 전체가 새 글이다.
scv_lang_new_text() {
  local list="${1:-}" last="${2:-}" us=$'\x1f' rs=$'\x1e' line id t found=0 out="" lastid="" k take
  local -a parts=()
  [[ -n "$list" ]] || return 0
  if [[ -n "$last" ]]; then
    while IFS= read -r line; do [[ "${line%%"$us"*}" == "$last" ]] && found=1; done <<<"$list"
  fi
  take=$(( 1 - found ))
  while IFS= read -r line; do
    [[ -n "$line" && "$line" == *"$us"* ]] || continue
    id="${line%%"$us"*}"; t="${line#*"$us"}"; lastid="$id"
    if (( ! take )); then [[ "$id" == "$last" ]] && take=1; continue; fi
    if [[ "$t" == *"$rs"* ]]; then
      parts=(); IFS="$rs" read -r -d '' -a parts <<<"$t" || true
      t=""; for (( k = 0; k < ${#parts[@]}; k++ )); do (( k )) && t+=$'\n'; t+="${parts[k]}"; done
      t="${t%$'\n'}"
    fi
    out="${out:+$out$'\n'}$t"
  done <<<"$list"
  [[ -n "$lastid" ]] || return 0
  printf '%s%s%s' "$lastid" "$us" "$out"
}

# @pure
# 역할: 다른 언어 줄 수와 자리(중간 · 최종), 걸린 줄 하나를 받아 언어 이름을 넣은 교정 문구를 만든다
# 종류: 조립
# 예: korean 3 mid → "[SCV 언어] 방금 쓴 글 중 3줄이 한국어가 아니다 — 다음 글부터 한국어로 써라(중간 보고 포함)."
# 예: korean 2 final → "[SCV 언어] 최종 답 중 2줄이 한국어가 아니다 — 그 줄만 한국어로 고쳐 다시 써라."
# 예: korean 1 mid "Next I'll run the tests." → "[SCV 언어] 방금 쓴 글 중 1줄이 한국어가 아니다(예: “Next I'll run the tests.”) — 다음 글부터 한국어로 써라(중간 보고 포함)."
# 예: korean 0 mid → ""
# <언어> <줄 수> <mid|final> [<걸린 줄>] → 한 줄 | 빈 값(줄 수 0 · 언어 없음).
# 걸린 줄을 싣는 까닭(0.82.0): 줄 수만 말하면 모델이 '이미 한국어로 썼다'고 믿고 헛경고로 넘긴다 — 2026-11-05 한 세션에서
# 중간 보고 영어 줄을 10번 넘게 잡았는데 한 번도 고쳐지지 않았다.
scv_lang_fix_note() {
  local lang="${1:-}" n="${2:-0}" where="${3:-mid}" ex="${4:-}" name eg=""
  [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 )) || return 0
  case "$lang" in korean|ko) name="한국어" ;; ""|english|en) return 0 ;; *) name="$lang" ;; esac
  [[ -n "$ex" ]] && eg="(예: “${ex}”)"
  if [[ "$where" == final ]]; then
    printf '%s\n' "[SCV 언어] 최종 답 중 ${n}줄이 ${name}가 아니다${eg} — 그 줄만 ${name}로 고쳐 다시 써라."
  else
    printf '%s\n' "[SCV 언어] 방금 쓴 글 중 ${n}줄이 ${name}가 아니다${eg} — 다음 글부터 ${name}로 써라(중간 보고 포함)."
  fi
}

# @pure
# 역할: 글에서 설정 언어가 아닌 첫 줄을 꺼내 앞 60바이트로 줄인다 — 교정 문구에 그대로 보여 주려고
# 종류: 꺼내기
# 예: $'결과를 봄\nNext I will run the tests now.' korean → "Next I will run the tests now."
# 예: $'```\nconst value = computeSomething();\n```\n모두 통과함' korean → ""
# 예: "모두 한국어로 씀" korean → ""
# <글> <언어> → 줄 | 빈 값. 판정은 scv_lint_lang_turn 에 줄마다 맡긴다(같은 판정을 다시 만들지 않는다). 코드 블록 안은 건너뛴다.
# 60바이트를 넘으면 자르고 '…'를 붙인다 — 끝에 걸친 한글 조각(바이트 일부)은 떼어 깨진 글자를 남기지 않는다.
scv_lang_first_other() {
  local text="${1:-}" lang="${2:-}" line t infence=0 cut
  [[ -n "$text" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    t="${line#"${line%%[![:space:]]*}"}"
    if [[ "$t" == '```'* ]]; then infence=$(( 1 - infence )); continue; fi
    (( infence )) && continue
    [[ -n "$(scv_lint_lang_turn "" "$t" "$lang")" ]] || continue
    cut="$(LC_ALL=C; t2="$t"; if (( ${#t2} > 60 )); then t2="${t2:0:60}"
      while [[ "$t2" == *[$'\x80'-$'\xff'] ]]; do t2="${t2%?}"; done; printf '%s…' "$t2"; else printf '%s' "$t2"; fi)"
    printf '%s' "$cut"
    return 0
  done <<< "$text"
}

# @pure
# 역할: 최종 답의 다른 언어 줄 수와 이번 턴 전달 여부로 끝내기를 막을지 정한다
# 종류: 판정/gate
# 예: 3 0 → "block"
# 예: 3 1 → "ok"
# 예: 0 0 → "ok"
# <최종 답 줄 수> <이번 턴에 이미 전달 0|1> → block | ok. 한 턴에 한 번만 막는다 — 다시 쓴 답도 어긋나면 다음 턴 경고로 넘긴다.
scv_lang_stop_decide() {
  local n="${1:-0}" delivered="${2:-0}"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if (( n > 0 )) && [[ "$delivered" != 1 ]]; then printf 'block'; else printf 'ok'; fi
}

# @pure
# 역할: 사람이 쓰지 않은 기계 글 블록(작업 완료 알림 · 시스템 안내 · 명령 기록 · 이벤트)을 지운다 — 언어 판정이 사람 글만 보게
# 종류: 다듬기
# 예: "<task-notification><summary>Background command completed</summary></task-notification>" → ""
# 예: "<system-reminder>## You are a session started from another session</system-reminder>잡몹 고치기" → "잡몹 고치기"
# 예: "영어로 답해 줘" → "영어로 답해 줘"
# <글> → 블록을 뺀 글. 닫는 꼬리표가 없으면(앞 4000바이트에서 잘림) 여는 꼬리표부터 끝까지 뺀다.
# 계기(0.81.5): 알림 · 세션 넘김 안내(영어)가 이번 턴 사용자 글로 잡혀 '사용자가 영어로 썼다'가 되고, 언어 검사가 꺼졌다.
scv_lang_drop_machine() {
  local p="${1:-}" lt=$'\x3c' gt=$'\x3e' t pre rest
  for t in task-notification system-reminder local-command-caveat local-command-stdout local-command-stderr \
           command-name command-message command-args side-sessions-event ci-monitor-event artifact-view-context; do
    while [[ "$p" == *"$lt$t"* ]]; do
      pre="${p%%"$lt$t"*}"; rest="${p#*"$lt$t"}"
      if [[ "$rest" == *"$lt/$t$gt"* ]]; then p="$pre${rest#*"$lt/$t$gt"}"; else p="$pre"; fi
    done
  done
  printf '%s' "$p"
}

# @pure
# 역할: 이번 턴 사용자 글이 다른 언어를 요청하거나 다른 언어로 쓰였는지 1 또는 0 으로 판정한다
# 종류: 판정/gate
# 예: "영어로 답해 줘" → "1"
# 예: "Please answer this one in English." → "1"
# 예: "로그인 버그 고쳐 줘" → "0"
# 예: "" → "0"
# <이번 턴 사용자 글> → 1 | 0. 1 이면 강제하지 않는다 — SCV 규칙은 사용자의 명시적 지시에 양보한다(SCV.md Top-level rules 7조).
# 다른 언어로 쓴 글: 글자 15개 이상에 한글이 20% 미만. 언어 요청: '영어로' · '일본어로' · 'in English' 같은 말. 앞 4000바이트만 본다.
scv_lang_user_other() {
  local p="${1:-}" h l
  p="$(scv_lang_drop_machine "${p:0:4000}")"
  case "$p" in
    *영어로*|*일본어로*|*중국어로*|*"in English"*|*"in english"*|*"英語で"*) printf '1'; return 0 ;;
  esac
  h="$(LC_ALL=C; printf '%s' "${p//[^$'\xea'-$'\xed']/}")"; l="$(LC_ALL=C; printf '%s' "${p//[^A-Za-z]/}")"
  if [[ $(( ${#h} + ${#l} )) -ge 15 && $(( ${#h} * 100 / (${#h} + ${#l}) )) -lt 20 ]]; then printf '1'; else printf '0'; fi
}
