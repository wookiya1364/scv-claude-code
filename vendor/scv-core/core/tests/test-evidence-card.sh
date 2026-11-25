#!/usr/bin/env bash
# test-evidence-card.sh — 숫자 결과를 막대 그림으로(계획 20261125-wookiya1364-visible-evidence-background · TESTS.md T5 · T6).
#
# 단계가 끝났다는 증거는 눈에 보이는 것이어야 한다. 숫자뿐인 결과를 그림 파일로 만드는 명령이 그림을 제대로 쓰는지,
# 같은 입력이면 같은 파일인지, 프로젝트 밖이나 심볼릭 링크 자리에는 쓰지 않는지 본다.
#
# Run: bash core/tests/test-evidence-card.sh
set -uo pipefail
CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"; CARD="$CORE/scripts/evidence-card.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-card.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
P="$WORK/proj"; mkdir -p "$P"

# ---------- T5 — 막대 그림을 만든다 ----------
( cd "$P" && bash "$CARD" card --out ev/a.svg --title "시험 결과" "통과=124" "실패=2" >/dev/null 2>&1 ); rc=$?
( cd "$P" && bash "$CARD" card --out ev/b.svg --title "시험 결과" "통과=124" "실패=2" >/dev/null 2>&1 )
f="$P/ev/a.svg"; first="$(head -c 4 "$f" 2>/dev/null)"; n=0
for w in "시험 결과" "통과" "실패" "124"; do grep -qF -- "$w" "$f" 2>/dev/null && n=$((n + 1)); done
if [[ "$rc" == 0 && "$first" == "$(printf '\x3csvg')" && "$n" == 4 ]] && cmp -s "$P/ev/a.svg" "$P/ev/b.svg"; then ok "T5 그림 파일이 생기고 제목 · 이름 · 값이 들어 있음, 같은 입력이면 같은 파일"
else bad "T5 종료=$rc 첫글자=[$first] 낱말=$n/4"; fi

# 꺾쇠와 & 는 글자로 바꿔 적는다 — 깨진 그림이 되지 않게
( cd "$P" && bash "$CARD" card --out ev/c.svg --title "전 & 뒤" "a=1" >/dev/null 2>&1 )
grep -qF '전 &amp; 뒤' "$P/ev/c.svg" 2>/dev/null && ok "T5 제목의 & 를 글자로 바꿔 적음" || bad "T5 & 바꾸기"

# ---------- T6 — 그림은 프로젝트 안에만 쓴다 ----------
mkdir -p "$WORK/outside"; ln -s "$WORK/outside" "$P/link"
r1=0; ( cd "$P" && bash "$CARD" card --out "$WORK/outside/x.svg" --title t "a=1" >/dev/null 2>&1 ) || r1=$?
r2=0; ( cd "$P" && bash "$CARD" card --out ../outside/y.svg --title t "a=1" >/dev/null 2>&1 ) || r2=$?
r3=0; ( cd "$P" && bash "$CARD" card --out link/z.svg --title t "a=1" >/dev/null 2>&1 ) || r3=$?
r4=0; ( cd "$P" && bash "$CARD" card --out ev/n.svg --title t "메모=없음" >/dev/null 2>&1 ) || r4=$?
left="$(ls "$WORK/outside" 2>/dev/null | grep -c . || true)"
if [[ "$r1" == 2 && "$r2" == 2 && "$r3" == 2 && "$r4" == 2 && "$left" == 0 && ! -e "$P/ev/n.svg" ]]; then ok "T6 프로젝트 밖 · 위로 올라가는 경로 · 링크 자리 · 숫자 없는 입력은 쓰지 않고 종료 코드 2"
else bad "T6 종료=$r1,$r2,$r3,$r4 밖에 생긴 파일=$left"; fi

# ---------- 순수 판정 ----------
# shellcheck source=/dev/null
source "$CORE/scripts/lib/evidence-card.sh"
rows="$(scv_card_rows $'전=6.2\n뒤=4.3' 200 | tr '\t' '|' | tr '\n' ' ')"
[[ "$rows" == "전|6.2|200 뒤|4.3|138" ]] && ok "막대 길이는 값에 비례(소수 포함)" || bad "길이 [$rows]"

exit "$fail"
