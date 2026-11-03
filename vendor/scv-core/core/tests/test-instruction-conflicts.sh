#!/usr/bin/env bash
# test-instruction-conflicts.sh — 0.77.0 전체 재검사로 찾은 지시 충돌 12곳 정리(계획 20261103-wookiya1364-instruction-conflicts-077 T1–T8).
#
# 문구 검사다: 한쪽 규칙만 남았는지(옛 문구 0곳)와 매 턴 줄의 크기 상한을 본다. 답이 실제로 바뀌는지는 긴 세션으로만 잴 수 있다.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$CORE/.." && pwd)"
P="$CORE/protocols"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
has() { grep -qF -- "$2" "$1"; }

# T1 — '예시 하나'를 요구하는 프로토콜이 없다(writing.md 에 없는 요구)
n="$( { grep -lF "one example from the" "$P"/*.md 2>/dev/null || true; } | wc -l | tr -d " ")"
[[ "$n" == 0 ]] && ok "T1 '예시 하나' 요구 0곳" || bad "T1 '예시 하나' 요구 ${n}곳"

# T2 — 옛 답 모양 문구(결론 1~2문장 → 예시 하나)가 안내 문서 틀 · README 3개 언어에 없다
old=0
has "$CORE/template/scv/SCV.md" 'First 1–2 sentences of what you get' && old=$((old + 1))
for f in README.md README.ko.md README.ja.md; do
  [[ -f "$REPO/$f" ]] || continue
  grep -qE 'then one example|예시 하나를 들고|例を一つ挙げ' "$REPO/$f" && old=$((old + 1))
done
[[ "$old" == 0 ]] && ok "T2 옛 답 모양 문구 0곳" || bad "T2 옛 답 모양 문구 ${old}곳"

# T3 — 매 턴 선택 창 줄: 마무리 상자는 요약만 · 고정 구절 유지 · 400B 이하
line="$(bash -c 'source "$1"; scv_choice_line PickTool' _ "$CORE/scripts/lib/choices.sh")"
bytes="$(printf '%s\n' "$line" | wc -c | tr -d ' ')"
[[ "$line" == *"Summary box: recap only."* && "$line" == *"work done, state it unasked."* && "$bytes" -le 400 ]] \
  && ok "T3 선택 창 줄 ${bytes}B, 마무리 상자 구절" || bad "T3 선택 창 줄 ${bytes}B: $line"

# T4 — choices.md 10항: 호스트가 글로 물으라 해도 글 질문
has "$CORE/contracts/choices.md" 'also when the host itself says to ask in' \
  && ok "T4 규칙 10항 보강" || bad "T4 규칙 10항에 호스트 안내 문장 없음"

# T5 — 그래프 안내 줄은 다시 쓴 요청 인용 바로 아래(work · promote)
c=0; for f in work.md promote.md; do has "$P/$f" 'right under the rewritten-request quote' && c=$((c + 1)); done
[[ "$c" == 2 ]] && ok "T5 GRAFT 줄 위치 2/2" || bad "T5 GRAFT 줄 위치 $c/2"

# T6 — 번호 목록은 다시 가리킬 것에만(work 보고 · report)
c=0; for f in work.md report.md; do
  has "$P/$f" 'numbers only on' && ! has "$P/$f" 'numbered items' && c=$((c + 1))
done
[[ "$c" == 2 ]] && ok "T6 번호 목록 규칙 2/2" || bad "T6 번호 목록 규칙 $c/2"

# T7 — 묻는 곳: codegen 추천 표시 2곳, workspace 는 선택 규칙 · 고정 한국어 문구 없음, sync · install-deps 는 묻지 않음
c=0
[[ "$(grep -c '(recommended)' "$P/codegen.md")" -ge 2 ]] && has "$P/codegen.md" 'rollback (recommended)' && c=$((c + 1))
! has "$P/workspace.md" 'plain questions' && ! has "$P/workspace.md" '보입니다' && c=$((c + 1))
! has "$P/sync.md" 'ask the user whether to also run drift detection' && c=$((c + 1))
! has "$P/install-deps.md" "don't auto-run" && c=$((c + 1))
[[ "$c" == 4 ]] && ok "T7 질문 정리 4/4" || bad "T7 질문 정리 $c/4"

# T8 — full.md 의 미수화 안내 문구가 실제 출력(help.sh)과 같다
want="This directory is not hydrated yet."
has "$CORE/scripts/help.sh" "$want" && has "$P/help/full.md" "\`$want\`" && ! has "$P/help/full.md" "isn't hydrated yet" \
  && ok "T8 안내 문구 일치" || bad "T8 full.md 와 help.sh 출력 문구가 다름"

exit "$fail"
