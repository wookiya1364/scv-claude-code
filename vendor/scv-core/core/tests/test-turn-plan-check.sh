#!/usr/bin/env bash
# test-turn-plan-check.sh — 턴 끝 계획 기록 검사(turn-check.sh)와 plan-link progress · exempt 를 본다
# (계획 20261109-wookiya1364-turn-plan-check · TESTS.md T1 ~ T12 · T15).
#
# 2026-11-09 시제품으로 잰 장면을 그대로 고정한다: 기록 없음 막힘(A) · append 통과(B) · progress 통과(P) ·
# 가짜 기록 여섯 가지 막힘(C · H · H2 · H3 · J · B2) · 엉터리 내용은 통과하되 원문이 붙음(K) ·
# 이번 턴 것만(D · D2 · E · F) · scv/ 밖 문서 · git 아닌 폴더 · 작업 공간의 다른 저장소 · 릴리스 예외 ·
# 2번 막히면 통과 + 기록 없음 · 선택 답 기록 · 끄기. T13(네 세션 다시 세기)은 로컬 기록이라 측정 단계, T14 는 scv-mods.
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
H "bash $PL progress p1 --step 2 --note '2인 적 배수'"
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

if [[ $fail -ne 0 ]]; then echo "test-turn-plan-check: FAIL" >&2; exit 1; fi
echo "test-turn-plan-check: all passed"
