#!/usr/bin/env bash
# pure-catalog.sh — 순수함수 사전을 만들고, 사전 · 예시 · 중복을 검사한다.
#
# 계약: core/contracts/purity.md "사전 — 만들기 전에 찾아 재사용한다"
#
# 표식(# @pure · # @deterministic)이 붙은 함수는 옆에 역할 · 종류 · 예를 단다. 이 스크립트는
# 그 주석에서 사전(저장소의 scv/core/catalog/pure/)을 만들고, 다음을 본다:
#   - 빈 칸 · 모르는 종류
#   - 예시를 실제로 돌려 적힌 출력과 같은지
#   - 같은 입력에 같은 출력을 내는 함수 짝(중복 의심)
#   - 사전이 주석과 어긋났는지, 한 파일이 한도를 넘었는지
#
# 판정은 lib/pure-catalog.sh 의 순수함수가 하고, 여기는 읽기 · 함수 불러 보기 · 쓰기만 한다.
#
# Usage:
#   pure-catalog.sh build [--root DIR] [--catalog DIR]   사전을 다시 만든다
#   pure-catalog.sh check [--root DIR] [--catalog DIR]   검사만 한다 (파일을 바꾸지 않는다)
#   pure-catalog.sh import --project [DIR] --entries FILE  (0.98.0+) 옮기기가 코드 표식에서 뽑은 항목을 사전에 합치고
#                                                          사전을 원본으로 둔다(사전 폴더의 SOURCE 표시)
#   사전이 원본인 프로젝트(SOURCE 표시 · --project): 항목은 사전 파일에서 읽고, 낡음은 '항목의 함수가 코드에 있나',
#   코드에 남은 주석 줄도 위반으로 센다(계획 comments-to-catalog).
#   --root 에 파일 하나를 주면 그 파일만 본다 (사전 낡음 판정은 전체 기준이라 무시할 것).
#   공통: --base DIR (위치 표시의 기준, 기본 core) · --contract FILE · --limit N (기본 400)
#
# Exit: 0 통과 · 1 위반 · 2 사용법 오류
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
# shellcheck source=lib/pure-catalog.sh
source "$SCRIPT_DIR/lib/pure-catalog.sh"
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true

MODE="${1:-}"; shift || true
case "$MODE" in
  build|check|import) : ;;
  -h|--help|"") sed -n '2,21p' "$0"; [[ -n "$MODE" ]] && exit 0; exit 2 ;;
  *) echo "pure-catalog.sh: unknown mode: $MODE (build | check | import)" >&2; exit 2 ;;
esac

# 사전은 저장소의 scv/core/ 아래 — 커밋되는 자리라 기기 · 협업자가 같은 사전을 본다.
# 래퍼 설치본(코어 사본)에는 scv/ 가 없다: 그때는 사전 낡음 · 크기 검사를 건너뛰고 예시 · 중복만 본다.
ROOT="$CORE_DIR/scripts"; CATALOG="$( cd "$CORE_DIR/.." && pwd )/scv/core/catalog/pure"; BASE="$CORE_DIR"
CATALOG_GIVEN=0; PROJECT=""; IMPORT_FILE=""
CONTRACT="$CORE_DIR/contracts/purity.md"; LIMIT=400
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; CATALOG_GIVEN=1; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --contract) CONTRACT="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --entries) IMPORT_FILE="$2"; shift 2 ;;
    --project)
      # 프로젝트 모드: 그 저장소의 추적 파일 중 표식이 든 것 — 언어 상관없이 — 을 읽어
      # 그 저장소의 scv/core/catalog/pure 에 사전을 둔다(기기 · 협업자가 같은 사전을 본다).
      if [[ -n "${2:-}" && "${2:0:2}" != "--" ]]; then PROJECT="$2"; shift 2; else PROJECT="."; shift; fi ;;
    *) echo "pure-catalog.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ -n "$PROJECT" ]]; then
  ROOT="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null)" || { echo "✖ git 저장소가 아니다: $PROJECT" >&2; exit 2; }
  BASE="$ROOT"
  [[ $CATALOG_GIVEN -eq 1 ]] || { CATALOG="$ROOT/scv/core/catalog/pure"; CATALOG_GIVEN=1; }
fi
if [[ -f "$ROOT" ]]; then ROOT="$( cd "$( dirname "$ROOT" )" && pwd )/$( basename "$ROOT" )"; else ROOT="$( cd "$ROOT" && pwd )" || exit 2; fi
BASE="$( cd "$BASE" && pwd )" || exit 2
ALLOWED_FILE="$CATALOG/duplicates-allowed.tsv"
# 사전 자리(저장소의 scv/)가 없으면 설치본이다 — 사전을 쓰지도, 낡음을 따지지도 않는다.
NO_HOME=0
[[ $CATALOG_GIVEN -eq 0 && ! -d "$( dirname "$( dirname "$( dirname "$CATALOG" )" )" )" ]] && NO_HOME=1

# ---------------------------------------------------------------- 입구: 읽기

KINDS="$(pc_kinds_from_contract < "$CONTRACT")"
[[ -n "$KINDS" ]] || { echo "✖ 종류 표를 못 찾았다: $CONTRACT" >&2; exit 2; }

# 프로젝트 모드에서 빼는 폴더(경로 마디 이름) — 시험 · 의존성 · 생성물. SCV_CATALOG_EXCLUDE 로 바꾼다.
PC_EXCLUDE="${SCV_CATALOG_EXCLUDE:-tests test __tests__ spec node_modules vendor dist build target scv .git}"
_pc_files() {
  if [[ -z "$PROJECT" ]]; then find "$ROOT" -type f -name '*.sh' | LC_ALL=C sort; return; fi
  local f seg skip
  git -C "$ROOT" grep -l -I -E '@(pure|deterministic)' -- . 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    skip=0
    for seg in $PC_EXCLUDE; do [[ "/$f" == *"/$seg/"* ]] && { skip=1; break; }; done
    [[ $skip -eq 0 ]] && printf '%s\n' "$ROOT/$f"
  done
}
ENTRIES=""
while IFS= read -r f; do
  rel="${f#"$BASE"/}"
  ENTRIES+="$(pc_extract_entries "$rel" < "$f")"$'\n'
done < <(_pc_files)
ENTRIES="$(printf '%s' "$ENTRIES" | LC_ALL=C awk 'NF')"
# 0.98.0+ — 사전이 원본인 프로젝트: 항목을 사전 파일에서 읽는다(코드에는 주석이 없다). 옮기기(import)는 지금 사전과
# 옮기기가 뽑은 항목을 합친다 — 같은 (파일, 이름)은 옮기기가 뽑은 것이 이긴다. 원본 표시: 사전 폴더의 SOURCE.
SRC=0
[[ -n "$PROJECT" && ( -f "$CATALOG/SOURCE" || "$MODE" == import ) ]] && SRC=1
# @effect _pc_catalog_text
# 이유: 사전 폴더의 md 파일들을 읽어 '@@FILE 이름' 줄로 이어 낸다
_pc_catalog_text() {
  local f
  for f in "$CATALOG"/*.md; do [[ -f "$f" ]] && { printf '@@FILE %s\n' "$(basename "$f")"; cat "$f"; printf '\n'; }; done
}
if [[ $SRC -eq 1 ]]; then
  _PC_FROM_CAT="$(pc_entries_from_catalog "$(_pc_catalog_text)")"
  if [[ "$MODE" == import ]]; then
    [[ -n "$IMPORT_FILE" && -f "$IMPORT_FILE" ]] || { echo "✖ import: --entries FILE 이 필요하다" >&2; exit 2; }
    _PC_NEW="$(LC_ALL=C awk 'NF' "$IMPORT_FILE")"
    ENTRIES="$(printf '%s\n%s\n%s\n' "$_PC_NEW" "$_PC_FROM_CAT" "$ENTRIES" | LC_ALL=C awk -F'\t' 'NF >= 3 && !seen[$1 FS $3]++')"
  else
    ENTRIES="$_PC_FROM_CAT"
  fi
fi
COUNT="$(printf '%s' "$ENTRIES" | LC_ALL=C awk 'NF' | wc -l | tr -d ' ')"
[[ $SRC -eq 1 ]] && export PC_SOURCE=1
# 예시를 실제로 돌리는 것은 셸 함수만 — 다른 언어는 칸만 보고 예시 글끼리 중복을 견준다.
PC_ALL="$(printf '%s\n' "$ENTRIES" | LC_ALL=C awk -F'\t' '$1 ~ /\.sh$/')"
PC_TEXT="$(printf '%s\n' "$ENTRIES" | LC_ALL=C awk -F'\t' 'NF && $1 !~ /\.sh$/')"
N_RUN="$(printf '%s' "$PC_ALL" | LC_ALL=C awk 'NF' | wc -l | tr -d ' ')"
N_TEXT=$((COUNT - N_RUN))
ALLOWED=""; [[ -f "$ALLOWED_FILE" ]] && ALLOWED="$(cat "$ALLOWED_FILE")"

# ---------------------------------------------------------------- 함수 불러 보기

# 공통 입력 묶음 — 빈 값 · 공백 · 줄바꿈 · 탭 · 한글 · 숫자 · 기호 · 버전 · JSON · 표
PC_WORDS=( "" " " "a" $'a\nb' $'\na' $'\t' "한글" "0" "-1" "1.2.3" "{}" "a|b" "  x  " )

# 표식 함수를 한 셸에 다 불러 둔다. lib 은 통째로, 스크립트 안의 함수는 본문만 꺼내 정의한다.
_pc_load() {
  local rel f name line prev=""
  while IFS= read -r line; do
    IFS=$'\x1d' read -r rel _ name _ <<< "${line//$'\t'/$'\x1d'}"
    [[ -n "$rel" ]] || continue
    f="$BASE/$rel"
    case "$rel" in
      lib/*|*/lib/*) [[ "$rel" == "$prev" ]] || source "$f"; prev="$rel" ;;
      *) eval "$(LC_ALL=C awk -v fn="$name" '$0 ~ "^"fn"\\(\\)[[:space:]]*\\{" {on=1} on {print} on && /^\}$/ {exit}' "$f")" ;;
    esac
  done <<< "$PC_ALL"
}

# 함수를 부를 때마다 $( ) 로 셸을 새로 띄우면 수천 번이 된다(맥에서 17초). 출력은 임시 파일로 받고
# read 로 읽어 셸을 띄우지 않는다. 함수끼리는 함수마다 한 번 띄운 셸로 떼어 놓는다.
PC_TMP="$(mktemp "${TMPDIR:-/tmp}/scv-pure-catalog.XXXXXX")" || exit 2
trap 'rm -f "$PC_TMP" "$PC_TMP".*' EXIT

# _pc_capture <함수> <인자 글> — PC_ST(종료 코드) · PC_OUT(출력, 끝 줄바꿈 뺌)에 담는다
_pc_capture() {
  if [[ "$2" == *"<<<"* ]]; then eval "$1 $2" >"$PC_TMP" 2>/dev/null
  else eval "$1 $2" >"$PC_TMP" 2>/dev/null </dev/null; fi
  PC_ST=$?
  PC_OUT=""; IFS= read -r -d '' PC_OUT <"$PC_TMP"
  PC_OUT="${PC_OUT%"${PC_OUT##*[!$'\n']}"}"
}

# _pc_split <예시> — PC_ARGS · PC_WANT(기대 출력 값) · PC_STATUS · PC_PIPE(인자에 파이프가 있나) 에 담는다.
# → 가 없으면 1, 기대 출력을 읽을 수 없으면 2
_pc_split() {
  local expect
  pc_split_example "$1" >"$PC_TMP" || return 1
  IFS= read -r -d '' expect <"$PC_TMP"; expect="${expect%$'\n'}"
  IFS=$'\x1d' read -r PC_ARGS expect PC_STATUS PC_PIPE <<< "${expect//$'\t'/$'\x1d'}"
  eval "PC_WANT=$expect" 2>/dev/null || return 2
  PC_WANT="${PC_WANT%"${PC_WANT##*[!$'\n']}"}"
}

# 예시 실행: 맞지 않는 예시를 "함수<탭>파일<탭>예시<탭>적힌<탭>실제" 로 낸다
_pc_run_examples() (
  set +eu +o pipefail
  _pc_load >/dev/null 2>&1
  local file tier name role kind exs ex line
  while IFS= read -r line; do
    IFS=$'\x1d' read -r file tier name role kind exs <<< "${line//$'\t'/$'\x1d'}"
    [[ -n "$name" && -n "$exs" ]] || continue
    (
      while IFS= read -r ex; do
        [[ -n "$ex" ]] || continue
        _pc_split "$ex"; case $? in
          1) printf '%s\t%s\t%s\t→ 가 없다\t\n' "$name" "$file" "$ex"; continue ;;
          2) printf '%s\t%s\t%s\t기대 출력을 읽을 수 없다\t\n' "$name" "$file" "$ex"; continue ;;
        esac
        if [[ "$PC_PIPE" == 1 ]]; then
          printf '%s\t%s\t%s\t파이프를 쓰지 않는다 — 출력 전체를 적는다\t\n' "$name" "$file" "$ex"; continue
        fi
        _pc_capture "$name" "$PC_ARGS"
        if [[ "$PC_ST" != "$PC_STATUS" || "$PC_OUT" != "$PC_WANT" ]]; then
          printf '%s\t%s\t%s\t%q [%s]\t%q [%s]\n' "$name" "$file" "$ex" "$PC_WANT" "$PC_STATUS" "$PC_OUT" "$PC_ST"
        fi
      done <<< "${exs//$PC_SEP/$'\n'}"
    )
  done <<< "$ENTRIES"
)

# 지문: 함수마다 "인자수|표준입력|cksum<탭>함수"
_pc_fingerprints() (
  set +eu +o pipefail
  _pc_load >/dev/null 2>&1
  local file tier name role kind exs line n stdin
  while IFS= read -r line; do
    IFS=$'\x1d' read -r file tier name role kind exs <<< "${line//$'\t'/$'\x1d'}"
    [[ -n "$name" && -n "$exs" ]] || continue
    _pc_split "${exs%%$PC_SEP*}" || continue
    stdin=0; [[ "$PC_ARGS" == *"<<<"* ]] && stdin=1
    eval "set -- ${PC_ARGS%%<<<*}" 2>/dev/null || continue
    n=$#
    (
      local fp="" w q args i
      for w in "${PC_WORDS[@]}"; do
        printf -v q '%q' "$w"
        args=""
        for (( i = 0; i != n; i++ )); do args+=" $q"; done
        [[ $stdin -eq 1 ]] && args+=" <<< $q"
        _pc_capture "$name" "$args"
        fp+="$PC_ST"$'\x1f'"$PC_OUT"$'\x1e'
      done
      printf '%s|%s|%s\t%s\n' "$n" "$stdin" "$(printf '%s' "$fp" | cksum | tr -d ' \t')" "$name"
    )
  done <<< "$ENTRIES"
)

# 방향 있는 확인: 후보 짝마다 "가가 나의 예시를 넣어도 나의 적힌 출력을 내나" 를 본다.
# 함수마다 셸을 한 번만 띄우고, 그 안에서 상대들을 차례로 본다. 같으면 "가<탭>나" 를 낸다.
_pc_directed() (
  set +eu +o pipefail
  _pc_load >/dev/null 2>&1
  # 예시는 함수마다 한 번만 풀어 둔다(긴 예시를 짝마다 다시 풀면 그것만으로 몇 초다).
  local -a names=() first=() last=() xa=() xw=() xs=()
  local line file tier name role kind exs e i k=0 n=0 f partners p
  while IFS= read -r line; do
    IFS=$'\x1d' read -r file tier name role kind exs <<< "${line//$'\t'/$'\x1d'}"
    names[n]="$name"; first[n]=$k
    while IFS= read -r e; do
      [[ -n "$e" ]] || continue
      _pc_split "$e" || continue
      xa[k]="$PC_ARGS"; xw[k]="$PC_WANT"; xs[k]="$PC_STATUS"; k=$((k + 1))
    done <<< "${exs//$PC_SEP/$'\n'}"
    last[n]=$k; n=$((n + 1))
  done <<< "$PC_ALL"
  _pc_behaves_as() {  # <함수> <다른 함수 이름> — 상대의 예시가 전부 같게 나오면 0
    local fn="$1" j q
    for (( j = 0; j != n; j++ )); do [[ "${names[j]}" == "$2" ]] && break; done
    [[ $j -lt $n ]] || return 1
    for (( q = first[j]; q != last[j]; q++ )); do
      _pc_capture "$fn" "${xa[q]}"
      [[ "$PC_ST" == "${xs[q]}" && "$PC_OUT" == "${xw[q]}" ]] || return 1
    done
    return 0
  }
  # 함수마다 상대 목록을 awk 한 번으로 만든다: "함수 상대 상대 …" — 이 일부만 맡으면 PC_PART(k/j)
  while read -r f partners; do
    [[ -n "$f" ]] || continue
    ( for p in $partners; do _pc_behaves_as "$f" "$p" && printf '%s\t%s\n' "$f" "$p"; done )
  done < <(printf '%s\n' "$1" | LC_ALL=C awk -F'\t' -v part="${PC_PART:-0/1}" 'NF == 2 { l[$1] = l[$1] " " $2; l[$2] = l[$2] " " $1; if (!($1 in o)) { o[$1] = ++k; ord[k] = $1 } if (!($2 in o)) { o[$2] = ++k; ord[k] = $2 } } END { split(part, pj, "/"); for (i = 1; i <= k; i++) if ((i - 1) % pj[2] == pj[1]) print ord[i] l[ord[i]] }')
)

# _pc_parallel <함수> — 항목을 PC_JOBS 묶음으로 나눠 동시에 돌리고 출력을 묶음 순서대로 잇는다
PC_JOBS=4
_pc_parallel() {
  local k part
  for (( k = 0; k != PC_JOBS; k++ )); do
    part="$(printf '%s\n' "$PC_ALL" | LC_ALL=C awk -v k="$k" -v j="$PC_JOBS" 'NF && (NR - 1) % j == k')"
    ( ENTRIES="$part"; PC_TMP="$PC_TMP.$1.$k"; "$1" ) > "$PC_TMP.out.$1.$k" &
  done
  wait
  for (( k = 0; k != PC_JOBS; k++ )); do cat "$PC_TMP.out.$1.$k"; done
}

# ---------------------------------------------------------------- 사전 글

# 예시 글 비교: 같은 언어끼리 같은 입출력이면 중복 의심(셸은 실행 지문이 맡는다),
# 다른 언어끼리면 중복이 아니라 '다른 언어 짝' — 프론트(TS) · 백엔드(파이썬)처럼 언어마다 따로 두는 함수다.
TEXT_PAIRS="$(pc_text_duplicates "$ENTRIES")"
# 짝 표기에 상대의 언어도 적는다: "fmt_date (py)"
TWINS="$(printf '%s\n' "$TEXT_PAIRS" | LC_ALL=C awk -F'\t' '$3 == "cross" { print $1 "\t" $2 }' | while IFS=$'\t' read -r a b; do
  [[ -n "$a" ]] || continue
  fa="$(printf '%s\n' "$ENTRIES" | LC_ALL=C awk -F'\t' -v n="$a" '$3 == n { print $1; exit }')"
  fb="$(printf '%s\n' "$ENTRIES" | LC_ALL=C awk -F'\t' -v n="$b" '$3 == n { print $1; exit }')"
  printf '%s (%s)\t%s (%s)\n' "$a" "$(pc_lang_of "$fa")" "$b" "$(pc_lang_of "$fb")"
done)"
SAME_TEXT="$(printf '%s\n' "$TEXT_PAIRS" | LC_ALL=C awk -F'\t' '$3 == "same" { print $1 "\t" $2 }')"
RENDERED="$(pc_render_catalog "$ENTRIES" "$KINDS" "$TWINS")"

_pc_files_in_render() { printf '%s\n' "$RENDERED" | sed -n 's/^@@FILE //p'; }
_pc_file_text() { printf '%s\n' "$RENDERED" | LC_ALL=C awk -v f="$1" '/^@@FILE /{on = (substr($0, 8) == f); next} on'; }

# ---------------------------------------------------------------- 출구: build

if [[ "$MODE" == "build" || "$MODE" == "import" ]]; then
  if [[ $NO_HOME -eq 1 ]]; then
    echo "✖ 사전 자리가 없다: $( dirname "$( dirname "$( dirname "$CATALOG" )" )" ) — 저장소(scv/ 가 있는 곳)에서 만든다" >&2; exit 2
  fi
  mkdir -p "$CATALOG"
  for old in "$CATALOG"/*.md; do
    [[ -e "$old" ]] || continue
    case "$(basename "$old")" in effects.md|notes.md) continue ;; esac   # 원본 사전의 부수효과 · 메모는 렌더하지 않는다
    _pc_files_in_render | grep -qxF "$(basename "$old")" || rm -f "$old"
  done
  while IFS= read -r f; do
    _pc_file_text "$f" > "$CATALOG/$f"
  done < <(_pc_files_in_render)
  [[ "$MODE" == import ]] && printf 'catalog\n' > "$CATALOG/SOURCE"
  echo "OK  catalog: ${COUNT}개 함수 → $(_pc_files_in_render | wc -l | tr -d ' ')개 파일 ($CATALOG)$([[ $SRC -eq 1 ]] && printf ' · 사전이 원본')"
  # 0.81.0+ — 선언 없는 함수(@pure · @deterministic · @effect 어느 것도 없음)의 기준선: 줄면 내리고, 늘리지는 않는다.
  _pd_args=(baseline update --baseline "$CATALOG/undeclared-baseline" --root "$ROOT"); [[ -n "$PROJECT" ]] && _pd_args+=(--project)
  bash "$SCRIPT_DIR/pure-declare.sh" "${_pd_args[@]}" 2>/dev/null | sed 's/^/    /' || true
  exit 0
fi

# ---------------------------------------------------------------- 출구: check

FAILS=0
report() { echo "$1" >&2; FAILS=$((FAILS + 1)); }

BAD="$(pc_validate_entries "$ENTRIES" "$KINDS")"
if [[ -n "$BAD" ]]; then
  while IFS=$'\t' read -r name file why; do report "✖ $file — $name: $why"; done <<< "$BAD"
fi

EXBAD="$(_pc_parallel _pc_run_examples)"
if [[ -n "$EXBAD" ]]; then
  while IFS= read -r line; do
    IFS=$'\x1d' read -r name file ex want got <<< "${line//$'\t'/$'\x1d'}"
    report "✖ $file — $name 예시가 틀렸다: $ex"
    [[ -n "$want$got" ]] && echo "      적힌: $want · 실제: $got" >&2
  done <<< "$EXBAD"
fi

CANDIDATES="$(pc_duplicate_pairs "$(_pc_parallel _pc_fingerprints)")"
_pc_directed_all() {
  local k
  for (( k = 0; k != PC_JOBS; k++ )); do
    ( PC_PART="$k/$PC_JOBS"; PC_TMP="$PC_TMP.dir.$k"; _pc_directed "$CANDIDATES" ) > "$PC_TMP.out.dir.$k" &
  done
  wait
  for (( k = 0; k != PC_JOBS; k++ )); do cat "$PC_TMP.out.dir.$k"; done
}
CONFIRMED="$( [[ -n "$CANDIDATES" ]] && pc_mutual_pairs "$(_pc_directed_all)" )"
# 셸 아닌 언어: 예시 글끼리 — 같은 입력에 같은 출력을 공유하고 어긋남이 없으면 중복 의심
# 셸 짝은 실행 지문이 이미 봤다 — 글 비교의 같은 언어 짝은 셸이 아닌 것만 쓴다.
TEXT_DUPS=""
if [[ -n "$SAME_TEXT" ]]; then
  TEXT_DUPS="$(while IFS=$'\t' read -r a b; do
    [[ -n "$a" ]] || continue
    la="$(printf '%s\n' "$ENTRIES" | LC_ALL=C awk -F'\t' -v n="$a" '$3 == n { print $1; exit }')"
    [[ "$(pc_lang_of "$la")" == sh ]] || printf '%s\t%s\n' "$a" "$b"
  done <<< "$SAME_TEXT")"
fi
[[ -n "$TEXT_DUPS" ]] && CONFIRMED="$(printf '%s\n%s' "$CONFIRMED" "$TEXT_DUPS" | LC_ALL=C awk 'NF')"
# 0.95.0+ — 셸 아닌 함수(TS/JS · 파이썬 · 러스트)는 같은 언어 짝을 서로의 예시 입력으로 실제로 돌려 본다(pure-run.sh).
# 예시 글이 달라도 같은 일을 하면 잡힌다. 돌려 보지 못한 함수 · 도구가 없는 언어는 알리기만 한다. 끄기: SCV_PURE_RUN=off.
RUN_NOTE=""
if [[ -n "$PC_TEXT" && "${SCV_PURE_RUN:-on}" != off && -f "$SCRIPT_DIR/pure-run.sh" ]]; then
  RUN_OUT="$(printf '%s\n' "$PC_TEXT" | bash "$SCRIPT_DIR/pure-run.sh" --root "$BASE" 2>/dev/null || true)"
  RUN_DUPS="$(printf '%s\n' "$RUN_OUT" | LC_ALL=C awk -F'\t' '$1 == "dup" { print $2 "\t" $3 }')"
  [[ -n "$RUN_DUPS" ]] && CONFIRMED="$(printf '%s\n%s' "$CONFIRMED" "$RUN_DUPS" | LC_ALL=C awk 'NF && !seen[$0]++')"
  RUN_NOTE="$(printf '%s\n' "$RUN_OUT" | LC_ALL=C awk -F'\t' '$1 == "unrun" { u = u (u ? ", " : "") $2 } $1 == "notool" { t = t (t ? ", " : "") $2 }
    END { if (u) print "돌려 보지 못함(함수): " u; if (t) print "돌려 보지 못함(도구 없음): " t }')"
fi
DUPS="$(pc_allowed_filter "$CONFIRMED" "$ALLOWED")"
if [[ -n "$DUPS" ]]; then
  while IFS=$'\t' read -r a b c; do
    if [[ "$a" == "!이유없음" ]]; then
      report "✖ 중복 예외에 이유가 없다: $b · $c ($ALLOWED_FILE)"
    else
      report "✖ 중복 의심: $a · $b — 같은 입력에 같은 출력을 낸다. 하나로 합치거나, 다르다면 다른 입력을 예시로 더하라"
    fi
  done <<< "$DUPS"
fi

HOME_NOTE="사전 최신"
if [[ $NO_HOME -eq 1 ]]; then HOME_NOTE="사전 자리 없음(설치본) — 사전 낡음 · 크기는 건너뜀"; RENDERED=""; fi
OVER="$(pc_oversize_files "$RENDERED" "$LIMIT")"
if [[ -n "$OVER" ]]; then
  while IFS=$'\t' read -r f n; do report "✖ 사전 파일이 너무 크다: $f ${n}줄 (한도 $LIMIT) — 그 종류의 함수에 세부 종류를 붙여라"; done <<< "$OVER"
fi

STALE=""
[[ $NO_HOME -eq 1 ]] || while IFS= read -r f; do
  if [[ ! -f "$CATALOG/$f" ]] || [[ "$(cat "$CATALOG/$f")" != "$(_pc_file_text "$f")" ]]; then STALE+=" $f"; fi
done < <(_pc_files_in_render)
[[ $NO_HOME -eq 1 ]] || for old in "$CATALOG"/*.md; do
  [[ -e "$old" ]] || continue
  case "$(basename "$old")" in effects.md|notes.md) continue ;; esac
  _pc_files_in_render | grep -qxF "$(basename "$old")" || STALE+=" $(basename "$old")"
done
# 0.98.0+ — 사전이 원본: 항목의 함수가 코드에 없으면 낡음(지워졌거나 이름이 바뀜), 코드에 남은 주석은 위반.
if [[ $SRC -eq 1 ]]; then
  while IFS=$'\t' read -r _f _t _n _rest; do
    [[ -n "$_n" ]] || continue
    if [[ ! -f "$BASE/$_f" ]] || ! grep -qw -- "$_n" "$BASE/$_f" 2>/dev/null; then report "✖ 사전 항목의 함수가 코드에 없다: $_n ($_f) — 지웠거나 이름이 바뀌었으면 사전을 고쳐라"; fi
  done <<< "$ENTRIES"
  _cs_sw=""; declare -F settings_get >/dev/null 2>&1 && _cs_sw="$(cd "$BASE" && settings_get SCV_CATALOG_SOURCE 2>/dev/null | tr -d '"[:space:]' | tr '[:upper:]' '[:lower:]')"
  # 끄면(off) 남은 주석을 세지 않는다 — 주석 막기만 풀린다(사전은 원본 그대로).
  if [[ "$_cs_sw" != off ]] && command -v python3 >/dev/null 2>&1 && [[ -f "$SCRIPT_DIR/code-comments.py" ]]; then
    _cc_out="$(cd "$BASE" && bash "$SCRIPT_DIR/comments-migrate.sh" files --root "$BASE" | python3 -I "$SCRIPT_DIR/code-comments.py" count-stdin 2>/dev/null)"
    _cc_n="$(printf '%s\n' "$_cc_out" | sed -n 's/^TOTAL\t//p')"
    if [[ "${_cc_n:-0}" -gt 0 ]]; then
      report "✖ 코드에 주석 ${_cc_n}줄 — 이 프로젝트는 사전이 원본이다. 옮기기: bash $SCRIPT_DIR/comments-migrate.sh run --root $BASE"
      printf '%s\n' "$_cc_out" | grep -v '^TOTAL' | head -5 | sed 's/^/      /' >&2
    fi
  fi
fi
[[ -z "$STALE" ]] || report "✖ 사전이 낡았다:$STALE — 다시 만들기: bash core/scripts/pure-catalog.sh build$([[ $SRC -eq 1 ]] && printf ' --project')"

# 0.81.0+ — 선언 없는 함수 수가 기준선보다 늘면 실패(사전 자리가 있을 때만 — 설치본에는 기준선이 없다).
if [[ $NO_HOME -eq 0 && -f "$CATALOG/undeclared-baseline" ]]; then
  _pd_args=(baseline check --baseline "$CATALOG/undeclared-baseline" --root "$ROOT"); [[ -n "$PROJECT" ]] && _pd_args+=(--project)
  _pd_out="$(bash "$SCRIPT_DIR/pure-declare.sh" "${_pd_args[@]}" 2>&1)" || report "${_pd_out}"
fi

[[ -n "$RUN_NOTE" ]] && printf '%s\n' "$RUN_NOTE"
if [[ $FAILS -eq 0 ]]; then
  if [[ $N_TEXT -gt 0 ]]; then
    echo "OK  catalog: ${COUNT}개 함수(예시 실행 ${N_RUN} · 칸만 ${N_TEXT}) · 중복 의심 0 · $HOME_NOTE"
  else
    echo "OK  catalog: ${COUNT}개 함수 · 예시 전부 맞음 · 중복 의심 0 · $HOME_NOTE"
  fi
  exit 0
fi
echo "" >&2
echo "→ 위반 ${FAILS}건 (함수 ${COUNT}개 중). 규칙: core/contracts/purity.md" >&2
exit 1
