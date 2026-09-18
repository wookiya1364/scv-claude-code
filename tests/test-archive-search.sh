#!/usr/bin/env bash
# test-archive-search.sh — 지난 작업 찾기 (v0.53.0+).
#
# 고치려는 병: 제목만 보고 고르면 놓친다. "회귀" "훅" "설정" 은 계획서 제목에 한 건도 없는데
# 본문에는 25~30건씩 있다. 고른 뒤 통째로 읽으면 715줄이 들어오고 대부분 물음과 무관하다.
#
# 순수부는 문자열만 넣고 문자열만 확인한다. 효과부는 임시 폴더에 만든 견본으로 세운다.
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE="$HERE/.."
LIB="$CORE/scripts/lib/archive-search.sh"
CMD="$CORE/scripts/archive-search.sh"
US=$'\x1f'

pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
want() { [[ "$2" == "$3" ]] && ok || bad "$1 — 기대 [$3] / 실제 [$2]"; }
has()  { grep -qF -- "$2" <<<"$1" && ok || bad "$3 — 없음: $2"; }
hasnt(){ grep -qF -- "$2" <<<"$1" && bad "$3 — 있으면 안 됨: $2" || ok; }

[[ -f "$LIB" && -f "$CMD" ]] || { echo "  ✗ 파일 없음"; exit 1; }
bash -n "$LIB" && bash -n "$CMD" || { echo "  ✗ 문법 오류"; exit 1; }
# shellcheck disable=SC1090
source "$LIB"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

mkproj() {  # <이름> → scv 폴더를 가진 프로젝트 경로
  local p="$WORK/$1"; mkdir -p "$p/scv/archive" "$p/scv/promote" \
    "$p/scv/raw/stale" "$p/scv/conversations/archive"; echo "$p"
}
mkplan() {  # <프로젝트> <슬러그> <PLAN 본문> [TESTS 본문] [ARCHIVED 본문]
  local d="$1/scv/archive/$2"; mkdir -p "$d"
  printf '%s\n' "$3" > "$d/PLAN.md"
  [[ -n "${4:-}" ]] && printf '%s\n' "$4" > "$d/TESTS.md"
  [[ -n "${5:-}" ]] && printf '%s\n' "$5" > "$d/ARCHIVED_AT.md"
  return 0
}
run() { local p="$1"; shift; ( cd "$p" && SCV_DIR="$p/scv" bash "$CMD" "$@" 2>&1 ); }

echo ""
echo "── 순수부 ──"

# T1. 물음 한 줄을 낱말로 쪼갠다
want "T1 공백으로 쪼갠다" "$(scv_as_parse_terms 'a b c' | tr '\n' '|')" "a|b|c|"
want "T1 따옴표 덩어리는 하나" "$(scv_as_parse_terms 'a "b c" d' | tr '\n' '|')" "a|b c|d|"
want "T1 빈 낱말은 버린다" "$(scv_as_parse_terms '  a   b  ' | tr '\n' '|')" "a|b|"
want "T1 빈 물음" "$(scv_as_parse_terms '' | wc -l | tr -d '[:space:]')" "0"

# T2. 줄마다 함께 나온 낱말 수
T3=$'회귀\n관문\n없는말'
want "T2 둘 맞음" "$(scv_as_count_terms '회귀 관문이 느리다' "$T3")" "2"
want "T2 하나 맞음" "$(scv_as_count_terms '회귀만 있다' "$T3")" "1"
want "T2 없음" "$(scv_as_count_terms '아무 상관 없는 줄' "$T3")" "0"
want "T2 대소문자 무시" "$(scv_as_count_terms 'PLAN and Tests' $'plan\ntests')" "2"

# 종류와 묶음
want "종류 계획" "$(scv_as_kind_of 'scv/archive/x/PLAN.md')" "계획"
want "종류 검사" "$(scv_as_kind_of 'scv/archive/x/TESTS.md')" "검사"
want "종류 보관" "$(scv_as_kind_of 'scv/archive/x/ARCHIVED_AT.md')" "보관"
want "종류 원자료" "$(scv_as_kind_of 'scv/raw/stale/a.md')" "원자료"
want "종류 대화" "$(scv_as_kind_of 'scv/conversations/archive/a.md')" "대화"
want "종류 결정" "$(scv_as_kind_of 'scv/DECISIONS.md')" "결정"
want "묶음: 계획의 네 문서는 폴더 하나로" \
  "$(scv_as_group_of 'scv/archive/20260101-x/TESTS.md')" "$(scv_as_group_of 'scv/archive/20260101-x/PLAN.md')"

# T2c. 여러 낱말이 맞은 것이 있으면 하나만 맞은 것은 버린다
ROWS="2${US}g1${US}계획${US}10${US}본문
1${US}g2${US}검사${US}20${US}본문
1${US}g3${US}보관${US}30${US}본문"
want "T2c 잡음 버리기" "$(scv_as_drop_weak "$ROWS" | wc -l | tr -d '[:space:]')" "1"
WEAK="1${US}g1${US}계획${US}10${US}본문
1${US}g2${US}검사${US}20${US}본문"
want "T2c 전부 하나면 그대로 둔다" "$(scv_as_drop_weak "$WEAK" | wc -l | tr -d '[:space:]')" "2"

# T3. 출처별로 묶고 가장 잘 맞은 줄을 대표로
G="1${US}같은계획${US}계획${US}5${US}약한줄
3${US}같은계획${US}보관${US}9${US}강한줄
2${US}다른계획${US}검사${US}7${US}다른줄"
out="$(scv_as_group_best "$G")"
want "T3 묶음 둘" "$(wc -l <<<"$out" | tr -d '[:space:]')" "2"
want "T3 대표는 가장 잘 맞은 줄" "$(head -1 <<<"$out" | cut -d"$US" -f5)" "강한줄"
want "T3 그 줄의 종류가 함께" "$(head -1 <<<"$out" | cut -d"$US" -f3)" "보관"

# T12. 아주 긴 줄은 맞은 자리 앞뒤만
LONG="$(printf 'x%.0s' $(seq 1 200))표적$(printf 'y%.0s' $(seq 1 200))"
ex="$(scv_as_excerpt "$LONG" "표적" 60)"
(( ${#ex} <= 70 )) && ok || bad "T12 자르기 — 길이 ${#ex}"
has "$ex" "표적" "T12 맞은 낱말이 남아 있다"
want "T12 짧은 줄은 그대로" "$(scv_as_excerpt "짧은 줄" "짧은" 100)" "짧은 줄"

echo ""
echo "── 효과부 ──"

# T4 + T13a. 계획서 밖의 기록에서도 찾는다
P=$(mkproj t4)
mkplan "$P" 20260101-a $'---\ntitle: 아무 상관 없는 제목\n---\n본문에 오직여기만 이 있다' \
  $'# 검사\n- 검사문서고유낱말 확인' $'reason: 보관기록고유낱말 로 끝냄'
mkplan "$P" 20260102-b $'---\ntitle: 다른 계획\n---\n전혀 다른 내용'
printf '원자료고유낱말 이 여기 있다\n' > "$P/scv/raw/stale/old.md"
printf '대화고유낱말 이 여기 있다\n' > "$P/scv/conversations/archive/c.md"
printf '결정고유낱말 이 여기 있다\n' > "$P/scv/DECISIONS.md"

o="$(run "$P" 오직여기만)"; has "$o" "20260101-a" "T4 제목에 없고 본문에만 있는 것을 찾는다"
hasnt "$o" "20260102-b" "T4 무관한 것은 안 나온다"
o="$(run "$P" 검사문서고유낱말)";  has "$o" "(검사)"  "T13a 검사 문서에서 찾는다"
o="$(run "$P" 보관기록고유낱말)";  has "$o" "(보관)"  "T13a 보관 기록에서 찾는다"
o="$(run "$P" 원자료고유낱말)";    has "$o" "(원자료)" "T13a 원자료에서 찾는다"
o="$(run "$P" 결정고유낱말)";      has "$o" "(결정)"  "T9 결정 기록에서 찾는다"
o="$(run "$P" 대화고유낱말)";      has "$o" "(대화)"  "T13b 대화의 보관 하위 폴더까지 훑는다"

# T13c. 생성물은 훑지 않는다
printf '<html>생성물고유낱말</html>\n' > "$P/scv/archive/20260101-a/x.deck.html"
o="$(run "$P" 생성물고유낱말)"; has "$o" "찾은 것이 없습니다" "T13c 기획서 HTML 은 훑지 않는다"

# T13. 진행 중인 계획은 찾지 않는다
mkdir -p "$P/scv/promote/20260103-c"
printf '진행중고유낱말\n' > "$P/scv/promote/20260103-c/PLAN.md"
o="$(run "$P" 진행중고유낱말)"; has "$o" "찾은 것이 없습니다" "T13 진행 중인 계획은 안 나온다"

# T2b. 낱말 순서를 바꿔도 같다
P=$(mkproj t2b)
mkplan "$P" 20260201-x $'---\ntitle: x\n---\n알파와 베타가 한 줄에'
mkplan "$P" 20260202-y $'---\ntitle: y\n---\n베타만 있는 줄'
a="$(run "$P" 알파 베타 | grep -c '개 함께')"
b="$(run "$P" 베타 알파 | grep -c '개 함께')"
want "T2b 순서를 바꿔도 같은 수" "$a" "$b"
# 둘째 낱말만 가진 견본은 낱말 하나만 맞으므로, 둘 맞은 것이 있으면 잡음으로 밀린다(설계대로).
# 여기서 확인할 것은 "훑기가 그것을 보긴 했는가" 다 — 낱말 하나로 물으면 나와야 한다.
o="$(run "$P" 베타)"; has "$o" "20260202-y" "T2b 둘째 낱말로만 물으면 나온다"
o="$(run "$P" 알파 베타)"; has "$o" "20260201-x" "T2b 둘 맞은 것이 위로"

# T2d. 낱말을 여러 개 줘도 전부 전달된다
# awk 의 -v 는 값 안의 줄바꿈 처리를 보장하지 않는다 — 맥에서 낱말 목록이 통째로 비어
# 여러 낱말 물음이 한 건도 안 잡혔다. 한 낱말은 되고 여러 낱말만 안 되는 모양이었다.
P=$(mkproj t2d)
mkplan "$P" 20260210-m $'---\ntitle: m\n---\n하나 둘 셋 넷 다섯이 한 줄에'
for n in 1 2 3 4 5; do
  case "$n" in
    1) q=(하나) ;; 2) q=(하나 둘) ;; 3) q=(하나 둘 셋) ;;
    4) q=(하나 둘 셋 넷) ;; 5) q=(하나 둘 셋 넷 다섯) ;;
  esac
  o="$(run "$P" "${q[@]}")"
  if grep -q "낱말 $n/${n}개 함께" <<<"$o"; then ok
  else bad "T2d 낱말 ${n}개 — 전부 전달되지 않았다: $(grep -o '낱말 [0-9]*/[0-9]*개' <<<"$o" | head -1)"; fi
done

# T5. 찾은 것이 없으면 없다고 한다
o="$(run "$P" 어디에도없는낱말)"
has "$o" "ARCHIVE_SEARCH: 0" "T5 0건 보고"
has "$o" "찾은 것이 없습니다" "T5 없다고 말한다"
hasnt "$o" "20260201-x" "T5 비슷한 것을 대신 내놓지 않는다"

# T6. 보관된 계획이 없으면 그렇게 말한다
P=$(mkproj t6)
o="$(run "$P" 아무낱말)"; rc=$?
has "$o" "아직 보관된 기록이 없습니다" "T6 안내"
want "T6 종료 코드" "$rc" "0"

# T7. 낱말을 안 주면 쓰는 법
P=$(mkproj t7); mkplan "$P" 20260301-z $'---\ntitle: z\n---\n본문'
o="$(run "$P")"; rc=$?
has "$o" "쓰는 법" "T7 쓰는 법을 보여준다"
want "T7 종료 코드" "$rc" "0"

# T8. 결과가 많으면 끊고 전체 수를 알린다
P=$(mkproj t8)
for i in $(seq 1 12); do mkplan "$P" "202604$(printf '%02d' "$i")-m" $'---\ntitle: m\n---\n흔한낱말 이 여기'; done
o="$(run "$P" --limit 3 흔한낱말)"
want "T8 상위 3개만" "$(grep -c '개 함께' <<<"$o")" "3"
has "$o" "그 밖에" "T8 남은 수를 알린다"

# T10. 없는 곳은 건너뛴다
P=$(mkproj t10); rm -rf "$P/scv/conversations" "$P/scv/raw"
mkplan "$P" 20260501-q $'---\ntitle: q\n---\n계획에만있는낱말'
o="$(run "$P" 계획에만있는낱말)"; rc=$?
has "$o" "20260501-q" "T10 있는 곳만 훑고 찾는다"
want "T10 종료 코드" "$rc" "0"

# T11. 검색 기호는 글자 그대로
P=$(mkproj t11)
mkplan "$P" 20260601-r $'---\ntitle: r\n---\n값은 a.b*c 이다'
mkplan "$P" 20260602-s $'---\ntitle: s\n---\n값은 axbyc 이다'
o="$(run "$P" 'a.b*c')"
has "$o" "20260601-r" "T11 기호를 글자 그대로 찾는다"
hasnt "$o" "20260602-s" "T11 기호로 해석하지 않는다"

# T14. 읽기만 한다
P=$(mkproj t14); mkplan "$P" 20260701-t $'---\ntitle: t\n---\n지문낱말'
before="$(cd "$P" && find . -type f | sort | xargs -r md5sum 2>/dev/null | md5sum)"
run "$P" 지문낱말 >/dev/null; run "$P" 없는것 >/dev/null; run "$P" 지문낱말 >/dev/null
after="$(cd "$P" && find . -type f | sort | xargs -r md5sum 2>/dev/null | md5sum)"
want "T14 파일이 하나도 안 바뀐다" "$after" "$before"

# T15. 순수부가 파일을 만지지 않는다
if grep -nE '^\s*(cat|rm|mv|cp|mkdir|touch|tee|>|>>)' "$LIB" | grep -v '^\s*#' | grep -q .; then
  bad "T15 순수부에 파일 조작이 있다"
else ok; fi
grep -qE '^# @pure' "$LIB" && ok || bad "T15 순수성 표시가 없다"

echo ""
echo "── 옛 셸에서도 깨지지 않는가 ──"
# 맥에는 bash 3.2 가 있고, 거기서는 "$n개" 의 한글이 변수 이름의 일부로 읽혀 unbound 가 난다.
# 리눅스에서는 멀쩡해서 CI 의 맥 쪽만 세 번 붉었다. 같은 함정을 글자 규칙으로 막는다.
for f in "$HERE/test-archive-search.sh" "$CORE/scripts/archive-search.sh" "$CORE/scripts/lib/archive-search.sh"; do
  # 주석은 뺀다 — 이 함정을 설명하는 주석 자신이 걸린다.
  if sed 's/[[:space:]]*#.*$//' "$f" \
     | grep -qP '\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7F])'; then
    bad "옛 셸 함정: $(basename "$f") 에 변수 뒤 곧바로 여러 바이트 글자가 온다 — \${var} 로 감쌀 것"
  else ok; fi
done

# 이 검사가 원본 저장소에서 도는지, 벤더링된 사본에서 도는지 (0.53.1).
# 사본에는 보관된 계획이 없다 — 아래 "실물" 묶음은 거기서 건너뛴다.
REPO="$(cd "$CORE/.." && pwd)"
IS_CORE_REPO=0; [[ -f "$REPO/VERSION" && -f "$REPO/core/TEMPLATE_DIGEST" && -d "$REPO/scv/archive" ]] && IS_CORE_REPO=1

if (( IS_CORE_REPO )); then
  echo ""
  echo "── 이 저장소에서 (실물) ──"
  # 계획이 "못 찾는다" 고 한 낱말들이 실제로 찾아지는가
  for w in 회귀 훅 설정; do
    t="$(ls "$REPO/scv/archive" 2>/dev/null | grep -ci "$w" || true)"
    o="$( cd "$REPO" && bash "$CMD" --limit 1 "$w" 2>/dev/null )"
    if grep -q '개 함께' <<<"$o"; then ok; else bad "실물: '$w' 을 못 찾았다 (제목 일치 ${t}건)"; fi
  done
fi

echo ""
echo "── test-archive-search: $pass passed, $fail failed ──"
[[ $fail -eq 0 ]]
