#!/usr/bin/env bash
# test-instruction-diet.sh — 매 턴 글 줄이기 · 충돌 3 정리 · 검사 3 추가(계획 20261102-wookiya1364-instruction-diet T1 · T1b · T3–T8).
#
# 매 턴 글 = 매 턴 훅 출력(진단 변동 없는 둘째 턴) + help.md 본문 + 원칙을 다시 싣지 않는 등록 출력. 0.76.0 같은 방식 14,823B,
# 상한 10,800B(사용자 결정 2026-11-02 10,500B → 2026-11-04 10,800B: 0.79.0 언어 줄 309B, codex 사본 10,695B).
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$CORE/tests/fixtures/model-prompting"
MP="$CORE/scripts/model-prompting.sh"; HOOK="$CORE/template/hooks/on-user-prompt.sh"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
# shellcheck source=../scripts/lib/help-state.sh
source "$CORE/scripts/lib/help-state.sh"
# shellcheck source=../scripts/lib/model-prompting.sh
source "$CORE/scripts/lib/model-prompting.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-diet.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides"
printf '# source: common.md\ngoal\tState the goal\tq a\nfinish\tState the done condition\tq b\n' > "$WORK/guides/checklist-common.tsv"
printf '# source: model-a.md\nfinish\tState the done condition precisely\tq c\n' > "$WORK/guides/checklist-model-a.tsv"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\nSCV_CHOICE_TOOL=PickTool\n' "$WORK/guides"; } > "$WORK/profile.env"
R="$WORK/r"; mkdir -p "$R/scv/journal"; (cd "$R" && git init -q)
printf '{"SCV_LANG": "korean"}\n' > "$R/scv/scv_settings.json"
printf '{"session":"s1","protocol":1,"turn":3,"diag":"","diag_at":"","nonce":"abcd1234"}\n' > "$R/scv/journal/.help-state"
hook() { (cd "$R" && jq -cn '{prompt:"로그인 버그 고쳐 줘",session_id:"s1"}' \
  | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile.env" bash "$HOOK" 2>/dev/null); }
reg() { (cd "$R" && printf 'goal | msg | 로그인 버그 고침\nfinish | ctx | 시험 통과\nrewrite | - | 로그인 버그를 고쳐 줘\n' \
  | SCV_HOST_PROFILE="$WORK/profile.env" bash "$MP" register --model vendor-model-a --session s1 2>/dev/null); }

# T1b — 원칙 전문은 첫 등록과 규약을 다시 읽은 뒤에만
hook >/dev/null; r1="$(reg)"
hook >/dev/null; r2="$(reg)"
sed -i.bak 's/abcd1234/ef567890/' "$R/scv/journal/.help-state"
hook >/dev/null; r3="$(reg)"
n1="$(grep -c . <<<"$r1")"; n2="$(grep -c . <<<"$r2")"; n3="$(grep -c . <<<"$r3")"
if grep -q '^PRINCIPLE:$' <<<"$r1" && grep -q '^PRINCIPLE: (이 세션에 이미 실음' <<<"$r2" && grep -q '^PRINCIPLE:$' <<<"$r3" && (( n2 < n1 )); then
  ok "T1b principle full → one line → full again after reload ($n1 · $n2 · $n3 lines)"
else
  bad "T1b principle lines: $n1 · $n2 · $n3"
fi
[[ "$(scv_mp_principle_show "" abc)" == full && "$(scv_mp_principle_show abc abc)" == short && "$(scv_mp_principle_show abc "")" == full ]] \
  && ok "T1b pure decision" || bad "T1b pure decision"

# T1 — 매 턴 글 9,000바이트 이하 · 도움말 합계 33,022 미만
hook >/dev/null; h="$(hook | wc -c | tr -d ' ')"; r="$(reg | wc -c | tr -d ' ')"; b="$(wc -c < "$CORE/protocols/help.md" | tr -d ' ')"
tot=$(( h + b + r ))
(( tot <= 10800 )) && ok "T1 per-turn text ${tot}B ≤ 10800B (hook $h + help $b + register $r)" || bad "T1 per-turn text ${tot}B > 10800B (hook $h + help $b + register $r)"
sum=0; for f in "$CORE/protocols/help.md" "$CORE"/protocols/help/*.md; do sum=$(( sum + $(wc -c < "$f") )); done
(( sum < 33022 )) && ok "T1 help total ${sum}B < 33022B" || bad "T1 help total ${sum}B"

# T3 · T4 — 번호 vs 불릿, 항목 표 vs 해결책 표
W="$CORE/contracts/writing.md"
grep -qF '번호는 답장에서 가리킬 것' "$W" && ok "T3 numbered lists only for things to point at" || bad "T3 missing"
grep -qF '상태 보고는 항목 표, 풀 문제는 해결책 표' "$W" && ok "T4 item table vs solution table" || bad "T4 missing"

# T5 — 앱 마무리 상자에는 요약만
grep -qF 'end-of-turn summary box' "$CORE/contracts/choices.md" && grep -qF 'never the question' "$CORE/contracts/choices.md" \
  && ok "T5 summary box gets the summary, never the question" || bad "T5 missing"

# T6 · T7 — 답 언어 검사
v="$(scv_answer_lint $'> **Rewritten request**: x\n\n**Status**\n- The core release passed and both wrappers are being synced now\n- Waiting on CI\n' 2 korean)"
[[ "$v" == *lang-mismatch* ]] && ok "T6 English answer under korean → lang-mismatch" || bad "T6 got [$v]"
v="$(scv_answer_lint $'> **다시 쓴 요청**: x\n\n**결과**\n- 답 검사 함수를 고침\n- 저장소 시험 통과함\n\n```\nsome english code here and more english words for the check\n```\n' 2 korean)"
[[ "$v" != *lang-mismatch* ]] && ok "T7 Korean answer with code passes" || bad "T7 korean got [$v]"
v="$(scv_answer_lint $'**Status**\n- The core release passed and both wrappers are being synced now\n' 2 english)"
[[ "$v" != *lang-mismatch* ]] && ok "T7 English answer under english passes" || bad "T7 english got [$v]"
[[ "$(scv_lint_hangul_ratio "로그인 버그를 고침")" == 100 && "$(scv_lint_hangul_ratio "fixed it")" == 0 ]] && ok "T7 ratio" || bad "T7 ratio"

# T8 — 크기 여유 검사: 코어 저장소에서 합계가 상한-100 을 넘으면 실패
o="$(SCV_HELP_TOTAL_MAX=$(( sum + 50 )) bash "$CORE/tests/test-help-budget.sh" 2>&1 || true)"
if [[ -f "$CORE/../VERSION" && -d "$CORE/../scv/archive" ]]; then
  grep -q '코어 여유 부족' <<<"$o" && ok "T8 margin check fails at limit-100" || bad "T8 margin check did not fire"
else
  echo "  – T8 SKIP (코어 저장소 밖)"
fi

exit "$fail"
