#!/usr/bin/env bash
# test-record-index.sh — 저널 색인. 순수부 전수 + 실제 읽기.
#
# 계획: 20260823-wookiya1364-journal-index
# 계약: core/contracts/purity.md
#
# 판정은 전부 문자열 비교다.
#
# Run: bash core/tests/test-record-index.sh
set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$REPO_ROOT/scripts/lib/record-index.sh"
APPEND="$REPO_ROOT/scripts/journal-append.sh"
READ="$REPO_ROOT/scripts/record-read.sh"
CHECK="$REPO_ROOT/scripts/check-purity.sh"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi; }

for f in "$LIB" "$APPEND" "$READ"; do [[ -f "$f" ]] || { echo "✖ 없다: $f"; exit 1; }; done
# shellcheck source=../scripts/lib/record-index.sh
source "$LIB"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ============================================================ T1. 표시 정규화 전수
echo "T1. 표시 정규화 — 알려진 것만 통과"
T1_OK=0; T1_N=0
check_mark() { T1_N=$((T1_N+1)); [[ "$(record_kind_normalize "$1")" == "$2" ]] && T1_OK=$((T1_OK+1)) \
               || fail "T1 [$1] — expected [$2], got [$(record_kind_normalize "$1")]"; }
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
R="$(record_index_entry decision k f 100 250 t1 "요약")"
eq "정상 레코드"        "decision	k	f	100	250	t1	요약" "$(printf '%s' "$R")"
eq "알 수 없는 표시"    "" "$(record_index_entry bogus k f 1 2 t s)"
eq "오프셋이 숫자 아님" "" "$(record_index_entry decision k f abc 2 t s)"
eq "길이 0"             "" "$(record_index_entry decision k f 1 0 t s)"
eq "길이가 음수"        "" "$(record_index_entry decision k f 1 -5 t s)"
eq "키 없음"            "" "$(record_index_entry decision '' f 1 2 t s)"
eq "파일 없음"          "" "$(record_index_entry decision k '' 1 2 t s)"
# 탭·줄바꿈이 들어가면 형식이 깨진다 — 공백으로 바꾼다
NL="$(record_index_entry decision "a	b" f 1 2 t "x
y")"
[[ "$(printf '%s' "$NL" | wc -l | tr -d ' ')" == "0" ]] && ok "탭·줄바꿈이 섞여도 한 줄" \
  || fail "T2 — 레코드가 여러 줄이 됐다"
echo "OK [T2]"

# ============================================================ T3. 조회 — 최신이 이긴다
echo
echo "T3. 조회 — 같은 키는 최신이 이긴다"
IDX="$(printf 'decision\tk1\tf\t10\t20\tt1\t옛것\ndecision\tk2\tf\t30\t40\tt2\t다른것\nplan\tk1\tf\t50\t60\tt3\t최신\n')"
eq "k1 은 최신"     "plan	k1	f	50	60	t3	최신"      "$(record_index_lookup "$IDX" k1)"
eq "k2"             "decision	k2	f	30	40	t2	다른것"  "$(record_index_lookup "$IDX" k2)"
eq "없는 키"        "" "$(record_index_lookup "$IDX" nope)"
eq "빈 색인"        "" "$(record_index_lookup "" k1)"
eq "빈 키"          "" "$(record_index_lookup "$IDX" "")"
# 반복 가능성 — 이것이 깨지면 나머지가 전부 의미를 잃는다
R1="$(record_index_lookup "$IDX" k1)"; SAME=1
for _ in $(seq 1 50); do [[ "$(record_index_lookup "$IDX" k1)" == "$R1" ]] || SAME=0; done
eq "같은 입력 50회 → 같은 출력" "1" "$SAME"
echo "OK [T3]"

# ============================================================ T4. 걸러내기
echo
echo "T4. 표시로 거르기 — 옛 레코드는 빠진다"
N_ALL="$(record_index_filter "$IDX" "" | grep -c . || true)"
eq "전부 (k1 은 최신 하나만)" "2" "$N_ALL"
N_PLAN="$(record_index_filter "$IDX" plan | grep -c . || true)"
eq "plan 만" "1" "$N_PLAN"
N_NONE="$(record_index_filter "$IDX" blocker | grep -c . || true)"
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
IDXF="$P/scv/INDEX.tsv"
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
printf 'garbage without tabs\n' > "$E/scv/INDEX.tsv"
rc="$( cd "$E" && SCV_JOURNAL_DIR="$E/scv/journal" bash "$READ" --key x >/dev/null 2>&1; echo $? )"
eq "깨진 색인 → exit 0" "0" "$rc"
# 알 수 없는 표시로 기록해도 저널 자체는 써진다
U="$WORK/unknown"; mkdir -p "$U/scv/journal"
out="$( cd "$U" && SCV_JOURNAL_DIR="$U/scv/journal" bash "$APPEND" --mark bogus --speaker user "내용" 2>&1 )"
grep -q "JOURNAL_FILE:" <<<"$out" && ok "알 수 없는 표시여도 저널 기록은 된다" || fail "T8 — 기록이 막혔다"
grep -q "unknown journal mark" <<<"$out" && ok "그 사실을 알린다" || fail "T8 — 조용히 넘어간다"
[[ -f "$U/scv/INDEX.tsv" ]] && fail "T8 — 잘못된 표시가 색인에 들어갔다" || ok "색인에는 안 들어간다"
echo "OK [T8]"

# ============================================================ T9. 결정이 스스로 색인된다
echo
echo "T9. 결정은 세 지점에서 자동으로 쌓이고 스스로 색인된다"
DEC="$REPO_ROOT/scripts/decisions-append.sh"
RCP="$REPO_ROOT/scripts/recap.sh"
D="$WORK/dec"; mkdir -p "$D"
( cd "$D" && bash "$REPO_ROOT/scripts/hydrate.sh" init . >/dev/null 2>&1 )
OUT="$( cd "$D" && bash "$DEC" --title "설정을 두 파일로" --verdict adopted --why "섞여서 오해가 잦았다" 2>&1 )"
grep -q '^DECISION:' <<<"$OUT" && ok "결정이 쌓인다" || fail "T9 — 결정이 안 쌓인다"
grep -q '^INDEXED:'  <<<"$OUT" && ok "쌓으면서 **자동으로** 색인된다 (판단 없음)" || fail "T9 — 색인이 안 된다"
[[ -f "$D/scv/INDEX.tsv" ]] && ok "색인이 scv/INDEX.tsv 한 곳에" || fail "T9 — 색인 자리가 다르다"

# 잘못된 판정은 거부한다 — 형식이 흔들리면 로그를 나중에 못 읽는다
( cd "$D" && bash "$DEC" --title x --verdict bogus --why y >/dev/null 2>&1 ) \
  && fail "T9 — 알 수 없는 verdict 를 받았다" || ok "알 수 없는 verdict 는 거부한다"
( cd "$D" && bash "$DEC" --title x --verdict adopted >/dev/null 2>&1 ) \
  && fail "T9 — why 없이 받았다" || ok "근거(why) 없이는 안 받는다"

# 668줄을 안 읽고 하나만 꺼낸다
KEY="$( cd "$D" && cut -f2 scv/INDEX.tsv | head -1 )"
BODY="$( cd "$D" && SCV_DIR=scv bash "$READ" --key "$KEY" 2>/dev/null )"
grep -q "설정을 두 파일로" <<<"$BODY" && ok "이름으로 그 결정만 읽는다" || fail "T9 — 결정을 못 읽는다"
DB="$( cd "$D" && wc -c < scv/DECISIONS.md | tr -d ' ' )"
BB="$( printf '%s' "$BODY" | wc -c | tr -d ' ' )"
if (( BB < DB / 2 )); then ok "읽은 양 ${BB}B < 결정 로그 ${DB}B 의 절반"
else fail "T9 — 읽은 양이 로그에 비해 크다 (${BB}B / ${DB}B)"; fi
echo "OK [T9]"

# ============================================================ T10. recap
echo
echo "T10. recap 은 아무것도 새로 쓰지 않고 조립한다"
BEFORE="$( cd "$D" && find scv -type f | LC_ALL=C sort | md5 2>/dev/null || find scv -type f | LC_ALL=C sort | md5sum )"
R="$( cd "$D" && SCV_DIR=scv bash "$RCP" 2>&1 )"
AFTER="$( cd "$D" && find scv -type f | LC_ALL=C sort | md5 2>/dev/null || find scv -type f | LC_ALL=C sort | md5sum )"
eq "파일을 하나도 만들거나 지우지 않는다" "$BEFORE" "$AFTER"
grep -q '설정을 두 파일로' <<<"$R" && ok "최근 결정이 보인다" || fail "T10 — 결정이 안 보인다"
grep -q 'record-read.sh --key' <<<"$R" && ok "펼치는 방법을 알려 준다" || fail "T10 — 펼치는 법이 없다"
RL="$( printf '%s' "$R" | wc -l | tr -d ' ' )"
if (( RL <= 40 )); then ok "짧다 (${RL}줄) — 비운 직후에 읽을 만하다"
else fail "T10 — ${RL}줄로 길다. 짧지 않으면 안 읽는다"; fi
echo "OK [T10]"

echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
