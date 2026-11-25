#!/usr/bin/env bash
# test-retired-coach.sh — 걷어낸 기능이 본체에 남지 않았는지 본다(2026-11-25 의 걷어내기 계획 · TESTS.md T1 ~ T4).
#
# 지난 세션을 돌아보는 코칭 보고서 기능을 걷어냈다(사용자 판단 2026-11-25: 실익 없음). 그 이름이 스크립트 · 규약 · 훅 · 설정 · 문서에
# 남지 않았는지, 액션 목록이 22개인지, 매 턴 훅과 세션 시작 훅이 그 폴더를 만들거나 안내하지 않는지 본다.
# 이름은 조각으로 이어 붙여 적는다 — 이 파일 자신이 검색에 걸리지 않게.
#
# Run: bash core/tests/test-retired-coach.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"; ROOT="$( cd "$CORE/.." && pwd )"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
NAME="dre""ams"; UPPER="SCV_DRE""AMS"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-nd.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

# ---------- T1 — 본체에 그 이름이 없다 ----------
# 코덱스 사본에는 core/ 만 있다 — 문서와 README 는 있을 때만 본다.
where=("$CORE"); for f in "$ROOT/docs" "$ROOT/README.md" "$ROOT/README.ko.md" "$ROOT/README.ja.md"; do [[ -e "$f" ]] && where+=("$f"); done
hits="$(grep -rIil -e "$NAME" "${where[@]}" 2>/dev/null | grep -v '/node_modules/' | LC_ALL=C sort | head -20)"
if [[ -z "$hits" ]]; then ok "T1 본체 · 문서에 그 이름이 든 파일 0개"; else bad "T1 남은 파일: $(printf '%s' "$hits" | tr '\n' ' ')"; fi

# ---------- T2 — 액션 목록이 22개이고 그 액션이 없다 ----------
n="$(jq -r '.actions | length' "$CORE/actions.json" 2>/dev/null)"; has="$(jq -r --arg n "$NAME" '[.actions[] | select(.id == $n)] | length' "$CORE/actions.json" 2>/dev/null)"
re_has=no; grep -E '^ACTIONS_RE=' "$CORE/template/hooks/guard.sh" | grep -q -- "$NAME" && re_has=yes
if [[ "$n" == 22 && "$has" == 0 && "$re_has" == no ]]; then ok "T2 액션 22개 · 가드의 액션 이름 목록에도 없음"; else bad "T2 액션=$n 그액션=$has 가드=$re_has"; fi

# ---------- T3 — 매 턴 훅이 그 폴더를 만들지 않는다 ----------
P="$WORK/t3"; mkdir -p "$P/scv/journal"; printf '{"SCV_LANG":"korean"}\n' > "$P/scv/scv_settings.json"
( cd "$P" && jq -cn '{prompt:"로그인 화면의 색을 바꿔 줘",session_id:"s1"}' | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/gs" bash "$CORE/template/hooks/on-user-prompt.sh" >/dev/null 2>&1 ); rc=$?
if [[ "$rc" == 0 && ! -e "$P/scv/$NAME" ]]; then ok "T3 매 턴 훅 뒤에 그 폴더가 생기지 않음(종료 코드 0)"; else bad "T3 종료=$rc 폴더=$([[ -e "$P/scv/$NAME" ]] && echo 있음 || echo 없음)"; fi

# ---------- T4 — 세션 시작 훅에 안내가 없고 폴더도 만들지 않는다 ----------
P="$WORK/t4"; mkdir -p "$P/scv/journal"; printf '{"SCV_LANG":"korean"}\n' > "$P/scv/scv_settings.json"
out="$( cd "$P" && jq -cn '{source:"compact",session_id:"s1"}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$CORE/template/hooks/on-session-start.sh" 2>/dev/null )"; rc=$?
if [[ "$rc" == 0 && ! -e "$P/scv/$NAME" ]] && ! grep -qi -e "$NAME" -e "$UPPER" <<<"$out"; then ok "T4 세션 시작 훅: 안내 없음 · 폴더 없음"; else bad "T4 종료=$rc"; fi

exit "$fail"
