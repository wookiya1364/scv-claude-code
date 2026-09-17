#!/usr/bin/env bash
# test-help-router-diet.sh — "매 턴 라우터 다이어트" 검사 (v0.51.0+).
#
# 왜 있나: 라우터가 작아져도 계약은 그대로여야 한다 — 언어·쉬운 말·답 모양 절은 바이트 그대로, 기록 계약과
# 명령 셋은 남고, 배경 조사 절은 문구 그대로 full.md 로 옮겨진다. 훅의 전체 진단은 안내문(Learn more ·
# hydrate 방법) 없이 진단 본문 + 권장 행동 첫 줄만 싣고, 사용자가 직접 부른 help.sh 는 그대로다.
#
# Covers TESTS.md T1·T2·T3·T4·T6·T7·T8 of 20260916-wookiya1364-help-router-diet (T5 = test-help-budget, T9 = 전체).
# Run: bash core/tests/test-help-router-diet.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-help-router-diet: payload not found from $HERE" >&2; exit 1; }
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ROUTER="$CORE/protocols/help.md"; FULL="$CORE/protocols/help/full.md"
FIX="$HERE/fixtures"; FORCE_LIB="$CORE/scripts/lib/force-help.sh"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"; HELP_SH="$CORE/scripts/help.sh"
section() { awk -v S="## $2" 'index($0,S)==1{f=1;print;next} f&&/^## /{exit} f' "$1"; }
# 사용자 결정(2026-09-16): 고정 절 4,529B + 계약 문구·명령 ≈1,000B 가 바닥 → scv-core 원본은 7,200B.
# 래퍼가 벤더링하며 호스트 자리표시자를 펼치면 몇백 바이트가 늘 수 있으므로, 사본에서는 budget 검사의 상한(7,500B)을 쓴다.
REPO="$(cd "$CORE/.." && pwd)"
IS_CORE_REPO=0; [[ -f "$REPO/VERSION" && -f "$REPO/core/TEMPLATE_DIGEST" && -d "$REPO/scv/archive" ]] && IS_CORE_REPO=1
ROUTER_MAX=7200; (( IS_CORE_REPO )) || ROUTER_MAX=7500

echo "── [T1] 라우터 크기 ──"
n="$(wc -c < "$ROUTER")"; (( n <= ROUTER_MAX )) && ok "help.md ${n}B ≤ ${ROUTER_MAX}B" || fail "help.md ${n}B > ${ROUTER_MAX}B"

echo "── [T2] 언어·쉬운 말·답 모양 절은 바이트 그대로 ──"
while IFS=$'\t' read -r name want; do
  got="$(section "$ROUTER" "$name" | md5sum | cut -d' ' -f1)"
  [[ "$got" == "$want" ]] && ok "'$name' 절 동일" || fail "'$name' 절이 바뀌었다 ($got ≠ $want)"
done < "$FIX/help-router-kept-sections.tsv"

echo "── [T3] 배경 조사 절은 full.md 로 통째 이동 ──"
! grep -q '^## Deep questions go to a background investigator' "$ROUTER" && ok "라우터에 없음" || fail "라우터에 아직 있다"
grep -q '^## Deep questions go to a background investigator' "$FULL" && ok "full.md 에 있음" || fail "full.md 에 없다"
[[ "$(section "$FULL" "Deep questions go to a background investigator" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | md5sum)" == "$(sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$FIX/help-deep-questions-section.md" | md5sum)" ]] \
  && ok "절 본문 문구 그대로" || fail "절 본문이 다르다"

echo "── [T4] 기록 계약은 라우터에 남는다 ──"
for a in 'protocol: <fingerprint>' 'Append, never overwrite' 'help.sh" --with-context' 'help-state.sh" mark' 'journal-append.sh" --redact-only' 'PROTOCOL: load' 'PROTOCOL: loaded' '## Plain language first' '## Answer shape' '## Language preference'; do
  grep -qF -- "$a" "$ROUTER" && ok "라우터에 [$a]" || fail "라우터에 [$a] 없음"
done
! grep -q '^## Final notes' "$ROUTER" && ok "Final notes 절 제거" || fail "Final notes 절이 남아 있다"

echo "── [T8] 순수부 — 진단 다듬기 ──"
source "$FORCE_LIB"
DIAG=$' Current project diagnosis (/x)\n──\n  [✗] hydrate not done\n  Dependency check:\n    [✓] git      — git operations\n  [i] scv/raw has 3 item(s)\n\n──\n Recommended next action\n──\n  This directory is not hydrated yet.\n\n  Hydrate seeds only the SCV workflow files.\n\n    bash "/p/hydrate.sh" init .\n\n  Run the help action again afterwards.\n\n──\n Learn more\n──\n  Each skill supports --help:\n    /scv:promote --help\n\n  Plugin root:\n    /p\n'
out="$(printf '%s' "$DIAG" | scv_force_trim_diagnosis)"
grep -q 'Current project diagnosis' <<<"$out" && grep -q 'scv/raw has 3' <<<"$out" && ok "(a) 진단 본문 유지" || fail "(a) 진단 본문: $out"
grep -q 'Recommended next action' <<<"$out" && grep -q 'This directory is not hydrated yet' <<<"$out" && ok "(a) 권장 행동 제목 + 첫 줄" || fail "(a) 권장 행동: $out"
! grep -q 'hydrate.sh' <<<"$out" && ! grep -q 'Hydrate seeds' <<<"$out" && ok "(a) hydrate 방법 제거" || fail "(a) 방법 남음: $out"
! grep -q 'Learn more' <<<"$out" && ! grep -q 'Plugin root' <<<"$out" && ok "(a) Learn more 제거" || fail "(a) Learn more 남음: $out"
NOLEARN="${DIAG%%$'\n──\n Learn more'*}"; out="$(printf '%s\n' "$NOLEARN" | scv_force_trim_diagnosis)"
grep -q 'This directory is not hydrated yet' <<<"$out" && ! grep -q 'hydrate.sh' <<<"$out" && ok "(b) Learn more 없는 출력도 권장 첫 줄만" || fail "(b): $out"
PLAIN=$'no diagnosis header here\n Recommended next action\n  x\n'; out="$(printf '%s' "$PLAIN" | scv_force_trim_diagnosis)"
[[ "$out" == "${PLAIN%$'\n'}" ]] && ok "(c) 진단 제목 없으면 입력 그대로" || fail "(c): $out"
ONLY=$' Current project diagnosis (/x)\n  [✓] git\n\n Recommended next action\n──\n'; out="$(printf '%s' "$ONLY" | scv_force_trim_diagnosis)"
grep -q 'Recommended next action' <<<"$out" && grep -q '\[✓\] git' <<<"$out" && ok "(d) 권장 내용 줄 없으면 제목만" || fail "(d): $out"
if [[ -f "$CORE/scripts/check-purity.sh" ]]; then
  OUT="$(bash "$CORE/scripts/check-purity.sh" "$FORCE_LIB" 2>&1)"; grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성: $(head -2 <<<"$OUT")"
fi

echo "── [T6·T7] 훅의 전체 진단은 안내문 없이, 전환은 그대로 ──"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-diet.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
P="$WORK/p"; mkdir -p "$P/scv/raw" "$P/scv/conversations"
hook() { ( cd "$P" && printf '{"prompt":"안녕","session_id":"%s"}' "$1" | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/gs" bash "$PROMPT_HOOK" 2>/dev/null ); }
O1="$(hook S1)"; PRE="$(printf '%s\n' "$O1" | awk '/^\[SCV preflight\]/{f=1} f')"
grep -q 'Current project diagnosis' <<<"$PRE" && ok "첫 턴: 전체 진단" || fail "첫 턴에 진단 없음"
grep -q 'Dependency check' <<<"$PRE" && grep -q 'scv/raw\|scv/archive\|hydrate' <<<"$PRE" && ok "진단 본문 있음" || fail "진단 본문 없음"
grep -q 'Recommended next action' <<<"$PRE" && ok "권장 행동 제목 있음" || fail "권장 행동 제목 없음"
! grep -q 'Learn more' <<<"$PRE" && ok "Learn more 없음" || fail "Learn more 있음"
! grep -q 'hydrate.sh" init' <<<"$PRE" && ok "hydrate 명령 줄 없음" || fail "hydrate 명령 줄 있음"
# 경로 길이에 흔들리지 않게 절대 경로 토큰을 모두 빼고 잰다 (CI 러너의 긴 경로·macOS 의 /private 해석 경로가 31B 를 넘겼다).
n="$(printf '%s' "$PRE" | sed -E 's#/[^[:space:])"]+##g' | wc -c | tr -d ' ')"; (( n <= 2000 )) && ok "preflight 블록 ${n}B ≤ 2000B (경로 제외)" || fail "preflight 블록 ${n}B > 2000B"
D="$( cd "$P" && bash "$HELP_SH" 2>/dev/null )"; grep -q 'Learn more' <<<"$D" && grep -q 'hydrate.sh" init' <<<"$D" && ok "직접 help.sh 는 안내문 그대로" || fail "직접 help.sh 에서 안내문이 사라짐"
O2="$(hook S1)"; grep -q '진단 변동 없음' <<<"$O2" && ! grep -q 'Current project diagnosis' <<<"$O2" && ok "둘째 턴: 한 줄" || fail "둘째 턴: $(printf '%s' "$O2" | tail -3)"
printf 'x\n' > "$P/scv/raw/new.md"; O3="$(hook S1)"; grep -q 'Current project diagnosis' <<<"$O3" && ok "진단 바뀌면 다시 전체" || fail "변동 뒤에도 한 줄"

echo; echo "test-help-router-diet: pass=$PASS fail=$FAIL"
(( FAIL == 0 ))
