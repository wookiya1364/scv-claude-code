#!/usr/bin/env bash
# pipe-arrange.sh — 줄을 흘려보내는 단계들의 더 빠른 순서를, 전부 돌려 보지 않고 계산해 표로 낸다.
# 계약 contracts/composition.md · 계획 20261112-wookiya1364-pipe-arrange.
#
# 단계마다 예시 입력을 한 번만 흘려 걸린 시간과 통과 비율을 재고, 비율 규칙으로 순서를 계산한 뒤,
# 고른 순서 하나만 실제로 돌려 처음 순서와 답이 같은지 · 정말 빠른지 본다. 단계 n개에 실행 n + 2번
# (전부 돌려 보면 n! 가지). 판단은 lib/pipe-arrange.sh 의 순수 함수가 하고, 여기는 읽기 · 실행 · 쓰기만 한다.
#
# Usage:
#   pipe-arrange.sh --steps FILE --input FILE
#
#   --steps FILE   단계 목록. 한 줄에 단계 하나: 이름<탭>종류<탭>명령[<탭>after:이름]
#                    종류   map      바꾸기 — 한 줄을 받아 한 줄을 낸다
#                           filter   고르기 — 줄을 통과시키거나 버린다
#                           head     앞의 N줄 — 명령 칸에 줄 수를 적는다
#                           collect  전체가 있어야 하는 단계(정렬 같은 것)
#                    명령은 표준 입력으로 줄을 받아 표준 출력으로 내는 셸 명령이다.
#                    after:이름 은 "이 단계는 그 단계 뒤에 있어야 한다"는 선언이다(고르기가 앞의 바꾸기 결과에 기댈 때).
#                    빈 줄과 # 으로 시작하는 줄은 읽지 않는다.
#   --input FILE   예시 입력(줄 단위 글).
#
# 이 명령은 표만 낸다 — 단계 목록도, 입력도, 다른 어떤 파일도 고치지 않는다. 고를지는 사람이 정한다.
# 답이 같다는 것은 준 예시 입력에서만 확인된다. head 와 collect 는 넘지 않는 벽이다.
# 고른 순서의 답이 처음과 다르면 덜 과감한 순서(이어진 고르기끼리만 바꿈)로 한 번 더 보고,
# 그래도 다르면 "바꿀 수 있는 순서를 찾지 못함"이라고 낸다.
#
# Exit: 0 = 표를 냈다 · 2 = 쓰임새 오류(파일 없음 · 단계 글이 틀림 · 단계가 둘 미만)
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/pure-bench.sh
source "$SCRIPT_DIR/lib/pure-bench.sh"
# shellcheck source=lib/pipe-arrange.sh
source "$SCRIPT_DIR/lib/pipe-arrange.sh"

PA_TMP=""
# @effect pa_cleanup
# 이유: 이 명령이 만든 임시 폴더를 지운다
pa_cleanup() { [[ -z "$PA_TMP" ]] || rm -rf "$PA_TMP"; }

# @effect pa_die
# 이유: 쓰임새 오류를 한 줄로 알리고 끝 코드 2 로 끝낸다
pa_die() { echo "pipe-arrange: $1" >&2; exit 2; }

# @effect pa_lines
# 이유: 파일의 줄 수를 센다
pa_lines() { LC_ALL=C wc -l < "$1" | tr -d ' '; }

# @effect pa_run
# 이유: 셸 한 줄을 예시 입력으로 실제로 돌려 "잰 시간(초)<탭>벽시계(초)<탭>메모리 MB"를 낸다 — 재는 일은 pure-bench.sh run 이 한다(GPU 를 쓴 명령은 벽시계로 본다)
pa_run() {
  local cmd="$1" in="$2" out="$3" wall cpu mem gu gm calls kind rc t
  IFS=$'\t' read -r wall cpu mem gu gm calls kind rc <<< "$(PA_IN="$in" PA_OUT="$out" bash "$SCRIPT_DIR/pure-bench.sh" run --no-count -- bash -c "{ $cmd ; } < \"\$PA_IN\" > \"\$PA_OUT\"" 2>/dev/null)"
  t="$cpu"; [[ "$kind" == cpu ]] || t="$wall"
  printf '%s\t%s\t%s' "${t:--}" "${wall:--}" "${mem:--}"
}

# @effect pa_ratio
# 이유: 나온 줄 수 ÷ 들어간 줄 수를 소수 둘째 자리로 낸다(계산기 프로그램을 부른다)
pa_ratio() { LC_ALL=C awk -v o="$1" -v i="$2" 'BEGIN { if (i + 0 == 0) print "1.00"; else printf "%.2f", o / i }'; }

STEPS_FILE=""; INPUT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --steps) STEPS_FILE="${2:-}"; shift 2 ;;
    --input) INPUT_FILE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) pa_die "모르는 인자: $1 (--steps FILE --input FILE)" ;;
  esac
done
[[ -n "$STEPS_FILE" && -f "$STEPS_FILE" ]] || pa_die "단계 목록 파일이 없다: ${STEPS_FILE:-(--steps 없음)}"
[[ -n "$INPUT_FILE" && -f "$INPUT_FILE" ]] || pa_die "예시 입력 파일이 없다: ${INPUT_FILE:-(--input 없음)}"

STEPS="$(pa_parse_steps "$(cat "$STEPS_FILE")")" || pa_die "${STEPS#오류: }"
NSTEP="$(grep -c . <<< "$STEPS" || true)"
[[ "$NSTEP" -ge 2 ]] || pa_die "단계가 둘 이상 있어야 순서를 견줄 수 있다 (지금 ${NSTEP}개)"
NIN="$(pa_lines "$INPUT_FILE")"
[[ "$NIN" -gt 0 ]] || pa_die "예시 입력이 비어 있다: $INPUT_FILE"

PA_TMP="$(mktemp -d)"; trap pa_cleanup EXIT

# 1) 단계마다 한 번만 잰다 — 걸린 시간과 통과 비율. head 는 재지 않는다(값이 정해져 있다).
MEAS=""; RUNS=0
while IFS=$'\t' read -r name kind cmd after; do
  [[ -n "$name" ]] || continue
  if [[ "$kind" == head ]]; then
    t=0; r="$(pa_ratio "$cmd" "$NIN")"; [[ "$(pb_to_milli "$r")" -le 1000 ]] || r="1.00"
  else
    IFS=$'\t' read -r t _ <<< "$(pa_run "$cmd" "$INPUT_FILE" "$PA_TMP/step.out")"; RUNS=$((RUNS + 1))
    pb_to_milli "$t" >/dev/null || t=0
    r="$(pa_ratio "$(pa_lines "$PA_TMP/step.out")" "$NIN")"
  fi
  MEAS+="${MEAS:+$'\n'}$name"$'\t'"$kind"$'\t'"$cmd"$'\t'"$after"$'\t'"$t"$'\t'"$r"
done <<< "$STEPS"

# 2) 순서를 계산한다(실행 없음)
ORIG="$(cut -f1 <<< "$STEPS")"
BEST="$(pa_order "$MEAS")"

# 3) 처음 순서와 고른 순서를 한 번씩 흘려보내 답을 견준다
IFS=$'\t' read -r T0 W0 M0 <<< "$(pa_run "$(pa_pipeline "$STEPS" "$ORIG")" "$INPUT_FILE" "$PA_TMP/orig.out")"; RUNS=$((RUNS + 1))
ROWS="처음"$'\t'"$(pa_join_names "$ORIG")"$'\t'"$(pa_expected "$MEAS" "$ORIG")"$'\t'"$T0"$'\t'"$W0"$'\t'"$M0"$'\t'"—"
NOTE=""; PICK="$ORIG"
if [[ "$BEST" == "$ORIG" ]]; then
  NOTE="계산해 보니 처음 순서가 이미 가장 좋다"
else
  IFS=$'\t' read -r T1 W1 M1 <<< "$(pa_run "$(pa_pipeline "$STEPS" "$BEST")" "$INPUT_FILE" "$PA_TMP/best.out")"; RUNS=$((RUNS + 1))
  if cmp -s "$PA_TMP/orig.out" "$PA_TMP/best.out"; then
    PICK="$BEST"
    ROWS+=$'\n'"고른 것"$'\t'"$(pa_join_names "$BEST")"$'\t'"$(pa_expected "$MEAS" "$BEST")"$'\t'"$T1"$'\t'"$W1"$'\t'"$M1"$'\t'"같음"
  else
    ROWS+=$'\n'"버림"$'\t'"$(pa_join_names "$BEST")"$'\t'"$(pa_expected "$MEAS" "$BEST")"$'\t'"$T1"$'\t'"$W1"$'\t'"$M1"$'\t'"다름"
    MILD="$(pa_order_mild "$MEAS")"
    if [[ "$MILD" != "$ORIG" && "$MILD" != "$BEST" ]]; then
      IFS=$'\t' read -r T2 W2 M2 <<< "$(pa_run "$(pa_pipeline "$STEPS" "$MILD")" "$INPUT_FILE" "$PA_TMP/mild.out")"; RUNS=$((RUNS + 1))
      if cmp -s "$PA_TMP/orig.out" "$PA_TMP/mild.out"; then
        PICK="$MILD"
        ROWS+=$'\n'"고른 것"$'\t'"$(pa_join_names "$MILD")"$'\t'"$(pa_expected "$MEAS" "$MILD")"$'\t'"$T2"$'\t'"$W2"$'\t'"$M2"$'\t'"같음"
        NOTE="고르기를 바꾸기 앞으로 당긴 순서는 답이 달라져 버렸다 — 이어진 고르기끼리만 바꾼 순서를 골랐다"
      else
        ROWS+=$'\n'"버림"$'\t'"$(pa_join_names "$MILD")"$'\t'"$(pa_expected "$MEAS" "$MILD")"$'\t'"$T2"$'\t'"$W2"$'\t'"$M2"$'\t'"다름"
      fi
    fi
    [[ "$PICK" != "$ORIG" ]] || NOTE="바꿀 수 있는 순서를 찾지 못함 — 계산이 고른 순서는 답이 달라졌다. 고르기가 앞의 바꾸기 결과에 기대면 그 줄에 after:이름 을 적어 다시 돌려라"
  fi
fi

# 4) 표
HEAD="입력 ${NIN}줄 · 단계 ${NSTEP}개 · 실행 ${RUNS}번 (순서를 전부 돌려 보면 $(pa_count_orders "$NSTEP")가지)"
pa_render "$MEAS" "$ROWS" "$(pa_hints "$MEAS" "$PICK")" "$HEAD"
printf '\n'
[[ -z "$NOTE" ]] || printf '\n%s\n' "$NOTE"
printf '\n알아 둘 것: 답이 같은지는 이 예시 입력에서만 확인했다. 예상 시간은 순서를 가리는 데만 쓴다(실제 시간과 크기가 다를 수 있다).\n'
