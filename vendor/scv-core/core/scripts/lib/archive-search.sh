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
      if (f ~ /\/archive\/[^\/]+\/WRAPUP\.md$/)               return "마무리 보고"
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

# 마무리 보고의 칸 줄 → 훑은 줄 모양. 파일 이름 줄은 단위 구분자(US)로 시작한다.
_SCV_AS_AWK_WRAPUP='
    substr($0, 1, 1) == US { f = substr($0, 2); next }
    f == "" { next }
    {
      t1 = index($0, "\t"); if (t1 == 0) next
      g = substr($0, 1, t1 - 1); r = substr($0, t1 + 1)
      t2 = index(r, "\t"); if (t2 == 0) next
      name = substr(r, 1, t2 - 1); v = substr(r, t2 + 1)
      if (g !~ /^[1-7]$/ || name == "#") next
      if (v == "" || index(v, "\074TODO") > 0) next
      printf "%s:%s:%s\n", f, g, v
    }'

# 비었는지는 길이로만 본다. 셸의 문자열 치환(${s//.../})을 큰 입력에 돌리면 아주 느리다 —
# 74KB 한 번에 1.9초였고, 그게 이 명령이 2.5초 걸리던 이유였다. 공백만 든 입력은
# awk 가 알아서 아무것도 내지 않으므로 따로 막지 않아도 된다.

# @deterministic
# 역할: 물음 한 줄을 낱말 목록(줄바꿈 구분)으로 쪼갠다 — 따옴표로 묶은 덩어리는 하나로 남긴다
# 종류: 꺼내기
# 예: '로그인 오류 수정' → $'로그인\n오류\n수정'
# 예: '"로그인 오류" 수정' → $'로그인 오류\n수정'
# 예: '' → ""
# <물음 한 줄> → 낱말 목록(줄바꿈 구분). 따옴표로 묶은 덩어리는 하나로 남긴다.
scv_as_parse_terms() {
  local raw="${1:-}"
  printf '%s' "$raw" | awk "$_SCV_AS_AWK_TERMS" | awk "$_SCV_AS_AWK_NONEMPTY"
}

# @pure
# 역할: 파일 경로 모양만 보고 기록의 종류(계획 · 검사 · 대화 · 결정 · 기타 …)를 정한다
# 종류: 판정/answer
# 예: scv/archive/x/PLAN.md → "계획"
# 예: scv/archive/x/WRAPUP.md → "마무리 보고"
# 예: scv/conversations/a.md → "대화"
# 예: scv/DECISIONS.md → "결정"
# 예: README.md → "기타"
# <파일 경로> → 기록의 종류. 경로 모양만 보고 정한다.
scv_as_kind_of() {
  case "${1:-}" in
    */archive/*/PLAN.md)                 printf '계획' ;;
    */archive/*/TESTS.md)                printf '검사' ;;
    */archive/*/FEATURE_ARCHITECTURE.md) printf '구조' ;;
    */archive/*/ARCHIVED_AT.md)          printf '보관' ;;
    */archive/*/WRAPUP.md)               printf '마무리 보고' ;;
    */raw/stale/*)                       printf '원자료' ;;
    */conversations/*)                   printf '대화' ;;
    */DECISIONS.md)                      printf '결정' ;;
    *)                                   printf '기타' ;;
  esac
}

# @pure
# 역할: 파일 경로에서 묶음 이름을 낸다 — 보관된 계획의 네 문서는 폴더 이름 하나로 합친다
# 종류: 변환
# 예: scv/archive/20260101-a-x/PLAN.md → "20260101-a-x"
# 예: scv/archive/20260101-a-x/TESTS.md → "20260101-a-x"
# 예: scv/DECISIONS.md → "DECISIONS"
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
# 역할: 한 줄에 낱말 목록 중 몇 개가 들어 있는지 센다(대소문자 무시)
# 종류: 세기
# 예: 'Fix the Login bug' $'login\nbug\nlogout' → "2"
# 예: 'nothing' $'login' → "0"
# <줄 내용> <낱말 목록> → 그 줄에 함께 나온 낱말 수. 대소문자를 가리지 않는다.
scv_as_count_terms() {
  local line="${1:-}" terms="${2:-}" t n=0 i=0 k=0 lowered=0
  local lower; lower="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
  local tl
  local -a tls=()
  while IFS= read -r t; do
    i=$((i + 1))
    [[ -n "$t" ]] || continue
    # 있는 그대로 먼저 — 문자 변환이 여러 바이트 글자를 깨뜨리는 환경이 있다.
    case "$line" in *"$t"*) n=$((n+1)); continue ;; esac
    # 소문자 낱말이 처음 필요해질 때 낱말 전체를 한 번에 바꿔 둔다 — 낱말마다 프로그램을 띄우지 않는다.
    # 줄 수는 그대로이므로 같은 줄 번호의 것이 그 낱말의 소문자다.
    if (( ! lowered )); then
      lowered=1
      while IFS= read -r tl; do tls[k]="$tl"; k=$((k + 1)); done <<< "$(printf '%s' "$terms" | tr '[:upper:]' '[:lower:]')"
    fi
    if [[ $i -le $k ]]; then tl="${tls[i - 1]}"
    else
      # 바꾸는 프로그램이 깨진 글자에서 멈춰 뒤 줄이 없을 때만 — 그 낱말 하나를 따로 바꾼다(예전과 같은 답).
      tl="$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')"
    fi
    case "$lower" in *"$tl"*) n=$((n+1)) ;; esac
  done <<< "$terms"
  printf '%s' "$n"
}

# @deterministic
# 역할: 훑은 "파일:줄번호:내용" 줄들에 낱말 맞은 수 점수를 매겨 점수 US 묶음 US 종류 US 줄번호 US 대목 줄로 낸다
# 종류: 고르기
# 예: $'scv/DECISIONS.md:3:login bug fixed' $'login\nbug' → $'2\x1fDECISIONS\x1f결정\x1f3\x1flogin bug fixed'
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
# 역할: 마무리 보고의 칸 줄들을 훑은 줄 모양("파일:묶음 번호:값")으로 바꾼다 — 묶음 제목 · 빈 값 · 채울 자리 표시(TODO)는 버리고 값만 남긴다
# 종류: 변환
# 예: $'\x1fa/WRAPUP.md\n1\t#\t문제\n1\t상황\t수달이 느리다\n7\t배운 것\t' → "a/WRAPUP.md:1:수달이 느리다"
# 예: $'\x1fa/WRAPUP.md\n2\t-\t해당 없음 — 새 기능' → "a/WRAPUP.md:2:해당 없음 — 새 기능"
# 예: $'1\t상황\t파일 이름 줄이 없다' → ""
# 예: "" → ""
# <파일 이름 줄(US + 경로)과 그 아래 칸 줄("묶음<TAB>이름<TAB>값")들> → 훑은 줄들. 여러 파일을 이어 줘도 된다.
# 마무리 보고는 모든 계획이 같은 틀(묶음 제목 · 칸 이름 · 안내 글)을 가진다. 파일을 그대로 훑으면
# "가설" 한 낱말에 모든 계획이 걸려 다른 답을 밀어낸다 — 그래서 값만 훑는다. 줄 번호 자리에는 묶음 번호(1 ~ 7)가 온다.
# 칸 줄은 scv_wu_fields(lib/wrapup.sh)가 낸 그대로다 — 무엇이 칸인지는 그 함수 하나만 안다.
scv_as_wrapup_lines() {
  local marked="${1:-}"
  [[ -n "$marked" ]] || return 0
  printf '%s\n' "$marked" | awk -v US="$_SCV_AS_US" "$_SCV_AS_AWK_WRAPUP"
}

# @deterministic
# 역할: 아주 긴 줄에서 낱말이 맞은 자리 앞뒤만 남긴 대목을 낸다(짧으면 그대로)
# 종류: 다듬기
# 예: 'short line' short 100 → "short line"
# 예: 'aaaaaaaaaaaaaaaaaaaaTARGETbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' TARGET 20 → "…aaaaaaTARGETbbbbbbbb…"
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
# 역할: 점수 매긴 줄들에서 두 낱말 이상 맞은 줄이 있으면 하나만 맞은 줄을 버린다
# 종류: 고르기
# 예: $'2\x1fg1\x1f계획\x1f1\x1fa\n1\x1fg2\x1f결정\x1f2\x1fb' → $'2\x1fg1\x1f계획\x1f1\x1fa'
# 예: $'1\x1fg2\x1f결정\x1f2\x1fb' → $'1\x1fg2\x1f결정\x1f2\x1fb'
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
# 역할: 점수 매긴 줄들에서 묶음마다 가장 높은 점수 줄 하나만 남기고 점수 내림차순으로 낸다
# 종류: 고르기
# 예: $'1\x1fg1\x1f계획\x1f1\x1fa\n3\x1fg1\x1f계획\x1f2\x1fb\n2\x1fg2\x1f결정\x1f3\x1fc' → $'3\x1fg1\x1f계획\x1f2\x1fb\n2\x1fg2\x1f결정\x1f3\x1fc'
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
# 역할: 묶음 줄들을 사람이 읽는 검색 결과 글로 만든다 — 없으면 못 찾았다고 말한다
# 종류: 조립
# 예: '' 0 1 5 x → $'ARCHIVE_SEARCH: 0\n찾은 것이 없습니다.'
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
