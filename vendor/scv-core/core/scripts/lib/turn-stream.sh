#!/usr/bin/env bash
# lib/turn-stream.sh — 원본(transcript)에서 이번 사람 턴의 어시스턴트 글을 읽는 효과부 (0.79.0+ 에 on-stop.sh 에서 옮김).
# 부르는 쪽이 TRANSCRIPT 를 정한다. 종료 훅(on-stop.sh)과 도구 뒤 언어 검사 훅(on-lang-check.sh)이 함께 쓴다.
# 순수 함수가 아니다(파일을 읽는다) — @pure 표시를 붙이지 않는다.

# 원본 → 턴 스트림: 줄마다 "U"(사람이 쓴 프롬프트) 또는 "A\x1f<텍스트, 줄바꿈은 \x1e>". 자르기는 scv_turn_slice.
# v0.64.0+ — (1) 호스트의 내부 메시지(내부 표시 isMeta — 스킬 불러오기 · 종료 훅 피드백 등)는 사람 프롬프트가 아니다. 그것을
# U 로 세면 같은 턴에서 그보다 앞서 보인 답(다시 쓴 요청 인용 등)이 이번 턴에서 빠진다. (2) 자르기는 jq 한 번에 한다 — 마지막
# U 뒤만, 앞쪽 A 400개 + 마지막 A 하나로 낸다(긴 턴에서도 뒤의 bash 처리가 작다). U 가 없으면 아무것도 내지 않는다.
# (3) 도구가 만든 사용자 몫 글(도구 출처 표시 sourceToolUseID)도 사람 프롬프트가 아니다 — 내부 표시와 둘 중 하나만 있어도 뺀다
# (호스트가 한쪽 이름을 바꿔도 다른 쪽이 남는다; 로컬 원본 25개에서 사람 프롬프트에 출처 표시가 붙은 일은 0건). (4) 창 안에
# 사람 · 모델 줄이 하나도 없으면(이 형식이 아닌 원본 — 예: 코덱스 세션 기록) "N" 하나만 낸다: 넓혀 찾지 않고, 경계 기록도 남기지
# 않는다(자르기는 빈 값 — 이 기능 전과 같은 판정).
_scv_turn_stream() {  # [원본 끝에서 읽을 줄 수 — 기본 400]
  tail -n "${1:-400}" "$TRANSCRIPT" 2>/dev/null \
    | jq -Rrn '[inputs | fromjson? | if .type? == "user" then
                  (if (.isMeta? == true) or (.sourceToolUseID? != null) then empty
                   elif ((.message.content|type) == "string")
                      or ((.message.content|type) == "array" and any(.message.content[]?; .type? == "text"))
                   then "U" else empty end)
                elif .type? == "assistant" then
                  ("A\u001f" + ([.message.content[]? | select(.type? == "text") | .text] | join("\n") | gsub("\n"; "\u001e")))
                else empty end] as $s
               | ([range(0; $s | length) | select($s[.] == "U")] | last) as $i
               | if ($s | length) == 0 then "N" elif $i == null then empty
                 else ($s[($i + 1):]) as $t
                   | "U", ($t[:400][]), (if ($t | length) > 400 then $t[-1] else empty end)
                 end' 2>/dev/null || true
}
# v0.64.0+ — 창 안에 사람 프롬프트가 없으면(선택지 질문 · 도구 결과가 많은 긴 턴) 창을 넓혀 이번 사람 턴의 경계를 찾는다:
# 400 → 4000 → 40000 줄. 끝내 못 찾으면 아무것도 내지 않는다(자르기는 빈 값 — 지금처럼 안전 쪽). 기록은 부른 쪽이 한 번 남긴다.
# 창이 이 형식이 아니면("N") 그대로 돌려준다 — 넓혀도 찾을 것이 없다.
_scv_turn_stream_wide() {
  local n s="" total
  total="$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')"; [[ "$total" =~ ^[0-9]+$ ]] || total=0
  for n in 400 4000 40000; do
    s="$(_scv_turn_stream "$n")"
    [[ -n "$s" ]] && { printf '%s' "$s"; return 0; }
    (( total <= n )) && break
  done
  return 0
}

# 0.79.0+ — 도구 뒤 언어 검사용: 마지막 사람 프롬프트 뒤 어시스턴트 글 블록마다 "uuid\x1f글(줄바꿈은 \x1e)" 한 줄.
# 글이 없는 메시지(도구 호출만)는 빼고, 사람 프롬프트 경계는 _scv_turn_stream 과 같은 규칙으로 찾는다. 창 안에 사람 프롬프트가
# 없으면(긴 턴 — 0.81.2+) 창 전체가 이번 턴이므로 창 안 글을 모두 낸다(전에는 빈 값이라 긴 턴에서 검사가 꺼졌다).
_scv_turn_texts() {  # [원본 끝에서 읽을 줄 수 — 기본 400]
  tail -n "${1:-400}" "$TRANSCRIPT" 2>/dev/null \
    | jq -Rrn '[inputs | fromjson? | if .type? == "user" then
                  (if (.isMeta? == true) or (.sourceToolUseID? != null) then empty
                   elif ((.message.content|type) == "string")
                      or ((.message.content|type) == "array" and any(.message.content[]?; .type? == "text"))
                   then "U" else empty end)
                elif .type? == "assistant" then
                  ([.message.content[]? | select(.type? == "text") | .text] | join("\n")) as $x
                  | if ($x | length) == 0 then empty else ((.uuid // "?") + "\u001f" + ($x | gsub("\n"; "\u001e"))) end
                else empty end] as $s
               | ([range(0; $s | length) | select($s[.] == "U")] | last) as $i
               | if $i == null then $s[] else $s[($i + 1):][] end' 2>/dev/null || true
}

# 0.79.0+ — 이번 턴을 연 사람 글(마지막 사람 프롬프트의 글). 내부 메시지 · 도구 결과는 빼고, 못 찾으면 빈 값.
_scv_turn_prompt() {  # [원본 끝에서 읽을 줄 수 — 기본 400]
  tail -n "${1:-400}" "$TRANSCRIPT" 2>/dev/null | jq -Rr 'fromjson? | select(.type? == "user") | select((.isMeta? != true) and (.sourceToolUseID? == null))
      | (.message.content) as $c
      | if ($c|type) == "string" then $c elif ($c|type) == "array" then ([$c[]? | select(.type? == "text") | .text] | join("\n")) else empty end
      | select(length > 0) | @json' 2>/dev/null | tail -n 1 | jq -r '. // empty' 2>/dev/null | head -c 4000 || true
}
# 사용자 메시지 찾기(넓혀 가며, 0.81.2+): 끝 400줄에 없으면 4000 · 40000줄까지 넓힌다 — 긴 턴에서 메시지가 밀려나도 찾는다.
# @effect _scv_turn_prompt_wide
# 이유: 원본(transcript) 파일을 읽는다
_scv_turn_prompt_wide() {
  local n p total
  total="$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')"; [[ "$total" =~ ^[0-9]+$ ]] || total=0
  for n in 400 4000 40000; do
    p="$(_scv_turn_prompt "$n")"
    [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
    (( total <= n )) && break
  done
  return 0
}
