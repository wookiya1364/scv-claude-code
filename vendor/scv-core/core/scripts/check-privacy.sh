#!/usr/bin/env bash
# check-privacy.sh — 공개 저장소에 개인정보가 다시 쌓이지 않게 막는 병합 시점 검사.
#
# 범위(BASE..HEAD)의 커밋마다 커밋 메시지와 더해진 줄을 본다. 걸리는 것: 내 컴퓨터 경로, 세션 id, 세션 링크 줄,
# 비밀 목록(SCV_PRIVACY_TERMS — 줄마다 하나, CI 는 Actions 비밀값)의 낱말. 비밀 목록 낱말은 출력에서 가린다(몇 번째
# 목록 줄인지만 말한다). 작성자 이름 · 메일과 개인 메일 주소는 기본으로 보지 않는다 — 공개 계정의 이름 · 메일을 쓰는
# 저장소가 있어서다. SCV_PRIVACY_EMAILS=on 이면 작성자 · 커미터가 noreply · 봇 주소인지와 개인 메일 주소도 막는다.
#
# 입력(환경): BASE_SHA(없으면 origin/BASE_REF 와의 merge-base), BASE_REF, SCV_PRIVACY_TERMS(선택), SCV_PRIVACY_EMAILS(선택)
# 출력: 통과면 "OK privacy: …" 와 exit 0, 걸리면 "✖ privacy: …" 줄들과 exit 1. 맥(bash 3.2) · 리눅스 공통.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/privacy.sh
source "$HERE/lib/privacy.sh"

base="${BASE_SHA:-}"
if [[ -z "$base" && -n "${BASE_REF:-}" ]] && git rev-parse --verify --quiet "origin/$BASE_REF" >/dev/null; then
  base="$(git merge-base "origin/$BASE_REF" HEAD 2>/dev/null)"
fi
[[ -n "$base" ]] || { echo "OK privacy: no merge base available — skipping."; exit 0; }
TERMS="${SCV_PRIVACY_TERMS:-}"
EMAILS="${SCV_PRIVACY_EMAILS:-off}"
rule_on() { [[ "$1" != personal-email || "$EMAILS" == on ]]; }

fail=0; ncommit=0; nline=0
bad() { echo "✖ privacy: $*"; fail=1; }

# ---------------------------------------------------------------- 커밋 · 메시지
while IFS= read -r c; do
  [[ -z "$c" ]] && continue
  ncommit=$((ncommit + 1))
  short="${c:0:7}"
  ae="$(git log -1 --format=%ae "$c")"; ce="$(git log -1 --format=%ce "$c")"
  [[ "$EMAILS" == on ]] && { scv_privacy_email_ok "$ae" || bad "$short author email is not a noreply address — set git config user.email to your GitHub noreply address"; }
  [[ "$EMAILS" == on ]] && { scv_privacy_email_ok "$ce" || bad "$short committer email is not a noreply address"; }
  for who in "$(git log -1 --format=%an "$c")" "$(git log -1 --format=%cn "$c")"; do
    t="$(scv_privacy_term_hit "$who" "$TERMS")"; [[ -n "$t" ]] && bad "$short author/committer name matches private term #$t"
  done
  while IFS= read -r line; do
    r="$(scv_privacy_text_rule "$line")"; [[ -n "$r" ]] && rule_on "$r" && bad "$short commit message: $r"
    t="$(scv_privacy_term_hit "$line" "$TERMS")"; [[ -n "$t" ]] && bad "$short commit message matches private term #$t"
  done <<< "$(git log -1 --format=%B "$c")"
done <<< "$(git rev-list "$base"..HEAD)"

# ---------------------------------------------------------------- 더해진 줄
file=""; lno=0
while IFS= read -r line; do
  case "$line" in
    '+++ b/'*) file="${line#+++ b/}"; continue ;;
    '+++ '*) file=""; continue ;;
    '@@ '*) lno="$(printf '%s' "$line" | sed -E 's/^@@ -[0-9,]+ \+([0-9]+).*/\1/')"; lno=$((lno - 1)); continue ;;
    '+'*) lno=$((lno + 1)) ;;
    ' '*) lno=$((lno + 1)); continue ;;
    *) continue ;;
  esac
  [[ -z "$file" ]] && continue
  scv_privacy_path_skipped "$file" && continue
  nline=$((nline + 1))
  text="${line#+}"
  r="$(scv_privacy_text_rule "$text")"; [[ -n "$r" ]] && rule_on "$r" && bad "$file:$lno $r"
  t="$(scv_privacy_term_hit "$text" "$TERMS")"; [[ -n "$t" ]] && bad "$file:$lno matches private term #$t"
done <<< "$(git diff --no-color --unified=0 --no-renames "$base"...HEAD 2>/dev/null)"

(( fail )) && exit 1
echo "OK privacy: $ncommit commit(s), $nline added line(s), $(printf '%s\n' "$TERMS" | grep -c '[^[:space:]]') private term(s)"
