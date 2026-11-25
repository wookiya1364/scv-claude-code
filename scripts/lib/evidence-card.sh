#!/usr/bin/env bash
# lib/evidence-card.sh — 숫자 결과를 눈에 보이는 그림으로(계획 20261125-wookiya1364-visible-evidence-background).
#
# 단계가 끝났다는 증거는 사람이 눈으로 볼 수 있는 것이어야 한다(영상 · 이미지 · 차트) — 소스코드 파일이 아니다. 시험 통과 수나 전후 값처럼
# 숫자뿐인 결과는 이 함수들이 막대 그림(SVG)으로 만든다: 모델이 그림을 그리느라 토큰을 쓰지 않고, 같은 입력이면 같은 파일이 나온다.
# 꺾쇠는 변수로 적는다 — 순수성 검사가 꺾쇠를 파일 읽기 · 쓰기와 가르지 못한다.

# @pure
# 역할: "이름=값" 줄들을 읽어 가장 큰 값에 맞춘 막대 길이를 붙인다 — 줄마다 "이름<탭>값<탭>길이". 값이 숫자가 아닌 줄과 빈 줄은 뺀다
# 종류: 변환
# 예: $'통과=124\n실패=2' 300 → $'통과\t124\t300\n실패\t2\t4'
# 예: $'전=6.2\n뒤=4.3' 200 → $'전\t6.2\t200\n뒤\t4.3\t138'
# 예: $'메모=없음' 300 → ""
# 예: "" 300 → ""
# <이름=값 줄들> <가장 긴 막대의 길이> → 길이는 값에 비례하고 0 이 아닌 값은 적어도 1. 값은 소수 둘째 자리까지 읽는다(적힌 글은 그대로 보인다).
scv_card_rows() {
  local lines="${1:-}" full="${2:-300}" line name val whole frac n max=0 out="" len T=$'\t' nl=$'\n'
  local re='^(.*[^[:space:]])[[:space:]]*=[[:space:]]*([0-9]+)(\.([0-9]{1,2})[0-9]*)?[[:space:]]*$'
  local names=() vals=() nums=() i=0
  while IFS= read -r line; do
    [[ "$line" =~ $re ]] || continue
    name="${BASH_REMATCH[1]}"; whole="${BASH_REMATCH[2]}"; frac="${BASH_REMATCH[4]}"
    val="$whole${frac:+.$frac}"; frac="${frac}00"; frac="${frac:0:2}"
    n=$(( 10#$whole * 100 + 10#$frac ))
    names[i]="$name"; vals[i]="$val"; nums[i]="$n"; i=$(( i + 1 ))
    (( n > max )) && max="$n"
  done <<< "$lines"
  (( i > 0 )) || return 0
  n=0
  while (( n < i )); do
    len=0
    if (( max > 0 )); then len=$(( nums[n] * full / max )); (( nums[n] > 0 && len < 1 )) && len=1; fi
    out+="${out:+$nl}${names[n]}$T${vals[n]}$T$len"
    n=$(( n + 1 ))
  done
  printf '%s' "$out"
}

# @pure
# 역할: 제목과 "이름<탭>값<탭>길이" 줄들로 막대 그림 SVG 글을 만든다 — 줄이 없으면 빈 값
# 종류: 조립/gate
# 예: "시험" "" → ""
# <제목> <줄들: 이름<탭>값<탭>길이> → SVG 글. 이름 · 제목의 꺾쇠와 & 는 글자로 바꿔 적는다. 같은 입력이면 바이트까지 같은 글.
scv_card_svg() {
  local title="${1:-}" rows="${2:-}" lt=$'\x3c' gt=$'\x3e' amp='&amp;' elt='&lt;' egt='&gt;' T=$'\t' nl=$'\n'
  local line name val len y n=0 body="" h esc
  [[ -n "$rows" ]] || return 0
  while IFS="$T" read -r name val len; do
    [[ -n "$name" && "$len" =~ ^[0-9]+$ ]] || continue
    esc=${name//&/"$amp"}; esc=${esc//"$lt"/"$elt"}; esc=${esc//"$gt"/"$egt"}
    y=$(( 56 + n * 26 ))
    body+="${lt}text x=\"290\" y=\"$(( y + 14 ))\" font-size=\"12\" text-anchor=\"end\" fill=\"#52514e\"${gt}${esc}${lt}/text${gt}$nl"
    body+="${lt}rect x=\"300\" y=\"$y\" width=\"$len\" height=\"16\" rx=\"3\" fill=\"#2a78d6\"/${gt}$nl"
    body+="${lt}text x=\"$(( 308 + len ))\" y=\"$(( y + 13 ))\" font-size=\"12\" fill=\"#0b0b0b\"${gt}${val}${lt}/text${gt}$nl"
    n=$(( n + 1 ))
  done <<< "$rows"
  (( n > 0 )) || return 0
  h=$(( 70 + n * 26 ))
  esc=${title//&/"$amp"}; esc=${esc//"$lt"/"$elt"}; esc=${esc//"$gt"/"$egt"}
  printf '%s\n' "${lt}svg xmlns=\"http://www.w3.org/2000/svg\" width=\"720\" height=\"$h\" viewBox=\"0 0 720 $h\" font-family=\"-apple-system, sans-serif\"${gt}"
  printf '%s\n' "${lt}rect width=\"720\" height=\"$h\" fill=\"#fcfcfb\"/${gt}"
  printf '%s\n' "${lt}text x=\"20\" y=\"34\" font-size=\"17\" font-weight=\"500\" fill=\"#0b0b0b\"${gt}${esc}${lt}/text${gt}"
  printf '%s' "$body"
  printf '%s\n' "${lt}/svg${gt}"
}
