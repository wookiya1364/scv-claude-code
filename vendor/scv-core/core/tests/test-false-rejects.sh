#!/usr/bin/env bash
# test-false-rejects.sh — 막지 말아야 할 셋이 통과하고, 막아야 할 것은 그대로 막히는지 본다
# (계획 20261111-wookiya1364-false-rejects-three · TESTS.md T1 ~ T12).
#
# 2026-11-10 세션에서 실제로 겪은 것을 고정한다: 기록 폴더(scv/raw · scv/journal)를 다른 저장소로 연결해 둔
# 프로젝트에서 기록 파일만 바꾼 턴이 막힘 · 진행 메모가 '하지 않음' 항목과 낱말 하나 겹쳐 거절됨 ·
# 연결된 원자료 폴더를 옮기기(consume)가 거절하고 쓰지 않은 원자료 목록이 비어 나옴.
# SCV_TEST_CORE 로 다른 core 폴더(고치기 전 사본)를 가리키면 그 사본으로 돈다 — 재현(빨강) 확인용.
set -uo pipefail

CORE="${SCV_TEST_CORE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TC="$CORE/scripts/turn-check.sh"
PL="$CORE/scripts/plan-link.sh"
RP="$CORE/scripts/readpath.sh"
# shellcheck source=../scripts/lib/plan-link.sh
source "$CORE/scripts/lib/plan-link.sh"
# shellcheck source=../scripts/lib/turn-check.sh
source "$CORE/scripts/lib/turn-check.sh"
WORK="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$WORK"' EXIT
export SCV_TODAY=2026-11-11
unset PROMOTE_DIR ARCHIVE_DIR SCV_JOURNAL_DIR SCV_WORKSPACE_REPOS SCV_TURN_PLAN_CHECK RAW_DIR STATE_FILE 2>/dev/null || true
# 낱말 판정은 글자로 나눈다 — 함수를 바로 부르는 시험은 plan-link.sh 처럼 UTF-8 지역 설정을 고른다
_x='가'; for _l in "" C.UTF-8 en_US.UTF-8 ko_KR.UTF-8; do [[ -n "$_l" ]] && { LC_ALL="$_l"; } 2>/dev/null; (( ${#_x} == 1 )) && break; done; export LC_ALL="${LC_ALL:-}"
TD="$WORK/turn"; mkdir -p "$TD"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

# ── 연결된 기록 폴더: 저장소 A 의 scv/raw · scv/journal 이 저장소 B 안 폴더를 가리킨다 ──
A="$WORK/a"; B="$WORK/b"
mkdir -p "$A/scv/promote/p1" "$A/src" "$B/rec/raw" "$B/rec/journal" "$B/other"
( cd "$B" && git init -q . && git config user.email t@t && git config user.name t && printf 'k\n' > rec/raw/.gitkeep && printf 'k\n' > rec/journal/.gitkeep && printf 'o\n' > other/y.sh && git add -A && git commit -qm init )
cd "$A" || exit 1
git init -q . && git config user.email t@t && git config user.name t
ln -s ../../b/rec/raw scv/raw; ln -s ../../b/rec/journal scv/journal
printf -- '---\ntitle: 시험 계획\nslug: p1\nstatus: in_progress\n---\n\n# 시험 계획\n\n## Goals / Non-Goals\n\n- **Goals**\n  - 결제 버튼\n- **Non-Goals**\n  - 환불 기능\n\n## Suggested path\n\n1. 하나\n2. 둘\n\n## Links\n' > scv/promote/p1/PLAN.md
printf 'a\n' > src/a.sh
git add -A && git commit -qm init
start() { printf '%s' "${1:-기록만 남겨라}" | bash "$TC" start --dir "$TD"; }
W() { bash "$TC" touch --dir "$TD" --kind write "$1"; }
SH() { bash "$TC" touch --dir "$TD" --kind shell; }

# T1 — 원자료 파일(쓰기 도구)과 저널 상태 파일(셸)만 쓴 턴 → 막지 않음
start
W scv/raw/x.md; printf 'x\n' > scv/raw/x.md
SH; printf 's\n' > scv/journal/.state
out="$(bash "$TC" end --dir "$TD")"
if grep -qx 'TURN_PLAN: pass' <<<"$out" && ! grep -q '^TURN_PLAN_REASON: ' <<<"$out"; then ok "T1 연결된 기록 폴더 안 파일만 → pass"
else bad "T1 $(tr '\n' '|' <<<"$out" | cut -c1-300)"; fi

# T2 — 기록 파일과 코드 파일을 함께 → 코드 파일 1개로 막힘
( cd "$B" && git add -A && git commit -qm rec ) >/dev/null 2>&1
start "코드도 고쳐라"
W scv/raw/y.md; printf 'y\n' > scv/raw/y.md
W src/a.sh; printf 'b\n' >> src/a.sh
out="$(bash "$TC" end --dir "$TD")"
if grep -qx 'TURN_PLAN: block' <<<"$out" && grep -q '파일 1개' <<<"$out"; then ok "T2 코드 파일도 바꿈 → block, 파일 1개"
else bad "T2 $(tr '\n' '|' <<<"$out" | cut -c1-300)"; fi

# T2b — 연결된 저장소의 기록 폴더 밖 파일은 여전히 센다
git checkout -q -- src/a.sh
start "다른 저장소 고쳐라"
W "$B/other/y.sh"; printf 'z\n' >> "$B/other/y.sh"
out="$(bash "$TC" end --dir "$TD")"
if grep -qx 'TURN_PLAN: block' <<<"$out" && grep -q '파일 1개' <<<"$out"; then ok "T2b 기록 폴더 밖(other/y.sh)은 센다 → block"
else bad "T2b $(tr '\n' '|' <<<"$out" | cut -c1-300)"; fi

# T4 — 뺄 글롭: 실제 경로가 저장소 뿌리 아래일 때만, 그 아래만
g="$(scv_tc_record_globs "/b" $'/b/rec/raw\n/b/rec/journal\n/x/y')"
f="$(scv_tc_filter $'rec/raw/x.md\nother/y.sh\nsrc/a.sh' "$g")"
if [[ "$g" == 'rec/raw/*:rec/journal/*' && "$f" == $'other/y.sh\nsrc/a.sh' ]]; then ok "T4 글롭 rec/raw/* · rec/journal/* → 남는 것 2줄"
else bad "T4 g=[$g] f=[$f]"; fi
[[ -z "$(scv_tc_record_globs "/b" "")" && "$(scv_tc_record_globs "/b" "/b")" == '*' ]] && ok "T4b 빈 값 · 뿌리 자체" || bad "T4b"

# T5 — 2026-11-10 세션에서 실제로 거절됐던 메모(세션 기록에서 확인된 3건 + 같은 일의 메모 1건) → 충돌 0건
NG=$'## Goals / Non-Goals\n\n- **Goals**\n  - 다시 쓰기는 가이드만\n- **Non-Goals**\n  - 권장 effort 를 묻는 일(따로 계획한다).\n  - 답 모양 같은 output 규칙의 내용을 바꾸는 일.\n  - SCV 자신의 안내문 · 절차 문서의 다른 부분(금지 규칙 · 물음 자리 · 위임 지시).\n  - 코덱스 래퍼에 가이드를 넣는 일. 코어 변경(G1–G3 · G6)은 코덱스에도 함께 적용된다.\n  - 공통 가이드 전문을 읽히는 일(측정에서 발췌보다 나은 점이 없었다).\n  - 다시 쓰기 자체를 없애는 일(측정으로 가릴 수 없었다).\n  - 순수함수 성능 계획.\n\n## Suggested path\n\n1. 하나\n'
n5=0
for note in "turn_block 문구 고침, 문서 맞추는 중" \
            "관련 시험 9개 파일을 새 모양에 맞춤, 새 시험 14개 통과, 전체 시험 실행 중" \
            "TEMPLATE_DIGEST 다시 계산" \
            "안내문 · 거절 문구에서 항목 표 문구 뺌, 문서 맞추는 중"; do
  [[ -z "$(scv_tc_nongoal_hits "$NG" "$note")" ]] && n5=$((n5 + 1)) || echo "  아직 충돌: $note" >&2
done
[[ $n5 == 4 ]] && ok "T5 실제로 거절됐던 메모 4/4 통과" || bad "T5 $n5/4"

# T6 — 문서에 적힌 진짜 충돌은 그대로
h="$(scv_tc_nongoal_hits $'## Goals / Non-Goals\n- **Goals**\n  - 결제 버튼\n- **Non-Goals**\n  - 환불 기능' "환불 버튼 추가")"
[[ "$h" == '충돌 · 하지 않기로 함: 환불 기능 ↔ 적으려는 글: 환불 버튼 추가' ]] && ok "T6 환불 기능 ↔ 환불 버튼 추가 → 충돌 1줄" || bad "T6 [$h]"
# 긴 항목이어도 그 일을 그대로 적으면 잡힌다
h="$(scv_tc_nongoal_hits "$NG" "다시 쓰기 자체를 없애는 일을 시작")"
[[ -n "$h" ]] && ok "T6b 항목을 그대로 적은 글 → 충돌" || bad "T6b"

# T7 — 절반 경계
[[ "$(scv_tc_overlap_count "가나 다라 마바 사아" "가나 사아 자차")" == "2 4" && "$(scv_tc_overlap_count "가나 다라 마바 사아" "가나 자차")" == "1 4" ]] \
  && ok "T7 겹친 수: 2 4 · 1 4" || bad "T7 count"
P4=$'## Goals / Non-Goals\n- **Non-Goals**\n  - 가나 다라 마바 사아'
[[ -n "$(scv_tc_nongoal_hits "$P4" "가나 사아 자차")" && -z "$(scv_tc_nongoal_hits "$P4" "가나 자차")" ]] \
  && ok "T7b 4개 중 2개 → 충돌, 4개 중 1개 → 통과" || bad "T7b"

# T8 — plan-link progress · append 의 종료 코드
PDIR="$WORK/pl"; mkdir -p "$PDIR/scv/promote/p2"; cd "$PDIR" || exit 1
git init -q . && git config user.email t@t && git config user.name t
printf -- '---\ntitle: 시험\nslug: p2\nstatus: in_progress\n---\n\n# 시험\n\n%s\n## Links\n' "$NG" > scv/promote/p2/PLAN.md
sed -i.bak 's/^1\. 하나$/1. 하나\n2. 둘/' scv/promote/p2/PLAN.md 2>/dev/null; rm -f scv/promote/p2/PLAN.md.bak
printf '\n- **Non-Goals**\n  - 환불 기능\n' >/dev/null
before="$(cat scv/promote/p2/PLAN.md)"
bash "$PL" progress p2 --step 1 --state doing --note "TEMPLATE_DIGEST 다시 계산" >/dev/null 2>&1; rc1=$?
n1="$(grep -c '^- \*\*2026-11-11 진행\*\* — 1단계' scv/promote/p2/PLAN.md)"
mid="$(cat scv/promote/p2/PLAN.md)"
bash "$PL" progress p2 --step 1 --state doing --note "순수함수 성능 계획" >/dev/null 2>&1; rc2=$?
bash "$PL" append p2 --after 1 --step "순수함수 성능 계획" --why "x" >/dev/null 2>&1; rc3=$?
if [[ $rc1 == 0 && "$n1" == 1 && $rc2 == 3 && $rc3 == 3 && "$(cat scv/promote/p2/PLAN.md)" == "$mid" && "$mid" != "$before" ]]; then ok "T8 메모 통과(0 · 진행 줄 1개) · 진짜 충돌은 3 이고 파일 그대로"
else bad "T8 rc=$rc1/$rc2/$rc3 n1=$n1"; fi

# ── 원자료 폴더 뿌리가 연결 ──
C="$WORK/c"; mkdir -p "$C/scv" "$WORK/recs/raw" "$WORK/outside"
cd "$C" || exit 1
git init -q . && git config user.email t@t && git config user.name t
ln -s ../../recs/raw scv/raw
printf '# 원자료\n' > scv/raw/a.md; printf '# 둘\n' > scv/raw/b.md
git add -A >/dev/null 2>&1; git commit -qm init >/dev/null 2>&1

# T11 — 쓰지 않은 원자료 목록에 보임
u="$(bash "$RP" unused 2>/dev/null)"
grep -q 'scv/raw/a\.md' <<<"$u" && grep -q 'scv/raw/b\.md' <<<"$u" && ok "T11 연결된 뿌리 — unused 에 a.md · b.md" || bad "T11 [$u]"

# T9 — 옮기기 성공
out="$(bash "$RP" consume slug-one scv/raw/a.md 2>&1)"; rc=$?
if [[ $rc == 0 ]] && grep -q $'^MOVED\tscv/raw/a.md\tscv/raw/stale/a.md' <<<"$out" && [[ "$(cat scv/raw/stale/a.md 2>/dev/null)" == '# 원자료' && ! -e scv/raw/a.md ]] \
   && grep -q 'slug-one' scv/readpath.json; then ok "T9 연결된 뿌리 — MOVED · 내용 그대로 · readpath.json 에 slug"
else bad "T9 rc=$rc $out"; fi

# T10 — 뿌리 아래 하위 폴더가 연결 → 거절
ln -s "$WORK/outside" scv/raw/sub; printf 'z\n' > "$WORK/outside/z.md"
out="$(bash "$RP" consume slug-two scv/raw/sub/z.md 2>&1)"; rc=$?
if [[ $rc == 1 ]] && grep -q 'refusing symlinked path component' <<<"$out" && [[ -f "$WORK/outside/z.md" ]]; then ok "T10 뿌리 아래 연결 → 거절(1), 안 옮김"
else bad "T10 rc=$rc $out"; fi
# stale 이 밖을 가리키는 연결이어도 거절
rm -f scv/raw/sub; rm -rf scv/raw/stale; ln -s "$WORK/outside" scv/raw/stale
out="$(bash "$RP" consume slug-three scv/raw/b.md 2>&1)"; rc=$?
if [[ $rc == 1 ]] && grep -q 'refusing symlinked path component' <<<"$out" && [[ -f scv/raw/b.md ]]; then ok "T10b stale 이 연결 → 거절(1)"
else bad "T10b rc=$rc $out"; fi

# below_raw_root — 순수
( RAW_DIR=scv/raw; eval "$(sed -n '/^below_raw_root() {/,/^}/p' "$RP")"
  [[ "$(below_raw_root scv/raw/sub/a.md scv/raw)" == "sub/a.md" && -z "$(below_raw_root scv/raw scv/raw)" && "$(below_raw_root x/y scv/raw)" == "x/y" ]] ) \
  && ok "T10c below_raw_root 세 경우" || bad "T10c"

[[ $fail == 0 ]] && echo "ALL PASS (test-false-rejects)" || { echo "FAILED (test-false-rejects)" >&2; exit 1; }
