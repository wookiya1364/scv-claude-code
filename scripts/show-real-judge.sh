#!/usr/bin/env bash
# show-real-judge.sh — SCV 실사용 보고의 판정자 명령(호스트 설정 SCV_JUDGE_COMMAND, Core 0.68.0+). Claude Code 래퍼 몫.
#
# 표준입력: 코어가 만든 판정 질문 → 표준출력: 모델의 답 글. 못 하면 0 이 아닌 종료 코드 — 코어는 그 묶음을 '판정 못 한 턴'으로
# 세고 보고를 끝까지 낸다. 모델은 Sonnet(Core 0.68.0 측정: 개발용에서 기준을 넘는 첫 모델), 도구 없이 · MCP 없이 · 이 플러그인을
# 끈 채 부른다. 부른 세션의 환경 변수(세션 id 등)는 물려주지 않는다. 시간 제한: SCV_JUDGE_TIMEOUT 초(기본 300)가 지나면 판정자를
# 끝낸다(timeout 이 있으면 그것으로, 없으면 perl alarm). 보고는 이 명령을 캐시 폴더에서 부른다.
set -u
command -v claude >/dev/null 2>&1 || exit 127
command -v jq >/dev/null 2>&1 || exit 127
limit="${SCV_JUDGE_TIMEOUT:-300}"
[[ "$limit" =~ ^[1-9][0-9]*$ ]] || limit=300

bounded() {  # <명령…> — 시간 제한 안에서 돌린다
  if command -v timeout >/dev/null 2>&1; then timeout "$limit" "$@"
  elif command -v perl >/dev/null 2>&1; then perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$limit" "$@"
  else "$@"
  fi
}

tmp="$(mktemp "${TMPDIR:-/tmp}/scv-judge.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT
# 답은 파일로 받는다 — 시간 제한으로 끝낸 판정자의 자식 프로세스가 출력을 붙잡아도 기다리지 않게.
bounded env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_EFFORT \
  -u CLAUDE_PID -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
  -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS \
  claude -p --model sonnet --tools "" --strict-mcp-config --settings '{"enabledPlugins":{"scv@scv-claude-code":false}}' \
  --system-prompt "Follow the user's instructions exactly." --output-format json > "$tmp" 2>/dev/null || exit 1
ans="$(jq -r 'if (.is_error // false) then empty else (.result // empty) end' < "$tmp" 2>/dev/null)"
[[ -n "$ans" ]] || exit 1
printf '%s\n' "$ans"
