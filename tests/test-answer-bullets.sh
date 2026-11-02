#!/usr/bin/env bash
# test-answer-bullets.sh — 답 모양(굵은 주제 + 두괄식 개조식 불릿, 다시 쓴 요청은 맨 위)이 검사 · 판정 · 안내에 들어갔는지 본다.
#
# 계획 20261102-wookiya1364-answer-bullets 의 TESTS.md T1–T8. 답 골격 검사(lib/help-state.sh scv_answer_lint),
# 맨 위 판정(lib/model-prompting.sh), 매 턴 안내(on-user-prompt.sh), 규칙 문서(contracts/writing.md).
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/help-state.sh
source "$CORE/scripts/lib/help-state.sh"
# shellcheck source=../scripts/lib/model-prompting.sh
source "$CORE/scripts/lib/model-prompting.sh"
HOOK="$CORE/template/hooks/on-user-prompt.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
lint() { scv_answer_lint "$1" "${2:-2}"; }

# T1 — 굵은 주제 + 불릿 답은 통과(예전 lead-missing 없음)
v="$(lint $'> **다시 쓴 요청**: 정리해 줘\n\n**주제**\n- 결과임\n- 풀이함\n')"
[[ -z "$v" ]] && ok "T1 bold topic + bullets pass" || bad "T1 got [$v]"

# T2 — 긴 줄글 문단은 위반
v="$(lint $'> **다시 쓴 요청**: x\n\n결론이다. 둘째 문장이다. 셋째 문장이다.\n')"
[[ "$v" == *"prose-long=3>2"* ]] && ok "T2 long prose flagged" || bad "T2 got [$v]"
v="$(lint $'결론이다. 둘째. 셋째.\n' 3)"
[[ "$v" != *prose-long* ]] && ok "T2 cap follows the sentence setting" || bad "T2 cap 3 got [$v]"

# T3 — 서술형 불릿은 위반, 물음은 예외
v="$(lint $'> **다시 쓴 요청**: x\n\n**만든 것**\n- 통과했습니다.\n- 이대로 쓸까요?\n- 남은 일 없음\n')"
[[ "$v" == "bullet-polite=1" ]] && ok "T3 polite bullet counted once, question exempt" || bad "T3 got [$v]"

# T4 — 다시 쓴 요청이 맨 위가 아니면 위반, 종료 판정이 맨 위로 옮기라고 안내
ans=$'결론이다.\n\n> **다시 쓴 요청**: x\n'
v="$(lint "$ans")"
[[ "$v" == *rewrite-not-top* ]] && ok "T4 lint flags rewrite not on top" || bad "T4 lint got [$v]"
top="$(scv_mp_answer_rewrite_on_top "$ans")"
g="$(scv_mp_stop_gate 1 1 0 "$top")"; r="$(scv_mp_stop_reason 1 1 "$top" tok x.sh m s)"
[[ "$top" == 0 && "$g" == block && "$r" == *"맨 위"* ]] && ok "T4 stop gate blocks and says 맨 위" || bad "T4 top=$top gate=$g reason=[$r]"

# T5 — 이해 한 줄 없이도 종료 허용
ans=$'> **다시 쓴 요청**: x\n\n**결과**\n- 됨\n'
top="$(scv_mp_answer_rewrite_on_top "$ans")"
[[ "$top" == 1 && "$(scv_mp_stop_gate 1 1 0 "$top")" == ok ]] && ok "T5 rewrite on top passes without the old top line" || bad "T5 top=$top"

# T6 — 안내 문구가 새 모양을 말하고, 옛 '이해 한 줄' 지시는 없다
W="$CORE/contracts/writing.md"
miss=""
for a in "굵은 주제" "두괄식" "~함 · ~임" "쉬운 말"; do grep -qF -- "$a" "$W" || miss+=" [$a]"; done
grep -qF -- "**bold topic**" "$HOOK" || miss+=" [hook bold topic]"
[[ -z "$miss" ]] && ok "T6 new shape named in writing.md and the per-turn hook" || bad "T6 missing:$miss"
old="$(grep -rlF "이렇게 이해하고 일함" "$CORE/protocols" "$CORE/template/hooks" "$CORE/contracts" 2>/dev/null || true)"
blk="$(scv_mp_turn_block on tok m "" x.sh)"
[[ -z "$old" && "$blk" != *"이렇게 이해하고 일함"* ]] && ok "T6 no old top-line instruction left" || bad "T6 old wording in: $old"

# T7 — 끄기 스위치 유지
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/p/scv/raw"; printf '{"SCV_PLAIN_LANGUAGE": "off"}\n' > "$WORK/p/scv/scv_settings.json"
out="$( cd "$WORK/p" && printf '{"prompt":"안녕","session_id":"s"}' \
  | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/state" bash "$HOOK" 2>/dev/null || true )"
[[ "$out" != *"[SCV plain language]"* ]] && ok "T7 SCV_PLAIN_LANGUAGE=off silences the block" || bad "T7 block still printed"

# T8 — 코드 블록 안은 검사하지 않음
v="$(lint $'> **다시 쓴 요청**: x\n\n```\n긴 문장. 둘. 셋. 넷.\n- 했습니다\n> **다시 쓴 요청**: y\n```\n')"
[[ -z "$v" ]] && ok "T8 code block ignored" || bad "T8 got [$v]"

exit "$fail"
