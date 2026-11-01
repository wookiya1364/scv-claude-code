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
