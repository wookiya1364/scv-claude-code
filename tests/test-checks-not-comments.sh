#!/usr/bin/env bash
# test-checks-not-comments.sh — 글 대신 검사(계획 20261117-wookiya1364-checks-not-comments).
#
# 1단계: 매 턴 글에서 덜어 낸 규칙마다, 그 규칙을 어긴 사례를 검사가 여전히 막고 거절 문구에 고칠 방법이 있는지(T2),
#        검사가 없는 규칙 줄은 남아 있는지(T3). T1(크기)은 test-instruction-diet.sh · test-help-budget.sh 가 맡는다.
# 뒤 단계의 시나리오는 이 파일에 이어 붙는다.
# scv-test: serial — 계획 끝 검사(재는 명령)를 실제로 돌린다
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/model-prompting.sh
source "$CORE/scripts/lib/help-state.sh"
source "$CORE/scripts/lib/model-prompting.sh"
# shellcheck source=../scripts/lib/finish-report.sh
source "$CORE/scripts/lib/finish-report.sh"
# shellcheck source=../scripts/lib/lang-enforce.sh
source "$CORE/scripts/lib/lang-enforce.sh"
# shellcheck source=../scripts/lib/force-help.sh
source "$CORE/scripts/lib/force-help.sh"
# shellcheck source=../scripts/lib/correction-check.sh
source "$CORE/scripts/lib/correction-check.sh"
# shellcheck source=../scripts/lib/comment-flag.sh
source "$CORE/scripts/lib/comment-flag.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
us=$'\x1f'

# ── T2: 덜어 낸 줄 → 그 규칙을 어긴 사례 · 검사 · 거절 문구 ─────────────────────────────
# (a) 첫 행동 블록의 이유 · 예외 문장 → help 를 안 부른 턴: 가드 · 끝 훅이 쓰는 거절 문구가 이유를 싣는다
why="$(scv_mp_help_reason scv:help)"
[[ "$(scv_mp_help_needed tok1 "" "" 1 on)" == 1 ]] && ok "T2a help 를 안 부른 턴은 막힘 판정" || bad "T2a 막힘 판정 아님"
for w in "판단하지 말고 부르라" "예외가 없다" "어디에도 남지 않는다" "지금 scv:help 를"; do
  [[ "$why" == *"$w"* ]] || { bad "T2a 거절 문구에 '$w' 없음"; continue; }
done
[[ "$why" == *"판단하지 말고 부르라"* && "$why" == *"어디에도 남지 않는다"* ]] && ok "T2a 거절 문구가 이유 · 고칠 방법을 실음"

# (b) 확인 범위 블록의 "'없음'엔 이유, 실패를 못 본 시험은 '확인 못 한 것'에" → 끝 보고 검사가 둘 다 잡는다
chk="$(scv_finish_check "verified${us}a.sh 읽음"$'\n'"unverified${us}없음"$'\n'"decided${us}이름" "read${us}a.sh${us}ok${us}a.sh" "" full)"
[[ "$chk" == *"noreason${us}unverified"* ]] && ok "T2b 이유 없는 '없음'을 잡음" || bad "T2b noreason 못 잡음 [$chk]"
note="$(scv_finish_note "$chk" korean)"
[[ "$note" == *"'없음'에 이유 없음"* && "$note" == *"고친 줄만 끝에 덧붙여라"* ]] && ok "T2b 거절 문구에 고칠 방법" || bad "T2b 문구 [$note]"
chk="$(scv_finish_check "verified${us}a.sh 읽음"$'\n'"unverified${us}폰 화면 — 기기 없음"$'\n'"decided${us}이름" "read${us}a.sh${us}ok${us}a.sh" "test-a.sh" full)"
note="$(scv_finish_note "$chk" korean)"
[[ "$note" == *"test-a.sh"* && "$note" == *"'확인 못 한 것'에 적어라"* ]] && ok "T2b 실패를 못 본 시험을 잡고 어디 적을지 알림" || bad "T2b 못 본 시험 [$chk] [$note]"

# (c) 언어 블록의 "다른 언어로 쓴 최종 답은 막힌다" → 답 언어 검사가 막는다
v="$(scv_answer_lint $'> **Rewritten request**: x\n\n**Status**\n- The core release passed and both wrappers are being synced now\n- Waiting on CI\n' 2 korean)"
[[ "$v" == *lang-mismatch* ]] && ok "T2c 한국어 설정에서 영어 최종 답 → lang-mismatch" || bad "T2c got [$v]"

# 덜어 낸 줄은 매 턴 글에서 정말 빠졌다
blk="$(scv_force_routing)"; fr="$(scv_finish_rule_line korean)"; lr="$(scv_lang_rule_line korean)"
[[ "$blk" != *"판단하지 말고 부르라"* && "$fr" != *"실패를 못 본 시험은"* && "$lr" != *"최종 답은 막힌다"* ]] \
  && ok "T2 덜어 낸 3곳이 매 턴 글에 없음" || bad "T2 덜어 낸 문장이 남아 있음"

# ── T3: 검사가 없는 규칙 줄은 남는다 ─────────────────────────────────────────────
# 중간 보고 언어(막지 않고 알리기만 함) · 재조회 금지를 진단으로 좁힌 문장 · 확인 범위 세 줄 이름은 검사가 대신 못 하므로 남는다.
[[ "$lr" == *"도구 사이 중간 보고"* ]] && ok "T3 중간 보고 언어 줄 남음" || bad "T3 중간 보고 줄 빠짐"
[[ "$blk" == *"상태를 다시 조회하지 않는 데에만"* && "$blk" == *"지금 호출하라"* ]] && ok "T3 호출 명령 · 진단 한정 줄 남음" || bad "T3 첫 행동 필수 줄 빠짐"
[[ "$fr" == *"확인한 것 · 확인 못 한 것 · 제가 대신 정한 것"* ]] && ok "T3 확인 범위 세 줄 이름 남음" || bad "T3 세 줄 이름 빠짐"

# ── T4 · T5 · T6: 고쳐 달라는 턴 뒤의 검사 제안 (진짜 매 턴 훅을 임시 저장소에서) ─────────────────
FIX="$CORE/tests/fixtures/model-prompting"; HOOK="$CORE/template/hooks/on-user-prompt.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-cnc.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\nSCV_CHOICE_TOOL=PickTool\n' "$WORK/guides"; } > "$WORK/profile.env"
R="$WORK/r"; mkdir -p "$R/scv/journal"; (cd "$R" && git init -q && git config user.email t@t && git config user.name t)
printf '{"SCV_LANG": "korean", "SCV_DREAMS": "off"}\n' > "$R/scv/scv_settings.json"
(cd "$R" && printf 'a\n' > a.txt && git add -A && git commit -qm init)
hookp() { (cd "$R" && jq -cn --arg p "$1" '{prompt:$p,session_id:"s1"}' \
  | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile.env" bash "$HOOK" 2>/dev/null); }
o1="$(hookp "아니, 그게 아니라 버튼은 오른쪽이야")"
[[ "$o1" != *"[SCV 정정]"* ]] && ok "T5b 세션 첫 턴의 정정 문장 → 안내 없음" || bad "T5b 첫 턴에 안내가 뜸"
TD="$(cat "$R/scv/journal/.turn-latest" 2>/dev/null || true)"
if [[ -n "$TD" && -d "$TD/.turn-plan" ]]; then
  printf 'a.txt\nb.txt\n' > "$TD/.turn-plan/changed"; : > "$TD/.turn-plan/ended"
  before="$(cd "$R" && git status --short -- . ':!scv/journal' ':!scv/conversations' | sort)"
  o2="$(hookp "아니, 그게 아니라 버튼은 오른쪽이야")"
  after="$(cd "$R" && git status --short -- . ':!scv/journal' ':!scv/conversations' | sort)"
  n="$(grep -c '^\[SCV 정정\]' <<<"$o2" || true)"
  [[ "$n" == 1 ]] && ok "T4 파일을 바꾼 턴 뒤의 정정 → 안내 1줄" || bad "T4 안내 줄 수 $n"
  [[ "$before" == "$after" ]] && ok "T6 안내만 하고 파일은 만들지 않음" || bad "T6 파일이 바뀜 [$before] → [$after]"
  printf 'a.txt\n' > "$TD/.turn-plan/changed"; : > "$TD/.turn-plan/ended"
  o3="$(hookp "결제 화면에 새 버튼 추가해줘")"
  [[ "$o3" != *"[SCV 정정]"* ]] && ok "T5a 새 기능 요청 턴 → 안내 없음" || bad "T5a 새 요청에 안내가 뜸"
  : > "$TD/.turn-plan/changed"; : > "$TD/.turn-plan/ended"
  o4="$(hookp "로그인 버그 고쳐 줘")"
  [[ "$o4" != *"[SCV 정정]"* ]] && ok "T5c 파일을 안 바꾼 턴 뒤의 '고쳐 줘' → 안내 없음" || bad "T5c 일 없는 턴 뒤에 안내"
else
  bad "T4 턴 폴더를 찾지 못함 [$TD]"
fi
[[ "$(scv_correction_notice 1 1 3 english)" == "[SCV correction]"* && -z "$(scv_correction_notice 1 0 3 korean)" ]] \
  && ok "T4 순수 함수(영어 · 끝나지 않은 턴)" || bad "T4 순수 함수"

# ── T7 · T8 · T9: 계획 끝 검사의 새 임시방편 주석 알림 ─────────────────────────────────
PB="$CORE/scripts/pure-bench.sh"
C="$WORK/c"; mkdir -p "$C"; (cd "$C" && git init -q -b main && git config user.email t@t && git config user.name t)
printf '// TODO: old\nconst a = 1\n' > "$C/app.ts"; printf 'x() { :; }\n' > "$C/lib.sh"
(cd "$C" && git add -A && git commit -qm init && git checkout -qb feat)
pe() { (cd "$C" && SCV_PURE_BENCH="${1:-off}" bash "$PB" plan-end 2>/dev/null); }
pe off >/dev/null; rc0=$?
printf '// TODO: old\n// TODO: 나중에 제거\nconst a = 1\n// 일반 설명\n' > "$C/app.ts"
printf '# workaround — 큰 변경이라 미룸\nx() { :; }\n' > "$C/lib.sh"
printf '#!/usr/bin/env bash\n# @pure foo\n# 역할: 나중에 쓸 값\nfoo() { :; }\n' > "$C/new.sh"
out="$(pe off)"; rc1=$?
n="$(grep -c '^  [a-z.]*:[0-9]' <<<"$out" || true)"
if [[ "$n" == 2 ]] && grep -q '^  app.ts:2  // TODO: 나중에 제거$' <<<"$out" && grep -q '^  lib.sh:1  # workaround' <<<"$out"; then
  ok "T7 새로 넣은 두 줄만 파일:줄로 알림 (원래 TODO · 일반 설명 없음)"
else
  bad "T7 알림 [$out]"
fi
grep -q 'new.sh' <<<"$out" && bad "T8 표식 주석 덩어리가 알림에 나옴" || ok "T8 표식 주석 덩어리는 알리지 않음"
[[ "$rc0" == "$rc1" ]] && ok "T9 알림이 있어도 종료 코드 같음 ($rc0 = $rc1)" || bad "T9 종료 코드 $rc0 → $rc1"
grep -q '막지 않음' <<<"$out" && ok "T9 알림에 '막지 않음'과 할 일" || bad "T9 문구 없음"

# ── T18 · T19 · T20 · T21: 계획 끝 검사가 사전 중복 검사를 자동으로 돌린다 ───────────────────────
P="$WORK/p"; mkdir -p "$P/src" "$P/scv"; (cd "$P" && git init -q -b main && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m base && git checkout -qb work)
# 바뀐 파일은 올려 두기만 하고 커밋하지 않는다 — 계획 끝 검사는 main 과 갈라진 뒤의 변경을, 사전은 git 이 아는 파일을 본다
mkpe() { (cd "$P" && git add -A && bash "$CORE/scripts/pure-catalog.sh" build --project >/dev/null 2>&1; SCV_PURE_BENCH=off bash "$PB" plan-end 2>&1); }
cat > "$P/src/a.sh" <<'SH'
# @pure
# 역할: 앞뒤 공백을 지운다
# 종류: 다듬기
# 예: " a " → "a"
trim_spaces() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
SH
rc=0; o="$(mkpe)" || rc=$?
grep -q '^사전 검사: 통과' <<<"$o" && [[ $rc == 0 ]] && ok "T18 계획 끝 검사가 사전 검사를 돌림 — 통과 줄 1개 · 종료 0" || bad "T18 [$rc] [$o]"
cat >> "$P/src/a.sh" <<'SH'

# @pure
# 역할: 양끝 빈칸을 없앤다
# 종류: 다듬기
# 예: "  hello" → "hello"
strip_blank() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
SH
rc=0; o="$(mkpe)" || rc=$?
n="$(grep -c '중복 의심: strip_blank · trim_spaces\|중복 의심: trim_spaces · strip_blank' <<<"$o" || true)"
[[ "$n" == 1 && $rc == 1 ]] && ok "T19 셸 중복은 계획 끝 검사에서 막힘 (1줄 · 종료 1)" || bad "T19 [$rc] [$o]"
printf 'trim_spaces\tstrip_blank\t두 이름을 한동안 같이 둔다(시험)\n' > "$P/scv/core/catalog/pure/duplicates-allowed.tsv"
rc=0; o="$(mkpe)" || rc=$?
[[ $rc == 0 ]] && ok "T21 이유를 적은 중복 예외는 통과 (종료 0)" || bad "T21 이유 있음 [$rc] [$o]"
printf 'trim_spaces\tstrip_blank\t\n' > "$P/scv/core/catalog/pure/duplicates-allowed.tsv"
rc=0; o="$(mkpe)" || rc=$?
[[ $rc == 1 ]] && grep -q '중복 예외에 이유가 없다' <<<"$o" && ok "T21 이유 없는 예외는 다시 막힘 (종료 1)" || bad "T21 이유 없음 [$rc]"
printf 'trim_spaces\tstrip_blank\t두 이름을 한동안 같이 둔다(시험)\n' > "$P/scv/core/catalog/pure/duplicates-allowed.tsv"
cat > "$P/src/b.ts" <<'TS'
// @pure trimSpaces
// 역할: 앞뒤 공백을 지운다
// 종류: 다듬기
// 예: " a " → "a"
export const trimSpaces = (s: string): string => s.trim()

// @pure stripBlank
// 역할: 양끝 빈칸을 없앤다
// 종류: 다듬기
// 예: "  hello" → "hello"
export const stripBlank = (s: string): string => s.replace(/^\s+|\s+$/g, '')
TS
cat > "$P/src/c.py" <<'PY'
# @pure add_up
# 역할: 두 수를 더한다
# 종류: 세기
# 예: 1 2 → 3
def add_up(a, b):
    return a + b

# @pure plus
# 역할: 합을 낸다
# 종류: 세기
# 예: 10 5 → 15
def plus(x, y):
    return x + y
PY
cat > "$P/src/d.rs" <<'RS'
// @pure double
// 역할: 두 배로 만든다
// 종류: 세기
// 예: 2 → 4
fn double(n: i64) -> i64 { n * 2 }

// @pure twice
// 역할: 같은 수를 한 번 더 더한다
// 종류: 세기
// 예: 7 → 14
fn twice(n: i64) -> i64 { n + n }
RS
if command -v node >/dev/null && command -v python3 >/dev/null && command -v rustc >/dev/null; then
  rc=0; o="$(mkpe)" || rc=$?
  n="$(grep -cE '중복 의심: (stripBlank · trimSpaces|add_up · plus|double · twice)' <<<"$o" || true)"
  # node 가 TS 를 돌리지 못하면(22.6 미만) TS 짝은 '돌려 보지 못함'으로 알려야 한다 — 조용히 지나가면 안 된다.
  printf 'export const x: number = 1\n' > "$WORK/probe.ts"
  if node "$WORK/probe.ts" >/dev/null 2>&1; then want=3; else want=2; grep -q '돌려 보지 못함(함수): stripBlank, trimSpaces' <<<"$o" || bad "T20 TS 를 못 돌린 것을 알리지 않음"; fi
  [[ "$n" == "$want" && $rc == 1 ]] && ok "T20 TS · 파이썬 · 러스트 중복을 실제로 돌려 잡음 (${n}줄 · 종료 1, node TS 지원 $([[ $want == 3 ]] && echo 있음 || echo '없음 → TS 는 알림'))" || bad "T20 [$rc] [$n/$want] [$o]"
else
  bad "T20 이 기계에 node · python3 · rustc 가 다 있어야 한다"
fi
rc=0; o="$(cd "$P" && git add -A && SCV_PURE_RUN_SKIP="js py rs" bash "$CORE/scripts/pure-catalog.sh" check --project 2>&1)" || rc=$?
grep -q '돌려 보지 못함(도구 없음): js, py, rs' <<<"$o" && [[ $rc == 0 ]] \
  && ok "T21 도구가 없으면 '돌려 보지 못함' 알림 · 그 언어 때문에 막지 않음 (종료 0)" || bad "T21 도구 없음 [$rc] [$o]"
# 다른 일을 하는 짝은 중복이 아니다
cat > "$P/src/e.py" <<'PY'
# @pure times
# 역할: 곱한다
# 종류: 세기
# 예: 3 4 → 12
def times(a, b):
    return a * b
PY
o="$(mkpe)" || true
grep -q 'times' <<<"$o" && bad "T20 다른 일을 하는 함수가 중복으로 잡힘" || ok "T20 다른 일을 하는 짝은 잡지 않음 (times)"

exit "$fail"
