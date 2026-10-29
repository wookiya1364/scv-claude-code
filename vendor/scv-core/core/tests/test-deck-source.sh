#!/usr/bin/env bash
# test-deck-source.sh — deck 엔진(DeckUI) 폴더 고르기(lib/deck-source.sh)와, 래퍼 설정 SCV_DECKUI_DIR 를 읽는 런타임(deck-runtime.sh path).
# T1 설정이 없으면 코어 루트 아래 · T2 코어 루트에 엔진이 없으면 설정 자리 · T3 잘못된 설정은 막는다.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$(cd "$HERE/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/scv-deck-source.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=../scripts/lib/deck-source.sh
source "$CORE/scripts/lib/deck-source.sh"

echo "── [T1–T3] 순수부: scv_deck_source_dir ──"
[[ "$(scv_deck_source_dir /r "" yes)" == /r/DeckUI ]] && ok "설정 없음 · 엔진 있음 → 코어 루트 아래" || fail "T1 a"
[[ "$(scv_deck_source_dir /r/ "" no)" == /r/DeckUI ]] && ok "설정 없음 · 엔진 없음 → 코어 루트 아래(없다는 오류는 런타임 몫)" || fail "T1 b"
[[ "$(scv_deck_source_dir /r "vendor/scv-core/core/DeckUI" yes)" == /r/DeckUI ]] && ok "코어 루트에 엔진이 있으면 설정보다 앞선다(코어 · codex 동작 그대로)" || fail "T1 c"
[[ "$(scv_deck_source_dir /r "vendor/scv-core/core/DeckUI/" no)" == /r/vendor/scv-core/core/DeckUI ]] && ok "코어 루트에 엔진이 없으면 설정 자리(끝 / 정리)" || fail "T2 a"
for bad in /abs/DeckUI .. ../x a/../b a/..; do
  out="$(scv_deck_source_dir /r "$bad" no)"; rc=$?
  [[ $rc -eq 2 && -z "$out" ]] && ok "거절: '$bad' → 2, 출력 없음" || fail "T3 '$bad' rc=$rc out=[$out]"
done
[[ "$(scv_deck_source_dir /r "a..b/DeckUI" no)" == /r/a..b/DeckUI ]] && ok "'..' 가 이름 일부면 조각이 아니다(a..b)" || fail "T3 a..b"

echo "── [T1–T3] 런타임: deck-runtime.sh path 가 고른 엔진으로 캐시 이름을 정한다 ──"
# 가짜 플러그인: 투영된 scripts/ 와, 코어 사본 안 엔진. 코어 루트(scripts/..) 아래에는 엔진이 없다.
mk_plugin() {  # <dir> <profile line or empty>
  local d="$1"; mkdir -p "$d/scripts/lib" "$d/vendor/scv-core/core/DeckUI/src"
  cp "$CORE/scripts/deck-runtime.sh" "$d/scripts/"; cp "$CORE/scripts/lib/host-profile.sh" "$CORE/scripts/lib/deck-source.sh" "$d/scripts/lib/"
  printf '{"name":"deckui-fixture"}\n' > "$d/vendor/scv-core/core/DeckUI/package.json"
  printf 'x\n' > "$d/vendor/scv-core/core/DeckUI/src/a.ts"
  : > "$d/host-profile.env"; [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$d/host-profile.env"
  return 0
}
rt_path() { ( cd "$WORK" && SCV_DECK_CACHE_DIR="$WORK/cache" bash "$1/scripts/deck-runtime.sh" path 2>&1 ); }

P2="$WORK/p2"; mk_plugin "$P2" "SCV_DECKUI_DIR=vendor/scv-core/core/DeckUI"
o="$(rt_path "$P2")"; rc=$?
[[ $rc -eq 0 && "$o" == "$WORK/cache/"*/DeckUI ]] && ok "T2 설정 자리 엔진으로 런타임 경로를 낸다" || fail "T2 runtime rc=$rc [$o]"

P1="$WORK/p1"; mk_plugin "$P1" ""
o="$(rt_path "$P1")"; rc=$?
[[ $rc -ne 0 && "$o" == *"missing or unsafe"*"$P1/DeckUI"* ]] && ok "T1 설정 없고 코어 루트에 엔진 없음 → 코어 루트 아래를 찾다 멈춘다" || fail "T1 runtime rc=$rc [$o]"

P3="$WORK/p3"; mk_plugin "$P3" "SCV_DECKUI_DIR=../outside/DeckUI"
o="$(rt_path "$P3")"; rc=$?
[[ $rc -ne 0 && "$o" == *"SCV_DECKUI_DIR must be a path inside the plugin"* && ! -d "$WORK/cache" ]] \
  && ok "T3 밖으로 나가는 설정 → 이유를 대며 멈추고 캐시를 만들지 않는다" || fail "T3 escape rc=$rc [$o]"

P4="$WORK/p4"; mk_plugin "$P4" "SCV_DECKUI_DIR=vendor/none/DeckUI"
o="$(rt_path "$P4")"; rc=$?
[[ $rc -ne 0 && "$o" == *"missing or unsafe"*"vendor/none/DeckUI"* ]] && ok "T3 없는 폴더 → 그 경로를 대며 멈춘다" || fail "T3 missing rc=$rc [$o]"

P5="$WORK/p5"; mk_plugin "$P5" "SCV_DECKUI_DIR=linked/DeckUI"
mkdir -p "$P5/linked"; ln -s "$P5/vendor/scv-core/core/DeckUI" "$P5/linked/DeckUI"
o="$(rt_path "$P5")"; rc=$?
[[ $rc -ne 0 && "$o" == *"missing or unsafe"* ]] && ok "T3 연결(심볼릭 링크) 폴더 → 멈춘다" || fail "T3 symlink rc=$rc [$o]"

P6="$WORK/p6"; mk_plugin "$P6" "SCV_DECKUI_DIR=vendor/scv-core/core/DeckUI"
mkdir -p "$P6/DeckUI/node_modules/x"   # 예전 작업본에 남은 실행 찌꺼기 — 엔진 파일 없음
o="$(rt_path "$P6")"; rc=$?
o2="$(rt_path "$P2")"
[[ $rc -eq 0 && "$o" == "$o2" ]] && ok "T2 맨 위에 찌꺼기 DeckUI 만 남아 있으면 엔진으로 보지 않고 설정 자리를 쓴다" || fail "T2 leftover rc=$rc [$o] vs [$o2]"

P7="$WORK/p7"; mk_plugin "$P7" "SCV_DECKUI_DIR=vendor/scv-core/core/DeckUI"
mkdir -p "$WORK/outside/scv-core/core"; mv "$P7/vendor/scv-core/core/DeckUI" "$WORK/outside/scv-core/core/"
rm -rf "$P7/vendor"; ln -s "$WORK/outside" "$P7/vendor"
o="$(rt_path "$P7")"; rc=$?
[[ $rc -ne 0 && "$o" == *"resolves outside the Core root"* ]] && ok "T3 중간 폴더가 밖을 가리키는 연결이면 멈춘다" || fail "T3 parent symlink rc=$rc [$o]"

echo "test-deck-source: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
