#!/usr/bin/env bash
export SCV_STOP_MODE=block   # 이 시험은 막힘(block)을 본다
# test-rewrite-guide-only.sh — 다시 쓰기는 가이드만(0.88.0): 요구 항목 표 · 낱말 규칙이 빠졌는지, 그러면서도 등록 · 답 맨 위
# 인용 · 쓰기 문 · 종료 훅 · SCV 원칙의 내용이 그대로 도는지 본다.
#
# 계획: scv/archive/20261110-wookiya1364-rewrite-by-guide-only/TESTS.md (T1~T14 — 래퍼 쪽 T15~T19 는 래퍼 저장소의 시험)
# 픽스처는 중립 id 만 쓴다 — 코어 payload 에 제공자·모델 이름을 넣지 않는다(tests/test-host-neutral.sh).
#
# Run: bash core/tests/test-rewrite-guide-only.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$CORE/scripts/lib/model-prompting.sh"
MP="$CORE/scripts/model-prompting.sh"
HELP="$CORE/scripts/help.sh"
HOOK="$CORE/template/hooks/on-user-prompt.sh"
STOP="$CORE/template/hooks/on-stop.sh"
FIX="$CORE/tests/fixtures/model-prompting"
PRIN="$CORE/contracts/rewrite-principle.md"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-rgo.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\n' "$WORK/guides"; } > "$WORK/profile.env"
mkdir -p "$WORK/noguides"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\n' "$WORK/noguides"; } > "$WORK/profile-noguides.env"
new_repo() {  # <이름> [<언어>] → 빈 scv 저장소 경로 (세션 s1 의 help 표식 포함)
  local d="$WORK/$1"; mkdir -p "$d/scv/journal" "$d/scv/promote" "$d/src"; (cd "$d" && git init -q . 2>/dev/null)
  printf '{"session":"s1","protocol":1,"turn":3,"diag":"","diag_at":"","nonce":"abcd1234"}\n' > "$d/scv/journal/.help-state"
  [[ -n "${2:-}" ]] && printf '{\n  "SCV_LANG": "%s"\n}\n' "$2" > "$d/scv/scv_settings.json"
  printf '%s' "$d"
}
tf() { printf '%s/scv/journal/.help-turns/s1/%s' "$1" "$2"; }
hook() {  # <저장소> [<프로필>] → 매 턴 훅 출력 (help 를 부른 턴으로 둔다)
  (cd "$1" && jq -cn '{prompt:"로그인 고쳐",session_id:"s1"}' | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="${2:-$WORK/profile.env}" bash "$HOOK" 2>/dev/null)
  (cd "$1" && SCV_HOST_PROFILE="${2:-$WORK/profile.env}" bash "$MP" helped --session s1 >/dev/null 2>&1) || true
}
reg() {  # <저장소> <제출 글> → 등록 출력
  (cd "$1" && printf '%s\n' "$2" | SCV_HOST_PROFILE="$WORK/profile.env" bash "$MP" register --model vendor-model-a --session s1 2>/dev/null)
}
gate() {  # <저장소> <파일> → 가드 출력
  (cd "$1" && printf '{"cwd":"%s","session_id":"s1","tool_name":"Write","tool_input":{"file_path":"%s/%s"}}' "$1" "$1" "$2" \
     | SCV_HOST_PROFILE="$WORK/profile.env" SCV_GUARD_STATE="$WORK/gstate" SCV_GUARD_RULE_B=off SCV_GUARD_SCRIPTS="$CORE/scripts" SCV_GUARD_MODE=gate-write bash "$CORE/template/hooks/guard.sh" 2>/dev/null)
}
stop() {  # <저장소> <답> → 종료 훅 stdout
  local tr="$WORK/tr-$RANDOM.jsonl"
  printf '{"type":"user","message":{"content":[{"type":"text","text":"q"}]}}\n' > "$tr"
  jq -cn --arg t "$2" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"text",text:$t}]}}' >> "$tr"
  (cd "$1" && jq -cn --arg p "$tr" --arg a "$2" '{transcript_path:$p,last_assistant_message:$a,stop_hook_active:false,session_id:"s1"}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile.env" GIT_AUTHOR_NAME="Hook User" bash "$STOP" 2>/dev/null)
}
TWO="$(printf 'scope | - | src/login.js\nrewrite | - | Fix the login bug until the login test passes\n')"

echo "T1. 등록은 다시 쓴 요청과 범위만으로 통과한다"
R="$(new_repo t1)"; hook "$R" >/dev/null; tok="$(head -1 "$(tf "$R" .help-turn)" 2>/dev/null)"
o="$(reg "$R" "$TWO")"
if [[ -n "$tok" ]] && grep -qx "REGISTERED: turn $tok · model vendor-model-a" <<<"$o" && grep -qx 'REWRITE: Fix the login bug until the login test passes' <<<"$o" && ! grep -q 'missing' <<<"$o"; then
  ok "OK [T1] two lines register"; else fail "[T1] $o"; fi

echo "T2. 다시 쓴 요청이 없으면 등록이 실패한다"
R="$(new_repo t2)"; hook "$R" >/dev/null
o="$(reg "$R" "scope | - | src/login.js")"
if grep -q '^REGISTER: incomplete' <<<"$o" && grep -q 'missing rewrite' <<<"$o" && ! grep -q '^REGISTERED' <<<"$o" && [[ ! -f "$(tf "$R" .help-rewrite)" ]]; then
  ok "OK [T2] no rewrite → incomplete, nothing saved"; else fail "[T2] $o"; fi

echo "T3. 범위가 없으면 등록이 실패한다"
R="$(new_repo t3)"; hook "$R" >/dev/null
o="$(reg "$R" "rewrite | - | Fix it")"
if grep -q '^REGISTER: incomplete' <<<"$o" && grep -q 'missing scope' <<<"$o" && ! grep -q '^REGISTERED' <<<"$o" && [[ ! -f "$(tf "$R" .help-rewrite)" ]]; then
  ok "OK [T3] no scope → incomplete, nothing saved"; else fail "[T3] $o"; fi

echo "T4. 옛 모양 등록도 통과한다 (요구 항목 줄은 무시)"
R="$(new_repo t4)"; hook "$R" >/dev/null
OLD="$(printf 'goal | msg | fix the login bug\ncontext | na | none\nfinish | ctx | the test passes\nscope | msg | src/login.js\noutput | na | -\nstop | na | -\nact-or-suggest | msg | fix\ndepth | bogus-status | -\nrewrite | - | Fix the login bug\n')"
o="$(reg "$R" "$OLD")"
if [[ "$(grep -c '^REGISTERED: ' <<<"$o")" == 1 ]] && [[ -z "$(gate "$R" src/a.js)" || "$(gate "$R" src/a.js)" != *'"deny"'* ]]; then
  ok "OK [T4] an old-shape submission registers and the write gate opens"; else fail "[T4] $o"; fi

echo "T5. 범위가 '변경 없음'이면 프로젝트 파일 편집이 거절된다"
c=0
R="$(new_repo t5a)"; hook "$R" >/dev/null; reg "$R" "$(printf 'scope | - | 변경 없음 — 읽기만\nrewrite | - | 알려 줘\n')" >/dev/null
o="$(gate "$R" src/a.js)"; grep -q '"permissionDecision":"deny"' <<<"$o" && grep -q '변경 없음' <<<"$o" && c=$((c + 1)) || echo "      (a) a no-change scope must refuse the edit: $o"
R="$(new_repo t5b)"; hook "$R" >/dev/null; reg "$R" "$TWO" >/dev/null
o="$(gate "$R" src/a.js)"; ! grep -q '"permissionDecision":"deny"' <<<"$o" && c=$((c + 1)) || echo "      (b) a scope that names a target must allow the edit: $o"
R="$(new_repo t5c)"; hook "$R" >/dev/null
o="$(gate "$R" src/a.js)"; grep -q '"permissionDecision":"deny"' <<<"$o" && grep -q 'register --model' <<<"$o" && ! grep -q 'checklist' <<<"$o" && c=$((c + 1)) || echo "      (c) an unregistered turn must refuse and name the register command only: $o"
if [[ $c -eq 3 ]]; then ok "OK [T5] 3/3 write gate"; else fail "[T5] $c/3"; fi

echo "T6. 매 턴 안내문에 요구 항목 문구가 없다"
c=0
R="$(new_repo t6)"; h="$(hook "$R")"
grep -q '^\[SCV 프롬프트\] ' <<<"$h" && grep -q 'register --model' <<<"$h" && grep -q "답 맨 위에" <<<"$h" && c=$((c + 1)) || echo "      (a) the block must keep the register command and the quote rule"
blk="$(grep -A1 '^\[SCV 프롬프트\] ' <<<"$h")"
! grep -q -E 'msg · ctx|1:1|checklist|항목 \[|항목마다' <<<"$blk" && c=$((c + 1)) || echo "      (b) item wording left in the block: $blk"
if [[ $c -eq 2 ]]; then ok "OK [T6] 2/2 per-turn block"; else fail "[T6] $c/2"; fi

echo "T7. 낱말 규칙이 어디에도 실리지 않는다"
c=0
R="$(new_repo t7 korean)"; h="$(hook "$R")"
o="$(cd "$R" && SCV_HOST_PROFILE="$WORK/profile.env" SCV_TODAY=2026-09-27 bash "$HELP" --with-context --model vendor-model-a 2>/dev/null)"
! grep -q '^STE:' <<<"$o" && ! grep -q '^STE:' <<<"$h" && c=$((c + 1)) || echo "      (a) STE lines still printed"
[[ ! -e "$CORE/contracts/rewrite-ste.md" ]] && c=$((c + 1)) || echo "      (b) the word-list contract still exists"
! grep -q 'SCV_REWRITE_STE' "$CORE/template/scv/scv_settings.example.json" && c=$((c + 1)) || echo "      (c) the settings example still names the switch"
! grep -rq 'SCV_REWRITE_STE' "$CORE/scripts" "$CORE/template/hooks" "$CORE/protocols" && c=$((c + 1)) || echo "      (d) a script, hook or protocol still reads the switch"
if [[ $c -eq 4 ]]; then ok "OK [T7] 4/4 no word list"; else fail "[T7] $c/4"; fi

echo "T8. 옛 설정값이 남아 있어도 오류가 없다"
R="$(new_repo t8)"; printf '{\n  "SCV_REWRITE_STE": "on",\n  "SCV_LANG": "korean"\n}\n' > "$R/scv/scv_settings.json"
hook "$R" >/dev/null
e1="$(cd "$R" && SCV_HOST_PROFILE="$WORK/profile.env" bash "$HELP" --with-context --model vendor-model-a 2>&1 >/dev/null; echo "rc=$?")"
e2="$(cd "$R" && printf '%s\n' "$TWO" | SCV_HOST_PROFILE="$WORK/profile.env" bash "$MP" register --model vendor-model-a --session s1 2>&1 >/dev/null; echo "rc=$?")"
if [[ "$e1" == "rc=0" && "$e2" == "rc=0" ]]; then ok "OK [T8] a leftover switch value is ignored quietly"; else fail "[T8] help [$e1] register [$e2]"; fi

echo "T9. 다시 쓴 요청에 SCV 원칙 표식이 붙지 않는다"
R="$(new_repo t9 korean)"; hook "$R" >/dev/null
o="$(reg "$R" "$TWO")"
if grep -qx 'REWRITE: Fix the login bug until the login test passes' <<<"$o" && ! grep -q 'SCV 원칙' <<<"$o" && ! grep -q '^PRINCIPLE' <<<"$o" && [[ "$(grep -c . <<<"$o")" == 2 ]]; then
  ok "OK [T9] the REWRITE line is the text as given; no principle in the register output"; else fail "[T9] $o"; fi

echo "T10. SCV 원칙의 내용이 매 턴 안내에 글자 그대로 있다"
c=0
SEC="$(bash -c 'source "$1"; scv_mp_principle_section "$(cat "$2")" korean' _ "$LIB" "$PRIN")"
TXT="$(bash -c 'source "$1"; scv_mp_principle_text "$2"' _ "$LIB" "$SEC")"
R="$(new_repo t10 korean)"; h="$(hook "$R")"
[[ -n "$TXT" && "$h" == *"PRINCIPLE:"$'\n'"$TXT"$'\n'* ]] && c=$((c + 1)) || echo "      (a) the section text must sit verbatim under PRINCIPLE:"
miss=0; while IFS= read -r line; do [[ -z "$line" ]] && continue; grep -qxF -- "$line" <<<"$h" || miss=$((miss + 1)); done <<< "$TXT"
[[ $miss -eq 0 ]] && c=$((c + 1)) || echo "      (b) $miss principle line(s) differ from the contract file"
for w in "듣기 좋은 말 대신 사실" "'항목 | 해결책 | 추천' 세 칸" "2배 이상"; do grep -qF -- "$w" <<<"$h" || { echo "      (c) missing: $w"; c=$((c - 1)); }; done; c=$((c + 1))
h2="$(hook "$R")"; grep -q '^PRINCIPLE: (' <<<"$h2" && ! grep -qF -- "$(head -1 <<<"$TXT")" <<<"$h2" && c=$((c + 1)) || echo "      (d) the next turn must carry one line only"
R="$(new_repo t10off)"; printf '{\n  "SCV_REWRITE_PRINCIPLE": "off"\n}\n' > "$R/scv/scv_settings.json"
! grep -q '^PRINCIPLE' <<<"$(hook "$R")" && c=$((c + 1)) || echo "      (e) switch off must print nothing"
if [[ $c -eq 5 ]]; then ok "OK [T10] 5/5 principle rides the per-turn hook"; else fail "[T10] $c/5"; fi

echo "T11. 끝 메시지의 문제 표는 여전히 막힌다"
c=0
QUOTE='> **Rewritten request**: Fix the login bug until the login test passes'
R="$(new_repo t11)"; hook "$R" >/dev/null; reg "$R" "$TWO" >/dev/null
o="$(stop "$R" "$(printf '%s\n\n**결론**\n- 됨\n\n| 단위 | 해결책 | 추천 | 생길 수 있는 문제 |\n|---|---|---|---|\n| a | ①x | ① 이유 | P1 |\n' "$QUOTE")")"
[[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && grep -q 'SCV 원칙' <<<"$o" && c=$((c + 1)) || echo "      (a) a problem table must block: [$o]"
R="$(new_repo t11b)"; hook "$R" >/dev/null; reg "$R" "$TWO" >/dev/null
o="$(stop "$R" "$(printf '%s\n\n**결론**\n- 됨\n\n| 항목 | 해결책 | 추천 |\n|---|---|---|\n| 속도 | ① 캐시 | ① |\n' "$QUOTE")")"
[[ -z "$o" ]] && c=$((c + 1)) || echo "      (b) a solution table must pass: [$o]"
if [[ $c -eq 2 ]]; then ok "OK [T11] 2/2 problem table gate kept"; else fail "[T11] $c/2"; fi

echo "T12. 다시 쓴 요청 인용이 답 맨 위에 없으면 종료 훅이 막는다"
c=0
R="$(new_repo t12)"; hook "$R" >/dev/null; reg "$R" "$TWO" >/dev/null
o="$(stop "$R" "$(printf '%s\n\n**결론**\n- 됨\n' "$QUOTE")")"; [[ -z "$o" ]] && c=$((c + 1)) || echo "      (a) quote on top must pass: [$o]"
o="$(stop "$R" "$(printf '**결론**\n- 됨\n')")"; [[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && grep -q '인용' <<<"$o" && c=$((c + 1)) || echo "      (b) no quote must block: [$o]"
R="$(new_repo t12c)"; hook "$R" >/dev/null
o="$(stop "$R" "answer")"; [[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && grep -q 'register --model' <<<"$o" && ! grep -q 'checklist' <<<"$o" && c=$((c + 1)) || echo "      (c) an unregistered turn must block and name the register command only: [$o]"
if [[ $c -eq 3 ]]; then ok "OK [T12] 3/3 stop gate kept"; else fail "[T12] $c/3"; fi

echo "T13. 가이드가 없는 모델은 공통 원문을 읽으라고 나온다"
c=0
R="$(new_repo t13)"
o="$(cd "$R" && SCV_HOST_PROFILE="$WORK/profile.env" SCV_TODAY=2026-09-27 bash "$HELP" --with-context --model other-model 2>/dev/null)"
grep -qx 'GUIDE: load common' <<<"$o" && [[ "$(grep -c '^GUIDE_FILE: ' <<<"$o")" == 1 ]] && grep -qx "GUIDE_FILE: $WORK/guides/common.md" <<<"$o" && c=$((c + 1)) || echo "      (a) expected the common guide alone: $o"
cmd="$(sed -n 's/^GUIDE_MARK_CMD: //p' <<<"$o" | head -1)"
(cd "$R" && SCV_HOST_PROFILE="$WORK/profile.env" eval "$cmd" >/dev/null 2>&1)
o2="$(cd "$R" && SCV_HOST_PROFILE="$WORK/profile.env" SCV_TODAY=2026-09-27 bash "$HELP" --with-context --model other-model 2>/dev/null)"
grep -qx 'GUIDE: loaded common' <<<"$o2" && c=$((c + 1)) || echo "      (b) after the mark it must be loaded: $(grep '^GUIDE' <<<"$o2")"
# 그 모델의 행이 나중에 생기면 다시 읽는다(읽음 기록의 id 가 다르다)
printf 'other-model\tmodel-b\tmodel-b.md\thttps://example.invalid/b.md\t2026-09-01\n' >> "$WORK/guides/INDEX.tsv"
o3="$(cd "$R" && SCV_HOST_PROFILE="$WORK/profile.env" SCV_TODAY=2026-09-27 bash "$MP" guide --model other-model 2>/dev/null)"
grep -qx 'GUIDE: load model-b' <<<"$o3" && c=$((c + 1)) || echo "      (c) a row added later must load again: $(grep '^GUIDE' <<<"$o3")"
grep -v '^other-model' "$WORK/guides/INDEX.tsv" > "$WORK/guides/INDEX.tsv.new" && mv "$WORK/guides/INDEX.tsv.new" "$WORK/guides/INDEX.tsv"
R="$(new_repo t13n)"
o4="$(cd "$R" && SCV_HOST_PROFILE="$WORK/profile-noguides.env" bash "$HELP" --with-context --model other-model 2>/dev/null)"
grep -qx 'GUIDE: none' <<<"$o4" && c=$((c + 1)) || echo "      (d) no guides folder → none: $(grep '^GUIDE' <<<"$o4")"
h="$(hook "$R" "$WORK/profile-noguides.env")"; ! grep -q 'SCV 프롬프트' <<<"$h" && c=$((c + 1)) || echo "      (e) no guides folder → no registration block"
if [[ $c -eq 5 ]]; then ok "OK [T13] 5/5 common guide for a model with no row"; else fail "[T13] $c/5"; fi

echo "T14. 매 턴 안내 분량 — 등록 블록이 0.87 의 것보다 길지 않다"
OLD_BLOCK_BYTES=880   # 0.87.4 의 scv_mp_turn_block(on · 모델 m-1 · 목록 없음 · 세션 없음) 출력 크기 — git show v0.87.4 의 함수로 잰 값(2026-11-10)
n="$(bash -c 'source "$1"; scv_mp_turn_block on t m-1 x.sh' _ "$LIB" | wc -c | tr -d ' ')"
if (( n <= OLD_BLOCK_BYTES )); then ok "OK [T14] per-turn block ${n}B ≤ ${OLD_BLOCK_BYTES}B"; else fail "[T14] per-turn block ${n}B > ${OLD_BLOCK_BYTES}B"; fi

echo
echo "── $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
