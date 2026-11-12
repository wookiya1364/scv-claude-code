#!/usr/bin/env bash
# test-pure-bench.sh — 재는 명령(계획 20261111-wookiya1364-pure-bench-and-gate)의 시험.
# 순수 함수는 값으로, 실행기는 임시 폴더의 작은 함수로 본다.
#
# Run: bash core/tests/test-pure-bench.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PB="$CORE/scripts/pure-bench.sh"
# shellcheck source=../scripts/lib/pure-catalog.sh
source "$CORE/scripts/lib/pure-catalog.sh"
# shellcheck source=../scripts/lib/pure-bench.sh
source "$CORE/scripts/lib/pure-bench.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "OK [$1]"; else fail "[$1] want [$2] got [$3]"; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "S1. 인자 늘리기 — 줄 · 낱말 · 늘릴 수 없음"
eq "S1 lines"            "\$'a\\nb\\na\\nb' \"x y\""  "$(pb_scale_args "\$'a\\nb' \"x y\"" 2)"
eq "S1 words"            '"x y x y" k'                 "$(pb_scale_args '"x y" k' 2)"
eq "S1 here-string"      "<<< \$'p\\nq\\np\\nq\\np\\nq'" "$(pb_scale_args "<<< \$'p\\nq'" 3)"
eq "S1 trailing newline" "\$'a\\nb\\na\\nb\\n'"        "$(pb_scale_args "\$'a\\nb\\n'" 2)"
pb_scale_args '"1.2.3" k' 2 >"$TMP/o"; st=$?
eq "S1 unscalable keeps the text" '"1.2.3" k' "$(cat "$TMP/o")"; eq "S1 unscalable returns 1" 1 "$st"
eq "S1 a quote inside a value" "\"it\\\"s ok it\\\"s ok\"" "$(pb_scale_args "\"it\\\"s ok\"" 2)"
# 늘린 글은 셸이 다시 읽을 수 있어야 한다 — 줄 수가 정확히 N배
eval "set -- $(pb_scale_args "\$'a\\tb\\nc'" 25)"; eq "S1 25 times = 50 lines" 50 "$(printf '%s\n' "$1" | grep -c .)"

echo "S2. 잴 목록 — 사전 글에서"
CAT=$'# 세기\n\n### f_lines\n- 역할: 센다\n- 위치: scripts/lib/a.sh · @pure · sh\n- 예: `$\'a\\nb\' → "2"`\n- 예: `"" → "0"`\n\n### f_fixed\n- 역할: 견준다\n- 위치: scripts/lib/b.sh · @deterministic · sh\n- 예: `1.2.3 1.2.4 → ""`\n\n### f_noexample\n- 역할: 없다\n- 위치: scripts/lib/c.sh · @pure · sh\n\n### g_ts\n- 역할: 다른 언어\n- 위치: src/x.ts · @pure · ts\n- 예: `"a b" → "2"`'
T="$(pb_targets "$CAT" "")"
eq "S2 three functions with an example" 3 "$(grep -c . <<<"$T")"
IFS=$'\t' read -r n f l a1 a4 sc <<<"$(sed -n 1p <<<"$T")"
eq "S2 name · file · lang" "f_lines scripts/lib/a.sh sh" "$n $f $l"
eval "set -- $a1"; c1="$(printf '%s\n' "$1" | grep -c .)"; eval "set -- $a4"; c4="$(printf '%s\n' "$1" | grep -c .)"
eq "S2 1x = 50 lines, 4x = 200 lines, scalable" "50 200 1" "$c1 $c4 $sc"
eq "S2 only the first example is used" 1 "$(grep -c '^f_lines' <<<"$T")"
eq "S2 a fixed-size example is marked 0" "f_fixed 0" "$(awk -F'\t' '$1 == "f_fixed" { print $1, $6 }' <<<"$T")"
eq "S2 other languages keep their lang" "ts" "$(awk -F'\t' '$1 == "g_ts" { print $3 }' <<<"$T")"
eq "S2 --only filter" "f_fixed" "$(pb_targets "$CAT" $'f_fixed\nnope' | cut -f1)"

echo "S3. 명령 — 이 저장소의 사전으로"
if [[ -d "$CORE/../scv/core/catalog/pure" ]]; then
  "$BASH" "$PB" targets > "$TMP/all.tsv"; st=$?
  want="$(grep -h -A8 '^### ' "$CORE"/../scv/core/catalog/pure/[a-z]*.md | grep -c '^### ')"
  have="$(grep -c . "$TMP/all.tsv")"
  [[ $st == 0 && "$have" -gt 100 && "$have" -le "$want" ]] && ok "OK [S3] $have of $want functions listed" || fail "[S3] st=$st have=$have want=$want"
  eq "S3 six columns on every line" 0 "$(awk -F'\t' 'NF != 6' "$TMP/all.tsv" | grep -c .)"
  eq "S3 --only" "scv_tc_words" "$("$BASH" "$PB" targets --only scv_tc_words | cut -f1)"
else
  echo "  - SKIP [S3] 이 저장소에 사전이 없음"
fi
"$BASH" "$PB" targets --catalog "$TMP/none" >/dev/null 2>&1; eq "S3 missing catalog → usage error" 2 "$?"

echo "S4. 잰 글을 값으로 — 순수 함수"
eq "S4 time, BSD form"  $'1.50\t0.50\t2.5' "$(pb_parse_time $'real 1.50\nuser 0.40\nsys 0.10\n  2621440  maximum resident set size')"
eq "S4 time, GNU form"  $'61.50\t0.50\t2.5' "$(pb_parse_time $'\tUser time (seconds): 0.40\n\tSystem time (seconds): 0.10\n\tElapsed (wall clock) time (h:mm:ss or m:ss): 1:01.50\n\tMaximum resident set size (kbytes): 2560')"
eq "S4 time, no memory → -" $'0.30\t0.00\t-' "$(pb_parse_time $'real 0.30\nuser 0.00\nsys 0.00')"
eq "S4 time, nothing → all -" $'-\t-\t-' "$(pb_parse_time '')"
eq "S4 times → seconds" "1.530" "$(pb_times_secs $'0m0.010s 0m0.020s\n0m1.000s 0m0.500s')"
eq "S4 reps grow to reach 0.3 s" "150" "$(pb_reps_next 0.010 5)"
eq "S4 reps stay when long enough" "5" "$(pb_reps_next 0.250 5)"
eq "S4 reps are capped" "2000" "$(pb_reps_next 0.000 5)"
eq "S4 ioreg" $'42\t100.0' "$(pb_parse_ioreg '"PerformanceStatistics" = {"In use system memory"=104857600,"Device Utilization %"=42}')"
eq "S4 ioreg, no device" "" "$(pb_parse_ioreg 'no gpu here')"
eq "S4 nvidia, two devices" $'90\t300.0' "$(pb_parse_nvidia $'10, 100\n90, 200')"
eq "S4 gpu summary: average · memory added · rise over the start" $'50\t300.0\t40' "$(pb_gpu_summary $'40\t1100.0\n60\t1300.0' 1000.0 10)"
eq "S4 gpu summary: nothing rose" $'10\t0.0\t0' "$(pb_gpu_summary $'10\t1000.0' 1000.0 15)"
eq "S4 gpu summary, no samples" $'-\t-\t-' "$(pb_gpu_summary '' 1000.0 0)"

echo "S5. 명령 하나 재기 (TESTS T4 — GPU 를 읽을 도구가 없을 때)"
IFS=$'\t' read -r wall cpu rss gu gm ex nm rc <<<"$(SCV_PB_GPU_TOOL=none "$BASH" "$PB" run -- sleep 0.3)"
awk -v w="$wall" 'BEGIN { exit !(w >= 0.25 && w < 3) }' && ok "OK [S5] wall of sleep 0.3 = $wall s" || fail "[S5] wall=$wall"
eq "S5 no GPU tool → not measured, never a number" "- -" "$gu $gm"
eq "S5 sleep is one program" 1 "$ex"
eq "S5 --no-count leaves the count out" "-" "$(SCV_PB_GPU_TOOL=none "$BASH" "$PB" run --no-count -- true | cut -f6)"
"$BASH" "$PB" run >/dev/null 2>&1; eq "S5 run without a command → usage error" 2 "$?"
[[ -z "$(ls -d "${TMPDIR:-/tmp}"/scv-pure-bench.* 2>/dev/null)" ]] && ok "OK [S5] nothing left behind in the temp folder" || fail "[S5] leftover: $(ls -d "${TMPDIR:-/tmp}"/scv-pure-bench.* | head -2)"

echo "S6. 함수 재기 — 부른 횟수와 입력 4배 (TESTS T5)"
B="$TMP/base"; mkdir -p "$B/lib" "$B/cat"
cat > "$B/lib/t.sh" <<'LIB'
t_each() { local l; while IFS= read -r l; do printf '%s\n' "$l" | tr 'a-z' 'A-Z'; done <<< "$1"; }
t_once() { printf '%s\n' "$1" | tr 'a-z' 'A-Z'; }
LIB
printf '### t_each\n- 위치: lib/t.sh · @pure · sh\n- 예: `$\x27a\\nb\x27 → $\x27A\\nB\x27`\n\n### t_once\n- 위치: lib/t.sh · @pure · sh\n- 예: `$\x27a\\nb\x27 → $\x27A\\nB\x27`\n\n### t_gone\n- 위치: lib/t.sh · @pure · sh\n- 예: `"a b" → "x"`\n\n### t_fixed\n- 위치: lib/t.sh · @pure · sh\n- 예: `7 → "7"`\n\n### t_ts\n- 위치: src/x.ts · @pure · ts\n- 예: `"a b" → "2"`\n' > "$B/cat/a.md"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" fn --catalog "$B/cat" --base "$B" > "$TMP/f1.tsv"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" fn --catalog "$B/cat" --base "$B" --scale 4 > "$TMP/f4.tsv"
col() { awk -F'\t' -v n="$2" -v c="$3" '$1 == n { print $c }' "$1"; }
eq "S6 a program per line: 50 → 200" "50 200" "$(col "$TMP/f1.tsv" t_each 9) $(col "$TMP/f4.tsv" t_each 9)"
eq "S6 one program whatever the size: 1 → 1" "1 1" "$(col "$TMP/f1.tsv" t_once 9) $(col "$TMP/f4.tsv" t_once 9)"
eq "S6 status ok" "ok ok" "$(col "$TMP/f1.tsv" t_each 10) $(col "$TMP/f4.tsv" t_once 10)"
ms1="$(col "$TMP/f1.tsv" t_each 4)"; ms4="$(col "$TMP/f4.tsv" t_each 4)"
awk -v a="$ms1" -v b="$ms4" 'BEGIN { exit !(a > 0 && b / a >= 2.5 && b / a <= 6.5) }' && ok "OK [S6] 4x input ≈ 4x time ($ms1 → $ms4 ms)" || fail "[S6] $ms1 → $ms4"
eq "S6 a function that is not there" "load-failed" "$(col "$TMP/f1.tsv" t_gone 10)"
eq "S6 a fixed-size example at 4x" "not-scalable" "$(col "$TMP/f4.tsv" t_fixed 10)"
eq "S6 not a shell function" "not-shell" "$(col "$TMP/f1.tsv" t_ts 10)"
eq "S6 eleven columns on every line" 0 "$(awk -F'\t' 'NF != 11' "$TMP/f1.tsv" "$TMP/f4.tsv" | grep -c .)"
eq "S6 a shell function that only computes is judged by CPU time" "cpu" "$(col "$TMP/f1.tsv" t_once 11)"

echo "S7. 메모리 최고치 (TESTS T7)"
seq 1 2000000 > "$TMP/big.txt"      # 약 14MB
printf '#!/usr/bin/env bash\nwc -l < "$1"\n' > "$TMP/stream.sh"                    # 흘려보내며 센다
printf '#!/usr/bin/env bash\nall="$(cat "$1")"; echo "${#all}"\n' > "$TMP/collect.sh"   # 전체를 변수에 담는다
r1="$(SCV_PB_GPU_TOOL=none "$BASH" "$PB" run --no-count -- bash "$TMP/stream.sh" "$TMP/big.txt" | cut -f3)"
r2="$(SCV_PB_GPU_TOOL=none "$BASH" "$PB" run --no-count -- bash "$TMP/collect.sh" "$TMP/big.txt" | cut -f3)"
if [[ "$r1" == "-" || "$r2" == "-" ]]; then echo "  - SKIP [S7] 이 컴퓨터에는 메모리를 재는 명령이 없음 (재지 못함)"
else awk -v a="$r1" -v b="$r2" 'BEGIN { exit !(b >= 2 * a) }' && ok "OK [S7] collecting uses at least twice the memory ($r1 → $r2 MB)" || fail "[S7] stream=$r1 collect=$r2"; fi

echo "S8. 판정 잣대 고르기 — 전수 (TESTS T8)"
eq "S8 works on the CPU only"                     cpu        "$(pb_pick_measure 1.00 0.98 0.0 4 100)"
eq "S8 used the GPU (memory)"                     wall-gpu   "$(pb_pick_measure 8.40 0.80 1171.0 78 100)"
eq "S8 used the GPU (use rose, little memory)"    wall-gpu   "$(pb_pick_measure 1.10 1.50 20.0 35 100)"
eq "S8 wall far above CPU, no GPU tool"           unmeasured "$(pb_pick_measure 8.40 0.80 - - 100)"
eq "S8 too short to measure"                      unmeasured "$(pb_pick_measure 0.01 0.00 - - 100)"
eq "S8 nothing measured"                          unmeasured "$(pb_pick_measure - - - - 100)"
eq "S8 a busy computer is not a GPU signal"       cpu        "$(pb_pick_measure 2.00 0.98 0.0 4 210)"
eq "S8 a busy computer, no tool — still CPU"      cpu        "$(pb_pick_measure 2.00 0.98 - - 210)"
eq "S8 waits on something else, tool present"     wall-gpu   "$(pb_pick_measure 1.00 0.00 0.0 0 100)"
eq "S8 background GPU noise stays CPU"            cpu        "$(pb_pick_measure 0.34 0.30 56.2 17 100)"
eq "S8 ratio"                 "17.3" "$(pb_scale_ratio 22.286 386.600)"
eq "S8 ratio, linear"         "3.1"  "$(pb_scale_ratio 4.492 13.739)"
eq "S8 ratio, not measured"   "-"    "$(pb_scale_ratio 5 -)"
eq "S8 ratio, zero base"      "-"    "$(pb_scale_ratio 0.000 3.0)"
eq "S8 milli" "22286 500 3000" "$(pb_to_milli 22.286) $(pb_to_milli 0.5) $(pb_to_milli 3)"
pb_to_milli - >/dev/null; eq "S8 milli, not a number → 1" 1 "$?"

echo "S9. 명령의 실패와 잣대 — 실제 실행"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" run --no-count -- bash -c 'exit 3' > "$TMP/fail.out" 2> "$TMP/fail.err"
eq "S9 a failing command: its exit code is in the line" 3 "$(cut -f8 "$TMP/fail.out")"
grep -q '종료 코드 3' "$TMP/fail.err" && ok "OK [S9] and it is said out loud" || fail "[S9] $(cat "$TMP/fail.err")"
eq "S9 waiting with no GPU tool → not measured" "unmeasured" "$(SCV_PB_GPU_TOOL=none "$BASH" "$PB" run --no-count -- sleep 1 | cut -f7)"

echo "S10. 입력 4배 때의 배수 — 이 저장소의 두 함수 (TESTS T6)"
if [[ -d "$CORE/../scv/core/catalog/pure" ]]; then
  SCV_PB_GPU_TOOL=none "$BASH" "$PB" fn --only pc_duplicate_pairs --only scv_tc_diff > "$TMP/r1.tsv"
  SCV_PB_GPU_TOOL=none "$BASH" "$PB" fn --only pc_duplicate_pairs --only scv_tc_diff --scale 4 > "$TMP/r4.tsv"
  rw="$(pb_scale_ratio "$(col "$TMP/r1.tsv" pc_duplicate_pairs 4)" "$(col "$TMP/r4.tsv" pc_duplicate_pairs 4)")"
  rd="$(pb_scale_ratio "$(col "$TMP/r1.tsv" scv_tc_diff 4)" "$(col "$TMP/r4.tsv" scv_tc_diff 4)")"
  # 가파른 쪽 본보기는 '같은 지문 짝'이다 — 되풀이한 입력에서 답 줄 수가 입력의 제곱만큼 늘어 어느 셸에서나
  # 한도(8배)를 넘는다(2026-11-11 실측: bash 3.2 14.3배, bash 5 14.9배).
  # 처음 본보기였던 낱말 나누기(bash 3.2 에서 17배)는 0.91.1 에서 고쳐 4.9배가 됐다 — 그래서 바꿨다.
  [[ "$rw" != "-" && "$rd" != "-" && $(( $(pb_to_milli "$rw") * 10 )) -ge $(( $(pb_to_milli "$rd") * 15 )) ]] \
    && ok "OK [S10] pair listing grows faster than line comparing ($rw vs $rd times at 4x, bash ${BASH_VERSINFO[0]})" || fail "[S10] pairs=$rw diff=$rd"
  [[ "$rw" != "-" && "$(pb_to_milli "$rw")" -ge 8000 ]] && ok "OK [S10] pair listing is past the limit of 8 ($rw)" || fail "[S10] pairs ratio=$rw"
  [[ "$rd" != "-" && "$(pb_to_milli "$rd")" -le 6000 ]] && ok "OK [S10] line comparing stays near linear ($rd times at 4x)" || fail "[S10] diff ratio=$rd"
else
  echo "  - SKIP [S10] 이 저장소에 사전이 없음"
fi

echo "S11. GPU 를 쓴 명령은 GPU 로 판정한다 (TESTS T3 — GPU 와 torch 가 있는 컴퓨터에서만)"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import torch, sys; sys.exit(0 if torch.backends.mps.is_available() or torch.cuda.is_available() else 1)' >/dev/null 2>&1 && [[ "$(SCV_PB_GPU_TOOL='' bash -c "source '$CORE/scripts/lib/pure-bench.sh'; command -v ioreg >/dev/null || command -v nvidia-smi >/dev/null; echo \$?")" == 0 ]]; then
  cat > "$TMP/job.py" <<'PY'
import sys, torch
dev = "mps" if torch.backends.mps.is_available() else "cuda"
n = int(sys.argv[1]); reps = int(sys.argv[2])
x = torch.rand(n, n, device=dev); y = torch.rand(n, n, device=dev)
for _ in range(reps):
    z = x @ y
    x = z / z.norm()
if dev == "mps": torch.mps.synchronize()
else: torch.cuda.synchronize()
print(float(x.sum().cpu()) > 0)
PY
  IFS=$'\t' read -r w1 c1 _ _ _ _ n1 e1 <<<"$("$BASH" "$PB" run --no-count -- python3 "$TMP/job.py" 3000 20)"
  IFS=$'\t' read -r w2 c2 _ _ _ _ n2 e2 <<<"$("$BASH" "$PB" run --no-count -- python3 "$TMP/job.py" 6000 60)"
  eq "S11 both ran" "0 0" "$e1 $e2"
  eq "S11 both judged by wall clock and GPU" "wall-gpu wall-gpu" "$n1 $n2"
  awk -v a="$w1" -v b="$w2" 'BEGIN { exit !(b >= 3 * a) }' && ok "OK [S11] the bigger job shows in the wall clock ($w1 → $w2 s)" || fail "[S11] wall $w1 → $w2"
  awk -v a="$c1" -v b="$c2" 'BEGIN { exit !(b <= 1.5 * a) }' && ok "OK [S11] and CPU time alone would have missed it ($c1 → $c2 s)" || echo "  - note [S11] CPU time also grew here ($c1 → $c2 s)"
else
  echo "  - SKIP [S11] GPU · torch · GPU 읽는 도구 중 없는 것이 있음 — 이 컴퓨터에서는 돌려 보지 않음"
fi

echo "S12. 엮은 함수와 표 — 순수 함수"
eq "S12 who calls whom (comments and unknown names are skipped)" $'f\tg h' "$(pb_calls $'@@ f\n  g "$1" | h\n  # i 는 주석\n@@ g\n  echo x\n@@ z\n  f' $'f\ng\nh\ni')"
eq "S12 composed = two or more" $'f\tg h' "$(pb_composed $'f\tg h\nk\tg')"
eq "S12 composed, at least one" 2 "$(pb_composed $'f\tg h\nk\tg' 1 | grep -c .)"
R1="$(pb_row $'f\t1\t14\t22.286\t0.32\t2.9\t7\t0.0\t0\tok\tcpu' $'f\t4\t5\t386.600\t1.95\t3.1\t14\t15.9\t0\tok\tcpu' "글을 나눈다")"
eq "S12 a row joins both sizes and the role" $'f\tcpu\t22.286\t386.600\t17.3\t2.9\t0\t0\tok\t글을 나눈다' "$R1"
R2="$(pb_row $'g\t1\t60\t1.500\t0.31\t2.4\t7\t0.0\t1\tok\tcpu' $'g\t4\t-\t-\t-\t-\t-\t-\t-\tnot-scalable\t-' "")"
eq "S12 a row that could not be scaled" $'g\tcpu\t1.500\t-\t-\t2.4\t1\t-\tnot-scalable\t-' "$R2"
R3=$'h\tcpu\t3.000\t12.000\t4.0\t2.4\t50\t200\tok\t줄마다 부른다'
R4=$'k\t-\t-\t-\t-\t-\t-\t-\tload-failed\t-'
R5=$'m\tunmeasured\t0.100\t-\t-\t2.4\t0\t-\tok\t-'
OUT="$(pb_render "$R1"$'\n'"$R2"$'\n'"$R3"$'\n'"$R4"$'\n'"$R5" "bash X")"
grep -q '^| f | 글을 나눈다 | cpu | 22.286 | 386.600 | 17.3 | 2.9 | 0 → 0 | 배수 한도(8배) 넘음 |$' <<<"$OUT" && ok "OK [S12] over the limit of 8 is said in the row" || fail "[S12] $(grep '^| f ' <<<"$OUT")"
grep -q '^| h | .* | 50 → 200 | 입력만큼 부름 |$' <<<"$OUT" && ok "OK [S12] calls that grow with the input are said in the row" || fail "[S12] $(grep '^| h ' <<<"$OUT")"
eq "S12 the count at the end" "잰 함수 3 · 못 잰 함수 2(불러오지 못함 1 · 셸 함수 아님 0 · 재지 못함 1) · 늘려 재지 못함 1 · 배수 한도 넘음 1 · 입력만큼 부름 1" "$(tail -1 <<<"$OUT")"
eq "S12 measured + not measured = all rows" 5 "$(( 3 + 2 ))"
eq "S12 the environment is the first line" "잰 환경: bash X" "$(head -1 <<<"$OUT")"
C="$(pb_render_composed $'f\tg h' $'f\tcpu\t10.000\t50.000\t5.0\t2.9\t0\t0\tok\t셋을 잇는다\ng\tcpu\t1.500\t6.000\t4.0\t2.4\t1\t1\tok\t-\nh\tcpu\t2.000\t-\t-\t2.4\t0\t-\tnot-scalable\t-')"
eq "S12 composed row: whole next to the sum of its parts" "| f | 셋을 잇는다 | g · h | 10.000 | 3.500 | 5.0 | 0 → 0 |" "$(tail -1 <<<"$C")"
eq "S12 roles: cut before the explanation" $'f\t글을 낱말들로 나눈다' "$(pb_roles $'### f\n- 역할: 글을 낱말들로 나눈다 — 2자 이상(빈칸으로 이음)\n- 위치: lib/a.sh · @pure · sh\n- 예: `"a" → "1"`' "")"
eq "S12 roles: long ones stop after eight words (the mark survives on bash 3.2)" $'f\t하나 둘 셋 넷 다섯 여섯 / 일곱…' "$(pb_roles $'### f\n- 역할: 하나 둘 셋 넷 다섯 여섯 | 일곱 여덟 아홉\n- 위치: lib/a.sh · @pure · sh\n- 예: `"a" → "1"`' "")"
eq "S12 roles follow the same order as the targets" "$(pb_targets "$CAT" "" | cut -f1)" "$(pb_roles "$CAT" "" | cut -f1)"

echo "S13. 엮은 함수 재기 — 임시 함수로 (TESTS T15)"
cat >> "$B/lib/t.sh" <<'LIB'
t_up()   { printf '%s\n' "$1" | tr 'a-z' 'A-Z'; }
t_rev()  { printf '%s\n' "$1" | tr 'A-Z' 'a-z'; }
t_both() { t_rev "$(t_up "$1")"; }
LIB
printf '\n### t_up\n- 역할: 대문자로 바꾼다\n- 위치: lib/t.sh · @deterministic · sh\n- 예: `$\x27a\\nb\x27 → $\x27A\\nB\x27`\n\n### t_rev\n- 역할: 소문자로 바꾼다\n- 위치: lib/t.sh · @deterministic · sh\n- 예: `$\x27A\\nB\x27 → $\x27a\\nb\x27`\n\n### t_both\n- 역할: 둘을 잇는다 — 대문자로 바꿨다가 소문자로\n- 위치: lib/t.sh · @deterministic · sh\n- 예: `$\x27a\\nb\x27 → $\x27a\\nb\x27`\n' >> "$B/cat/a.md"
eq "S13 found in the code, not from a list" $'t_both\tt_rev t_up' "$("$BASH" "$PB" composed --catalog "$B/cat" --base "$B")"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" bench --composed --catalog "$B/cat" --base "$B" --tsv "$TMP/rows.tsv" > "$TMP/bench.md"
eq "S13 only the composed function and what it calls are measured" "t_both t_rev t_up" "$(cut -f1 "$TMP/rows.tsv" | sort | tr '\n' ' ' | sed 's/ $//')"
crow="$(grep '^| t_both | 둘을 잇는다 | ' "$TMP/bench.md" | tail -1)"
IFS='|' read -r _ _ _ _ whole parts ratio calls _ <<<"$crow"
[[ "$(pb_to_milli "${whole// /}")" -gt 0 && "$(pb_to_milli "${parts// /}")" -gt 0 && "${ratio// /}" != "-" ]] && ok "OK [S13] whole · sum of parts · 4x ratio are all there (${whole// /} · ${parts// /} · ${ratio// /})" || fail "[S13] $crow"
eq "S13 the composed function runs two programs, at any size" "2 → 2" "$(sed 's/^ *//; s/ *$//' <<<"$calls")"
grep -q '^잰 함수 3 · 못 잰 함수 0' "$TMP/bench.md" && ok "OK [S13] the count line" || fail "[S13] $(grep '^잰 함수' "$TMP/bench.md")"
if [[ -d "$CORE/../scv/core/catalog/pure" ]]; then
  n="$("$BASH" "$PB" composed | grep -c .)"
  [[ "$n" -ge 20 ]] && ok "OK [S13] this repository: $n composed functions" || fail "[S13] composed=$n"
fi

echo "S14. 앞뒤 견주기의 판정 — 순수 함수 (TESTS T9 · T12)"
eq "S14 median, odd" "2.000" "$(pb_median "3.000 1.000 2.000")"
eq "S14 median, even" "2.500" "$(pb_median "4.0 1.0 3.0 2.0")"
eq "S14 median, nothing" "-" "$(pb_median "")"
eq "S14 ratio" "1.25 0.90 -" "$(pb_ratio 3.000 3.750) $(pb_ratio 10 9) $(pb_ratio 0 5)"
v() { pb_compare "$1" | cut -f2-; }
eq "S14 1.15 times → pass"                      $'pass\t-'                 "$(v $'f\tok\tcpu\t3.000\t3.450\t0\t0\t2.4\t2.5\t-\t-')"
eq "S14 1.25 times → fail"                      $'fail\ttime=1.25'         "$(v $'f\tok\tcpu\t3.000\t3.750\t0\t0\t2.4\t2.5\t-\t-')"
eq "S14 memory 1.25 times and +2 MB → fail"     $'fail\tmem=8.0:10.0'      "$(v $'f\tok\tcpu\t3.000\t3.000\t0\t0\t8.0\t10.0\t-\t-')"
eq "S14 memory 1.25 times but +0.3 MB → pass"   $'pass\t-'                 "$(v $'f\tok\tcpu\t3.000\t3.000\t0\t0\t1.2\t1.5\t-\t-')"
eq "S14 one more program called → fail"         $'fail\tcalls=1:2'         "$(v $'f\tok\tcpu\t3.000\t3.000\t1\t2\t2.4\t2.4\t-\t-')"
eq "S14 the answer changed → left out"          $'skipped-different-answer\t-' "$(v $'f\tdifferent-answer\t-\t-\t-\t-\t-\t-\t-\t-\t-')"
eq "S14 4x ratio newly over 8 → fail"           $'fail\tscale=4.0:9.1'     "$(v $'f\tok\tcpu\t3.000\t3.000\t0\t0\t2.4\t2.4\t4.0\t9.1')"
eq "S14 4x ratio already over, not worse → pass" $'pass\t-'                "$(v $'f\tok\tcpu\t3.000\t3.000\t0\t0\t2.4\t2.4\t9.0\t9.5')"
eq "S14 4x ratio already over, much worse → fail" $'fail\tscale=9.0:12.0'  "$(v $'f\tok\tcpu\t3.000\t3.000\t0\t0\t2.4\t2.4\t9.0\t12.0')"
eq "S14 a new function over 8 → fail"           $'fail\tscale=-:17.5'      "$(v $'f\tnew\tcpu\t-\t3.000\t-\t0\t-\t2.4\t-\t17.5')"
eq "S14 a new function within limits → new"     $'new\t-'                  "$(v $'f\tnew\tcpu\t-\t3.000\t-\t0\t-\t2.4\t-\t4.0')"
eq "S14 judged unmeasured stays unmeasured"     $'unmeasured\t-'           "$(v $'f\tok\tunmeasured\t3.000\t9.000\t0\t0\t2.4\t2.4\t-\t-')"
eq "S14 not reached in time"                    $'not-reached\t-'          "$(v $'f\tnot-reached\t-\t-\t-\t-\t-\t-\t-\t-\t-')"
pb_accept_covers "time=1.35" "time=1.40"; eq "S14 accepted, about the same → covered" 0 "$?"
pb_accept_covers "time=1.35" "time=1.80"; eq "S14 accepted, somewhat higher on a busy computer → still covered" 0 "$?"
pb_accept_covers "time=1.35" "time=3.00"; eq "S14 accepted, now more than twice as bad → asked again" 1 "$?"
pb_accept_covers "mem=1.9:37.0" "mem=1.9:50.0"; eq "S14 accepted memory, 1.35 times more → asked again" 1 "$?"
pb_accept_covers "time=1.35" "time=1.30 calls=1:2"; eq "S14 accepted, a new kind of excess → asked again" 1 "$?"
pb_accept_covers "calls=1:100 mem=1.9:37.0" "calls=1:100"; eq "S14 accepted calls, same count → covered" 0 "$?"
pb_accept_covers "calls=1:100" "calls=1:101"; eq "S14 accepted calls, one more → asked again" 1 "$?"
eq "S14 baseline: the same stays" $'a\nb' "$(pb_baseline_next $'a\nb' $'a\nb')"
eq "S14 baseline: one fewer → the list shrinks" "a" "$(pb_baseline_next $'a\nb' $'a')"
eq "S14 baseline: a new one is named, not added" $'a\nb\n@@new c' "$(pb_baseline_next $'a\nb' $'a\nb\nc')"
eq "S14 the line a person reads" "f — 시간 1.25배 · 다른 프로그램을 부른 횟수 1번 → 100번 · 메모리 1.9MB → 37.0MB" "$(pb_fail_lines $'f\tfail\ttime=1.25 calls=1:100 mem=1.9:37.0\ng\tpass\t-')"

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

echo "S17. 턴 끝 — 고친 함수만 (TESTS T14 · T13)"
if ! command -v git >/dev/null 2>&1; then echo "  - SKIP [S17] git 없음"
else
  G="$TMP/proj"; mkdir -p "$G/lib" "$G/scv/core/catalog/pure" "$G/scv/journal" "$G/turn/.turn-plan"
  ( cd "$G" && git init -q . && git symbolic-ref HEAD refs/heads/main )
  cat > "$G/lib/t.sh" <<'LIB'
t_each() { local l; while IFS= read -r l; do printf '%s\n' "$l" | tr 'a-z' 'A-Z'; done <<< "$1"; }
t_once() { printf '%s\n' "$1" | tr 'a-z' 'A-Z'; }
t_up()   { printf '%s\n' "$1" | tr 'a-z' 'A-Z'; }
t_rev()  { printf '%s\n' "$1" | tr 'A-Z' 'a-z'; }
t_both() { t_rev "$(t_up "$1")"; }
LIB
  : > "$G/scv/core/catalog/pure/INDEX.md"
  for f in t_each t_once t_up t_rev t_both; do printf '### %s\n- 역할: 시험용\n- 위치: lib/t.sh · @deterministic · sh\n- 예: `$\x27a\\nb\x27 → $\x27A\\nB\x27`\n\n' "$f"; done > "$G/scv/core/catalog/pure/a.md"
  echo "읽어 보세요" > "$G/README.md"
  ( cd "$G" && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -q -m base && git checkout -q -b work )
  pbg() { ( cd "$G" && SCV_PB_GPU_TOOL=none "$BASH" "$PB" "$@" ); }
  first() { local o; o="$(pbg "$@")"; printf '%s' "${o%%$'\n'*}"; }   # 첫 줄만 — 출력을 끝까지 받은 뒤 자른다
  # 사전 함수를 고치지 않은 턴
  echo "바뀜" >> "$G/README.md"; printf 'README.md\n' > "$G/turn/.turn-plan/changed"
  o="$(pbg turn-end --dir "$G/turn")"
  eq "S17 a turn that touched no pure function: nothing is measured" "PURE_BENCH: pass / PURE_BENCH_RUNS: 0" "$(tr '\n' '/' <<<"$o" | sed 's#/# / #; s#/$##')"
  : > "$G/turn/.turn-plan/changed"
  eq "S17 a turn that changed nothing" "PURE_BENCH: pass" "$(first turn-end --dir "$G/turn")"
  # 함수 둘을 고친 턴 — 그 둘만 잰다(둘 다 답은 그대로)
  python3 - "$G/lib/t.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("""t_once() { printf '%s\\n' "$1" | tr 'a-z' 'A-Z'; }""", """t_once() { local l; while IFS= read -r l; do printf '%s\\n' "$l" | tr 'a-z' 'A-Z'; done <<< "$1"; }""")
s = s.replace("""t_each() { local l; while""", """t_each() { local l x=1; while""")
open(p, "w").write(s)
PY
  printf 'lib/t.sh\nREADME.md\n' > "$G/turn/.turn-plan/changed"
  o="$(pbg turn-end --dir "$G/turn")"
  eq "S17 two functions changed: those two are measured" "PURE_BENCH_RUNS: 2" "$(grep '^PURE_BENCH_RUNS' <<<"$o")"
  eq "S17 the slowed one stops the turn" "PURE_BENCH: block" "$(head -1 <<<"$o")"
  r="$(sed -n 's/^PURE_BENCH_REASON: //p' <<<"$o")"
  [[ "$r" == *"t_once — 시간 "*"배 · 다른 프로그램을 부른 횟수 1번 → 50번"* && "$r" == *"[재는 검사] 함수 이름 —"* && "$r" != *"t_each —"* ]] && ok "OK [S17] the reason names the function, its real numbers and how to ask" || fail "[S17] $r"
  eq "S17 what went over waits for the user's answer" "t_once" "$(cut -f1 "$G/scv/journal/.pure-bench-pending")"
  # 사용자가 "고침"을 고르면 받아들인 것이 아니다 → 다시 막는다. "이대로"를 고르면 지나간다.
  pbg accept --question "[재는 검사] t_once — 시간이 늘었습니다" --answer "고침 (추천)" >/dev/null
  eq "S17 'fix it' is not an acceptance" "PURE_BENCH: block" "$(first turn-end --dir "$G/turn")"
  eq "S17 after two stops the turn is let through, and that is recorded" "PURE_BENCH: pass-unanswered" "$(first turn-end --dir "$G/turn")"
  grep -q 't_once' "$G/scv/journal/.pure-bench.log" && ok "OK [S17] the log names what was left over the limit" || fail "[S17] no log line"
  printf '0' > "$G/turn/.turn-plan/pb-blocks"
  a="$(pbg accept --question "[재는 검사] t_once — 시간이 늘었습니다" --answer "이대로 둠")"
  [[ "$a" == "PURE_BENCH_ACCEPTED: t_once"* ]] && ok "OK [S17] '이대로' is recorded as accepted" || fail "[S17] $a"
  eq "S17 an accepted change passes" "PURE_BENCH: pass" "$(first turn-end --dir "$G/turn")"
  # 엮은 함수: 부품을 고치면 그것을 부르는 엮은 함수도 함께 잰다
  ( cd "$G" && git checkout -q lib/t.sh ) ; python3 - "$G/lib/t.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("""t_rev()  { printf '%s\\n' "$1" | tr 'A-Z' 'a-z'; }""", """t_rev()  { local x=1; printf '%s\\n' "$1" | tr 'A-Z' 'a-z'; }""")
open(p, "w").write(s)
PY
  o="$(pbg turn-end --dir "$G/turn")"
  eq "S17 a changed part brings its composed caller along (t_rev + t_both)" "PURE_BENCH_RUNS: 2" "$(grep '^PURE_BENCH_RUNS' <<<"$o")"
  # 끄기
  printf '{"SCV_PURE_BENCH": "off"}\n' > "$G/scv/scv_settings.json"
  eq "S17 switched off" "PURE_BENCH: off" "$(first turn-end --dir "$G/turn")"
  rm -f "$G/scv/scv_settings.json"
  # 계획 끝: 꼼꼼히
  ( cd "$G" && git checkout -q lib/t.sh ); rm -f "$G/scv/journal/.pure-bench-accepted"
  python3 - "$G/lib/t.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("""t_once() { printf '%s\\n' "$1" | tr 'a-z' 'A-Z'; }""", """t_once() { local l; while IFS= read -r l; do printf '%s\\n' "$l" | tr 'a-z' 'A-Z'; done <<< "$1"; }""")
open(p, "w").write(s)
PY
  pbg plan-end > "$TMP/planend.md"; st=$?
  eq "S17 plan end: a slowed function fails the full check" 1 "$st"
  grep -q '쌍 6 · 입력 4배 포함' "$TMP/planend.md" && grep -q '^| t_once | 한도 넘음 |' "$TMP/planend.md" && grep -q '^견주는 기준: 이 일을 시작하기 전의 코드' "$TMP/planend.md" && ok "OK [S17] six pairs, 4x input, against the code before this work" || fail "[S17] $(head -3 "$TMP/planend.md")"
  ( cd "$G" && git checkout -q lib/t.sh )
  eq "S17 plan end with nothing changed: exit 0" 0 "$(pbg plan-end >/dev/null; echo $?)"
fi

echo "S18. 훅과 턴 검사에 이어졌는가"
grep -q 'pure-bench.sh" turn-end --dir' "$CORE/template/hooks/on-stop.sh" 2>/dev/null || grep -q 'turn-end --dir "\$_scv_tdir"' "$CORE/template/hooks/on-stop.sh" && ok "OK [S18] the stop hook runs the turn-end check" || fail "[S18] on-stop.sh does not call turn-end"
a="$(grep -n '/turn plan check' "$CORE/template/hooks/on-stop.sh" | head -1 | cut -d: -f1)"; b="$(grep -n 'turn-end --dir' "$CORE/template/hooks/on-stop.sh" | head -1 | cut -d: -f1)"
[[ -n "$a" && -n "$b" && "$b" -gt "$a" ]] && ok "OK [S18] after the plan-record check" || fail "[S18] a=$a b=$b"
grep -q '> "\$S/changed"' "$CORE/scripts/turn-check.sh" && ok "OK [S18] the turn check leaves the list of changed files" || fail "[S18] no changed list"
HOOK="$CORE/template/hooks/on-stop.sh"
# 값싼 앞 검사: 사전 함수가 사는 파일을 고치지 않은 턴은 재는 명령을 띄우지도 않는다
if [[ -d "$CORE/../scv/core/catalog/pure" ]]; then
  pre() { awk '{ print "- 위치: " $0 " · "; if (sub(/^core\//, "")) print "- 위치: " $0 " · " }' "$1" | grep -q -F -f - "$CORE"/../scv/core/catalog/pure/*.md; }
  printf 'README.md\ncore/tests/test-x.sh\n' > "$TMP/ch1"; printf 'README.md\ncore/scripts/lib/turn-check.sh\n' > "$TMP/ch2"
  pre "$TMP/ch1"; r1=$?; pre "$TMP/ch2"; r2=$?
  eq "S18 the cheap check: no pure-function file → not started, one → started" "1 0" "$r1 $r2"
  grep -q 'grep -q -F -f - "\$_scv_pb_cat"' "$HOOK" && ok "OK [S18] and the stop hook uses that check before starting the command" || fail "[S18] the hook starts the command without the cheap check"
fi
grep -q '"\[재는 검사\]"\* \]\] || bash "\$SCRIPT_DIR/pure-bench.sh" accept' "$CORE/scripts/turn-check.sh" && ok "OK [S18] only that question starts the acceptance step (other answers cost nothing)" || fail "[S18] every choice answer starts the command"
grep -q 'pure-bench.sh" accept --question' "$CORE/scripts/turn-check.sh" && ok "OK [S18] a choice answer reaches the acceptance record" || fail "[S18] no accept call"
grep -q 'SCV_PURE_BENCH' "$CORE/scripts/lib/settings.sh" && ok "OK [S18] the switch is a known setting" || fail "[S18] setting key missing"

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

echo
echo "── $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
