#!/usr/bin/env bash
# run-focused.sh — 집중 시험(core/tests/test-*.sh)을 한 작업 안에서 동시에 돌린다.
#
# 시험 64개를 하나씩 돌리면 CI 집중 시험 단계가 10분을 넘는다. 시험은 서로 독립이므로
# 코어 수만큼 겹쳐 돌리고, 시간 한도를 재는 시험만 다른 시험이 다 끝난 뒤 하나씩 돌린다.
# 혼자 돌아야 하는 시험은 파일 앞 30줄 안에 다음 한 줄로 스스로 밝힌다:
#
#   # scv-test: serial
#
# 쓰는 법:
#   bash core/tests/run-focused.sh [--jobs N] [--dir DIR]... [--also FILE]... [--shard I/N] [--timings FILE]
#     --jobs N       동시에 돌 시험 수(기본: SCV_TEST_JOBS, 없으면 이 컴퓨터의 코어 수; --shard 를 주면 1)
#     --dir DIR      시험 폴더(여러 번 가능, 기본: 이 파일이 있는 폴더) — 그 안의 test-*.sh
#     --also FILE    시험 파일 하나 더(여러 번 가능, 예: core/tests/run-dry.sh)
#     --shard I/N    모은 시험을 N 조각으로 고르게 나눠 I 번째만 돈다(CI 워커 나누기)
#     --timings FILE 조각을 고르게 나눌 때 쓰는 시험별 시간(기본: 이 폴더의 timings.tsv).
#                    줄 모양 '<key><TAB><초>' — key 는 core/tests/test-x.sh · tests/test-y.sh 꼴.
#                    기록 없는 시험은 5초로 친다. 표의 초를 옮겨 적으면 갱신된다.
#
# 한 러너 안에서 겹쳐 돌리면(--jobs) 러너의 CPU 를 나눠 써 시험마다 느려진다(맥 CI 실측:
# 시험 시간 합 719 → 1397초). 그래서 CI 는 조각마다 다른 러너를 쓰고, 조각 안은 차례로 돈다.
#
# 출력: 시험마다 'PASS|FAIL  <초>s  <이름>' 한 줄(오래 걸린 순), 실패한 시험의 로그 전문,
# 마지막 줄 'run-focused: pass=N fail=N jobs=N wall=Ns'. 하나라도 실패하면 종료 코드 1.
# GitHub Actions 에서는 시험마다 로그를 접힌 묶음으로 함께 찍는다.
#
# 파이프라인: list_tests → classify → partition → run_batch → summarize → report
#   (classify · partition · summarize 는 문자열만 받고 돌려주는 순수 함수다.)

set -u

# ── 순수: 목록 줄 'path<TAB>mark' → 'parallel|serial<TAB>path'
rf_classify() {
  local path mark
  while IFS="$(printf '\t')" read -r path mark; do
    [[ -n "$path" ]] || continue
    if [[ "$mark" == "serial" ]]; then
      printf 'serial\t%s\n' "$path"
    else
      printf 'parallel\t%s\n' "$path"
    fi
  done
}

# key — 시험 파일의 이름표: 'core/tests/test-x.sh' 또는 'tests/test-y.sh' (어느 폴더에서 돌려도 같다)
RF_KEY_AWK='function rfkey(p,   n, a) {
  n = split(p, a, "/")
  if (n >= 3 && a[n-1] == "tests" && a[n-2] == "core") return "core/tests/" a[n]
  if (n >= 2 && a[n-1] == "tests") return "tests/" a[n]
  return a[n]
}'

# ── 순수: 이름표 하나
rf_key() { awk "$RF_KEY_AWK"' { print rfkey($0) }' <<< "$1"; }

# ── 순수: 'class<TAB>path' 줄 + 시간 기록 문자열 + I + N → 조각 I 의 줄(원래 순서)
#   긴 것부터, 지금 가장 덜 찬 조각에 넣는다(같으면 번호 작은 조각). 기록 없으면 5초.
rf_partition() {
  local timings="$1" i="$2" n="$3"
  # 시간 기록은 환경으로 넘긴다 — 맥 awk 는 -v 값 안의 줄바꿈을 받지 않는다.
  RF_TIMINGS="$timings" awk -F'\t' -v want="$i" -v n="$n" "$RF_KEY_AWK"'
    BEGIN {
      m = split(ENVIRON["RF_TIMINGS"], L, "\n")
      for (j = 1; j <= m; j++) { if (L[j] ~ /^#/ || L[j] == "") continue; split(L[j], f, "\t"); w[f[1]] = f[2] + 0 }
    }
    NF >= 2 { c++; line[c] = $0; k = rfkey($2); wt[c] = (k in w) ? w[k] : 5; key[c] = k }
    END {
      for (a = 1; a <= c; a++) ord[a] = a
      for (a = 2; a <= c; a++) {            # 무게 내림차순, 같으면 이름표 오름차순(삽입 정렬 — 수십 개)
        x = ord[a]; b = a - 1
        while (b >= 1 && (wt[ord[b]] < wt[x] || (wt[ord[b]] == wt[x] && key[ord[b]] > key[x]))) { ord[b+1] = ord[b]; b-- }
        ord[b+1] = x
      }
      for (s = 1; s <= n; s++) load[s] = 0
      for (a = 1; a <= c; a++) {
        best = 1; for (s = 2; s <= n; s++) if (load[s] < load[best]) best = s
        bin[ord[a]] = best; load[best] += wt[ord[a]]
      }
      for (a = 1; a <= c; a++) if (bin[a] == want) print line[a]
    }'
}

# ── 순수: 결과 줄 'name<TAB>rc<TAB>seconds' → 표 줄 · FAILED 줄 · TOTAL 줄
rf_summarize() {
  local rows name rc secs pass=0 fail=0 failed=""
  rows="$(cat)"
  while IFS="$(printf '\t')" read -r name rc secs; do
    [[ -n "$name" ]] || continue
    if [[ "$rc" == "0" ]]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      failed="${failed}$(printf 'FAILED\t%s' "$name")"$'\n'
    fi
  done <<EOF
$rows
EOF
  printf '%s\n' "$rows" | awk -F'\t' 'NF >= 3 { printf "%s\t%s\t%s\n", $3, ($2 == "0" ? "PASS" : "FAIL"), $1 }' \
    | LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k3,3 \
    | awk -F'\t' '{ printf "ROW\t%s\t%s\t%s\n", $2, $1, $3 }'
  printf '%s' "$failed"
  printf 'TOTAL\t%s\t%s\n' "$pass" "$fail"
}

# ── 입구: 시험 폴더들의 test-*.sh + 덧붙인 파일 → 'path<TAB>mark' (이름순)
#   인자: 'D:<폴더>' 또는 'F:<파일>'
rf_list_tests() {
  local arg f mark
  for arg in "$@"; do
    case "$arg" in
      D:*) for f in "${arg#D:}"/test-*.sh; do [[ -f "$f" ]] && printf '%s\n' "$f"; done ;;
      F:*) printf '%s\n' "${arg#F:}" ;;
    esac
  done | LC_ALL=C sort -u | while IFS= read -r f; do
    mark=""
    head -n 30 "$f" | grep -Eq '^# scv-test: serial([[:space:]]|$)' && mark="serial"
    printf '%s\t%s\n' "$f" "$mark"
  done
}

# ── 부수효과: 시험 하나를 돌려 로그와 결과 줄을 남긴다
rf_run_one() {
  local logdir="$1" path="$2" name file t0 t1 rc
  name="$(rf_key "$path")"
  file="$(printf '%s' "$name" | tr '/' '_')"
  t0=$(date +%s)
  bash "$path" > "$logdir/$file.log" 2>&1 < /dev/null
  rc=$?
  t1=$(date +%s)
  printf '%s\t%s\t%s\n' "$name" "$rc" "$((t1 - t0))" > "$logdir/$file.result"
}

# ── 부수효과: 동시에 돌 시험은 jobs 만큼 겹쳐, 혼자 돌 시험은 그 뒤 하나씩
rf_run_batch() {
  local self="$1" logdir="$2" jobs="$3" classified="$4" path
  printf '%s\n' "$classified" | awk -F'\t' '$1 == "parallel" { print $2 }' \
    | tr '\n' '\0' | xargs -0 -n 1 -P "$jobs" bash "$self" --one "$logdir"
  while IFS= read -r path; do
    [[ -n "$path" ]] && rf_run_one "$logdir" "$path"
  done <<EOF
$(printf '%s\n' "$classified" | awk -F'\t' '$1 == "serial" { print $2 }')
EOF
  cat "$logdir"/*.result 2>/dev/null
}

# ── 출구: 표 · 실패 로그 · 마지막 줄, 종료 코드
rf_report() {
  local summary="$1" logdir="$2" jobs="$3" wall="$4" ci="${GITHUB_ACTIONS:-}" f name pass fail
  if [[ "$ci" == "true" ]]; then
    for f in "$logdir"/*.log; do
      [[ -f "$f" ]] || continue
      echo "::group::$(basename "$f" .log | sed 's/_/\//g')"
      cat "$f"
      echo "::endgroup::"
    done
  fi
  printf '%s\n' "$summary" | awk -F'\t' '$1 == "ROW" { printf "%s  %4ss  %s\n", $2, $3, $4 }'
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    echo
    echo "──── FAIL $name ── 로그 전문 ────"
    cat "$logdir/$(printf '%s' "$name" | tr '/' '_').log"
  done <<EOF
$(printf '%s\n' "$summary" | awk -F'\t' '$1 == "FAILED" { print $2 }')
EOF
  pass="$(printf '%s\n' "$summary" | awk -F'\t' '$1 == "TOTAL" { print $2 }')"
  fail="$(printf '%s\n' "$summary" | awk -F'\t' '$1 == "TOTAL" { print $3 }')"
  echo "run-focused: pass=${pass:-0} fail=${fail:-0} jobs=$jobs${RF_SHARD:+ shard=$RF_SHARD} wall=${wall}s"
  [[ "${fail:-0}" == "0" ]]
}

rf_default_jobs() {
  local n="${SCV_TEST_JOBS:-}"
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || n=2
  printf '%s\n' "$n"
}

rf_main() {
  local self here jobs="" shard="" timings="" t0 classified results summary i n tfile
  local -a inputs
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  here="$(dirname "$self")"
  inputs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jobs) jobs="${2:-}"; shift 2 ;;
      --dir) [[ -d "${2:-}" ]] || { echo "run-focused: no such directory: ${2:-}" >&2; return 2; }
             inputs+=("D:$2"); shift 2 ;;
      --also) [[ -f "${2:-}" ]] || { echo "run-focused: no such file: ${2:-}" >&2; return 2; }
              inputs+=("F:$2"); shift 2 ;;
      --shard) shard="${2:-}"; shift 2 ;;
      --timings) timings="${2:-}"; shift 2 ;;
      *) echo "run-focused: unknown argument: $1" >&2; return 2 ;;
    esac
  done
  [[ ${#inputs[@]} -gt 0 ]] || inputs=("D:$here")
  if [[ -n "$shard" ]]; then
    [[ "$shard" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]] || { echo "run-focused: --shard needs I/N" >&2; return 2; }
    i="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[2]}"
    (( i <= n )) || { echo "run-focused: --shard $shard — I is larger than N" >&2; return 2; }
    [[ -n "$jobs" ]] || jobs=1
  fi
  [[ -n "$jobs" ]] || jobs="$(rf_default_jobs)"
  [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "run-focused: --jobs needs a positive number" >&2; return 2; }

  RF_LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/scv-focused.XXXXXX")"
  trap 'rm -rf "$RF_LOGDIR"' EXIT
  t0=$(date +%s)
  classified="$(rf_list_tests "${inputs[@]}" | rf_classify)"
  if [[ -n "$shard" ]]; then
    RF_SHARD="$shard"
    tfile="${timings:-$here/timings.tsv}"
    classified="$(printf '%s\n' "$classified" | rf_partition "$(cat "$tfile" 2>/dev/null)" "$i" "$n")"
  fi
  if [[ -z "$classified" ]]; then
    echo "run-focused: nothing to run${RF_SHARD:+ in shard $RF_SHARD}"
    return 0
  fi
  results="$(rf_run_batch "$self" "$RF_LOGDIR" "$jobs" "$classified")"
  summary="$(printf '%s\n' "$results" | rf_summarize)"
  rf_report "$summary" "$RF_LOGDIR" "$jobs" "$(( $(date +%s) - t0 ))"
}

if [[ "${1:-}" == "--one" ]]; then
  rf_run_one "$2" "$3"
  exit 0
fi
if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  rf_main "$@"
fi
