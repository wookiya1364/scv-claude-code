#!/usr/bin/env bash
# test-mods.sh — 모드 명령 셋(/scv:mods · /scv:mods-install · /scv:mods-remove)의 엔진 scripts/mods.sh 와 스킬 검사.
#
# 가짜 claude 로 본다 — 상태(마켓 있음/없음, 설치된 모드와 버전)를 파일로 들고, 받은 plugin 명령을 기록하고 상태를 바꾼다.
# 실제 마켓 · 네트워크 · 설치본은 건드리지 않는다. /scv:update 진단이 그대로인지도 본다.
# Run: bash tests/test-mods.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
U="$ROOT/scripts/update.sh"; M="$ROOT/scripts/mods.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
for f in "$U" "$M"; do [[ -f "$f" ]] || { echo "✖ 없음: $f"; exit 1; }; done
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
W="$(mktemp -d "${TMPDIR:-/tmp}/scv-mods-test.XXXXXX")"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"

# 가짜 claude — $FC_DIR/mkt (있으면 마켓 있음), $FC_DIR/inst ("모드 버전" 줄), $FC_DIR/avail ("모드" 줄),
# $FC_DIR/next (업데이트 뒤 버전), $FC_DIR/failon (이 단어로 시작하는 명령은 인증 오류로 실패 — $FC_DIR/failmsg 가
# 있으면 그 문구로).
cat > "$W/bin/claude" <<'FC'
#!/usr/bin/env bash
[[ "$1" == plugin ]] || exit 9; shift
echo "$*" >> "$FC_DIR/calls"
if [[ -f "$FC_DIR/failon" ]] && [[ "$*" == "$(cat "$FC_DIR/failon")"* ]]; then
  if [[ -f "$FC_DIR/failmsg" ]]; then cat "$FC_DIR/failmsg" >&2; exit 1; fi
  echo "Error: Failed to clone marketplace repository: fatal: could not read Username for 'https://github.com': terminal prompts disabled" >&2; exit 1
fi
inst() { [[ -f "$FC_DIR/inst" ]] && cat "$FC_DIR/inst"; }
case "$*" in
  "marketplace list --json")
    if [[ -f "$FC_DIR/mkt" ]]; then echo '[{"name":"scv-mods","source":"github","repo":"wookiya1364/scv-mods"},{"name":"other","source":"github"}]'; else echo '[{"name":"other","source":"github"}]'; fi ;;
  "list --json")
    { inst | awk 'NF { printf "{\"id\":\"%s@scv-mods\",\"version\":\"%s\"}\n", $1, $2 }'; echo '{"id":"x@other","version":"1"}'; } | jq -cs . ;;
  "list --json --available")
    { [[ -f "$FC_DIR/avail" ]] && awk 'NF { printf "{\"name\":\"%s\",\"marketplaceName\":\"scv-mods\"}\n", $1 }' "$FC_DIR/avail"; echo '{"name":"y","marketplaceName":"other"}'; } \
      | jq -cs --argjson i "$(inst | awk 'NF { printf "{\"id\":\"%s@scv-mods\",\"version\":\"%s\"}\n", $1, $2 }' | jq -cs .)" '{installed: $i, available: .}' ;;
  "marketplace add "*) touch "$FC_DIR/mkt" ;;
  "marketplace update "*) : ;;
  "install "*) m="${2%@*}"; echo "$m 1111111" >> "$FC_DIR/inst" ;;
  "update "*) m="${2%@*}"; v="$(cat "$FC_DIR/next" 2>/dev/null)"; [[ -n "$v" ]] && { inst | awk -v m="$m" -v v="$v" '$1 == m { $2 = v } { print }' > "$FC_DIR/inst.n"; mv "$FC_DIR/inst.n" "$FC_DIR/inst"; } ;;
  "uninstall "*) m="${2%@*}"; inst | awk -v m="$m" '$1 != m' > "$FC_DIR/inst.n"; mv "$FC_DIR/inst.n" "$FC_DIR/inst" ;;
  *) exit 8 ;;
esac
exit 0
FC
chmod +x "$W/bin/claude"

case_dir() { rm -rf "$W/fc"; mkdir -p "$W/fc"; : > "$W/fc/calls"; }
run() { FC_DIR="$W/fc" SCV_CLAUDE_BIN="$W/bin/claude" bash "$M" "$@" 2>&1; }
calls() { grep -vE '^(marketplace list|list) --json' "$W/fc/calls"; }

echo "── [T1] /scv:update 진단은 그대로 ──"
OUT1="$(bash "$U" 2>&1)"
keys="$(printf '%s\n' "$OUT1" | sed -E 's/:.*//' | tr '\n' ' ')"
[[ "$keys" == "INSTALLED_VERSION MARKETPLACE_NAME PLUGIN_NAME LATEST_VERSION UP_TO_DATE " ]] && ok "출력 키 5개 그대로: $keys" || fail "출력 키가 바뀜: $keys"
grep -q '^MODS_' <<<"$OUT1" && fail "업데이트 진단에 모드 줄이 나옴" || ok "모드 줄 없음"

echo "── [T2] 목록 ──"
case_dir; touch "$W/fc/mkt"; echo "scv-dashboard 0.1.0" > "$W/fc/inst"; echo "scv-other" > "$W/fc/avail"
O="$(run list)"
grep -q '^MOD: scv-dashboard installed 0.1.0$' <<<"$O" && ok "설치된 모드와 버전" || fail "설치 줄: $O"
grep -q '^MOD: scv-other available$' <<<"$O" && ok "설치 가능한 모드" || fail "설치 가능 줄: $O"
grep -qE '^MOD: (x|y) ' <<<"$O" && fail "다른 마켓 모드가 섞임" || ok "다른 마켓은 빠짐"
[[ -z "$(calls)" ]] && ok "목록은 아무것도 바꾸지 않음" || fail "목록이 명령을 실행: $(calls)"

echo "── [T2b] /scv:mods — 인자 없이: 설치된 모드 전부 업데이트 + 목록 ──"
case_dir; touch "$W/fc/mkt"; echo "scv-dashboard 0.1.0" > "$W/fc/inst"; echo "scv-other" > "$W/fc/avail"; echo 0.2.0 > "$W/fc/next"
O="$(run)"
grep -q '^RESULT: scv-dashboard updated 0.1.0 -> 0.2.0$' <<<"$O" && ok "업데이트 전 → 후" || fail "결과: $O"
grep -q '^MOD: scv-dashboard installed 0.2.0$' <<<"$O" && grep -q '^MOD: scv-other available$' <<<"$O" && ok "이어서 목록(새 버전)" || fail "목록: $O"
case_dir; echo "scv-other" > "$W/fc/avail"
O="$(run)"
grep -q 'mods-install' <<<"$O" && ok "마켓이 없으면 설치 명령 안내" || fail "안내 없음: $O"
[[ -z "$(calls)" ]] && ok "마켓이 없을 땐 아무것도 바꾸지 않음" || fail "호출: $(calls | tr '\n' '|')"

echo "── [T2c] /scv:mods-install 의 보기 — 마켓이 없으면 추가 뒤 설치 가능 목록 ──"
case_dir; echo "scv-dashboard" > "$W/fc/avail"
O="$(run candidates)"
[[ "$(calls | tr '\n' '|')" == "marketplace add wookiya1364/scv-mods|" ]] && ok "마켓 추가 1번" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^MOD: scv-dashboard available$' <<<"$O" && ok "설치 가능한 모드" || fail "보기: $O"

echo "── [T3] 설치 — 마켓이 없으면 추가부터 ──"
case_dir
O="$(run install scv-dashboard)"
[[ "$(calls | tr '\n' '|')" == "marketplace add wookiya1364/scv-mods|install scv-dashboard@scv-mods|" ]] && ok "순서: 마켓 추가 → 설치" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv-dashboard installed 1111111$' <<<"$O" && ok "설치됨 + 버전" || fail "결과: $O"
grep -q '/reload-plugins' <<<"$O" && ok "다시 불러오기 안내" || fail "다시 불러오기 안내 없음"

echo "── [T4] 이미 설치됨 → 업데이트로 ──"
case_dir; touch "$W/fc/mkt"; echo "scv-dashboard 0.1.0" > "$W/fc/inst"
O="$(run install scv-dashboard)"
calls | grep -q '^install ' && fail "다시 설치함" || ok "설치 호출 0번"
[[ "$(calls | grep -c '^update scv-dashboard@scv-mods$')" -eq 1 ]] && ok "업데이트 1번" || fail "호출: $(calls | tr '\n' '|')"

echo "── [T5] 업데이트 — 전후 버전 ──"
case_dir; touch "$W/fc/mkt"; echo "scv-dashboard 0.1.0" > "$W/fc/inst"; echo 0.2.0 > "$W/fc/next"
O="$(run update scv-dashboard)"
grep -q '^RESULT: scv-dashboard updated 0.1.0 -> 0.2.0$' <<<"$O" && ok "전 → 후 버전" || fail "결과: $O"
grep -q '/reload-plugins' <<<"$O" && ok "바뀌면 다시 불러오기 안내" || fail "안내 없음"
case_dir; touch "$W/fc/mkt"; echo "scv-dashboard 0.1.0" > "$W/fc/inst"
O="$(run update scv-dashboard)"
grep -q '^RESULT: scv-dashboard up-to-date 0.1.0$' <<<"$O" && ok "같으면 이미 최신" || fail "결과: $O"
grep -q '/reload-plugins' <<<"$O" && fail "안 바뀌었는데 다시 불러오기 안내" || ok "안 바뀌면 안내 없음"
case_dir; touch "$W/fc/mkt"; printf 'scv-dashboard 0.1.0\nscv-b 1\n' > "$W/fc/inst"; echo 2 > "$W/fc/next"
O="$(run update)"
[[ "$(calls | grep -c '^update ')" -eq 2 ]] && ok "이름 없으면 설치된 모드 전부" || fail "호출: $(calls | tr '\n' '|')"

echo "── [T6] 삭제 ──"
case_dir; touch "$W/fc/mkt"; echo "scv-dashboard 0.1.0" > "$W/fc/inst"
O="$(run remove scv-dashboard)"
[[ "$(calls | tr '\n' '|')" == "uninstall scv-dashboard@scv-mods|" ]] && ok "uninstall 1번" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv-dashboard removed$' <<<"$O" && ok "삭제됨" || fail "결과: $O"
grep -q '/reload-plugins' <<<"$O" && ok "다시 불러오기 안내" || fail "안내 없음"

echo "── [T7] 마켓 저장소 인증 실패(비공개 마켓) ──"
case_dir; echo "marketplace add" > "$W/fc/failon"
O="$(run install scv-dashboard)"; rc=$?
[[ $rc -ne 0 ]] && ok "종료 코드 $rc" || fail "실패인데 0"
grep -q 'installed' <<<"$O" && fail "설치됐다고 함: $O" || ok "설치됐다고 하지 않음"
grep -q 'gh auth login' <<<"$O" && grep -q 'gh auth setup-git' <<<"$O" && ok "인증 할 일 안내" || fail "안내 없음: $O"
calls | grep -q '^install ' && fail "실패 뒤에도 설치를 부름" || ok "실패 뒤 설치 안 부름"

echo "── [T7b] 이름이 바뀐 모드 — 모드 단계의 not found 는 인증 안내가 아니다 ──"
case_dir; touch "$W/fc/mkt"; echo "scv-hello 0.1.0" > "$W/fc/inst"; echo "update scv-hello" > "$W/fc/failon"
echo "Plugin \"scv-hello\" not found in marketplace \"scv-mods\"" > "$W/fc/failmsg"
O="$(run)"; rc=$?
[[ $rc -ne 0 ]] && ok "종료 코드 $rc" || fail "실패인데 0"
grep -q 'gh auth' <<<"$O" && fail "인증 안내가 나옴: $O" || ok "인증 안내 없음"
grep -q 'mods-install' <<<"$O" && grep -q 'mods-remove' <<<"$O" && ok "새 모드 설치 · 옛 모드 삭제 안내" || fail "안내 없음: $O"
case_dir; echo "marketplace add" > "$W/fc/failon"; echo "Error: repository not found" > "$W/fc/failmsg"
O="$(run install scv-dashboard)"
grep -q 'gh auth login' <<<"$O" && ok "마켓 단계의 not found 는 그대로 인증 안내" || fail "안내 없음: $O"

echo "── [T8] 스킬 — 인자 없음, 설치 · 삭제는 선택 창에서 고름 ──"
for a in mods mods-install mods-remove; do
  S="$ROOT/skills/$a/SKILL.md"
  [[ -f "$S" ]] || { fail "스킬 없음: $a"; continue; }
  grep -q 'scripts/mods.sh' "$S" && ok "$a: 엔진을 부름" || fail "$a: 엔진 호출 없음"
  grep -q '^argument-hint: ""$' "$S" && ok "$a: 인자 없음" || fail "$a: 인자 힌트가 있음"
done
grep -q 'AskUserQuestion' "$ROOT/skills/mods-install/SKILL.md" && ok "mods-install: 선택 창" || fail "mods-install: 선택 창 없음"
grep -q 'AskUserQuestion' "$ROOT/skills/mods-remove/SKILL.md" && ok "mods-remove: 선택 창" || fail "mods-remove: 선택 창 없음"
grep -qiE 'without asking|no question|do not ask' "$ROOT/skills/mods/SKILL.md" && ok "mods: 묻지 않고 업데이트" || fail "mods: 묻지 않는다는 문장 없음"
grep -q 'mods' "$ROOT/skills/update/SKILL.md" && fail "업데이트 스킬에 모드가 남음" || ok "업데이트 스킬은 그대로"

echo "── [T10] 순수 단계 — 같은 입력 같은 출력, 바깥 호출 없음 ──"
case_dir
# shellcheck source=/dev/null
( SCV_CLAUDE_BIN="$W/bin/claude"; FC_DIR="$W/fc"; source "$M"
  a="$(mods_plan install scv-dashboard scv-mods wookiya1364/scv-mods 0 '')"
  b="$(mods_plan install scv-dashboard scv-mods wookiya1364/scv-mods 0 '')"
  s1="$(mods_summary update scv-dashboard 'scv-dashboard 1' 'scv-dashboard 2' '' '')"
  s2="$(mods_summary update scv-dashboard 'scv-dashboard 1' 'scv-dashboard 2' '' '')"
  [[ "$a" == "$b" && "$s1" == "$s2" && -n "$a" ]] && echo SAME || echo DIFF ) > "$W/pure"
[[ "$(cat "$W/pure")" == SAME ]] && ok "두 번 같은 출력" || fail "출력이 다름"
[[ ! -s "$W/fc/calls" ]] && ok "가짜 claude 호출 0번" || fail "순수 단계가 바깥을 부름: $(cat "$W/fc/calls")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
