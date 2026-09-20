#!/usr/bin/env bash
# rule-constitution.sh — 규칙 헌법 검사의 순수부.
#
# scv/SCV.md 의 "Top-level rules" 절은 규칙이 어긋날 때의 해소 순서를 말하는 **유일한**
# 자리다 (4조: 같은 요구는 한 곳에만). 이 파일의 함수들은 규칙 문서에서 뽑은 줄들을
# 문자열로 받아, (a) 그 절 밖에서 우선순위를 서술하는 줄과 (b) 두 문서 이상에 같은 요구가
# 적힌 후보를 낸다. 파일을 읽는 일은 바깥(core/tests/test-rule-constitution.sh)이 맡는다.
#
# 줄(row) 형식: "<파일>\t<줄번호>\t<본문>" — 한 줄에 하나.
#
# 어휘 목록은 그물이지 울타리가 아니다 (core/contracts/purity.md 와 같은 정신). 다른 말로
# 적힌 우선순위 문장은 잡지 못할 수 있다 — 리뷰가 잡고, 잡히면 어휘를 더한다.

# ------------------------------------------------------------------ 순수: 판별

# 우선순위를 서술하는 어휘. 대소문자 무시.
SCV_RC_PRECEDENCE_RE='overrid|precedence|takes priority|wins over|prevail|우선한다|우선순위|이긴다|먼저다'
# 규범 문장을 고르는 어휘 — 검사 (b) 의 입력이 된다.
SCV_RC_NORMATIVE_RE='(^|[^a-z])(never|always|must|do not|don.t|only)([^a-z]|$)|금지|반드시|절대'
# 참조형: 해소 순서를 적는 대신 그 자리를 가리키는 문장.
SCV_RC_REFERENCE='Top-level rules'
# 호스트 표기 정규화 (0.54.1): 래퍼는 `action:<이름>` 을 호스트별 접두어(달러 또는 슬래시 + 플러그인 이름)로
# 바꿔 배송한다. 허용목록은 정규형(`action:`)으로 적고, 비교 전에 양쪽을 이 sed 로 맞춘다 — 벤더링된
# 사본에서 검사 (a) 가 허용목록 한 줄을 못 알아봐 붉던 것을 고친다. 표준입력 필터로만 쓴다.
SCV_RC_CANON_SED='s#(\$|/)[a-z][a-z0-9-]*:([a-z][a-z-]*)#action:\2#g'

# scv_rc_is_precedence <본문> — 우선순위 어휘가 있으면 참.
# @pure
scv_rc_is_precedence() {
  local text="${1:-}"
  shopt -s nocasematch
  [[ "$text" =~ $SCV_RC_PRECEDENCE_RE ]]
  local rc=$?
  shopt -u nocasematch
  return $rc
}

# scv_rc_is_normative <본문> — 규범 동사가 있으면 참.
# @pure
scv_rc_is_normative() {
  local text="${1:-}"
  shopt -s nocasematch
  [[ "$text" =~ $SCV_RC_NORMATIVE_RE ]]
  local rc=$?
  shopt -u nocasematch
  return $rc
}

# scv_rc_is_reference <본문> — Top-level rules 를 가리키는 참조형이면 참.
# @pure
scv_rc_is_reference() {
  [[ "${1:-}" == *"$SCV_RC_REFERENCE"* ]]
}

# ------------------------------------------------------------------ 순수: 검사 (a)

# scv_rc_precedence_violations <rows> <허용 파일> <허용 시작줄> <허용 끝줄> <허용목록>
#
# rows 중 우선순위 어휘를 담았고, 참조형이 아니고, 허용 파일의 허용 구간(Top-level rules
# 절) 밖이며, 허용목록("<파일>\t<본문>" 줄들; '#' 로 시작하는 줄은 주석)에도 없는 줄을
# 그대로 낸다. 아무것도 안 내면 통과.
# @pure
scv_rc_precedence_violations() {
  local rows="${1:-}" allowed_file="${2:-}" from="${3:-0}" to="${4:-0}" allow="${5:-}"
  local file ln text allow_nl=$'\n'"$allow"$'\n'
  while IFS=$'\t' read -r file ln text; do
    [[ -z "$file" ]] && continue
    scv_rc_is_precedence "$text" || continue
    scv_rc_is_reference "$text" && continue
    if [[ "$file" == "$allowed_file" && "$ln" -ge "$from" && "$ln" -le "$to" ]]; then continue; fi
    [[ "$allow_nl" == *$'\n'"$file"$'\t'"$text"$'\n'* ]] && continue
    printf '%s\t%s\t%s\n' "$file" "$ln" "$text"
  done <<< "$rows"
}

# ------------------------------------------------------------------ 결정적: 검사 (b)

# scv_rc_normative_rows — 표준입력 rows → 규범 문장인 rows 만.
# @pure
scv_rc_normative_rows() {
  local file ln text
  while IFS=$'\t' read -r file ln text; do
    [[ -z "$file" ]] && continue
    scv_rc_is_normative "$text" || continue
    printf '%s\t%s\t%s\n' "$file" "$ln" "$text"
  done
}

# awk 프로그램은 함수 밖 상수로 둔다 — 비교 연산자(<, >)를 순수성 검사기가 리다이렉션으로
# 오해하지 않게 하려는 것이다 (지난 작업 찾기 계획의 교훈).
# 키 = 소문자, 코드 조각·마크다운 기호·구두점 제거, 앞 8단어. 6단어 미만은 버린다.
# 줄표(—·–)는 대괄호 문자 집합에 넣지 않는다 — 바이트 단위 awk(mawk)에서는 그 3바이트가 낱낱이
# 집합 원소가 되어 한글의 이어지는 바이트까지 지운다. 문자열 패턴으로 따로 지우면 맥·리눅스가 같다.
SCV_RC_AWK_KEYS='{
  file=$1; text=$3
  gsub(/`[^`]*`/, " ", text)
  gsub(/—/, " ", text); gsub(/–/, " ", text)
  gsub(/[][*_>#|()`"'"'"',.:;!?-]/, " ", text)
  n=split(text, w, /[ \t]+/); k=""; c=0
  for (i=1; i<=n; i++) { if (w[i]=="") continue; c++; if (c<=8) k=(k==""?w[i]:k" "w[i]) }
  if (c>=6) print k "\t" file
}'
# 두 파일 이상에 나온 키만.
SCV_RC_AWK_DUPS='{ c[$1]++ } END { for (k in c) if (c[k]>=2) print k }'

# scv_rc_demand_keys — 표준입력 rows → "<키>\t<파일>". 표준입력 필터만 부른다.
# @deterministic
scv_rc_demand_keys() {
  tr 'A-Z' 'a-z' | awk -F'\t' "$SCV_RC_AWK_KEYS"
}

# scv_rc_duplicate_keys — 표준입력 "<키>\t<파일>" → 두 파일 이상에 나온 키, 정렬.
# @deterministic
scv_rc_duplicate_keys() {
  LC_ALL=C sort -u | awk -F'\t' "$SCV_RC_AWK_DUPS" | LC_ALL=C sort
}

# scv_rc_ratchet_new <후보 키들> <기준선 키들> — 기준선에 없는 후보만 낸다. 비면 통과.
# @pure
scv_rc_ratchet_new() {
  local cand="${1:-}" base="${2:-}" k base_nl=$'\n'"$base"$'\n'
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    [[ "$base_nl" == *$'\n'"$k"$'\n'* ]] && continue
    printf '%s\n' "$k"
  done <<< "$cand"
}
