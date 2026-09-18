#!/usr/bin/env bash
# archive-search.sh (lib) — 지난 작업 찾기의 순수부 (v0.53.0+).
#
# 왜 있나: 지난 작업을 찾을 때 제목만 보고 고르면 놓친다. "회귀" "훅" "설정" 은 계획서 제목에
# 한 건도 없는데 본문에는 25~30건씩 있다. 고른 뒤 계획서를 통째로 읽으면 715줄이 들어오고
# 대부분 물음과 무관하다. 본문까지 훑어 맞는 대목만 출처와 함께 내면 둘 다 해결된다.
#
# 순수성 계약: 여기의 함수는 문자열만 받아 문자열만 낸다. 파일도 시각도 난수도 만지지 않는다.
# 파일을 훑는 일과 출력은 scripts/archive-search.sh (효과부) 가 한다.
#
# 설계에서 시제품으로 확인한 것 셋:
#  · 점수는 파일이 아니라 줄로 센다. 파일 단위로 세면 한 계획이 계획서·검사·구조·보관 네 곳에서
#    따로 올라와 상위 자리를 혼자 먹고, 보여주는 대목도 엉뚱해진다.
#  · 훑을 때 아무 낱말이라도 걸리면 후보로 본다. 첫 낱말로만 훑으면 순서만 바꿔도 답이 달라진다.
#  · 여러 낱말이 맞은 것이 있으면 하나만 맞은 것은 뒤로 민다.
#
# 레코드 구분자는 단위 구분자(US, 0x1f). 줄 구분은 개행.

_SCV_AS_US=$'\x1f'

# awk 프로그램 — 함수 밖 상수. 순수성 검사기는 함수 본문만 보고, 프로그램 글 안의
# 부등호(length(s) > 0)를 파일 리다이렉션으로 오해한다. Graft 라이브러리가 jq 프로그램을
# 같은 이유로 밖에 두는 것과 같은 관례다.
_SCV_AS_AWK_TERMS='
    {
      s = $0; out = ""
      while (length(s) > 0) {
        c = substr(s, 1, 1)
        if (c == "\"") {
          e = index(substr(s, 2), "\"")
          if (e > 0) { out = out substr(s, 2, e - 1) "\n"; s = substr(s, e + 2) }
          else { out = out substr(s, 2) "\n"; s = "" }
        } else if (c == " " || c == "\t") {
          s = substr(s, 2)
        } else {
          e = match(s, /[ \t]/)
          if (e > 0) { out = out substr(s, 1, e - 1) "\n"; s = substr(s, e) }
          else { out = out s "\n"; s = "" }
        }
      }
      printf "%s", out
    }'
# 작은 awk 조각도 상수로. 'NF' 만 쓰면 부등호가 없어 오탐이 나지 않는다.
_SCV_AS_AWK_NONEMPTY='NF'
_SCV_AS_AWK_MAXSCORE='NF { if ($1+0 >= m+0) m=$1+0 } END { print m+0 }'
_SCV_AS_AWK_KEEP_STRONG='NF && $1+0 >= 2'
_SCV_AS_AWK_FIRST_PER_GROUP='!seen[$2]++'
_SCV_AS_AWK_SCORE='
    BEGIN {
      nt = split(TERMS, T, "\t"); k = 0
      for (i = 1; i <= nt; i++) if (length(T[i]) > 0) { k++; O[k] = T[i]; L[k] = tolower(T[i]) }
      nt = k
    }
    function kind_of(f) {
      if (f ~ /\/archive\/[^\/]+\/PLAN\.md$/)                 return "계획"
      if (f ~ /\/archive\/[^\/]+\/TESTS\.md$/)                return "검사"
      if (f ~ /\/archive\/[^\/]+\/FEATURE_ARCHITECTURE\.md$/) return "구조"
      if (f ~ /\/archive\/[^\/]+\/ARCHIVED_AT\.md$/)          return "보관"
      if (f ~ /\/raw\/stale\//)                               return "원자료"
      if (f ~ /\/conversations\//)                             return "대화"
      if (f ~ /DECISIONS\.md$/)                                 return "결정"
      return "기타"
    }
    function group_of(f,  n, parts, base) {
      if (f ~ /\/archive\/[^\/]+\//) { sub(/\/[^\/]+$/, "", f); n = split(f, parts, "/"); return parts[n] }
      n = split(f, parts, "/"); base = parts[n]; sub(/\.md$/, "", base); return base
    }
    {
      c1 = index($0, ":"); if (c1 == 0) next
      f = substr($0, 1, c1 - 1); r = substr($0, c1 + 1)
      c2 = index(r, ":");  if (c2 == 0) next
      ln = substr(r, 1, c2 - 1); body = substr(r, c2 + 1)
      if (ln !~ /^[0-9]+$/) next
      # 있는 그대로 먼저, 없을 때만 소문자로 — BSD awk 의 tolower() 는 한글을 깨뜨린다.
      lo = tolower(body); n = 0
      for (i = 1; i <= nt; i++) if (index(body, O[i]) > 0 || index(lo, L[i]) > 0) n++
      if (n == 0) next
      printf "%d%s%s%s%s%s%s%s%s\n", n, US, group_of(f), US, kind_of(f), US, ln, US, body
    }'

# 비었는지는 길이로만 본다. 셸의 문자열 치환(${s//.../})을 큰 입력에 돌리면 아주 느리다 —
# 74KB 한 번에 1.9초였고, 그게 이 명령이 2.5초 걸리던 이유였다. 공백만 든 입력은
# awk 가 알아서 아무것도 내지 않으므로 따로 막지 않아도 된다.

# @deterministic
# <물음 한 줄> → 낱말 목록(줄바꿈 구분). 따옴표로 묶은 덩어리는 하나로 남긴다.
scv_as_parse_terms() {
  local raw="${1:-}"
  printf '%s' "$raw" | awk "$_SCV_AS_AWK_TERMS" | awk "$_SCV_AS_AWK_NONEMPTY"
}

# @pure
# <파일 경로> → 기록의 종류. 경로 모양만 보고 정한다.
scv_as_kind_of() {
  case "${1:-}" in
    */archive/*/PLAN.md)                 printf '계획' ;;
    */archive/*/TESTS.md)                printf '검사' ;;
    */archive/*/FEATURE_ARCHITECTURE.md) printf '구조' ;;
    */archive/*/ARCHIVED_AT.md)          printf '보관' ;;
    */raw/stale/*)                       printf '원자료' ;;
    */conversations/*)                   printf '대화' ;;
    */DECISIONS.md)                      printf '결정' ;;
    *)                                   printf '기타' ;;
  esac
}

# @pure
# <파일 경로> → 묶음 이름. 보관된 계획의 네 문서는 한 폴더 이름으로 합친다 —
# 합치지 않으면 한 계획이 네 칸을 차지해 다른 답이 밀려난다.
scv_as_group_of() {
  local f="${1:-}"
  case "$f" in
    */archive/*/*) f="${f%/*}"; printf '%s' "${f##*/}" ;;
    *)             f="${f##*/}"; printf '%s' "${f%.md}" ;;
  esac
}

# @deterministic
# <줄 내용> <낱말 목록> → 그 줄에 함께 나온 낱말 수. 대소문자를 가리지 않는다.
scv_as_count_terms() {
  local line="${1:-}" terms="${2:-}" t n=0
  local lower; lower="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
  local tl
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    # 있는 그대로 먼저 — 문자 변환이 여러 바이트 글자를 깨뜨리는 환경이 있다.
    case "$line" in *"$t"*) n=$((n+1)); continue ;; esac
    tl="$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in *"$tl"*) n=$((n+1)) ;; esac
  done <<< "$terms"
  printf '%s' "$n"
}

# @deterministic
# <훑은 줄들> <낱말 목록> → 점수 매긴 줄들. 자르기는 하지 않는다 —
# 327줄을 다 잘라도 보여주는 것은 다섯 줄뿐이고, mawk 는 한글을 바이트로 세어
# 글자 중간을 자른다. 자르기는 보여줄 줄에만, 글자를 아는 셸에서 한다.
#   들어오는 한 줄: <파일>:<줄번호>:<내용>   (훑기가 그대로 내는 모양)
#   나가는 한 줄:   <점수>US<묶음>US<종류>US<줄번호>US<대목>
#
# 한 번의 awk 로 끝낸다. 줄마다 셸에서 다시 비교하면 같은 일이 백 배 느려진다 —
# 처음에 그렇게 썼다가 327줄에 11초가 걸렸다. 훑기를 한 번에 끝내라는 규칙은
# 훑기 뒤의 계산에도 똑같이 적용된다.
scv_as_score_lines() {
  local sweep="${1:-}" terms="${2:-}"
  [[ -n "$sweep" ]] || return 0
  # awk 의 -v 는 값 안의 줄바꿈을 보장하지 않는다 — 맥에서 낱말 목록이 통째로 비어
  # 여러 낱말 물음이 한 건도 안 잡혔다. 한 줄짜리 구분자로 이어 붙여 넘긴다.
  local joined; joined="$(printf '%s' "$terms" | tr '\n' '\t')"
  printf '%s\n' "$sweep" | awk -v TERMS="$joined" -v US="$_SCV_AS_US" "$_SCV_AS_AWK_SCORE"
}

# @deterministic
# <아주 긴 줄> <낱말 하나> <상한> → 맞은 자리 앞뒤만 남긴 대목.
scv_as_excerpt() {
  local line="${1:-}" term="${2:-}" max="${3:-100}"
  [[ "$max" =~ ^[0-9]+$ ]] || max=100
  (( ${#line} <= max )) && { printf '%s' "$line"; return 0; }
  local pre start pos
  # 있는 그대로 먼저 찾는다 — 소문자 변환이 여러 바이트 글자를 깨뜨리는 환경이 있다.
  pre="${line%%"$term"*}"
  if [[ "$pre" == "$line" ]]; then
    local lower tl
    lower="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
    tl="$(printf '%s' "$term" | tr '[:upper:]' '[:lower:]')"
    pre="${lower%%"$tl"*}"
  fi
  if [[ "$pre" == "$line" || "$pre" == "$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')" ]]; then start=0
  else pos=${#pre}; start=$(( pos - max / 3 )); fi
  (( start < 0 )) && start=0
  (( start > 0 )) && printf '…'
  printf '%s' "${line:start:max}"
  (( start + max < ${#line} )) && printf '…'
  return 0
}

# @deterministic
# <점수 매긴 줄들> → 잡음을 뒤로 민 줄들.
# 여러 낱말이 맞은 줄이 하나라도 있으면, 하나만 맞은 줄은 전부 버린다 —
# 시제품에서 상위 다섯 중 셋이 낱말 하나만 맞은 잡음이었다.
# 입력·출력 한 줄: <점수>US<묶음>US<종류>US<줄번호>US<대목>
scv_as_drop_weak() {
  local rows="${1:-}"
  [[ -n "$rows" ]] || return 0
  local best
  best="$(printf '%s\n' "$rows" | awk -F"$_SCV_AS_US" "$_SCV_AS_AWK_MAXSCORE")"
  if [[ "${best:-0}" -ge 2 ]]; then
    printf '%s\n' "$rows" | awk -F"$_SCV_AS_US" "$_SCV_AS_AWK_KEEP_STRONG"
  else
    printf '%s\n' "$rows" | awk "$_SCV_AS_AWK_NONEMPTY"
  fi
}

# @deterministic
# <점수 매긴 줄들> → 묶음마다 가장 잘 맞은 줄 하나만 남긴 줄들 (점수 내림차순).
scv_as_group_best() {
  local rows="${1:-}"
  [[ -n "$rows" ]] || return 0
  printf '%s\n' "$rows" | awk "$_SCV_AS_AWK_NONEMPTY" \
    | sort -t"$_SCV_AS_US" -k2,2 -k1,1nr \
    | awk -F"$_SCV_AS_US" "$_SCV_AS_AWK_FIRST_PER_GROUP" \
    | sort -t"$_SCV_AS_US" -k1,1nr
}

# @deterministic
# <묶음 줄들> <전체 줄 수> <낱말 수> <상한> <첫 낱말> → 사람이 읽는 글.
# 찾은 것이 없으면 그렇게 말한다 — 비슷한 것을 대신 내놓지 않는다.
scv_as_render() {
  local rows="${1:-}" total="${2:-0}" nterms="${3:-1}" limit="${4:-5}" first="${5:-}"
  [[ "$limit" =~ ^[0-9]+$ ]] || limit=5
  if [[ -z "$rows" ]]; then
    printf 'ARCHIVE_SEARCH: 0\n찾은 것이 없습니다.\n'
    return 0
  fi
  local shown; shown="$(printf '%s\n' "$rows" | awk "$_SCV_AS_AWK_NONEMPTY" | wc -l | tr -d '[:space:]')"
  printf 'ARCHIVE_SEARCH: %s\n' "$shown"
  printf '맞은 줄 %s개 · 출처 %s곳' "$total" "$shown"
  (( shown > limit )) && printf ' — 상위 %s' "$limit"
  printf '\n'
  printf '%s\n' "$rows" | awk "$_SCV_AS_AWK_NONEMPTY" | head -n "$limit" \
    | while IFS="$_SCV_AS_US" read -r score group kind ln body; do
        printf '  %s (%s) — 낱말 %s/%s개 함께\n      %s:%s %s\n' \
          "$group" "$kind" "$score" "$nterms" "$kind" "$ln" \
          "$(scv_as_excerpt "$body" "$first" "${SCV_SEARCH_EXCERPT:-100}")"
      done
  (( shown > limit )) && printf '  … 그 밖에 %s곳. 낱말을 더 주면 좁혀집니다.\n' "$(( shown - limit ))"
  return 0
}
