#!/usr/bin/env bash
# run-plan-tests.sh — 계획의 테스트를 돌리고, 그 실행이 만든 결과 파일을 기록한다.
#
# 이 래퍼를 거치면 첨부(증적)가 파일 이름과 무관하게 이 계획 소속으로 잡힌다 —
# 결과 폴더명이 잘려도(lib/run-manifest.sh 참조) PR/리포트에 붙는다.
#
# Usage:
#   run-plan-tests.sh --slug <slug> --tests <TESTS.md> [--timeout N]
#   run-plan-tests.sh --slug <slug> [--timeout N] -- <command...>
#
#   --slug     기록의 주인이 될 계획 슬러그 (필수)
#   --tests    TESTS.md 경로 — `## How to run` 블록을 추출해 실행
#   --timeout  초 단위 제한 (timeout 명령이 있을 때만 적용)
#   --         이후 인자를 명령으로 직접 실행 (--tests 대신)
#
# 종료코드는 명령의 것을 그대로 전달한다. 명령이 실패해도 기록은 남긴다 —
# 실패 증적도 증적이다. 요약 한 줄(stderr): `manifest: N file(s) for <slug>`
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/run-manifest.sh
source "$SCRIPT_DIR/lib/run-manifest.sh"
# shellcheck source=lib/attachment-scope.sh
source "$SCRIPT_DIR/lib/attachment-scope.sh"

SLUG="" TESTS_FILE="" TIMEOUT_SECS=""
CMD=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)    SLUG="${2:-}"; shift 2 ;;
    --tests)   TESTS_FILE="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT_SECS="${2:-}"; shift 2 ;;
    --)        shift; CMD=("$@"); break ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         echo "run-plan-tests: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$SLUG" ]] || { echo "run-plan-tests: --slug is required" >&2; exit 2; }

CMD_STR=""
if [[ ${#CMD[@]} -eq 0 ]]; then
  [[ -n "$TESTS_FILE" && -f "$TESTS_FILE" ]] \
    || { echo "run-plan-tests: pass --tests <TESTS.md> or -- <command...>" >&2; exit 2; }
  CMD_STR="$(attachment_scope_read_test_command "$TESTS_FILE" || true)"
  [[ -n "${CMD_STR//[[:space:]]/}" ]] \
    || { echo "run-plan-tests: no '## How to run' block in $TESTS_FILE" >&2; exit 2; }
fi

# 결과 폴더는 관례상 test-results — 모노레포 등에서는 TEST_RESULTS_DIR 로 지정
TR_DIR="${TEST_RESULTS_DIR:-test-results}"

# 실행 전 스냅샷: marker(mtime 기준) + 파일 목록(같은 초에 생긴 새 파일 대비)
MARKER="$(mktemp)"; PRE="$(mktemp)"
trap 'rm -f "$MARKER" "$PRE"' EXIT
[[ -d "$TR_DIR" ]] && find "$TR_DIR" -type f ! -path "$TR_DIR/.scv/*" 2>/dev/null > "$PRE"

run_cmd() {
  if [[ ${#CMD[@]} -gt 0 ]]; then "${CMD[@]}"; else bash -c "$CMD_STR"; fi
}
if [[ -n "$TIMEOUT_SECS" ]] && command -v timeout >/dev/null 2>&1; then
  if [[ ${#CMD[@]} -gt 0 ]]; then timeout "$TIMEOUT_SECS" "${CMD[@]}"; else timeout "$TIMEOUT_SECS" bash -c "$CMD_STR"; fi
else
  run_cmd
fi
RC=$?

run_manifest_record "$SLUG" "$MARKER" "$PRE" "$TR_DIR"
N=0
MF="$(run_manifest_path "$SLUG" "$TR_DIR")"
[[ -f "$MF" ]] && N="$(grep -c . "$MF" 2>/dev/null || true)"
echo "manifest: ${N:-0} file(s) for $SLUG" >&2
exit "$RC"
