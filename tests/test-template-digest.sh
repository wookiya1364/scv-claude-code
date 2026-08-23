#!/usr/bin/env bash
# test-template-digest.sh — 템플릿 갱신 판단의 순수부 검사.
#
# 계획 20260823-wookiya1364-template-refresh 의 TESTS.md T1–T3 을 덮는다.
#   T1. 판단 함수 전수 검사 (18가지 조합)
#   T2. 판단 함수에 부수효과가 없다 (정적 검사)
#   T3. 지문 접기가 결정적이다
#
# 판정은 전부 문자열 비교다. "잘 된 것 같다" 는 자리가 없다.
#
# Run: bash core/tests/test-template-digest.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$REPO_ROOT/scripts/lib/template-digest.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi; }

[[ -f "$LIB" ]] || { echo "✖ 라이브러리 없음: $LIB"; exit 1; }
# shellcheck source=../scripts/lib/template-digest.sh
source "$LIB"

# ============================================================ T1. 전수 검사
echo "T1. 판단 함수 — 18가지 조합 전수"

D_A="aaaaaaaa"   # 배포본 지문
D_B="bbbbbbbb"   # 다른 지문

# 표: <찍힌지문상태> <배포본지문상태> <번호관계> <기대>
#   찍힌지문상태 : same | diff | empty
#   배포본지문상태: has  | none
#   번호관계     : newer(배포본이 최신) | equal | older(배포본이 더 오래됨)
T1_TABLE=(
  # 되돌림 방지가 언제나 먼저다 — 지문 상태와 무관하게 6가지 전부 skip:backward
  "same  has  older  skip:backward"
  "diff  has  older  skip:backward"
  "empty has  older  skip:backward"
  "same  none older  skip:backward"
  "diff  none older  skip:backward"
  "empty none older  skip:backward"

  # 배포본에 지문이 없다 (구형 배포본) — 예전처럼 번호로만 판단한다
  "same  none newer  refresh:version"
  "diff  none newer  refresh:version"
  "empty none newer  refresh:version"
  "same  none equal  skip:same"
  "diff  none equal  skip:same"
  "empty none equal  skip:same"

  # 프로젝트에 지문이 없다 = 이번 변경 이전의 정상 상태
  "empty has  newer  refresh:unstamped"
  "empty has  equal  refresh:unstamped"

  # 지문이 다르다 → 갱신. equal 칸이 이번 수정의 본체다.
  "diff  has  newer  refresh"
  "diff  has  equal  refresh"

  # 지문은 같다 — 번호가 낡았으면 예전 경로로 바로잡고, 아니면 할 일 없음
  "same  has  newer  refresh:version"
  "same  has  equal  skip:same"
)

T1_OK=0; T1_N=0
for row in "${T1_TABLE[@]}"; do
  read -r st pd vr want <<< "$row"
  T1_N=$((T1_N + 1))

  case "$st" in
    same)  stamped="$D_A" ;;
    diff)  stamped="$D_B" ;;
    empty) stamped=""     ;;
  esac
  case "$pd" in
    has)  payload="$D_A" ;;
    none) payload=""     ;;
  esac
  case "$vr" in
    newer) sver="2.3.0"; pver="2.4.0" ;;
    equal) sver="2.3.0"; pver="2.3.0" ;;
    older) sver="2.4.0"; pver="2.3.0" ;;
  esac

  got="$(scv_template_decide "$stamped" "$payload" "$sver" "$pver")"
  if [[ "$got" == "$want" ]]; then
    T1_OK=$((T1_OK + 1))
  else
    fail "T1 [$st/$pd/$vr] — expected [$want], got [$got]"
  fi
done
if [[ $T1_OK -eq $T1_N ]]; then
  ok "18가지 조합 전부 기대와 일치"
  echo "OK [T1] $T1_OK/$T1_N"
else
  echo "✖ [T1] $T1_OK/$T1_N"
fi

# 같은 입력을 100번 넣으면 100번 같은 답이어야 한다 (반복 가능성 자체를 검사).
REPEAT_FIRST="$(scv_template_decide "$D_B" "$D_A" "2.3.0" "2.3.0")"
REPEAT_SAME=1
for _ in $(seq 1 100); do
  [[ "$(scv_template_decide "$D_B" "$D_A" "2.3.0" "2.3.0")" == "$REPEAT_FIRST" ]] || REPEAT_SAME=0
done
eq "같은 입력 100회 → 같은 출력" "1" "$REPEAT_SAME"

# 되돌림 방지는 프리릴리스에서도 산다.
eq "프리릴리스: 배포본 2.3.0-rc1 vs 프로젝트 2.3.0 → 되돌리지 않음" \
   "skip:backward" "$(scv_template_decide "$D_B" "$D_A" "2.3.0" "2.3.0-rc1")"

# 번호가 비어 있으면(스탬프 이전) 되돌림 방지를 걸 근거가 없다 — 지문으로 간다.
eq "번호 없음 + 지문 다름 → 갱신" \
   "refresh" "$(scv_template_decide "$D_B" "$D_A" "" "")"

# 지문은 번호를 대체하지 않고 더한다. 두 경로가 동시에 살아 있어야 한다.
eq "지문 같음 + 번호 낡음 → 예전 경로로 바로잡음" \
   "refresh:version" "$(scv_template_decide "$D_A" "$D_A" "2.0.0" "2.3.0")"
eq "지문 다름 + 번호 같음 → 새 경로로 갱신" \
   "refresh" "$(scv_template_decide "$D_B" "$D_A" "2.3.0" "2.3.0")"

# ============================================================ T2. 정적 검사
echo
echo "T2. 판단 함수 — 부수효과 없음 (정적 검사)"

# 이 검사 자체가 순수함수다: 코드 텍스트를 받아 위반 목록을 낸다.
# 원칙이 문서에만 남지 않게 하는 장치 — 순수해야 할 자리에 효과가 섞이면 여기서 멈춘다.
#
# 대상은 판단 함수 둘뿐이다. scv_digest_fold 는 외부 해시 도구를 부르므로 제외한다
# (표준입력 → 표준출력의 결정적 변환이며 디스크를 만지지 않는다).
extract_fn() {
  awk -v fn="$1" '
    $0 ~ "^"fn"\\(\\) \\{" { inside = 1 }
    inside { print }
    inside && /^\}$/ { exit }
  ' "$LIB"
}

# 검사 전에 "부수효과가 아닌 것" 을 먼저 지운다. 그래야 과잉 탐지가 없다.
#   - 주석 줄
#   - 산술식 (( ... ))        — `<`, `>` 가 비교 연산자이지 리다이렉션이 아니다
#   - 히어스트링 <<<          — 문자열 전달이지 파일 읽기가 아니다
strip_benign() {
  grep -vE '^[[:space:]]*#' \
    | sed -E 's/\(\([^)]*\)\)/@ARITH@/g' \
    | sed -E 's/<<</@HERESTRING@/g'
}

# 남은 것에서 진짜 부수효과를 찾는다.
#   1. 금지된 명령이 명령 자리에 오는 것
#   2. 파일 리다이렉션 (> >> <)
#   3. 무작위
FORBIDDEN_CMD='(^|[;&|(][[:space:]]*|^[[:space:]]*)(date|curl|wget|git|ssh|mktemp|touch|rm|mv|cp|mkdir|sha256sum|shasum|md5|cat|head|tail|source)([[:space:]]|$)'
FORBIDDEN_REDIR='[^@<>&[:space:]][[:space:]]*(>>?|<)[[:space:]]*[^&@[:space:]]'
FORBIDDEN_RANDOM='\$RANDOM|\$\{RANDOM'

T2_VIOL=0
for fn in scv_ver_lt scv_template_decide; do
  body="$(extract_fn "$fn")"
  if [[ -z "$body" ]]; then
    fail "T2 — 함수 본문을 못 찾음: $fn"
    T2_VIOL=$(( T2_VIOL + 1 ))
    continue
  fi
  clean="$(printf '%s\n' "$body" | strip_benign)"
  hits="$(printf '%s\n' "$clean" \
    | grep -nE "$FORBIDDEN_CMD|$FORBIDDEN_REDIR|$FORBIDDEN_RANDOM" || true)"
  if [[ -n "$hits" ]]; then
    fail "T2 — $fn 에 부수효과가 있음:"
    printf '%s\n' "$hits" | sed 's/^/      /'
    T2_VIOL=$(( T2_VIOL + 1 ))
  else
    ok "$fn — 파일·시각·무작위·네트워크 호출 없음"
  fi
done

# 검사기 자체가 도는지 확인한다 — 통과만 하고 아무것도 안 보는 검사기는 무의미하다.
CANARY='canary() {
  local x
  x="$(date +%s)"
  cat /etc/hosts > /tmp/x
}'
canary_hits="$(printf '%s\n' "$CANARY" | strip_benign \
  | grep -cE "$FORBIDDEN_CMD|$FORBIDDEN_REDIR|$FORBIDDEN_RANDOM" || true)"
if [[ "${canary_hits:-0}" -ge 2 ]]; then
  ok "검사기 자체 확인 — 일부러 넣은 부수효과를 잡는다 (${canary_hits}건)"
else
  fail "T2 — 검사기가 부수효과를 못 잡는다 (canary ${canary_hits}건)"
  T2_VIOL=$(( T2_VIOL + 1 ))
fi

if [[ ${T2_VIOL} -eq 0 ]]; then echo "OK [T2]"; else echo "✖ [T2] 위반 ${T2_VIOL}건"; fi

# ============================================================ T3. 지문 결정성
echo
echo "T3. 지문 접기 — 결정적"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# "<해시>  <경로>" 줄 목록. 실제 빌드가 넘기는 모양과 같다.
LINES_A=$'aaa1  template/scv/SCV.md\nbbb2  template/scv/PROMOTE.md\nccc3  template/hooks/guard.sh'
# 같은 내용, 순서만 뒤집음
LINES_REV=$'ccc3  template/hooks/guard.sh\nbbb2  template/scv/PROMOTE.md\naaa1  template/scv/SCV.md'
# 파일 하나의 내용만 다름
LINES_CHANGED=$'aaa1  template/scv/SCV.md\nbbb9  template/scv/PROMOTE.md\nccc3  template/hooks/guard.sh'
# 파일 하나 추가
LINES_ADDED="$LINES_A"$'\nddd4  template/scv/REPORTING.md'
# 파일 하나 삭제
LINES_REMOVED=$'aaa1  template/scv/SCV.md\nbbb2  template/scv/PROMOTE.md'

d1="$(printf '%s\n' "$LINES_A"        | scv_digest_fold)"
d2="$(printf '%s\n' "$LINES_A"        | scv_digest_fold)"
drev="$(printf '%s\n' "$LINES_REV"    | scv_digest_fold)"
dchg="$(printf '%s\n' "$LINES_CHANGED"| scv_digest_fold)"
dadd="$(printf '%s\n' "$LINES_ADDED"  | scv_digest_fold)"
drem="$(printf '%s\n' "$LINES_REMOVED"| scv_digest_fold)"

eq "같은 입력 두 번 → 같은 지문"        "$d1" "$d2"
eq "순서만 다름 → 같은 지문"            "$d1" "$drev"
[[ "$d1" != "$dchg" ]] && ok "내용 한 글자 다름 → 다른 지문" || fail "T3 — 내용이 달라도 지문이 같다"
[[ "$d1" != "$dadd" ]] && ok "파일 추가 → 다른 지문"        || fail "T3 — 파일이 늘어도 지문이 같다"
[[ "$d1" != "$drem" ]] && ok "파일 삭제 → 다른 지문"        || fail "T3 — 파일이 줄어도 지문이 같다"
[[ "$d1" =~ ^[0-9a-f]{64}$ ]] && ok "지문이 64자리 16진수" || fail "T3 — 지문 모양이 이상함: $d1"

if [[ "$d1" == "$d2" && "$d1" == "$drev" && "$d1" != "$dchg" && "$d1" != "$dadd" && "$d1" != "$drem" ]]; then
  echo "OK [T3]"
else
  echo "✖ [T3]"
fi

# ============================================================ T4. 지문 신선도
echo
echo "T4. 배포본에 실린 지문이 현재 템플릿과 맞는가"

# 왜 이 검사가 있나: 지문이 오래되면 자동 갱신이 "같다" 고 판단해서 건너뛴다.
# 번호를 안 올려서 생기던 바로 그 문제가 지문 갱신을 잊는 형태로 되돌아온다.
# 사람이 잊어도 여기서 잡는다.
COMPUTE="$REPO_ROOT/scripts/compute-template-digest.sh"
DIGEST_FILE="$REPO_ROOT/TEMPLATE_DIGEST"

if [[ ! -x "$COMPUTE" && ! -f "$COMPUTE" ]]; then
  fail "T4 — 지문 계산 스크립트가 없음: $COMPUTE"
elif [[ ! -f "$DIGEST_FILE" ]]; then
  fail "T4 — 배포본에 지문 파일이 없음: $DIGEST_FILE"
else
  if bash "$COMPUTE" --check "$DIGEST_FILE" >/dev/null 2>&1; then
    ok "실린 지문이 현재 템플릿과 일치"
    echo "OK [T4]"
  else
    fail "T4 — 실린 지문이 오래됨. 다시 만들 것:"
    echo "        bash core/scripts/compute-template-digest.sh > core/TEMPLATE_DIGEST"
    bash "$COMPUTE" --check "$DIGEST_FILE" 2>&1 | sed 's/^/        /' || true
  fi

  # 지문 파일 모양도 본다 — 빈 파일이나 잘린 값이 조용히 들어가면 안 된다.
  STORED_RAW="$(tr -d '[:space:]' < "$DIGEST_FILE")"
  if [[ "$STORED_RAW" =~ ^[0-9a-f]{64}$ ]]; then
    ok "지문 파일이 64자리 16진수"
  else
    fail "T4 — 지문 파일 모양이 이상함: [${STORED_RAW}]"
  fi
fi

# ============================================================ 요약
echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
