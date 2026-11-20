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
lint() { scv_answer_lint "$1" "${2:-0}"; }   # 0.96.0+ 훅들은 문장 상한을 넘기지 않는다

# T1 — 굵은 주제 + 불릿 답은 통과(예전 lead-missing 없음)
v="$(lint $'> **다시 쓴 요청**: 정리해 줘\n\n**주제**\n- 결과임\n- 풀이함\n')"
[[ -z "$v" ]] && ok "T1 bold topic + bullets pass" || bad "T1 got [$v]"

# T2 — 0.96.0+: 줄글 문장 수는 세지 않는다(숫자 상한 없음). 상한을 직접 주면 그 기능은 그대로.
v="$(lint $'> **다시 쓴 요청**: x\n\n결론이다. 둘째 문장이다. 셋째 문장이다.\n')"
[[ "$v" != *prose-long* ]] && ok "T2 long prose not counted by default" || bad "T2 got [$v]"
v="$(lint $'결론이다. 둘째. 셋째.\n' 2)"
[[ "$v" == *"prose-long=3>2"* ]] && ok "T2 an explicit cap still counts" || bad "T2 cap 2 got [$v]"

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

# ── 계획 20261115-wookiya1364-answer-lead-paragraph-bullets (P1–P9): 결론은 불릿 없는 한두 문장, 이어지는 생각은 문단 불릿 ──
# shellcheck source=../scripts/lib/writing.sh
source "$CORE/scripts/lib/writing.sh"
BCAP="$(scv_writing_bullet_cap 2>/dev/null || true)"
lintb() { scv_answer_lint "$1" "${2:-0}" "" "$BCAP"; }
RWQ=$'> **다시 쓴 요청**: x\n\n'

# P1 — 새 모양(결론 줄 2문장 + 3문장 문단 불릿 둘)은 위반 없음
NEW="${RWQ}"$'**능력을 제한하는지**\n\n생각 · 문제 풀이는 제한하지 않음. 글의 질은 깎을 가능성이 높음(추정).\n\n- 글의 질은 사정이 다름. 설명은 이유가 이어져야 읽히는데, 한 가지씩만 쓰면 이음말이 빠짐. 다만 재 본 적이 없으므로 추정임.\n- SCV 는 모델도 생각 깊이도 바꾸지 않음. 손대는 것은 답의 모양뿐임. 그래서 문제를 푸는 힘이 줄 길이 없음.\n'
v="$(lintb "$NEW")"
[[ -z "$v" ]] && ok "P1 lead lines + paragraph bullets pass" || bad "P1 got [$v]"

# P2 — 0.96.0+: 결론 줄 문장 수는 세지 않는다
v="$(lintb "${RWQ}"$'**주제**\n\n결론임. 둘째 문장임. 셋째 문장임.\n\n- 풀이함\n')"
[[ "$v" != *prose-long* ]] && ok "P2 three-sentence lead not counted" || bad "P2 got [$v]"

# P3 — 불릿 아래로 이어 쓴 줄은 그 불릿의 것 (들여 쓴 줄 · 들이지 않은 줄 · 빈 줄 뒤 들여 쓴 줄)
v="$(lintb "${RWQ}"$'**주제**\n\n결론임.\n\n- 첫 문장임. 둘째 문장임.\n  셋째 문장임. 넷째 문장임. 다섯째 문장임.\n')"
[[ "$v" != *prose-long* ]] && ok "P3 indented continuation belongs to the bullet" || bad "P3 indented got [$v]"
v="$(lintb "${RWQ}"$'**주제**\n\n결론임.\n\n- 첫 문장임. 둘째 문장임.\n셋째 문장임. 넷째 문장임. 다섯째 문장임.\n')"
[[ "$v" != *prose-long* ]] && ok "P3 lazy continuation belongs to the bullet" || bad "P3 lazy got [$v]"
v="$(lintb "${RWQ}"$'**주제**\n\n결론임.\n\n- 첫 문장임.\n\n  이어지는 문단임. 둘째임. 셋째임.\n')"
[[ "$v" != *prose-long* ]] && ok "P3 indented paragraph after a blank line belongs to the bullet" || bad "P3 blank got [$v]"
v="$(lintb "${RWQ}"$'**주제**\n\n- 불릿임\n\n들이지 않은 줄글임. 둘째임. 셋째임.\n')"
[[ "$v" != *prose-long* ]] && ok "P3 unindented paragraph is prose but not counted (0.96.0+)" || bad "P3 prose got [$v]"

# P4 — 기준을 넘는 불릿만 알림 (기준 숫자는 lib/writing.sh 한 곳)
[[ "$BCAP" == 6 ]] && ok "P4 bullet cap comes from one function (6)" || bad "P4 cap [$BCAP]"
S7='하나임. 둘임. 셋임. 넷임. 다섯임. 여섯임. 일곱임.'
S6='하나임. 둘임. 셋임. 넷임. 다섯임. 여섯임.'
v="$(lintb "${RWQ}"$'**주제**\n\n결론임.\n\n- '"$S7"$'\n')"
[[ "$v" == *"bullet-long=7>6"* ]] && ok "P4 seven-sentence bullet flagged" || bad "P4 seven got [$v]"
v="$(lintb "${RWQ}"$'**주제**\n\n결론임.\n\n- '"$S6"$'\n')"
[[ "$v" != *bullet-long* ]] && ok "P4 six-sentence bullet passes" || bad "P4 six got [$v]"
v="$(scv_answer_lint "${RWQ}"$'**주제**\n\n- '"$S7"$'\n' 2)"
[[ "$v" != *bullet-long* ]] && ok "P4 no cap given → no bullet-length check" || bad "P4 nocap got [$v]"

# P5 — 굵은 주제 아래 결론 줄이 존댓말이면 알림, 물음은 예외
v="$(lintb "${RWQ}"$'**주제**\n\n통과했습니다.\n\n- 풀이함\n')"
[[ "$v" == *"lead-polite=1"* ]] && ok "P5 polite lead flagged" || bad "P5 got [$v]"
v="$(lintb "${RWQ}"$'**주제**\n\n이대로 쓸까요?\n')"
[[ "$v" != *lead-polite* ]] && ok "P5 question lead exempt" || bad "P5 question got [$v]"

# P6 — 문단 불릿의 끝말 검사는 불릿의 끝을 본다
v="$(lintb "${RWQ}"$'**주제**\n\n결론임.\n\n- 첫 문장임. 그래서 통과했습니다.\n- 첫 문장임. 그래서 통과함.\n')"
[[ "$v" == "bullet-polite=1" ]] && ok "P6 polite ending counted on the paragraph bullet" || bad "P6 got [$v]"
v="$(lintb "${RWQ}"$'**주제**\n\n결론임.\n\n- 첫 문장임.\n  그래서 통과했습니다.\n')"
[[ "$v" == "bullet-polite=1" ]] && ok "P6 the ending is read from the continuation line" || bad "P6 continuation got [$v]"

# P7 — 따로인 항목만 나열한 주제(결론 줄 없음)와 지금 모양의 답은 위반 없음
v="$(lintb "${RWQ}"$'**확인 범위**\n- 확인한 것: 시험 실행함\n- 확인 못 한 것: 휴대폰 화면\n- 제가 대신 정한 것: 기준 6문장\n')"
[[ -z "$v" ]] && ok "P7 a list-only topic passes without lead lines" || bad "P7 list got [$v]"
v="$(lintb "${RWQ}"$'**주제**\n- 결과임\n- 풀이함\n')"
[[ -z "$v" ]] && ok "P7 the earlier shape still passes" || bad "P7 old got [$v]"

# P8 — 새 표시는 다음 턴 경고에 사람이 읽을 말로 실린다
d="$(scv_drift_decide ok $'bullet-long=7>6\nlead-polite=1\n' on on korean)"
[[ "${d%%$'\x1f'*}" == 1 && "$d" == *"불릿"* && "$d" == *"결론"* ]] && ok "P8 new marks become readable warning lines" || bad "P8 got [$d]"

# P9 — 규칙 문구가 새 모양을 말한다: 이유 문장이 있고 불릿 상한 숫자는 문구에 없다
miss=""
for a in "결론" "문단" "휴대폰" "한 화면"; do grep -qF -- "$a" "$W" || miss+=" [writing.md $a]"; done
grep -qF -- "phone" "$HOOK" || miss+=" [hook phone]"
grep -qiE 'result .*(line|lines)' "$HOOK" || miss+=" [hook result lines]"
[[ -z "$miss" ]] && ok "P9 rule text names the lead lines, paragraph bullets and the reason" || bad "P9 missing:$miss"
num="$( { grep -nE '불릿[^.]*[0-9]+ ?문장|[0-9]+ ?문장[^.]*불릿' "$W" || true; grep -nE 'bullet[^.]*[0-9]+ sentences|[0-9]+ sentences[^.]*bullet' "$HOOK" || true; } | { grep -vE '1[~–]2|1–\$|one or two' || true; } | wc -l | tr -d ' ')"
[[ "$num" == 0 ]] && ok "P9 no bullet sentence cap written in the rule text" || bad "P9 a number in the rule text ($num)"

exit "$fail"
