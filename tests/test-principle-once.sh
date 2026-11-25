#!/usr/bin/env bash
# test-principle-once.sh — 원칙 글도 맥락에 한 번만(계획 20261125-wookiya1364-principle-once-context · TESTS.md T1 ~ T7).
#
# 매 턴 규칙 글은 맥락 표시로 한 줄이 됐는데, 함께 붙는 원칙 글(약 2.5 KB)은 규약 지문을 견줘서 지문이 바뀔 때마다 전문이
# 다시 실렸다(실제 세션의 한 줄 턴 108개 중 105개). 원칙 글도 '이 맥락에 실었다는 표시'로 판정하는지 본다:
# 지문이 바뀌어도 한 줄, 대화 초기화 뒤 첫 턴과 원칙 경고가 남은 턴은 전문, 끈 설정에서는 이 일 전과 같다.
# 픽스처는 중립 id 만 쓴다 — 코어 payload 에 제공자 · 모델 이름을 넣지 않는다(tests/test-host-neutral.sh).
#
# Run: bash core/tests/test-principle-once.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$CORE/scripts/lib/model-prompting.sh"
HOOK="$CORE/template/hooks/on-user-prompt.sh"
STATE_SH="$CORE/scripts/help-state.sh"
FIX="$CORE/tests/fixtures/model-prompting"
PRIN="$CORE/contracts/rewrite-principle.md"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
unset SCV_RULES_ONCE SCV_REWRITE_PRINCIPLE SCV_JOURNAL_DIR 2>/dev/null || true

fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-po.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\n' "$WORK/guides"; } > "$WORK/profile.env"

KOREAN='{"SCV_LANG":"korean"}'
mkproj() {  # <이름> [설정 JSON] → 프로젝트 경로
  local p="$WORK/$1"; mkdir -p "$p/scv/journal" "$p/scv/raw" "$p/scv/conversations"
  printf '%s\n' "${2:-$KOREAN}" > "$p/scv/scv_settings.json"
  printf '{"session":"s1","protocol":1,"turn":3,"diag":"","diag_at":"","nonce":"abcd1234"}\n' > "$p/scv/journal/.help-state"
  printf '%s' "$p"
}
hook() {  # <프로젝트> <세션> → 매 턴 훅 출력
  ( cd "$1" && jq -cn --arg s "$2" '{prompt:"로그인 고쳐",session_id:$s}' \
    | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/gs" SCV_HOST_PROFILE="$WORK/profile.env" bash "$HOOK" 2>/dev/null )
}
renonce() {  # <프로젝트> <새 지문> — 규약을 다시 읽어 지문이 바뀐 것과 같다
  local f="$1/scv/journal/.help-state"
  jq -c --arg n "$2" '.nonce = $n' "$f" > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
}
reset_ctx() { ( cd "$1" && bash "$STATE_SH" reset --turn-dir "scv/journal/.help-turns/${2:-s1}" >/dev/null 2>&1 ); }
bytes() { printf '%s' "$1" | wc -c | tr -d ' '; }

# 원칙 전문의 첫 줄 — 전문이 실렸는지는 이 줄이 있는지로 가른다.
SEC="$(bash -c 'source "$1"; scv_mp_principle_section "$(cat "$2")" korean' _ "$LIB" "$PRIN")"
HEAD1="$(bash -c 'source "$1"; scv_mp_principle_text "$2"' _ "$LIB" "$SEC" | head -1)"
[[ -n "$HEAD1" ]] || { echo "원칙 글을 읽지 못했다 — $PRIN" >&2; exit 1; }
is_full() { grep -q '^PRINCIPLE:$' <<<"$1" && grep -qF -- "$HEAD1" <<<"$1"; }
is_short() { grep -q '^PRINCIPLE: (' <<<"$1" && ! grep -qF -- "$HEAD1" <<<"$1"; }
mode() { if is_full "$1"; then printf 'full'; elif is_short "$1"; then printf 'short'; else printf 'none'; fi; }

# ---------- T1 — 지문이 바뀐 둘째 턴도 한 줄 ----------
P="$(mkproj t1)"
O1="$(hook "$P" s1)"; renonce "$P" ef567890
O2="$(hook "$P" s1)"; renonce "$P" 0a1b2c3d
O3="$(hook "$P" s1)"
b1="$(bytes "$O1")"; b3="$(bytes "$O3")"
if is_full "$O1" && is_short "$O2" && is_short "$O3" && (( b1 - b3 >= 1500 )); then ok "T1 첫 턴 전문 · 지문이 두 번 바뀌어도 한 줄 (${b1}B → ${b3}B)"
else bad "T1 1=$(mode "$O1") 2=$(mode "$O2") 3=$(mode "$O3") ${b1}B→${b3}B"; fi

# ---------- T2 — 대화 초기화 뒤 첫 턴은 전문, 그다음은 한 줄 ----------
reset_ctx "$P"
[[ -e "$P/scv/journal/.help-turns/s1/.principle-seen" ]] && gone=no || gone=yes
O4="$(hook "$P" s1)"; O5="$(hook "$P" s1)"
if [[ "$gone" == yes ]] && is_full "$O4" && is_short "$O5"; then ok "T2 초기화가 원칙 표시를 지움 · 첫 턴 전문 · 그다음 한 줄"
else bad "T2 표시지움=$gone 4=$(mode "$O4") 5=$(mode "$O5")"; fi

# ---------- T3 — 원칙 경고가 남은 턴만 전문 ----------
W="$P/scv/journal/.help-turns/s1/.help-warn"
printf '[SCV 원칙] 문제 표 · 문제 칸 없이, 해결책 안에서 막아 다시 써라.\n' > "$W"
Oa="$(hook "$P" s1)"
printf '[SCV 확인 범위] 끝 보고에 고칠 것 — 빠진 줄: 확인한 것\n' > "$W"
Ob="$(hook "$P" s1)"
if is_full "$Oa" && is_short "$Ob"; then ok "T3 원칙 경고 턴은 전문 · 확인 범위 경고만 남은 턴은 한 줄"
else bad "T3 원칙경고=$(mode "$Oa") 다른경고=$(mode "$Ob")"; fi

# ---------- T4 — 끈 설정에서는 이 일 전과 같다(지문 비교) ----------
P="$(mkproj t4 '{"SCV_LANG":"korean","SCV_RULES_ONCE":"off"}')"
Oc="$(hook "$P" s1)"; Od="$(hook "$P" s1)"; renonce "$P" ef567890; Oe="$(hook "$P" s1)"
if is_full "$Oc" && is_short "$Od" && is_full "$Oe"; then ok "T4 SCV_RULES_ONCE=off: 전문 → 한 줄 → 지문이 바뀌면 다시 전문"
else bad "T4 c=$(mode "$Oc") d=$(mode "$Od") e=$(mode "$Oe")"; fi

# ---------- T5 — 원칙을 끈 설정에서는 싣지 않는다 ----------
P="$(mkproj t5 '{"SCV_LANG":"korean","SCV_REWRITE_PRINCIPLE":"off"}')"
Of="$(hook "$P" s1)"
if ! grep -q '^PRINCIPLE' <<<"$Of"; then ok "T5 SCV_REWRITE_PRINCIPLE=off: 원칙 줄 없음"; else bad "T5 원칙 줄이 실림"; fi

# ---------- T6 — 세션마다 따로 ----------
P="$(mkproj t6)"
hook "$P" s1 >/dev/null; Os1="$(hook "$P" s1)"; Os2="$(hook "$P" s2)"
if is_short "$Os1" && is_full "$Os2"; then ok "T6 s1 이 한 줄인 때 처음 온 s2 는 전문"
else bad "T6 s1=$(mode "$Os1") s2=$(mode "$Os2")"; fi

# ---------- T7 — 원칙 경고 가르기(순수 판정) ----------
# shellcheck source=/dev/null
source "$LIB"
if declare -F scv_mp_warn_has_principle >/dev/null 2>&1; then
  a="$(scv_mp_warn_has_principle $'[SCV 직전 답] [SCV 원칙] 문제 표 없이 다시 써라.\n')"
  b="$(scv_mp_warn_has_principle $'[SCV 확인 범위] 끝 보고에 고칠 것\n')"
  c="$(scv_mp_warn_has_principle "")"
  if [[ "$a$b$c" == "100" ]]; then ok "T7 원칙 줄이 있으면 1 · 다른 경고 · 빈 글은 0"; else bad "T7 [$a] [$b] [$c]"; fi
else bad "T7 scv_mp_warn_has_principle 이 없다"; fi

exit "$fail"
