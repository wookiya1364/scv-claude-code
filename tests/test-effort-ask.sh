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

echo "T3. 다르면 요청 1번 — 지금 값 · 권장 값 · 근거 문장이 실린다"
R="$(new_repo t3)"; seen "$R" vendor-model-a; T="$(log "$R" high)"
o="$(turn "$R" "$T")"
if [[ "$(asks "$o")" == 1 ]] && grep -q 'effort 는 high 인데' <<<"$o" && grep -q '권하는 값은 medium 이다' <<<"$o" \
   && grep -qxF "근거(model-a.md): \"$QA\"" <<<"$o" && grep -q '글 질문 한 번으로 물어라' <<<"$o" && ! grep -q '^조건:' <<<"$o"; then
  ok "OK [T3] differs → asked once, with the quote"; else fail "[T3] $o"; fi

echo "T4. 같은 조건에서 다시 0번"
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

echo "T8. 조건이 달라지면 다시 1번 — 값이 바뀜 · 모델이 바뀜 · 권장으로 갔다가 다시 벗어남"
R="$(new_repo t8)"; seen "$R" vendor-model-a; T="$(log "$R" high)"
a1="$(asks "$(turn "$R" "$T")")"; a2="$(asks "$(turn "$R" "$T")")"
T="$(log "$R" low)"; b1="$(asks "$(turn "$R" "$T")")"; b2="$(asks "$(turn "$R" "$T")")"
seen "$R" vendor-model-b; T="$(log "$R" medium)"; c1="$(asks "$(turn "$R" "$T")")"; c2="$(asks "$(turn "$R" "$T")")"
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
  h1="$(hk)"; h2="$(hk)"
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
[[ "$(scv_mp_effort_verdict on high "$r" "" m)" == ask && "$(scv_mp_effort_verdict on high "$r" "m|high|medium" m)" == asked && "$(scv_mp_effort_verdict on medium "$r" "" m)" == same \
   && "$(scv_mp_effort_verdict on "" "$r" "" m)" == unknown && "$(scv_mp_effort_verdict on high "" "" m)" == unknown && "$(scv_mp_effort_verdict off high "$r" "" m)" == off ]] && c=$((c + 1))
[[ -z "$(scv_mp_effort_block same m high "$r" choice)" && -z "$(scv_mp_effort_block ask m high "" choice)" && "$(scv_mp_effort_block ask m high "$r" choice | wc -l | tr -d ' ')" == 1 ]] && c=$((c + 1))
[[ "$(scv_mp_effort_word High)" == high && -z "$(scv_mp_effort_word banana)" && "$(scv_mp_effort_word ' XHIGH ')" == xhigh ]] && c=$((c + 1))
[[ $c == 6 ]] && ok "OK [T16] 6/6" || fail "[T16] $c/6"

echo
echo "── $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
