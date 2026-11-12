#!/usr/bin/env bash
# test-effort-ask.sh — 권장 effort 요청(0.89.0): 세션의 effort 가 그 모델의 권장 값과 다를 때만, 한 번만 묻게 하는지 본다.
# 값을 모르거나 · 표가 없거나 · 꺼졌거나 · 사람이 없는 실행이면 아무 일도 없어야 한다.
#
# 계획: scv/archive/20261111-wookiya1364-recommended-effort-ask/TESTS.md (T3~T14 — T1 · T2 · T15 는 래퍼 저장소와 실제 세션)
# 픽스처는 중립 id 만 쓴다 — 코어 payload 에 제공자 · 모델 이름을 넣지 않는다(tests/test-host-neutral.sh).
#
# Run: bash core/tests/test-effort-ask.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
MP="$CORE/scripts/model-prompting.sh"
HELP="$CORE/scripts/help.sh"
FIX="$CORE/tests/fixtures/model-prompting"
# shellcheck source=../scripts/lib/text.sh
source "$CORE/scripts/lib/text.sh" 2>/dev/null || true
# shellcheck source=../scripts/lib/model-prompting.sh
source "$CORE/scripts/lib/model-prompting.sh"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-eff.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
unset SCV_EFFORT_LOG_KEY SCV_EFFORT_RECOMMEND SCV_CHOICE_TOOL SCV_CHOICE_OFF_WHEN 2>/dev/null || true
cp -R "$FIX/guides" "$WORK/guides"
QA='Start at medium, the default.'
QB='Start with the xhigh level for coding and agentic use cases.'
printf '# model id\trecommended\tcondition\tquote\tsource\nvendor-model-a\tmedium\t-\t%s\tmodel-a.md\nvendor-model-b\txhigh\tcoding and agentic work: xhigh; otherwise at least high\t%s\tmodel-b.md\n' "$QA" "$QB" > "$WORK/guides/EFFORT.tsv"
cp -R "$FIX/guides" "$WORK/guides-notable"
prof() {  # <이름> <가이드 폴더> [<덧붙일 줄>…] → 프로필 경로
  local f="$WORK/profile-$1.env" g="$2"; shift 2
  { cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\nSCV_EFFORT_LOG_KEY=turnEffort\n' "$g"; for l in "$@"; do printf '%s\n' "$l"; done; } > "$f"
  printf '%s' "$f"
}
P="$(prof base "$WORK/guides")"
PCH="$(prof choice "$WORK/guides" 'SCV_CHOICE_TOOL=PickOne')"
PUN="$(prof unatt "$WORK/guides" 'SCV_CHOICE_TOOL=PickOne' 'SCV_CHOICE_OFF_WHEN=SCV_TEST_HEADLESS=1')"
PNT="$(prof notable "$WORK/guides-notable")"
PNK="$WORK/profile-nokey.env"; { cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\n' "$WORK/guides"; } > "$PNK"
new_repo() {  # <이름> → 빈 scv 저장소 경로 (세션 s1 의 help 표식 포함)
  local d="$WORK/$1"; mkdir -p "$d/scv/journal" "$d/scv/promote"; (cd "$d" && git init -q . 2>/dev/null)
  printf '{"session":"s1","protocol":1,"turn":3,"diag":"","diag_at":"","nonce":"abcd1234"}\n' > "$d/scv/journal/.help-state"
  # 실제 순서대로: 매 턴 훅이 먼저 이 세션이 사람 메시지를 받았다고 적는다(그래야 모델이 부르는 명령이 이 세션 자리를 쓴다)
  (cd "$d" && SCV_HOST_PROFILE="$P" bash "$MP" human --session s1 >/dev/null 2>&1) || true
  printf '%s' "$d"
}
log() {  # <저장소> <effort 값 또는 빈 값> → 세션 기록 파일(답 한 줄에 그 턴의 effort)
  local f="$1/tr.jsonl"
  printf '{"type":"user","message":{"content":[{"type":"text","text":"q"}]}}\n' > "$f"
  if [[ -n "${2:-}" ]]; then printf '{"type":"assistant","turnEffort":"%s","message":{"content":[{"type":"text","text":"a \\"turnEffort\\":\\"max\\""}]}}\n' "$2" >> "$f"; fi
  printf '%s' "$f"
}
seen() {  # <저장소> <모델> [<프로필>] — 도움말이 그 모델을 본 것으로 둔다
  (cd "$1" && SCV_HOST_PROFILE="${3:-$P}" bash "$MP" guide --model "$2" --session s1 >/dev/null 2>&1) || true
}
turn() {  # <저장소> <기록 파일> [<프로필>] → 매 턴 안내(prompt) 출력
  (cd "$1" && SCV_HOST_PROFILE="${3:-$P}" bash "$MP" prompt --session s1 --transcript "$2" 2>/dev/null)
}
asks() { grep -c '^\[SCV effort\]' <<<"$1" || true; }
ended() {  # <저장소> <답 글> [<프로필>] — 턴 끝 판정에 그 턴의 답을 넘긴다(물었는지는 코어가 가린다)
  (cd "$1" && printf '%s' "$2" | SCV_HOST_PROFILE="${3:-$P}" bash "$MP" stop --session s1 >/dev/null 2>&1) || true
}
Q_HM='이 세션의 effort 는 high 인데 권장은 medium 입니다. medium 로 바꿀까요, high 그대로 둘까요?'
NOQ='파일은 한 줄입니다.'

echo "T3. 다르면 요청 1번 — 지금 값 · 권장 값 · 근거 문장이 실린다"
R="$(new_repo t3)"; seen "$R" vendor-model-a; T="$(log "$R" high)"
o="$(turn "$R" "$T")"
if [[ "$(asks "$o")" == 1 ]] && grep -q 'effort 는 high 인데' <<<"$o" && grep -q '권하는 값은 medium 이다' <<<"$o" \
   && grep -qxF "근거(model-a.md): \"$QA\"" <<<"$o" && grep -q '글 질문 한 번으로 물어라' <<<"$o" && ! grep -q '^조건:' <<<"$o"; then
  ok "OK [T3] differs → asked once, with the quote"; else fail "[T3] $o"; fi

echo "T4. 물은 턴 뒤에는 같은 조건에서 다시 0번"
ended "$R" "$Q_HM"
o2="$(turn "$R" "$T")"; o3="$(turn "$R" "$T")"
# 새 세션(s2)도 같은 조건이면 묻지 않는다 — "한 번"은 프로젝트에서 한 번
(cd "$R" && SCV_HOST_PROFILE="$P" bash "$MP" human --session s2 >/dev/null 2>&1) || true
o4="$(cd "$R" && SCV_HOST_PROFILE="$P" bash "$MP" prompt --session s2 --transcript "$T" 2>/dev/null)"
[[ "$(asks "$o2")" == 0 && "$(asks "$o3")" == 0 && "$(asks "$o4")" == 0 ]] && ok "OK [T4] same condition → 0 · 0, and 0 in a new session" || fail "[T4] $(asks "$o2") · $(asks "$o3") · $(asks "$o4")"

echo "T5. 같으면 0번 — 안내가 끈 때와 바이트 단위로 같다"
R="$(new_repo t5)"; seen "$R" vendor-model-a; T="$(log "$R" medium)"
o="$(turn "$R" "$T")"
R2="$(new_repo t5off)"; printf '{\n  "SCV_EFFORT_RECOMMEND": "off"\n}\n' > "$R2/scv/scv_settings.json"; seen "$R2" vendor-model-a; T2="$(log "$R2" medium)"
ooff="$(turn "$R2" "$T2")"
strip() { sed -e 's/turn [0-9a-f]\{8\}/turn X/g' -e "s#$WORK/[a-z0-9]*#R#g" <<<"$1"; }
[[ "$(asks "$o")" == 0 && "$(strip "$o")" == "$(strip "$ooff")" ]] && ok "OK [T5] equal → 0, same bytes as switched off" || fail "[T5] $(asks "$o")"

echo "T6. 표에 없는 모델 0번"
R="$(new_repo t6)"; seen "$R" vendor-model-a-5; T="$(log "$R" low)"
o="$(turn "$R" "$T")"
[[ "$(asks "$o")" == 0 ]] && ok "OK [T6] model not in the table → 0" || fail "[T6] $o"

echo "T7. 지금 값을 모르면 0번 — 기록에 값이 없음 · 값 낱말이 아님 · 프로필에 키가 없음"
c=0
R="$(new_repo t7a)"; seen "$R" vendor-model-a; T="$(log "$R" "")"; [[ "$(asks "$(turn "$R" "$T")")" == 0 ]] && c=$((c + 1))
R="$(new_repo t7b)"; seen "$R" vendor-model-a; T="$(log "$R" banana)"; [[ "$(asks "$(turn "$R" "$T")")" == 0 ]] && c=$((c + 1))
R="$(new_repo t7c)"; seen "$R" vendor-model-a "$PNK"; T="$(log "$R" high)"; [[ "$(asks "$(turn "$R" "$T" "$PNK")")" == 0 ]] && c=$((c + 1))
# 본문 글 속의 같은 글자("…\"turnEffort\":\"max\"…")는 따옴표가 이스케이프돼 값으로 읽히지 않는다
R="$(new_repo t7d)"; seen "$R" vendor-model-a; T="$(log "$R" medium)"; [[ "$(asks "$(turn "$R" "$T")")" == 0 ]] && c=$((c + 1))
[[ $c == 4 ]] && ok "OK [T7] 4/4 unknown → 0" || fail "[T7] $c/4"

echo "T6. 안 물은 턴 — 다음 턴에 다시 싣는다 (0.89.2)"
R="$(new_repo t6b)"; seen "$R" vendor-model-a; T="$(log "$R" high)"
a1="$(asks "$(turn "$R" "$T")")"; ended "$R" "$NOQ"; a2="$(asks "$(turn "$R" "$T")")"
[[ "$a1$a2" == "11" ]] && ok "OK [T6] not asked → carried again" || fail "[T6] $a1$a2"

echo "T7. 세 번에서 멈춘다 — 답에 질문이 계속 없으면 1 · 1 · 1 · 0 · 0"
R="$(new_repo t7x)"; seen "$R" vendor-model-a; T="$(log "$R" high)"; seq=""
for _i in 1 2 3 4 5; do seq="$seq$(asks "$(turn "$R" "$T")")"; ended "$R" "$NOQ"; done
[[ "$seq" == "11100" ]] && ok "OK [T7] 11100" || fail "[T7] $seq"

echo "T7b. 선택 창으로 물은 턴 — 질문 글을 받으면 '물었다'로 적는다(턴 끝의 답 글에 질문이 없어도)"
R="$(new_repo t7c)"; seen "$R" vendor-model-a "$PCH"; T="$(log "$R" high)"
a1="$(asks "$(turn "$R" "$T" "$PCH")")"
(cd "$R" && printf '%s' '이 세션의 effort 가 high 인데 가이드는 medium 을 권합니다. 바꾸시겠어요?' | SCV_HOST_PROFILE="$PCH" bash "$MP" effort-seen --session s1 >/dev/null 2>&1)
ended "$R" "medium 로 바꾸는 법: 설정에서 고르면 됩니다." "$PCH"
a2="$(asks "$(turn "$R" "$T" "$PCH")")"
R2="$(new_repo t7d)"; seen "$R2" vendor-model-a "$PCH"; T2="$(log "$R2" high)"
b1="$(asks "$(turn "$R2" "$T2" "$PCH")")"
(cd "$R2" && printf '%s' '다음에 무엇을 할까요?' | SCV_HOST_PROFILE="$PCH" bash "$MP" effort-seen --session s1 >/dev/null 2>&1)
b2="$(asks "$(turn "$R2" "$T2" "$PCH")")"
[[ "$a1$a2 $b1$b2" == "10 11" ]] && ok "OK [T7b] 10 (effort question) · 11 (another question)" || fail "[T7b] $a1$a2 $b1$b2"

echo "T7c. 선택 창 답 훅 — 훅 입력의 질문 글이 코어에 닿는다"
AHOOK="$CORE/template/hooks/on-choice-answer.sh"
R="$(new_repo t7e)"; seen "$R" vendor-model-a "$PCH"; T="$(log "$R" high)"
if command -v jq >/dev/null 2>&1; then
  a1="$(asks "$(turn "$R" "$T" "$PCH")")"
  (cd "$R" && jq -cn '{session_id:"s1",tool_name:"PickOne",tool_input:{questions:[{question:"effort 를 medium 으로 바꾸시겠어요?"}]},tool_response:{answers:{"effort 를 medium 으로 바꾸시겠어요?":"그대로"}}}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$PCH" bash "$AHOOK" >/dev/null 2>&1)
  a2="$(asks "$(turn "$R" "$T" "$PCH")")"
  [[ "$a1$a2" == "10" ]] && ok "OK [T7c] the answer hook marks it asked" || fail "[T7c] $a1$a2"
else ok "OK [T7c] (skip) jq unavailable"; fi

echo "T8. 조건이 달라지면 다시 1번 — 값이 바뀜 · 모델이 바뀜 · 권장으로 갔다가 다시 벗어남"
Q_LM='effort 는 low 인데 권장은 medium 입니다. medium 로 바꿀까요, low 그대로 둘까요?'
Q_MX='effort 는 medium 인데 권장은 xhigh 입니다. xhigh 로 바꿀까요, medium 그대로 둘까요?'
R="$(new_repo t8)"; seen "$R" vendor-model-a; T="$(log "$R" high)"
a1="$(asks "$(turn "$R" "$T")")"; ended "$R" "$Q_HM"; a2="$(asks "$(turn "$R" "$T")")"
T="$(log "$R" low)"; b1="$(asks "$(turn "$R" "$T")")"; ended "$R" "$Q_LM"; b2="$(asks "$(turn "$R" "$T")")"
seen "$R" vendor-model-b; T="$(log "$R" medium)"; c1="$(asks "$(turn "$R" "$T")")"; ended "$R" "$Q_MX"; c2="$(asks "$(turn "$R" "$T")")"
seen "$R" vendor-model-a; T="$(log "$R" medium)"; d0="$(asks "$(turn "$R" "$T")")"
T="$(log "$R" low)"; d1="$(asks "$(turn "$R" "$T")")"
# 물은 조건은 줄로 쌓인다: 모델 a 가 권장으로 돌아오면 a 의 줄만 지워지고 b 의 줄은 남는다
kept="$(grep -c '^vendor-model-b|' "$R/scv/journal/.effort-asked" 2>/dev/null || true)"; gone="$(grep -c '^vendor-model-a|' "$R/scv/journal/.effort-asked" 2>/dev/null || true)"
[[ "$a1$a2 $b1$b2 $c1$c2 $d0$d1" == "10 10 10 01" && "$kept" == 1 && "$gone" == 1 ]] && ok "OK [T8] 10 10 10 01" || fail "[T8] $a1$a2 $b1$b2 $c1$c2 $d0$d1 kept=$kept gone=$gone"

echo "T9. 끄는 설정 — 0번, 상태 파일도 안 생긴다"
R="$(new_repo t9)"; printf '{\n  "SCV_EFFORT_RECOMMEND": "off"\n}\n' > "$R/scv/scv_settings.json"; seen "$R" vendor-model-a; T="$(log "$R" high)"
o="$(turn "$R" "$T")"
[[ "$(asks "$o")" == 0 && ! -e "$R/scv/journal/.effort-asked" ]] && ok "OK [T9] off → 0, no state file" || fail "[T9] $o"

echo "T10. 조건이 달린 모델 — 조건 글이 글자 그대로 실린다"
R="$(new_repo t10)"; seen "$R" vendor-model-b; T="$(log "$R" high)"
o="$(turn "$R" "$T")"
[[ "$(asks "$o")" == 1 ]] && grep -qxF '조건: coding and agentic work: xhigh; otherwise at least high' <<<"$o" && grep -qxF "근거(model-b.md): \"$QB\"" <<<"$o" \
  && ok "OK [T10] the condition is carried verbatim" || fail "[T10] $o"

echo "T11. 바꾸는 것은 사용자 — 선택 창이 있으면 선택 창으로, 값을 바꾸라는 지시는 없다"
R="$(new_repo t11)"; seen "$R" vendor-model-a "$PCH"; T="$(log "$R" high)"
o="$(turn "$R" "$T" "$PCH")"; l="$(grep '^\[SCV effort\]' <<<"$o")"
if grep -q "선택 창으로 한 번 물어라 — 첫 보기(추천) 'medium 로 바꿈', 둘째 'high 그대로'" <<<"$l" && grep -q '바꾸는 것은 사용자다 — 값을 직접 바꾸지 말고' <<<"$l" \
   && ! grep -q -E 'effort 를 (medium|high) (으)?로 (바꿔라|설정해라|올려라|낮춰라)' <<<"$l"; then
  ok "OK [T11] ask through the choice tool; the user changes it"; else fail "[T11] $l"; fi

echo "T11b. 사람이 없는 실행 — 묻지 않고, 물었다고 적지도 않는다(사람이 돌아오면 그때 묻는다)"
R="$(new_repo t11b)"; seen "$R" vendor-model-a "$PUN"; T="$(log "$R" high)"
o="$(SCV_TEST_HEADLESS=1 turn "$R" "$T" "$PUN")"
o2="$(turn "$R" "$T" "$PUN")"
[[ "$(asks "$o")" == 0 && "$(asks "$o2")" == 1 ]] && ok "OK [T11b] unattended → 0, then 1 when attended" || fail "[T11b] $(asks "$o") · $(asks "$o2")"

echo "T12. 매 턴 훅 — 훅 입력의 기록 경로로 값을 읽어 그 줄을 싣고, 다음 턴에는 싣지 않는다"
HOOK="$CORE/template/hooks/on-user-prompt.sh"
R="$(new_repo t12)"; seen "$R" vendor-model-a; T="$(log "$R" high)"
hk() { (cd "$R" && jq -cn --arg t "$T" '{prompt:"로그인 고쳐",session_id:"s1",transcript_path:$t}' | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$P" bash "$HOOK" 2>/dev/null); }
if command -v jq >/dev/null 2>&1; then
  h1="$(hk)"; ended "$R" "$Q_HM"; h2="$(hk)"
  [[ "$(grep -c '\[SCV effort\]' <<<"$h1")" == 1 && "$(grep -c '\[SCV effort\]' <<<"$h2")" == 0 ]] && grep -qF "$QA" <<<"$h1" \
    && ok "OK [T12] the hook carries it once" || fail "[T12] $(grep -c '\[SCV effort\]' <<<"$h1") · $(grep -c '\[SCV effort\]' <<<"$h2")"
else
  ok "OK [T12] (skip) jq unavailable"
fi

echo "T13. 도움말이 effort 를 받는다 — 호스트 값이 없을 때 그 값을 쓰고, 없이 부르면 출력이 같다"
R="$(new_repo t13)"
h1="$(cd "$R" && SCV_HOST_PROFILE="$PNK" bash "$HELP" --with-context --model vendor-model-a 2>/dev/null)"
R2="$(new_repo t13b)"
h2="$(cd "$R2" && SCV_HOST_PROFILE="$PNK" bash "$HELP" --with-context --model vendor-model-a --effort high 2>/dev/null)"
T="$(log "$R2" "")"
(cd "$R2" && SCV_HOST_PROFILE="$PNK" bash "$MP" guide --model vendor-model-a --session s1 --effort high >/dev/null 2>&1)
o="$(turn "$R2" "$T" "$PNK")"
R3="$(new_repo t13c)"; (cd "$R3" && SCV_HOST_PROFILE="$P" bash "$MP" guide --model vendor-model-a --session s1 --effort high >/dev/null 2>&1); T3="$(log "$R3" medium)"
o3="$(turn "$R3" "$T3")"
if [[ "$(strip "$h1")" == "$(strip "$h2")" && "$(asks "$o")" == 1 && "$(asks "$o3")" == 0 ]]; then
  ok "OK [T13] help passes it on; the host's value wins"; else fail "[T13] same=$([[ "$(strip "$h1")" == "$(strip "$h2")" ]] && echo y || echo n) asks=$(asks "$o") host-first=$(asks "$o3")"; fi

echo "T14. 표가 없는 호스트 — 그대로"
R="$(new_repo t14)"; seen "$R" vendor-model-a "$PNT"; T="$(log "$R" high)"
o="$(turn "$R" "$T" "$PNT")"
[[ "$(asks "$o")" == 0 && ! -e "$R/scv/journal/.effort-asked" ]] && ok "OK [T14] no table → 0" || fail "[T14] $o"

echo "T16. 순수부 — 표 줄 고르기 · 기록에서 값 꺼내기 · 판정 · 안내 줄"
c=0
TB="$(cat "$WORK/guides/EFFORT.tsv")"
[[ "$(scv_mp_effort_row "$TB" vendor-model-a)" == $'medium\t-\t'"$QA"$'\tmodel-a.md' ]] && c=$((c + 1))
[[ -z "$(scv_mp_effort_row "$TB" nobody)" && -z "$(scv_mp_effort_row $'m\tfast\t-\tq\ts' m)" && -z "$(scv_mp_effort_row "$TB" "")" ]] && c=$((c + 1))
[[ "$(scv_mp_effort_from_log $'"k":"low"\n"k":"high"' k)" == high && -z "$(scv_mp_effort_from_log '"k":"banana"' k)" && -z "$(scv_mp_effort_from_log '"k":"low"' 'k"x')" ]] && c=$((c + 1))
r=$'medium\t-\tq\ts'
[[ "$(scv_mp_effort_verdict on high "$r" "" m)" == ask && "$(scv_mp_effort_verdict on high "$r" "asked" m)" == asked && "$(scv_mp_effort_verdict on medium "$r" "" m)" == same \
   && "$(scv_mp_effort_verdict on high "$r" "shown:2" m)" == ask && "$(scv_mp_effort_verdict on high "$r" "shown:3" m)" == asked \
   && "$(scv_mp_effort_verdict on "" "$r" "" m)" == unknown && "$(scv_mp_effort_verdict on high "" "" m)" == unknown && "$(scv_mp_effort_verdict off high "$r" "" m)" == off ]] && c=$((c + 1))
[[ -z "$(scv_mp_effort_block same m high "$r" choice)" && -z "$(scv_mp_effort_block ask m high "" choice)" && "$(scv_mp_effort_block ask m high "$r" choice | wc -l | tr -d ' ')" == 1 ]] && c=$((c + 1))
[[ "$(scv_mp_effort_word High)" == high && -z "$(scv_mp_effort_word banana)" && "$(scv_mp_effort_word ' XHIGH ')" == xhigh ]] && c=$((c + 1))
k='m|high|medium'
[[ -z "$(scv_mp_effort_state_of "" "$k")" && "$(scv_mp_effort_state_of "$k" "$k")" == asked && "$(scv_mp_effort_state_of "$k|shown:2" "$k")" == "shown:2" \
   && "$(scv_mp_effort_state_next "" "$k" shown)" == "$k|shown:1" && "$(scv_mp_effort_state_next "$k|shown:1" "$k" shown)" == "$k|shown:2" \
   && "$(scv_mp_effort_state_next $'a|low|high|asked\n'"$k|shown:2" "$k" asked)" == $'a|low|high|asked\n'"$k|asked" && "$(scv_mp_effort_state_next "$k|asked" "$k" shown)" == "$k|asked" ]] && c=$((c + 1))
[[ "$(scv_mp_effort_asked_in "" "effort 를 high 로 바꾸시겠어요?" medium high)" == 1 && "$(scv_mp_effort_asked_in "effort 는 low 인데 권장은 high. high 로 바꿀까요, low 그대로 둘까요?" "" low high)" == 1 \
   && "$(scv_mp_effort_asked_in "effort 를 high 로 올렸습니다." "" low high)" == 0 && "$(scv_mp_effort_asked_in "파일은 한 줄입니다." "" low high)" == 0 ]] && c=$((c + 1))
[[ $c == 8 ]] && ok "OK [T16] 8/8" || fail "[T16] $c/8"

echo "T17. 프로필 도구 — 검사가 새 키를 받고, 프로필 만들기가 옮긴다 (0.89.1 — 0.89.0 래퍼 릴리스가 여기서 막혔다)"
VH="$CORE/../tools/validate-host-profile.sh"; MZ="$CORE/../tools/materialize-profile.sh"; FXE="$CORE/../tests/fixtures/codex.env"
if [[ -f "$VH" && -f "$MZ" && -f "$FXE" ]]; then
  { grep -v '^SCV_EFFORT_LOG_KEY' "$FXE"; printf 'SCV_EFFORT_LOG_KEY=turnEffort\n'; } > "$WORK/pe1.env"
  { grep -v '^SCV_EFFORT_LOG_KEY' "$FXE"; printf 'SCV_EFFORT_LOG_KEY=turn effort"\n'; } > "$WORK/pe2.env"
  a=0; bash "$VH" --profile "$WORK/pe1.env" >/dev/null 2>&1 || a=$?
  b=0; bash "$VH" --profile "$WORK/pe2.env" >/dev/null 2>&1 || b=$?
  mkdir -p "$WORK/mcore"; cp -R "$CORE/." "$WORK/mcore/"
  d=0; bash "$MZ" --root "$WORK/mcore" --profile "$WORK/pe1.env" >/dev/null 2>&1 || d=$?
  [[ $a == 0 && $b != 0 && $d == 0 ]] && grep -qx 'SCV_EFFORT_LOG_KEY=turnEffort' "$WORK/mcore/host-profile.env" \
    && ok "OK [T17] validator accepts it, rejects a bad name, materialize carries it" || fail "[T17] validate=$a bad=$b materialize=$d"
  # 다시 안 놓치게: 읽는 쪽(lib/host-profile.sh)이 아는 키는 검사도 받고 프로필 만들기도 옮겨야 한다
  miss=""
  for k in $(sed -n 's/^    \(SCV_[A-Z_]*\)) .*/\1/p' "$CORE/scripts/lib/host-profile.sh"); do
    grep -q "$k" "$VH" || miss="$miss validate:$k"
    grep -q "$k" "$MZ" || miss="$miss materialize:$k"
  done
  [[ -z "$miss" ]] && ok "OK [T17b] every key the reader knows is known to both tools" || fail "[T17b] missing:$miss"
else
  ok "OK [T17] (skip) profile tools not in this layout"; ok "OK [T17b] (skip)"
fi

echo
echo "── $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
