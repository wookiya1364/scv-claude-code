#!/usr/bin/env bash
# test-pure-bench-c.sh — 재는 명령(계획 20261111-wookiya1364-pure-bench-and-gate)의 시험, 넷 가운데 턴 끝과 훅(S17 · S18).
# 한 파일이던 것을 넷으로 나눴다(계획 20261112-wookiya1364-small-fixes-bundle) — 조각 실행기가 넷을 서로 다른
# 러너에 나눠 함께 돌릴 수 있게. 구간 번호(S1 ~ S23)는 나누기 전 그대로다.
#
# Run: bash core/tests/test-pure-bench-c.sh   (넷 모두: bash core/tests/test-pure-bench.sh)
#
# 시간을 재는 시험이라 다른 시험과 겹쳐 돌면 값이 틀어진다 — 다른 시험이 다 끝난 뒤 혼자 돈다:
# scv-test: serial
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PB="$CORE/scripts/pure-bench.sh"
# shellcheck source=fixtures/pure-bench/common.sh
source "$CORE/tests/fixtures/pure-bench/common.sh"

echo "S17. 턴 끝 — 고친 함수만 (TESTS T14 · T13)"
if ! command -v git >/dev/null 2>&1; then echo "  - SKIP [S17] git 없음"
else
  G="$TMP/proj"; mkdir -p "$G/lib" "$G/scv/core/catalog/pure" "$G/scv/journal" "$G/turn/.turn-plan"
  ( cd "$G" && git init -q . && git symbolic-ref HEAD refs/heads/main )
  cat > "$G/lib/t.sh" <<'LIB'
t_each() { local l; while IFS= read -r l; do printf '%s\n' "$l" | tr 'a-z' 'A-Z'; done <<< "$1"; }
t_once() { printf '%s\n' "$1" | tr 'a-z' 'A-Z'; }
t_up()   { printf '%s\n' "$1" | tr 'a-z' 'A-Z'; }
t_rev()  { printf '%s\n' "$1" | tr 'A-Z' 'a-z'; }
t_both() { t_rev "$(t_up "$1")"; }
LIB
  : > "$G/scv/core/catalog/pure/INDEX.md"
  for f in t_each t_once t_up t_rev t_both; do printf '### %s\n- 역할: 시험용\n- 위치: lib/t.sh · @deterministic · sh\n- 예: `$\x27a\\nb\x27 → $\x27A\\nB\x27`\n\n' "$f"; done > "$G/scv/core/catalog/pure/a.md"
  echo "읽어 보세요" > "$G/README.md"
  ( cd "$G" && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -q -m base && git checkout -q -b work )
  pbg() { ( cd "$G" && SCV_PB_GPU_TOOL=none "$BASH" "$PB" "$@" ); }
  first() { local o; o="$(pbg "$@")"; printf '%s' "${o%%$'\n'*}"; }   # 첫 줄만 — 출력을 끝까지 받은 뒤 자른다
  # 사전 함수를 고치지 않은 턴
  echo "바뀜" >> "$G/README.md"; printf 'README.md\n' > "$G/turn/.turn-plan/changed"
  o="$(pbg turn-end --dir "$G/turn")"
  eq "S17 a turn that touched no pure function: nothing is measured" "PURE_BENCH: pass / PURE_BENCH_RUNS: 0" "$(tr '\n' '/' <<<"$o" | sed 's#/# / #; s#/$##')"
  : > "$G/turn/.turn-plan/changed"
  eq "S17 a turn that changed nothing" "PURE_BENCH: pass" "$(first turn-end --dir "$G/turn")"
  # 함수 둘을 고친 턴 — 그 둘만 잰다(둘 다 답은 그대로)
  python3 - "$G/lib/t.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("""t_once() { printf '%s\\n' "$1" | tr 'a-z' 'A-Z'; }""", """t_once() { local l; while IFS= read -r l; do printf '%s\\n' "$l" | tr 'a-z' 'A-Z'; done <<< "$1"; }""")
s = s.replace("""t_each() { local l; while""", """t_each() { local l x=1; while""")
open(p, "w").write(s)
PY
  printf 'lib/t.sh\nREADME.md\n' > "$G/turn/.turn-plan/changed"
  o="$(pbg turn-end --dir "$G/turn")"
  eq "S17 two functions changed: those two are measured" "PURE_BENCH_RUNS: 2" "$(grep '^PURE_BENCH_RUNS' <<<"$o")"
  eq "S17 the slowed one stops the turn" "PURE_BENCH: block" "$(head -1 <<<"$o")"
  r="$(sed -n 's/^PURE_BENCH_REASON: //p' <<<"$o")"
  [[ "$r" == *"t_once — 시간 "*"배 · 다른 프로그램을 부른 횟수 1번 → 50번"* && "$r" == *"[재는 검사] 함수 이름 —"* && "$r" != *"t_each —"* ]] && ok "OK [S17] the reason names the function, its real numbers and how to ask" || fail "[S17] $r"
  eq "S17 what went over waits for the user's answer" "t_once" "$(cut -f1 "$G/scv/journal/.pure-bench-pending")"
  # 사용자가 "고침"을 고르면 받아들인 것이 아니다 → 다시 막는다. "이대로"를 고르면 지나간다.
  pbg accept --question "[재는 검사] t_once — 시간이 늘었습니다" --answer "고침 (추천)" >/dev/null
  eq "S17 'fix it' is not an acceptance" "PURE_BENCH: block" "$(first turn-end --dir "$G/turn")"
  eq "S17 after two stops the turn is let through, and that is recorded" "PURE_BENCH: pass-unanswered" "$(first turn-end --dir "$G/turn")"
  grep -q 't_once' "$G/scv/journal/.pure-bench.log" && ok "OK [S17] the log names what was left over the limit" || fail "[S17] no log line"
  printf '0' > "$G/turn/.turn-plan/pb-blocks"
  a="$(pbg accept --question "[재는 검사] t_once — 시간이 늘었습니다" --answer "이대로 둠")"
  [[ "$a" == "PURE_BENCH_ACCEPTED: t_once"* ]] && ok "OK [S17] '이대로' is recorded as accepted" || fail "[S17] $a"
  eq "S17 an accepted change passes" "PURE_BENCH: pass" "$(first turn-end --dir "$G/turn")"
  # 엮은 함수: 부품을 고치면 그것을 부르는 엮은 함수도 함께 잰다
  ( cd "$G" && git checkout -q lib/t.sh ) ; python3 - "$G/lib/t.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("""t_rev()  { printf '%s\\n' "$1" | tr 'A-Z' 'a-z'; }""", """t_rev()  { local x=1; printf '%s\\n' "$1" | tr 'A-Z' 'a-z'; }""")
open(p, "w").write(s)
PY
  o="$(pbg turn-end --dir "$G/turn")"
  eq "S17 a changed part brings its composed caller along (t_rev + t_both)" "PURE_BENCH_RUNS: 2" "$(grep '^PURE_BENCH_RUNS' <<<"$o")"
  # 끄기
  printf '{"SCV_PURE_BENCH": "off"}\n' > "$G/scv/scv_settings.json"
  eq "S17 switched off" "PURE_BENCH: off" "$(first turn-end --dir "$G/turn")"
  rm -f "$G/scv/scv_settings.json"
  # 계획 끝: 꼼꼼히
  ( cd "$G" && git checkout -q lib/t.sh ); rm -f "$G/scv/journal/.pure-bench-accepted"
  python3 - "$G/lib/t.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("""t_once() { printf '%s\\n' "$1" | tr 'a-z' 'A-Z'; }""", """t_once() { local l; while IFS= read -r l; do printf '%s\\n' "$l" | tr 'a-z' 'A-Z'; done <<< "$1"; }""")
open(p, "w").write(s)
PY
  pbg plan-end > "$TMP/planend.md"; st=$?
  eq "S17 plan end: a slowed function fails the full check" 1 "$st"
  grep -q '쌍 6 · 입력 4배 포함' "$TMP/planend.md" && grep -q '^| t_once | 한도 넘음 |' "$TMP/planend.md" && grep -q '^견주는 기준: 이 일을 시작하기 전의 코드' "$TMP/planend.md" && ok "OK [S17] six pairs, 4x input, against the code before this work" || fail "[S17] $(head -3 "$TMP/planend.md")"
  ( cd "$G" && git checkout -q lib/t.sh )
  eq "S17 plan end with nothing changed: exit 0" 0 "$(pbg plan-end >/dev/null; echo $?)"
fi

echo "S18. 훅과 턴 검사에 이어졌는가"
grep -q 'pure-bench.sh" turn-end --dir' "$CORE/template/hooks/on-stop.sh" 2>/dev/null || grep -q 'turn-end --dir "\$_scv_tdir"' "$CORE/template/hooks/on-stop.sh" && ok "OK [S18] the stop hook runs the turn-end check" || fail "[S18] on-stop.sh does not call turn-end"
a="$(grep -n '/turn plan check' "$CORE/template/hooks/on-stop.sh" | head -1 | cut -d: -f1)"; b="$(grep -n 'turn-end --dir' "$CORE/template/hooks/on-stop.sh" | head -1 | cut -d: -f1)"
[[ -n "$a" && -n "$b" && "$b" -gt "$a" ]] && ok "OK [S18] after the plan-record check" || fail "[S18] a=$a b=$b"
grep -q '> "\$S/changed"' "$CORE/scripts/turn-check.sh" && ok "OK [S18] the turn check leaves the list of changed files" || fail "[S18] no changed list"
HOOK="$CORE/template/hooks/on-stop.sh"
# 값싼 앞 검사: 사전 함수가 사는 파일을 고치지 않은 턴은 재는 명령을 띄우지도 않는다
if [[ -d "$CORE/../scv/core/catalog/pure" ]]; then
  pre() { awk '{ print "- 위치: " $0 " · "; if (sub(/^core\//, "")) print "- 위치: " $0 " · " }' "$1" | grep -q -F -f - "$CORE"/../scv/core/catalog/pure/*.md; }
  printf 'README.md\ncore/tests/test-x.sh\n' > "$TMP/ch1"; printf 'README.md\ncore/scripts/lib/turn-check.sh\n' > "$TMP/ch2"
  pre "$TMP/ch1"; r1=$?; pre "$TMP/ch2"; r2=$?
  eq "S18 the cheap check: no pure-function file → not started, one → started" "1 0" "$r1 $r2"
  grep -q 'grep -q -F -f - "\$_scv_pb_cat"' "$HOOK" && ok "OK [S18] and the stop hook uses that check before starting the command" || fail "[S18] the hook starts the command without the cheap check"
fi
grep -q '"\[재는 검사\]"\* \]\] || bash "\$SCRIPT_DIR/pure-bench.sh" accept' "$CORE/scripts/turn-check.sh" && ok "OK [S18] only that question starts the acceptance step (other answers cost nothing)" || fail "[S18] every choice answer starts the command"
grep -q 'pure-bench.sh" accept --question' "$CORE/scripts/turn-check.sh" && ok "OK [S18] a choice answer reaches the acceptance record" || fail "[S18] no accept call"
grep -q 'SCV_PURE_BENCH' "$CORE/scripts/lib/settings.sh" && ok "OK [S18] the switch is a known setting" || fail "[S18] setting key missing"

pbt_finish
