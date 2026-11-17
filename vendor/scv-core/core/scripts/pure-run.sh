#!/usr/bin/env bash
# pure-run.sh — 셸이 아닌 사전 함수 짝(TS/JS · 파이썬 · 러스트)을 서로의 예시 입력으로 실제로 돌려, 같은 일을 하는 짝을 낸다(0.95.0+).
#
#   pure-run.sh --root DIR        (표준 입력: pure-catalog 의 항목 줄들 — 파일 · 층 · 이름 · 역할 · 종류 · 예시들)
#   → "dup<탭>가<탭>나" (두 방향 모두 상대 예시의 출력을 냄) · "unrun<탭>이름" (돌려 보지 못함) · "notool<탭>언어" 줄들
#
# 무엇을 돌리나: 사전에 순수로 표식된 함수를, 짝 상대가 적어 둔 예시 입력으로만. 임시 폴더에서 HOME 도 그 폴더로 두고,
# 한 번에 20초(SCV_PURE_RUN_TIMEOUT)를 넘기면 끊는다. 모듈을 불러오면 그 파일의 맨 위 코드도 돈다 — 순수로 표식한
# 파일이라는 전제에 기댄다(계획의 한계). 도구(node · python3 · rustc)가 없으면 그 언어는 notool 로 알리고 막지 않는다.
# 판정 · 짝 고르기는 lib/pure-run.sh. 계획 20261117-wookiya1364-checks-not-comments 5단계.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/pure-run.sh
source "$SCRIPT_DIR/lib/pure-run.sh"

ROOT="$(pwd -P)"
while [[ $# -gt 0 ]]; do
  case "$1" in --root) ROOT="$2"; shift 2 ;; *) echo "pure-run: 모르는 인자: $1" >&2; exit 2 ;; esac
done
ENTRIES="$(cat)"
PAIRS="$(scv_prun_pairs "$ENTRIES")"
[[ -n "$PAIRS" ]] || exit 0
LIMIT="${SCV_PURE_RUN_TIMEOUT:-20}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/scv-prun.XXXXXX")" || exit 0
trap 'rm -rf "$TMP"' EXIT

# rustup 은 HOME 아래에서 도구 묶음을 찾는다 — HOME 을 바꾸기 전에 그 자리를 넘긴다.
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
TIMER=(); if command -v timeout >/dev/null 2>&1; then TIMER=(timeout "$LIMIT"); elif command -v gtimeout >/dev/null 2>&1; then TIMER=(gtimeout "$LIMIT")
elif command -v perl >/dev/null 2>&1; then TIMER=(perl -e 'alarm shift; exec @ARGV' "$LIMIT"); fi

# @effect pr_timed
# 이유: 남의 함수를 담은 프로그램을 시간 제한을 걸고 임시 폴더에서 돌린다 — 표준 출력을 그대로 낸다
pr_timed() {
  ( cd "$TMP" && HOME="$TMP" ${TIMER[@]+"${TIMER[@]}"} "$@" )
}

PY_HARNESS='import ast, shlex, sys, importlib.util
path, fn = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("scv_pure_mod", path)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
f = getattr(m, fn)
def lit(t):
    try: return ast.literal_eval(t)
    except Exception: return t
for ex in sys.argv[3:]:
    args, exp = ex.split("→", 1)
    try:
        r = f(*[lit(t) for t in shlex.split(args.strip(), posix=False)])
        print("ok" if r == lit(exp.strip()) else "diff")
    except Exception:
        print("diff")'

JS_HARNESS='const { pathToFileURL } = await import("node:url")
const [path, fn, ...exs] = process.argv.slice(1)
const m = await import(pathToFileURL(path).href)
const f = m[fn]
if (typeof f !== "function") process.exit(3)
const lit = t => { if (/^\x27.*\x27$/.test(t)) return t.slice(1, -1); try { return JSON.parse(t) } catch { return t } }
const toks = s => s.trim().match(/"(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27|\S+/g) ?? []
for (const ex of exs) {
  const [args, exp] = ex.split("→")
  try { console.log(JSON.stringify(await f(...toks(args).map(lit))) === JSON.stringify(lit(exp.trim())) ? "ok" : "diff") } catch { console.log("diff") }
}'

# @effect pr_run_js
# 이유: node 로 TS/JS 파일을 불러 함수 하나를 예시 입력들로 부른다(node 는 TS 형식을 지우고 돈다)
pr_run_js() { pr_timed node --input-type=module -e "$JS_HARNESS" "$@" 2>/dev/null; }

# @effect pr_run_py
# 이유: python3 -I 로 파이썬 파일을 불러 함수 하나를 예시 입력들로 부른다
pr_run_py() { pr_timed python3 -I -c "$PY_HARNESS" "$@" 2>/dev/null; }

# @effect pr_run_rs
# 이유: 러스트 파일을 그대로 끼운 작은 프로그램을 rustc 로 만들어, 함수 하나를 예시 입력들로 부른다
pr_run_rs() {
  local path="$1" fn="$2" ex args exp body=""
  shift 2
  for ex in "$@"; do
    args="${ex%%→*}"; exp="${ex#*→}"
    args="$(printf '%s' "$args" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/("[^"]*"|[^[:space:]"]+)[[:space:]]+/\1, /g')"
    body+="    println!(\"{}\", if format!(\"{:?}\", $fn($args)) == format!(\"{:?}\", ${exp# }) { \"ok\" } else { \"diff\" });"$'\n'
  done
  mkdir -p "$TMP/rs" && printf '#![allow(warnings)]\ninclude!(%s);\nfn main() {\n%s}\n' "\"$path\"" "$body" > "$TMP/rs/main.rs"
  pr_timed rustc --edition 2021 -O -o "$TMP/rs/main" "$TMP/rs/main.rs" >/dev/null 2>&1 || return 1
  pr_timed "$TMP/rs/main" 2>/dev/null
}

# @effect entry_of
# 이유: 표준 입력으로 받은 항목 목록(전역)에서 이름 하나의 줄을 꺼낸다
entry_of() { printf '%s\n' "$ENTRIES" | LC_ALL=C awk -F'\t' -v n="$1" '$3 == n { print; exit }'; }

RUNS=""; NOTOOL=""
while IFS=$'\t' read -r a b; do
  [[ -n "$a" ]] || continue
  for dir in "$a $b" "$b $a"; do
    caller="${dir% *}"; owner="${dir#* }"
    IFS=$'\t' read -r cfile _ _ _ _ _ <<< "$(entry_of "$caller")"
    IFS=$'\t' read -r _ _ _ _ _ oexs <<< "$(entry_of "$owner")"
    lang="$(scv_prun_lang "$cfile")"
    tool=""; case "$lang" in js) tool=node ;; py) tool=python3 ;; rs) tool=rustc ;; esac
    # SCV_PURE_RUN_SKIP="js py rs" — 그 언어의 도구가 없는 기계처럼 돈다(시험 · 일부러 끄기)
    if [[ " ${SCV_PURE_RUN_SKIP:-} " == *" $lang "* ]] || ! command -v "$tool" >/dev/null 2>&1; then NOTOOL+="notool"$'\t'"$lang"$'\n'; continue; fi
    IFS=$'\x1f' read -r -a exs <<< "$oexs"
    out="$("pr_run_$lang" "$ROOT/$cfile" "$caller" "${exs[@]}")"; rc=$?
    if [[ $rc -ne 0 || -z "$out" ]]; then res=err
    elif grep -qv '^ok$' <<< "$out"; then res=diff
    else res=ok; fi
    RUNS+="$caller"$'\t'"$owner"$'\t'"$res"$'\n'
  done
done <<< "$PAIRS"
scv_prun_verdict "$RUNS"
[[ -n "$NOTOOL" ]] && printf '%s' "$NOTOOL" | LC_ALL=C sort -u
exit 0
