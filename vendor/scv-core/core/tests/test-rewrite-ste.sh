#!/usr/bin/env bash
# test-rewrite-ste.sh — 0.84.0 다시 쓴 요청 낱말 목록(contracts/rewrite-ste.md): korean 이면 help 가이드 안내 끝에
# 규약 지문마다 한 번 전문을 싣고, 다른 언어 · off 이면 싣지 않는다.
# 계획: scv/archive/20261108-wookiya1364-rewrite-ste-list/TESTS.md
# S1 korean 첫 안내에 전문 · S2 같은 지문 두 번째는 한 줄 · S3 english 없음 · S4 off 없음 · S5 절차 문서 연결 · S6 구역 고르기 순수부.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELP="$CORE/scripts/help.sh"; LIB="$CORE/scripts/lib/model-prompting.sh"; FIX="$CORE/tests/fixtures/model-prompting"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-ste.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\n' "$WORK/guides"; } > "$WORK/profile.env"

new_repo() {  # <이름> <설정 JSON> → 저장소 경로 (세션 s1 의 help 표식 포함)
  local d="$WORK/$1"; mkdir -p "$d/scv/journal"
  printf '{"session":"s1","protocol":1,"turn":3,"diag":"","diag_at":"","nonce":"abcd1234"}\n' > "$d/scv/journal/.help-state"
  printf '%s\n' "$2" > "$d/scv/scv_settings.json"
  printf '%s' "$d"
}
help_wc() { (cd "$1" && SCV_HOST_PROFILE="$WORK/profile.env" SCV_TODAY=2026-09-27 bash "$HELP" --with-context --model vendor-model-a 2>/dev/null); }

# S1 · S2 — korean: 첫 안내는 전문, 같은 규약 지문의 두 번째 안내는 한 줄
R="$(new_repo ko '{"SCV_LANG":"korean"}')"
o1="$(help_wc "$R")"; o2="$(help_wc "$R")"
grep -qx 'STE:' <<<"$o1" && grep -q '^R1 문장 하나에 지시 하나' <<<"$o1" && grep -q '^R15 ' <<<"$o1" && grep -q '^금지 낱말: ' <<<"$o1" \
  && ok "S1 korean 첫 안내에 목록 전문" || bad "S1 [$(grep -A2 '^STE' <<<"$o1")]"
grep -q '^STE: (이 세션에 이미 실음' <<<"$o2" && ! grep -q '^R1 ' <<<"$o2" \
  && ok "S2 같은 지문 두 번째는 한 줄" || bad "S2 [$(grep -A1 '^STE' <<<"$o2")]"

# S3 — english: 구역이 없으니 싣지 않는다(지금과 같은 출력)
R="$(new_repo en '{"SCV_LANG":"english"}')"
o="$(help_wc "$R")"
! grep -q '^STE' <<<"$o" && grep -q '^GUIDE' <<<"$o" && ok "S3 english 는 싣지 않음" || bad "S3 [$(grep '^STE' <<<"$o")]"

# S4 — SCV_REWRITE_STE=off: 싣지 않는다
R="$(new_repo off '{"SCV_LANG":"korean","SCV_REWRITE_STE":"off"}')"
o="$(help_wc "$R")"
! grep -q '^STE' <<<"$o" && ok "S4 off 는 싣지 않음" || bad "S4 [$(grep '^STE' <<<"$o")]"

# S5 — 다시 쓰기 절차가 목록을 가리킨다 · 설정 예시에 스위치
grep -q 'When help printed `STE:`, write the rewrite by that word list' "$CORE/protocols/help/prompt-refine.md" \
  && grep -q '"SCV_REWRITE_STE"' "$CORE/template/scv/scv_settings.example.json" \
  && ok "S5 절차 문서 · 설정 예시" || bad "S5 prompt-refine 2 또는 설정 예시에 없음"

# S6 — 구역 고르기 순수부: 종류를 받고, 기본은 principle
out="$(bash -c 'source "$1"
  printf "%s|%s|%s\n" "$(scv_mp_principle_pick $'"'"'<!-- ste:korean -->\nKO\n<!-- ste:english -->\nEN'"'"' korean ste)" \
    "$(scv_mp_principle_pick $'"'"'<!-- principle:korean -->\nP'"'"' korean)" "$(scv_mp_principle_pick $'"'"'<!-- principle:korean -->\nP'"'"' korean ste)"' _ "$LIB")"
[[ "$out" == "KO|P|" ]] && ok "S6 구역 고르기(종류 ste · 기본 principle)" || bad "S6 [$out]"

if (( fail )); then echo "── test-rewrite-ste: FAIL"; exit 1; fi
echo "── test-rewrite-ste: 6 passed"
