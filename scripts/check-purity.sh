#!/usr/bin/env bash
# check-purity.sh — 순수해야 한다고 선언한 함수에 부수효과가 없는지 검사한다.
#
# 왜 있나: "순수함수로 만들자" 는 문서에만 쓰면 두 달 뒤에 원래대로 돌아간다.
# 지켜지는지 기계가 봐야 한다. 이 검사가 그 장치다.
#
# 선언은 코드 옆에 둔다. 함수 바로 위에 표식을 적으면 이 검사가 찾아낸다:
#
#   # @pure
#   my_fn() { ... }              외부 명령조차 부르지 않는다. 셸 안에서만 논다
#
#   # @deterministic
#   my_transform() { ... }       jq·sha256sum 같은 결정적 도구는 부를 수 있다.
#                                디스크·시각·무작위·네트워크는 여전히 금지
#
# 두 층을 가르는 이유: 우선순위 판단 같은 것은 외부 도구가 필요 없지만, JSON 을
# 읽거나 해싱하는 변환은 도구가 필요하다. 후자도 같은 입력에 같은 출력이므로
# 테스트는 결정적이다 — 다만 "아무것도 안 부른다" 와는 다른 약속이라 이름을 나눈다.
#
# 이 검사기 자체가 순수함수다: 코드 텍스트를 받아 위반 목록을 낸다.
#
# Usage:
#   check-purity.sh [PATH ...]     기본: core/scripts 아래 전부
#   check-purity.sh --list         선언된 함수 목록만 찍는다
#   check-purity.sh --self-test    검사기가 실제로 위반을 잡는지 확인한다
#
# Exit: 0 위반 없음 · 1 위반 있음 · 2 사용법 오류
set -uo pipefail

MODE="check"
PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) MODE="list"; shift ;;
    --self-test) MODE="selftest"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) echo "check-purity.sh: unknown flag: $1" >&2; exit 2 ;;
    *) PATHS+=("$1"); shift ;;
  esac
done

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [[ ${#PATHS[@]} -eq 0 ]]; then PATHS=("$SCRIPT_DIR"); fi

# ---------------------------------------------------------------- 순수: 판정부

# 부수효과가 **아닌** 것을 먼저 지운다. 이게 없으면 과잉 탐지가 난다.
#   (( ))        산술 비교의 부등호는 리다이렉션이 아니다
#   <<<          히어스트링은 문자열 전달이지 파일 읽기가 아니다
#   >/dev/null   버리는 것은 파일 쓰기가 아니다
#   command -v   도구가 있는지 보는 것뿐 — 실행하지 않는다
_purity_strip_benign() {
  grep -vE '^[[:space:]]*#' \
    | sed -E 's/\(\([^)]*\)\)/@ARITH@/g' \
    | sed -E 's/<<</@HERESTRING@/g' \
    | sed -E 's#[0-9]?>>?[[:space:]]*/dev/(null|stdout|stderr)#@DEVNULL@#g' \
    | sed -E 's/command -v [a-zA-Z0-9_.-]+/@HAVECMD@/g'
}

# 어느 층에서든 금지되는 것: 시각·무작위·네트워크·파일 조작·디스크 순회.
#
# cat 과 find 가 여기 있는 이유: 둘은 파일을 이름으로 지목하는 것이 본업이다.
# 인자 없는 cat(파이프 안 no-op)까지 막히지만, 그건 지워도 되는 코드다.
_PURITY_ALWAYS='(^|[;&|(][[:space:]]*|^[[:space:]]*)(date|curl|wget|ssh|scp|git|mktemp|touch|rm|mv|cp|mkdir|rmdir|ln|chmod|chown|source|cat|find|ls|stat|readlink)([[:space:]]|$)|\$RANDOM|\$\{RANDOM|\$\(date|`date'
# 파일 리다이렉션 — 읽기도 쓰기도
_PURITY_REDIR='[^@<>&[:space:]][[:space:]]*(>>?|<)[[:space:]]*[^&@[:space:]]'
# @pure 에서만 금지되는 것: 외부 명령 일반
_PURITY_STRICT='(^|[;&|(][[:space:]]*|^[[:space:]]*)(sed|awk|grep|head|tail|tr|cut|sort|uniq|comm|jq|python3|sha256sum|shasum|wc|xargs|printf[[:space:]]+-v)([[:space:]]|$)'

# 알려진 한계 — 이 검사는 **보호 장치이지 증명이 아니다.**
#   sed/awk/grep/jq 에 파일 이름을 인자로 주면 잡지 못한다 (deterministic 층).
#   그 도구들은 표준입력 필터로 쓰라고 허용한 것이고, 스크립트 인자와 파일
#   인자를 정규식으로 가르는 것은 오탐 없이 되지 않는다. 잡히지 않는다고
#   허용된 것은 아니다 — 계약(core/contracts/purity.md)이 우선한다.

# purity_violations <tier> <함수본문> — 위반 줄을 낸다. 없으면 아무것도 안 낸다.
# 순수하다: 텍스트를 받아 텍스트를 낸다.
purity_violations() {
  local tier="$1" body="$2" pattern="$_PURITY_ALWAYS|$_PURITY_REDIR"
  [[ "$tier" == "pure" ]] && pattern="$pattern|$_PURITY_STRICT"
  printf '%s\n' "$body" | _purity_strip_benign | grep -nE "$pattern" || true
}

# ---------------------------------------------------------------- 효과: 파일 읽기

# 표식이 붙은 함수를 찾는다: "<파일>|<층>|<함수이름>|<시작줄>"
_purity_scan_file() {
  local f="$1"
  awk -v file="$f" '
    /^[[:space:]]*#[[:space:]]*@pure[[:space:]]*$/          { tier="pure";          pending=NR; next }
    /^[[:space:]]*#[[:space:]]*@deterministic[[:space:]]*$/ { tier="deterministic"; pending=NR; next }
    pending && /^[[:space:]]*#/ { next }                     # 표식과 함수 사이 주석은 허용
    pending && /^[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{/ {
      name=$0; sub(/\(\).*/, "", name); gsub(/[[:space:]]/, "", name)
      printf "%s|%s|%s|%d\n", file, tier, name, NR
      pending=0; next
    }
    pending && NF { printf "%s|%s|!ORPHAN!|%d\n", file, tier, pending; pending=0 }
  ' "$f"
}

_purity_extract_body() {  # <파일> <함수이름>
  awk -v fn="$2" '
    $0 ~ "^"fn"\\(\\)[[:space:]]*\\{" { inside = 1 }
    inside { print }
    inside && /^\}$/ { exit }
  ' "$1"
}

_purity_files() {
  local p
  for p in "${PATHS[@]}"; do
    if [[ -f "$p" ]]; then printf '%s\n' "$p"
    elif [[ -d "$p" ]]; then find "$p" -type f -name '*.sh' 2>/dev/null
    fi
  done | LC_ALL=C sort -u
}

# ---------------------------------------------------------------- 검사기 자체 확인

if [[ "$MODE" == "selftest" ]]; then
  bad_pure='fn() {
  local x
  x="$(date +%s)"
  cat /etc/hosts > /tmp/x
}'
  ok_pure='fn() {
  local a="$1" b="$2"
  (( a < b )) && return 0
  printf "%s\n" "$a"
}'
  n_bad="$(purity_violations pure "$bad_pure" | grep -c . || true)"
  n_ok="$(purity_violations pure "$ok_pure" | grep -c . || true)"
  n_det="$(purity_violations deterministic 'fn() {
  jq -r .x
}' | grep -c . || true)"
  n_det_bad="$(purity_violations deterministic 'fn() {
  cat /etc/hosts
}' | grep -c . || true)"
  fails=0
  [[ "${n_bad:-0}"     -ge 2 ]] || { echo "✖ self-test: 일부러 넣은 부수효과를 못 잡는다 ($n_bad)"; fails=1; }
  [[ "${n_ok:-0}"      -eq 0 ]] || { echo "✖ self-test: 멀쩡한 함수를 위반이라 한다 ($n_ok)"; fails=1; }
  [[ "${n_det:-0}"     -eq 0 ]] || { echo "✖ self-test: deterministic 층에서 jq 를 막는다 ($n_det)"; fails=1; }
  [[ "${n_det_bad:-0}" -ge 1 ]] || { echo "✖ self-test: deterministic 층에서 파일 읽기를 놓친다 ($n_det_bad)"; fails=1; }
  [[ $fails -eq 0 ]] && { echo "OK  self-test: 검사기가 위반을 잡고 멀쩡한 것은 통과시킨다"; exit 0; }
  exit 1
fi

# ---------------------------------------------------------------- 본 검사

DECLARED=0; VIOLATIONS=0; ORPHANS=0
while IFS='|' read -r file tier name line; do
  [[ -n "${file:-}" ]] || continue
  if [[ "$name" == "!ORPHAN!" ]]; then
    echo "✖ $file:$line — @$tier 표식 아래에 함수 정의가 없다" >&2
    ORPHANS=$((ORPHANS + 1)); continue
  fi
  DECLARED=$((DECLARED + 1))
  if [[ "$MODE" == "list" ]]; then
    printf '%-14s %-34s %s:%s\n' "@$tier" "$name" "$file" "$line"
    continue
  fi
  body="$(_purity_extract_body "$file" "$name")"
  if [[ -z "$body" ]]; then
    echo "✖ $file:$line — $name 의 본문을 찾을 수 없다" >&2
    VIOLATIONS=$((VIOLATIONS + 1)); continue
  fi
  hits="$(purity_violations "$tier" "$body")"
  if [[ -n "$hits" ]]; then
    echo "✖ $file — $name 은 @$tier 로 선언됐지만 부수효과가 있다:" >&2
    printf '%s\n' "$hits" | sed 's/^/      /' >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done < <(_purity_files | while IFS= read -r f; do _purity_scan_file "$f"; done)

[[ "$MODE" == "list" ]] && { echo "— 선언된 함수 ${DECLARED}개"; exit 0; }

if [[ $((VIOLATIONS + ORPHANS)) -eq 0 ]]; then
  echo "OK  purity: 선언된 ${DECLARED}개 함수 전부 약속을 지킨다"
  exit 0
fi
echo "" >&2
echo "→ 위반 ${VIOLATIONS}건, 표식 오류 ${ORPHANS}건 (선언 ${DECLARED}개 중)" >&2
echo "  순수부는 문자열만 다루고, 파일·시각·네트워크는 바깥층이 맡는다." >&2
echo "  자세한 계약: core/contracts/purity.md" >&2
exit 1
