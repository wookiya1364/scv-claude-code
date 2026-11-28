#!/usr/bin/env bash
# test-plan-link.sh — 계획 밖 요구를 계획 파일에 남기는 plan-link.sh 를 본다
# (계획 20261109-wookiya1364-plan-pause-and-return · TESTS.md T1 ~ T9).
#
# T1 같은 목표 → 단계 넣기 · T2 다른 목표 → A 보류 + B 연결 · T3 앞쪽 충돌 · T4 B 끝 → A 복귀
# T5 뒤쪽 충돌 · T6 여러 겹 역순 복귀 · T7 다시 하기 단계 · T8 frontmatter 검사가 paused 를 받음
# T9 맥 · 리눅스는 이 파일을 두 곳에서 돌려 본다(CI 는 리눅스). T10(패널)은 scv-mods 저장소의 시험.
# T20 ~ T25 두 일을 가르고 합친다(계획 20261127-wookiya1364-dashboard-motion-cards-two-jobs).
# 덧붙임: 절차 글(work · help · PROMOTE.md)이 스크립트를 부르는지.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PL="$CORE/scripts/plan-link.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export PROMOTE_DIR="$WORK/promote" ARCHIVE_DIR="$WORK/archive" SCV_TODAY=2026-11-09
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

# 계획 하나를 만든다: <이름> <status> <제목> [<Non-Goals 항목>] [<Goals 항목>] [단계 줄…]
mk() {
  local slug="$1" st="$2" title="$3" ng="${4:-}" goal="${5:-}"; shift 5 || shift $#
  mkdir -p "$PROMOTE_DIR/$slug"
  {
    printf -- '---\ntitle: %s\nslug: %s\nauthor: t\ncreated_at: 2026-11-09\nstatus: %s\ntags: []\n---\n\n# %s\n\n' "$title" "$slug" "$st" "$title"
    printf '## Goals / Non-Goals\n\n- **Goals**\n'
    [[ -n "$goal" ]] && printf '  - %s\n' "$goal"
    printf -- '- **Non-Goals**\n'
    [[ -n "$ng" ]] && printf '  - %s\n' "$ng"
    printf '\n## Suggested path\n\n'
    local i=1 s; for s in "$@"; do printf '%d. %s\n' "$i" "$s"; i=$((i + 1)); done
    printf '\n## Links\n'
  } > "$PROMOTE_DIR/$slug/PLAN.md"
}
fm() { awk -v k="$2" 'NR>1 && /^---$/ {exit} $0 ~ "^"k":" {sub("^"k":[ ]*",""); print}' "$1"; }
reset() { rm -rf "$PROMOTE_DIR" "$ARCHIVE_DIR"; mkdir -p "$PROMOTE_DIR" "$ARCHIVE_DIR"; }

# T1 — 같은 목표: 단계 넣기, 이력 한 사건, 끝난 단계 글 그대로, 파일 끝 줄바꿈 그대로
reset
mk a in_progress "결제 화면" "" "" "[x] 준비 — 폴더" "화면 만들기 — x" "시험 — 시험 돌리기"
before1="$(grep -n '^1\. ' "$PROMOTE_DIR/a/PLAN.md")"
rc=0; out="$(bash "$PL" append a --after 2 --step "버튼 색 — y" --why "같은 목표" 2>&1)" || rc=$?
f="$PROMOTE_DIR/a/PLAN.md"
steps="$(grep -cE '^[0-9]+\. ' "$f")"
if [[ $rc == 0 && $steps == 4 && "$(grep -n '^1\. ' "$f")" == "$before1" ]] \
   && grep -qx '3. 버튼 색 — y' "$f" && grep -qx '4. 시험 — 시험 돌리기' "$f" \
   && [[ "$(grep -c '^- \*\*2026-11-09 추가\*\* — 2단계 뒤에 새 단계$' "$f")" == 1 ]] \
   && grep -qx '  - 이유: 같은 목표' "$f" && [[ "$(tail -c 1 "$f" | od -An -c | tr -d ' ')" == '\n' ]]; then
  ok "T1 step 3 inserted, old 3 → 4, step 1 line identical, one 추가 entry, trailing newline kept"
else bad "T1 rc=$rc steps=$steps out=$out"; sed 's/^/    /' "$f" >&2; fi

# T2 — 다른 목표: A 보류 + B 연결
reset
mk a in_progress "결제 화면" "" "" "[x] 준비 — 폴더" "화면 만들기 — x" "시험 — 시험 돌리기"
mk b planned "로그 정리" "" "로그 줄이기"
rc=0; out="$(bash "$PL" pause a --by b --resume-at 2 --why "다른 목표" 2>&1)" || rc=$?
A="$PROMOTE_DIR/a/PLAN.md"; B="$PROMOTE_DIR/b/PLAN.md"
if [[ $rc == 0 && "$(fm "$A" status)" == paused && "$(fm "$A" paused_by)" == b && "$(fm "$A" resume_at)" == 2 \
      && "$(fm "$B" return_to)" == a && "$(fm "$B" status)" == planned ]] \
   && grep -qx -- '- \*\*2026-11-09 보류\*\* — 먼저 할 계획: 로그 정리' "$A" && grep -qx '  - 다시 시작: 2단계부터' "$A" \
   && grep -qx -- '- \*\*2026-11-09 연결\*\* — 끝나면 돌아갈 계획: 결제 화면' "$B"; then
  ok "T2 A paused (by b · resume 2) with 보류 entry, B return_to a with 연결 entry"
else bad "T2 rc=$rc out=$out"; fi
rc=0; bash "$PL" pause a --by b --resume-at 2 --why x >/dev/null 2>&1 || rc=$?
[[ $rc == 1 ]] && ok "T2 pausing an already-paused plan is refused (exit 1)" || bad "T2 second pause rc=$rc"

# T3 — 앞쪽 충돌: A Non-Goals ↔ B Goals
reset
mk a in_progress "결제 화면" "결제 한도 변경 안 함" "" "[x] 준비 — 폴더" "화면 만들기 — x"
mk b planned "한도 손보기" "" "결제 한도 변경"
cp "$PROMOTE_DIR/a/PLAN.md" "$WORK/a.before"; cp "$PROMOTE_DIR/b/PLAN.md" "$WORK/b.before"
rc=0; out="$(bash "$PL" check-before a b 2>&1)" || rc=$?
rc2=0; out2="$(bash "$PL" pause a --by b --resume-at 2 --why x 2>&1)" || rc2=$?
if [[ $rc == 3 && "$(printf '%s\n' "$out" | grep -c '^충돌 · ')" == 1 && $rc2 == 3 ]] \
   && cmp -s "$PROMOTE_DIR/a/PLAN.md" "$WORK/a.before" && cmp -s "$PROMOTE_DIR/b/PLAN.md" "$WORK/b.before"; then
  ok "T3 one conflict line, exit 3; pause without --accept-conflict also stops (exit 3); A · B unchanged"
else bad "T3 rc=$rc rc2=$rc2 out=$out"; fi
rc=0; bash "$PL" pause a --by b --resume-at 2 --why x --accept-conflict >/dev/null 2>&1 || rc=$?
[[ $rc == 0 && "$(fm "$PROMOTE_DIR/a/PLAN.md" status)" == paused ]] \
  && ok "T3 after the user's answer, --accept-conflict pauses" || bad "T3 accept rc=$rc"

# T4 — B 가 끝나면(보관) A 로 복귀
reset
mk a in_progress "결제 화면" "" "" "[x] 준비 — 폴더" "화면 만들기 — x"
mk b planned "로그 정리" "" "로그 줄이기"
bash "$PL" pause a --by b --resume-at 2 --why "다른 목표" >/dev/null
mv "$PROMOTE_DIR/b" "$ARCHIVE_DIR/b"
rc=0; out="$(SCV_TODAY=2026-11-10 bash "$PL" resume b 2>&1)" || rc=$?
A="$PROMOTE_DIR/a/PLAN.md"
if [[ $rc == 0 && "$(fm "$A" status)" == in_progress && -z "$(fm "$A" paused_by)" ]] \
   && ! grep -q '^resume_at:' "$A" && ! grep -q '^paused_by:' "$A" \
   && grep -qx -- '- \*\*2026-11-10 재개\*\* — 끝난 계획: 로그 정리' "$A" && grep -qx '  - 다시 시작: 2단계부터' "$A"; then
  ok "T4 A back to in_progress, paused keys gone, 재개 entry (2단계부터)"
else bad "T4 rc=$rc out=$out"; fi

# T5 — 뒤쪽 충돌: B 가 바꾼 파일 ↔ A 의 남은 단계
reset
mk a in_progress "결제 화면" "" "" "[x] core/scripts/x.sh 준비" "core/scripts/x.sh 다룸"
mk b planned "로그 정리" "" "로그 줄이기"
bash "$PL" pause a --by b --resume-at 2 --why x >/dev/null
cp "$PROMOTE_DIR/a/PLAN.md" "$WORK/a.before"
rc=0; out="$(bash "$PL" check-after b --changed core/scripts/x.sh --changed docs/y.md 2>&1)" || rc=$?
rc2=0; bash "$PL" resume b --changed core/scripts/x.sh >/dev/null 2>&1 || rc2=$?
if [[ $rc == 3 && "$out" == "겹침 · A 2단계 · core/scripts/x.sh" && $rc2 == 3 ]] && cmp -s "$PROMOTE_DIR/a/PLAN.md" "$WORK/a.before"; then
  ok "T5 one overlap (step 2 · core/scripts/x.sh, done step 1 ignored), resume stops, A unchanged"
else bad "T5 rc=$rc rc2=$rc2 out=$out"; fi

# T6 — 여러 겹: A 보류(by B), B 보류(by C) → resume C 는 B 만, resume B 는 A
reset
mk a in_progress "A 계획" "" "" "하나 — 1"
mk b in_progress "B 계획" "" "비" "하나 — 1"
mk c planned "C 계획" "" "씨"
bash "$PL" pause a --by b --resume-at 1 --why x >/dev/null
bash "$PL" pause b --by c --resume-at 1 --why y >/dev/null
s0="$(fm "$PROMOTE_DIR/a/PLAN.md" status)/$(fm "$PROMOTE_DIR/b/PLAN.md" status)"
mv "$PROMOTE_DIR/c" "$ARCHIVE_DIR/c"; bash "$PL" resume c >/dev/null
s1="$(fm "$PROMOTE_DIR/a/PLAN.md" status)/$(fm "$PROMOTE_DIR/b/PLAN.md" status)"
mv "$PROMOTE_DIR/b" "$ARCHIVE_DIR/b"; bash "$PL" resume b >/dev/null
s2="$(fm "$PROMOTE_DIR/a/PLAN.md" status)"
if [[ "$s0" == paused/paused && "$s1" == paused/in_progress && "$s2" == in_progress ]]; then
  ok "T6 statuses paused/paused → paused/in_progress → in_progress (C → B → A)"
else bad "T6 s0=$s0 s1=$s1 s2=$s2"; fi

# T7 — 끝난 단계 요건이 바뀌면 다시 하기 단계
reset
mk a in_progress "결제 화면" "" "" "[x] 검사 추가 — \`checkA\`" "화면 — x"
line1="$(grep '^1\. ' "$PROMOTE_DIR/a/PLAN.md")"
rc=0; bash "$PL" append a --redo 1 --why "요건 바뀜" >/dev/null 2>&1 || rc=$?
f="$PROMOTE_DIR/a/PLAN.md"
if [[ $rc == 0 && "$(grep '^1\. ' "$f")" == "$line1" && "$(grep -cE '^[0-9]+\. ' "$f")" == 3 ]] \
   && grep -qx '3. 다시 하기: 검사 추가 — `checkA`' "$f" \
   && grep -qx -- '- \*\*2026-11-09 다시 하기\*\* — 1단계를 바뀐 요건으로 다시 함' "$f"; then
  ok "T7 step 1 line identical, 3. 다시 하기 keeps the step's tail, 다시 하기 entry"
else bad "T7 rc=$rc"; sed 's/^/    /' "$f" >&2; fi

# T8 — frontmatter 검사가 paused 를 받고 오타는 막는다
reset
mk a paused "A" "" "" "하나 — 1"
mk z pausd "Z" "" "" "하나 — 1"
r1=0; bash "$CORE/scripts/check-frontmatter.sh" --plan "$PROMOTE_DIR/a/PLAN.md" >/dev/null 2>&1 || r1=$?
r2=0; bash "$CORE/scripts/check-frontmatter.sh" --plan "$PROMOTE_DIR/z/PLAN.md" >/dev/null 2>&1 || r2=$?
[[ $r1 == 0 && $r2 != 0 ]] && ok "T8 status: paused valid (exit 0), status: pausd invalid (exit $r2)" || bad "T8 r1=$r1 r2=$r2"

# ── 두 일을 가르고 합친다 (계획 20261127-wookiya1364-dashboard-motion-cards-two-jobs · TESTS.md T20 ~ T25) ──
# 시험용 저장소: 체력(hp.txt) ÷ 한 대 피해(dmg.txt)를 "보스: N" 으로 찍는 확인 명령. 계획 폴더는 저장소 밖에 둔다.
REPO="$WORK/repo"
g() { git -C "$REPO" "$@"; }
mkrepo() {
  rm -rf "$REPO" "$WORK"/repo.split-*; mkdir -p "$REPO"
  git -C "$REPO" init -q
  g checkout -q -b main 2>/dev/null || true
  g config user.name t; g config user.email t@example.com
  printf '1000\n' > "$REPO/hp.txt"; printf '100\n' > "$REPO/dmg.txt"; printf '메모\n' > "$REPO/notes.txt"; printf '옛 파일\n' > "$REPO/old.txt"
  printf 'echo "보스: $(( $(cat hp.txt) / $(cat dmg.txt) ))"\n' > "$REPO/check.sh"
  g add -A; g commit -q -m init
}
# 계획의 확인 명령(TESTS.md 의 실행 블록)을 적는다: <이름> <명령>
mktests() { printf '# Tests\n\n## How to run\n\n```bash\n%s\n```\n' "$2" > "$PROMOTE_DIR/$1/TESTS.md"; }
# 진행 중인 계획 a(체력) · 새 계획 b(피해), 원래 폴더에 커밋하지 않은 변경 둘(고친 파일 · 새 파일)
split_setup() {
  reset; mkrepo
  mk a in_progress "보스 체력" "" "" "[x] 준비 — 폴더" "hp.txt 다듬기 — x" "시험 — 시험 돌리기"
  mk b planned "한 대 피해" "" "피해 올리기" "dmg.txt 고치기 — y"
  mktests a "bash check.sh"
  printf '메모\n고치는 중\n' > "$REPO/notes.txt"; printf '새 파일\n' > "$REPO/new.txt"
  A="$PROMOTE_DIR/a/PLAN.md"; B="$PROMOTE_DIR/b/PLAN.md"; D="$(cd "$WORK" && pwd -P)/repo.split-a"
}
split_ab() { (cd "$REPO" && SCV_NOW='2026-11-09 10:30' bash "$PL" split a --with b --at 2 --files dmg.txt --why "다른 목표" 2>&1); }
join_a() { (cd "$REPO" && SCV_NOW='2026-11-09 11:00' bash "$PL" join a 2>&1); }
nsteps() { grep -cE '^[0-9]+\. ' "$1"; }

# T20 — 겹치지 않는 두 일을 가른다: 폴더와 가지가 하나씩 생기고, 원래 폴더는 그대로이고, 확인 결과가 남는다
split_setup
st0="$(g status --porcelain)"; head0="$(g rev-parse HEAD)"
rc=0; out="$(split_ab)" || rc=$?
if [[ $rc == 0 && "$(g worktree list | wc -l | tr -d ' ')" == 2 && "$(g status --porcelain)" == "$st0" && "$(g rev-parse HEAD)" == "$head0" ]] \
   && [[ -d "$D" ]] && grep -qx '고치는 중' "$D/notes.txt" && [[ -f "$D/new.txt" ]] \
   && [[ "$(g branch --list 'scv-split/a' | wc -l | tr -d ' ')" == 1 ]] \
   && grep -qx '보스: 10' "$PROMOTE_DIR/a/split-result.txt" \
   && [[ "$(fm "$A" split_with)" == b && "$(fm "$A" split_at)" == 2 && "$(fm "$A" split_on)" == '2026-11-09 10:30' && "$(fm "$A" split_dir)" == ../repo.split-a ]] \
   && [[ -n "$(fm "$A" split_base)" && "$(fm "$A" split_branch)" == scv-split/a && "$(fm "$A" status)" == in_progress ]] \
   && [[ "$(fm "$B" split_with)" == a && "$(fm "$B" split_on)" == '2026-11-09 10:30' && -z "$(fm "$B" split_dir)" ]] \
   && grep -qx -- '- \*\*2026-11-09 가름\*\* — 함께 하는 일: 한 대 피해' "$A" && grep -qx '  - 가른 단계: 2단계' "$A" \
   && grep -qx '  - 이 일의 자리: 따로 만든 폴더 ../repo.split-a' "$A" && ! grep -q "$WORK" "$A" "$B" \
   && grep -qx -- '- \*\*2026-11-09 가름\*\* — 함께 하는 일: 보스 체력' "$B"; then
  ok "T20 split: one folder + one branch, uncommitted work is in the folder, the original tree and HEAD untouched, result kept (보스: 10), both plans name each other"
else bad "T20 rc=$rc out=$out"; sed 's/^/    /' "$A" >&2; fi

# T21 — 같은 파일을 고치는 두 일 · 고칠 파일을 모르는 일은 가르지 않는다
split_setup
cp "$A" "$WORK/a.before"; cp "$B" "$WORK/b.before"
rc=0; out="$(cd "$REPO" && bash "$PL" split a --with b --at 2 --files hp.txt --why x 2>&1)" || rc=$?
rc2=0; out2="$(cd "$REPO" && bash "$PL" split a --with b --at 2 --why x 2>&1)" || rc2=$?
if [[ $rc == 3 && "$(printf '%s\n' "$out" | grep -c '^겹침 · A 2단계 · hp.txt$')" == 1 && $rc2 == 3 && "$(printf '%s\n' "$out2" | grep -c '^알 수 없음 · ')" == 1 ]] \
   && [[ "$(g worktree list | wc -l | tr -d ' ')" == 1 && ! -e "$D" ]] && cmp -s "$A" "$WORK/a.before" && cmp -s "$B" "$WORK/b.before"; then
  ok "T21 no split: the same file (one overlap line) and an unknown file list (one line) both stop with exit 3, nothing made, plans unchanged"
else bad "T21 rc=$rc rc2=$rc2 out=$out out2=$out2"; fi

# T22 — 합친다: 같은 줄 충돌 없음 · 달라진 결과 1개 → 다시 하기 단계
split_setup; split_ab >/dev/null
printf 'A 가 이어서 한 일\n' > "$D/a-work.txt"
printf '200\n' > "$REPO/dmg.txt"; g add dmg.txt; g commit -q -m "피해 200"
steps0="$(nsteps "$A")"; head0="$(g rev-parse HEAD)"
rc=0; out="$(join_a)" || rc=$?
if [[ $rc == 0 && "$(printf '%s\n' "$out" | grep -cx '같은 줄 충돌 없음')" == 1 && "$(printf '%s\n' "$out" | grep -cx '달라진 결과 1개: 보스 10 → 5')" == 1 ]] \
   && [[ "$(nsteps "$A")" == $((steps0 + 1)) ]] && grep -q '^4\. 다시 하기: ' "$A" \
   && grep -q -- '^- \*\*2026-11-09 합침\*\* — 함께 한 일: 한 대 피해$' "$A" && grep -qx '  - 달라진 결과 1개: 보스 10 → 5' "$A" \
   && ! grep -q '^split_' "$A" && ! grep -q '^split_' "$B" \
   && [[ "$(fm "$A" joined_with)" == b && "$(fm "$A" joined_at)" == 2 && "$(fm "$A" joined_on)" == '2026-11-09 11:00' && "$(fm "$A" joined_changed)" == '보스 10 → 5' ]] \
   && [[ "$(fm "$A" joined_redo)" == 4 && -z "$(fm "$B" joined_redo)" ]] \
   && grep -qx 'A 가 이어서 한 일' "$REPO/a-work.txt" && grep -qx '고치는 중' "$REPO/notes.txt" && [[ -f "$REPO/new.txt" ]] \
   && [[ "$(g rev-parse HEAD)" == "$head0" && -d "$D" ]]; then
  ok "T22 join: no same-line conflict, one changed result (보스 10 → 5), a redo step added, split keys gone, the other side's work arrived, no commit made, the folder kept"
else bad "T22 rc=$rc out=$out"; sed 's/^/    /' "$A" >&2; fi

# T23 — 합친다: 달라진 결과 없음 → 다시 하기 단계 없음
split_setup; split_ab >/dev/null
printf 'A 가 이어서 한 일\n' > "$D/a-work.txt"; git -C "$D" rm -q old.txt; printf '문서\n' > "$REPO/readme.txt"
steps0="$(nsteps "$A")"
rc=0; out="$(join_a)" || rc=$?
if [[ $rc == 0 && "$(printf '%s\n' "$out" | grep -cx '달라진 결과 없음')" == 1 && "$(nsteps "$A")" == "$steps0" ]] \
   && grep -qx '  - 달라진 결과 없음' "$A" && [[ -z "$(fm "$A" joined_changed)" && -z "$(fm "$A" joined_redo)" ]] \
   && [[ ! -e "$REPO/old.txt" && -f "$REPO/readme.txt" && -f "$REPO/a-work.txt" ]]; then
  ok "T23 join with nothing changed: 달라진 결과 없음, no redo step; a file the other side removed is gone here too"
else bad "T23 rc=$rc out=$out"; fi

# T24 — 합친다: 같은 줄 충돌이면 아무것도 바꾸지 않고 멈춘다
split_setup; split_ab >/dev/null
printf '900\n' > "$D/hp.txt"; printf '800\n' > "$REPO/hp.txt"
cp "$A" "$WORK/a.before"; cp "$B" "$WORK/b.before"
st0="$(g status --porcelain)"; head0="$(g rev-parse HEAD)"
rc=0; out="$(join_a)" || rc=$?
if [[ $rc == 3 && "$(printf '%s\n' "$out" | grep -c '^충돌 · hp.txt$')" == 1 && "$(g status --porcelain)" == "$st0" && "$(g rev-parse HEAD)" == "$head0" ]] \
   && [[ "$(cat "$REPO/hp.txt")" == 800 ]] && cmp -s "$A" "$WORK/a.before" && cmp -s "$B" "$WORK/b.before"; then
  ok "T24 join with a same-line conflict: exit 3, the file named, the tree · HEAD · plans as before"
else bad "T24 rc=$rc out=$out"; fi

# T25 — 값이 없는 확인은 통과 여부만 비교하고, 그렇게 말한다
split_setup; mktests a "echo ok"
rc=0; out="$(split_ab)" || rc=$?
rc2=0; out2="$(join_a)" || rc2=$?
if [[ $rc == 0 && $rc2 == 0 && "$(printf '%s\n' "$out" | grep -c '비교할 값이 없음')" == 1 && "$(printf '%s\n' "$out2" | grep -c '비교할 값이 없음')" == 1 ]] \
   && [[ "$(printf '%s\n' "$out2" | grep -cx '달라진 결과 없음')" == 1 ]]; then
  ok "T25 a check with no values: both split and join say 비교할 값이 없음 (pass or fail only)"
else bad "T25 rc=$rc rc2=$rc2 out=$out out2=$out2"; fi

# T25b — 통과하던 확인이 합친 뒤 실패하면 달라진 결과로 잡는다
split_setup; mktests a "test ! -f fail.flag"
split_ab >/dev/null
printf 'A 가 이어서 한 일\n' > "$D/a-work.txt"; printf 'x\n' > "$REPO/fail.flag"
rc=0; out="$(join_a)" || rc=$?
if [[ $rc == 0 && "$(printf '%s\n' "$out" | grep -cx '달라진 결과 1개: 확인 명령 통과 → 실패')" == 1 ]] && grep -q '^4\. 다시 하기: ' "$A"; then
  ok "T25b a check that passed at the split and fails after the join is one changed result"
else bad "T25b rc=$rc out=$out"; fi

# 덧붙임 — 절차 글이 스크립트를 부른다
w="$CORE/protocols/work.md"; h="$CORE/protocols/help/full.md"; p="$CORE/template/scv/PROMOTE.md"
if grep -q 'plan-link.sh resume' "$w" && grep -q 'plan-link.sh pause' "$w" && grep -q 'plan-link.sh append' "$w" \
   && grep -q 'plan-link.sh split' "$w" && grep -q 'plan-link.sh join' "$w" \
   && grep -q 'plan-link.sh' "$h" && grep -q 'paused_by' "$p" && grep -q 'return_to' "$p" && grep -q '변경 이력' "$p"; then
  ok "protocols — work (pause · append · resume · split · join), help, PROMOTE.md (paused_by · return_to · 변경 이력)"
else bad "protocols do not call plan-link.sh / document the fields"; fi

if [[ $fail -ne 0 ]]; then echo "test-plan-link: FAIL" >&2; exit 1; fi
echo "test-plan-link: all passed"
