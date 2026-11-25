#!/usr/bin/env bash
# test-rules-once.sh — 매 턴 규칙 글은 규약 지문마다 한 번 · 숫자 길이 상한 없음
# (계획 20261120-wookiya1364-rules-once-no-caps · TESTS.md T1 ~ T9).
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

DEFAULT_SETTINGS='{"SCV_LANG":"korean"}'   # 기본값을 변수로 둔다 — 옛 셸(3.2)은 ${2:-{…\}} 안의 닫는 괄호 앞 역슬래시를 글자로 남긴다
mkproj() { local p="$WORK/$1"; mkdir -p "$p/scv/raw" "$p/scv/conversations"; printf '%s\n' "${2:-$DEFAULT_SETTINGS}" > "$p/scv/scv_settings.json"; echo "$p"; }
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

# ---------- T3 · T4 — 같은 맥락이면 한 줄, 맥락이 비워지면(요약 · 비움 · 재개 = 세션 시작 초기화) 다시 전문 (0.97.1+ 맥락 표시) ----------
reset_ctx() { ( cd "$1" && bash "$STATE_SH" reset --turn-dir "scv/journal/.help-turns/${2:-s1}" >/dev/null 2>&1 ); }
P="$(mkproj t3)"
O1="$(hook "$P" s1)"; mark "$P"
O2="$(hook "$P" s1)"
O3="$(hook "$P" s1)"
b1=$(printf '%s' "$O1" | wc -c | tr -d ' '); b3=$(printf '%s' "$O3" | wc -c | tr -d ' ')
if is_full "$O1" && is_short "$O2" && is_short "$O3" && (( b1 - b3 >= 1500 )); then ok "T3 첫 턴 전문 · 규약 표시(mark) 뒤에도 한 줄 (${b1}B → ${b3}B)"
else bad "T3 full1=$(is_full "$O1" && echo y) short2=$(is_short "$O2" && echo y) short3=$(is_short "$O3" && echo y) ${b1}B→${b3}B"; fi
reset_ctx "$P"; O4="$(hook "$P" s1)"; O5="$(hook "$P" s1)"
if is_full "$O4" && is_short "$O5"; then ok "T4 맥락이 비워진(초기화) 뒤 첫 턴은 전문, 그다음은 다시 한 줄"
else bad "T4 full4=$(is_full "$O4" && echo y) short5=$(is_short "$O5" && echo y)"; fi

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

# ---------- T8 — 초기화 뒤 모델이 규약 표시를 건너뛰어도(지문이 빈 채) 전문은 한 번뿐 (0.97.0 실제 세션: 73턴 중 한 줄 3) ----------
P="$(mkproj t8)"
hook "$P" s1 >/dev/null; mark "$P"; hook "$P" s1 >/dev/null
reset_ctx "$P"                       # 대화 요약 · 재개 — 지문이 지워지고, 이후 mark 는 일어나지 않는다
Oa="$(hook "$P" s1)"; Ob="$(hook "$P" s1)"; Oc="$(hook "$P" s1)"; Od="$(hook "$P" s1)"
nonce="$(cat "$P/scv/journal/.help-nonce" 2>/dev/null)"
if is_full "$Oa" && is_short "$Ob" && is_short "$Oc" && is_short "$Od" && [[ -z "$nonce" ]]; then
  ok "T8 지문이 빈 채 네 턴: 전문 한 번 뒤 한 줄 셋"
else bad "T8 a=$(is_full "$Oa" && echo f || echo s) b=$(is_short "$Ob" && echo s || echo f) c=$(is_short "$Oc" && echo s || echo f) d=$(is_short "$Od" && echo s || echo f) nonce=[$nonce]"; fi

# ---------- T9 — 가이드 원문 읽기 안내만 남은 경고는 규칙 어김이 아니다 → 한 줄 ----------
P="$(mkproj t9)"; hook "$P" s1 >/dev/null; hook "$P" s1 >/dev/null
printf '[SCV 가이드] 직전 턴: 이 컨텍스트에서 아직 이 모델의 프롬프팅 가이드 원문을 읽지 않았다\n  GUIDE_FILE: /x/guide.md\n' > "$P/scv/journal/.help-turns/s1/.help-warn"
Og="$(hook "$P" s1)"
printf '[SCV 답 모양] 직전 답이 답 모양 계약을 벗어났다 (lead-polite=1)\n' > "$P/scv/journal/.help-turns/s1/.help-warn"
Ow="$(hook "$P" s1)"
if is_short "$Og" && is_full "$Ow"; then ok "T9 가이드 안내만 남은 턴은 한 줄 · 답 모양 경고 턴은 전문"
else bad "T9 가이드=$(is_short "$Og" && echo s || echo f) 경고=$(is_full "$Ow" && echo f || echo s)"; fi

exit "$fail"
