#!/usr/bin/env bash
# test-plan-link.sh — 계획 밖 요구를 계획 파일에 남기는 plan-link.sh 를 본다
# (계획 20261109-wookiya1364-plan-pause-and-return · TESTS.md T1 ~ T9).
#
# T1 같은 목표 → 단계 넣기 · T2 다른 목표 → A 보류 + B 연결 · T3 앞쪽 충돌 · T4 B 끝 → A 복귀
# T5 뒤쪽 충돌 · T6 여러 겹 역순 복귀 · T7 다시 하기 단계 · T8 frontmatter 검사가 paused 를 받음
# T9 맥 · 리눅스는 이 파일을 두 곳에서 돌려 본다(CI 는 리눅스). T10(패널)은 scv-mods 저장소의 시험.
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

# 덧붙임 — 절차 글이 스크립트를 부른다
w="$CORE/protocols/work.md"; h="$CORE/protocols/help/full.md"; p="$CORE/template/scv/PROMOTE.md"
if grep -q 'plan-link.sh resume' "$w" && grep -q 'plan-link.sh pause' "$w" && grep -q 'plan-link.sh append' "$w" \
   && grep -q 'plan-link.sh' "$h" && grep -q 'paused_by' "$p" && grep -q 'return_to' "$p" && grep -q '변경 이력' "$p"; then
  ok "protocols — work (pause · append · resume), help, PROMOTE.md (paused_by · return_to · 변경 이력)"
else bad "protocols do not call plan-link.sh / document the fields"; fi

if [[ $fail -ne 0 ]]; then echo "test-plan-link: FAIL" >&2; exit 1; fi
echo "test-plan-link: all passed"
