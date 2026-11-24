#!/usr/bin/env bash
# test-picture-rule.sh — "글 대신 그림" 규칙(contracts/writing.md 10)이 매 턴 글 · 직전 답 검사 · 호스트 프로필에 들어갔는지 본다.
#
# 계획 20261124-wookiya1364-gears-io-args 의 TESTS.md T44–T51. 매 턴 글(on-user-prompt.sh), 직전 답 판정
# (lib/help-state.sh scv_hs_seq_prose · scv_hs_picture_shown · scv_hs_picture_due), 다음 턴 알림(help-state.sh stop),
# 이번 턴의 도구 호출 수(lib/turn-stream.sh), 프로필 새 칸(SCV_DRAW_TOOL — 읽기 · 검증 · 내려쓰기).
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$CORE/tests/fixtures/model-prompting"
HOOK="$CORE/template/hooks/on-user-prompt.sh"; HS="$CORE/scripts/help-state.sh"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
# shellcheck source=../scripts/lib/help-state.sh
source "$CORE/scripts/lib/help-state.sh"
# shellcheck source=../scripts/lib/turn-stream.sh
source "$CORE/scripts/lib/turn-stream.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-picture.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\n' "$WORK/guides"; } > "$WORK/plain.env"
{ cat "$WORK/plain.env"; printf 'SCV_DRAW_TOOL=DrawTool\n'; } > "$WORK/draw.env"

# @effect newproj
# 이유: 임시 폴더에 빈 시험용 프로젝트(설정 파일 · 세션 상태 포함)를 만든다 — 인자: 이름 · 설정 JSON
newproj() {
  local r="$WORK/$1"; mkdir -p "$r/scv/journal"; (cd "$r" && git init -q)
  printf '%s\n' "$2" > "$r/scv/scv_settings.json"
  printf '{"session":"s1","protocol":1,"turn":3,"diag":"","diag_at":"","nonce":"abcd1234"}\n' > "$r/scv/journal/.help-state"
}
# @effect hook
# 이유: 시험용 프로젝트에서 매 턴 훅을 돌려 실리는 글을 낸다 — 인자: 프로젝트 이름 · 프로필 파일
hook() { (cd "$WORK/$1" && jq -cn '{prompt:"로그인 흐름 설명해 줘",session_id:"s1"}' \
  | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$2" bash "$HOOK" 2>/dev/null); }
# @effect stop
# 이유: 시험용 프로젝트에서 턴 끝 검사를 돌린다(표준 입력 = 직전 답) — 인자: 프로젝트 이름 · 그림 스위치 · 그림 도구 호출 수
stop() { (cd "$WORK/$1" && bash "$HS" stop --echo off --lint off --picture "$2" --draw-calls "$3" 2>/dev/null); }

SEQ=$'**설치 순서**\n\n아래 순서로 함.\n\n1. 저장소를 받음\n2. 의존성을 설치함\n3. 설정 파일을 만듦\n4. 서버를 띄움\n5. 화면을 확인함\n'
ARR=$'**흐름**\n\n- 요청 -> 검증\n- 검증 → 저장\n- 저장 → 알림\n- 알림 → 끝\n'

# T44 — 매 턴 글에 그림 구절이 한 번 실리고(쉬운 말 설정이 꺼지면 없음), 매 턴 글 크기는 한도 안이다
newproj on '{"SCV_LANG": "korean"}'
newproj off '{"SCV_LANG": "korean", "SCV_PLAIN_LANGUAGE": "off"}'
h1="$(hook on "$WORK/plain.env")"; h2="$(hook off "$WORK/plain.env")"
c1="$(grep -c 'show a picture first' <<< "$h1" || true)"; c2="$(grep -c 'show a picture first' <<< "$h2" || true)"
if [[ "$c1" == 1 && "$c2" == 0 ]] && bash "$CORE/tests/test-instruction-diet.sh" > "$WORK/diet.out" 2>&1; then ok "T44 그림 구절 — 켜짐 1건 · 꺼짐 0건, 매 턴 글 크기 한도 안"
else bad "T44 c1=$c1 c2=$c2 $(grep -E '^(✖|.*T1 per-turn)' "$WORK/diet.out" 2>/dev/null | head -n 2 | tr '\n' '|')"; fi

# T45 — 그림 도구가 있는 호스트는 그 도구 이름을, 없는 호스트는 화살표 한 줄 · 표를 말한다. core 글에는 도구 이름이 박혀 있지 않다
newproj draw '{"SCV_LANG": "korean"}'
h3="$(hook draw "$WORK/draw.env")"
if grep -q 'with the DrawTool tool when this session has it' <<< "$h3" && ! grep -q 'DrawTool' <<< "$h1" \
   && grep -q 'as one arrow line (A → B → C) or a short table' <<< "$h1" && { [[ ! -f "$CORE/../tests/test-host-neutral.sh" ]] || bash "$CORE/../tests/test-host-neutral.sh" >/dev/null 2>&1; }; then ok "T45 도구 있는 호스트 → 도구 이름, 없는 호스트 → 화살표 한 줄 · 표, 호스트 이름 검사 통과"
else bad "T45 $(grep -c DrawTool <<< "$h3") $(grep -c 'arrow line' <<< "$h1")"; fi

# T46 — 긴 순서 글인데 그림이 없으면 잡는다(번호 순서 5줄 · 화살표 줄 4줄)
v1="$(scv_hs_picture_due "$(scv_hs_seq_prose "$SEQ")" 0 "$(scv_hs_picture_shown "$SEQ")")"
v2="$(scv_hs_picture_due "$(scv_hs_seq_prose "$ARR")" 0 "$(scv_hs_picture_shown "$ARR")")"
[[ "$v1" == "picture=1" && "$v2" == "picture=1" ]] && ok "T46 긴 순서 글 + 그림 없음 → picture=1 (번호 순서 · 화살표 줄)" || bad "T46 v1=[$v1] v2=[$v2]"

# T47 — 그 턴에 그림 도구를 썼으면 잡지 않는다. 호출 수를 모르면(빈 값)도 잡지 않는다
v1="$(scv_hs_picture_due "$(scv_hs_seq_prose "$SEQ")" 1 "$(scv_hs_picture_shown "$SEQ")")"
v2="$(scv_hs_picture_due "$(scv_hs_seq_prose "$SEQ")" "" "$(scv_hs_picture_shown "$SEQ")")"
[[ -z "$v1" && -z "$v2" ]] && ok "T47 그림 도구 호출 1번 · 모름 → 잡지 않음" || bad "T47 v1=[$v1] v2=[$v2]"

# T48 — 화살표가 둘 이상인 한 줄이나 표가 있으면 잡지 않는다
A1="$SEQ"$'\n순서: 받기 → 설치 → 설정 → 실행\n'
A2="$SEQ"$'\n| 단계 | 하는 일 |\n|---|---|\n| 1 | 받기 |\n'
v1="$(scv_hs_picture_due "$(scv_hs_seq_prose "$A1")" 0 "$(scv_hs_picture_shown "$A1")")"
v2="$(scv_hs_picture_due "$(scv_hs_seq_prose "$A2")" 0 "$(scv_hs_picture_shown "$A2")")"
[[ -z "$v1" && -z "$v2" ]] && ok "T48 화살표 한 줄 · 표가 있으면 잡지 않음" || bad "T48 v1=[$v1] v2=[$v2]"

# T49 — 짧은 답은 건드리지 않는다(한 줄 · 받았다는 답 · 불릿 3개 · 번호 순서 3줄)
t49=1
for a in "통과함." "네, 알겠음." $'**상태**\n- 가 끝남\n- 나 끝남\n- 다 남음\n' $'1. 받기\n2. 설치\n3. 실행\n'; do
  [[ -z "$(scv_hs_picture_due "$(scv_hs_seq_prose "$a")" 0 "$(scv_hs_picture_shown "$a")")" ]] || t49=0
done
[[ $t49 == 1 ]] && ok "T49 짧은 답 네 가지 → 잡지 않음" || bad "T49"

# T50 — 켜면 다음 턴에 알림 한 줄이 실리고(턴은 막히지 않는다), 끄거나 어긋남이 없으면 실리지 않는다
newproj n-on '{"SCV_LANG": "korean"}'; newproj n-off '{"SCV_LANG": "korean"}'; newproj n-fine '{"SCV_LANG": "korean"}'
o1="$(printf '%s' "$SEQ" | stop n-on on 0)"; r1=$?
printf '%s' "$SEQ" | stop n-off off 0 >/dev/null; r2=$?
printf '%s' "$A1" | stop n-fine on 0 >/dev/null; r3=$?
g1="$(hook n-on "$WORK/plain.env" | grep -c '^\[SCV 그림\]' || true)"
g2="$(hook n-off "$WORK/plain.env" | grep -c '^\[SCV 그림\]' || true)"
g3="$(hook n-fine "$WORK/plain.env" | grep -c '^\[SCV 그림\]' || true)"
if [[ $r1 == 0 && $r2 == 0 && $r3 == 0 && "$g1" == 1 && "$g2" == 0 && "$g3" == 0 && "$o1" == *"reload=0 picture=1"* ]] \
   && grep -q 'SCV_PICTURE_NOTICE' "$CORE/template/hooks/on-stop.sh" && grep -q -- '--picture "\$_scv_pic" --draw-calls "\$_scv_dc"' "$CORE/template/hooks/on-stop.sh"; then
  ok "T50 알림 — 켬 1줄 · 끔 0줄 · 어긋남 없음 0줄, 규약은 다시 싣지 않음, 턴 끝 훅이 스위치를 넘김"
else bad "T50 r=$r1/$r2/$r3 g=$g1/$g2/$g3 o1=$o1"; fi

# T50b — 이번 턴에 그림 도구를 부른 횟수를 대화 기록에서 센다(앞 턴의 호출은 세지 않고, 턴 경계가 없으면 아무것도 내지 않는다)
TRANSCRIPT="$WORK/t.jsonl"
{
  printf '%s\n' '{"type":"user","message":{"content":"앞 턴"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"DrawTool"}]}}'
  printf '%s\n' '{"type":"user","message":{"content":"이번 턴"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"그림을 그림"},{"type":"tool_use","name":"DrawTool"}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"OtherTool"},{"type":"tool_use","name":"DrawTool"}]}}'
} > "$TRANSCRIPT"
n1="$(_scv_turn_tool_count DrawTool)"; n2="$(_scv_turn_tool_count NoneTool)"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"DrawTool"}]}}' > "$TRANSCRIPT"
n3="$(_scv_turn_tool_count DrawTool)"
[[ "$n1" == 2 && "$n2" == 0 && -z "$n3" ]] && ok "T50b 이번 턴의 도구 호출 수 — 2 · 0 · 경계 없으면 모름" || bad "T50b n1=[$n1] n2=[$n2] n3=[$n3]"

# T51 — 호스트 프로필의 새 칸이 읽기 · 검증 · 내려쓰기 세 곳에 있다
VH="$CORE/../tools/validate-host-profile.sh"; MZ="$CORE/../tools/materialize-profile.sh"; FXE="$CORE/../tests/fixtures/codex.env"
rd="$( SCV_HOST_PROFILE="$WORK/draw.env"; export SCV_HOST_PROFILE; source "$CORE/scripts/lib/host-profile.sh" 2>/dev/null; printf '%s' "${SCV_DRAW_TOOL:-}" )"
# 검증 · 내려쓰기 도구와 본보기 프로필은 core 저장소에만 있다 — core 만 옮겨 간 사본에서는 읽기만 본다(도구가 빠지면 test-effort-ask T17b 가 잡는다)
if [[ -f "$VH" && -f "$MZ" && -f "$FXE" ]]; then
  { cat "$FXE"; printf 'SCV_DRAW_TOOL=DrawTool\n'; } > "$WORK/good.env"
  { cat "$FXE"; printf 'SCV_DRAW_TOOL=two words\n'; } > "$WORK/bad.env"
  bash "$VH" --profile "$WORK/good.env" >/dev/null 2>&1; v1=$?
  bash "$VH" --profile "$WORK/bad.env" >/dev/null 2>&1; v2=$?
  mkdir -p "$WORK/mcore"; cp -R "$CORE/." "$WORK/mcore/"
  bash "$MZ" --root "$WORK/mcore" --profile "$WORK/good.env" >/dev/null 2>&1; v3=$?
  if [[ "$rd" == DrawTool && $v1 == 0 && $v2 != 0 && $v3 == 0 ]] && grep -qx 'SCV_DRAW_TOOL=DrawTool' "$WORK/mcore/host-profile.env"; then ok "T51 프로필 새 칸 — 읽기 값 같음, 검증 통과 · 거부, 내려쓴 파일에 있음"
  else bad "T51 rd=[$rd] v1=$v1 v2=$v2 v3=$v3"; fi
else
  [[ "$rd" == DrawTool ]] && ok "T51 프로필 새 칸 — 읽기 값 같음(검증 · 내려쓰기 도구가 없는 사본)" || bad "T51 rd=[$rd]"
fi

if [[ $fail -ne 0 ]]; then echo "test-picture-rule: FAIL" >&2; exit 1; fi
echo "test-picture-rule: all passed"
