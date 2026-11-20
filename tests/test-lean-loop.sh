#!/usr/bin/env bash
# test-lean-loop.sh — 가벼운 루프(SCV_LEAN_LOOP) · 처음과 끝만 묻기(SCV_ASK_MODE)
# (계획 20261120-wookiya1364-lean-loop · TESTS.md T1 ~ T6).
#
# 장부(help 부르기 · 등록 명령 · 규약 읽음 표시)를 훅이 대신 하는지, 계획 기록 검사가 막지 않고 기록만 남기는지,
# ends 모드가 자리마다 맞게 묻는지, 기본값은 출력이 그대로인지 본다. 픽스처는 중립 도구 이름(PickTool)만 쓴다.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"
MP="$CORE/scripts/model-prompting.sh"; TC="$CORE/scripts/turn-check.sh"; FIX="$CORE/tests/fixtures/model-prompting"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unset SCV_LEAN_LOOP SCV_ASK_MODE SCV_RULES_ONCE SCV_JOURNAL_DIR PROMOTE_DIR ARCHIVE_DIR SCV_TURN_PLAN_CHECK 2>/dev/null || true
export SCV_TODAY=2026-11-20
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

cp -R "$FIX/guides" "$WORK/guides"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\nSCV_CHOICE_TOOL=PickTool\n' "$WORK/guides"; } > "$WORK/profile.env"
PROF="$WORK/profile.env"
QUOTE=$'> **다시 쓴 요청**: 로그인 버그를 로그인 시험이 통과할 때까지 고친다.'

mkproj() {  # <이름> [설정 JSON] → 프로젝트 경로
  local p="$WORK/$1"; mkdir -p "$p/scv/raw" "$p/scv/conversations"
  printf '%s\n' "${2:-{\"SCV_LANG\":\"korean\"\}}" > "$p/scv/scv_settings.json"; echo "$p"
}
hook() {  # <프로젝트> [프롬프트] → 매 턴 훅 출력
  ( cd "$1" && jq -cn --arg p "${2:-로그인 고쳐}" '{prompt:$p,session_id:"s1"}' \
      | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$PROF" SCV_GUARD_STATE="$WORK/gs" bash "$PROMPT_HOOK" 2>/dev/null )
}
mp() { local d="$1"; shift; ( cd "$d" && SCV_HOST_PROFILE="$PROF" bash "$MP" "$@" 2>/dev/null ); }
LEAN='{"SCV_LANG":"korean","SCV_LEAN_LOOP":"on"}'

# ---------- T1 — help 를 부르라는 지시 없이 진단 · 규약이 실리고 표시가 써진다 ----------
P="$(mkproj t1 "$LEAN")"; O="$(hook "$P")"
st="$(head -1 "$P/scv/journal/.help-state" 2>/dev/null)"
hg="$(mp "$P" help-gate --session s1)"
if ! grep -qF '이 턴의 첫 행동' <<<"$O" && grep -qF '[SCV 가벼운 루프]' <<<"$O" && grep -qF 'full protocol (read once per session)' <<<"$O" \
   && grep -qF '"protocol":1' <<<"$st" && [[ -z "$hg" ]]; then
  O2="$(hook "$P")"
  if ! grep -qF 'full protocol (read once per session)' <<<"$O2"; then ok "T1 help 지시 없음 · 첫 턴 규약 전문 + 읽음 표시 · 둘째 턴은 다시 싣지 않음 · help 먼저 검사 통과"
  else bad "T1 둘째 턴에도 규약 전문"; fi
else bad "T1 지시=$(grep -c '이 턴의 첫 행동' <<<"$O") 가벼운줄=$(grep -c '가벼운 루프' <<<"$O") 규약=$(grep -c 'read once per session' <<<"$O") 표시=[$st] help-gate=[$hg]"; fi

# ---------- T2 — 등록 명령 없이 쓰기가 열리고, 답 맨 위 인용이 등록된다 ----------
P="$(mkproj t2 "$LEAN")"; hook "$P" >/dev/null
gw="$(mp "$P" gate --session s1)"
s_ok="$(printf '%s\n\n결론임.\n' "$QUOTE" | mp "$P" stop --session s1 | head -1)"
reg="$(tail -n +2 "$P/scv/journal/.help-turns/s1/.help-rewrite" 2>/dev/null)"
hook "$P" >/dev/null
s_no="$(printf '결론임.\n' | mp "$P" stop --session s1 | head -1)"
if [[ -z "$gw" && "$s_ok" == "STOP_GATE: ok" && "$reg" == *"로그인 버그를 로그인 시험이 통과할 때까지 고친다."* && "$s_no" == "STOP_GATE: block" ]]; then
  ok "T2 쓰기 거절 없음 · 인용 있는 답 → 등록 · 통과 · 인용 없는 답 → 막힘"
else bad "T2 gate=[$gw] 있음=[$s_ok] 없음=[$s_no] 등록=[${reg:0:80}]"; fi

# T2b — help 를 부르지 않아도 첫 파일 쓰기가 안전장치(이 세션에서 SCV 액션이 돌았나)에 막히지 않는다. 끄면 그대로 막힌다.
guardw() {  # <프로젝트> → 쓰기 전 안전장치 출력(거절이면 글이 나온다)
  ( cd "$1" && jq -cn --arg c "$1" '{session_id:"s1",cwd:$c,tool_name:"Edit",tool_input:{file_path:($c+"/add.js")}}' \
      | SCV_GUARD_MODE=gate-write SCV_GUARD_SCRIPTS="$CORE/scripts" SCV_GUARD_STATE="$2" bash "$CORE/template/hooks/guard.sh" 2>/dev/null )
}
P="$(mkproj t2b "$LEAN")"; ( cd "$P" && jq -cn '{prompt:"고쳐",session_id:"s1"}' | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$PROF" SCV_GUARD_STATE="$WORK/gs2" bash "$PROMPT_HOOK" >/dev/null 2>&1 )
gl="$(guardw "$P" "$WORK/gs2")"
P="$(mkproj t2c)"; ( cd "$P" && jq -cn '{prompt:"고쳐",session_id:"s1"}' | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$PROF" SCV_GUARD_STATE="$WORK/gs3" bash "$PROMPT_HOOK" >/dev/null 2>&1 )
gd="$(guardw "$P" "$WORK/gs3")"
if [[ "$gl" != *deny* && "$gd" == *deny* ]]; then ok "T2b 가벼운 루프는 훅만 돈 뒤 첫 쓰기 허용 · 끄면 그대로 거절"
else bad "T2b 켬=[${gl:0:120}] 끔=[${gd:0:120}]"; fi

# ---------- T3 — 대화 기록 · 지문 되새김을 모델에 맡기지 않는다 ----------
P="$(mkproj t3 "$LEAN")"; hook "$P" "기록 확인 문장" >/dev/null
jr="$(grep -rlF '기록 확인 문장' "$P/scv/journal" 2>/dev/null | head -1)"
nonce="$(cat "$P/scv/journal/.help-nonce" 2>/dev/null)"
if [[ -n "$jr" && -n "$nonce" ]]; then ok "T3 사람 말은 훅이 일지에 · 규약 지문은 훅이 표시(모델 도구 호출 없음)"
else bad "T3 일지=[$jr] 지문=[$nonce]"; fi

# ---------- T4 — 계획 기록 검사는 가벼운 루프에서 막지 않고 기록만 ----------
R="$WORK/repo"; mkdir -p "$R/scv/promote/p1" "$R/src"
( cd "$R" && git init -q . && git config user.email t@t && git config user.name t \
  && printf -- '---\ntitle: 시험\nslug: p1\nstatus: in_progress\n---\n\n# 시험\n\n## Suggested path\n\n1. 하나\n\n## Links\n' > scv/promote/p1/PLAN.md \
  && printf 'a\n' > src/a.ts && git add -A && git commit -qm init )
tc_turn() {  # <설정 JSON> → turn-check end 판정
  ( cd "$R" && git reset -q --hard HEAD && git clean -qfdx && printf '%s\n' "$1" > scv/scv_settings.json \
    && printf '고쳐' | bash "$TC" start --session s1 && bash "$TC" touch --session s1 --kind write src/a.ts \
    && printf 'x\n' >> src/a.ts && bash "$TC" end --session s1 | sed -n 's/^TURN_PLAN: //p' )
}
v_def="$(tc_turn '{"SCV_LANG":"korean"}')"
v_lean="$(tc_turn "$LEAN")"
logl="$(grep -c '가벼운 루프 · 막지 않음' "$R/scv/journal/.turn-plan.log" 2>/dev/null)"
hist="$(grep -c '막지 않음(' "$R/scv/promote/p1/PLAN.md" 2>/dev/null)"
if [[ "$v_def" == block && "$v_lean" == pass-unrecorded && "${logl:-0}" -ge 1 && "${hist:-0}" -ge 1 ]]; then
  ok "T4 기본은 막힘 그대로 · 가벼운 루프는 통과 + 기록 · 계획 이력"
else bad "T4 기본=[$v_def] 가벼운=[$v_lean] 기록=$logl 이력=$hist"; fi

# ---------- T5 — 처음과 끝만 묻기: 자리 판정 · 설정 파일 · 환경 변수 ----------
# shellcheck source=/dev/null
source "$CORE/scripts/lib/choices.sh"
got=""; for pl in outline verify irreversible mid first-run archive; do got+="$pl=$(scv_ask_policy ends "$pl") "; done
want="outline=ask verify=ask irreversible=ask mid=recommend first-run=recommend archive=recommend "
all="$(scv_ask_policy all mid)"
P="$(mkproj t5 '{"SCV_LANG":"korean","SCV_ASK_MODE":"ends"}')"; Of="$(hook "$P")"
P="$(mkproj t5e)"; Oe="$( cd "$P" && jq -cn '{prompt:"고쳐",session_id:"s1"}' | SCV_ASK_MODE=ends CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$PROF" SCV_GUARD_STATE="$WORK/gs" bash "$PROMPT_HOOK" 2>/dev/null )"
if [[ "$got" == "$want" && "$all" == ask ]] && grep -qF '[SCV choices · ends]' <<<"$Of" && grep -qF '처음과 끝만 묻는 모드' <<<"$Of" \
   && grep -qF '[SCV choices · ends]' <<<"$Oe" && grep -qF '처음과 끝만 묻는 모드' <<<"$Oe"; then
  ok "T5 개요 · 끝 검증 · 되돌릴 수 없는 일은 묻기, 중간 · 첫 실행 · 보관은 추천대로 · 설정 파일과 환경 변수 모두 안내 줄이 바뀜"
else bad "T5 판정=[$got] all=[$all] 파일=$(grep -c 'choices · ends' <<<"$Of") 환경=$(grep -c 'choices · ends' <<<"$Oe")"; fi

# ---------- T6 — 기본값(설정 없음 · all · off)은 출력이 같다 ----------
P1="$(mkproj t6a)"; P2="$(mkproj t6b '{"SCV_LANG":"korean","SCV_ASK_MODE":"all","SCV_LEAN_LOOP":"off"}')"
A="$(hook "$P1" | sed "s#$P1#<P>#g")"; B="$(hook "$P2" | sed "s#$P2#<P>#g")"
if [[ "$A" == "$B" ]] && grep -qF '이 턴의 첫 행동' <<<"$A" && grep -qF '[SCV choices] Ask decisions with PickTool' <<<"$A" \
   && ! grep -qF '가벼운 루프' <<<"$A"; then ok "T6 설정 없음 = all · off (바이트 같음), 예전 지시 · 선택 줄 그대로"
else bad "T6 같음=$([[ "$A" == "$B" ]] && echo 예 || echo 아니오)"; diff <(printf '%s' "$A") <(printf '%s' "$B") | head -5 >&2; fi

# ---------- T7 — ask-mode 명령: 인자 없으면 뒤집기 · ends/all 지정 · 환경 변수가 이기면 알림 · 잘못된 인자는 쓰지 않음 ----------
AM="$CORE/scripts/ask-mode.sh"
P="$(mkproj t7)"
o1="$(cd "$P" && bash "$AM")"; o2="$(cd "$P" && bash "$AM")"; o3="$(cd "$P" && bash "$AM" ends)"
o4="$(cd "$P" && SCV_ASK_MODE=all bash "$AM" all)"
( cd "$P" && bash "$AM" maybe >/dev/null 2>&1 ); r5=$?
v="$(jq -r '.SCV_ASK_MODE' "$P/scv/scv_settings.json")"; lang="$(jq -r '.SCV_LANG' "$P/scv/scv_settings.json")"
if [[ "$o1" == *"ASK_MODE: all -> ends"* && "$o2" == *"ASK_MODE: ends -> all"* && "$o3" == *"ASK_MODE: all -> ends"* \
   && "$o4" == *"ENV_VALUE: all"* && "$r5" == 2 && "$v" == all && "$lang" == korean ]]; then
  ok "T7 ask-mode 뒤집기 · 지정 · 환경 변수 알림 · 잘못된 인자 거절(exit 2), 다른 설정은 그대로"
else bad "T7 [$o1] [$o2] [$o3] [$o4] r5=$r5 값=$v 언어=$lang"; fi

exit "$fail"
