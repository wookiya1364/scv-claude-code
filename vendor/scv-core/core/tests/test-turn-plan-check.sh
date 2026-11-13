#!/usr/bin/env bash
# test-turn-plan-check.sh — 턴 끝 계획 기록 검사(turn-check.sh)와 plan-link progress · exempt 를 본다
# (계획 20261109-wookiya1364-turn-plan-check · TESTS.md T1 ~ T12 · T15).
#
# 2026-11-09 시제품으로 잰 장면을 그대로 고정한다: 기록 없음 막힘(A) · append 통과(B) · progress 통과(P) ·
# 가짜 기록 여섯 가지 막힘(C · H · H2 · H3 · J · B2) · 엉터리 내용은 통과하되 원문이 붙음(K) ·
# 이번 턴 것만(D · D2 · E · F) · scv/ 밖 문서 · git 아닌 폴더 · 작업 공간의 다른 저장소 · 릴리스 예외 ·
# 2번 막히면 통과 + 기록 없음 · 선택 답 기록 · 끄기. T13(네 세션 다시 세기)은 로컬 기록이라 측정 단계, T14 는 scv-mods.
#
# T8(사진 0.3초 안) · T12(선택 답 2초 안)가 벽시계 한도를 본다 — 겹쳐 돌면 흔들린다(2026-11-12, 붐빌 때 두 번 실패).
# 다른 시험이 다 끝난 뒤 혼자 돈다:
# scv-test: serial
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TC="$CORE/scripts/turn-check.sh"
PL="$CORE/scripts/plan-link.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export SCV_TODAY=2026-11-09
unset PROMOTE_DIR ARCHIVE_DIR SCV_JOURNAL_DIR SCV_WORKSPACE_REPOS SCV_TURN_PLAN_CHECK 2>/dev/null || true
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

# @effect now_ms
# 이유: 시계를 읽는다(밀리초)
now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'; }

R="$WORK/repo"
mkdir -p "$R/scv/promote/p1" "$R/src"
cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
printf -- '---\ntitle: 시험 계획\nslug: p1\nstatus: in_progress\n---\n\n# 시험 계획\n\n## Goals / Non-Goals\n\n- **Goals**\n  - 결제 버튼\n- **Non-Goals**\n  - 환불 기능\n\n## Suggested path\n\n1. 하나\n2. 둘\n\n## Links\n' > scv/promote/p1/PLAN.md
printf 'a\n' > src/a.ts; printf '# r\n' > README.md
git add -A && git commit -qm init

reset() { git reset -q --hard HEAD; git clean -qfdx; }
start() { printf '%s' "${1:-전사 체력 87로 수정해}" | bash "$TC" start --session s1; }
verdict() { bash "$TC" end --session s1 | sed -n 's/^TURN_PLAN: //p'; }
tid() { cat scv/journal/.turn-plan/id 2>/dev/null; }
# 호스트 흉내: 도구 앞 훅처럼 영수증을 남기고 명령을 돌린다
H() { printf '%s' "$1" | bash "$TC" receipt --session s1; eval "$1" >/dev/null 2>&1; }
# 호스트 흉내: 쓰기 도구는 도구 앞 훅이 파일 이름을 알린 뒤 쓴다, 셸은 돌기 전 모습을 알린다
W() { bash "$TC" touch --session s1 --kind write "$1"; }
SH() { bash "$TC" touch --session s1 --kind shell; }
ed() { W src/a.ts; printf 'x\n' >> src/a.ts; }
plan() { cat scv/promote/p1/PLAN.md; }

# T1 — 셸로 코드 수정, 계획 기록 없음 → 막힘 · 막는 말 한 줄에 명령
reset; start; ed
out="$(bash "$TC" end --session s1)"
if grep -qx 'TURN_PLAN: block' <<<"$out" && grep -q 'plan-link.sh progress p1 --step' <<<"$out" \
   && [[ "$(grep -c '^TURN_PLAN_REASON: ' <<<"$out")" == 1 ]]; then ok "T1 기록 없음 → block, 막는 말에 progress 명령"
else bad "T1 $out"; fi

# T2 — 계획 밖 일 + plan-link append → 통과, 새 줄에 요청 번호 · 원문
reset; start "방패 옵션 바꿔라"; ed
H "bash $PL append p1 --after 2 --step '방패 옵션 글 바꿈 — x' --why '사용자 요청'"
v="$(verdict)"; id="$(tid)"
if [[ "$v" == pass ]] && plan | grep -q "요청: 방패 옵션 바꿔라 (요청 $id)"; then ok "T2 append → pass, 원문 · 번호 붙음"
else bad "T2 v=$v"; plan | tail -5 >&2; fi

# T3 — 계획 안 일 + progress 한 줄 → 통과
reset; start; ed
H "bash $PL progress p1 --step 2 --state done --note '2인 적 배수'"
v="$(verdict)"
if [[ "$v" == pass ]] && [[ "$(plan | grep -c '^- \*\*2026-11-09 진행\*\* — 2단계 끝: 2인 적 배수$')" == 1 ]]; then ok "T3 progress → pass, 진행 줄 1개"
else bad "T3 v=$v"; fi

# T4 — 가짜 기록 여섯 가지 → 모두 막힘
n4=0
reset; start; ed; printf '그냥 메모\n' >> scv/promote/p1/PLAN.md; [[ "$(verdict)" == block ]] && n4=$((n4 + 1))            # C
reset; start; ed; printf -- '- **2026-11-09 추가** — 아무거나\n' >> scv/promote/p1/PLAN.md; [[ "$(verdict)" == block ]] && n4=$((n4 + 1))   # H
reset; start; ed; printf -- '- **2026-11-09 추가** — 아무거나\n  - 요청: x (요청 %s)\n' "$(tid)" >> scv/promote/p1/PLAN.md; [[ "$(verdict)" == block ]] && n4=$((n4 + 1))   # H2
reset; start; ed; H "echo plan-link.sh append; printf -- '- **2026-11-09 추가** — x\n  - 요청: x (요청 $(tid))\n' >> scv/promote/p1/PLAN.md"; [[ "$(verdict)" == block ]] && n4=$((n4 + 1))   # H3
reset; start; ed; H "bash $PL append no-such --after 1 --step x --why y"; [[ "$(verdict)" == block ]] && n4=$((n4 + 1))   # J
reset; start; ed; printf 'bash %s progress p1 --step 1 --note x' "$PL" | bash "$TC" receipt --session s1
printf -- '- **2026-11-09 진행** — 1단계 끝: x\n' >> scv/promote/p1/PLAN.md; [[ "$(verdict)" == block ]] && n4=$((n4 + 1))   # B2
[[ $n4 == 6 ]] && ok "T4 가짜 기록 6/6 block (C · H · H2 · H3 · J · B2)" || bad "T4 $n4/6"

# T5 — 엉터리 내용 'x' 는 통과하되 원문이 보임
reset; start "칼 갈기 옵션 이상하다"; ed
H "bash $PL append p1 --after 1 --step x --why x"
v="$(verdict)"
if [[ "$v" == pass ]] && plan | grep -q '요청: 칼 갈기 옵션 이상하다 (요청 '; then ok "T5 엉터리 append → pass, 원문 붙음"
else bad "T5 v=$v"; fi

# T6 — 이번 턴 것만 (D · D2 · E · F)
reset; ed; start; vD="$(verdict)"
start; ed; vD2="$(verdict)"
reset; start; ed; git commit -qam c; vE="$(verdict)"; git reset -q --hard HEAD~1
reset; start; printf 'x\n' >> scv/promote/p1/PLAN.md; vF="$(verdict)"
[[ "$vD $vD2 $vE $vF" == "pass block block pass" ]] && ok "T6 D pass · D2 block · E block · F pass" || bad "T6 $vD $vD2 $vE $vF"

# T7 — scv/ 밖 문서도 바뀐 것, 계획 없으면 계획을 만들라는 말
reset; rm -rf scv/promote/p1; start; W README.md; printf 'y\n' >> README.md
out="$(bash "$TC" end --session s1)"
grep -qx 'TURN_PLAN: block' <<<"$out" && grep -q '진행 중 계획이 없다' <<<"$out" && ok "T7 README.md → block (no-plan)" || bad "T7 $out"

# T8 — git 아닌 폴더 · 파일 1,000개 사진 0.3초 안
G="$WORK/nogit"; mkdir -p "$G/scv/journal" "$G/d"
( cd "$G/d" && i=0; while (( i < 1000 )); do printf '%s' "$i" > "f$i.txt"; i=$((i + 1)); done )
cd "$G"
t0="$(now_ms)"; printf 'x' | bash "$TC" start --session s1; t1="$(now_ms)"
W d/f1.txt; printf 'z' >> d/f1.txt
v="$(verdict)"; ms=$((t1 - t0))
cd "$R"
[[ "$v" == block && $ms -lt 300 ]] && ok "T8 git 아님 → block, 사진 ${ms}ms" || bad "T8 v=$v ms=$ms"

# T9 — 작업 공간의 다른 저장소를 명령 글에 안 보이게 고침 → 그 저장소에서 막힘
B="$WORK/B"; mkdir -p "$B"; ( cd "$B" && git init -q . && git config user.email t@t && git config user.name t && printf 'b\n' > f.ts && git add -A && git commit -qm i )
reset; export SCV_WORKSPACE_REPOS="$B"; start
printf 'echo hack >> %s/f.ts\n' "$B" > "$WORK/sneaky.sh"; SH; bash "$WORK/sneaky.sh"
out="$(bash "$TC" end --session s1)"; unset SCV_WORKSPACE_REPOS
if grep -qx 'TURN_PLAN: block' <<<"$out" && grep -q 'TURN_PLAN_FILES: B:f.ts' <<<"$out"; then ok "T9 다른 저장소 B:f.ts → block"
else bad "T9 $out"; fi

# T10 — 릴리스 예외 통과 · 정하지 않은 종류는 거절 + 막힘
reset; rm -rf scv/promote/p1; start; W VERSION; printf '1.0\n' > VERSION
H "bash $PL exempt --kind release --why '래퍼 0.86.0'"; vR="$(verdict)"
reset; rm -rf scv/promote/p1; start; W VERSION; printf '1.0\n' > VERSION
rc=0; bash "$PL" exempt --kind misc --why x >/dev/null 2>&1 || rc=$?
printf 'bash %s exempt --kind misc --why x' "$PL" | bash "$TC" receipt --session s1; vM="$(verdict)"
[[ "$vR" == pass && $rc == 2 && "$vM" == block ]] && ok "T10 release pass · misc 거절(2) + block" || bad "T10 vR=$vR rc=$rc vM=$vM"

# T11 — 2번 막히면 통과 + 기록 없음 한 줄
reset; start; ed
v1="$(verdict)"; v2="$(verdict)"; v3="$(verdict)"
if [[ "$v1 $v2 $v3" == "block block pass-unrecorded" ]] && plan | grep -q '기록 없음\*\* — 파일 1개를 바꾼 턴' \
   && grep -q '계획 기록 없음' scv/journal/.turn-plan.log; then ok "T11 block · block · pass-unrecorded + 기록 없음 줄"
else bad "T11 $v1 $v2 $v3"; fi

# T12 — 선택 답 17개를 이력에 바로 · 1초 안, 훅 입력(JSON) 한 개도
reset
t0="$(now_ms)"
i=1; while (( i <= 17 )); do bash "$TC" choice --question "질문 $i" --answer "답 $i" >/dev/null; i=$((i + 1)); done
t1="$(now_ms)"
printf '%s' '{"session_id":"s1","tool_input":{"questions":[{"question":"어떻게 할까요?"}]},"tool_response":{"answers":{"어떻게 할까요?":"추천대로"}}}' \
  | CLAUDE_PLUGIN_ROOT="$CORE" bash "$CORE/template/hooks/on-choice-answer.sh"
nq="$(plan | grep -c ' 선택\*\* — 답: ')"; ms=$((t1 - t0))
first="$(plan | grep -m1 ' 선택\*\* — 답: ' | sed 's/.*답: //')"
if [[ $nq == 18 && "$first" == "답 1" && $ms -lt 2000 ]] && plan | grep -q '답: 추천대로'; then ok "T12 선택 답 17 + 훅 1 = 18줄, 순서 그대로, ${ms}ms"
else bad "T12 nq=$nq first=$first ms=$ms"; fi


# T16 — 계획이 하지 않기로 한 일(환불)을 progress · append 로 적으면 멈춤(3), 물은 뒤 --accept-conflict 면 적힘 (검증 X1 · X2)
reset; start "환불 버튼도 추가해"; ed
r1=0; bash "$PL" progress p1 --step 1 --note '환불 버튼' >/dev/null 2>&1 || r1=$?
r2=0; bash "$PL" append p1 --after 1 --step '환불 버튼 — z' --why x >/dev/null 2>&1 || r2=$?
v1="$(verdict)"
r3=0; bash "$PL" progress p1 --step 1 --note '결제 버튼 색' >/dev/null 2>&1 || r3=$?
r4=0; bash "$PL" append p1 --after 1 --step '환불 버튼 — z' --why '사용자가 같은 목표라 함' --accept-conflict >/dev/null 2>&1 || r4=$?
if [[ "$r1 $r2 $v1 $r3 $r4" == "3 3 block 0 0" ]] && plan | grep -q '^2\. 환불 버튼 — z$'; then ok "T16 하지 않음 겹침 → progress 3 · append 3 · 판정 block, 겹치지 않으면 0, 물은 뒤 적힘"
else bad "T16 $r1 $r2 $v1 $r3 $r4"; fi

# T17 — 대시보드가 켜져 있으면 단계 보고 도구 호출이 있어야 끝남, 꺼져 있으면 진행 줄로 충분
ON="$WORK/host-settings.json"; printf '{"enabledPlugins": {"dash@m": true}}' > "$ON"
export SCV_STEP_TOOL=tool_step SCV_STEP_TOOL_ON_FILE="$ON" SCV_STEP_TOOL_ON_MARK='"dash@m": true'
reset; start; ed; H "bash $PL progress p1 --step 1 --note '결제 버튼'"; vA="$(verdict)"
bash "$TC" step --session s1 --tool other_tool; vB="$(verdict)"
bash "$TC" step --session s1 --tool tool_step; vC="$(verdict)"
printf '{"enabledPlugins": {"dash@m": false}}' > "$ON"
reset; start; ed; H "bash $PL progress p1 --step 1 --note '결제 버튼'"; vD="$(verdict)"
unset SCV_STEP_TOOL SCV_STEP_TOOL_ON_FILE SCV_STEP_TOOL_ON_MARK
[[ "$vA $vB $vC $vD" == "block block pass pass" ]] && ok "T17 켜짐: 보고 없음 block · 다른 도구 block · 보고 pass, 꺼짐: 진행 줄만 pass" || bad "T17 $vA $vB $vC $vD"

# T43 ~ T50 — 단계 보고 도구에 도구 앞 훅이 닿지 않는 호스트 (계획 20261113-wookiya1364-step-report-and-bench-before · TESTS T1 ~ T8).
# 그 도구를 앱의 모드가 직접 처리하면 도구 앞 훅이 돌지 않아 표시가 0 이다(2026-11-13 실제 세션에서 확인: 16번 넘게 불러도 0).
# 턴 끝 검사는 막을 참일 때만 대화 기록에서 "이번 턴이 시작된 뒤 어시스턴트가 그 도구를 부른 줄"을 센다.
printf '{"enabledPlugins": {"dash@m": true}}' > "$ON"
export SCV_STEP_TOOL=tool_step SCV_STEP_TOOL_ON_FILE="$ON" SCV_STEP_TOOL_ON_MARK='"dash@m": true'
TR="$WORK/transcript.jsonl"; LATER="2099-01-01T00:00:00.000Z"; EARLIER="2000-01-01T00:00:00.000Z"
tline() {  # <call|other|text|user|list|junk> <시각> → 대화 기록 한 줄
  case "$1" in
    call)  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"단계를 알린다"},{"type":"tool_use","id":"t1","name":"tool_step","input":{"plan":"p1","step":1,"state":"doing"}}]}}\n' "$2" ;;
    other) printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"other_tool","input":{"note":"tool_step 은 아니다"}}]}}\n' "$2" ;;
    text)  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"tool_step 을 부르겠다"}]}}\n' "$2" ;;
    user)  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"이 세션에 tool_step 도구가 있으면 단계를 알려라 — tool_use 가 아니다"}}\n' "$2" ;;
    list)  printf '{"type":"attachment","timestamp":"%s","attachment":{"type":"tool_list","names":["tool_step","other_tool"],"note":"tool_use"}}\n' "$2" ;;
    junk)  printf 'tool_step tool_use — JSON 이 아닌 줄 %s\n' "$2" ;;
  esac
}
verdict_t() { bash "$TC" end --session s1 --transcript "$1" | sed -n 's/^TURN_PLAN: //p'; }
turn_ready() { reset; start; ed; H "bash $PL progress p1 --step 1 --note '결제 버튼'"; }

turn_ready; tline call "$LATER" > "$TR"; v="$(verdict_t "$TR")"
[[ "$v" == pass ]] && ok "T43 표시 없이 대화 기록에 이번 턴의 호출 → pass" || bad "T43 $v"

turn_ready; { tline other "$LATER"; tline text "$LATER"; } > "$TR"
o="$(bash "$TC" end --session s1 --transcript "$TR")"
[[ "$(sed -n 's/^TURN_PLAN: //p' <<< "$o")" == block ]] && grep -q '^TURN_PLAN_REASON: .*tool_step' <<< "$o" && ok "T44 부르지 않은 턴 → block, 이유에 도구 이름" || bad "T44 $o"

turn_ready; tline call "$EARLIER" > "$TR"; v="$(verdict_t "$TR")"
[[ "$v" == block ]] && ok "T45 앞 턴의 호출은 세지 않음 → block" || bad "T45 $v"

turn_ready; { tline user "$LATER"; tline list "$LATER"; tline text "$LATER"; tline junk "$LATER"; } > "$TR"; v="$(verdict_t "$TR")"
[[ "$v" == block ]] && ok "T46 이름이 글에 나온 것만으로는 세지 않음 → block" || bad "T46 $v"

# 호출 줄의 시각은 "턴 시작 1초 뒤, 도중에 온 말보다 앞"이다 — 시작 시각이 도중에 온 말로 밀리면 세지 못해 막힌다
turn_ready; i0="$(cat scv/journal/.turn-plan/id)"; sleep 2; tline call "$(date -u +%Y-%m-%dT%H:%M:%S).000Z" > "$TR"
sleep 2; start "도중에 온 말"; i1="$(cat scv/journal/.turn-plan/id)"; v="$(verdict_t "$TR")"
[[ -n "$i0" && "$i0" == "$i1" && "$v" == pass ]] && ok "T47 도중에 온 말로 이어진 턴: 처음 시작 시각부터 셈 · pass" || bad "T47 [$i0] [$i1] $v"

turn_ready; bash "$TC" step --session s1 --tool tool_step
e="$(bash "$TC" end --session s1 --transcript "$WORK/no-such-transcript.jsonl" 2>&1 >/dev/null)"; reset
turn_ready; bash "$TC" step --session s1 --tool tool_step; v="$(verdict_t "$WORK/no-such-transcript.jsonl")"
[[ "$v" == pass && -z "$e" ]] && ok "T48 훅의 표시가 있으면 대화 기록 없이 pass, 오류 출력 없음" || bad "T48 $v [$e]"

n7=0; : > "$WORK/empty.jsonl"; { tline junk "$LATER"; printf '{"type":"assistant"\n'; } > "$WORK/junk.jsonl"
for tr7 in "$WORK/no-such-transcript.jsonl" "$WORK/empty.jsonl" "$WORK/junk.jsonl" ""; do
  turn_ready
  if [[ -n "$tr7" ]]; then o="$(bash "$TC" end --session s1 --transcript "$tr7" 2>&1)"; rc=$?; else o="$(bash "$TC" end --session s1 2>&1)"; rc=$?; fi
  [[ $rc == 0 && "$(sed -n 's/^TURN_PLAN: //p' <<< "$o")" == block && "$(grep -c . <<< "$o")" == 4 ]] && n7=$((n7 + 1))
done
[[ $n7 == 4 ]] && ok "T49 대화 기록을 읽을 수 없는 넷(없음 · 빔 · JSON 아님 · 안 넘김) → 모두 block, 종료 코드 0, 군말 없음" || bad "T49 $n7/4"

# shellcheck source=../scripts/lib/turn-check.sh
c8="$( source "$CORE/scripts/lib/plan-link.sh"; source "$CORE/scripts/lib/turn-check.sh"
  L="$(tline call "$LATER"; tline call "2026-11-13T02:00:00.500Z"; tline call "$EARLIER"; tline other "$LATER"; tline text "$LATER"; tline junk "$LATER")"
  printf '%s %s %s %s' "$(scv_tc_step_calls "$L" tool_step "2026-11-13T02:00:00")" "$(scv_tc_step_calls "" tool_step "2026-11-13T02:00:00")" \
    "$(scv_tc_step_calls "$L" tool_step "")" "$(scv_tc_step_calls "$L" "" "2026-11-13T02:00:00")" )"
[[ "$c8" == "2 0 0 0" ]] && ok "T50 세는 함수: 시작 뒤 호출 2 · 빈 입력 0 · 시작 시각 없음 0 · 도구 이름 없음 0" || bad "T50 [$c8]"
# T51 — 끝 훅이 대화 기록 자리를 턴 끝 검사에 넘긴다 (TESTS T10)
STOP_HOOK="$CORE/template/hooks/on-stop.sh"
stop_out() { jq -cn --arg p "$1" '{transcript_path:$p,last_assistant_message:"끝",stop_hook_active:false}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$STOP_HOOK" 2>/dev/null; }
turn_ready; tline call "$LATER" > "$TR"; oA="$(stop_out "$TR")"
turn_ready; tline other "$LATER" > "$TR"; oB="$(stop_out "$TR")"
if ! grep -q 'tool_step' <<< "$oA" && grep -q '"decision":"block"' <<< "$oB" && grep -q 'tool_step' <<< "$oB"; then ok "T51 끝 훅: 호출이 있으면 단계 보고로 막지 않고, 없으면 막는다"
else bad "T51 A=[$(head -c 200 <<< "$oA")] B=[$(head -c 200 <<< "$oB")]"; fi
# T52 — 막을 일이 없는 턴은 대화 기록을 열지 않고, 막을 참인 턴이 큰 대화 기록(30MB)을 읽어도 0.7초를 더 쓰지 않는다 (TESTS T9)
BIG="$WORK/big.jsonl"
yes '{"type":"user","timestamp":"2099-01-01T00:00:00.000Z","message":{"role":"user","content":"긴 대화 기록의 한 줄 — 단계 보고 도구의 이름은 없다"}}' 2>/dev/null | head -c 30000000 > "$BIG"
end_ms() {  # [대화 기록] → 턴 끝 검사를 세 번 돌린 가운데 가장 빠른 시간(ms)
  local best=999999 a b i
  for i in 1 2 3; do
    a="$(now_ms)"; if [[ -n "${1:-}" ]]; then bash "$TC" end --session s1 --transcript "$1" >/dev/null; else bash "$TC" end --session s1 >/dev/null; fi; b="$(now_ms)"
    [[ $((b - a)) -lt $best ]] && best=$((b - a))
  done
  printf '%s' "$best"
}
printf '{"enabledPlugins": {"dash@m": false}}' > "$ON"
turn_ready; off_no="$(end_ms)"; off_big="$(end_ms "$BIG")"
printf '{"enabledPlugins": {"dash@m": true}}' > "$ON"
turn_ready; printf '5' > scv/journal/.turn-plan/blocks; on_no="$(end_ms)"; on_big="$(end_ms "$BIG")"
# 큰 기록의 맨 끝에 붙은 호출도 센다 — 끝 쪽만 읽어도 이번 턴의 호출은 거기 있다
turn_ready; cp "$BIG" "$WORK/big-call.jsonl"; { printf '\n'; tline call "$LATER"; } >> "$WORK/big-call.jsonl"; vbig="$(verdict_t "$WORK/big-call.jsonl")"
if [[ $off_big -le $((off_no * 3 / 2 + 200)) && $((on_big - on_no)) -le 700 && "$vbig" == pass ]]; then ok "T52 대화 기록 30MB: 보고가 필요 없는 턴 ${off_no} → ${off_big}ms · 막을 참인 턴 ${on_no} → ${on_big}ms"
else bad "T52 필요 없음 ${off_no} → ${off_big}ms · 막을 참 ${on_no} → ${on_big}ms · 큰 기록 끝의 호출 $vbig"; fi
unset SCV_STEP_TOOL SCV_STEP_TOOL_ON_FILE SCV_STEP_TOOL_ON_MARK

# T18 — 보류시킨 계획이 보관됐는데 원래 계획이 아직 보류면 막고, resume 뒤 통과
reset; mkdir -p scv/promote/p2 scv/archive
printf -- '---\ntitle: 로그\nstatus: in_progress\nreturn_to: p1\n---\n\n## Suggested path\n\n1. 로그 — l\n' > scv/promote/p2/PLAN.md
bash "$PL" pause p1 --by p2 --resume-at 2 --why '다른 목표' >/dev/null 2>&1
mv scv/promote/p2 scv/archive/p2
start; ed; H "bash $PL exempt --kind release --why x"; out="$(bash "$TC" end --session s1)"
H "bash $PL resume p2"; H "bash $PL progress p1 --step 2 --note '결제 버튼'"; v2="$(verdict)"
if grep -qx 'TURN_PLAN: block' <<<"$out" && grep -q 'resume p2' <<<"$out" && [[ "$v2" == pass ]]; then ok "T18 되돌아가지 않은 보류 → block(resume p2 안내), resume 뒤 pass"
else bad "T18 $out / $v2"; fi

# T19 — 진행 줄의 시작 · 막힘 상태
reset; bash "$PL" progress p1 --step 1 --state doing --note 시작함 >/dev/null; bash "$PL" progress p1 --step 2 --state blocked --note '키 없음' >/dev/null
if plan | grep -q '1단계 시작: 시작함' && plan | grep -q '2단계 막힘: 키 없음'; then ok "T19 진행 줄 시작 · 막힘"; else bad "T19"; fi


# T20 — 호스트 프로필 검사가 대시보드 켜짐 두 키를 받고, 짝이 없거나 상대 경로면 거절 (0.87.1 — 0.87.0 래퍼 릴리스가 여기서 막혔다)
VH="$CORE/../tools/validate-host-profile.sh"; FX="$CORE/../tests/fixtures/codex.env"
if [[ -f "$VH" && -f "$FX" ]]; then
  grep -v '^SCV_STEP_TOOL' "$FX" > "$WORK/base.env"; printf 'SCV_STEP_TOOL=tool_step\n' >> "$WORK/base.env"
  { cat "$WORK/base.env"; printf 'SCV_STEP_TOOL_ON_FILE=~/.host/settings.json\nSCV_STEP_TOOL_ON_MARK="dash": true\n'; } > "$WORK/p1.env"
  { cat "$WORK/base.env"; printf 'SCV_STEP_TOOL_ON_FILE=rel/settings.json\nSCV_STEP_TOOL_ON_MARK=x\n'; } > "$WORK/p2.env"
  { cat "$WORK/base.env"; printf 'SCV_STEP_TOOL_ON_FILE=~/.host/settings.json\n'; } > "$WORK/p3.env"
  a=0; bash "$VH" --profile "$WORK/p1.env" >/dev/null 2>&1 || a=$?
  b=0; bash "$VH" --profile "$WORK/p2.env" >/dev/null 2>&1 || b=$?
  c=0; bash "$VH" --profile "$WORK/p3.env" >/dev/null 2>&1 || c=$?
  [[ $a == 0 && $b != 0 && $c != 0 ]] && ok "T20 프로필 검사: 두 키 통과 · 상대 경로 거절 · 짝 없음 거절" || bad "T20 $a $b $c"
  MP="$CORE/../tools/materialize-profile.sh"
  if [[ -f "$MP" ]]; then
    mkdir -p "$WORK/mcore"; cp -R "$CORE/." "$WORK/mcore/"
    d=0; bash "$MP" --root "$WORK/mcore" --profile "$WORK/p1.env" >/dev/null 2>&1 || d=$?
    if [[ $d == 0 ]] && grep -qx 'SCV_STEP_TOOL_ON_FILE=~/.host/settings.json' "$WORK/mcore/host-profile.env" \
       && grep -qx 'SCV_STEP_TOOL_ON_MARK="dash": true' "$WORK/mcore/host-profile.env"; then ok "T20b 프로필 만들기가 두 키를 옮김 (0.87.2)"
    else bad "T20b materialize d=$d"; fi
  fi
else ok "T20 건너뜀 (프로필 검사 도구 없음 — 래퍼 안)"; fi

# ---- 계획 20261109-wookiya1364-turn-check-own-files: 이 세션이 고친 파일만 센다 ----
# 2026-11-09 실측: 이 세션은 slay 를 읽기만 했는데 slay 세션이 고친 파일로 두 번 막혔다.

# T21 — 남이 고친 파일만 있으면 통과 (이 세션은 읽기만)
reset; rm -rf scv/promote/p1; start
bash "$TC" touch --session s1 --kind read src/a.ts
printf 'other session\n' >> src/a.ts
v="$(verdict)"
[[ "$v" == pass ]] && ok "T21 남이 고친 파일만 → pass" || bad "T21 v=$v"

# T22 — 편집 도구로 고친 파일은 막힘, 그 파일 이름이 나옴
reset; rm -rf scv/promote/p1; start; W src/a.ts; printf 'mine\n' >> src/a.ts
out="$(bash "$TC" end --session s1)"
grep -qx 'TURN_PLAN: block' <<<"$out" && grep -q 'TURN_PLAN_FILES: src/a.ts' <<<"$out" && ok "T22 편집 도구 → block, src/a.ts" || bad "T22 $out"

# T23 — 셸로 고친 파일은 막힘, 셸 앞에 남이 고친 파일은 빠짐
reset; rm -rf scv/promote/p1; start
printf 'other\n' >> README.md            # 다른 세션
SH; printf 'mine\n' >> src/a.ts           # 이 세션의 셸 명령
out="$(bash "$TC" end --session s1)"
files="$(sed -n 's/^TURN_PLAN_FILES: //p' <<<"$out")"
if grep -qx 'TURN_PLAN: block' <<<"$out" && [[ "$files" == *src/a.ts* && "$files" != *README.md* ]]; then ok "T23 셸 → block, src/a.ts 만 (README.md 빠짐)"
else bad "T23 $out"; fi

# T24 — 읽기만 한 다른 저장소는 상태에 남지 않음 (도구 앞 훅에 읽기 입력을 그대로 넣음)
reset; start
printf '{"cwd":"%s","session_id":"s1","tool_name":"Read","tool_input":{"file_path":"%s/f.ts"}}' "$R" "$B" \
  | SCV_GUARD_STATE="$WORK/gstate" bash "$CORE/template/hooks/guard.sh" >/dev/null 2>&1
printf '{"cwd":"%s","session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"%s/src/a.ts","old_string":"a","new_string":"b"}}' "$R" "$R" \
  | SCV_GUARD_STATE="$WORK/gstate" bash "$CORE/template/hooks/guard.sh" >/dev/null 2>&1
nr="$(grep -c . scv/journal/.turn-plan/roots)"
if [[ $nr == 1 ]] && ! grep -q "$B" scv/journal/.turn-plan/roots && grep -q '/src/a.ts$' scv/journal/.turn-plan/mine; then ok "T24 훅: 읽기 → 저장소 안 셈, 편집 → 내 파일에 src/a.ts"
else bad "T24 roots=$(tr '\n' ' ' < scv/journal/.turn-plan/roots) mine=$(cat scv/journal/.turn-plan/mine 2>/dev/null)"; fi

# T25 — 셸로 커밋한 파일도 내 몫
reset; rm -rf scv/promote/p1; start; SH; printf 'c\n' >> src/a.ts; git commit -qam c
out="$(bash "$TC" end --session s1)"; git reset -q --hard HEAD~1
grep -qx 'TURN_PLAN: block' <<<"$out" && grep -q 'src/a.ts' <<<"$out" && ok "T25 셸로 커밋 → block, src/a.ts" || bad "T25 $out"

# T26 — 순수 함수
# shellcheck source=../scripts/lib/turn-check.sh
source "$CORE/scripts/lib/turn-check.sh"
k="$(scv_tc_tool_kind ls '' '') $(scv_tc_tool_kind '' /a yes) $(scv_tc_tool_kind '' /a '')"
a="$(scv_tc_abs_paths /r $'a.ts\nsrc/b.ts')"; m="$(scv_tc_mine_only $'/r/a\n/r/b' $'/r/b\n/x/c')"
[[ "$k" == "shell write read" && "$a" == $'/r/a.ts\n/r/src/b.ts' && "$m" == /r/b ]] && ok "T26 순수 함수 세 개" || bad "T26 k=$k a=$a m=$m"

# T27 — --state 없는 progress 는 '시작' (끝은 직접 말할 때만, 0.87.4)
reset; bash "$PL" progress p1 --step 2 --note '측정 중' >/dev/null
if plan | grep -q '2단계 시작: 측정 중$' && ! plan | grep -q '2단계 끝'; then ok "T27 상태 없는 progress → 시작"; else bad "T27 $(plan | grep 단계)"; fi

# T28 — --state done 은 그대로 '끝'
reset; bash "$PL" progress p1 --step 2 --state done --note '다 함' >/dev/null
plan | grep -q '2단계 끝: 다 함$' && ok "T28 --state done → 끝" || bad "T28 $(plan | grep 단계)"

# T29 — 막힘 안내문이 끝 · 진행을 나눠 보여 줌
# shellcheck source=../scripts/lib/turn-check.sh
source "$CORE/scripts/lib/turn-check.sh"
m="$(scv_tc_block_msg in-plan a 3 /p/plan-link.sh)"
if [[ "$m" == *"--state doing"* && "$m" == *"--state done"* && "$m" == *"끝났을 때만"* ]]; then ok "T29 안내문 doing · done 구분"; else bad "T29 $m"; fi

# T30 — 단계를 끼우면 뒤 진행 줄 번호가 밀림, 다른 이력 줄은 그대로
reset
printf -- '---\ntitle: t\nslug: p1\nstatus: in_progress\n---\n\n## Suggested path\n\n1. 하나\n2. 둘\n3. 셋\n\n## 변경 이력\n\n- **2026-11-09 진행** — 1단계 끝: a\n\n- **2026-11-09 진행** — 2단계 끝: b\n  - 요청: x (요청 ab)\n\n- **2026-11-09 추가** — 1단계 뒤에 새 단계\n  - 새 단계: 옛것\n\n- **2026-11-09 진행** — 3단계 시작: c\n\n## Links\n' > scv/promote/p1/PLAN.md
bash "$PL" append p1 --after 1 --step '새것 — n' --why x >/dev/null
if plan | grep -q '1단계 끝: a$' && plan | grep -q '3단계 끝: b$' && plan | grep -q '4단계 시작: c$' \
   && plan | grep -q '추가\*\* — 1단계 뒤에 새 단계$' && plan | grep -q '^2\. 새것 — n$' && ! plan | grep -q '2단계 끝: b'; then
  ok "T30 끼우기 → 뒤 진행 줄 번호 +1, 추가 줄 그대로"
else bad "T30 $(plan | grep -E '단계|^[0-9]\.')"; fi

# T31 — 순수 함수 scv_plan_shift_progress
# shellcheck source=../scripts/lib/plan-link.sh
source "$CORE/scripts/lib/plan-link.sh"
s1="$(scv_plan_shift_progress $'## 변경 이력\n\n- **d 진행** — 3a단계 막힘: k\n- **d 진행** — 2단계 끝: j' 2)"
s2="$(scv_plan_shift_progress $'# a\n본문 3단계' 1)"
if [[ "$s1" == $'## 변경 이력\n\n- **d 진행** — 4a단계 막힘: k\n- **d 진행** — 2단계 끝: j' && "$s2" == $'# a\n본문 3단계' ]]; then ok "T31 순수 함수 번호 밀기"
else bad "T31 s1=$s1 s2=$s2"; fi

# T15 — 끄기 · 기존 plan-link 시험
reset; export SCV_TURN_PLAN_CHECK=off; start; ed; v="$(verdict)"; unset SCV_TURN_PLAN_CHECK
rc=0; bash "$CORE/tests/test-plan-link.sh" >/dev/null 2>&1 || rc=$?
[[ "$v" == off && $rc == 0 ]] && ok "T15 off → 판정 안 함, test-plan-link 통과" || bad "T15 v=$v rc=$rc"

# 덧붙임 — 훅 네 곳이 turn-check.sh 를 부른다
hk="$CORE/template/hooks"
if grep -q 'turn-check.sh' "$hk/on-user-prompt.sh" && grep -q 'turn-check.sh' "$hk/on-stop.sh" \
   && grep -q 'turn-check.sh' "$hk/guard.sh" && grep -q 'turn-check.sh' "$hk/on-choice-answer.sh"; then
  ok "hooks — 턴 시작 · 턴 끝 · 도구 앞 · 선택 답이 turn-check.sh 를 부름"
else bad "hooks do not call turn-check.sh"; fi

# T32 — 계획을 보관한 턴: 그 계획에 남긴 기록이 보관함으로 옮겨져도 읽는다 → 통과 (계획 20261112-wookiya1364-bench-gate-gaps T1)
# 보관 기록 파일이 턴 시작 표시보다 새것이어야 하므로(초 단위로 견준다) 1초 쉰다.
cd "$R" || exit 1
reset; start; ed
H "bash $PL progress p1 --step 2 --note '체력 숫자를 87로 고침'"
sleep 1
mkdir -p scv/archive && mv scv/promote/p1 scv/archive/p1 && printf '보관: 시험 통과\n' > scv/archive/p1/ARCHIVED_AT.md
v="$(verdict)"
if [[ "$v" == pass ]]; then ok "T32 계획을 보관한 턴 → pass (보관함으로 옮긴 계획의 기록을 읽음)"
else bad "T32 v=$v"; fi

# T33 — 턴이 시작되기 전에 보관된 계획으로는 통과하지 않는다 → 지금처럼 막힘 (같은 계획 T2)
reset
mkdir -p scv/archive && mv scv/promote/p1 scv/archive/p1 && printf '보관: 예전\n' > scv/archive/p1/ARCHIVED_AT.md
sleep 1
start; ed
v="$(verdict)"
if [[ "$v" == block ]]; then ok "T33 예전에 보관된 계획만 있고 기록 없음 → block"
else bad "T33 v=$v"; fi
reset

# T34 — 기록 명령을 실제로 돌렸으면 명령 글의 모양과 상관없이 영수증이 남는다 (계획 20261112-wookiya1364-small-fixes-bundle T4)
#   2026-11-12 재현: 모델은 기록 명령을 "경로를 변수에 담아" · "다른 명령 뒤에 이어서" · "둘째 줄에서" 돌린다.
#   도구 앞 훅은 명령 글의 첫 줄이 정해진 꼴일 때만 영수증을 남겨, 기록 줄이 계획에 있는데도 턴이 막혔다
#   (그 세션의 상태 파일: 기록 명령 네 번 · 영수증 0). 기록 명령 스스로가 기록을 남긴 뒤 영수증을 더한다.
n34=0
reset; start; ed; H "P='$CORE/scripts'; bash \"\$P/plan-link.sh\" progress p1 --step 2 --note '변수에 담은 경로'"
v="$(verdict)"; [[ "$v" == pass ]] && n34=$((n34 + 1)) || echo "  (T34 변수 경로: $v)" >&2
reset; start; ed; H "cd '$R' && git status --short >/dev/null; SL=p1; bash '$PL' progress \"\$SL\" --step 2 --note '다른 명령 뒤'"
v="$(verdict)"; [[ "$v" == pass ]] && n34=$((n34 + 1)) || echo "  (T34 다른 명령 뒤: $v)" >&2
reset; start; ed; H "echo 먼저
bash '$PL' progress p1 --step 2 --note '둘째 줄'"
v="$(verdict)"; [[ "$v" == pass ]] && n34=$((n34 + 1)) || echo "  (T34 둘째 줄: $v)" >&2
[[ $n34 == 3 ]] && ok "T34 기록 명령을 실제로 돌린 턴 3/3 pass (변수 경로 · 다른 명령 뒤 · 둘째 줄)" || bad "T34 $n34/3"
# 실패한 기록 명령은 영수증을 남기지 않는다 — 없는 계획에 적으려 한 턴은 그대로 막힌다
reset; start; ed; H "P='$CORE/scripts'; bash \"\$P/plan-link.sh\" progress no-such --step 1 --note x"
v="$(verdict)"; [[ "$v" == block ]] && ok "T34 실패한 기록 명령은 영수증이 아니다 → block" || bad "T34 실패한 명령 v=$v"
reset

# T35 — 파일을 붙여 보낸 요청: 첨부 파일의 경로는 계획 기록에 적히지 않는다 (같은 계획 T5)
#   2026-11-12: 보관된 계획 둘의 "요청:" 줄에 내 컴퓨터의 경로가 그대로 남아 손으로 지웠다.
att='@"/Users/x/uploads/s1/shot@2x.png" 이 화면처럼 방패 옵션을 고쳐줘'
reset; start "$att"; ed
H "bash $PL progress p1 --step 2 --note '방패 옵션 고침'"
v="$(verdict)"; id="$(tid)"
if [[ "$v" == pass ]] && plan | grep -q "요청: \[첨부\] 이 화면처럼 방패 옵션을 고쳐줘 (요청 $id)" \
   && ! plan | grep -q '/Users/x' && ! grep -q '/Users/x' scv/journal/.turn-plan/req; then ok "T35 첨부 경로는 계획 기록 · 턴 상태에 없다, 나머지 글은 그대로"
else bad "T35 v=$v"; plan | tail -3 >&2; fi
# 첨부가 없는 요청은 한 글자도 바뀌지 않는다
reset; start "방패 옵션 바꿔라 — 메일은 a@b.com"; ed
[[ "$(cat scv/journal/.turn-plan/req)" == "방패 옵션 바꿔라 — 메일은 a@b.com" ]] && ok "T35 첨부 없는 요청은 그대로" || bad "T35 그대로가 아님: $(cat scv/journal/.turn-plan/req)"
# 순수 함수 — 닫는 따옴표가 없으면 경로가 아니다, 맨 꼴은 빈칸 뒤에서만
t35="$(scv_tc_strip_attach '안 닫힘 @"/a/b 그리고 x@/y'; printf '|'; scv_tc_strip_attach $'줄\n@/a/b.png\n끝')"
[[ "$t35" == $'안 닫힘 @"/a/b 그리고 x@/y|줄\n[첨부]\n끝' ]] && ok "T35 순수 함수: 안 닫힌 따옴표 · 메일 꼴은 그대로, 줄 사이의 맨 꼴은 지움" || bad "T35 순수 함수: [$t35]"
reset

# ── 턴 도중에 온 말은 같은 턴으로 이어 간다 (계획 20261112-wookiya1364-turn-continues-mid-message) ──
# 사람의 말마다 턴을 새로 시작하면, 일하는 도중에 온 말 뒤에는 그 앞의 기록 · 영수증이 '앞 턴 것'이 되어 같은 일에
# 기록을 한 번 더 요구했다. 턴이 끝났다는 표시(턴 끝이 통과를 냄 · 세션을 새로 열거나 다시 엶)가 없으면 이어 간다.
SS_HOOK="$CORE/template/hooks/on-session-start.sh"
REQF="scv/journal/.turn-plan/req"

# T36 — 일하는 도중에 온 말: 요청 번호 · 영수증이 그대로라 앞의 기록으로 통과, 요청 글에는 두 말이 모두 남는다
reset; start "방패 옵션 바꿔라"; ed
H "bash $PL progress p1 --step 1 --note '방패 옵션 글 바꿈'"
id1="$(tid)"
start "아 그리고 설명도 고쳐"
W README.md; printf 'more\n' >> README.md
v="$(verdict)"; id2="$(tid)"
if [[ "$v" == pass && -n "$id1" && "$id1" == "$id2" && "$(cat "$REQF")" == $'방패 옵션 바꿔라\n(도중에 온 말) 아 그리고 설명도 고쳐' ]]; then ok "T36 도중에 온 말 → 같은 턴(번호 그대로), 앞의 기록으로 pass, 요청 글에 두 말"
else bad "T36 v=$v id1=$id1 id2=$id2 req=$(cat "$REQF" 2>/dev/null | tr '\n' '|')"; fi

# T37 — 계획을 보관한 뒤 온 말: 그 턴에 보관한 계획을 계속 읽는다 → 예외를 적지 않아도 통과
reset; start "마무리해"; ed
H "bash $PL progress p1 --step 2 --state done --note '체력 숫자를 87로 고침'"
sleep 1
mkdir -p scv/archive && mv scv/promote/p1 scv/archive/p1 && printf '보관: 시험 통과\n' > scv/archive/p1/ARCHIVED_AT.md
start "변경 기록도 써 줘"
W CHANGELOG.md; printf 'x\n' > CHANGELOG.md
v="$(verdict)"
if [[ "$v" == pass && ! -s scv/journal/.turn-plan/exempt ]]; then ok "T37 보관한 뒤 온 말 → 예외 없이 pass"
else bad "T37 v=$v exempt=$(cat scv/journal/.turn-plan/exempt 2>/dev/null)"; fi

# T38 — 끝난 턴 뒤의 말: 지금처럼 새로 시작한다 → 지난 턴의 기록은 세지 않는다, 번호가 바뀌고 요청 글은 새 말뿐
reset; start "첫 요청"; ed
H "bash $PL progress p1 --step 1 --note '첫 일'"
v1="$(verdict)"; id1="$(tid)"
start "둘째 요청"
W README.md; printf 'more\n' >> README.md
v2="$(verdict)"; id2="$(tid)"
if [[ "$v1 $v2" == "pass block" && "$id1" != "$id2" && "$(cat "$REQF")" == "둘째 요청" ]]; then ok "T38 끝난 턴 뒤의 말 → 새 턴(번호 바뀜), 지난 기록은 세지 않아 block"
else bad "T38 v1=$v1 v2=$v2 id1=$id1 id2=$id2 req=$(cat "$REQF" 2>/dev/null | tr '\n' '|')"; fi

# T39 — 사용자가 멈춘 턴 뒤의 말: 멈추기 전에 고친 파일도 이번 턴 끝에 센다. 되돌렸으면 셀 것이 없다
reset; start "전사 체력 고쳐"; ed
start "그만, 다른 것부터"
out="$(bash "$TC" end --session s1)"
reset; start "전사 체력 고쳐"; ed
git checkout -q -- src/a.ts
start "그만, 그건 버려"
vR="$(verdict)"
if grep -qx 'TURN_PLAN: block' <<<"$out" && grep -q '^TURN_PLAN_FILES: .*src/a.ts' <<<"$out" && [[ "$vR" == pass ]]; then ok "T39 멈춘 턴 뒤의 말 → 멈추기 전에 고친 파일로 block, 되돌렸으면 pass"
else bad "T39 vR=$vR out=$out"; fi

# T40 — 막혔다가 이어지는 턴에 온 말: 막힌 횟수가 이어진다 (새로 세면 끝없이 막을 수 있다)
reset; start; ed
v1="$(verdict)"
start "빨리 해"
v2="$(verdict)"; v3="$(verdict)"
[[ "$v1 $v2 $v3" == "block block pass-unrecorded" ]] && ok "T40 막힌 뒤 온 말 → 막힌 횟수 이어짐 (block · block · pass-unrecorded)" || bad "T40 $v1 $v2 $v3"

# T41 — 세션을 다시 열면 앞 턴은 끝난 것: 다음 말은 새 턴. 압축은 턴 도중이라 이어 간다
#   세션 시작 훅을 실제로 부른다(이 저장소의 훅 · 이 코어).
ss() { printf '{"source":"%s","session_id":"s1"}' "$1" | CLAUDE_PLUGIN_ROOT="$CORE" bash "$SS_HOOK" >/dev/null 2>&1; }
reset; start "첫 요청"; ed
H "bash $PL progress p1 --step 1 --note '첫 일'"
ss resume
start "다시 열고 온 말"
W README.md; printf 'more\n' >> README.md
vRes="$(verdict)"
reset; start "첫 요청"; ed
H "bash $PL progress p1 --step 1 --note '첫 일'"
ss compact
start "압축 뒤에 온 말"
W README.md; printf 'more\n' >> README.md
vCom="$(verdict)"
[[ "$vRes $vCom" == "block pass" ]] && ok "T41 다시 연 세션의 말 → 새 턴(block), 압축 뒤의 말 → 같은 턴(pass)" || bad "T41 resume=$vRes compact=$vCom"

# T42 — 순수 함수: 시작 방식 · 요청 글 잇기 · 세션 열기의 종류
t42="$(scv_tc_start_mode 1 0)|$(scv_tc_start_mode 1 1)|$(scv_tc_start_mode 0 0)|$(scv_tc_start_mode 0 1)|$(scv_tc_start_mode)"
[[ "$t42" == "continue|fresh|fresh|fresh|fresh" ]] && ok "T42 시작 방식: 번호가 있고 끝 표시가 없을 때만 이어 감" || bad "T42 방식 [$t42]"
long="$(printf 'a%.0s' $(seq 1 3990))"
j="$(scv_tc_req_join "$long" "0123456789abcdefghij" 4000)"
[[ "$(scv_tc_req_join "" "새 말" 4000)" == "새 말" && "$(scv_tc_req_join "앞 말" "" 4000)" == "앞 말" && ${#j} -eq 4000 && "$j" == "$long"* ]] \
  && ok "T42 요청 글 잇기: 빈 쪽은 그대로, 4,000자에서 자름" || bad "T42 잇기 len=${#j}"
t42="$(scv_tc_session_closes startup)$(scv_tc_session_closes resume)$(scv_tc_session_closes compact)$(scv_tc_session_closes clear)$(scv_tc_session_closes "")"
[[ "$t42" == "11000" ]] && ok "T42 세션 열기: 새로 열기 · 다시 열기만 앞 턴을 끝냄" || bad "T42 세션 [$t42]"
reset

if [[ $fail -ne 0 ]]; then echo "test-turn-plan-check: FAIL" >&2; exit 1; fi
echo "test-turn-plan-check: all passed"
