#!/usr/bin/env bash
# lib/text.sh — 여러 기능이 같이 쓰는 글자 다듬기. 어느 기능의 것도 아니다.
#
# 맥 기본 bash 는 3.2 라 ${v,,} 가 없다(bash 4 부터). 그 문법을 쓴 곳들이 맥에서 조용히 깨졌다 —
# 기록 색인 종류 맞추기 · 결정 이름 · 작성자 이름(2026-11-01 순수함수 사전 검사가 찾음).

# @pure
# 역할: ASCII 대문자만 소문자로 바꾼다 — 공백 · 한글 · 기호는 그대로(맥 기본 bash 3.2 에서도 됨)
# 종류: 다듬기
# 예: " AbC-1 " → " abc-1 "
# 예: "한글 OK" → "한글 ok"
# 예: "" → ""
# 글자 범위([A-Z])는 쓰지 않는다 — bash 3.2 는 UTF-8 지역 설정에서 [A-Z] 가 소문자까지 맞춘다.
# 대문자 26자를 그대로 적어 표로 바꾼다(model-prompting 의 id 정규화에서 옮겨 옴).
scv_lower() {
  local s="${1:-}" up="ABCDEFGHIJKLMNOPQRSTUVWXYZ" lo="abcdefghijklmnopqrstuvwxyz" out="" c i head
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$up" in
      *"$c"*) head="${up%%"$c"*}"; out+="${lo:${#head}:1}" ;;
      *) out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

# @pure
# 역할: 한 줄이 다시 쓴 요청 인용 줄(> **다시 쓴 요청**: · > **Rewritten request**: · > **書き直した依頼**:)인지 1|0 으로 정한다
# 종류: 판정/answer
# 예: "> **다시 쓴 요청**: 정리해 줘" → "1"
# 예: "  >Rewritten request: fix" → "1"
# 예: "다시 쓴 요청: 인용 아님" → "0"
# 예: "> 다른 인용" → "0"
# 앞 공백 · 인용 기호 뒤 공백 · 꾸밈 글자(* _)는 무시한다. 이름표 목록은 이곳 하나다 —
# 다시 쓴 요청이 맨 위에 있는지 보는 판정(model-prompting)과 답 모양 검사(help-state)가 같이 쓴다.
scv_is_rewrite_quote() {
  local t="${1:-}" q=$'\x3e'
  t="${t#"${t%%[![:space:]]*}"}"
  [[ "${t:0:1}" == "$q" ]] || { printf '0'; return 0; }
  t="${t:1}"; t="${t//\*/}"; t="${t//_/}"; t="${t#"${t%%[![:space:]]*}"}"
  case "$t" in
    "다시 쓴 요청"*|"Rewritten request"*|"rewritten request"*|"書き直した依頼"*) printf '1' ;;
    *) printf '0' ;;
  esac
}
