#!/usr/bin/env bash
# test-show-real-judge.sh — Claude 래퍼의 판정자 명령(scripts/show-real-judge.sh, Core 0.68.0 의 SCV_JUDGE_COMMAND) 검사.
#
# 가짜 claude 로 본다 — 부르는 방식(Sonnet · 도구 없음 · MCP 없음 · 이 플러그인 끔 · 부른 세션의 환경 변수를 물려주지 않음) ·
# 답 꺼내기 · 실패(오류 답 · 0 아닌 종료) · 시간 제한, 그리고 설치본 모양 그대로 실사용 보고(scripts/show-real-report.sh)가 호스트
# 설정의 판정자 명령을 찾아 부르는지. 실제 모델은 부르지 않는다.
# Run: bash tests/test-show-real-judge.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
J="$ROOT/scripts/show-real-judge.sh"; REPORT="$ROOT/scripts/show-real-report.sh"; PROFILE="$ROOT/host-profile.env"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
for f in "$J" "$REPORT" "$PROFILE"; do [[ -f "$f" ]] || { echo "✖ 없음: $f"; exit 1; }; done
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
W="$(mktemp -d "${TMPDIR:-/tmp}/scv-judge-test.XXXXXX")"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/fc"
cat > "$W/bin/claude" <<'FC'
#!/usr/bin/env bash
# 가짜 claude — 인자 · 환경 · 표준입력을 남기고, 받은 발췌 수만큼 yes 를 담아 답한다(FC_MODE 로 실패 모양).
printf '%s\n' "$@" > "$FC_DIR/args"; env > "$FC_DIR/env"; cat > "$FC_DIR/stdin"; echo x >> "$FC_DIR/calls"
n="$(grep -c '^=== Excerpt [0-9]* ===$' "$FC_DIR/stdin")"; [[ "$n" -gt 0 ]] || n=1
arr="$(printf '"yes",%.0s' $(seq 1 "$n"))"; arr="[${arr%,}]"
case "${FC_MODE:-ok}" in
  ok)    jq -cn --arg r "$arr" '{type: "result", is_error: false, result: $r}' ;;
  error) jq -cn '{type: "result", is_error: true, result: "You have hit your limit"}' ;;
  exit1) exit 1 ;;
  slow)  sleep 20; jq -cn --arg r "$arr" '{is_error: false, result: $r}' ;;
esac
FC
chmod +x "$W/bin/claude"
judge() {  # <FC_MODE> [환경 이름=값…] → JO(출력) · rc
  local mode="$1"; shift
  JO="$(printf 'Question\n\n=== Excerpt 1 ===\nhello\n' | env "$@" FC_DIR="$W/fc" FC_MODE="$mode" PATH="$W/bin:$PATH" \
        CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=parent-session bash "$J")"; rc=$?
}

echo "── 판정자 명령 ──"
rm -f "$W/fc/"*; judge ok
[[ "$rc" == 0 && "$JO" == '["yes"]' ]] && ok "답 글(result)만 낸다" || fail "답: rc=$rc [$JO]"
grep -qx 'sonnet' "$W/fc/args" && grep -B1 -x 'sonnet' "$W/fc/args" | head -1 | grep -qx -- '--model' \
  && ok "모델은 Sonnet" || fail "모델: [$(tr '\n' ' ' < "$W/fc/args")]"
grep -A1 -x -- '--tools' "$W/fc/args" | sed -n 2p | grep -qx '' && grep -qx -- '--strict-mcp-config' "$W/fc/args" \
  && grep -qF '"scv@scv-claude-code":false' "$W/fc/args" && grep -qx -- '-p' "$W/fc/args" \
  && ok "도구 없이 · MCP 없이 · 이 플러그인을 끈 채 · 한 번 묻고 끝냄" || fail "인자: [$(tr '\n' ' ' < "$W/fc/args")]"
! grep -qE '^(CLAUDECODE|CLAUDE_CODE_SESSION_ID)=' "$W/fc/env" && ok "부른 세션의 환경 변수(CLAUDECODE · 세션 id)를 물려주지 않는다" || fail "환경 변수가 넘어감"
grep -qxF '=== Excerpt 1 ===' "$W/fc/stdin" && ok "질문은 표준입력으로 그대로 간다" || fail "표준입력"
for m in error exit1; do
  judge "$m"
  [[ "$rc" != 0 && -z "$JO" ]] && ok "실패($m) — 0 아닌 종료 · 출력 없음(보고는 그 묶음을 판정 못 함으로 셈)" || fail "실패($m): rc=$rc [$JO]"
done
t0=$(date +%s); judge slow SCV_JUDGE_TIMEOUT=2; t1=$(date +%s)
[[ "$rc" != 0 && -z "$JO" && $((t1 - t0)) -lt 15 ]] && ok "시간 제한 — 2초 제한에 $((t1 - t0))초 만에 끝남(0 아닌 종료)" || fail "시간 제한: rc=$rc $((t1 - t0))s"

echo "── 설치본 모양 그대로: 실사용 보고가 판정자 명령을 찾아 부른다 ──"
grep -qx 'SCV_JUDGE_COMMAND=scripts/show-real-judge.sh' "$PROFILE" && grep -qx 'SCV_CHOICE_REJECTED_PREFIX=<tool_use_error>' "$PROFILE" \
  && ok "호스트 설정: 판정자 명령 · 거절 표시" || fail "호스트 설정 값"
mkdir -p "$W/rec"
python3 - "$W/rec/s.jsonl" <<'PY'
import json, sys
rows = [{"type": "user", "message": {"content": "기능 만들어 줘"}, "timestamp": "2026-10-11T02:00:00Z"},
        {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "e1", "name": "Write", "input": {"file_path": "a.py", "content": "x"}}]}},
        {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "r1", "name": "Bash", "input": {"command": "pytest"}}]}},
        {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "r1", "content": "32 passed in 0.51s"}]}},
        {"type": "assistant", "message": {"content": [{"type": "text", "text": "32 passed 입니다.\n\n리뷰 부탁드립니다."}]}}]
open(sys.argv[1], "w", encoding="utf-8").write("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
PY
rm -f "$W/fc/"*
RP="$(cd "$W" && TZ=UTC XDG_CACHE_HOME="$W/xdg" FC_DIR="$W/fc" PATH="$W/bin:$PATH" SCV_LANG=english \
      bash "$REPORT" --before 2026-10-01..2026-10-05 --after 2026-10-08..2026-10-12 --dir "$W/rec" 2>&1)"; rc=$?
[[ "$rc" == 0 && -f "$W/fc/calls" ]] && grep -qF 'decided by the judge: Before 0 (shown 0) · After 1 (shown 1)' <<<"$RP" \
  && grep -qF '| After 2026-10-08..2026-10-12 | 1 | 1 | 100% (1) |' <<<"$RP" \
  && ok "보고가 판정자를 불러 그 턴을 보여 줌으로 센다(판정자 1번)" || fail "보고: rc=$rc [$RP]"

echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL SHOW-REAL-JUDGE CHECKS OK"; exit 0; } || exit 1
