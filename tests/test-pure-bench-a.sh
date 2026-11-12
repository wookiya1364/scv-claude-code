#!/usr/bin/env bash
# test-pure-bench-a.sh — 재는 명령(계획 20261111-wookiya1364-pure-bench-and-gate)의 시험, 넷 가운데 순수 함수와 가벼운 실행(S1 ~ S14).
# 한 파일이던 것을 넷으로 나눴다(계획 20261112-wookiya1364-small-fixes-bundle) — 조각 실행기가 넷을 서로 다른
# 러너에 나눠 함께 돌릴 수 있게. 구간 번호(S1 ~ S23)는 나누기 전 그대로다.
#
# Run: bash core/tests/test-pure-bench-a.sh   (넷 모두: bash core/tests/test-pure-bench.sh)
#
# 시간을 재는 시험이라 다른 시험과 겹쳐 돌면 값이 틀어진다 — 다른 시험이 다 끝난 뒤 혼자 돈다:
# scv-test: serial
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PB="$CORE/scripts/pure-bench.sh"
# shellcheck source=fixtures/pure-bench/common.sh
source "$CORE/tests/fixtures/pure-bench/common.sh"

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
pbt_base
SCV_PB_GPU_TOOL=none "$BASH" "$PB" fn --catalog "$B/cat" --base "$B" > "$TMP/f1.tsv"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" fn --catalog "$B/cat" --base "$B" --scale 4 > "$TMP/f4.tsv"
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
pbt_base_composed
eq "S13 found in the code, not from a list" $'t_both\tt_rev t_up' "$("$BASH" "$PB" composed --catalog "$B/cat" --base "$B")"
SCV_PB_GPU_TOOL=none "$BASH" "$PB" bench --composed --catalog "$B/cat" --base "$B" --tsv "$TMP/rows.tsv" > "$TMP/bench.md"
eq "S13 only the composed function and what it calls are measured" "t_both t_rev t_up" "$(cut -f1 "$TMP/rows.tsv" | sort | tr '\n' ' ' | sed 's/ $//')"
crow="$(grep '^| t_both | 둘을 잇는다 | ' "$TMP/bench.md" | tail -1)"
IFS='|' read -r _ _ _ _ whole parts ratio calls _ <<<"$crow"
[[ "$(pb_to_milli "${whole// /}")" -gt 0 && "$(pb_to_milli "${parts// /}")" -gt 0 && "${ratio// /}" != "-" ]] && ok "OK [S13] whole · sum of parts · 4x ratio are all there (${whole// /} · ${parts// /} · ${ratio// /})" || fail "[S13] $crow"
eq "S13 the composed function runs two programs, at any size" "2 → 2" "$(sed 's/^ *//; s/ *$//' <<<"$calls")"
# 실패하면 잰 표와 줄들을 함께 찍는다 — "재지 못함"은 러너가 붐빌 때 나는데(벽시계 ≥ CPU × 1.5), 어느 함수가 어떤 값이었는지 보여야 가른다.
grep -q '^잰 함수 3 · 못 잰 함수 0' "$TMP/bench.md" && ok "OK [S13] the count line" \
  || { fail "[S13] $(grep '^잰 함수' "$TMP/bench.md")"; echo "    --- bench.md"; sed 's/^/    /' "$TMP/bench.md" | head -n 30; echo "    --- rows.tsv"; sed 's/^/    /' "$TMP/rows.tsv" | head -n 10; echo "    --- uptime: $(uptime 2>/dev/null)"; ps -A -o pcpu=,etime=,args= 2>/dev/null | sort -rn | head -n 8 | cut -c1-160 | sed 's/^/    /'; }
if [[ -d "$CORE/../scv/core/catalog/pure" ]]; then
  n="$("$BASH" "$PB" composed | grep -c .)"
  [[ "$n" -ge 20 ]] && ok "OK [S13] this repository: $n composed functions" || fail "[S13] composed=$n"
fi

echo "S13b. 재지 못한 함수만 다시 잰다 — 가짜 시간 도구로 (계획 20261112-wookiya1364-pure-bench-remeasure)"
# 컴퓨터가 잠깐 바쁘면 프로그램을 띄우는 함수는 벽시계만 늘어 "재지 못함"이 된다(2026-11-12 맥 러너 실측).
# 재는 명령은 그 함수만 같은 되풀이 수로 두 번까지 다시 잰다. 규칙은 그대로다 — 계속 못 재면 "재지 못함"으로 남는다.
eq "S13b remeasure decision" "1 0 0 0 0" "$(pb_remeasure unmeasured 0 2) $(pb_remeasure unmeasured 2 2) $(pb_remeasure cpu 0 2) $(pb_remeasure unmeasured 0 0) $(pb_remeasure wall-gpu 0 2)"
eq "S13b the line under the table" "다시 잰 함수 2 — 재지 못해 같은 횟수로 다시 쟀다: f(1배 · 1번 → cpu) · g(4배 · 2번 → 재지 못함)" "$(pb_remeasure_line $'f\t1\t1\tcpu\ng\t4\t2\tunmeasured')"
eq "S13b no line when nothing was measured again" "" "$(pb_remeasure_line "")"
# 가짜 시간 도구(BSD 꼴: -l -p -o <보고> <명령…>) — 명령은 그대로 돌리고 보고만 지어낸다.
#   first-bad : 함수를 재는 실행이 바로 앞 실행과 되풀이 수가 같으면(= 다시 재기) 좋은 값, 다르면 나쁜 값(벽시계 = CPU × 3)
#   always-bad: 함수를 재는 실행은 늘 나쁜 값          good: 늘 좋은 값
cat > "$TMP/faketime" <<'FK'
#!/usr/bin/env bash
report=""
while [[ $# -gt 0 ]]; do case "$1" in -l|-p) shift ;; -o) report="$2"; shift 2 ;; *) break ;; esac; done
"$@"; rc=$?
kind=good; a=("$@"); i=0
while [[ $i -lt ${#a[@]} ]]; do
  if [[ "${a[$i]}" == _drive ]]; then
    reps="${a[$((i + 5))]}"; last="$(cat "$FAKE_STATE" 2>/dev/null)"; printf '%s' "$reps" > "$FAKE_STATE"
    case "$FAKE_MODE" in always-bad) kind=bad ;; first-bad) [[ "$reps" == "$last" ]] || kind=bad ;; esac
    break
  fi
  i=$((i + 1))
done
if [[ $kind == bad ]]; then printf 'real 0.90\nuser 0.20\nsys 0.10\n  8388608  maximum resident set size\n' > "$report"
else printf 'real 0.31\nuser 0.20\nsys 0.10\n  8388608  maximum resident set size\n' > "$report"; fi
exit $rc
FK
chmod +x "$TMP/faketime"
# @effect fk
# 이유: 가짜 시간 도구를 끼워 재는 명령을 돌린다 — <방식> <명령(fn|bench)> [환경 설정 하나]
fk() {
  rm -f "$TMP/fk.state" "$TMP/again.log"
  env FAKE_MODE="$1" FAKE_STATE="$TMP/fk.state" SCV_PB_TIME_TOOL="$TMP/faketime" SCV_PB_REMEASURE_LOG="$TMP/again.log" SCV_PB_GPU_TOOL=none ${3:+"$3"} \
    "$BASH" "$PB" "$2" --catalog "$B/cat" --base "$B" --only t_up $( [[ "$2" != fn ]] || echo "--scale 1" )
}
line="$(fk first-bad fn)"
[[ "$(cut -f11 <<< "$line")" == cpu && "$(cat "$TMP/again.log" 2>/dev/null)" == $'t_up\t1\t1\tcpu' ]] \
  && ok "OK [S13b] measured on the second try" || fail "[S13b] first-bad: line=[$line] log=[$(cat "$TMP/again.log" 2>/dev/null)]"
[[ "$(awk -F'\t' '{ print NF }' <<< "$line")" == 11 ]] && ok "OK [S13b] the row keeps its eleven fields" || fail "[S13b] fields: [$line]"
out="$(fk first-bad bench)"
grep -q '^다시 잰 함수 [12] — 재지 못해 같은 횟수로 다시 쟀다: t_up(1배 · 1번 → cpu)' <<< "$out" && grep -q '^잰 함수 1 · 못 잰 함수 0' <<< "$out" \
  && ok "OK [S13b] the table says which function was measured again" || fail "[S13b] bench: $(grep -E '^다시 잰|^잰 함수' <<< "$out")"
line="$(fk always-bad fn)"
[[ "$(cut -f11 <<< "$line")" == unmeasured && "$(cat "$TMP/again.log" 2>/dev/null)" == $'t_up\t1\t2\tunmeasured' ]] \
  && ok "OK [S13b] still unmeasured after two more tries" || fail "[S13b] always-bad: line=[$line] log=[$(cat "$TMP/again.log" 2>/dev/null)]"
line="$(fk good fn)"
[[ "$(cut -f11 <<< "$line")" == cpu && ! -s "$TMP/again.log" ]] \
  && ok "OK [S13b] a measured function is not measured again" || fail "[S13b] good: line=[$line] log=[$(cat "$TMP/again.log" 2>/dev/null)]"
line="$(fk always-bad fn SCV_PB_REMEASURE=0)"
[[ "$(cut -f11 <<< "$line")" == unmeasured && ! -s "$TMP/again.log" ]] \
  && ok "OK [S13b] off: no second try" || fail "[S13b] off: line=[$line] log=[$(cat "$TMP/again.log" 2>/dev/null)]"

echo "S14. 앞뒤 견주기의 판정 — 순수 함수 (TESTS T9 · T12)"
eq "S14 median, odd" "2.000" "$(pb_median "3.000 1.000 2.000")"
eq "S14 median, even" "2.500" "$(pb_median "4.0 1.0 3.0 2.0")"
eq "S14 median, nothing" "-" "$(pb_median "")"
eq "S14 ratio" "1.25 0.90 -" "$(pb_ratio 3.000 3.750) $(pb_ratio 10 9) $(pb_ratio 0 5)"
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

pbt_finish
