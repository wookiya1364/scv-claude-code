#!/usr/bin/env bash
# test-pipe-arrange.sh — 엮음 고르기 명령(계획 20261112-wookiya1364-pipe-arrange)의 시험.
# 계산은 순수 함수의 값으로, 명령은 임시 폴더의 작은 입력으로 실제로 돌려 본다.
#
# Run: bash core/tests/test-pipe-arrange.sh
#
# 재는 명령을 실제로 돌린다 — 겹쳐 돌면 잰 시간이 틀어지므로 다른 시험이 다 끝난 뒤 혼자 돈다:
# scv-test: serial
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PA="$CORE/scripts/pipe-arrange.sh"
# shellcheck source=../scripts/lib/pure-bench.sh
source "$CORE/scripts/lib/pure-bench.sh"
# shellcheck source=../scripts/lib/pipe-arrange.sh
source "$CORE/scripts/lib/pipe-arrange.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "OK [$1]"; else fail "[$1] want [$2] got [$3]"; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export SCV_PB_GPU_TOOL=none      # GPU 를 읽지 않는다 — 시험이 빨라지고 컴퓨터마다 같다
T=$'\t'

echo "T1. 단계 글 읽기"
S4="up${T}map${T}tr a-z A-Z"$'\n'"keep${T}filter${T}grep 7${T}after:up"$'\n'"top${T}head${T}100"$'\n'"srt${T}collect${T}sort"
eq "T1 four steps, blank and # lines dropped" 4 "$(pa_parse_steps "# 머리"$'\n\n'"$S4"$'\n' | grep -c .)"
eq "T1 the after column: a name or -" "- up - -" "$(pa_parse_steps "$S4" | cut -f4 | tr '\n' ' ' | sed 's/ $//')"
pa_parse_steps "up${T}mop${T}cat" >"$TMP/e"; st=$?
eq "T1 a wrong kind → 1 and a reason" "1 오류: 2번째 칸은 map · filter · head · collect 가운데 하나여야 한다 — up" "$st $(cat "$TMP/e")"
pa_parse_steps "a${T}map${T}cat"$'\n'"a${T}filter${T}grep x" >"$TMP/e"; eq "T1 a repeated name → 1" "1 오류: 이름이 겹친다 — a" "$? $(cat "$TMP/e")"
pa_parse_steps "k${T}filter${T}grep x${T}after:z" >"$TMP/e"; eq "T1 after names a step that is not there → 1" "1" "$?"
pa_parse_steps "top${T}head${T}many" >"$TMP/e"; eq "T1 head without a number → 1" "1" "$?"

echo "T2. 순위 값과 순서 — 2026-11-11 에 잰 값"
M="up${T}map${T}A${T}-${T}0.134${T}1.00"$'\n'"tag${T}map${T}B${T}-${T}0.083${T}1.00"$'\n'"keep${T}filter${T}C${T}-${T}0.032${T}0.41"
eq "T2 rank: the filter is far below the maps" "0 0 -18437" "$(pa_rank 0.134 1.00) $(pa_rank 0.083 1.00) $(pa_rank 0.032 0.41)"
eq "T2 the order: filter first, maps keep their order" "keep up tag" "$(pa_order "$M" | tr '\n' ' ' | sed 's/ $//')"
eq "T2 expected time of the first order" "0.249" "$(pa_expected "$M" $'up\ntag\nkeep')"
eq "T2 expected time of the chosen order" "0.121" "$(pa_expected "$M" $'keep\nup\ntag')"
eq "T2 expected time of the one in between" "0.200" "$(pa_expected "$M" $'up\nkeep\ntag')"
eq "T2 how many orders there would be to try" "6 720 아주 많음" "$(pa_count_orders 3) $(pa_count_orders 6) $(pa_count_orders 25)"

echo "T3. 벽을 넘지 않는다"
W="up${T}map${T}A${T}-${T}0.1${T}1.00"$'\n'"k1${T}filter${T}B${T}-${T}0.05${T}0.5"$'\n'"top${T}head${T}10${T}-${T}0${T}0.1"$'\n'"k2${T}filter${T}C${T}-${T}0.01${T}0.1"
eq "T3 a filter after 'head' stays after it" "k1 up top k2" "$(pa_order "$W" | tr '\n' ' ' | sed 's/ $//')"
W2="up${T}map${T}A${T}-${T}0.1${T}1.00"$'\n'"srt${T}collect${T}sort${T}-${T}0.2${T}1.00"$'\n'"k${T}filter${T}C${T}-${T}0.01${T}0.1"
eq "T3 a filter after 'collect' stays after it" "up srt k" "$(pa_order "$W2" | tr '\n' ' ' | sed 's/ $//')"
eq "T3 'head' cuts the share that is still alive" "0.105" "$(pa_expected "up${T}map${T}A${T}-${T}0.100${T}1.00"$'\n'"top${T}head${T}10${T}-${T}0${T}0.10"$'\n'"k${T}filter${T}C${T}-${T}0.050${T}0.50" $'up\ntop\nk')"

echo "T4. 선언을 지킨다"
D="up${T}map${T}A${T}-${T}0.134${T}1.00"$'\n'"tag${T}map${T}B${T}-${T}0.083${T}1.00"$'\n'"dep${T}filter${T}C${T}tag${T}0.032${T}0.41"$'\n'"free${T}filter${T}E${T}-${T}0.020${T}0.50"
eq "T4 the declared filter waits for its map, the free one goes first" "free up tag dep" "$(pa_order "$D" | tr '\n' ' ' | sed 's/ $//')"
eq "T4 the mild order moves only filters that sit next to each other" "up tag free dep" "$(pa_order_mild "$D" | tr '\n' ' ' | sed 's/ $//')"

echo "T5. 실제 실행 — 더 빠른 순서를 고르고 답이 같다"
LC_ALL=C awk 'BEGIN { for (i = 1; i <= 20000; i++) printf "line %d abc\n", i }' > "$TMP/in.txt"
printf 'up\tmap\ttr a-z A-Z\ntag\tmap\tsed "s/^/item:/"\nkeep\tfilter\tgrep 7\n' > "$TMP/s3.tsv"
"$BASH" "$PA" --steps "$TMP/s3.tsv" --input "$TMP/in.txt" > "$TMP/t5.md"; st=$?
eq "T5 exit 0" 0 "$st"
grep -q '^입력 20000줄 · 단계 3개 · 실행 5번 (순서를 전부 돌려 보면 6가지)$' "$TMP/t5.md" && ok "OK [T5] five runs for three steps, said in the first line" || fail "[T5] $(sed -n 1p "$TMP/t5.md")"
grep -q '^| 고른 것 | keep → up → tag | .* | 같음 |$' "$TMP/t5.md" && ok "OK [T5] the filter is moved to the front and the answer is the same" || fail "[T5] $(grep '^| 고른 것\|^| 버림' "$TMP/t5.md")"
grep -q '^| 처음 | up → tag → keep | ' "$TMP/t5.md" && ok "OK [T5] the first order is shown beside it" || fail "[T5] no first row"
grep -q '^- 고르기 keep 을 바꾸기 앞으로 당김' "$TMP/t5.md" && grep -q '^- 이어진 바꾸기 2개(up · tag)' "$TMP/t5.md" && ok "OK [T5] what the rules saw is written under the table" || fail "[T5] hints: $(grep '^- ' "$TMP/t5.md")"
grep -q '예시 입력에서만 확인' "$TMP/t5.md" && ok "OK [T5] it says the answer was checked on this input only" || fail "[T5] no caveat"
printf 'up\tmap\ttr a-z A-Z\nkeep\tfilter\tgrep 7\ntop\thead\t5\n' > "$TMP/sh.tsv"
"$BASH" "$PA" --steps "$TMP/sh.tsv" --input "$TMP/in.txt" > "$TMP/t5h.md"
grep -q '^| 고른 것 | keep → up → top | .* | 같음 |$' "$TMP/t5h.md" && grep -q '^- 앞의 5줄만 쓴다' "$TMP/t5h.md" && ok "OK [T5] with 'head': the wall stays last, the filter still moves" || fail "[T5] $(grep '^| \|^- ' "$TMP/t5h.md" | tail -4)"

echo "T6. 실제 실행 — 답이 달라지는 순서는 내놓지 않는다"
# 고르기가 앞의 바꾸기 결과(붙인 글)에 기댄다 — 앞으로 당기면 한 줄도 통과하지 못한다
printf 'up\tmap\ttr a-z A-Z\ntag\tmap\tsed "s/^/item:/"\nhas\tfilter\tgrep "^item:.*7"\n' > "$TMP/dep.tsv"
"$BASH" "$PA" --steps "$TMP/dep.tsv" --input "$TMP/in.txt" > "$TMP/t6.md"; st=$?
eq "T6 exit 0 (it is a report, not a failure)" 0 "$st"
grep -q '^| 버림 | has → up → tag | .* | 다름 |$' "$TMP/t6.md" && ok "OK [T6] the order whose answer changed is marked dropped" || fail "[T6] $(grep '^| ' "$TMP/t6.md" | tail -2)"
! grep -q '^| 고른 것 |' "$TMP/t6.md" && grep -q '^바꿀 수 있는 순서를 찾지 못함' "$TMP/t6.md" && ok "OK [T6] nothing is offered, and it says how to declare the dependency" || fail "[T6] $(tail -4 "$TMP/t6.md")"
printf 'up\tmap\ttr a-z A-Z\ntag\tmap\tsed "s/^/item:/"\nhas\tfilter\tgrep "^item:.*7"\tafter:tag\n' > "$TMP/dep2.tsv"
"$BASH" "$PA" --steps "$TMP/dep2.tsv" --input "$TMP/in.txt" > "$TMP/t6b.md"
grep -q '실행 4번' "$TMP/t6b.md" && grep -q '^계산해 보니 처음 순서가 이미 가장 좋다$' "$TMP/t6b.md" && ok "OK [T6] with the dependency declared: the first order stands, one run fewer" || fail "[T6] $(sed -n 1p "$TMP/t6b.md") / $(tail -3 "$TMP/t6b.md" | head -1)"
# 덜 과감한 순서: 앞의 고르기 둘은 서로 바꿔도 되고, 끝의 고르기는 바꾸기에 기댄다
printf 'wide\tfilter\tgrep -v "^line 1 "\nnarrow\tfilter\tgrep 77\ntag\tmap\tsed "s/^/item:/"\nhas\tfilter\tgrep "^item:"\n' > "$TMP/mild.tsv"
"$BASH" "$PA" --steps "$TMP/mild.tsv" --input "$TMP/in.txt" > "$TMP/t6c.md"
grep -q '^| 고른 것 | narrow → wide → tag → has | .* | 같음 |$' "$TMP/t6c.md" && grep -q '^| 버림 | .* | 다름 |$' "$TMP/t6c.md" && grep -q '이어진 고르기끼리만 바꾼 순서를 골랐다' "$TMP/t6c.md" && ok "OK [T6] the bold order is dropped, the mild one (filters next to each other) is offered" || fail "[T6] $(grep '^| \|골랐다\|못함' "$TMP/t6c.md" | tail -4)"

echo "T7. 아무 파일도 고치지 않는다"
mkdir -p "$TMP/cwd"; s0="$(cksum < "$TMP/s3.tsv") $(cksum < "$TMP/in.txt")"
( cd "$TMP/cwd" && "$BASH" "$PA" --steps "$TMP/s3.tsv" --input "$TMP/in.txt" >/dev/null )
eq "T7 the steps file and the input are untouched" "$s0" "$(cksum < "$TMP/s3.tsv") $(cksum < "$TMP/in.txt")"
eq "T7 nothing is left in the working folder" 0 "$(ls -A "$TMP/cwd" | grep -c . || true)"

echo "T8. 쓰임새 오류"
"$BASH" "$PA" --steps "$TMP/none.tsv" --input "$TMP/in.txt" >/dev/null 2>"$TMP/e"; eq "T8 no steps file → 2 and why" "2 pipe-arrange: 단계 목록 파일이 없다: $TMP/none.tsv" "$? $(cat "$TMP/e")"
"$BASH" "$PA" --steps "$TMP/s3.tsv" >/dev/null 2>"$TMP/e"; eq "T8 no input → 2" 2 "$?"
printf 'up\tmap\ttr a-z A-Z\n' > "$TMP/one.tsv"
"$BASH" "$PA" --steps "$TMP/one.tsv" --input "$TMP/in.txt" >/dev/null 2>"$TMP/e"; eq "T8 one step only → 2 and why" "2 pipe-arrange: 단계가 둘 이상 있어야 순서를 견줄 수 있다 (지금 1개)" "$? $(cat "$TMP/e")"
printf 'up\tmop\ttr a-z A-Z\nk\tfilter\tgrep 7\n' > "$TMP/bad.tsv"
"$BASH" "$PA" --steps "$TMP/bad.tsv" --input "$TMP/in.txt" >/dev/null 2>"$TMP/e"; st=$?
[[ $st -eq 2 ]] && grep -q 'map · filter · head · collect' "$TMP/e" && ok "OK [T8] a wrong kind → 2, the reason names the four kinds" || fail "[T8] st=$st $(cat "$TMP/e")"
: > "$TMP/empty.txt"
"$BASH" "$PA" --steps "$TMP/s3.tsv" --input "$TMP/empty.txt" >/dev/null 2>"$TMP/e"; eq "T8 an empty input → 2" 2 "$?"

echo
echo "── $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
