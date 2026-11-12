#!/usr/bin/env bash
# test-pure-bench-d.sh — 재는 명령(계획 20261111-wookiya1364-pure-bench-and-gate)의 시험, 넷 가운데 끊긴 값 · 일찍 멈춤 · 4배 먼저(S21 ~ S23).
# 한 파일이던 것을 넷으로 나눴다(계획 20261112-wookiya1364-small-fixes-bundle) — 조각 실행기가 넷을 서로 다른
# 러너에 나눠 함께 돌릴 수 있게. 구간 번호(S1 ~ S23)는 나누기 전 그대로다.
#
# Run: bash core/tests/test-pure-bench-d.sh   (넷 모두: bash core/tests/test-pure-bench.sh)
#
# 시간을 재는 시험이라 다른 시험과 겹쳐 돌면 값이 틀어진다 — 다른 시험이 다 끝난 뒤 혼자 돈다:
# scv-test: serial
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PB="$CORE/scripts/pure-bench.sh"
# shellcheck source=fixtures/pure-bench/common.sh
source "$CORE/tests/fixtures/pure-bench/common.sh"

echo "S21. 끊긴 값의 판정 · 표 · 멈춘 글 — 순수 함수 (계획 20261112-wookiya1364-bench-gate-gaps T3 · T4)"
eq "S21 before cut at 4x, after finished over 8 → pass (it was over already)" $'pass\t-' "$(v $'f\tok\tcpu\t3.000\t3.000\t0\t0\t2.4\t2.5\ttoo-slow\t9.1')"
eq "S21 after cut at 4x, before finished → fail"                               $'fail\tscale=4.0:too-slow' "$(v $'f\tok\tcpu\t3.000\t3.000\t0\t0\t2.4\t2.5\t4.0\ttoo-slow')"
eq "S21 both cut at 4x → not judged"                                           $'pass\t-' "$(v $'f\tok\tcpu\t3.000\t3.000\t0\t0\t2.4\t2.5\ttoo-slow\ttoo-slow')"
eq "S21 before cut at 1x, after measured → pass, no memory verdict"            $'pass\t-' "$(v $'f\tok\tcpu\ttoo-slow\t3.000\t0\t0\t-\t2.5\ttoo-slow\t9.1')"
eq "S21 before cut at 1x but one more program called → still fail"             $'fail\tcalls=0:1' "$(v $'f\tok\tcpu\ttoo-slow\t3.000\t0\t1\t-\t2.5\t-\t-')"
tbl="$(pb_render_compare $'f\tok\tcpu\ttoo-slow\t3.000\t0\t0\t-\t2.5\ttoo-slow\t9.1' $'f\tpass\t-')"
[[ "$tbl" == *"| f | 통과 | 끊김 | 3.000 | - |"*"| 끊김 → 9.1 |"* && "$tbl" != *too-slow* ]] && ok "OK [S21] the table says 끊김, not a blank and not the raw word" || fail "[S21] $tbl"
eq "S21 the line a person reads" "f — 입력 4배에 걸리는 시간 4.0배 → 끊김" "$(pb_fail_lines $'f\tfail\tscale=4.0:too-slow')"
pb_accept_covers "scale=4.0:too-slow" "scale=4.0:too-slow"; eq "S21 accepted 'cut', cut again → covered" 0 "$?"
pb_accept_covers "scale=4.0:9.1" "scale=4.0:too-slow"; eq "S21 accepted a number, now cut → asked again" 1 "$?"
eq "S21 pairs: two in a row at half or less → enough" "1 0 0 1 0" "$(pb_pairs_enough "100.0 98.0" "10.0 12.0") $(pb_pairs_enough "100.0 98.0" "10.0 60.0") $(pb_pairs_enough "100.0" "10.0") $(pb_pairs_enough "30.0 100.0 98.0" "29.0 10.0 12.0") $(pb_pairs_enough "100.0 -" "10.0 12.0")"
eq "S21 pairs: slower or about the same → never enough" "0 0" "$(pb_pairs_enough "10.0 10.0 10.0" "30.0 31.0 29.0") $(pb_pairs_enough "10.0 10.0" "10.1 9.9")"
eq "S21 4x ratio over the limit, or cut" "1 0 1 0" "$(pb_scale_over 9.1) $(pb_scale_over 8.0) $(pb_scale_over too-slow) $(pb_scale_over -)"

echo "S22. 뚜렷하면 일찍 멈추고, 아니면 다 잰다 — 실제 실행 (같은 계획 T5)"
B2="$TMP/b2"; A2="$TMP/a2"; mkdir -p "$B2/lib" "$B2/cat" "$A2/lib"
cat > "$B2/lib/u.sh" <<'LIB'
u_fast() { local i x=0; for (( i = 0; i != 4000; i++ )); do x=$((x + i)); done; printf '%s' "$1"; }
u_same() { local i x=0; for (( i = 0; i != 400; i++ )); do x=$((x + i)); done; printf '%s' "$1"; }
u_slow() { printf '%s' "$1"; }
LIB
cat > "$A2/lib/u.sh" <<'LIB'
u_fast() { printf '%s' "$1"; }
u_same() { local i x=0; for (( i = 0; i != 400; i++ )); do x=$((x + i)); done; printf '%s' "$1"; }
u_slow() { local i x=0; for (( i = 0; i != 4000; i++ )); do x=$((x + i)); done; printf '%s' "$1"; }
LIB
printf '# 시험\n\n### u_fast\n- 역할: 빨라진다\n- 위치: lib/u.sh · @pure · sh\n- 예: `"1.2.3" → "1.2.3"`\n\n### u_same\n- 역할: 그대로다\n- 위치: lib/u.sh · @pure · sh\n- 예: `"1.2.3" → "1.2.3"`\n\n### u_slow\n- 역할: 느려진다\n- 위치: lib/u.sh · @pure · sh\n- 예: `"1.2.3" → "1.2.3"`\n' > "$B2/cat/a.md"
: > "$TMP/pairs.log"
SCV_PB_PAIRS_LOG="$TMP/pairs.log" SCV_PB_GPU_TOOL=none "$BASH" "$PB" compare --before "$B2" --base "$A2" --catalog "$B2/cat" --only u_fast --only u_same --only u_slow --full > "$TMP/early.md"; st=$?
eq "S22 a slower function is still caught: exit 1" 1 "$st"
eq "S22 clearly faster → 2 pairs, the same and the slower → all 6" "u_fast=2 u_same=6 u_slow=6" "$(sort "$TMP/pairs.log" | awk -F'\t' '{ printf "%s%s=%s", (NR > 1 ? " " : ""), $1, $2 }')"
grep -q '^| u_fast | 통과 |' "$TMP/early.md" && grep -q '^| u_same | 통과 |' "$TMP/early.md" && grep -q '^| u_slow | 한도 넘음 |' "$TMP/early.md" && ok "OK [S22] verdicts: faster passes, same passes, slower is over the limit" || fail "[S22] $(grep '^| u_' "$TMP/early.md")"
: > "$TMP/pairs.log"
SCV_PB_PAIRS_LOG="$TMP/pairs.log" SCV_PB_GPU_TOOL=none "$BASH" "$PB" compare --before "$B2" --base "$A2" --catalog "$B2/cat" --only u_fast --pairs 3 >/dev/null
eq "S22 the quick check is left as it was: all 3 pairs" "u_fast=3" "$(awk -F'\t' '{ printf "%s=%s", $1, $2 }' "$TMP/pairs.log")"

echo "S23. 4배 입력은 뒤를 먼저 재고, 한도 안이면 앞은 재지 않는다 (같은 계획 T6)"
cat >> "$B2/lib/u.sh" <<'LIB'
w_lin()  { local l n=0; while IFS= read -r l; do n=$((n + 1)); done <<< "$1"; printf '%s' "$n"; }
w_quad() { local l n=0; while IFS= read -r l; do n=$((n + 1)); done <<< "$1"; printf '%s' "$n"; }
LIB
cat >> "$A2/lib/u.sh" <<'LIB'
w_lin()  { local l n=0; while IFS= read -r l; do n=$((n + 1)); done <<< "$1"; printf '%s' "$n"; }
w_quad() { local l m n=0; while IFS= read -r l; do while IFS= read -r m; do :; done <<< "$1"; n=$((n + 1)); done <<< "$1"; printf '%s' "$n"; }
LIB
printf '\n### w_lin\n- 역할: 줄을 센다\n- 위치: lib/u.sh · @pure · sh\n- 예: `$\x27a\\nb\x27 → "2"`\n\n### w_quad\n- 역할: 줄을 센다(뒤 코드는 제곱으로 돈다)\n- 위치: lib/u.sh · @pure · sh\n- 예: `$\x27a\\nb\x27 → "2"`\n' >> "$B2/cat/a.md"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" compare --before "$B2" --base "$A2" --catalog "$B2/cat" --only w_lin --only w_quad --full > "$TMP/scale.md"; st=$?
eq "S23 the function that became quadratic is caught: exit 1" 1 "$st"
lin="$(grep '^| w_lin | ' "$TMP/scale.md")"; quad="$(grep '^| w_quad | ' "$TMP/scale.md")"
[[ "$lin" == "| w_lin | 통과 |"*"| - → "[0-9]*" |" ]] && ok "OK [S23] within the limit: the 'before' 4x value is not measured (${lin##*| - → })" || fail "[S23] $lin"
[[ "$quad" == "| w_quad | 한도 넘음 |"* && "$quad" =~ \|\ [0-9.]+\ →\ [0-9.]+\ \|$ ]] && ok "OK [S23] over the limit: both sides are measured (${quad##*| MB*|})" || fail "[S23] $quad"

pbt_finish
