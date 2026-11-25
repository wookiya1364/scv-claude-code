#!/usr/bin/env bash
# test-guard-wait.sh — 앞에서 오래 기다리는 호출 거절(계획 20261125-wookiya1364-visible-evidence-background · TESTS.md T7 ~ T9).
#
# 오래 도는 일은 뒤에서 돌린다. 긴 대기 값을 실은 도구 호출, 뒤로 보내지 않고 잠자기로 기다리는 셸 명령은 가드가 부르기 전에
# 거절하고, 짧은 대기 · 뒤로 보낸 명령 · 보통 명령은 이 규칙으로 건드리지 않는다. 끄는 설정에서는 거절하지 않는다.
# 이 규칙의 거절인지는 이유 글의 머리("[SCV 뒤에서]")로 가른다 — 다른 규칙의 거절과 섞이지 않게.
#
# Run: bash core/tests/test-guard-wait.sh
set -uo pipefail
unset SCV_BACKGROUND_FIRST SCV_WAIT_FIELD SCV_BACKGROUND_FIELD 2>/dev/null || true
CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"; GUARD="$CORE/template/hooks/guard.sh"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-gw.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
KOREAN='{"SCV_LANG":"korean"}'
mkproj() { local p="$WORK/$1"; mkdir -p "$p/scv/journal" "$p/scv/promote"; printf '%s\n' "${2:-$KOREAN}" > "$p/scv/scv_settings.json"; printf '%s' "$p"; }
gate() {  # <프로젝트> <도구 입력 JSON> → 가드가 낸 글
  ( cd "$1" && jq -cn --arg c "$1" --argjson x "$2" '{session_id:"s1",cwd:$c,tool_name:"AnyTool",tool_input:$x}' \
    | SCV_GUARD_MODE=gate-any SCV_GUARD_SCRIPTS="$CORE/scripts" SCV_GUARD_STATE="$WORK/gs" SCV_HELP_FIRST_ALLOW="" bash "$GUARD" 2>/dev/null )
}
mine() { grep -c 'SCV 뒤에서' <<<"$1" || true; }

# ---------- T7 — 앞에서 오래 기다리는 호출을 거절한다 ----------
P="$(mkproj t7)"
a="$(gate "$P" '{"wait_for_output_ms":200000}')"
b="$(gate "$P" '{"command":"sleep 120 && tail -3 run.log"}')"
c="$(gate "$P" '{"command":"until grep -q DONE run.log; do sleep 15; done"}')"
if [[ "$(mine "$a")" == 1 && "$(mine "$b")" == 1 && "$(mine "$c")" == 1 ]] && grep -q '"permissionDecision":"deny"' <<<"$a" && grep -qF '뒤에서 돌리고' <<<"$b"; then
  ok "T7 긴 대기 값 · 잠자기 120초 · 기다림 루프를 거절하고 뒤에서 돌리라고 안내"
else bad "T7 대기=$(mine "$a") 잠자기=$(mine "$b") 루프=$(mine "$c")"; fi

# ---------- T8 — 보통 호출은 건드리지 않는다 ----------
n=0
for x in '{"wait_for_output_ms":5000}' '{"command":"sleep 600 && make all","run_in_background":true}' '{"command":"ls -la && echo sleepy"}' '{"command":"sleep 2; echo ok"}'; do
  n=$(( n + $(mine "$(gate "$P" "$x")") ))
done
[[ "$n" == 0 ]] && ok "T8 짧은 대기 · 뒤로 보낸 명령 · 보통 명령 · 잠자기 2초: 이 규칙의 거절 0건" || bad "T8 거절 $n건"

# ---------- T9 — 끄는 설정 ----------
Q="$(mkproj t9 '{"SCV_LANG":"korean","SCV_BACKGROUND_FIRST":"off"}')"
d="$(gate "$Q" '{"wait_for_output_ms":200000}')"; e="$(gate "$Q" '{"command":"sleep 120 && tail -3 run.log"}')"
f="$( cd "$P" && jq -cn --arg c "$P" '{session_id:"s1",cwd:$c,tool_name:"AnyTool",tool_input:{wait_for_output_ms:200000}}' \
  | SCV_BACKGROUND_FIRST=off SCV_GUARD_MODE=gate-any SCV_GUARD_SCRIPTS="$CORE/scripts" SCV_GUARD_STATE="$WORK/gs" SCV_HELP_FIRST_ALLOW="" bash "$GUARD" 2>/dev/null )"
[[ "$(mine "$d")" == 0 && "$(mine "$e")" == 0 && "$(mine "$f")" == 0 ]] && ok "T9 설정 · 환경 변수로 끄면 이 규칙의 거절 0건" || bad "T9 설정=$(mine "$d"),$(mine "$e") 환경=$(mine "$f")"

exit "$fail"
