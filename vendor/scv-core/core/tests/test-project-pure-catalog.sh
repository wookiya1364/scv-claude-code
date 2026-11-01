#!/usr/bin/env bash
# test-project-pure-catalog.sh — 프로젝트 순수함수 사전: 어느 언어든 그 저장소의 scv/core 에.
#
# 계약: core/contracts/purity.md "사전" · 계획: scv/archive/20261101-wookiya1364-project-pure-catalog/TESTS.md
#   P1 여러 언어의 표식을 이름으로 찾는다     P2 사전은 그 저장소의 scv/core/catalog/pure
#   P3 빈 칸은 언어 상관없이 실패             P4 셸은 실행 · 다른 언어는 칸만, 숫자로 밝힘
#   P5 같은 언어끼리 같은 입출력은 중복 의심, 다른 언어끼리는 '다른 언어 짝'으로 표기
#   P6 제외 폴더                              P7 scv-core 자신은 test-pure-catalog.sh 가 본다
#   P8 래퍼 설치본(코어 사본)에서 프로젝트 모드 P9 규약
# Run: bash core/tests/test-project-pure-catalog.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TOOL="$CORE/scripts/pure-catalog.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-project-catalog.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

mk_repo() {  # mk_repo <이름> — 여러 언어 함수가 든 git 저장소
  local d="$WORK/$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/lib" "$d/tests" "$d/node_modules/x"
  ( cd "$d" && git init -q && git config user.email t@x && git config user.name t )
  cat > "$d/src/Calc.java" <<'EOF'
/**
 * @pure add
 * 역할: 두 정수를 더한다
 * 종류: 세기
 * 예: 1 2 → 3
 */
public static int add(int a, int b) { return a + b; }
EOF
  cat > "$d/src/clamp.c" <<'EOF'
// @pure clamp
// 역할: 값을 lo..hi 범위로 자른다
// 종류: 다듬기
// 예: 5 0 3 → 3
int clamp(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }
EOF
  cat > "$d/src/vec.rs" <<'EOF'
/// @pure dot
/// 역할: 두 벡터의 내적
/// 종류: 세기
/// 예: "[1,2]" "[3,4]" → 11
pub fn dot(a: &[i32], b: &[i32]) -> i32 { a.iter().zip(b).map(|(x, y)| x * y).sum() }
EOF
  cat > "$d/src/date.ts" <<'EOF'
// @pure formatDate
// 역할: 날짜를 YY/MM/DD 로
// 종류: 변환
// 예: "2026-01-02" → "26/01/02"
export const formatDate = (s: string) => s.slice(2).replace(/-/g, "/");
EOF
  cat > "$d/src/util.py" <<'EOF'
# @pure fmt_date
# 역할: 날짜를 짧게 쓴다
# 종류: 변환
# 예: "2026-01-02" → "26/01/02"
def fmt_date(s): return s[2:].replace("-", "/")
EOF
  cat > "$d/lib/trim.sh" <<'EOF'
# @pure
# 역할: 앞뒤 공백을 지운다
# 종류: 다듬기
# 예: "  a " → "a"
p_trim() { local s="${1:-}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s\n' "$s"; }
EOF
  printf '// @pure inTests\n// 역할: x\n// 종류: 세기\n// 예: 1 → 1\nfunction inTests(){}\n' > "$d/tests/t.js"
  printf '// @pure inDeps\n// 역할: x\n// 종류: 세기\n// 예: 2 → 2\nfunction inDeps(){}\n' > "$d/node_modules/x/i.js"
  ( cd "$d" && git add -A && git commit -qm init )
  printf '%s' "$d"
}
names() { grep -h '^### ' "$1"/scv/core/catalog/pure/*.md 2>/dev/null | sed 's/^### //' | LC_ALL=C sort | tr '\n' ' '; }

echo "P1. 여러 언어의 표식을 이름으로 찾는다"
R="$(mk_repo p1)"
OUT="$(cd "$R/src" && bash "$TOOL" build --project 2>&1)"
[[ "$(names "$R")" == "add clamp dot fmt_date formatDate p_trim " ]] && ok "자바 · C · 러스트 · TS · 파이썬 · 셸 여섯" || fail "P1 [$(names "$R")] $OUT"
grep -q '^- 위치: src/vec.rs · @pure · rs$' "$R/scv/core/catalog/pure/count.md" && ok "위치에 파일 · 언어" || fail "P1 위치 줄"

echo "P2. 사전은 그 저장소의 scv/core/catalog/pure 에만"
extra="$(cd "$R" && git status --porcelain | grep -v '^?? scv/' || true)"
[[ -f "$R/scv/core/catalog/pure/INDEX.md" && -z "$extra" ]] && ok "사전 폴더 말고는 바뀐 것 없음" || fail "P2 [$extra]"

echo "P3. 빈 칸은 언어 상관없이 실패"
R="$(mk_repo p3)"; sed -i.bak '/예: "\[1,2\]"/d' "$R/src/vec.rs" && rm -f "$R/src/vec.rs.bak"
OUT="$(bash "$TOOL" check --project "$R" 2>&1)"; RC=$?
[[ $RC -eq 1 ]] && grep -q 'dot: 예 없음' <<<"$OUT" && ok "러스트 함수 '예 없음'" || fail "P3 rc=$RC $OUT"

echo "P4. 셸은 실행, 다른 언어는 칸만 — 숫자로 밝힘"
R="$(mk_repo p4)"; bash "$TOOL" build --project "$R" >/dev/null 2>&1
OUT="$(bash "$TOOL" check --project "$R" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] && grep -q '예시 실행 1 · 칸만 5' <<<"$OUT" && ok "실행 1 · 칸만 5" || fail "P4a rc=$RC $OUT"
sed -i.bak 's/# 예: "  a " → "a"/# 예: "  a " → "b"/' "$R/lib/trim.sh" && rm -f "$R/lib/trim.sh.bak"
OUT="$(bash "$TOOL" check --project "$R" 2>&1)"
grep -q 'p_trim 예시가 틀렸다' <<<"$OUT" && ! grep -q '예시가 틀렸다.*\(add\|clamp\|dot\|formatDate\|fmt_date\)' <<<"$OUT" && ok "틀린 셸 예시만 잡힌다" || fail "P4b $OUT"

echo "P5. 같은 언어 같은 입출력은 중복 의심, 다른 언어는 짝 표기"
R="$(mk_repo p5)"; bash "$TOOL" build --project "$R" >/dev/null 2>&1
grep -q '^- 다른 언어 짝: fmt_date (py)$' "$R/scv/core/catalog/pure/convert.md" && grep -q '^- 다른 언어 짝: formatDate (ts)$' "$R/scv/core/catalog/pure/convert.md" \
  && ok "TS · 파이썬 짝이 서로의 항목에" || fail "P5a 짝 표기 없음"
OUT="$(bash "$TOOL" check --project "$R" 2>&1)"
! grep -q '중복 의심:' <<<"$OUT" && ok "다른 언어 짝은 중복으로 막지 않는다" || fail "P5b $OUT"
cat > "$R/src/date2.ts" <<'EOF'
// @pure shortDate
// 역할: 날짜를 줄인다
// 종류: 변환
// 예: "2026-01-02" → "26/01/02"
export const shortDate = (s: string) => s.slice(2).split("-").join("/");
EOF
( cd "$R" && git add -A && git commit -qm dup )
OUT="$(bash "$TOOL" check --project "$R" 2>&1)"
grep -q '중복 의심: formatDate · shortDate' <<<"$OUT" && ok "같은 TS 끼리는 중복 의심" || fail "P5c $OUT"

echo "P6. 제외 폴더"
R="$(mk_repo p6)"; bash "$TOOL" build --project "$R" >/dev/null 2>&1
[[ "$(names "$R")" != *inTests* && "$(names "$R")" != *inDeps* ]] && ok "tests · node_modules 는 기본으로 빠진다" || fail "P6a [$(names "$R")]"
SCV_CATALOG_EXCLUDE="node_modules" bash "$TOOL" build --project "$R" >/dev/null 2>&1
[[ "$(names "$R")" == *inTests* && "$(names "$R")" != *inDeps* ]] && ok "설정으로 제외 목록을 바꾼다" || fail "P6b [$(names "$R")]"

echo "P8. 래퍼 설치본(코어 사본)에서 프로젝트 모드"
COPY="$WORK/plugin/vendor/scv-core"; mkdir -p "$COPY"; cp -R "$CORE" "$COPY/core"
R="$(mk_repo p8)"
(cd "$R" && bash "$COPY/core/scripts/pure-catalog.sh" build --project >/dev/null 2>&1)
[[ -f "$R/scv/core/catalog/pure/INDEX.md" && ! -e "$WORK/plugin/vendor/scv-core/scv" ]] && ok "사용자 저장소에만 생긴다" || fail "P8"

echo "P9. 규약 — 어느 프로젝트든 차례부터"
for proto in work codegen; do
  grep -q 'pure-catalog.sh build --project' "$CORE/protocols/$proto.md" && ok "$proto 규약" || fail "P9 $proto 규약에 프로젝트 사전 단계 없음"
done

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
