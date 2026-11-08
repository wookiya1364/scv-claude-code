#!/usr/bin/env bash
# test-deck-picture-spots.sh — 0.85.0 발표 자료 '그림 자리' 제안: 그림이 없는 구역 중 순서 있는 단계 3개 이상,
# 또는 문단 · 목록의 화살표(→) 3개 이상인 곳을 최대 3곳 짚는다. 문서는 바꾸지 않는다(제안만).
#   P1 단계 3개 구역 → 제안 · P2 단계 2개 → 없음 · P3 그림(mermaid)이 이미 있는 구역 → 없음
#   P4 문단 화살표 3개 → 제안, 표 · 코드의 화살표는 셈하지 않음 · P5 후보가 4곳이어도 3곳만 · P6 절차 문서 연결
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$HERE/.."
DECKUI_DIR="$(bash "$ROOT/scripts/deck-runtime.sh" ensure)" || { echo "FAIL test-deck-picture-spots: deck runtime unavailable"; exit 1; }
DECKDOC="$DECKUI_DIR/scripts/deckdoc"
command -v node >/dev/null 2>&1 || { echo "SKIP test-deck-picture-spots: node not found"; exit 0; }
if [[ ! -d "$DECKDOC/node_modules" ]]; then
  command -v pnpm >/dev/null 2>&1 || { echo "SKIP test-deck-picture-spots: pnpm not found"; exit 0; }
  ( cd "$DECKDOC" && pnpm install ) >/dev/null 2>&1 || { echo "SKIP test-deck-picture-spots: deckdoc install failed"; exit 0; }
fi

fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
lint() {  # <md 본문> → doc.mjs 의 LINT 줄들
  printf '%s\n' "$1" > "$TMP/in.md"
  node "$DECKDOC/doc.mjs" "$TMP/in.md" spots --out "$TMP/out.html" --no-source 2>&1 | grep -E '^LINT|⚠'
}

o="$(lint $'# 문서\n\n## 세 단계\n\n1. 하나\n2. 둘\n3. 셋\n')"
grep -qF 'Picture spot: "세 단계" — 3 ordered steps' <<<"$o" && ok "P1 단계 3개 구역 제안" || bad "P1 [$o]"

o="$(lint $'# 문서\n\n## 두 단계\n\n1. 하나\n2. 둘\n')"
! grep -qF 'Picture spot' <<<"$o" && ok "P2 단계 2개는 제안 없음" || bad "P2 [$o]"

o="$(lint $'# 문서\n\n## 그림 있음\n\n1. 하나\n2. 둘\n3. 셋\n\n```mermaid\nflowchart LR\n  A --> B\n```\n')"
! grep -qF 'Picture spot' <<<"$o" && ok "P3 그림이 있는 구역은 제안 없음" || bad "P3 [$o]"

o="$(lint $'# 문서\n\n## 글 속 흐름\n\n받음 → 고침 → 검사 → 내보냄.\n\n## 표 속 화살표\n\n| 단계 | 받는 값 → 돌려주는 값 |\n|---|---|\n| a | 원문 → 값 |\n| b | 값 → 결과 |\n')"
grep -qF 'Picture spot: "글 속 흐름" — 3 arrows' <<<"$o" && ! grep -qF '"표 속 화살표"' <<<"$o" \
  && ok "P4 문단 화살표는 제안, 표 화살표는 셈하지 않음" || bad "P4 [$o]"

md='# 문서'; for s in 가 나 다 라; do md+=$'\n\n## 구역 '"$s"$'\n\n1. 하나\n2. 둘\n3. 셋'; done
o="$(lint "$md")"
n="$(grep -cF 'Picture spot' <<<"$o")"
[[ "$n" == 3 ]] && grep -qF '"구역 가"' <<<"$o" && ! grep -qF '"구역 라"' <<<"$o" \
  && ok "P5 후보 4곳이어도 읽는 순서로 3곳만" || bad "P5 n=$n [$o]"

grep -qF 'Picture spot' "$ROOT/protocols/deck.md" && grep -qF 'only from that section' "$ROOT/protocols/deck.md" \
  && ok "P6 절차 문서가 그림 자리 흐름을 적음" || bad "P6 protocols/deck.md 에 그림 자리 흐름 없음"

if (( fail )); then echo "── test-deck-picture-spots: FAIL"; exit 1; fi
echo "── test-deck-picture-spots: 6 passed"
