#!/usr/bin/env bash
# test-turn-check-fast-end.sh — 큰 상태에서도 턴 끝 확인 · 쓰기 전 확인이 제한 시간 안에 끝나고 판정이 그대로인지 본다
# (계획 20261119-wookiya1364-turn-check-fast-end · TESTS.md T1 ~ T7 · T5a).
#
# 한 긴 세션에서 '쓴 파일 목록'이 44만 줄로 불고 비교가 줄마다 목록 전체를 훑어, 종료 훅이 매번 60초 한도에 끊겼다.
# 여기서는 합성 자료(다른 프로젝트 이름 · 경로 없음)로 그 크기를 만든다. 벽시계 한도를 보므로 혼자 돈다:
# scv-test: serial
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TC="$CORE/scripts/turn-check.sh"
PL="$CORE/scripts/plan-link.sh"
# shellcheck source=/dev/null
source "$CORE/scripts/lib/turn-check.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export SCV_TODAY=2026-11-19 LC_ALL=C
unset PROMOTE_DIR ARCHIVE_DIR SCV_JOURNAL_DIR SCV_WORKSPACE_REPOS SCV_TURN_PLAN_CHECK SCV_TURN_CHECK_BUDGET 2>/dev/null || true
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

# @effect now_ms
# 이유: 시계를 읽는다(밀리초)
now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'; }

# ---------- T1 · T2 · 사진 비교: 순수부를 큰 입력으로, 기대값은 다른 도구(grep · comm)로 따로 구한다 ----------
seq -f "/r/f%g" 5000 > "$WORK/uniq"
for _ in $(seq 100); do cat "$WORK/uniq"; done > "$WORK/mine"          # 50만 줄, 서로 다른 것 5,000
{ seq -f "/r/f%g" 4001 5000; seq -f "/r/g%g" 1000; } > "$WORK/paths"   # 2,000개 중 1,000개만 목록에 있음
t0=$(now_ms); got="$(scv_tc_mine_only "$(cat "$WORK/paths")" "$(cat "$WORK/mine")")"; ms=$(( $(now_ms) - t0 ))
want="$(grep -Fxf "$WORK/uniq" "$WORK/paths")"
if [[ "$got" == "$want" && "$(printf '%s\n' "$got" | wc -l | tr -d ' ')" == 1000 && $ms -lt 2000 ]]; then ok "T1 목록 50만 줄 · 경로 2,000 → 1,000 남음, ${ms}ms"
else bad "T1 ms=$ms 같음=$([[ "$got" == "$want" ]] && echo 예 || echo 아니오)"; fi

seq -f "src/f%g.ts" 1998 > "$WORK/fp"; printf 'conf/a.toml\nhost/settings.json\nscv/promote/x/PLAN.md\n' >> "$WORK/fp"
t0=$(now_ms); got="$(scv_tc_filter "$(cat "$WORK/fp")" "host/settings.json:conf/*")"; ms=$(( $(now_ms) - t0 ))
want="$(grep -v -e '^conf/' -e '^host/settings\.json$' -e '^scv/' "$WORK/fp")"
if [[ "$got" == "$want" && $ms -lt 2000 ]]; then ok "T2 걸러내기 2,001 → 1,998, ${ms}ms"
else bad "T2 ms=$ms"; fi

for i in $(seq 4000); do printf 'g/f%05d.gz\t%d\n' "$i" "$i"; done > "$WORK/s0"
awk -F'\t' 'NR % 2 { print $1 "\tx"; next } NR <= 3990 { print }' "$WORK/s0" > "$WORK/s1"; printf 'g/new.gz\t1\n' >> "$WORK/s1"
t0=$(now_ms); got="$(scv_tc_diff "$(cat "$WORK/s0")" "$(cat "$WORK/s1")")"; ms=$(( $(now_ms) - t0 ))
want="$(comm -3 "$WORK/s0" <(sort "$WORK/s1") | sed 's/^\t//' | cut -f1 | sort -u)"
if [[ "$got" == "$want" && $ms -lt 2000 ]]; then ok "T1b 사진 비교 4,000줄 → $(printf '%s\n' "$got" | wc -l | tr -d ' ')개 바뀜, ${ms}ms"
else bad "T1b ms=$ms"; fi

# ---------- 저장소 준비 ----------
R="$WORK/repo"
mkdir -p "$R/scv/promote/p1" "$R/src"
cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
printf -- '---\ntitle: 시험 계획\nslug: p1\nstatus: in_progress\n---\n\n# 시험 계획\n\n## Suggested path\n\n1. 하나\n2. 둘\n\n## Links\n' > scv/promote/p1/PLAN.md
printf 'a\n' > src/a.ts
git add -A && git commit -qm init
S=scv/journal/.turn-plan
reset() { git reset -q --hard HEAD; git clean -qfdx; }
start() { printf '%s' "${1:-전사 체력 고쳐}" | bash "$TC" start --session s1; }
tid() { cat "$S/id" 2>/dev/null; }

# ---------- T3 — 같은 파일 50번 써도 목록에는 한 줄 ----------
reset; start
for _ in $(seq 50); do bash "$TC" touch --session s1 --kind write src/a.ts; done
n="$(grep -c 'src/a.ts$' "$S/mine" 2>/dev/null)"; n="${n:-0}"
[[ "$n" == 1 ]] && ok "T3 같은 파일 50번 → 목록 1줄" || bad "T3 줄 수 $n"

# ---------- T4 · T7 — 큰 상태: 시작 뒤 커밋으로 2,000개 바뀜 + 목록 50만 줄 ----------
big_state() {
  reset; start
  ROOT="$(head -n 1 "$S/roots")"
  mkdir -p "$R/gen"
  for i in $(seq 2000); do printf '%s\n' "$i" > "$R/gen/f$i.txt"; done
  git add -A && git commit -qm big
  for _ in $(seq 250); do seq -f "$ROOT/gen/f%g.txt" 2000; done > "$S/mine"
}
big_state
t0=$(now_ms); out="$(bash "$TC" end --session s1)"; ms=$(( $(now_ms) - t0 ))
if grep -qx 'TURN_PLAN: block' <<<"$out" && [[ ! -e "$S/ended" && $ms -lt 10000 ]]; then ok "T4 큰 상태 기록 없음 → block 그대로, ${ms}ms"
else bad "T4 ms=$ms out=$(head -1 <<<"$out")"; fi
big_state
printf 'bash %s progress p1 --step 1 --note x' "$PL" | bash "$TC" receipt --session s1
bash "$PL" progress p1 --step 1 --note "큰 변경" >/dev/null 2>&1
t0=$(now_ms); out="$(bash "$TC" end --session s1)"; ms=$(( $(now_ms) - t0 ))
if grep -qx 'TURN_PLAN: pass' <<<"$out" && [[ -e "$S/ended" && $ms -lt 10000 ]]; then ok "T4b 큰 상태 기록 있음 → pass · 끝 표시, ${ms}ms"
else bad "T4b ms=$ms out=$(head -1 <<<"$out")"; fi

# T7 — 커밋 안 한 2,000개가 바뀐 채로 셸 명령 → 다음 도구 앞 확인(정산)이 1초 안
reset; start
bash "$TC" touch --session s1 --kind shell
mkdir -p "$R/gen"; for i in $(seq 2000); do printf 'c%s\n' "$i" > "$R/gen/f$i.txt"; done   # 앞 시험이 커밋한 내용과 다르게
t0=$(now_ms); bash "$TC" touch --session s1 --kind read; ms=$(( $(now_ms) - t0 ))
n="$(grep -c '/gen/f' "$S/mine" 2>/dev/null)"; n="${n:-0}"
if [[ $ms -lt 1000 && "$n" == 2000 ]]; then ok "T7 바뀐 2,000개 정산 ${ms}ms · 목록 $n 줄"
else bad "T7 ms=$ms 목록=$n"; fi

# ---------- T5 — 시간 예산을 넘으면 통과 + 생략 기록 + 끝 표시 → 다음 말은 새 턴 ----------
reset; start; bash "$TC" touch --session s1 --kind write src/a.ts; printf 'x\n' >> src/a.ts
id0="$(tid)"
out="$(SCV_TURN_CHECK_BUDGET=0 bash "$TC" end --session s1)"
if grep -qx 'TURN_PLAN: pass' <<<"$out" && [[ -e "$S/ended" ]] && grep -q '확인 생략 · 시간 예산 0초' scv/journal/.turn-plan.log 2>/dev/null; then
  start "다음 말"; [[ "$(tid)" != "$id0" ]] && ok "T5 예산 넘음 → pass · 생략 기록 · 다음 말 새 턴" || bad "T5 다음 말이 새 턴이 아님"
else bad "T5 out=$(head -1 <<<"$out")"; fi

# ---------- T5a — 종료 훅이 죽어도 새 턴 · 도중에 온 말은 이어짐 · 막힌 뒤도 이어짐 ----------
reset; start; bash "$TC" touch --session s1 --kind write src/a.ts; id0="$(tid)"
bash "$TC" stop-begin --session s1                    # (가) 판정 전에 끊김
start "끊긴 뒤 말"; ga=$([[ "$(tid)" != "$id0" && ! -s "$S/mine" ]] && echo 1 || echo 0)
reset; start; bash "$TC" touch --session s1 --kind write src/a.ts; id0="$(tid)"
start "일하는 중 온 말"                                # (나) 종료 훅 없이
na=$([[ "$(tid)" == "$id0" ]] && grep -q '(도중에 온 말) 일하는 중 온 말' "$S/req" && echo 1 || echo 0)
reset; start; bash "$TC" touch --session s1 --kind write src/a.ts; printf 'y\n' >> src/a.ts; id0="$(tid)"
bash "$TC" stop-begin --session s1; v="$(bash "$TC" end --session s1 | sed -n 's/^TURN_PLAN: //p')"   # (다) 막힘
start "막힌 뒤 말"; da=$([[ "$v" == block && "$(tid)" == "$id0" ]] && echo 1 || echo 0)
if [[ "$ga$na$da" == 111 ]]; then ok "T5a 끊김 → 새 턴 · 도중 말 → 이어짐 · 막힘 뒤 → 이어짐"
else bad "T5a 가=$ga 나=$na 다=$da"; fi

exit "$fail"
