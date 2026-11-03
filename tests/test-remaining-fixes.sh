#!/usr/bin/env bash
# test-remaining-fixes.sh — 남은 문제 정리(계획 20261103-wookiya1364-remaining-fixes-078 T1–T6).
#
# ① 프로젝트 밖 등록 거절 ② 막을 때 '고친 부분만' 안내 ③ 중간 보고 언어 검사 ④ 가이드 경로를 지금 설치본으로 ⑥ 비슷한 충돌 문구.
# ⑤(코덱스 모델 정책)는 코덱스 저장소의 시험이 맡는다.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MP="$CORE/scripts/model-prompting.sh"
# shellcheck source=../scripts/lib/help-state.sh
source "$CORE/scripts/lib/help-state.sh"
# shellcheck source=../scripts/lib/model-prompting.sh
source "$CORE/scripts/lib/model-prompting.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
has() { grep -qF -- "$2" "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-remaining.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

# T1 — 프로젝트 밖(scv/ 없음)의 등록은 저장하지 않고 거절
mkdir -p "$WORK/outside"
o="$(cd "$WORK/outside" && printf 'goal | msg | x\nrewrite | - | y\n' | env -u SCV_JOURNAL_DIR bash "$MP" register --model m-1 --session s1 2>&1 || true)"
[[ "$o" == "REGISTER: refused — no scv/"* && ! -e "$WORK/outside/scv" ]] && ok "T1 프로젝트 밖 등록 거절 · 저장 없음" || bad "T1 [$o]"

# T2 — 종료 훅이 막을 때 '앞 답은 이미 화면에 있음 — 고친 부분만' 한 줄을 붙인다
has "$CORE/template/hooks/on-stop.sh" '앞 답은 이미 사용자 화면에 있다 — 고친 부분만' \
  && ok "T2 막는 이유에 고친 부분만 안내" || bad "T2 막는 이유에 안내 없음"

# T3 — 언어 검사는 줄마다, 중간 보고까지 본다
v1="$(scv_lint_lang_turn $'**결과**\n- 모두 통과함' $'중간 보고임.\nAnswer-language check works as intended. Now running the size checks for real.' korean)"
v2="$(scv_lint_lang_turn $'**결과**\n- 모두 통과함' $'중간 보고임. `core/tests/test-x.sh` 를 돌림\n| a long english table cell text here for testing only | b |\n```\nsome long english code comment line inside a fence here ok\n```' korean)"
v3="$(scv_lint_lang_turn 'Running the size checks for real, then the hook test now.' '' english)"
[[ "$v1" == "lang-mismatch-lines=1" && -z "$v2" && -z "$v3" ]] && ok "T3 줄별 언어 검사(영어 줄 1 · 코드 · 표 · 영어 설정은 안 봄)" || bad "T3 [$v1] [$v2] [$v3]"

# T4 — 종료 훅이 이번 턴 글 전체를 언어 검사에 넘긴다
has "$CORE/template/hooks/on-stop.sh" '--lang-text' && has "$CORE/scripts/help-state.sh" 'scv_lint_lang_turn' \
  && ok "T4 턴 글 전체를 넘김" || bad "T4 종료 훅 · help-state 연결 없음"

# T5 — 기록된 가이드 경로를 지금 설치본 자리로(그 자리에 원문이 있을 때만)
rec=$'m-1\nGUIDE_FILE: /old/0.75.1/prompting/g.md\nGUIDE_MARK_CMD: bash "/old/0.75.1/scripts/model-prompting.sh" mark --model "m-1"'
r="$(scv_mp_guide_rebase "$rec" /new/prompting /new/scripts/model-prompting.sh)"
[[ "$r" == $'m-1\nGUIDE_FILE: /new/prompting/g.md\nGUIDE_MARK_CMD: bash "/new/scripts/model-prompting.sh" mark --model "m-1"' ]] \
  && has "$MP" 'scv_mp_guide_rebase "$_rec"' && ok "T5 가이드 경로 다시 씀" || bad "T5 [$r]"

# T6 — 비슷한 충돌 정리: 묻는 곳 목록 · 분석 제안 · push 질문 · 낡은 숫자 · 섞인 문장
c=0
! has "$CORE/contracts/guard.md" 'sixteenth action' && c=$((c + 1))
has "$CORE/contracts/guard.md" '| channel |' && c=$((c + 1))
! has "$CORE/protocols/regression.md" "Offer once: \"Want me to analyze" && c=$((c + 1))
! has "$CORE/protocols/regression.md" 'put the slug back into the triage table as its only row' && c=$((c + 1))
! has "$CORE/protocols/handoff.md" 'Show the user one line:' && c=$((c + 1))
! has "$CORE/protocols/install-deps.md" 'and place SKILL.md in the skill directory' && c=$((c + 1))
[[ "$c" == 6 ]] && ok "T6 비슷한 충돌 정리 6/6" || bad "T6 비슷한 충돌 정리 $c/6"

exit "$fail"
