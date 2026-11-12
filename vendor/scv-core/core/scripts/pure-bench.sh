#!/usr/bin/env bash
# pure-bench.sh — 순수함수(와 셸에서 띄우는 명령 하나)의 시간 · 메모리 · GPU · 부른 횟수를 잰다.
# 계약 contracts/composition.md · 계획 20261111-wookiya1364-pure-bench-and-gate.
#
# 판단은 lib/pure-bench.sh 의 순수 함수가 하고, 여기는 사전 읽기 · 실행 · 쓰기만 한다.
#
# Usage:
#   pure-bench.sh targets [--catalog DIR] [--only NAME]…
#       사전에서 잴 목록을 낸다: "함수<탭>파일<탭>언어<탭>1배 인자<탭>4배 인자<탭>늘림(1/0)".
#       1배 = 예시를 25번 되풀이, 4배 = 100번. 늘릴 값이 없는 예시는 늘림 0 (늘려 재지 못함).
#
#   pure-bench.sh env
#       재는 환경 한 줄: 셸 버전 · 지역 설정 · GPU 읽는 도구.
#   pure-bench.sh run [--no-count] -- <명령…>
#       셸에서 띄우는 명령 하나를 감싸 잰다. 한 줄: "벽시계 초<탭>CPU 초<탭>메모리 MB<탭>GPU 사용률 %<탭>GPU 메모리 MB<탭>부른 횟수<탭>판정 잣대<탭>명령의 종료 코드".
#       판정 잣대: cpu(CPU 시간으로 본다) · wall-gpu(GPU 를 썼다 — 벽시계와 GPU 값으로 본다) · unmeasured(재지 못함).
#       잴 수 없는 값은 "-" (통과가 아니라 '재지 못함'). GPU 값은 컴퓨터 전체의 값이다.
#   pure-bench.sh fn [--catalog DIR] [--base DIR] [--only NAME]… [--scale 1|4]
#       사전의 함수를 그 예시(1배 또는 4배 입력)로 재서 줄마다:
#       "함수<탭>배<탭>되풀이<탭>회당 ms<탭>벽시계 초<탭>메모리 MB<탭>GPU 사용률<탭>GPU 메모리<탭>부른 횟수<탭>상태<탭>판정 잣대".
#       상태: ok · not-scalable(늘려 재지 못함) · load-failed(함수를 불러오지 못함) · not-shell(셸 함수가 아님) ·
#       too-slow(한 번 재는 데 SCV_PB_CALL_LIMIT 초 — 기본 60 — 를 넘겨 끊음).
#
#   pure-bench.sh composed [--catalog DIR] [--base DIR]
#       엮은 함수(다른 사전 함수를 2개 이상 부르는 사전 함수)를 "함수<탭>부르는 함수들" 줄로 낸다.
#   pure-bench.sh bench [--catalog DIR] [--base DIR] [--only NAME]… [--composed] [--tsv FILE] [--baseline FILE]
#       함수를 1배 · 4배 입력으로 재서 표를 낸다(비고 · 끝의 셈 포함). --composed 는 엮은 함수와 그것이 부르는 함수만
#       재고, 엮은 함수의 표(묶음 전체의 값 · 부품 값의 합)를 덧붙인다. --tsv 는 표의 줄을 파일에도 쓴다.
#       --baseline 은 '입력 4배에 8배를 넘는 함수' 목록 파일: 없으면 지금 값으로 만들고, 있으면 줄어든 이름은 내리고
#       새로 넘은 이름이 있으면 알리고 Exit 1 (목록에 넣지 않는다 — 고치거나, 받아들일지 사용자가 정한다).
#       값은 셸에 따라 다르므로 목록 파일은 셸 큰 버전마다 따로 둔다(예: scale-baseline.bash3).
#
#   pure-bench.sh compare (--before DIR | --before-ref REF) [--catalog DIR] [--base DIR] [--only NAME]…
#                         [--pairs N] [--full] [--budget SEC] [--accepted FILE] [--pending FILE]
#       고치기 전 코드(--before: 같은 상대 경로를 가진 폴더, --before-ref: 그 커밋의 코드)와 지금 코드를 번갈아 재서
#       한도로 가린다: 시간 1.2배 · 다른 프로그램을 부른 횟수(1번이라도) · 메모리 1.2배와 1MB · (--full) 입력 4배 배수 8배.
#       기본은 빠른 검사(세 쌍 — 넘으면 그 함수만 여섯 쌍으로 다시), --full 은 여섯 쌍 + 입력 4배.
#       --full 은 뚜렷하면 일찍 멈춘다(0.91.2+): 두 쌍 연속으로 뒤가 앞의 절반 이하이면 남은 쌍을 재지 않고,
#       4배 입력은 뒤를 먼저 재서 한도 안이면 앞은 재지 않는다(표의 앞 칸은 '-'). 비슷하거나 느려진 함수는 다 잰다.
#       한 번 재는 실행이 한도 시간(SCV_PB_CALL_LIMIT)에 끊기면 그 값은 '끊김'이다: 앞만 끊기면 통과, 뒤만 끊기면 한도 넘음.
#       SCV_PB_PAIRS_LOG=FILE 을 주면 함수마다 잰 쌍의 수를 "함수<탭>쌍" 으로 적는다(시험 · 살펴보기용).
#       --budget 초를 넘기면 남은 함수는 '재지 못함'으로 적는다. --accepted 는 사용자가 받아들인 것("함수<탭>이유들"),
#       --pending 은 한도를 넘은 것을 그 꼴로 쓸 파일. Exit 1 = 받아들이지 않은 한도 넘음이 있다.
#
#   pure-bench.sh turn-end --dir TURN_DIR      (턴 끝 훅이 부른다)
#       이번 턴에 고친 파일(TURN_DIR/.turn-plan/changed)에 사전 함수가 있으면, 본문이 달라진 함수와 그것을 부르는 엮은
#       함수만 빠르게 견준다 — 기준은 이 일을 시작하기 전의 코드(작업 가지가 갈라진 지점). 사전 함수를 고치지 않은 턴은
#       아무것도 재지 않는다. 출력: "PURE_BENCH: pass|block|off|pass-unanswered", "PURE_BENCH_RUNS: N",
#       막을 때 "PURE_BENCH_REASON: …". 같은 턴에 두 번 막은 뒤에는 지나가고 기록에 한 줄 남긴다.
#   pure-bench.sh plan-end                     (계획을 끝내기 전에 한 번)
#       이 일을 시작한 뒤 달라진 사전 함수 전부를 꼼꼼히(여섯 쌍 · 입력 4배) 견준다. Exit 1 = 한도 넘음.
#   pure-bench.sh accept --question Q --answer A   (선택 창 답 훅이 부른다)
#       질문이 "[재는 검사] 함수 이름 —" 으로 시작하고 답이 "이대로"로 시작하면, 그 함수의 넘은 값을 받아들인 것으로 적는다
#       (진행 중 계획 폴더의 pure-bench-accepted.tsv). 그 값보다 더 나빠지면 다시 묻는다.
#
# 설정: SCV_PURE_BENCH=off 로 턴 끝 · 계획 끝 검사를 끈다(기본 on). SCV_PR_BASE 가 있으면 그 가지가 기준이다.
# 환경: SCV_PB_GPU_TOOL=none|ioreg|nvidia 로 GPU 읽는 도구를 정한다(기본: 있는 것을 찾는다).
# 잰 값은 이 스크립트를 돌린 셸과 지역 설정의 값이다 — 같은 함수가 bash 3.2 와 bash 5 에서 열 배 넘게 다를 수 있다
# (2026-11-11: 낱말 나누기 한 번에 22ms 대 1.8ms). 앞뒤를 견줄 때는 같은 셸로 잰다. `env` 로 그 셸을 본다.
# Exit: 0 통과 · 2 사용법 오류
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
# shellcheck source=lib/pure-catalog.sh
source "$SCRIPT_DIR/lib/pure-catalog.sh"
# shellcheck source=lib/pure-bench.sh
source "$SCRIPT_DIR/lib/pure-bench.sh"
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true
# shellcheck source=lib/pr-flow.sh
source "$SCRIPT_DIR/lib/pr-flow.sh" 2>/dev/null || true

# @effect read_catalog
# 이유: 사전 파일을 읽는다 — 파이프라인의 입구(차례 파일은 뺀다)
read_catalog() {
  local f
  for f in "$1"/*.md; do
    [[ -f "$f" && "${f##*/}" != INDEX.md ]] && cat "$f"
  done
  return 0
}

# 함수를 부르는 새 셸(_drive)은 부모의 임시 폴더를 물려받는다 — 재는 일마다 폴더와 가짜 명령 묶음을 새로 만들지 않게.
if [[ "${1:-}" == _drive && -n "${PB_PARENT_TMP:-}" && -d "${PB_PARENT_TMP:-}" ]]; then PB_TMP="$PB_PARENT_TMP"; PB_OWN_TMP=0
else PB_TMP="$(mktemp -d "${TMPDIR:-/tmp}/scv-pure-bench.XXXXXX")" || exit 2; PB_OWN_TMP=1; export PB_PARENT_TMP="$PB_TMP"; fi
PB_SAMPLER=""
# @effect pb_cleanup
# 이유: 끝날 때 GPU 표본기를 끄고 임시 폴더를 지운다 — 남은 과정이 컴퓨터를 붐비게 하지 않게
pb_cleanup() {
  [[ -z "$PB_SAMPLER" ]] || { kill "$PB_SAMPLER" 2>/dev/null; wait "$PB_SAMPLER" 2>/dev/null; }
  [[ "$PB_OWN_TMP" != 1 ]] || rm -rf "$PB_TMP"
}
trap pb_cleanup EXIT
trap 'exit 143' TERM INT      # 끊겨도 치우고 끝낸다

# @effect pb_gpu_tool
# 이유: 이 컴퓨터에서 GPU 를 읽을 도구를 찾는다(환경 값이 있으면 그것) — ioreg | nvidia | none
pb_gpu_tool() {
  case "${SCV_PB_GPU_TOOL:-}" in ioreg|nvidia|none) printf '%s' "$SCV_PB_GPU_TOOL"; return ;; esac
  if command -v ioreg >/dev/null 2>&1 && [[ -n "$(pb_parse_ioreg "$(ioreg -r -d 1 -w 0 -c IOAccelerator 2>/dev/null)")" ]]; then printf ioreg
  elif command -v nvidia-smi >/dev/null 2>&1; then printf nvidia
  else printf none; fi
}

# @effect pb_gpu_read
# 이유: GPU 의 지금 값을 한 번 읽는다 — "사용률<탭>메모리 MB" (도구가 없으면 빈 글)
pb_gpu_read() {
  case "$1" in
    ioreg)  pb_parse_ioreg "$(ioreg -r -d 1 -w 0 -c IOAccelerator 2>/dev/null)" ;;
    nvidia) pb_parse_nvidia "$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null)" ;;
  esac
}

# @effect pb_timed
# 이유: 명령을 운영체제의 시간 재는 명령으로 감싸 돌리고 그 보고를 파일에 쓴다(없으면 셸의 time — 메모리는 재지 못함)
pb_timed() {
  local report="$1"; shift
  if [[ -x /usr/bin/time ]] && /usr/bin/time -l -p -o "$report" true >/dev/null 2>&1; then
    /usr/bin/time -l -p -o "$report" "$@" >/dev/null 2>&1          # BSD(맥)
  elif [[ -x /usr/bin/time ]] && /usr/bin/time -v -o "$report" true >/dev/null 2>&1; then
    /usr/bin/time -v -o "$report" "$@" >/dev/null 2>&1             # GNU(리눅스)
  else
    { TIMEFORMAT=$'real %R\nuser %U\nsys %S'; time "$@" >/dev/null 2>&1; } 2> "$report"
  fi
}

# @effect run_measured
# 이유: 명령 하나를 돌려 잰다 — "벽시계<탭>CPU<탭>메모리<탭>GPU 사용률<탭>GPU 메모리<탭>GPU 사용률 오름" (파이프라인의 입구)
run_measured() {
  local tool="$1" base="" before="" samples="$PB_TMP/gpu.samples" sum; shift
  : > "$samples"
  if [[ "$tool" != none ]]; then
    before="$(pb_gpu_read "$tool")"; base="${before#*$'\t'}"
    ( while :; do pb_gpu_read "$tool"; echo; sleep 0.2; done >> "$samples" ) &
    PB_SAMPLER=$!
  fi
  pb_timed "$PB_TMP/time.report" "$@"; echo "$?" > "$PB_TMP/exit"
  if [[ -n "$PB_SAMPLER" ]]; then kill "$PB_SAMPLER" 2>/dev/null; wait "$PB_SAMPLER" 2>/dev/null; PB_SAMPLER=""; fi
  sum=$'-\t-\t-'; [[ "$tool" == none ]] || sum="$(pb_gpu_summary "$(grep . "$samples")" "${base:-0}" "${before%%$'\t'*}")"
  printf '%s\t%s' "$(pb_parse_time "$(cat "$PB_TMP/time.report" 2>/dev/null)")" "$sum"
}

# @effect pb_load_now
# 이유: 지금 컴퓨터가 얼마나 붐비는지 잰다 — CPU 만 쓰는 짧은 반복의 벽시계 ÷ CPU × 100 (100 = 한가함)
pb_load_now() {
  local w c
  pb_timed "$PB_TMP/load.report" "$BASH" -c 'i=0; while [[ $i -ne 150000 ]]; do i=$((i + 1)); done'
  IFS=$'\t' read -r w c _ <<< "$(pb_parse_time "$(cat "$PB_TMP/load.report" 2>/dev/null)")"
  w="$(pb_to_milli "$w")" || w=0; c="$(pb_to_milli "$c")" || c=0
  if [[ $c -eq 0 ]]; then printf 100; else printf '%s' "$(( w * 100 / c ))"; fi
}

# @effect pb_measure_name
# 이유: 잰 값으로 판정 잣대를 고른다 — CPU 가 아닌 답이 나오면 붐빔을 한 번 재서 다시 고른다(붐비는 컴퓨터를 GPU 신호로 잘못 읽지 않게)
pb_measure_name() {
  local name; name="$(pb_pick_measure "$1" "$2" "$3" "$4" 100)"
  [[ "$name" == cpu ]] || name="$(pb_pick_measure "$1" "$2" "$3" "$4" "$(pb_load_now)")"
  printf '%s' "$name"
}

# @effect pb_bodies
# 이유: 사전 함수들이 있는 파일을 읽어 함수마다 "@@ 이름" 줄과 본문을 낸다 — 누가 누구를 부르는지 보려는 입구
pb_bodies() {
  local base="$1" files=() f seen=$'\n'
  while IFS=$'\x1d' read -r _ f _; do
    [[ -n "$f" && -f "$base/$f" ]] || continue
    case "$seen" in *$'\n'"$f"$'\n'*) continue ;; esac
    seen+="$f"$'\n'; files+=("$base/$f")
  done <<< "$(tr '\t' '\035' <<< "$2")"
  [[ ${#files[@]} -eq 0 ]] && return 0
  # 한 줄짜리 함수(이름() { … })는 그 줄의 나머지가 본문이다.
  LC_ALL=C awk '/^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/ {
                  name = $0; sub(/\(\).*/, "", name); print "@@ " name
                  rest = $0; sub(/^[^{]*\{/, "", rest); on = 1
                  if (rest ~ /\}[ \t]*$/) on = 0
                  if (rest ~ /[^ \t]/) print rest
                  next
                }
                on && /^\}/ { on = 0; next }
                on { print }' "${files[@]}"
}

# @effect pb_shim_dir
# 이유: 이름만 빌린 가짜 명령 묶음을 만든다 — 불린 이름을 한 줄 적고 진짜 명령을 돌린다(부른 횟수를 세는 장치)
pb_shim_dir() {
  local dir="$PB_TMP/shim" d f
  [[ -d "$dir" ]] && { printf '%s' "$dir"; return; }
  mkdir -p "$dir/.bin"
  cat > "$dir/.bin/shim" <<'SHIM'
#!/bin/sh
n="${0##*/}"; echo "$n" >> "$PB_COUNT"
IFS=:
for d in $PB_REALPATH; do [ -x "$d/$n" ] && [ ! -d "$d/$n" ] && exec "$d/$n" "$@"; done
echo "$n: not found" >&2; exit 127
SHIM
  chmod +x "$dir/.bin/shim"
  if command -v perl >/dev/null 2>&1; then
    perl -e 'my $dir = shift; for my $d (split /:/, $ENV{PATH}) { opendir(my $h, $d) or next; for (readdir $h) { next if /^\./; symlink(".bin/shim", "$dir/$_") unless -e "$dir/$_" || -l "$dir/$_" } }' "$dir"
  else
    local IFS=:
    for d in $PATH; do for f in "$d"/*; do [[ -e "$dir/${f##*/}" ]] || ln -s .bin/shim "$dir/${f##*/}" 2>/dev/null; done; done
  fi
  printf '%s' "$dir"
}

# @effect pb_count_execs
# 이유: 명령을 한 번 더 돌려, 그 명령이 이름으로 부른 다른 프로그램의 수를 센다(시간 재기와 따로 — 세는 장치가 시간을 흐린다)
pb_count_execs() {
  local shim count="$PB_TMP/count"; shim="$(pb_shim_dir)"; : > "$count"
  PB_COUNT="$count" PB_REALPATH="$PATH" PATH="$shim:$PATH" "$@" >/dev/null 2>&1
  grep -c . "$count"
}

# @effect pb_drive
# 이유: 사전의 함수 하나를 불러와 인자 글로 여러 번 부르고, 그 앞뒤의 CPU 시간을 파일에 쓴다(새 셸에서 돈다)
pb_drive() {
  set +eu +o pipefail
  local base="$1" rel="$2" fn="$3" args="$4" reps="$5" out="$6" count="${7:-}" answer="${8:-}" r
  case "$rel" in
    lib/*|*/lib/*) source "$base/$rel" ;;
    *) eval "$(LC_ALL=C awk -v fn="$fn" '$0 ~ "^"fn"\\(\\)[[:space:]]*\\{" {on=1} on {print} on && /^\}$/ {exit}' "$base/$rel")" ;;
  esac
  declare -F "$fn" >/dev/null || exit 3
  # 지킴이: 재는 일이 한도(기본 60초)를 넘기면 표시를 남기고 이 과정을 끊는다 — 한 함수가 전체 재기를 붙잡지 않게.
  # 이 과정은 신호를 받으면 바로 끝나야 한다(잡아 두면 부르던 명령이 끝날 때까지 기다린다). 지킴이는 기다림을
  # 자식으로 두고 wait 하므로, 일이 먼저 끝나 지킴이를 끌 때 기다림도 함께 끝난다(남는 과정 없음).
  trap - TERM INT
  ( trap 'kill "$nap" 2>/dev/null; exit 0' TERM
    sleep "${SCV_PB_CALL_LIMIT:-60}" & nap=$!
    wait "$nap" && { : > "$out.slow"; kill -TERM "$$" 2>/dev/null; } ) >/dev/null 2>&1 &
  local guard=$!
  trap 'kill "$guard" 2>/dev/null; pb_cleanup' EXIT
  if [[ "$args" == *"<<<"* ]]; then pb_call() { eval "$fn $args"; }; else pb_call() { eval "$fn $args" </dev/null; }; fi
  if [[ -n "$answer" ]]; then     # 답만 낸다 — 앞뒤의 답이 같은지 보려는 실행
    pb_call > "$answer" 2>/dev/null; echo "[$?]" >> "$answer"
    exit 0
  fi
  if [[ -n "$count" ]]; then      # 세는 실행 — 부르는 동안만 가짜 명령 묶음을 앞에 둔다
    local shim real="$PATH"; shim="$(pb_shim_dir)"; : > "$count"
    export PB_COUNT="$count" PB_REALPATH="$real"
    PATH="$shim:$real"; pb_call >/dev/null 2>&1; PATH="$real"
    exit 0
  fi
  times > "$out.a"
  for (( r = 0; r < reps; r++ )); do pb_call >/dev/null 2>&1; done
  times > "$out.b"
  exit 0
}

# @effect pb_measure_fn
# 이유: 사전의 함수 하나를 한 배(1 또는 4)의 입력으로 재서 한 줄을 낸다 — 되풀이 수를 맞추고, 시간 · 메모리 · GPU · 부른 횟수를 모은다
pb_measure_fn() {
  local tool="$1" base="$2" name="$3" rel="$4" args="$5" scale="$6" reps=1 try cpu="" m ms r2 wall tcpu rss gutil gmem grise out="$PB_TMP/drive"
  # 한 번부터 잰다 — 한 번에 몇 초가 걸리는 함수를 여러 번 부르지 않게. 짧으면 되풀이 수를 늘려 다시 잰다.
  for try in 1 2 3; do
    rm -f "$out.slow"
    m="$(run_measured "$tool" "$BASH" "$0" _drive "$base" "$rel" "$name" "$args" "$reps" "$out")"
    if [[ -e "$out.slow" ]]; then rm -f "$out.slow" "$out.a" "$out.b"; printf '%s\t%s\t-\t-\t-\t-\t-\t-\t-\ttoo-slow\t-\n' "$name" "$scale"; return; fi
    [[ -s "$out.b" ]] || { printf '%s\t%s\t-\t-\t-\t-\t-\t-\t-\tload-failed\t-\n' "$name" "$scale"; return; }
    cpu="$(LC_ALL=C awk -v a="$(pb_times_secs "$(cat "$out.a")")" -v b="$(pb_times_secs "$(cat "$out.b")")" 'BEGIN { printf "%.3f", b - a }')"
    r2="$(pb_reps_next "$cpu" "$reps")"; rm -f "$out.a" "$out.b"
    [[ "$r2" == "$reps" ]] && break
    [[ $try -lt 3 ]] && reps="$r2"
  done
  ms="$(LC_ALL=C awk -v c="$cpu" -v r="$reps" 'BEGIN { printf "%.3f", c * 1000 / r }')"
  "$BASH" "$0" _drive "$base" "$rel" "$name" "$args" 1 "$out" "$PB_TMP/fn.count" >/dev/null 2>&1
  IFS=$'\t' read -r wall tcpu rss gutil gmem grise <<< "$m"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tok\t%s\n' "$name" "$scale" "$reps" "$ms" "$wall" "$rss" "$gutil" "$gmem" "$(grep -c . "$PB_TMP/fn.count")" "$(pb_measure_name "$wall" "$tcpu" "$gmem" "$grise")"
}

# @effect pb_fixed_run
# 이유: 되풀이 수를 정해 둔 채 함수를 한 번 재서 "회당 ms<탭>메모리 MB<탭>벽시계 초"를 낸다 — 앞뒤를 번갈아 잴 때(GPU 표본 없이, 가볍게). 한도 시간에 끊기면 첫 칸이 too-slow
pb_fixed_run() {
  local out="$PB_TMP/fx" cpu w c rss
  rm -f "$out.a" "$out.b" "$out.slow"
  pb_timed "$PB_TMP/fx.report" "$BASH" "$0" _drive "$1" "$3" "$2" "$4" "$5" "$out"
  # 한도 시간에 끊겼으면 빈칸이 아니라 too-slow 를 낸다(0.91.2+) — 판정이 '못 잼'과 '너무 느림'을 가릴 수 있게
  if [[ -e "$out.slow" ]]; then rm -f "$out.slow" "$out.a" "$out.b"; printf 'too-slow\t-\t-'; return 0; fi
  [[ -s "$out.b" ]] || { printf -- '-\t-\t-'; return 0; }
  cpu="$(LC_ALL=C awk -v a="$(pb_times_secs "$(cat "$out.a")")" -v b="$(pb_times_secs "$(cat "$out.b")")" -v r="$5" 'BEGIN { printf "%.3f", (b - a) * 1000 / r }')"
  IFS=$'\t' read -r w c rss <<< "$(pb_parse_time "$(cat "$PB_TMP/fx.report" 2>/dev/null)")"
  printf '%s\t%s\t%s' "$cpu" "$rss" "$w"
}

# @effect pb_compare_fn
# 이유: 한 함수를 앞 코드와 뒤 코드에서 번갈아 재서 앞뒤 잰 줄 하나를 낸다 — 답이 같은지 · 부른 횟수 · 시간 쌍 · 메모리 · (꼼꼼히) 입력 4배
pb_compare_fn() {
  local tool="$1" before="$2" after="$3" name="$4" rel="$5" a1="$6" a4="$7" sc="$8" pairs="$9" full="${10}"
  local LA LB reps nm eb ea mb ma i vb="" va="" r sb="-" sa="-" L st=ok a b a0 m0 bslow np
  if ! grep -q "^$name()" "$before/$rel" 2>/dev/null; then st=new; fi
  LA="$(pb_measure_fn "$tool" "$after" "$name" "$rel" "$a1" 1)"
  [[ "$LA" == *$'\tok\t'* ]] || { printf '%s\tload-failed\t-\t-\t-\t-\t-\t-\t-\t-\t-\n' "$name"; return 0; }
  IFS=$'\x1d' read -r _ _ reps va _ ma _ _ ea _ nm <<< "$(tr '\t' '\035' <<< "$LA")"
  if [[ "$st" == new ]]; then
    if [[ "$full" == 1 && "$sc" == 1 ]]; then L="$(pb_measure_fn "$tool" "$after" "$name" "$rel" "$a4" 4)"; sa="$(pb_scale_ratio "$va" "$(cut -f4 <<< "$L")")"; fi
    printf '%s\tnew\t%s\t-\t%s\t-\t%s\t-\t%s\t-\t%s\n' "$name" "$nm" "$va" "$ea" "$ma" "$sa"; return 0
  fi
  # 답이 달라졌으면 다른 일을 하게 된 것 — 견주지 않는다
  "$BASH" "$0" _drive "$before" "$rel" "$name" "$a1" 1 "$PB_TMP/x" "" "$PB_TMP/ans.b" >/dev/null 2>&1
  "$BASH" "$0" _drive "$after"  "$rel" "$name" "$a1" 1 "$PB_TMP/x" "" "$PB_TMP/ans.a" >/dev/null 2>&1
  if ! cmp -s "$PB_TMP/ans.b" "$PB_TMP/ans.a"; then printf '%s\tdifferent-answer\t-\t-\t-\t-\t-\t-\t-\t-\t-\n' "$name"; return 0; fi
  # 부른 횟수(앞) — 뒤는 위에서 셌다
  "$BASH" "$0" _drive "$before" "$rel" "$name" "$a1" 1 "$PB_TMP/x" "$PB_TMP/cnt.b" >/dev/null 2>&1; eb="$(grep -c . "$PB_TMP/cnt.b")"
  # 시간 — 같은 되풀이 수로 앞 · 뒤를 번갈아.
  # 되풀이 수는 뒤(지금 코드)에 맞춰 정해졌다. 앞이 훨씬 느리면 그 횟수가 앞에는 너무 많다 — 그래서(0.91.2+):
  #   · 앞이 한도 시간에 끊기면 다시 재지 않는다(b 는 too-slow, 뒤 값은 처음 잰 것을 쓴다).
  #   · 꼼꼼히 잴 때, 두 쌍 연속으로 뒤가 앞의 절반 이하이면 남은 쌍을 재지 않는다(pb_pairs_enough).
  a0="$va"; m0="$ma"; vb=""; va=""; mb=0; ma=0; bslow=0; np=0
  for (( i = 0; i != pairs; i++ )); do
    IFS=$'\t' read -r r L _ <<< "$(pb_fixed_run "$before" "$name" "$rel" "$a1" "$reps")"
    if [[ "$r" == too-slow ]]; then bslow=1; break; fi
    vb="$vb $r"; [[ "$L" == "-" ]] || mb="$(LC_ALL=C awk -v a="$mb" -v b="$L" 'BEGIN { print (b + 0 > a + 0) ? b : a }')"
    IFS=$'\t' read -r r L _ <<< "$(pb_fixed_run "$after"  "$name" "$rel" "$a1" "$reps")"; va="$va $r"; [[ "$L" == "-" ]] || ma="$(LC_ALL=C awk -v a="$ma" -v b="$L" 'BEGIN { print (b + 0 > a + 0) ? b : a }')"
    np=$((np + 1))
    [[ "$full" == 1 && "$(pb_pairs_enough "$vb" "$va")" == 1 ]] && break
  done
  [[ -z "${SCV_PB_PAIRS_LOG:-}" ]] || printf '%s\t%s\n' "$name" "$np" >> "$SCV_PB_PAIRS_LOG"
  b="$(pb_median "$vb")"; a="$(pb_median "$va")"
  [[ "$mb" != 0 ]] || mb="-"
  [[ "$ma" != 0 ]] || ma="$m0"
  if [[ $bslow -eq 1 ]]; then b=too-slow; [[ "$a" != "-" ]] || a="$a0"; fi
  if [[ "$full" == 1 && "$sc" == 1 ]]; then
    # 4배 입력은 뒤를 먼저 잰다. 뒤 배수가 한도 안이면 앞의 4배 값은 판정에 쓰이지 않는다 — 재지 않는다(pb_scale_over).
    IFS=$'\t' read -r r _ _ <<< "$(pb_fixed_run "$after"  "$name" "$rel" "$a4" "$(( reps / 4 + 1 ))")"
    if [[ "$r" == too-slow ]]; then sa=too-slow; else sa="$(pb_scale_ratio "$a" "$r")"; fi
    if [[ "$(pb_scale_over "$sa")" == 1 ]]; then
      if [[ $bslow -eq 1 ]]; then sb=too-slow
      else
        IFS=$'\t' read -r r _ _ <<< "$(pb_fixed_run "$before" "$name" "$rel" "$a4" "$(( reps / 4 + 1 ))")"
        if [[ "$r" == too-slow ]]; then sb=too-slow; else sb="$(pb_scale_ratio "$b" "$r")"; fi
      fi
    fi
  fi
  printf '%s\tok\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$nm" "$b" "$a" "$eb" "$ea" "$mb" "$ma" "$sb" "$sa"
}

# @effect pb_setting
# 이유: 설정 파일에서 값을 읽는다(없으면 둘째 인자)
pb_setting() {
  local v=""
  declare -F settings_get >/dev/null 2>&1 && v="$(settings_get "$1" 2>/dev/null | tr -d '"' | tr -d "'" || true)"
  printf '%s' "${v:-${2:-}}"
}

# @effect pb_before_ref
# 이유: 이 일을 시작하기 전의 코드가 있는 커밋을 찾는다 — 기준 가지(설정 > 원격의 기본 가지 > main)와 갈라진 지점, 그 가지 위에서 일하면 마지막 커밋
pb_before_ref() {
  local root="$1" head base ref
  head="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"; head="${head#origin/}"
  base="$(scv_pr_base_branch "" "$(pb_setting SCV_PR_BASE "")" "$head" 2>/dev/null)"; base="${base:-main}"
  for ref in "origin/$base" "$base"; do
    ref="$(git -C "$root" merge-base HEAD "$ref" 2>/dev/null)" && [[ -n "$ref" ]] && { printf '%s' "$ref"; return 0; }
  done
  git -C "$root" rev-parse --verify --quiet HEAD 2>/dev/null
}

# @effect pb_gate
# 이유: 고친 파일들에서 달라진 사전 함수와 그것을 부르는 엮은 함수를 찾아 앞뒤를 견준다 — 턴 끝(빠르게)과 계획 끝(꼼꼼히)이 함께 쓴다
pb_gate() {
  local mode="$1" root="$2" files="$3" cat base ref prefix f rel hit="" t names bodies_a bodies_b changed calls callers only=() n acc pend out rc
  cat="$root/scv/core/catalog/pure"
  [[ -d "$cat" ]] || { echo "PURE_BENCH: pass"; echo "PURE_BENCH_RUNS: 0"; return 0; }
  base="$root"; [[ -d "$root/core/scripts" && -f "$cat/INDEX.md" ]] && grep -q -- '- 위치: scripts/' "$cat"/*.md 2>/dev/null && base="$root/core"
  prefix="${base#"$root"}"; prefix="${prefix#/}"; prefix="${prefix:+$prefix/}"
  # 값싼 앞 검사: 고친 파일에 사전 함수가 하나라도 있는가 — 없으면 여기서 끝(아무것도 재지 않는다)
  while IFS= read -r f; do
    [[ -n "$f" && "$f" == "$prefix"* ]] || continue
    rel="${f#"$prefix"}"
    grep -q -F -- "- 위치: $rel · " "$cat"/*.md 2>/dev/null && hit+="$rel"$'\n'
  done <<< "$files"
  [[ -n "$hit" ]] || { echo "PURE_BENCH: pass"; echo "PURE_BENCH_RUNS: 0"; return 0; }
  ref="$(pb_before_ref "$root")" || { echo "PURE_BENCH: pass"; echo "PURE_BENCH_RUNS: 0"; echo "PURE_BENCH_NOTE: git 저장소가 아니라 견줄 앞 코드가 없다"; return 0; }
  # 달라진 함수: 앞 코드와 뒤 코드의 본문을 견준다
  t="$(pb_targets "$(read_catalog "$cat")" "")"
  mkdir -p "$PB_TMP/gate"
  bodies_a="$(pb_bodies "$base" "$t")"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    mkdir -p "$PB_TMP/gate/$(dirname "$rel")"
    git -C "$root" show "$ref:$prefix$rel" > "$PB_TMP/gate/$rel" 2>/dev/null || rm -f "$PB_TMP/gate/$rel"
  done <<< "$(cut -f2 <<< "$t" | sort -u)"
  bodies_b="$(pb_bodies "$PB_TMP/gate" "$t")"
  names="$(cut -f1 <<< "$t")"
  changed="$(pb_changed_names "$bodies_b" "$bodies_a" | grep -F -x -f <(printf '%s\n' "$names") || true)"
  [[ -n "$changed" ]] || { echo "PURE_BENCH: pass"; echo "PURE_BENCH_RUNS: 0"; return 0; }
  calls="$(pb_composed "$(pb_calls "$bodies_a" "$names")")"
  callers="$(pb_callers "$calls" "$changed")"
  while IFS= read -r n; do [[ -n "$n" ]] && only+=(--only "$n"); done <<< "$(printf '%s\n%s\n' "$changed" "$callers" | sort -u)"
  n=$(( ${#only[@]} / 2 ))
  acc="$PB_TMP/accepted"; cat "$root"/scv/promote/*/pure-bench-accepted.tsv "$root/${SCV_JOURNAL_DIR:-scv/journal}/.pure-bench-accepted" > "$acc" 2>/dev/null || true
  pend="$root/${SCV_JOURNAL_DIR:-scv/journal}/.pure-bench-pending"
  if [[ "$mode" == full ]]; then
    out="$("$BASH" "$0" compare --before-ref "$ref" --base "$base" --catalog "$cat" "${only[@]}" --full --accepted "$acc" --pending "$pend" 2>&1)"; rc=$?
  else
    out="$("$BASH" "$0" compare --before-ref "$ref" --base "$base" --catalog "$cat" "${only[@]}" --budget "${SCV_PB_BUDGET:-35}" --accepted "$acc" --pending "$pend" 2>&1)"; rc=$?
  fi
  PB_GATE_OUT="$out"; PB_GATE_N="$n"
  return "$rc"
}

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
if [[ "$CMD" == _drive ]]; then pb_drive "$@"; fi
CATALOG="$( cd "$CORE_DIR/.." && pwd )/scv/core/catalog/pure"; BASE="$CORE_DIR"; ONLY=""; SCALE=1; COUNT=1; COMPOSED=0; TSV=""; BEFORE=""; BEFORE_REF=""; PAIRS=""; FULL=0; BUDGET=0; ACCEPTED=""; PENDING=""; TDIR=""; Q=""; A=""; BASELINE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog)  CATALOG="${2:-}"; shift 2 ;;
    --base)     BASE="${2:-}"; shift 2 ;;
    --only)     ONLY+="${2:-}"$'\n'; shift 2 ;;
    --scale)    SCALE="${2:-}"; shift 2 ;;
    --no-count) COUNT=0; shift ;;
    --composed) COMPOSED=1; shift ;;
    --before)     BEFORE="${2:-}"; shift 2 ;;
    --before-ref) BEFORE_REF="${2:-}"; shift 2 ;;
    --pairs)      PAIRS="${2:-}"; shift 2 ;;
    --full)       FULL=1; shift ;;
    --budget)     BUDGET="${2:-0}"; shift 2 ;;
    --accepted)   ACCEPTED="${2:-}"; shift 2 ;;
    --pending)    PENDING="${2:-}"; shift 2 ;;
    --dir)        TDIR="${2:-}"; shift 2 ;;
    --question)   Q="${2:-}"; shift 2 ;;
    --answer)     A="${2:-}"; shift 2 ;;
    --tsv)      TSV="${2:-}"; shift 2 ;;
    --baseline) BASELINE="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *) echo "pure-bench: 모르는 인자: $1" >&2; exit 2 ;;
  esac
done

case "$CMD" in
  env)
    printf 'bash %s · LC_ALL=%s · LANG=%s · GPU 도구 %s\n' "$BASH_VERSION" "${LC_ALL:-}" "${LANG:-}" "$(pb_gpu_tool)" ;;
  targets)
    [[ -d "$CATALOG" ]] || { echo "pure-bench: 사전 폴더가 없다: $CATALOG" >&2; exit 2; }
    pb_targets "$(read_catalog "$CATALOG")" "${ONLY%$'\n'}" ;;
  run)
    [[ $# -gt 0 ]] || { echo "pure-bench: run 뒤에 -- <명령…> 이 있어야 한다" >&2; exit 2; }
    TOOL="$(pb_gpu_tool)"
    M="$(run_measured "$TOOL" "$@")"
    N="-"; [[ $COUNT -eq 0 ]] || N="$(pb_count_execs "$@")"
    IFS=$'\t' read -r wall tcpu rss gutil gmem grise <<< "$M"
    RC="$(cat "$PB_TMP/exit" 2>/dev/null)"; RC="${RC:-0}"
    [[ "$RC" == 0 ]] || echo "pure-bench: 잰 명령이 종료 코드 $RC 로 끝났다 — 아래 값은 실패한 실행의 값이다" >&2
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$wall" "$tcpu" "$rss" "$gutil" "$gmem" "$N" "$(pb_measure_name "$wall" "$tcpu" "$gmem" "$grise")" "$RC" ;;
  fn)
    [[ -d "$CATALOG" ]] || { echo "pure-bench: 사전 폴더가 없다: $CATALOG" >&2; exit 2; }
    [[ "$SCALE" == 1 || "$SCALE" == 4 ]] || { echo "pure-bench: --scale 은 1 또는 4" >&2; exit 2; }
    TOOL="$(pb_gpu_tool)"
    while IFS=$'\x1d' read -r name rel lang a1 a4 sc; do
      [[ -n "$name" ]] || continue
      if [[ "$lang" != sh ]]; then printf '%s\t%s\t-\t-\t-\t-\t-\t-\t-\tnot-shell\t-\n' "$name" "$SCALE"; continue; fi
      if [[ "$SCALE" == 4 && "$sc" != 1 ]]; then printf '%s\t4\t-\t-\t-\t-\t-\t-\t-\tnot-scalable\t-\n' "$name"; continue; fi
      if [[ "$SCALE" == 4 ]]; then pb_measure_fn "$TOOL" "$BASE" "$name" "$rel" "$a4" 4
      else pb_measure_fn "$TOOL" "$BASE" "$name" "$rel" "$a1" 1; fi
    done <<< "$(pb_targets "$(read_catalog "$CATALOG")" "${ONLY%$'\n'}" | tr '\t' '\035')" ;;
  compare)
    [[ -d "$CATALOG" ]] || { echo "pure-bench: 사전 폴더가 없다: $CATALOG" >&2; exit 2; }
    if [[ -n "$BEFORE_REF" ]]; then
      # 그 커밋의 코드를 임시 폴더에 푼다 — 지금 코드와 같은 상대 경로로
      PREFIX="$(git -C "$BASE" rev-parse --show-prefix 2>/dev/null)" || { echo "pure-bench: git 저장소가 아니다: $BASE" >&2; exit 2; }
      TOP="$(git -C "$BASE" rev-parse --show-toplevel)"
      # 잴 함수가 있는 파일만 꺼낸다. 그 커밋에 없는 파일의 함수는 '새 함수'가 된다.
      while IFS=$'\x1d' read -r _ rel _; do
        [[ -n "$rel" && ! -e "$PB_TMP/before/$PREFIX$rel" ]] || continue
        mkdir -p "$PB_TMP/before/$PREFIX$(dirname "$rel")"
        git -C "$TOP" show "$BEFORE_REF:$PREFIX$rel" > "$PB_TMP/before/$PREFIX$rel" 2>/dev/null || rm -f "$PB_TMP/before/$PREFIX$rel"
      done <<< "$(pb_targets "$(read_catalog "$CATALOG")" "${ONLY%$'\n'}" | tr '\t' '\035')"
      mkdir -p "$PB_TMP/before/${PREFIX%/}"
      BEFORE="$PB_TMP/before/${PREFIX%/}"
    fi
    [[ -n "$BEFORE" && -d "$BEFORE" ]] || { echo "pure-bench: --before DIR 또는 --before-ref REF 가 있어야 한다" >&2; exit 2; }
    [[ -n "$PAIRS" ]] || { if [[ $FULL -eq 1 ]]; then PAIRS=6; else PAIRS=3; fi; }
    TOOL="$(pb_gpu_tool)"; LINES=""; VERD=""; ACC=""; [[ -z "$ACCEPTED" || ! -f "$ACCEPTED" ]] || ACC="$(cat "$ACCEPTED")"
    T0=$SECONDS; NFAIL=0; PEND=""
    while IFS=$'\x1d' read -r name rel lang a1 a4 sc; do
      [[ -n "$name" && "$lang" == sh ]] || continue
      if [[ "$BUDGET" -gt 0 && $(( SECONDS - T0 )) -ge "$BUDGET" ]]; then
        L="$(printf '%s\tnot-reached\t-\t-\t-\t-\t-\t-\t-\t-\t-' "$name")"
      else
        L="$(pb_compare_fn "$TOOL" "$BEFORE" "$BASE" "$name" "$rel" "$a1" "$a4" "$sc" "$PAIRS" "$FULL")"
        V="$(pb_compare "$L")"
        # 빠른 검사에서 시간만으로 넘었으면 여섯 쌍으로 한 번 더 재서 확인한다
        if [[ $FULL -eq 0 && "$PAIRS" -lt 6 && "$V" == *$'\tfail\t'*time=* ]]; then
          L="$(pb_compare_fn "$TOOL" "$BEFORE" "$BASE" "$name" "$rel" "$a1" "$a4" "$sc" 6 0)"
        fi
      fi
      V="$(pb_compare "$L")"
      if [[ "$V" == *$'\tfail\t'* ]]; then
        WHY="${V##*$'\t'}"; WAS=""
        while IFS=$'\t' read -r an aw; do [[ "$an" == "$name" ]] && WAS="$aw"; done <<< "$ACC"
        if [[ -n "$WAS" ]] && pb_accept_covers "$WAS" "$WHY"; then V="$(printf '%s\taccepted\t%s' "$name" "$WHY")"
        else NFAIL=$((NFAIL + 1)); PEND+="$name"$'\t'"$WHY"$'\n'; fi
      fi
      LINES+="$L"$'\n'; VERD+="$V"$'\n'
    done <<< "$(pb_targets "$(read_catalog "$CATALOG")" "${ONLY%$'\n'}" | tr '\t' '\035')"
    LINES="${LINES%$'\n'}"; VERD="${VERD%$'\n'}"
    echo "잰 환경: bash $BASH_VERSION · LC_ALL=${LC_ALL:-} · GPU 도구 $TOOL · 쌍 $PAIRS$( [[ $FULL -eq 1 ]] && echo ' · 입력 4배 포함' )"; echo
    pb_render_compare "$LINES" "$VERD"; echo
    [[ -z "$PENDING" ]] || printf '%s' "$PEND" > "$PENDING"
    if [[ $NFAIL -gt 0 ]]; then echo; echo "한도를 넘은 것:"; pb_fail_lines "$VERD"; exit 1; fi
    exit 0 ;;
  turn-end)
    [[ "$(pb_setting SCV_PURE_BENCH on)" != off ]] || { echo "PURE_BENCH: off"; exit 0; }
    ST="$TDIR/.turn-plan"
    [[ -n "$TDIR" && -s "$ST/changed" ]] || { echo "PURE_BENCH: pass"; echo "PURE_BENCH_RUNS: 0"; exit 0; }
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
    PB_GATE_OUT=""; PB_GATE_N=0
    pb_gate quick "$ROOT" "$(grep -v ':' "$ST/changed")"; RC=$?
    [[ -n "$PB_GATE_OUT" ]] || exit 0            # 재지 않았다 — pb_gate 가 이미 한 줄을 냈다
    if [[ $RC -eq 1 ]]; then
      BL="$(cat "$ST/pb-blocks" 2>/dev/null || echo 0)"
      if [[ "$BL" -ge 2 ]]; then
        echo "PURE_BENCH: pass-unanswered"
        printf '%s 재는 검사 — 한도를 넘은 채 답 없이 끝남: %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$(sed -n '/^한도를 넘은 것:/,$p' <<< "$PB_GATE_OUT" | sed 1d | tr '\n' ' ')" >> "$ROOT/${SCV_JOURNAL_DIR:-scv/journal}/.pure-bench.log" 2>/dev/null || true
      else
        printf '%s' "$((BL + 1))" > "$ST/pb-blocks"
        echo "PURE_BENCH: block"
        printf 'PURE_BENCH_REASON: %s\n' "$(pb_block_text "$(sed -n '/^한도를 넘은 것:/,$p' <<< "$PB_GATE_OUT" | sed 1d)")"
      fi
    else
      echo "PURE_BENCH: pass"
    fi
    echo "PURE_BENCH_RUNS: $PB_GATE_N"
    SK="$(grep -c '| 재지 못함 |' <<< "$PB_GATE_OUT" || true)"; [[ "${SK:-0}" == 0 ]] || echo "PURE_BENCH_NOTE: 시간이 모자라거나 잴 수 없어 ${SK}개를 재지 못함"
    exit 0 ;;
  plan-end)
    [[ "$(pb_setting SCV_PURE_BENCH on)" != off ]] || { echo "재는 검사: 꺼져 있음 (SCV_PURE_BENCH=off)"; exit 0; }
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
    REF="$(pb_before_ref "$ROOT")" || { echo "재는 검사: git 저장소가 아니라 견줄 앞 코드가 없다 — 재지 못함"; exit 0; }
    PB_GATE_OUT=""; PB_GATE_N=0
    pb_gate full "$ROOT" "$( { git -C "$ROOT" diff --name-only "$REF" 2>/dev/null; git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null; } | sort -u)" > "$PB_TMP/gate.line"; RC=$?
    if [[ -z "$PB_GATE_OUT" ]]; then echo "재는 검사: 이 일을 시작한 뒤 달라진 사전 함수가 없다 — 잰 함수 0"; exit 0; fi
    echo "견주는 기준: 이 일을 시작하기 전의 코드 (${REF:0:7})"; echo "$PB_GATE_OUT"
    [[ $RC -ne 1 ]] || { echo; pb_block_text "$(sed -n '/^한도를 넘은 것:/,$p' <<< "$PB_GATE_OUT" | sed 1d)"; echo; }
    exit "$RC" ;;
  accept)
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"; JD="$ROOT/${SCV_JOURNAL_DIR:-scv/journal}"
    [[ -s "$JD/.pure-bench-pending" ]] || exit 0
    PICK="$(pb_accept_pick "$(cat "$JD/.pure-bench-pending")" "$Q" "$A")"
    [[ -n "$PICK" ]] || exit 0
    PLAN="$(grep -l -E '^status:[[:space:]]*(in_progress|testing)' "$ROOT"/scv/promote/*/PLAN.md 2>/dev/null | head -n 1)"
    if [[ -n "$PLAN" ]]; then DEST="$(dirname "$PLAN")/pure-bench-accepted.tsv"; else DEST="$JD/.pure-bench-accepted"; fi
    printf '%s\n' "$PICK" >> "$DEST"
    echo "PURE_BENCH_ACCEPTED: $(cut -f1 <<< "$PICK" | tr '\n' ' ')→ $DEST" ;;
  composed)
    [[ -d "$CATALOG" ]] || { echo "pure-bench: 사전 폴더가 없다: $CATALOG" >&2; exit 2; }
    T="$(pb_targets "$(read_catalog "$CATALOG")" "")"
    pb_composed "$(pb_calls "$(pb_bodies "$BASE" "$T")" "$(cut -f1 <<< "$T")")" ;;
  bench)
    [[ -d "$CATALOG" ]] || { echo "pure-bench: 사전 폴더가 없다: $CATALOG" >&2; exit 2; }
    ALL="$(pb_targets "$(read_catalog "$CATALOG")" "")"; CALLS=""
    if [[ $COMPOSED -eq 1 ]]; then
      CALLS="$(pb_composed "$(pb_calls "$(pb_bodies "$BASE" "$ALL")" "$(cut -f1 <<< "$ALL")")")"
      if [[ -n "${ONLY%$'\n'}" ]]; then
        KEEP=""; while IFS=$'\t' read -r cn cc; do case $'\n'"$ONLY" in *$'\n'"$cn"$'\n'*) KEEP+="$cn"$'\t'"$cc"$'\n' ;; esac; done <<< "$CALLS"
        CALLS="${KEEP%$'\n'}"
      fi
      WANT="$(tr '\t ' '\n\n' <<< "$CALLS" | grep . | sort -u)"
      [[ -n "$WANT" ]] || { echo "엮은 함수 없음 — 다른 사전 함수를 2개 이상 부르는 사전 함수가 없다"; exit 0; }
    else
      WANT="${ONLY%$'\n'}"
    fi
    TOOL="$(pb_gpu_tool)"; ROWS=""; CATTEXT="$(read_catalog "$CATALOG")"
    while IFS=$'\x1d' read -r name rel lang a1 a4 sc && IFS=$'\x1d' read -r rname role <&3; do
      [[ -n "$name" ]] || continue
      [[ "$rname" == "$name" ]] || role="-"
      if [[ "$lang" != sh ]]; then ROWS+="$(pb_row "$(printf '%s\t1\t-\t-\t-\t-\t-\t-\t-\tnot-shell\t-' "$name")" "" "$role")"$'\n'; continue; fi
      L1="$(pb_measure_fn "$TOOL" "$BASE" "$name" "$rel" "$a1" 1)"
      if [[ "$sc" == 1 && "$L1" == *$'\tok\t'* ]]; then L4="$(pb_measure_fn "$TOOL" "$BASE" "$name" "$rel" "$a4" 4)"
      else L4="$(printf '%s\t4\t-\t-\t-\t-\t-\t-\t-\tnot-scalable\t-' "$name")"; fi
      ROWS+="$(pb_row "$L1" "$L4" "$role")"$'\n'
    done <<< "$(pb_targets "$CATTEXT" "$WANT" | tr '\t' '\035')" 3<<< "$(pb_roles "$CATTEXT" "$WANT" | tr '\t' '\035')"
    ROWS="${ROWS%$'\n'}"
    [[ -z "$TSV" ]] || printf '%s\n' "$ROWS" > "$TSV"
    pb_render "$ROWS" "bash $BASH_VERSION · LC_ALL=${LC_ALL:-} · GPU 도구 $TOOL"; echo
    if [[ $COMPOSED -eq 1 ]]; then echo; pb_render_composed "$CALLS" "$ROWS"; echo; fi
    if [[ -n "$BASELINE" ]]; then
      OVER=""
      while IFS=$'\t' read -r n _ ms1 _ ratio _ _ _ st _; do
        if [[ "$st" == too-slow && "$ms1" != "-" ]]; then OVER+="$n"$'\n'      # 1배는 쟀고 4배 입력에서 끊겼다
        elif r="$(pb_to_milli "$ratio")" && [[ $r -gt $(( PB_SCALE_LIMIT * 1000 )) ]]; then OVER+="$n"$'\n'; fi
      done <<< "$ROWS"
      OVER="$(printf '%s' "$OVER" | LC_ALL=C sort)"
      if [[ ! -f "$BASELINE" ]]; then
        printf '%s\n' "$OVER" | sed '/^$/d' > "$BASELINE"
        echo; echo "기준 목록을 새로 만듦: $(grep -c . "$BASELINE")개 ($BASELINE)"
      else
        NEXT="$(pb_baseline_next "$(cat "$BASELINE")" "$OVER")"
        NEWN="$(sed -n 's/^@@new //p' <<< "$NEXT")"
        printf '%s\n' "$NEXT" | sed '/^@@new /d; /^$/d' > "$BASELINE"
        echo; echo "기준 목록: $(grep -c . "$BASELINE")개"
        if [[ -n "$NEWN" ]]; then echo "새로 한도(${PB_SCALE_LIMIT}배)를 넘은 함수: $(tr '\n' ' ' <<< "$NEWN")"; exit 1; fi
      fi
    fi ;;
  *) echo "Usage: pure-bench.sh targets|env|run|fn|composed|bench|compare|turn-end|plan-end|accept … (파일 머리말 참고)" >&2; exit 2 ;;
esac
