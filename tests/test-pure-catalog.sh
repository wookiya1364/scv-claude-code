#!/usr/bin/env bash
# test-pure-catalog.sh — 순수함수 사전: 빈 칸 · 틀린 예시 · 중복 · 낡은 사전을 잡는지 본다.
#
# 계약: core/contracts/purity.md "사전 — 만들기 전에 찾아 재사용한다"
# 계획: scv/archive/20261101-wookiya1364-pure-function-catalog/TESTS.md
#
# Run: bash core/tests/test-pure-catalog.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TOOL="$CORE/scripts/pure-catalog.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-pure-catalog.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

# fixture <이름> — 빈 시험 폴더(lib + 사전)를 만든다
fixture() { rm -rf "$WORK/$1"; mkdir -p "$WORK/$1/lib" "$WORK/$1/cat"; }
# run <이름> <build|check> [더 줄 인자…] — 출력 전체를 OUT, 종료 코드를 RC 에
run() {
  local n="$1" m="$2"; shift 2
  OUT="$(bash "$TOOL" "$m" --root "$WORK/$n" --base "$WORK/$n" --catalog "$WORK/$n/cat" "$@" 2>&1)"; RC=$?
}

TRIM_OK='# @pure
# 역할: 앞뒤 공백을 지운다
# 종류: 다듬기
# 예: "  a " → "a"
t_ok() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
  printf "%s\n" "$s"
}'

echo "T1. 역할 · 종류 · 예시가 빠지면 실패"
fixture t1
cat > "$WORK/t1/lib/a.sh" <<EOF
$TRIM_OK

# @pure
# 종류: 세기
# 예: "ab" → "2"
no_role() { printf '%s\n' "\${#1}"; }

# @pure
# 역할: 길이를 센다
# 종류: 세기
no_ex() { printf '%s\n' "\${#1}"; }
EOF
run t1 check
if [[ $RC -eq 1 ]] && grep -q 'no_role: 역할 없음' <<<"$OUT" && grep -q 'no_ex: 예 없음' <<<"$OUT" && ! grep -q 't_ok:' <<<"$OUT"; then
  ok "빠진 두 함수와 칸 이름만 나온다"
else fail "T1 — rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; fi

echo "T2. 목록에 없는 종류는 실패"
fixture t2
cat > "$WORK/t2/lib/a.sh" <<'EOF'
# @pure
# 역할: 길이를 센다
# 종류: 아무거나
# 예: "ab" → "2"
odd_kind() { printf '%s\n' "${#1}"; }
EOF
run t2 check
if [[ $RC -eq 1 ]] && grep -q 'odd_kind: 모르는 종류: 아무거나' <<<"$OUT"; then ok "모르는 종류를 막는다"
else fail "T2 — rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; fi

echo "T3. 틀린 예시는 실패, 맞는 예시는 통과"
fixture t3
cat > "$WORK/t3/lib/a.sh" <<EOF
$TRIM_OK

# @pure
# 역할: 앞뒤 공백을 지운다 (일부러 틀린 예시)
# 종류: 다듬기
# 예: "  a " → "b"
t_bad() {
  local s="\${1:-}"
  s="\${s#"\${s%%[![:space:]]*}"}"; s="\${s%"\${s##*[![:space:]]}"}"
  printf "%s\n" "\$s"
}
EOF
cat > "$WORK/t3/cat/duplicates-allowed.tsv" <<'EOF'
t_bad	t_ok	예시만 다른 시험용 짝
EOF
run t3 check
if [[ $RC -eq 1 ]] && grep -q 't_bad 예시가 틀렸다' <<<"$OUT" && grep -q '적힌: b \[0\] · 실제: a \[0\]' <<<"$OUT" && ! grep -q 't_ok 예시' <<<"$OUT"; then
  ok "틀린 예시만 적힌 값 · 실제 값과 함께 잡는다"
else fail "T3 — rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; fi

echo "T4. 사전은 주석에서 생성된다 — 차례 + 종류별 파일"
fixture t4
cat > "$WORK/t4/lib/a.sh" <<EOF
$TRIM_OK

# @pure
# 역할: 앞뒤 공백을 지우고 대괄호로 감싼다
# 종류: 다듬기
# 예: " a " → "[a]"
t_wrap() { printf '[%s]\n' "\$(t_ok "\$1")"; }

# @pure
# 역할: 두 수 중 앞이 작으면 참
# 종류: 비교
# 예: "1" "2" → [0]
# 예: "2" "1" → [1]
t_lt() { [[ "\$1" -lt "\$2" ]]; }
EOF
run t4 build
EXPECT_INDEX='| 다듬기 | 글자를 정리한다 — 공백 · 대소문자 · 이스케이프 · 자르기 | 2 | [tidy.md](tidy.md) |
| 비교 | 둘을 비교해 순서나 같음을 낸다 — 버전 · 숫자 · 집합 | 1 | [compare.md](compare.md) |'
if [[ $RC -eq 0 && -f "$WORK/t4/cat/INDEX.md" && -f "$WORK/t4/cat/tidy.md" && -f "$WORK/t4/cat/compare.md" ]] \
   && [[ "$(grep '^| [^종-]' "$WORK/t4/cat/INDEX.md")" == "$EXPECT_INDEX" ]] \
   && grep -q '^### t_wrap$' "$WORK/t4/cat/tidy.md" && grep -q '^- 위치: lib/a.sh · @pure · sh$' "$WORK/t4/cat/compare.md" \
   && grep -q '^- 예: `"2" "1" → \[1\]`$' "$WORK/t4/cat/compare.md"; then
  ok "차례 두 줄(개수 2 · 1)과 종류 파일 두 개, 함수마다 역할 · 위치 · 예"
else fail "T4 — rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; ls "$WORK/t4/cat" | sed 's/^/      /'; fi

echo "T5. 사전이 코드와 어긋나면 실패"
run t4 check
[[ $RC -eq 0 ]] && ok "손대지 않으면 통과" || { fail "T5 기준 — rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; }
printf '\n손으로 더한 줄\n' >> "$WORK/t4/cat/tidy.md"
run t4 check
if [[ $RC -eq 1 ]] && grep -q '사전이 낡았다: tidy.md' <<<"$OUT"; then ok "사전을 손으로 고치면 잡는다"
else fail "T5a — rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; fi
run t4 build >/dev/null
sed 's/두 수 중 앞이 작으면 참/앞 수가 뒤 수보다 작으면 참/' "$WORK/t4/lib/a.sh" > "$WORK/t4/a.tmp" && mv "$WORK/t4/a.tmp" "$WORK/t4/lib/a.sh"
run t4 check
if [[ $RC -eq 1 ]] && grep -q '사전이 낡았다: compare.md' <<<"$OUT"; then ok "역할 주석을 바꾸고 다시 안 만들면 잡는다"
else fail "T5b — rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; fi

echo "T6. 크기 한도를 넘는 종류는 실패, 세부 종류를 붙이면 쪼개진다"
fixture t6
{
  for i in 1 2 3; do
    printf '# @pure\n# 역할: 길이 %s\n# 종류: 세기\n# 예: "ab" → "%s"\nlen%s() { printf "%%s\\n" "$(( %s + 1 ))"; }\n\n' "$i" "$((i + 1))" "$i" "$i"
  done
} > "$WORK/t6/lib/a.sh"
run t6 check --limit 14
if [[ $RC -eq 1 ]] && grep -q '사전 파일이 너무 크다: count.md' <<<"$OUT"; then ok "한도를 넘으면 세부 종류를 붙이라고 막는다"
else fail "T6a — rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; fi
sed 's/^# 종류: 세기$/# 종류: 세기\/len/' "$WORK/t6/lib/a.sh" | awk '/^# 종류: 세기\/len$/ { n++; if (n == 3) $0 = "# 종류: 세기/other" } { print }' > "$WORK/t6/a.tmp" && mv "$WORK/t6/a.tmp" "$WORK/t6/lib/a.sh"
run t6 build --limit 14
run t6 check --limit 14
big="$(find "$WORK/t6/cat" -name '*.md' -exec awk 'END { if (NR > 14) print FILENAME }' {} \;)"
if [[ $RC -eq 0 && -f "$WORK/t6/cat/count-len.md" && -f "$WORK/t6/cat/count-other.md" && -z "$big" ]] \
   && grep -q 'count-len.md' "$WORK/t6/cat/INDEX.md"; then ok "세부 종류마다 파일이 나뉘고 어떤 파일도 한도를 넘지 않는다"
else fail "T6b — rc=$RC big=[$big]"; printf '%s\n' "$OUT" | sed 's/^/      /'; ls "$WORK/t6/cat" | sed 's/^/      /'; fi

echo "T7. 같은 입력 → 같은 출력이면 중복 의심, 줄바꿈만 다른 함수는 아니다"
fixture t7
cat > "$WORK/t7/lib/a.sh" <<'EOF'
# @pure
# 역할: 앞뒤 공백 · 탭 · 줄바꿈을 지운다
# 종류: 다듬기
# 예: "  a b " → "a b"
trim_expand() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
}

# @pure
# 역할: 공백류를 앞뒤에서 하나씩 떼어 낸다
# 종류: 다듬기
# 예: $'\t x \n' → "x"
trim_loop() {
  local s="${1:-}"
  while [[ "$s" == [[:space:]]* ]]; do s="${s:1}"; done
  while [[ "$s" == *[[:space:]] ]]; do s="${s%?}"; done
  printf '%s\n' "$s"
}

# @pure
# 역할: 앞뒤 공백 · 탭만 지운다 (줄바꿈은 남긴다)
# 종류: 다듬기
# 예: "  a " → "a"
trim_blank() {
  local s="${1:-}"
  s="${s#"${s%%[![:blank:]]*}"}"; s="${s%"${s##*[![:blank:]]}"}"
  printf '%s\n' "$s"
}
EOF
run t7 build
run t7 check
pairs="$(grep -c '중복 의심' <<<"$OUT")"
if [[ $RC -eq 1 && "$pairs" == 1 ]] && grep -q '중복 의심: trim_expand · trim_loop' <<<"$OUT"; then
  ok "모양이 다른 같은 함수 한 짝만 잡는다"
else fail "T7 — rc=$RC pairs=$pairs"; printf '%s\n' "$OUT" | sed 's/^/      /'; fi

echo "T8. 예외 목록 — 이유가 있어야 통과"
printf 'trim_expand\ttrim_loop\t시험용 — 같은 일을 다른 방식으로 쓴 예\n' > "$WORK/t7/cat/duplicates-allowed.tsv"
run t7 check
[[ $RC -eq 0 ]] && ok "이유와 함께 적으면 통과" || { fail "T8a — rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; }
printf 'trim_expand\ttrim_loop\t\n' > "$WORK/t7/cat/duplicates-allowed.tsv"
run t7 check
if [[ $RC -eq 1 ]] && grep -q '중복 예외에 이유가 없다: trim_expand · trim_loop' <<<"$OUT"; then ok "이유 없는 예외는 막는다"
else fail "T8b — rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      /'; fi

echo "T9. 이 저장소 — 표식 함수 전부가 갖췄고 사전이 최신"
OUT="$(bash "$TOOL" check 2>&1)"; RC=$?
if [[ $RC -eq 0 ]]; then ok "$(grep '^OK  catalog' <<<"$OUT" | sed 's/^OK  catalog: //')"
else fail "T9 — 이 저장소 검사 실패:"; printf '%s\n' "$OUT" | tail -25 | sed 's/^/      /'; fi

echo "T13. 맥 기본 bash(3.2)에서도 예시가 전부 맞는다"
# 맥 사용자 셸은 /bin/bash 3.2 일 수 있다. bash 4 문법(${x,,} 등)은 거기서 조용히 깨진다 —
# 이 시험이 그것을 처음 찾았다(기록 색인 종류 맞추기 · 결정 이름 · 작성자 이름 · [a-z] 범위 3곳, 2026-11-01).
if [[ -x /bin/bash ]] && /bin/bash -c '[[ ${BASH_VERSINFO[0]} -lt 4 ]]'; then
  B32="$WORK/b32"; mkdir -p "$B32"; ln -sf /bin/bash "$B32/bash"
  # UTF-8 지역 설정이라야 3.2 의 함정([a-z] 가 대문자까지 맞춤)이 드러난다 — 맥 CI 의 기본도 en_US.UTF-8.
  OUT="$(LC_ALL=en_US.UTF-8 PATH="$B32:$PATH" /bin/bash "$TOOL" check 2>&1)"; RC=$?
  if [[ $RC -eq 0 ]]; then ok "bash $(/bin/bash -c 'echo $BASH_VERSION') 로 $(grep '^OK  catalog' <<<"$OUT" | sed 's/^OK  catalog: //; s/ ·.*//') 예시 통과"
  else fail "T13 — bash 3.2 에서 어긋남:"; printf '%s\n' "$OUT" | grep '^✖' | head -10 | sed 's/^/      /'; fi
else
  echo "  - 건너뜀: 이 기계에는 bash 3.2 가 없다 (맥 CI 에서 돈다)"
fi

echo "T11. 구현 규약이 차례부터 읽게 한다"
for proto in work codegen; do
  f="$CORE/protocols/$proto.md"
  # 사전은 저장소의 scv/ 아래 — 래퍼 설치본(코어 사본)에는 없으니 그때는 규약 글만 본다.
  if grep -q 'scv/core/catalog/pure/INDEX.md' "$f" && { [[ ! -d "$CORE/../scv" ]] || [[ -f "$CORE/../scv/core/catalog/pure/INDEX.md" ]]; }; then ok "$proto 규약에 차례 읽기 단계, 경로가 실제 파일"
  else fail "T11 — $proto 규약에 차례 읽기 단계가 없거나 사전이 없다"; fi
done

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
