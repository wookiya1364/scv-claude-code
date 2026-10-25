#!/usr/bin/env bash
# test-plan-path-links.sh — work.sh 의 단계 줄 연결 경고 (0.70.4).
#
# Suggested path 줄마다 하는 일이 보여야 단계 흐름(scv-dashboard)이 단계마다 '하는 일'을
# 보여 준다: " — `단계`" 로 파이프라인 표와 잇거나, " — <하는 일 한 줄>" 로 말로 적는다.
# 둘 다 없는 줄, 표에 없는 이름은 PLAN_LINK: 경고 한 줄 — 막지는 않는다.
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WS="$HERE/../scripts/work.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { echo "  ✗ $1"; fail=$((fail+1)); }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
SLUG=20261025-u-links

run() {  # <plan body> → work.sh 의 PLAN_LINK 줄만
  local p="$WORK/p$RANDOM"
  mkdir -p "$p/scv/promote/$SLUG"
  printf '%s\n' "$1" > "$p/scv/promote/$SLUG/PLAN.md"
  printf '# T\n## How to run\n```bash\ntrue\n```\n' > "$p/scv/promote/$SLUG/TESTS.md"
  ( cd "$p" && bash "$WS" "$SLUG" 2>/dev/null ) | grep '^PLAN_LINK: ' || true
}

TABLE='---
title: 견본
status: planned
---
## 순수함수 · 파이프라인 (Pure functions & pipeline)

| # | 단계 | 하는 일 | 받는 값 → 돌려주는 값 | 순수/부수효과 |
|---|---|---|---|---|
| 1 | `alpha` | 나눈다 | 글 → 목록 | 순수 |
| 2 | 세션 저장 · 기록 | 저장한다 | 목록 → 없음 | 부수효과 (출구) |
'

# T1. 모든 줄이 잇거나 말로 적으면 경고가 없다 — 진행 표시, 가운뎃점 든 이름, 여러 이름 포함
o=$(run "$TABLE
## Suggested path

1. 나누기. — \`alpha\`
2. [x] 저장. — \`세션 저장 · 기록\`, \`alpha\`
3. 시나리오 쓰기. — 갈래를 시나리오에 넣는다")
[[ -z "$o" ]] && ok || bad "T1 경고가 없어야 함: $o"

# T2. 꼬리가 없는 줄은 그 번호로 경고한다
o=$(run "$TABLE
## Suggested path

1. 나누기. — \`alpha\`
2. 녹음하기.")
[[ "$o" == *'step 2 has no'* && $(grep -c . <<<"$o") == 1 ]] && ok || bad "T2 꼬리 없는 줄: $o"

# T3. 표에 없는 이름은 그 이름과 번호로 경고한다
o=$(run "$TABLE
## Suggested path

1. 나누기. — \`alpha\`, \`gamma\`")
[[ "$o" == *'step 1 names `gamma`'* && $(grep -c . <<<"$o") == 1 ]] && ok || bad "T3 표에 없는 이름: $o"

# T4. 옛 '## Steps' 절도 같은 검사를 받는다
o=$(run "$TABLE
## Steps

1. 나누기.")
[[ "$o" == *'step 1 has no'* ]] && ok || bad "T4 Steps 절: $o"

# T5. 경고가 있어도 work.sh 는 끝까지 간다(막지 않음)
p="$WORK/block"; mkdir -p "$p/scv/promote/$SLUG"
printf '%s\n## Suggested path\n\n1. 녹음하기.\n' "$TABLE" > "$p/scv/promote/$SLUG/PLAN.md"
printf '# T\n## How to run\n```bash\ntrue\n```\n' > "$p/scv/promote/$SLUG/TESTS.md"
full=$( cd "$p" && bash "$WS" "$SLUG" 2>/dev/null ); rc=$?
[[ $rc == 0 && "$full" == *'=== related documents'* ]] && ok || bad "T5 막으면 안 됨: rc=$rc"

# T6. 계획서 양식의 단계 줄 견본은 이 검사를 통과하는 모양이다
PROMOTE="$HERE/../protocols/promote.md"
grep -qF '1. <TODO> — `<단계>`' "$PROMOTE" && grep -qF '3. <TODO> — <TODO: 하는 일 한 줄, 쉬운 말>' "$PROMOTE" && ok || bad "T6 양식 견본"

echo "test-plan-path-links: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
