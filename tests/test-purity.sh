#!/usr/bin/env bash
# test-purity.sh — 순수성 계약이 지켜지는지 저장소 전체에서 본다.
#
# 계약: core/contracts/purity.md
#
# 이 검사가 없으면 "순수함수로 만들자" 는 문서에만 남고 두 달 뒤에 원래대로
# 돌아간다. 지켜지는지 기계가 봐야 한다.
#
# Run: bash core/tests/test-purity.sh
set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
CHECK="$REPO_ROOT/scripts/check-purity.sh"
CONTRACT="$REPO_ROOT/contracts/purity.md"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

[[ -f "$CHECK" ]]    || { echo "✖ 검사기가 없다: $CHECK"; exit 1; }
[[ -f "$CONTRACT" ]] || { echo "✖ 계약 문서가 없다: $CONTRACT"; exit 1; }

echo "T1. 검사기 자신이 도는가"
# 통과만 하고 아무것도 안 보는 검사기는 없느니만 못하다.
if bash "$CHECK" --self-test >/dev/null 2>&1; then
  ok "일부러 넣은 부수효과를 잡고, 멀쩡한 것은 통과시킨다"
else
  fail "검사기 자체 확인 실패 — 아래 출력을 볼 것"
  bash "$CHECK" --self-test 2>&1 | sed 's/^/      /'
fi

echo
echo "T2. 선언된 함수가 실제로 약속을 지키는가"
OUT="$(bash "$CHECK" "$REPO_ROOT/scripts" 2>&1)"
if [[ $? -eq 0 ]] && grep -q '^OK  purity' <<<"$OUT"; then
  ok "$(grep '^OK  purity' <<<"$OUT" | sed 's/^OK  purity: //')"
else
  fail "순수성 위반:"
  printf '%s\n' "$OUT" | sed 's/^/      /'
fi

echo
echo "T3. 선언이 실제로 존재하는가"
# 표식이 하나도 없으면 검사가 아무것도 안 보면서 통과한다 — 가장 나쁜 상태다.
N="$(bash "$CHECK" --list "$REPO_ROOT/scripts" 2>/dev/null | grep -cE '^@(pure|deterministic)' || true)"
if [[ "${N:-0}" -ge 5 ]]; then
  ok "순수부로 선언된 함수 ${N}개 (빈 검사가 아니다)"
else
  fail "선언된 함수가 ${N}개뿐 — 검사가 사실상 아무것도 안 보고 있다"
fi

echo
echo "T4. 계약 문서가 검사와 같은 것을 말하는가"
for anchor in '# @pure' '# @deterministic' 'check-purity.sh' '--self-test' '알려진 한계'; do
  if grep -qF -e "$anchor" "$CONTRACT"; then
    ok "계약에 [$anchor] 가 있다"
  else
    fail "계약에 [$anchor] 가 없다 — 문서와 검사가 어긋났다"
  fi
done

echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
