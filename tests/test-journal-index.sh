#!/usr/bin/env bash
# test-journal-index.sh — 저널 색인. 순수부 전수 + 실제 읽기.
#
# 계획: 20260823-wookiya1364-journal-index
# 계약: core/contracts/purity.md
#
# 판정은 전부 문자열 비교다.
#
# Run: bash core/tests/test-journal-index.sh
set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$REPO_ROOT/scripts/lib/journal-index.sh"
APPEND="$REPO_ROOT/scripts/journal-append.sh"
READ="$REPO_ROOT/scripts/journal-read.sh"
CHECK="$REPO_ROOT/scripts/check-purity.sh"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi; }

for f in "$LIB" "$APPEND" "$READ"; do [[ -f "$f" ]] || { echo "✖ 없다: $f"; exit 1; }; done
# shellcheck source=../scripts/lib/journal-index.sh
source "$LIB"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ============================================================ T1. 표시 정규화 전수
echo "T1. 표시 정규화 — 알려진 것만 통과"
T1_OK=0; T1_N=0
check_mark() { T1_N=$((T1_N+1)); [[ "$(journal_mark_normalize "$1")" == "$2" ]] && T1_OK=$((T1_OK+1)) \
               || fail "T1 [$1] — expected [$2], got [$(journal_mark_normalize "$1")]"; }
for m in decision plan blocker pivot; do
  check_mark "$m" "$m"                     # 그대로
  check_mark "${m^^}" "$m"                 # 대문자
  check_mark "  $m  " "$m"                 # 앞뒤 공백
done
for bad in nonsense "" "decisions" "de cision" "-decision" "plan!"; do
  check_mark "$bad" ""                     # 알 수 없는 것은 빈 값
done
eq "표시 전수 ${T1_N}가지" "$T1_N" "$T1_OK"
[[ $T1_OK -eq $T1_N ]] && echo "OK [T1] $T1_OK/$T1_N"

# ============================================================ T2. 레코드 만들기
echo
echo "T2. 레코드 — 잘못된 입력은 빈 값"
R="$(journal_index_record decision k f 100 250 t1 "요약")"
eq "정상 레코드"        "decision	k	f	100	250	t1	요약" "$(printf '%s' "$R")"
eq "알 수 없는 표시"    "" "$(journal_index_record bogus k f 1 2 t s)"
eq "오프셋이 숫자 아님" "" "$(journal_index_record decision k f abc 2 t s)"
eq "길이 0"             "" "$(journal_index_record decision k f 1 0 t s)"
eq "길이가 음수"        "" "$(journal_index_record decision k f 1 -5 t s)"
eq "키 없음"            "" "$(journal_index_record decision '' f 1 2 t s)"
eq "파일 없음"          "" "$(journal_index_record decision k '' 1 2 t s)"
# 탭·줄바꿈이 들어가면 형식이 깨진다 — 공백으로 바꾼다
NL="$(journal_index_record decision "a	b" f 1 2 t "x
y")"
[[ "$(printf '%s' "$NL" | wc -l | tr -d ' ')" == "0" ]] && ok "탭·줄바꿈이 섞여도 한 줄" \
  || fail "T2 — 레코드가 여러 줄이 됐다"
echo "OK [T2]"

# ============================================================ T3. 조회 — 최신이 이긴다
echo
echo "T3. 조회 — 같은 키는 최신이 이긴다"
IDX="$(printf 'decision\tk1\tf\t10\t20\tt1\t옛것\ndecision\tk2\tf\t30\t40\tt2\t다른것\nplan\tk1\tf\t50\t60\tt3\t최신\n')"
eq "k1 은 최신"     "plan	k1	f	50	60	t3	최신"      "$(journal_index_lookup "$IDX" k1)"
eq "k2"             "decision	k2	f	30	40	t2	다른것"  "$(journal_index_lookup "$IDX" k2)"
eq "없는 키"        "" "$(journal_index_lookup "$IDX" nope)"
eq "빈 색인"        "" "$(journal_index_lookup "" k1)"
eq "빈 키"          "" "$(journal_index_lookup "$IDX" "")"
# 반복 가능성 — 이것이 깨지면 나머지가 전부 의미를 잃는다
R1="$(journal_index_lookup "$IDX" k1)"; SAME=1
for _ in $(seq 1 50); do [[ "$(journal_index_lookup "$IDX" k1)" == "$R1" ]] || SAME=0; done
eq "같은 입력 50회 → 같은 출력" "1" "$SAME"
echo "OK [T3]"

# ============================================================ T4. 걸러내기
echo
echo "T4. 표시로 거르기 — 옛 레코드는 빠진다"
N_ALL="$(journal_index_filter "$IDX" "" | grep -c . || true)"
eq "전부 (k1 은 최신 하나만)" "2" "$N_ALL"
N_PLAN="$(journal_index_filter "$IDX" plan | grep -c . || true)"
eq "plan 만" "1" "$N_PLAN"
N_NONE="$(journal_index_filter "$IDX" blocker | grep -c . || true)"
eq "없는 표시" "0" "$N_NONE"
echo "OK [T4]"

# ============================================================ T5. 순수성
echo
echo "T5. 순수부에 부수효과가 없는가"
if bash "$CHECK" "$LIB" >/dev/null 2>&1; then
  ok "$(bash "$CHECK" "$LIB" 2>&1 | sed 's/^OK  purity: //')"
  echo "OK [T5]"
else
  fail "T5 — 순수성 위반:"; bash "$CHECK" "$LIB" 2>&1 | sed 's/^/      /'
fi

# ============================================================ T6. 실제 쓰기·읽기
echo
echo "T6. 저널을 훑지 않고 그 항목만 읽는가"
P="$WORK/proj"; mkdir -p "$P/scv/journal"
export SCV_JOURNAL_DIR="$P/scv/journal"
( cd "$P"
  bash "$APPEND" --mark decision --key store --speaker assistant "설정을 두 파일로 가른다" >/dev/null
  for i in 1 2 3 4 5 6 7 8; do echo "잡담 $i — 이 줄들은 색인에 없다" | bash "$APPEND" >/dev/null; done
  bash "$APPEND" --mark blocker --key timing --speaker assistant "업데이트 즉시 갱신은 불가능하다" >/dev/null
  bash "$APPEND" --mark decision --key store --speaker assistant "생각을 바꿨다: 되돌아가기도 없앤다" >/dev/null
)
JOURNAL="$(find "$P/scv/journal" -name '*.md' | head -1)"
IDXF="$P/scv/journal/INDEX.tsv"
[[ -f "$IDXF" ]] && ok "색인 파일이 생겼다" || fail "T6 — 색인이 없다"
eq "표시한 것만 색인에 (3건)" "3" "$(grep -c . "$IDXF" 2>/dev/null || echo 0)"

OUT="$( cd "$P" && bash "$READ" --key store 2>/dev/null )"
grep -qF "생각을 바꿨다" <<<"$OUT" && ok "최신 결정을 읽는다" || fail "T6 — 최신이 아니다"
grep -qF "잡담" <<<"$OUT" && fail "T6 — 표시 안 한 턴이 섞여 나온다" || ok "표시 안 한 턴은 안 나온다"

JB="$(wc -c < "$JOURNAL" | tr -d ' ')"; OB="$(printf '%s' "$OUT" | wc -c | tr -d ' ')"
if (( OB < JB / 2 )); then ok "읽은 양 ${OB}B < 저널 ${JB}B 의 절반 — 훑지 않는다"
else fail "T6 — 읽은 양이 저널에 비해 크다 (${OB}B / ${JB}B)"; fi

ERR="$( cd "$P" && bash "$READ" --key store 2>&1 >/dev/null )"
[[ -z "$ERR" ]] && ok "정상 읽기는 조용하다" || fail "T6 — 정상인데 경고가 나온다: $ERR"
echo "OK [T6]"

# ============================================================ T7. 손상 감지
echo
echo "T7. 저널이 손으로 편집되면 알린다"
cp "$JOURNAL" "$JOURNAL.bak"
sed -i.tmp '2d' "$JOURNAL" 2>/dev/null || sed -i '' '2d' "$JOURNAL"
ERR="$( cd "$P" && bash "$READ" --key store 2>&1 >/dev/null )"
grep -q "edited by hand" <<<"$ERR" && ok "밀림을 잡는다" || fail "T7 — 편집을 못 잡는다"
[[ "$( cd "$P" && bash "$READ" --key store >/dev/null 2>&1; echo $? )" == "0" ]] \
  && ok "손상돼도 exit 0 — 부르는 쪽을 막지 않는다" || fail "T7 — 손상이 명령을 막는다"
mv "$JOURNAL.bak" "$JOURNAL"; rm -f "$JOURNAL.tmp"
echo "OK [T7]"

# ============================================================ T8. 없어도 죽지 않는다
echo
echo "T8. 색인이 없거나 깨져도 죽지 않는다"
E="$WORK/empty"; mkdir -p "$E/scv/journal"
rc="$( cd "$E" && SCV_JOURNAL_DIR="$E/scv/journal" bash "$READ" --list >/dev/null 2>&1; echo $? )"
eq "색인 없음 → exit 0" "0" "$rc"
printf 'garbage without tabs\n' > "$E/scv/journal/INDEX.tsv"
rc="$( cd "$E" && SCV_JOURNAL_DIR="$E/scv/journal" bash "$READ" --key x >/dev/null 2>&1; echo $? )"
eq "깨진 색인 → exit 0" "0" "$rc"
# 알 수 없는 표시로 기록해도 저널 자체는 써진다
U="$WORK/unknown"; mkdir -p "$U/scv/journal"
out="$( cd "$U" && SCV_JOURNAL_DIR="$U/scv/journal" bash "$APPEND" --mark bogus --speaker user "내용" 2>&1 )"
grep -q "JOURNAL_FILE:" <<<"$out" && ok "알 수 없는 표시여도 저널 기록은 된다" || fail "T8 — 기록이 막혔다"
grep -q "unknown journal mark" <<<"$out" && ok "그 사실을 알린다" || fail "T8 — 조용히 넘어간다"
[[ -f "$U/scv/journal/INDEX.tsv" ]] && fail "T8 — 잘못된 표시가 색인에 들어갔다" || ok "색인에는 안 들어간다"
echo "OK [T8]"

echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
