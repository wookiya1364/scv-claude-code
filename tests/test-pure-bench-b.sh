#!/usr/bin/env bash
# test-pure-bench-b.sh — 재는 명령(계획 20261111-wookiya1364-pure-bench-and-gate)의 시험, 넷 가운데 앞뒤를 번갈아 재기 · 기준 목록 · 끊기(S15 · S16 · S19 · S20).
# 한 파일이던 것을 넷으로 나눴다(계획 20261112-wookiya1364-small-fixes-bundle) — 조각 실행기가 넷을 서로 다른
# 러너에 나눠 함께 돌릴 수 있게. 구간 번호(S1 ~ S23)는 나누기 전 그대로다.
#
# Run: bash core/tests/test-pure-bench-b.sh   (넷 모두: bash core/tests/test-pure-bench.sh)
#
# 시간을 재는 시험이라 다른 시험과 겹쳐 돌면 값이 틀어진다 — 다른 시험이 다 끝난 뒤 혼자 돈다:
# scv-test: serial
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PB="$CORE/scripts/pure-bench.sh"
# shellcheck source=fixtures/pure-bench/common.sh
source "$CORE/tests/fixtures/pure-bench/common.sh"

pbt_base; pbt_base_composed   # 나누기 전에는 S6 · S13 이 만들어 둔 바탕

echo "S15. 앞뒤를 번갈아 재기 — 실제 실행 (TESTS T10 · T11 · T13)"
A="$TMP/after"; mkdir -p "$A/lib"; cp "$B/lib/t.sh" "$A/lib/t.sh"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" compare --before "$B" --base "$A" --catalog "$B/cat" --only t_once --only t_up --only t_rev --only t_both --only t_each --pairs 6 > "$TMP/same.md"; st=$?
eq "S15 the same code before and after: exit 0" 0 "$st"
eq "S15 all five pass" 5 "$(grep -c '^| t_[a-z]* | 통과 |' "$TMP/same.md")"
# 답은 같고 느리기만 한 판: 한 번 부르던 것을 줄마다 부른다
cat >> "$A/lib/t.sh" <<'LIB'
t_once() { local l; while IFS= read -r l; do printf '%s\n' "$l" | tr 'a-z' 'A-Z'; done <<< "$1"; }
t_up()   { printf '%s\n' "$1" | tr 'a-z' 'A-Z' | tr 'A-Z' 'a-z'; }
t_new()  { printf '%s\n' "$1"; }
LIB
printf '\n### t_new\n- 역할: 그대로 낸다\n- 위치: lib/t.sh · @pure · sh\n- 예: `$\x27a\\nb\x27 → $\x27a\\nb\x27`\n' >> "$B/cat/a.md"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" compare --before "$B" --base "$A" --catalog "$B/cat" --only t_once --only t_up --only t_rev --only t_new --pending "$TMP/pending" > "$TMP/slow.md"; st=$?
eq "S15 a slower version: exit 1" 1 "$st"
grep -q '^| t_once | 한도 넘음 |.*| 1 → 50 |' "$TMP/slow.md" && ok "OK [S15] the slowed function is named with its calls 1 → 50" || fail "[S15] $(grep '^| t_once' "$TMP/slow.md")"
grep -q '^t_once — 시간 [0-9.]*배 · 다른 프로그램을 부른 횟수 1번 → 50번' "$TMP/slow.md" && ok "OK [S15] and said in plain words with the real numbers" || fail "[S15] $(grep '^t_once —' "$TMP/slow.md")"
grep -q '^| t_up | 답이 달라 뺌 |' "$TMP/slow.md" && ok "OK [S15] a function whose answer changed is left out, not failed" || fail "[S15] $(grep '^| t_up' "$TMP/slow.md")"
grep -q '^| t_rev | 통과 |' "$TMP/slow.md" && ok "OK [S15] an untouched function passes" || fail "[S15] $(grep '^| t_rev' "$TMP/slow.md")"
grep -q '^| t_new | 새 함수 |' "$TMP/slow.md" && ok "OK [S15] a function with no 'before' is only recorded" || fail "[S15] $(grep '^| t_new' "$TMP/slow.md")"
eq "S15 what went over is written for the choice step" "t_once" "$(cut -f1 "$TMP/pending")"
cp "$TMP/pending" "$TMP/accepted"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" compare --before "$B" --base "$A" --catalog "$B/cat" --only t_once --accepted "$TMP/accepted" > "$TMP/acc.md"; st=$?
eq "S15 after the user accepted it: exit 0" 0 "$st"
grep -q '^| t_once | 받아들임 |' "$TMP/acc.md" && ok "OK [S15] and the row says accepted" || fail "[S15] $(grep '^| t_once' "$TMP/acc.md")"
printf 't_once\ttime=1.30\n' > "$TMP/accepted-small"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" compare --before "$B" --base "$A" --catalog "$B/cat" --only t_once --accepted "$TMP/accepted-small" >/dev/null; eq "S15 worse than what was accepted: exit 1 again" 1 "$?"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" compare --before "$B" --base "$A" --catalog "$B/cat" --only t_rev --only t_both --only t_each --budget 1 > "$TMP/budget.md"
[[ "$(grep -c '| 재지 못함 |' "$TMP/budget.md")" -ge 1 ]] && grep -q '재지 못함 [1-9]' "$TMP/budget.md" && ok "OK [S15] out of time: the rest is counted as not measured" || fail "[S15] $(tail -1 "$TMP/budget.md")"
"$BASH" "$PB" compare --catalog "$B/cat" >/dev/null 2>&1; eq "S15 no 'before' given → usage error" 2 "$?"
if git -C "$CORE" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -d "$CORE/../scv/core/catalog/pure" ]] && git -C "$CORE" cat-file -e HEAD:core/scripts/lib/turn-check.sh 2>/dev/null; then
  SCV_PB_GPU_TOOL=none "$BASH" "$PB" compare --before-ref HEAD --only scv_tc_overlap_count > "$TMP/ref.md"; st=$?
  [[ "$(grep -c '^| scv_tc_overlap_count | ' "$TMP/ref.md")" == 1 && $st -le 1 ]] && ok "OK [S15] the code of a commit can be the 'before' ($(grep '^| scv_tc_overlap_count' "$TMP/ref.md" | cut -d'|' -f3 | tr -d ' '))" || fail "[S15] st=$st $(tail -2 "$TMP/ref.md")"
fi

echo "S16. 무엇을 견줄지 · 멈출 때의 글 — 순수 함수"
eq "S16 changed or new bodies" $'g\nh' "$(pb_changed_names $'@@ f\n a\n@@ g\n b' $'@@ f\n a\n@@ g\n c\n@@ h\n d')"
eq "S16 nothing changed" "" "$(pb_changed_names $'@@ f\n a' $'@@ f\n a')"
eq "S16 composed functions that call a changed one" "f" "$(pb_callers $'f\tg h\nk\tx y' $'h\nz')"
eq "S16 accepted: the asked function, answer starts with 이대로" $'f\ttime=1.35' "$(pb_accept_pick $'f\ttime=1.35\ng\tcalls=1:2' "[재는 검사] f — 시간 1.35배. 어떻게 할까요?" "이대로 둠")"
eq "S16 not accepted: the user chose to fix" "" "$(pb_accept_pick $'f\ttime=1.35' "[재는 검사] f — 시간 1.35배" "고침 (추천)")"
eq "S16 not accepted: some other question" "" "$(pb_accept_pick $'f\ttime=1.35' "다른 질문 f" "이대로 둠")"
eq "S16 not accepted: a longer name is not this name" "" "$(pb_accept_pick $'f\ttime=1.35' "[재는 검사] ff — 시간 1.35배" "이대로 둠")"
bt="$(pb_block_text $'f — 시간 1.25배\ng — 메모리 1.9MB → 37.0MB')"
[[ "$bt" == *"f — 시간 1.25배 / g — 메모리 1.9MB → 37.0MB"* && "$bt" == *"[재는 검사] 함수 이름 —"* && "$bt" == *"이대로 둠"* && "$bt" != *$'\n'* ]] && ok "OK [S16] the stop text carries the real numbers and how to ask, on one line" || fail "[S16] $bt"

echo "S19. 기준 목록 — 늘면 실패, 줄면 내림 (TESTS T12)"
BL="$TMP/scale-baseline"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" bench --catalog "$B/cat" --base "$B" --only t_once --only t_rev --baseline "$BL" >/dev/null; st=$?
eq "S19 the first run makes the list (nothing over 8 here)" "0 0" "$st $(grep -c . "$BL")"
printf 't_once\nt_gone_now\n' > "$BL"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" bench --catalog "$B/cat" --base "$B" --only t_once --only t_rev --baseline "$BL" >/dev/null; st=$?
eq "S19 names that are no longer over the limit leave the list" "0 0" "$st $(grep -c . "$BL")"
eq "S19 a new name is told and not added" $'a\n@@new c' "$(pb_baseline_next $'a\nb' $'a\nc')"

echo "S20. 너무 오래 걸리는 함수 — 끊고 그렇게 적는다"
cat >> "$B/lib/t.sh" <<'LIB'
t_long() { local n; n="$(printf '%s\n' "$1" | grep -c .)"; if [[ $n -gt 60 ]]; then sleep 30; fi; printf '%s' "$n"; }
LIB
printf '\n### t_long\n- 역할: 줄이 많으면 오래 걸린다\n- 위치: lib/t.sh · @deterministic · sh\n- 예: `$\x27a\\nb\x27 → "2"`\n' >> "$B/cat/a.md"
t0=$SECONDS
SCV_PB_CALL_LIMIT=3 SCV_PB_GPU_TOOL=none "$BASH" "$PB" bench --catalog "$B/cat" --base "$B" --only t_long --tsv "$TMP/long.tsv" --baseline "$TMP/long.base" > "$TMP/long.md"
el=$(( SECONDS - t0 ))
[[ $el -lt 25 ]] && ok "OK [S20] one slow function does not hold the whole run (${el}s, not 30+)" || fail "[S20] took ${el}s"
eq "S20 the row says it was cut at 4x" "too-slow" "$(cut -f9 "$TMP/long.tsv")"
grep -q '4배 입력에서 너무 오래 걸려 끊음 · 배수 한도(8배) 넘음' "$TMP/long.md" && ok "OK [S20] and it counts as over the limit, in plain words" || fail "[S20] $(grep '^| t_long' "$TMP/long.md")"
eq "S20 it is on the list of functions that are dangerous with bigger input" "t_long" "$(cat "$TMP/long.base")"
[[ -z "$(ps -Ao command | grep -v grep | grep 'sleep 30' | head -1)" ]] || echo "  - note [S20] 끊긴 함수가 띄운 기다림이 잠깐 남아 있음(30초 뒤 사라짐)"

pbt_finish
