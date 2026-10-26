#!/usr/bin/env bash
# test-channel-engine.sh — /scv:channel 의 엔진 scripts/channel.sh (0.71.0).
#
# 가짜 claude · git 으로 본다 — 상태(마켓 있음/없음, 그 브랜치, 설치된 버전)를 파일로 들고, 받은 plugin 명령을 기록하고 상태를
# 바꾼다. 실제 마켓 · 네트워크 · 설치본은 건드리지 않는다. 진짜 바꿔 끼우기는 임시 설정 폴더(CLAUDE_CONFIG_DIR)에서 따로 봤다.
# Run: bash tests/test-channel-engine.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
C="$ROOT/scripts/channel.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
[[ -f "$C" && -f "$ROOT/scripts/lib/channel.sh" ]] || { echo "✖ 없음: $C 또는 lib/channel.sh"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
W="$(mktemp -d "${TMPDIR:-/tmp}/scv-channel-test.XXXXXX")"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"

# 가짜 claude — $FC_DIR/mkt (있으면 마켓 있음, 내용은 브랜치 — 비면 없음), $FC_DIR/ver (설치된 버전, 없으면 안 깔림),
# $FC_DIR/failon (이 문구로 시작하는 명령은 실패). 마켓을 지우면 플러그인도 빠진다(실제 CLI 와 같게 — 2026-10-26 확인).
cat > "$W/bin/claude" <<'FC'
#!/usr/bin/env bash
[[ "$1" == plugin ]] || exit 9; shift
echo "$*" >> "$FC_DIR/calls"
if [[ -f "$FC_DIR/failon" ]] && [[ "$*" == "$(cat "$FC_DIR/failon")"* ]]; then echo "Error: failed" >&2; exit 1; fi
case "$*" in
  "marketplace list --json")
    if [[ -f "$FC_DIR/mkt" ]]; then r="$(cat "$FC_DIR/mkt")"
      if [[ -n "$r" ]]; then echo '[{"name":"scv-claude-code","source":"git","ref":"'"$r"'"},{"name":"other"}]'
      else echo '[{"name":"scv-claude-code","source":"github"},{"name":"other"}]'; fi
    else echo '[{"name":"other"}]'; fi ;;
  "list --json")
    if [[ -f "$FC_DIR/ver" ]]; then echo '[{"id":"scv@scv-claude-code","version":"'"$(cat "$FC_DIR/ver")"'"},{"id":"x@other","version":"1"}]'
    else echo '[{"id":"x@other","version":"1"}]'; fi ;;
  "marketplace remove scv-claude-code") rm -f "$FC_DIR/mkt" "$FC_DIR/ver" ;;
  "marketplace add "*)
    src="${*#marketplace add }"; case "$src" in *'#'*) printf '%s' "${src#*#}" > "$FC_DIR/mkt" ;; *) : > "$FC_DIR/mkt" ;; esac ;;
  "install scv@scv-claude-code")
    r="$(cat "$FC_DIR/mkt")"; case "$r" in channel/dev) echo 0.70.5-dev.abc1234 ;; channel/stage) echo 0.70.5-stage.def5678 ;; *) echo 0.70.4 ;; esac > "$FC_DIR/ver" ;;
  *) exit 8 ;;
esac
exit 0
FC
# 가짜 git — ls-remote 만. $FC_DIR/branches 에 있는 브랜치만 있다.
cat > "$W/bin/git" <<'FG'
#!/usr/bin/env bash
[[ "$1" == ls-remote ]] || exit 9
grep -qxF "${@: -1}" "$FC_DIR/branches" 2>/dev/null
FG
chmod +x "$W/bin/claude" "$W/bin/git"

case_dir() { rm -rf "$W/fc"; mkdir -p "$W/fc"; : > "$W/fc/calls"; printf '%s\n' channel/dev channel/stage > "$W/fc/branches"; }
run() { FC_DIR="$W/fc" SCV_CLAUDE_BIN="$W/bin/claude" SCV_CHANNEL_GIT_BIN="$W/bin/git" bash "$C" "$@" 2>&1; }
calls() { grep -vE '^(marketplace list|list) --json' "$W/fc/calls" | tr '\n' '|'; }

echo "── [T0] 인자 없이 — 지금 채널만 보이고 아무것도 바꾸지 않는다 ──"
case_dir; : > "$W/fc/mkt"; echo 0.70.4 > "$W/fc/ver"
OUT="$(run)"; rc=$?
[[ $rc -eq 0 && "$OUT" == "CHANNEL: prod 0.70.4" && -z "$(calls)" ]] && ok "운영 0.70.4, 명령 없음" || fail "rc=$rc $OUT / $(calls)"

echo "── [T5] 운영 → 개발: 지우기 → 브랜치 붙여 넣기 → 설치, 버전에 dev 표시 ──"
OUT="$(run dev)"; rc=$?
[[ "$(calls)" == "marketplace remove scv-claude-code|marketplace add https://github.com/wookiya1364/scv-claude-code.git#channel/dev|install scv@scv-claude-code|" ]] \
  && ok "순서: remove → add #channel/dev → install" || fail "순서: $(calls)"
[[ $rc -eq 0 && "$OUT" == *"RESULT: switched prod 0.70.4 -> dev 0.70.5-dev.abc1234"* && "$OUT" == *"NEXT: "*"/reload-plugins"* ]] \
  && ok "결과 줄과 다시 불러오기 안내" || fail "rc=$rc $OUT"

echo "── [T6] 개발 → 운영: 브랜치 없이 다시 넣는다 ──"
: > "$W/fc/calls"; OUT="$(run prod)"; rc=$?
[[ "$(calls)" == "marketplace remove scv-claude-code|marketplace add https://github.com/wookiya1364/scv-claude-code.git|install scv@scv-claude-code|" ]] \
  && ok "순서: remove → add (꼬리 없음) → install" || fail "순서: $(calls)"
[[ $rc -eq 0 && "$OUT" == *"RESULT: switched dev 0.70.5-dev.abc1234 -> prod 0.70.4"* ]] && ok "운영으로 돌아옴" || fail "rc=$rc $OUT"

echo "── [T3] 같은 채널이면 아무것도 하지 않는다 ──"
: > "$W/fc/calls"; OUT="$(run prod)"; rc=$?
[[ $rc -eq 0 && "$OUT" == *"RESULT: already prod 0.70.4"* && -z "$(calls)" ]] && ok "이미 운영 — 명령 없음" || fail "rc=$rc $OUT / $(calls)"

echo "── [T7a] 채널 브랜치가 없으면 지우기 전에 멈춘다 ──"
case_dir; : > "$W/fc/mkt"; echo 0.70.4 > "$W/fc/ver"; : > "$W/fc/branches"
OUT="$(run stage)"; rc=$?
[[ $rc -eq 1 && "$OUT" == *"RESULT: failed branch-missing channel/stage"* && -z "$(calls)" && -f "$W/fc/ver" ]] \
  && ok "branch-missing, 설치 그대로" || fail "rc=$rc $OUT / $(calls)"

echo "── [T7b] 지운 뒤 실패하면 그 단계를 말하고 원래 채널로 되돌린다 ──"
case_dir; : > "$W/fc/mkt"; echo 0.70.4 > "$W/fc/ver"; echo "marketplace add https://github.com/wookiya1364/scv-claude-code.git#" > "$W/fc/failon"
OUT="$(run dev)"; rc=$?
[[ $rc -eq 1 && "$OUT" == *"STEP: marketplace add https://github.com/wookiya1364/scv-claude-code.git#channel/dev fail"* \
   && "$OUT" == *"RESULT: failed marketplace add"* && "$OUT" == *"RESULT: restored prod"* && "$OUT" != *"switched"* ]] \
  && ok "실패 단계 + 되돌림, 성공으로 보고하지 않음" || fail "rc=$rc $OUT"
[[ "$(cat "$W/fc/ver" 2>/dev/null)" == 0.70.4 ]] && ok "되돌린 뒤 운영 0.70.4 설치됨" || fail "되돌린 뒤 버전: $(cat "$W/fc/ver" 2>/dev/null)"

echo "── [T7c] 모르는 채널은 사용법 오류 ──"
case_dir; OUT="$(run nightly)"; rc=$?
[[ $rc -eq 2 ]] && ok "rc=2" || fail "rc=$rc $OUT"

echo "── 스킬 ──"
S="$ROOT/skills/channel/SKILL.md"
[[ -f "$S" ]] && grep -q 'scripts/channel.sh' "$S" && grep -q 'AskUserQuestion' "$S" && ok "skills/channel 이 엔진과 선택 창을 쓴다" || fail "skills/channel/SKILL.md"

echo; echo "test-channel-engine: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
