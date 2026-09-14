#!/usr/bin/env bash
# anchors.sh — run-dry 의 규약 문장 고정(앵커)을 추출·분류하는 순수부 (v0.48.0+).
#
# 왜 있나: run-dry 의 `assert_contains "$<규약>" "<문장>"` 은 규약 문장이 그대로 있는지 고정한다.
# 그 고정은 결정을 지키는 계약일 수도, 그저 표현을 못 박는 것일 수도 있다. 이 순수부가 둘을
# 기계로 가르고, 검사(test-anchor-intent.sh)가 "남는 고정엔 이유(# why:)가 있고, 코칭 문구
# (GUIDANCE 블록)만 고정하는 것은 없다"를 강제한다. 감사와 검사가 같은 함수를 쓴다.
#
# 종류(kind):
#   token     ≤24자 또는 공백 없는 식별자·플래그·경로 — 짧고 안정적, 이유 없이 허용
#   guidance  대상 규약의 GUIDANCE 블록 안에만 있는 문장 — 최소 프로필에서 잘려나가는 코칭 문구
#   sentence  6단어 이상의 문장 — 계약이면 남기되 # why: 필수
#   short     그 사이의 짧은 구 — # why: 필수
#   missing   대상 본문에 없는 문장 (run-dry 가 다른 파일 묶음을 볼 때 생김 — 검사가 아니라 정보)
#
# 순수: 함수는 문자열만 받아 문자열만 낸다. 파일 읽기는 부르는 쪽.

# @pure
# 셸 문자열 안의 이스케이프된 백틱을 되돌린다.
scv_anchor_unescape() {
  local t="${1:-}"
  t="${t//\\\`/\`}"
  printf '%s' "$t"
}

# @pure
# 본문에서 GUIDANCE 블록을 모두 걷어낸 문자열.
scv_anchor_strip_guidance() {
  # 꺾쇠는 리터럴로 적지 않는다(순수성 검사가 리다이렉션으로 본다) — 8진 이스케이프로 만든다.
  local body="${1:-}" pre post lt=$'\074' gt=$'\076' open close
  open="${lt}!-- SCV:GUIDANCE --${gt}"; close="${lt}!-- /SCV:GUIDANCE --${gt}"
  while [[ "$body" == *"$open"* ]]; do
    pre="${body%%"$open"*}"
    post="${body#*"$open"}"
    [[ "$post" == *"$close"* ]] || break
    post="${post#*"$close"}"
    body="$pre$post"
  done
  printf '%s' "$body"
}

# @pure
# 앵커 문장 + 대상 본문 + (GUIDANCE 를 걷어낸 본문) → kind 한 단어.
# 세 번째 인자는 부르는 쪽이 파일마다 한 번만 만들어 넘긴다 — 앵커마다 걷어내면 느리다.
scv_anchor_kind() {
  local text="${1:-}" body="${2:-}" stripped="${3-}" words=0 w
  if (( ${#text} <= 24 )) || [[ "$text" != *" "* ]]; then printf 'token'; return 0; fi
  if [[ "$body" != *"$text"* ]]; then printf 'missing'; return 0; fi
  [[ -n "$stripped" ]] || stripped="$(scv_anchor_strip_guidance "$body")"
  if [[ "$stripped" != *"$text"* ]]; then printf 'guidance'; return 0; fi
  for w in $text; do words=$((words + 1)); done
  if (( words >= 6 )); then printf 'sentence'; else printf 'short'; fi
}

# @pure
# run-dry 본문 → 한 줄에 하나: "<줄번호>\x1f<변수>\x1f<하위파일>\x1f<문장>\x1f<why:1|0>"
# 직전 비어 있지 않은 줄이 "# why:" 로 시작하면 why=1.
scv_anchor_extract() {
  local text="${1:-}" line n=0 prev="" us=$'\x1f' rest var sub q body
  while IFS= read -r line; do
    n=$((n + 1))
    if [[ "$line" =~ ^[[:space:]]*assert_contains[[:space:]]+\"\$([A-Z_]+)(/[a-z-]+\.md)?\"[[:space:]]+(.*)$ ]]; then
      var="${BASH_REMATCH[1]}"; sub="${BASH_REMATCH[2]#/}"; rest="${BASH_REMATCH[3]}"
      q="${rest:0:1}"
      if [[ "$q" == '"' || "$q" == "'" ]]; then
        rest="${rest:1}"
        body="${rest%%$q*}"
        [[ "$prev" == "# why:"* ]] && printf '%s%s%s%s%s%s%s%s1\n' "$n" "$us" "$var" "$us" "$sub" "$us" "$body" "$us" \
                                    || printf '%s%s%s%s%s%s%s%s0\n' "$n" "$us" "$var" "$us" "$sub" "$us" "$body" "$us"
      fi
    fi
    [[ -n "${line//[[:space:]]/}" ]] && prev="${line#"${line%%[![:space:]]*}"}"
  done <<<"$text"
}

# @pure
# 추출 결과 → 같은 (변수/하위파일, 문장) 이 두 번 이상인 줄들 "<변수>/<하위파일>\x1f<문장>".
scv_anchor_dups() {
  local rows="${1:-}" us=$'\x1f' n var sub body why key seen=$'\n' out=""
  while IFS="$us" read -r n var sub body why; do
    [[ -z "$var" ]] && continue
    key="$var/$sub$us$body"
    if [[ "$seen" == *$'\n'"$key"$'\n'* ]]; then
      [[ "$out" == *$'\n'"$key"$'\n'* ]] || out="$out$key"$'\n'
    else
      seen="$seen$key"$'\n'
    fi
  done <<<"$rows"
  printf '%s' "$out"
}

# @pure
# "<줄번호>\x1f<kind>\x1f<why>" 목록 + 상한 → 위반 줄들.
#   sentence/short 인데 why=0 → "no-why <줄번호>", guidance → "guidance <줄번호>",
#   (sentence+short) 총수 > 상한 → "over-budget <n> (max <상한>)".
scv_anchor_check() {
  local rows="${1:-}" max="${2:-120}" us=$'\x1f' n kind why total=0
  while IFS="$us" read -r n kind why; do
    [[ -z "$n" ]] && continue
    case "$kind" in
      sentence|short) total=$((total + 1)); (( why == 1 )) || printf 'no-why %s\n' "$n" ;;
      guidance) printf 'guidance %s\n' "$n" ;;
    esac
  done <<<"$rows"
  (( total <= max )) || printf 'over-budget %s (max %s)\n' "$total" "$max"
}
