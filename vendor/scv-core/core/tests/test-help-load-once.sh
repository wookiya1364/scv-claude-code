#!/usr/bin/env bash
# test-help-load-once.sh — "규약은 세션당 한 번" 의 상태 표식과 훅·스크립트 연동 검사 (v0.49.0+).
#
# 왜 있나: 규약을 다시 읽을 시점을 모델이 아니라 훅 상태로 정한다는 약속은, 상태 전이가 기계로
# 검증될 때만 믿을 수 있다. 여기서 순수부의 전이(새 세션·같은 세션·reset·N턴·mark)와 효과부
# (파일 왕복·실패 시 이전 동작), 훅 두 개와 help.sh 의 PROTOCOL 줄, 그리고 10턴 시뮬레이션을 본다.
#
# Covers TESTS.md T1·T2·T3·T4·T5·T6(일부) of 20260914-wookiya1364-help-load-once.
# Run: bash core/tests/test-help-load-once.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-help-load-once: payload not found from $HERE" >&2; exit 1; }
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  – SKIP: $1"; SKIP=$((SKIP + 1)); }
US=$'\x1f'
LIB="$CORE/scripts/lib/help-state.sh"; STATE_SH="$CORE/scripts/help-state.sh"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"; START_HOOK="$CORE/template/hooks/on-session-start.sh"
HELP_SH="$CORE/scripts/help.sh"
[[ -f "$LIB" ]] || { echo "lib missing: $LIB" >&2; exit 1; }
source "$LIB"
f() {  # <상태> <n> → n번째 필드 (BSD awk 는 -F 의 \x1f 이스케이프를 모른다 — 셸로 자른다)
  local IFS="$US" a; read -r -a a <<<"$1"; printf '%s' "${a[$(( $2 - 1 ))]:-}"; }

echo "── [T1] 순수부 — 파싱·되돌림·진단 판정·렌더 ──"
st="$(scv_hstate_parse '{{broken')"; [[ "$(f "$st" 2)" == "0" && -z "$(f "$st" 1)" ]] && ok "깨진 JSON → 기본값" || fail "기본값 아님: $st"
st="$(scv_hstate_parse '{"session":"A","protocol":1,"turn":4,"diag":"abc","diag_at":"10:00"}')"
[[ "$(f "$st" 1)" == "A" && "$(f "$st" 2)" == "1" && "$(f "$st" 3)" == "4" ]] && ok "정상 JSON 파싱" || fail "파싱 실패: $st"
r="$(scv_hstate_reload "$st" "B" prompt 10)"; [[ "$(f "$r" 1)" == "B" && "$(f "$r" 2)" == "0" && "$(f "$r" 3)" == "1" && -z "$(f "$r" 4)" ]] && ok "세션 다름 → protocol=0 · turn=1 · diag 비움" || fail "세션 전환 실패: $r"
r="$(scv_hstate_reload "$st" "A" prompt 10)"; [[ "$(f "$r" 2)" == "1" && "$(f "$r" 3)" == "5" ]] && ok "같은 세션 → loaded 유지 · turn+1" || fail "같은 세션 실패: $r"
r="$(scv_hstate_reload "$(scv_hstate_parse '{"session":"A","protocol":1,"turn":9}')" "A" prompt 10)"; [[ "$(f "$r" 2)" == "0" && "$(f "$r" 3)" == "10" ]] && ok "N=10: 10턴째 → protocol=0" || fail "N턴 재읽기 실패: $r"
r="$(scv_hstate_reload "$(scv_hstate_parse '{"session":"A","protocol":1,"turn":9}')" "A" prompt 0)"; [[ "$(f "$r" 2)" == "1" ]] && ok "N=0: 주기 재읽기 끔" || fail "N=0 실패: $r"
r="$(scv_hstate_reload "$st" "" prompt 10)"; [[ "$(f "$r" 2)" == "0" ]] && ok "세션 번호 없음 → 매 턴 load" || fail "빈 세션 실패: $r"
r="$(scv_hstate_reload "$st" "A" reset 10)"; [[ "$(f "$r" 2)" == "0" && "$(f "$r" 1)" == "A" && "$(f "$r" 3)" == "4" ]] && ok "reset → protocol=0, 세션·turn 유지" || fail "reset 실패: $r"
r="$(scv_hstate_mark "$r")"; [[ "$(f "$r" 2)" == "1" ]] && ok "mark → protocol=1" || fail "mark 실패"
d="$(scv_hstate_diag "$st" "diag text" "11:11")"; [[ "${d%%$US*}" == "full" ]] && ok "첫 진단 → full" || fail "첫 진단 판정: $d"
st2="${d#*$US}"; d2="$(scv_hstate_diag "$st2" "diag text" "11:12")"; [[ "${d2%%$US*}" == "brief" && "$(f "${d2#*$US}" 5)" == "11:11" ]] && ok "같은 진단 → brief, diag_at 유지" || fail "brief 판정: $d2"
d3="$(scv_hstate_diag "$st2" "diag CHANGED" "11:13")"; [[ "${d3%%$US*}" == "full" && "$(f "${d3#*$US}" 5)" == "11:13" ]] && ok "바뀐 진단 → full, 시각 갱신" || fail "변경 판정: $d3"
j="$(scv_hstate_render "$st")"; [[ "$(scv_hstate_parse "$j")" == "$st" ]] && ok "render→parse 항등" || fail "왕복 불일치: $j"
[[ "$(scv_hstate_protocol_line "$st" on)" == "PROTOCOL: loaded" && "$(scv_hstate_protocol_line "$st" off)" == "PROTOCOL: load" ]] && ok "PROTOCOL 줄 (on/off)" || fail "PROTOCOL 줄"
[[ "$(scv_hstate_switch ' "OFF" ')" == "off" && "$(scv_hstate_switch "")" == "on" ]] && ok "스위치 정규화" || fail "스위치"
if [[ -f "$CORE/scripts/check-purity.sh" ]]; then
  OUT="$(bash "$CORE/scripts/check-purity.sh" "$LIB" 2>&1)"; grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성: $(head -2 <<<"$OUT")"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-load-once.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
mkproj() { local p="$WORK/$1"; mkdir -p "$p/scv/raw"; [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$p/scv/scv_settings.json"; echo "$p"; }
hook() {  # <proj> <session> → 훅 stdout
  ( cd "$1" && printf '{"prompt":"안녕","session_id":"%s"}' "$2" | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/gs" bash "$PROMPT_HOOK" 2>/dev/null )
}
start() { ( cd "$1" && printf '{"source":"%s"}' "$2" | CLAUDE_PLUGIN_ROOT="$CORE" bash "$START_HOOK" >/dev/null 2>&1 ); }
wc_line() { ( cd "$1" && bash "$HELP_SH" --with-context 2>/dev/null | grep '^PROTOCOL:' ); }

echo "── [T2] 새 세션 → load · mark → loaded · 다른 세션 → load ──"
P=$(mkproj t2)
hook "$P" A >/dev/null; [[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "새 세션 첫 턴: load" || fail "첫 턴: $(wc_line "$P")"
( cd "$P" && bash "$STATE_SH" mark >/dev/null ); [[ "$(wc_line "$P")" == "PROTOCOL: loaded" ]] && ok "mark 뒤: loaded" || fail "mark 뒤: $(wc_line "$P")"
hook "$P" A >/dev/null; [[ "$(wc_line "$P")" == "PROTOCOL: loaded" ]] && ok "같은 세션 다음 턴: loaded" || fail "같은 세션: $(wc_line "$P")"
hook "$P" B >/dev/null; [[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "세션 B: load" || fail "세션 B: $(wc_line "$P")"
P2=$(mkproj t2b); hook "$P2" A >/dev/null; hook "$P2" A >/dev/null; [[ "$(wc_line "$P2")" == "PROTOCOL: load" ]] && ok "mark 없이는 계속 load" || fail "mark 없이 loaded"

echo "── [T3] 압축·/clear·재개 → 다시 load ──"
for src in compact clear resume; do
  P=$(mkproj "t3$src"); hook "$P" A >/dev/null; ( cd "$P" && bash "$STATE_SH" mark >/dev/null ); start "$P" "$src"
  [[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "$src → load" || fail "$src 뒤 $(wc_line "$P")"
  sess="$( cd "$P" && bash "$STATE_SH" read | grep -o '"session":"[^"]*"' )"; [[ "$sess" == '"session":"A"' ]] && ok "$src: 세션 유지" || fail "$src: 세션 $sess"
done

echo "── [T4] 진단 — 첫 턴 전체 · 변동 없으면 한 줄 · 바뀌면 전체 ──"
P=$(mkproj t4); O1="$(hook "$P" A)"; grep -q "Current project diagnosis" <<<"$O1" && ok "1턴: 전체 진단" || fail "1턴 전체 진단 없음"
O2="$(hook "$P" A)"; grep -q "진단 변동 없음" <<<"$O2" && ! grep -q "Dependency check" <<<"$O2" && ok "2턴: 한 줄 요약, 전체 없음" || fail "2턴: $(grep -c . <<<"$O2") 줄"
grep -q "SCV: 이 턴의 첫 행동" <<<"$O2" && ok "2턴: 라우팅 지시는 그대로" || fail "2턴 라우팅 지시 없음"
touch "$P/scv/raw/new.md"; O3="$(hook "$P" A)"; grep -q "Current project diagnosis" <<<"$O3" && ok "3턴(raw 추가): 전체 다시" || fail "변경 후 전체 진단 없음"

echo "── [T5] 실패는 이전 동작으로 ──"
P=$(mkproj t5); mkdir -p "$P/scv/journal/.help-state"   # 디렉터리 → 쓰기 불가
O="$(hook "$P" A)"; rc=$?; [[ $rc -eq 0 ]] && grep -q "Current project diagnosis" <<<"$O" && ok "쓰기 불가: exit 0 · 전체 진단" || fail "쓰기 불가 처리 (rc=$rc)"
[[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "쓰기 불가: load" || fail "쓰기 불가: $(wc_line "$P")"
P=$(mkproj t5b); mkdir -p "$P/scv/journal"; printf '{{{not json' > "$P/scv/journal/.help-state"
[[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "깨진 표식: load" || fail "깨진 표식: $(wc_line "$P")"
P=$(mkproj t5c); O="$( cd "$P" && printf '{"prompt":"안녕"}' | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/gs" bash "$PROMPT_HOOK" 2>/dev/null )"
grep -q "SCV: 이 턴의 첫 행동" <<<"$O" && [[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "session_id 없음: 지시 유지 · 매 턴 load" || fail "session_id 없음 처리"
P=$(mkproj t5d '{"SCV_HELP_LOAD_ONCE":"off"}'); hook "$P" A >/dev/null; ( cd "$P" && bash "$STATE_SH" mark >/dev/null ); [[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "스위치 off: 항상 load" || fail "스위치 off 무시"
O="$(hook "$P" A)"; grep -q "Current project diagnosis" <<<"$O" && ok "스위치 off: 진단 매 턴 전체" || fail "스위치 off 진단 요약됨"

echo "── [T6] 10턴 시뮬레이션 — load 2회(첫 턴 + compact 뒤), N=10 이면 10턴째 +1 ──"
P=$(mkproj t6 '{"SCV_HELP_RELOAD_EVERY":"0"}'); loads=0
for i in $(seq 1 10); do hook "$P" S >/dev/null; [[ $i -eq 5 ]] && start "$P" compact; if [[ "$(wc_line "$P")" == "PROTOCOL: load" ]]; then loads=$((loads+1)); ( cd "$P" && bash "$STATE_SH" mark >/dev/null ); fi; done
[[ $loads -eq 2 ]] && ok "N=0: load 2회 (첫 턴 · compact 뒤)" || fail "N=0: load ${loads}회"
P=$(mkproj t6b); loads=0
for i in $(seq 1 10); do hook "$P" S >/dev/null; if [[ "$(wc_line "$P")" == "PROTOCOL: load" ]]; then loads=$((loads+1)); ( cd "$P" && bash "$STATE_SH" mark >/dev/null ); fi; done
[[ $loads -eq 2 ]] && ok "기본 N=10: load 2회 (첫 턴 · 10턴째)" || fail "N=10: load ${loads}회"
echo "─────────────────────────────"; echo "  통과 $PASS · 실패 $FAIL · 생략 $SKIP"; [[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
