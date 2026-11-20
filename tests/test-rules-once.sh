#!/usr/bin/env bash
# test-rules-once.sh — 매 턴 규칙 글은 규약 지문마다 한 번 · 숫자 길이 상한 없음
# (계획 20261120-wookiya1364-rules-once-no-caps · TESTS.md T1 ~ T7).
#
# 사람 턴마다 같은 규칙 글(약 4.8 KB)이 다시 붙어 쌓였다. 지문이 같은 턴은 한 줄로 줄이고, 지문이 바뀌거나 경고가 남은 턴 ·
# 끈 프로젝트 · 처음 보는 세션은 전문을 싣는지 본다. 숫자 상한(문장 수 · 불릿 길이)은 검사 · 안내 어디에도 없어야 한다.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"
STATE_SH="$CORE/scripts/help-state.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unset SCV_RULES_ONCE SCV_JOURNAL_DIR 2>/dev/null || true
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

mkproj() { local p="$WORK/$1"; mkdir -p "$p/scv/raw" "$p/scv/conversations"; printf '%s\n' "${2:-{\"SCV_LANG\":\"korean\"\}}" > "$p/scv/scv_settings.json"; echo "$p"; }
hook() { ( cd "$1" && printf '{"prompt":"안녕","session_id":"%s"}' "$2" | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/gs" bash "$PROMPT_HOOK" 2>/dev/null ); }
mark() { ( cd "$1" && bash "$STATE_SH" mark >/dev/null 2>&1 ); }
is_full() { grep -qF '[SCV plain language]' <<<"$1" && grep -qF '[SCV 확인 범위]' <<<"$1" && ! grep -qF '[SCV 규칙]' <<<"$1"; }
is_short() { grep -qF '[SCV 규칙]' <<<"$1" && ! grep -qF '[SCV plain language]' <<<"$1" && ! grep -qF '[SCV 확인 범위]' <<<"$1"; }

# ---------- T1 — 긴 줄글 · 긴 불릿에 문장 수 · 길이 경고가 없다 ----------
# shellcheck source=/dev/null
source "$CORE/scripts/lib/help-state.sh"
v="$(scv_answer_lint $'**주제**\n\n결론임. 둘째임. 셋째임. 넷째임.\n\n- 하나임. 둘임. 셋임. 넷임. 다섯임. 여섯임.\n')"
v2="$(scv_answer_lint $'**주제**\n\n결론입니다.\n\n- 항목\n')"
if [[ -z "$v" && "$v2" == *lead-polite=1* ]]; then ok "T1 문장 수 · 불릿 길이 경고 없음, '~습니다' 결론 줄은 그대로 잡음"
else bad "T1 [$v] [$v2]"; fi

# ---------- T2 — 안내 · 규약에 숫자 상한 표현이 없다 ----------
P="$(mkproj t2)"; O="$(hook "$P" s1)"
n="$( { grep -rlF -e '1–2 sentences' -e 'SCV_PLAIN_MAX_SENTENCES' "$CORE/protocols" "$CORE/template/scv/SCV.md" 2>/dev/null || true; } | wc -l | tr -d ' ')"
if ! grep -qE '1–[0-9]+ sentences|SCV_PLAIN_MAX_SENTENCES' <<<"$O" && [[ "$n" == 0 ]]; then ok "T2 훅 출력 · 규약 · SCV.md 에 숫자 상한 표현 0곳"
else bad "T2 남은 곳 $n"; fi

# ---------- T3 · T4 — 같은 지문이면 한 줄, 지문이 바뀌면 다시 전문 (시험 환경엔 선택 창 · 원칙 글이 없어 전문이 작다) ----------
P="$(mkproj t3)"
O1="$(hook "$P" s1)"; mark "$P"
O2="$(hook "$P" s1)"
O3="$(hook "$P" s1)"
b2=$(printf '%s' "$O2" | wc -c | tr -d ' '); b3=$(printf '%s' "$O3" | wc -c | tr -d ' ')
if is_full "$O1" && is_full "$O2" && is_short "$O3" && (( b2 - b3 >= 1500 )); then ok "T3 지문이 생긴 뒤 첫 턴 전문 · 다음 턴 한 줄 (${b2}B → ${b3}B)"
else bad "T3 full1=$(is_full "$O1" && echo y) full2=$(is_full "$O2" && echo y) short3=$(is_short "$O3" && echo y) ${b2}B→${b3}B"; fi
mark "$P"; O4="$(hook "$P" s1)"; O5="$(hook "$P" s1)"
if is_full "$O4" && is_short "$O5"; then ok "T4 지문이 바뀐 턴은 전문, 그다음은 다시 한 줄"
else bad "T4"; fi

# ---------- T5 — 남은 경고가 있으면 전문 ----------
printf '[SCV 답 모양] 직전 답이 답 모양 계약을 벗어났다 (lead-polite=1)\n' > "$P/scv/journal/.help-turns/s1/.help-warn"
O6="$(hook "$P" s1)"; O7="$(hook "$P" s1)"
if is_full "$O6" && grep -qF '[SCV 답 모양]' <<<"$O6" && is_short "$O7"; then ok "T5 경고가 남은 턴은 전문(경고와 함께), 경고가 지워진 다음 턴은 한 줄"
else bad "T5"; fi

# ---------- T6 — 끄면 예전과 같다 ----------
P="$(mkproj t6 '{"SCV_LANG":"korean","SCV_RULES_ONCE":"off"}')"
hook "$P" s1 >/dev/null; mark "$P"; hook "$P" s1 >/dev/null; O="$(hook "$P" s1)"
is_full "$O" && [[ ! -e "$P/scv/journal/.help-turns/s1/.rules-seen" ]] && ok "T6 SCV_RULES_ONCE=off: 셋째 턴도 전문, 표시를 쓰지 않음" || bad "T6"

# ---------- T7 — 다른 세션은 섞이지 않는다 ----------
P="$(mkproj t7)"
hook "$P" s1 >/dev/null; mark "$P"; hook "$P" s1 >/dev/null; Os1="$(hook "$P" s1)"
Os2="$(hook "$P" s2)"
if is_short "$Os1" && is_full "$Os2"; then ok "T7 s1 은 한 줄인 때 처음 온 s2 는 전문"
else bad "T7 s1short=$(is_short "$Os1" && echo y) s2full=$(is_full "$Os2" && echo y)"; fi

# ---------- T8 — 규약을 다시 읽어도 전문 턴은 하나 (턴 끝이 새 지문을 본 것으로 적는다) ----------
MP="$CORE/scripts/model-prompting.sh"
endturn() { ( cd "$1" && printf '' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$MP" stop --session "$2" >/dev/null 2>&1 ); }
P="$(mkproj t8)"
# 실제 턴의 순서: 훅(전문 판단) → help 가 규약을 다시 읽음(mark, 새 지문) → 턴 끝(stop)
hook "$P" s1 >/dev/null; mark "$P"; endturn "$P" s1
Oa="$(hook "$P" s1)"; endturn "$P" s1
Ob="$(hook "$P" s1)"; endturn "$P" s1
mark "$P"                     # 10턴마다 같은 '다시 읽기'
Oc="$(hook "$P" s1)"; mark "$P"; endturn "$P" s1
Od="$(hook "$P" s1)"; endturn "$P" s1
if is_short "$Oa" && is_short "$Ob" && is_full "$Oc" && is_short "$Od" && [[ ! -e "$P/scv/journal/.help-turns/s1/.rules-full" ]]; then
  ok "T8 다시 읽은 턴 하나만 전문, 바로 다음 턴부터 한 줄 · 표시는 지워짐"
else bad "T8 a=$(is_short "$Oa" && echo s || echo f) b=$(is_short "$Ob" && echo s || echo f) c=$(is_full "$Oc" && echo f || echo s) d=$(is_short "$Od" && echo s || echo f)"; fi

exit "$fail"
