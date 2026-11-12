#!/usr/bin/env bash
# test-wrapup.sh — 마무리 보고(WRAPUP.md)가 다 채워져야 보관되는지, 계획 없이 가는 빠른 길이 없어졌는지 본다
# (계획 20261113-wookiya1364-wrapup-report-plan-required · TESTS.md T1 ~ T15).
#
# T1 빈 칸 → 막힘 · T2 다 채움 → 보관 + 보고 일곱 묶음 · T3 가운데 넷 건너뜀 → 보관 · T4 이유 없는 건너뜀 → 막힘 ·
# T5 1 · 6 · 7번 건너뜀 → 막힘 · T6 보고 없는 옛 계획 → 보관 + 알림 · T7 가리키는데 파일 없음 → 막힘 · T8 칸을 지움 → 막힘 ·
# T9 영어 계획 · T10 순수 함수의 예 · T11 틀(문서 = 명령) · 손으로 못 만듦 · T12 일하기 규약의 두 문장 ·
# T13 빠른 길 선언은 없어졌다고 말하고 턴 끝은 여전히 막음 · T14 빠른 길 안내가 남아 있지 않음 · T15 예외는 릴리스 · 동기화뿐.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WU="$CORE/scripts/wrapup.sh"
WORKSH="$CORE/scripts/work.sh"
GUARD="$CORE/template/hooks/guard.sh"
TC="$CORE/scripts/turn-check.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unset PROMOTE_DIR ARCHIVE_DIR SCV_JOURNAL_DIR SCV_WORKSPACE_REPOS SCV_TURN_PLAN_CHECK SCV_DIR 2>/dev/null || true
fail=0
# @effect ok
# 이유: 통과 줄을 표준 출력에 쓴다
ok() { echo "ok $1"; }
# @effect bad
# 이유: 실패 줄을 표준 오류에 쓰고 실패 표시를 남긴다
bad() { echo "✖ $1" >&2; fail=1; }

# shellcheck source=../scripts/lib/wrapup.sh
source "$CORE/scripts/lib/wrapup.sh"
# @effect tpl
# 이유: 새 마무리 보고 파일의 글(머리 + 몸)을 표준 출력에 쓴다 — 명령(wrapup.sh new)이 엮는 것과 같은 순서
tpl() { printf '%s\n\n%s\n' "$(scv_wu_head "$1" "$2")" "$(scv_wu_skeleton "$(scv_wu_names "$1")")"; }
# shellcheck source=../scripts/lib/turn-check.sh
source "$CORE/scripts/lib/turn-check.sh"

# @effect wu_full
# 이유: 16칸을 다 채운 한국어 마무리 보고 글을 표준 출력에 쓴다
wu_full() {
  cat <<'EOF'
# 마무리 보고 — 시험 계획

<!-- 계획을 세울 때 아는 만큼 채우고, 일이 끝난 뒤 모든 칸을 채운다.
     - 이 줄은 주석이라 칸이 아니다: 값 -->

## 1. 문제

- 상황: 로그인 버튼이 눌리지 않는다
- 기대: 눌리면 들어간다
- 실제: 아무 일도 없다
- 재현 조건: 비밀번호를 비우고 누른다

## 2. 관찰

- 관찰한 사실과 측정값: 10번 중 10번 실패
- 정상일 때와 차이: 비밀번호가 있으면 된다

## 3. 가설

- H1: 빈 값 검사가 버튼을 막는다
- H2: 버튼이 다른 층에 가려 있다

## 4. 실험

- 방법과 같게 둔 것: 같은 계정으로 빈 값과 채운 값을 번갈아 넣었다
- 결과와 가설별 판정: H1 맞음 · H2 틀림

## 5. 원인

- 직접 원인과 일어난 길: 빈 값 검사가 알림 없이 멈춘다
- 근본 원인: 빈 값의 뜻을 정하지 않았다

## 6. 해결과 검증

- 해결책과 고른 이유: 빈 값을 거절하고 알림을 띄운다 — 가장 작은 고침이다
- 고치기 전후 값: 0 / 10 → 10 / 10
- 부작용과 회귀 시험: 시험 12개 통과, 부작용 없음 — 다른 입력은 건드리지 않았다

## 7. 배운 것

- 다음에 같은 문제를 만나면 진단하는 법: 입력 검사부터 본다
- 다른 곳에도 쓸 수 있는 것: 빈 값의 뜻을 먼저 정한다
EOF
}

# @effect skip_group
# 이유: 표준 입력의 마무리 보고에서 한 묶음의 칸 줄을 지우고 건너뜀 줄 하나로 바꿔 표준 출력에 쓴다
skip_group() {  # <묶음 번호> <건너뜀 줄>
  awk -v n="$1" -v line="$2" '
    /^## [1-7]\./ { cur = substr($2, 1, 1); print; if (cur == n) { print ""; print line }; next }
    cur == n && /^- / { next }
    { print }'
}

# @effect mkplan
# 이유: 임시 프로젝트에 가짜 계획 폴더(계획 문서 · 시험 문서)를 만든다
mkplan() {  # <프로젝트> <계획 이름> <마무리 보고를 가리킴 yes|no>
  local p="$1" s="$2" points="$3" link=""
  mkdir -p "$p/scv/promote/$s" "$p/scv/archive"
  [[ "$points" == yes ]] && link=$'- 마무리 보고: [`WRAPUP.md`](./WRAPUP.md)\n'
  printf -- '---\ntitle: 시험 계획\nslug: %s\nstatus: testing\nlang: korean\n---\n\n# 시험 계획\n\n## Links\n\n%s- Related PRs:\n' "$s" "$link" > "$p/scv/promote/$s/PLAN.md"
  printf '# Test Plan\n\n## How to run\n\n```bash\ntrue\n```\n' > "$p/scv/promote/$s/TESTS.md"
}

# @effect archive
# 이유: 임시 프로젝트에서 실제 보관 명령을 돌려 출력과 종료 코드를 변수에 담는다
archive() {  # <프로젝트> <계획 이름> → OUT · RC
  OUT="$(cd "$1" && bash "$WORKSH" "$2" --archive --reason="tests passed" 2>&1)"; RC=$?
}

# @effect moved
# 이유: 계획 폴더가 보관 자리로 옮겨졌는지 파일 시스템에서 본다
moved() { [[ -d "$1/scv/archive/$2" && ! -d "$1/scv/promote/$2" ]]; }
# @effect untouched
# 이유: 계획 폴더가 그 자리에 그대로이고 보관 폴더가 없는지 파일 시스템에서 본다
untouched() { [[ -d "$1/scv/promote/$2" && ! -e "$1/scv/archive/$2" ]]; }

P="$WORK/p"; mkdir -p "$P"; (cd "$P" && git init -q . && git config user.email t@t && git config user.name t)

# T1 — 빈 칸 하나 → 막힘, 칸 이름, 아무것도 옮기지 않음
mkplan "$P" t1 yes
wu_full | sed 's/^- 다른 곳에도 쓸 수 있는 것: .*/- 다른 곳에도 쓸 수 있는 것:/' > "$P/scv/promote/t1/WRAPUP.md"
archive "$P" t1
if [[ "$RC" == 1 ]] && grep -q '묶음 7 · 다른 곳에도 쓸 수 있는 것 — 빈 칸' <<<"$OUT" && untouched "$P" t1; then ok "T1 빈 칸 → exit 1, 칸 이름, 옮긴 것 없음"
else bad "T1 rc=$RC out=$OUT"; fi

# T1b — 채울 자리 표시가 남은 칸도 빈 칸이다
wu_full | sed 's/^- 근본 원인: .*/- 근본 원인: <TODO: 끝난 뒤>/' > "$P/scv/promote/t1/WRAPUP.md"
archive "$P" t1
[[ "$RC" == 1 ]] && grep -q '묶음 5 · 근본 원인 — 빈 칸' <<<"$OUT" && untouched "$P" t1 && ok "T1b 채울 자리 표시 → exit 1" || bad "T1b rc=$RC out=$OUT"

# T2 — 다 채움 → 보관, 지금과 같은 줄, 보고 일곱 묶음, 파일 넷
mkplan "$P" t2 yes; wu_full > "$P/scv/promote/t2/WRAPUP.md"
archive "$P" t2
n="$(grep -cE '^[1-7]\. ' <<<"$OUT" || true)"
files="$(ls "$P/scv/archive/t2" 2>/dev/null | grep -cE '^(PLAN|TESTS|WRAPUP|ARCHIVED_AT)\.md$' || true)"
if [[ "$RC" == 0 && "$n" == 7 && "$files" == 4 ]] && grep -q '^ARCHIVED: ' <<<"$OUT" && grep -q '^WROTE: .*ARCHIVED_AT.md' <<<"$OUT" \
   && grep -q '^   - 고치기 전후 값: 0 / 10 → 10 / 10$' <<<"$OUT" && ! grep -q '이 줄은 주석' <<<"$OUT" && moved "$P" t2; then ok "T2 다 채움 → exit 0, 보고 7묶음, 파일 4"
else bad "T2 rc=$RC groups=$n files=$files out=$OUT"; fi

# T3 — 새 기능 계획: 가운데 넷 건너뜀 → 보관, 이유가 보고에 나옴
mkplan "$P" t3 yes
wu_full | skip_group 2 '해당 없음 — 새 기능이라 고장이 없다' | skip_group 3 '해당 없음 — 의심한 것이 없다' \
  | skip_group 4 '- 해당 없음: 가를 가설이 없다' | skip_group 5 '해당 없음 — 원인을 찾는 일이 아니다' > "$P/scv/promote/t3/WRAPUP.md"
archive "$P" t3
r="$(grep -cE '^   -? ?해당 없음' <<<"$OUT" || true)"
if [[ "$RC" == 0 && "$r" == 4 ]] && grep -q '새 기능이라 고장이 없다' <<<"$OUT" && grep -q '가를 가설이 없다' <<<"$OUT" && moved "$P" t3; then ok "T3 가운데 넷 건너뜀 → exit 0, 이유 4줄"
else bad "T3 rc=$RC reasons=$r out=$OUT"; fi

# T4 — 이유 없는 건너뜀 → 막힘
mkplan "$P" t4 yes; wu_full | skip_group 3 '해당 없음' > "$P/scv/promote/t4/WRAPUP.md"
archive "$P" t4
[[ "$RC" == 1 ]] && grep -q '묶음 3 — 이유 없음' <<<"$OUT" && untouched "$P" t4 && ok "T4 이유 없는 건너뜀 → exit 1" || bad "T4 rc=$RC out=$OUT"
wu_full | skip_group 3 '해당 없음 — ' > "$P/scv/promote/t4/WRAPUP.md"
archive "$P" t4
[[ "$RC" == 1 ]] && grep -q '묶음 3 — 이유 없음' <<<"$OUT" && ok "T4b 줄표뿐인 건너뜀 → exit 1" || bad "T4b rc=$RC out=$OUT"

# T5 — 문제 · 해결과 검증 · 배운 것은 건너뛸 수 없다
blocked=0
for g in 1 6 7; do
  mkplan "$P" "t5-$g" yes; wu_full | skip_group "$g" '해당 없음 — 적을 것이 없다' > "$P/scv/promote/t5-$g/WRAPUP.md"
  archive "$P" "t5-$g"
  [[ "$RC" == 1 ]] && grep -q "묶음 $g — 건너뛸 수 없는 묶음" <<<"$OUT" && untouched "$P" "t5-$g" && blocked=$((blocked + 1))
done
[[ "$blocked" == 3 ]] && ok "T5 1 · 6 · 7번 건너뜀 → 3 / 3 막힘" || bad "T5 막힌 수 $blocked / 3"

# T6 — 마무리 보고가 없는 옛 계획 → 그대로 보관, 알림 한 줄
mkplan "$P" t6 no
archive "$P" t6
l="$(grep -c '^WRAPUP: legacy' <<<"$OUT" || true)"
[[ "$RC" == 0 && "$l" == 1 ]] && grep -q '^ARCHIVED: ' <<<"$OUT" && ! grep -q 'wrap-up report' <<<"$OUT" && moved "$P" t6 && ok "T6 옛 계획 → exit 0, 알림 1줄" || bad "T6 rc=$RC legacy=$l out=$OUT"

# T7 — 계획이 가리키는데 파일이 없음 → 막힘
mkplan "$P" t7 yes
archive "$P" t7
[[ "$RC" == 1 ]] && grep -q '마무리 보고 파일 없음' <<<"$OUT" && untouched "$P" t7 && ok "T7 가리키는데 파일 없음 → exit 1" || bad "T7 rc=$RC out=$OUT"

# T8 — 칸 줄을 지움 → 막힘
mkplan "$P" t8 yes; wu_full | sed '/^- 고치기 전후 값: /d' > "$P/scv/promote/t8/WRAPUP.md"
archive "$P" t8
[[ "$RC" == 1 ]] && grep -q '묶음 6 — 칸 2개 · 필요 3개' <<<"$OUT" && untouched "$P" t8 && ok "T8 칸을 지움 → exit 1" || bad "T8 rc=$RC out=$OUT"
wu_full | sed '/^## 7\. /,$d' > "$P/scv/promote/t8/WRAPUP.md"
archive "$P" t8
[[ "$RC" == 1 ]] && grep -q '묶음 7 — 묶음 없음' <<<"$OUT" && ok "T8b 묶음을 통째로 지움 → exit 1" || bad "T8b rc=$RC out=$OUT"

# T9 — 영어 계획도 같은 판정
# @effect wu_english
# 이유: 영어 틀을 채운 마무리 보고 글을 표준 출력에 쓴다(가운데 넷은 N/A)
wu_english() {
  tpl english "Login fix" | sed -e 's/<TODO[^>]*>/filled in/' \
    | skip_group 2 'N/A — a new feature, nothing went wrong' | skip_group 3 'N/A: no suspicion to list' \
    | skip_group 4 'N/A — no hypothesis to test' | skip_group 5 'N/A — no cause to find'
}
mkplan "$P" t9a yes; wu_english > "$P/scv/promote/t9a/WRAPUP.md"; archive "$P" t9a; rc_a=$RC; out_a="$OUT"
mkplan "$P" t9b yes; wu_english | sed 's/^- Expected: .*/- Expected:/' > "$P/scv/promote/t9b/WRAPUP.md"; archive "$P" t9b
if [[ "$rc_a" == 0 && "$RC" == 1 ]] && grep -q '묶음 1 · Expected — 빈 칸' <<<"$OUT" && grep -q 'nothing went wrong' <<<"$out_a"; then ok "T9 영어 계획 → 0 · 1"
else bad "T9 full=$rc_a empty=$RC out=$OUT"; fi

# T10 — 순수 함수의 예
t=$'\t'
e=0
[[ "$(scv_wu_fields $'## 1. 문제\n- 상황: 느리다\n- 기대:')" == "1${t}#${t}문제"$'\n'"1${t}상황${t}느리다"$'\n'"1${t}기대${t}" ]] || { e=$((e + 1)); echo "  fields 1" >&2; }
[[ "$(scv_wu_fields $'## 3. 가설\n- H1:\n  - 캐시가 낡았다')" == "3${t}#${t}가설"$'\n'"3${t}H1${t}캐시가 낡았다" ]] || { e=$((e + 1)); echo "  fields 이어지는 줄" >&2; }
[[ "$(scv_wu_fields $'## 6. 해결\n- 값: 전: 3초, 뒤: 1초')" == "6${t}#${t}해결"$'\n'"6${t}값${t}전: 3초, 뒤: 1초" ]] || { e=$((e + 1)); echo "  fields 쌍점 여럿" >&2; }
[[ -z "$(scv_wu_fields '')" && -z "$(scv_wu_fields $'## Links\n- a: b')" ]] || { e=$((e + 1)); echo "  fields 빈 글" >&2; }
[[ "$(scv_wu_fields '## 2. 관찰')" == "2${t}#${t}관찰" ]] || { e=$((e + 1)); echo "  fields 머리만" >&2; }
[[ "$(scv_wu_empty '' | grep -c '묶음 없음')" == 7 ]] || { e=$((e + 1)); echo "  empty 빈 글" >&2; }
[[ -z "$(scv_wu_empty "$(scv_wu_fields "$(wu_full)")")" ]] || { e=$((e + 1)); echo "  empty 다 채움" >&2; }
[[ -z "$(scv_wu_skip_bad "2${t}-${t}해당 없음 — 새 기능이라 고장이 없다")" ]] || { e=$((e + 1)); echo "  skip 이유 있음" >&2; }
[[ "$(scv_wu_skip_bad "3${t}-${t}해당 없음")" == "3${t}-${t}이유 없음" ]] || { e=$((e + 1)); echo "  skip 이유 없음" >&2; }
[[ "$(scv_wu_skip_bad "1${t}-${t}해당 없음 — x")" == "1${t}-${t}건너뛸 수 없는 묶음" ]] || { e=$((e + 1)); echo "  skip 1번" >&2; }
[[ "$(scv_wu_points 'see WRAPUP.md')" == yes && "$(scv_wu_points '')" == no ]] || { e=$((e + 1)); echo "  points" >&2; }
[[ "$(scv_wu_verdict '' '' yes yes)" == pass && "$(scv_wu_verdict '' '' no no)" == legacy ]] || { e=$((e + 1)); echo "  verdict pass · legacy" >&2; }
[[ "$(scv_wu_verdict '' '' no yes)" == block$'\n'* ]] || { e=$((e + 1)); echo "  verdict 파일 없음" >&2; }
[[ "$(scv_wu_verdict "7${t}칸${t}빈 칸" "3${t}-${t}이유 없음" yes yes)" == $'block\n묶음 7 · 칸 — 빈 칸\n묶음 3 — 이유 없음' ]] || { e=$((e + 1)); echo "  verdict block" >&2; }
[[ "$(scv_wu_digest "1${t}#${t}문제"$'\n'"1${t}상황${t}느리다"$'\n'"2${t}#${t}관찰"$'\n'"2${t}-${t}해당 없음 — 새 기능")" == $'1. 문제\n   - 상황: 느리다\n2. 관찰\n   해당 없음 — 새 기능' ]] || { e=$((e + 1)); echo "  digest" >&2; }
[[ "$e" == 0 ]] && ok "T10 순수 함수의 예 — 실패 0개" || bad "T10 예 실패 ${e}개"

# T11 — 틀: 명령이 쓴 것 = 틀 문서의 것, 일곱 묶음 16칸, 틀 그대로는 막힘, 손으로는 못 만듦
doc_tpl="$(sed -n '/^# Wrap-up — /,/^- What applies elsewhere/p' "$CORE/template/scv/PROMOTE.md" | sed 's/{{title}}/Login fix/')"
[[ -n "$doc_tpl" && "$doc_tpl" == "$(tpl english "Login fix")" ]] && ok "T11a 틀 문서의 틀 = 명령의 틀" || bad "T11a 틀 문서와 명령의 틀이 다르다"
shape=""
for lang in korean english; do
  f="$(scv_wu_fields "$(tpl "$lang" x)")"
  shape+="$(grep -c "^[1-7]${t}#${t}" <<<"$f" || true):$(grep -vc "^[1-7]${t}#${t}" <<<"$f" || true) "
done
[[ "$shape" == "7:16 7:16 " ]] && ok "T11b 두 언어의 틀 — 묶음 7 · 칸 16" || bad "T11b 틀의 모양: $shape"
mkplan "$P" t11 yes
out="$(bash "$WU" new "$P/scv/promote/t11" 2>&1)"; rc_new=$?
bash "$WU" check "$P/scv/promote/t11" >/dev/null 2>&1; rc_chk=$?
bash "$WU" new "$P/scv/promote/t11" >/dev/null 2>&1; rc_again=$?
if [[ "$rc_new" == 0 && "$rc_chk" == 1 && "$rc_again" == 1 ]] && grep -q '^# 마무리 보고 — 시험 계획$' "$P/scv/promote/t11/WRAPUP.md"; then ok "T11c 새 파일은 계획의 언어 · 제목으로, 틀 그대로는 exit 1, 있는 파일은 덮지 않음"
else bad "T11c new=$rc_new check=$rc_chk again=$rc_again $out"; fi
grep -qF 'wrapup.sh" new' "$CORE/protocols/promote.md" && grep -qF 'write **three files**' "$CORE/protocols/promote.md" \
  && ok "T11d 계획 세우기 규약이 세 번째 파일과 명령을 말한다" || bad "T11d 계획 세우기 규약에 마무리 보고가 없다"
G="$WORK/g"; mkdir -p "$G/scv/promote/x" "$G/scv/archive" "$G/state"
payload='{"cwd":"'"$G"'","session_id":"s1","tool_name":"Write","tool_input":{"file_path":"scv/promote/x/WRAPUP.md"}}'
out="$(SCV_GUARD_STATE="$G/state" SCV_GUARD_MODE=gate-write bash "$GUARD" <<<"$payload" 2>/dev/null)"
grep -q '"permissionDecision":"deny"' <<<"$out" && ok "T11e 영수증 없이 손으로 만든 마무리 보고 → 훅 거절" || bad "T11e 훅이 허용: $out"

# T12 — 일하기 규약의 두 문장
w="$CORE/protocols/work.md"; found=0
grep -qF 'Then the wrap-up report — every field filled.' "$w" && grep -qF 'wrapup.sh check' "$w" && found=$((found + 1))
grep -qF 'show the wrap-up report once' "$w" && found=$((found + 1))
[[ "$found" == 2 ]] && ok "T12 일하기 규약 — 찾은 문장 2개" || bad "T12 찾은 문장 ${found}개"

# T13 — 빠른 길 선언은 없어졌다고 말하고, 계획 없는 턴은 여전히 막힌다
R="$WORK/r"; mkdir -p "$R/scv/promote" "$R/src"
(
  cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf '# r\n' > README.md; git add -A && git commit -qm init
) >/dev/null 2>&1
out="$(cd "$R" && bash "$WORKSH" --fast "typo in the readme" 2>/dev/null)"; rc=$?
err="$(cd "$R" && bash "$WORKSH" --fast "typo in the readme" 2>&1 >/dev/null)"
crit="$(grep -c 'FAST_CRITERIA\|FAST_LINE_CEILING' <<<"$out$err" || true)"
end="$(cd "$R" && export SCV_TODAY=2026-11-13 && printf '%s' '오타 고쳐라' | bash "$TC" start --session s1 >/dev/null 2>&1; bash "$TC" touch --session s1 --kind write README.md >/dev/null 2>&1; printf 'y\n' >> README.md; bash "$TC" end --session s1 2>&1)"
if [[ "$rc" == 2 && "$crit" == 0 ]] && grep -q '^FAST_REMOVED: ' <<<"$err" && grep -qx 'TURN_PLAN: block' <<<"$end" && grep -q '진행 중 계획이 없다' <<<"$end"; then ok "T13 빠른 길 선언 → exit 2, 기준 출력 0줄, 턴 끝 막힘"
else bad "T13 rc=$rc crit=$crit err=$err end=$end"; fi

# T14 — 빠른 길 안내가 남아 있지 않다 (선언 명령의 '없어졌다' 안내 한 곳만)
left="$(grep -lE -- '--fast|SCV_FAST_PATH_LINE_THRESHOLD|[Ff]ast-path' "$CORE/template/scv/PROMOTE.md" "$CORE/template/scv/scv_settings.example.json" \
  "$CORE/scripts/lib/settings.sh" "$CORE/template/hooks/guard.sh" "$CORE"/protocols/*.md "$CORE"/contracts/*.md "$WORKSH" 2>/dev/null | sed "s#^$CORE/##" | tr '\n' ' ')"
if [[ "$left" == "scripts/work.sh " ]] && grep -qF '## 1.6. No change without a plan' "$CORE/template/scv/PROMOTE.md" \
   && grep -qF 'Two exceptions only: a release and a Core sync' "$CORE/template/scv/PROMOTE.md" && ! grep -q 'FAST_CRITERIA' "$WORKSH"; then ok "T14 빠른 길을 말하는 곳 1 (없어졌다는 안내)"
else bad "T14 남은 곳: $left"; fi

# T15 — 계획 없이 해도 되는 예외는 릴리스 · 동기화뿐
[[ "$(scv_tc_exempt_ok release)$(scv_tc_exempt_ok sync)$(scv_tc_exempt_ok fast)$(scv_tc_exempt_ok misc)$(scv_tc_exempt_ok '')" == "yesyesnonono" ]] \
  && ok "T15 예외 — 릴리스 · 동기화만" || bad "T15 예외 판정이 바뀌었다"

[[ "$fail" == 0 ]] && echo "test-wrapup: all passed" || { echo "test-wrapup: FAILED" >&2; exit 1; }
