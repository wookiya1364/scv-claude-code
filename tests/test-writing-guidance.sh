#!/usr/bin/env bash
# test-writing-guidance.sh — 글 모양 규칙(contracts/writing.md)이 판정 · 규약에 들어갔고, 묻는 횟수는 그대로인지 본다.
#
# T1 값 없는 통과 기준 경고(work 머리말) · T4 promote 개요 확인 — 묻는 지점 수 불변 · T5 실물 확인은 볼 곳을 짚어 ·
# T6 규칙 문서 하나를 규약들이 가리킨다. 표 칸 · 문단 길이(④)는 tests/test-check-readme.sh 가 본다.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/writing.sh
source "$CORE/scripts/lib/writing.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

# T1 — 판정과 work 머리말
tests_md=$'### T1. a\n\n- **Pass criterion**: 잘 동작한다\n\n### T2. b\n\n- **Pass criterion**: 종료 코드 0\n\n## Pass criteria\n\n- `OK readme` 출력'
v="$(scv_writing_vague_criteria "$(scv_writing_pass_criteria "$tests_md")")"
[[ "$v" == "잘 동작한다" ]] && ok "T1 vague criterion picked (1 of 3)" || bad "T1 vague criteria: got [$v]"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scv/promote/20260101-a-x"
printf -- '---\ntitle: x\nstatus: planned\n---\n# x\n' > "$T/scv/promote/20260101-a-x/PLAN.md"
printf '%s\n' "$tests_md" > "$T/scv/promote/20260101-a-x/TESTS.md"
rc=0; out="$(cd "$T" && git init -q && bash "$CORE/scripts/work.sh" 20260101-a-x 2>&1)" || rc=$?
n="$(printf '%s\n' "$out" | grep -c '^TESTS_VAGUE:' || true)"
[[ "$n" == 1 && "$rc" == 0 ]] && ok "T1 work header warns once, exit 0" || bad "T1 work header: TESTS_VAGUE=$n rc=$rc"

# T4 — 개요 확인이 폴더 승인이다, 묻는 지점 수는 바꾸기 전과 같다 (promote 11 · work 10)
asks() { grep -cE '^Question:|^ *Question:|[Aa]sk (once|the user|one)' "$1" || true; }
p="$(asks "$CORE/protocols/promote.md")"; w="$(asks "$CORE/protocols/work.md")"
[[ "$p" == 11 && "$w" == 10 ]] && ok "T4 ask points unchanged (promote $p · work $w)" || bad "T4 ask points: promote $p (want 11) · work $w (want 10)"
grep -q '^### Step 4.5 — Outline first: this is the per-folder approval' "$CORE/protocols/promote.md" \
  && grep -q '^### Step 5 — Write scaffolds (only after the Step 4.5 approval per folder)' "$CORE/protocols/promote.md" \
  && ok "T4 outline step precedes writing and is the approval" || bad "T4 outline step missing or not linked from Step 5"

# T5 — 실물 확인 질문은 볼 곳을 짚는다, 보기 · 한 번 규칙은 그대로
sr="$CORE/contracts/show-real.md"
grep -q '"글자가 다 읽히나요?"처럼 좁게' "$sr" && grep -q '보기는 2개 이상' "$sr" && grep -q '처음 돌아가는 순간 한 번이다' "$sr" \
  && ok "T5 show-real asks a pointed question, options and once-rule kept" || bad "T5 show-real wording"

# T6 — 규칙 문서 하나, 규칙 6개, 규약들이 가리킨다
wr="$CORE/contracts/writing.md"
r="$(grep -cE '^[1-6]\. \*\*' "$wr" || true)"
[[ "$r" == 6 ]] && ok "T6 writing contract has 6 rules" || bad "T6 writing rules: $r (want 6)"
refs="$(grep -rl 'contracts/writing.md' "$CORE/protocols" | wc -l | tr -d ' ')"
(( refs >= 3 )) && ok "T6 $refs protocols point to the writing contract" || bad "T6 pointers: $refs (want >= 3)"

# 판정 숫자는 한 곳 — 규칙 문서는 숫자 대신 함수 이름을 가리킨다
grep -qE '(40|60|300|600) ?자' "$wr" && bad "T6 writing contract repeats the limits" || ok "T6 limits live only in lib/writing.sh"

(( fail )) && exit 1
echo "writing-guidance: all checks passed"
