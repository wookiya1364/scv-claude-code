#!/usr/bin/env bash
# test-step-report.sh — 단계 보고(protocols/work.md "Step progress")가 도구가 있고 구현 중일 때만 한 줄을 싣는지 본다.
#
# T1 칸 없음 → 0바이트 · T2 칸 있음 + 구현 중 → 1줄(≤400B, 도구 · 계획 이름) · T3 구현 중 계획 없음 → 0바이트 ·
# T4 매 턴 훅: 칸 없음 → 단계 줄 0, 칸 있음 → 1 · T5 work · codegen 이 시작 · 끝 · 막힘을 말한다.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SR="$CORE/scripts/step-report.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

printf 'SCV_HOST_PROFILE_API=1\n' > "$WORK/off.env"
printf 'SCV_HOST_PROFILE_API=1\nSCV_STEP_TOOL=demo_step\n' > "$WORK/on.env"
proj() {  # <폴더> <상태> — promote 에 계획 하나
  mkdir -p "$1/scv/promote/20260102-a-y"
  printf -- '---\ntitle: y\nstatus: %s\n---\n# y\n' "$2" > "$1/scv/promote/20260102-a-y/PLAN.md"
}
run_line() { (cd "$1" && SCV_HOST_PROFILE="$2" bash "$SR" line); }

P1="$WORK/p1"; proj "$P1" in_progress
o="$(run_line "$P1" "$WORK/off.env")"
[[ -z "$o" ]] && ok "T1 no step tool → nothing" || bad "T1 printed with no tool: $o"

o="$(run_line "$P1" "$WORK/on.env")"
n="$(printf '%s\n' "$o" | grep -c . || true)"; b="$(printf '%s' "$o" | wc -c | tr -d ' ')"
if [[ "$n" == 1 && "$b" -le 400 && "$o" == *demo_step* && "$o" == *20260102-a-y* ]]; then ok "T2 one line, $b bytes, tool and plan named"
else bad "T2 lines=$n bytes=$b: $o"; fi

P3="$WORK/p3"; proj "$P3" planned
o="$(run_line "$P3" "$WORK/on.env")"
[[ -z "$o" ]] && ok "T3 no plan in progress → nothing" || bad "T3 printed with no active plan: $o"

hook() {  # <프로젝트> <프로필> → 매 턴 훅 출력
  (cd "$1" && printf '{"prompt":"안녕","session_id":"s1"}' \
    | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$2" bash "$CORE/template/hooks/on-user-prompt.sh" 2>/dev/null) || true
}
h0="$(hook "$P1" "$WORK/off.env" | grep -c '^\[SCV 단계\]' || true)"
h1="$(hook "$P1" "$WORK/on.env" | grep -c '^\[SCV 단계\]' || true)"
[[ "$h0" == 0 && "$h1" == 1 ]] && ok "T4 per-turn hook carries the line only with a tool" || bad "T4 hook lines: off=$h0 on=$h1"

w="$CORE/protocols/work.md"; c="$CORE/protocols/codegen.md"
if grep -q '^### Step progress' "$w" && grep -q '^### Step progress' "$c" \
   && grep -q '`doing` when you start' "$w" && grep -q '`done` when it is finished' "$w" && grep -q '`blocked` with a one-line reason' "$w"; then
  ok "T5 work and codegen say when to report (doing · done · blocked)"
else bad "T5 step progress rule missing"; fi

(( fail )) && exit 1
echo "step-report: all checks passed"
