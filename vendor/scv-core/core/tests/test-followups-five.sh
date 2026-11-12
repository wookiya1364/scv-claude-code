#!/usr/bin/env bash
# test-followups-five.sh — 남은 일 다섯 마무리(계획 20261111-wookiya1364-followups-five)의 자동 시험.
#   T1~T4  저널 기록 명령: 이 컴퓨터에서 만든 저널 뿌리의 연결은 따라가고, 그 밖의 연결은 거절한다
# (effort 요청의 다시 싣기는 test-effort-ask.sh, 속도 시험은 두 시험 자신이 본다.)
#
# Run: bash core/tests/test-followups-five.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
JA="$CORE/scripts/journal-append.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/scv-fu5.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
unset SCV_JOURNAL_DIR 2>/dev/null || true
repo() {  # <이름> → git 저장소 경로(scv 폴더 포함)
  local d="$WORK/$1"; mkdir -p "$d/scv"; (cd "$d" && git init -q . && git config user.email t@t && git config user.name t); printf '%s' "$d"
}
day="$(date +%Y%m%d)"

echo "T1. 저널 뿌리가 이 컴퓨터에서 만든 연결(추적 안 됨) — 쓴다"
R="$(repo t1)"; mkdir -p "$WORK/rec1"; ln -s "$WORK/rec1" "$R/scv/journal"
( cd "$R" && bash "$JA" --author t --speaker user "한 줄" >/dev/null 2>&1 ); rc=$?
[[ $rc == 0 && "$(grep -c '한 줄' "$WORK/rec1/$day-t.md" 2>/dev/null)" == 1 ]] && ok "OK [T1] written through the local link" || fail "[T1] rc=$rc $(ls "$WORK/rec1")"

echo "T2. 저널 파일 자체가 연결 — 거절, 밖의 파일은 그대로"
R="$(repo t2)"; mkdir -p "$R/scv/journal" "$WORK/out2"; printf 'keep\n' > "$WORK/out2/victim.md"; ln -s "$WORK/out2/victim.md" "$R/scv/journal/$day-t.md"
( cd "$R" && bash "$JA" --author t --speaker user "x" >/dev/null 2>&1 ); rc=$?
[[ $rc != 0 && "$(cat "$WORK/out2/victim.md")" == keep ]] && ok "OK [T2] a linked journal file is refused" || fail "[T2] rc=$rc"

echo "T2b. 저장소가 추적하는 연결 · git 저장소가 아닌 곳 · 폴더가 아닌 곳을 가리키는 연결 — 거절"
c=0
R="$(repo t2b)"; mkdir -p "$WORK/out3"; ln -s "$WORK/out3" "$R/scv/journal"; ( cd "$R" && git add scv/journal >/dev/null 2>&1 && git commit -qm link >/dev/null 2>&1 )
( cd "$R" && bash "$JA" --author t --speaker user "x" >/dev/null 2>&1 ); [[ $? != 0 && -z "$(ls -A "$WORK/out3")" ]] && c=$((c + 1))
N="$WORK/nogit"; mkdir -p "$N/scv" "$WORK/out4"; ln -s "$WORK/out4" "$N/scv/journal"
( cd "$N" && GIT_CEILING_DIRECTORIES="$WORK" bash "$JA" --author t --speaker user "x" >/dev/null 2>&1 ); [[ $? != 0 && -z "$(ls -A "$WORK/out4")" ]] && c=$((c + 1))
R="$(repo t2c)"; printf 'f\n' > "$WORK/afile"; ln -s "$WORK/afile" "$R/scv/journal"
( cd "$R" && bash "$JA" --author t --speaker user "x" >/dev/null 2>&1 ); [[ $? != 0 && "$(cat "$WORK/afile")" == f ]] && c=$((c + 1))
[[ $c == 3 ]] && ok "OK [T2b] 3/3 refused" || fail "[T2b] $c/3"

echo "T4. 가림은 그대로 — 연결된 뿌리로 써도 비밀값이 남지 않는다"
R="$(repo t4)"; mkdir -p "$WORK/rec4"; ln -s "$WORK/rec4" "$R/scv/journal"
( cd "$R" && bash "$JA" --author t --speaker user "token=abc123SECRET" >/dev/null 2>&1 )
[[ -f "$WORK/rec4/$day-t.md" ]] && ! grep -q 'abc123SECRET' "$WORK/rec4/$day-t.md" && grep -q 'REDACTED' "$WORK/rec4/$day-t.md" && ok "OK [T4] redacted before the write" || fail "[T4]"

echo
echo "── $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
