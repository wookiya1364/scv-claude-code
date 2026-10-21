#!/usr/bin/env bash
# test-dreams.sh — 드림(프롬프트 코치) 검사 (v0.69.0+).
#
# 왜 있나: 드림은 지난 세션 기록과 보관 기록을 읽어 '계획 하나에 사람 질의 몇 번' · 개선점 · 조언을 HTML 과 한 줄 요약으로 낸다.
# 입력은 읽기만 하고, 훅은 배경으로 띄우고 바로 돌아오며, 끄면 훅 출력이 이 기능 전과 바이트 단위로 같아야 한다. 보고서 · 요약 ·
# 판정자 입력에는 경로 · 메일 · 비밀값 · 세션 id 가 없어야 한다. 규칙 전문은 protocols/dreams.md 한 곳.
#
# Covers TESTS.md T1~T11 of 20261021-wookiya1364-scv-dreams-prompt-coach (T11 의 규칙 일치 전체는 test-rule-constitution,
# T12 는 실제 기록 · 설치본 판정자라 여기 넣지 않는다).
# 픽스처는 중립 도구 이름(Runner · Writer)만 쓴다 — 코어에는 호스트 도구 이름을 적지 않는다. 날짜는 TZ=UTC 로 고정한다.
# Run: bash core/tests/test-dreams.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-dreams: payload not found from $HERE" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1"; printf '      expected: %s\n      got:      %s\n' "$(printf '%s' "$2" | tr '\t\n' '›¶')" "$(printf '%s' "$3" | tr '\t\n' '›¶')"; fi; }
export TZ=UTC

LIB="$CORE/scripts/lib/dreams.sh"; DR="$CORE/scripts/dreams.sh"; PROTO="$CORE/protocols/dreams.md"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"; START_HOOK="$CORE/template/hooks/on-session-start.sh"
EXAMPLE="$CORE/template/scv/scv_settings.example.json"; FIXP="$CORE/tests/fixtures/model-prompting/profile.env"
FIX="$CORE/tests/fixtures/dreams/sessions"
for f in "$LIB" "$DR" "$PROTO" "$PROMPT_HOOK" "$START_HOOK" "$EXAMPLE" "$FIXP"; do [[ -f "$f" ]] || { echo "✖ 없음: $f"; exit 1; }; done
# shellcheck source=../scripts/lib/show-real.sh
source "$CORE/scripts/lib/show-real.sh"
# shellcheck source=../scripts/lib/model-prompting.sh
source "$CORE/scripts/lib/model-prompting.sh"
# shellcheck source=../scripts/lib/dreams.sh
source "$LIB"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-dreams.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
TR="$WORK/transcripts"; mkdir -p "$TR"; cp "$FIX"/*.jsonl "$TR/"
printf '{"type":"user","message":{"role":"user","content":"NUL \000 줄"},"timestamp":"2026-09-02T04:00:00Z"}\n' >> "$TR/1111aaaa-0000-4000-8000-000000000001.jsonl"
{ cat "$FIXP"; printf 'SCV_AUTO_PROMPT_TAGS=machine-event\n'; } > "$WORK/profile.env"
TAGS="machine-event"
new_repo() {  # <이름> → 보관 계획 넷(하나는 기록보다 이른 것)이 든 scv 저장소
  local d="$WORK/$1" s
  rm -rf "$d"; mkdir -p "$d/scv/journal" "$d/scv/conversations"
  printf 'conversation\n' > "$d/scv/conversations/c.md"
  for s in "20250101-x-old:2025-01-10" "20260901-x-plan-a:2026-09-06" "20260910-x-plan-b:\"2026-09-25\"" "20260911-x-plan-c:2026-09-25 10:00"; do
    mkdir -p "$d/scv/archive/${s%%:*}"
    printf -- '---\narchived_at: %s\narchived_by: someone\n---\n# Archive record\n' "${s#*:}" > "$d/scv/archive/${s%%:*}/ARCHIVED_AT.md"
  done
  printf '%s' "$d"
}
judge_script() {  # <이름> <동작 ok|fail|broken> → 판정자 명령 경로(입력은 $WORK/judge-<이름>.log 에 쌓고, 부른 횟수는 .n 에)
  local p="$WORK/judge-$1.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cat >> "%s"; printf "\\n=====\\n" >> "%s"; echo x >> "%s"\n' "$WORK/judge-$1.log" "$WORK/judge-$1.log" "$WORK/judge-$1.n"
    case "$2" in
      ok)     printf '%s\n' "echo 'Here: {\"rule\": \"finish — State what counts as done\", \"advice\": \"완료 기준을 한 줄로 적어라\", \"example\": \"테스트가 통과하면 끝내 줘\"}'" ;;
      fail)   printf 'echo oops; exit 3\n' ;;
      broken) printf 'echo "I cannot answer that"\n' ;;
    esac
  } > "$p"
  printf '%s' "$p"
}
profile_with_judge() { { cat "$WORK/profile.env"; printf 'SCV_JUDGE_COMMAND=%s\n' "$1"; } > "$WORK/profile-$2.env"; printf '%s' "$WORK/profile-$2.env"; }
run_dream() {  # <저장소> <프로필> [인자...] → dreams.sh 출력(캐시는 $WORK/cache-<저장소 이름>)
  local r="$1" p="$2"; shift 2
  (cd "$r" && CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$p" XDG_CACHE_HOME="$WORK/cache-${r##*/}" bash "$DR" --dir "$TR" "$@" 2>&1)
}
html_of() { ls "$1"/scv/dreams/*.html 2>/dev/null | head -n 1; }
nhtml() { ls "$1"/scv/dreams/*.html 2>/dev/null | grep -c . || true; }

# ------------------------------------------------------------------ T2 순수 단계
echo "── [T2] 순수 단계 — 픽스처 입력에 정해진 값 ──"
E1="$(tr -d '\000' < "$TR/1111aaaa-0000-4000-8000-000000000001.jsonl" | scv_dreams_entries)"
E2="$(scv_dreams_entries < "$TR/2222bbbb-0000-4000-8000-000000000002.jsonl")"
E3="$(scv_dreams_entries < "$TR/3333cccc-0000-4000-8000-000000000003.jsonl")"
eq "기록 항목: 압축 요약 · 도구 결과 · 깨진 줄은 빠진다(U 6 · A 6 · G 3)" "6 6 3" \
  "$(printf '%s\n' "$E1" | grep -c '^U	') $(printf '%s\n' "$E1" | grep -c '^A$') $(printf '%s\n' "$E1" | grep -c '^G	')"
eq "기록 항목: 하위 에이전트 · 메타 줄 · register --keep 은 빠진다" "2 1" \
  "$(printf '%s\n' "$E2" | grep -c '^U	') $(printf '%s\n' "$E2" | grep -c '^G	')"
eq "기록 항목: 등록 줄의 상태(탭 모양)" "G	2026-09-05T01:00:10Z	msg	msg	na" "$(printf '%s\n' "$E2" | grep '^G	')"
T1R="$(scv_dreams_human_turns f1 "$E1" "$TAGS" "" "")"
eq "사람 턴: 자동 알림 · 도구 결과 · 압축 요약 · 모델이 안 한 턴(중단 · NUL 줄)은 빠진다" \
  "f1	1	2026-09-02T01:00:00Z	로그인 버튼 만들어 줘
f1	2	2026-09-02T02:00:00Z	아니 색이 틀렸어, 파랗게 고쳐 줘" "$T1R"
eq "사람 턴: 자동 입력 태그가 없으면 알림도 사람 턴(이전 동작)" "4" "$(scv_dreams_human_turns f1 "$E1" "" "" "" | grep -c .)"
T3R="$(scv_dreams_human_turns f3 "$E3" "$TAGS" "" "")"
eq "사람 턴: 일하는 도중 입력한 첨부도 사람 턴" "f3	4	2026-10-03T01:00:00Z	작업 중 추가 요청" "$(printf '%s\n' "$T3R" | tail -n 1)"
TURNS="$T1R
$(scv_dreams_human_turns f2 "$E2" "$TAGS" "" "")
$T3R"
REGS="$(scv_dreams_register_features f1 "$E1" "$TAGS" "" "")
$(scv_dreams_register_features f2 "$E2" "$TAGS" "" "")
$(scv_dreams_register_features f3 "$E3" "$TAGS" "" "")"
eq "등록: 턴마다 마지막 등록, 첫 사람 턴 앞의 등록은 버림, 빠진 항목은 -" \
  "f1	1	2026-09-02T01:00:05Z	msg	asked	ctx
f1	2	2026-09-02T02:00:10Z	msg	msg	msg
f2	1	2026-09-05T01:00:10Z	msg	msg	na
f3	1	2026-09-12T01:00:10Z	msg	-	asked" "$REGS"
ARCH_IN="20250101-x-old	2025-01-10
20260910-x-plan-b	\"2026-09-25\"
20260901-x-plan-a	2026-09-06
20260911-x-plan-c	2026-09-25 10:00
bad	not-a-date
20260230-x	2026-02-30"
ARCH="$(scv_dreams_archive_dates "$ARCH_IN")"
eq "보관: 날짜 순 · 따옴표 · 시각 무관 · 없는 날 · 날짜 없음은 뺀다" \
  "20250110	20250101-x-old
20260906	20260901-x-plan-a
20260925	20260910-x-plan-b
20260925	20260911-x-plan-c" "$ARCH"
eq "기간(한 달): 9월 6질의 · 3보관 · 2.0, 10월 2질의 · 0 · -, 기록 전 보관은 안 셈" \
  "20260901	20260930	6	3	2.0
20261001	20261031	2	0	-" "$(scv_dreams_periods "$TURNS" "$ARCH" 0 month)"
eq "기간(열흘): 빈 기간 포함 · 말일까지" \
  "20260901	20260910	4	1	4.0
20260911	20260920	1	0	-
20260921	20260930	1	2	0.5
20261001	20261010	2	0	-" "$(scv_dreams_periods "$TURNS" "$ARCH" 0 dekad)"
eq "기간 단위: 100턴 미만 month · 이상 dekad" "month dekad" "$(scv_dreams_unit 99) $(scv_dreams_unit 100)"
eq "지역 오프셋: +09:00 이면 9월 2일 18시 UTC 는 9월 3일" "20260903" "$(scv_show_real_local_date 2026-09-02T18:00:00Z 540)"
DIST="$(scv_dreams_distribution "$TURNS" "$ARCH" 0)"
eq "분포: 앞 보관 다음 날 ~ 보관 날, 같은 날 둘은 나눔, 근거는 구간의 첫 턴, 진행 중 2" \
  "20260901-x-plan-a	20260906	4	f1/1
20260910-x-plan-b	20260925	1	f3/1
20260911-x-plan-c	20260925	1	-
#open	2" "$DIST"
TIPS="$(scv_dreams_tips "$REGS" "$TURNS" "$DIST")"
eq "개선점: 완료 기준 1/4(근거 = msg 아닌 턴), 정정 2/8(근거 = 고친 원래 요청), 깊이 2/4 · 짧은 계획은 안 걸림" \
  "finish	1	4		f1/1 f2/1 f3/1
correction	2	8		f1/1 f3/1" "$TIPS"
eq "개선점(plan): 계획 셋 이상 · 최대가 중앙값 2배 이상 · 10번 이상" "plan	12	2	p2	f9/1" \
  "$(scv_dreams_tips "" "" "$(printf 'p1\t20260101\t2\tf1/1\np2\t20260102\t12\tf9/1\np3\t20260103\t1\t-\n#open\t0\n')")"
eq "개선점: 문턱 아래면 없음" "" "$(scv_dreams_tips "$(printf 'a\t1\tt\tmsg\tmsg\tmsg\n')" "$(printf 'a\t1\tt\tx\n')" "")"
EVID="$(scv_dreams_evidence "$TIPS" "$TURNS")"
eq "근거: 개선점마다 발췌(경로 · 메일 · 비밀값 · id 가림)" \
  "1	로그인 버튼 만들어 줘
1	내 경로 [경로] 메일 [메일] token: [REDACTED] 세션 [id] 확인해 줘
1	대시보드 차트 추가
2	로그인 버튼 만들어 줘
2	대시보드 차트 추가" "$EVID"
# 붙여 넣은 글은 근거로 고르지 않는다(2026-10-21 첫 실실행: 붙여 넣은 이전 답변이 '질의가 많았던 계획'의 근거로 뽑혀 조언이 엇나감)
_paste='스팸이에요. **영업 메일**로 보여요. **근거:** - **템플릿 메일이에요.** 이름이 두 번 들어가 있어요'
_r=""; for _s in "$_paste" '```log 오류```' '[Image #1] 이거 봐' '로그인 **꼭** 고쳐 줘' '결제 버튼 만들어 줘'; do
  if scv_dreams_pasted "$_s"; then _r="$_r 1"; else _r="$_r 0"; fi; done
eq "붙여 넣은 글 판별: 굵은 글씨 세 쌍 · 코드 울타리 · 이미지는 붙여 넣은 글, 굵은 글씨 한 쌍 · 보통 요청은 아님" " 1 1 1 0 0" "$_r"
_pt="$(printf 'f1\t1\t2026-09-02T09:00:00Z\t%s\nf1\t2\t2026-09-03T09:00:00Z\t결제 버튼 만들어 줘\n' "$_paste")"
eq "분포: 구간의 첫 턴이 붙여 넣은 글이면 다음 사람 요청을 근거로(질의 수는 그대로 2)" \
  "20260901-x-plan-a	20260906	2	f1/2
#open	0" "$(scv_dreams_distribution "$_pt" "$(printf '20260906\t20260901-x-plan-a\n')" 0)"
eq "분포: 구간이 모두 붙여 넣은 글이면 근거 없음(-)" \
  "20260901-x-plan-a	20260906	1	-
#open	0" "$(scv_dreams_distribution "$(printf '%s\n' "$_pt" | head -1)" "$(printf '20260906\t20260901-x-plan-a\n')" 0)"
eq "근거: 붙여 넣은 글로 보이는 턴은 발췌하지 않음" "1	결제 버튼 만들어 줘" \
  "$(scv_dreams_evidence "$(printf 'finish\t0\t3\t\tf1/1 f1/2\n')" "$_pt")"
_long="$(scv_dreams_mask "$(printf '가%.0s' $(seq 1 300))")"
eq "가림: 160자에서 자른다(글자 단위, 끝에 …)" "161" "$(jq -nr --arg s "$_long" '$s | length')"
eq "판정자 답: 객체 하나에서 규칙 · 조언 · 예시" "finish	적어라	예시" "$(scv_dreams_judge_parse 'x {"rule":"finish","advice":"적어라","example":"예시"} y')"
eq "판정자 답: 깨진 답은 빈 값" "" "$(scv_dreams_judge_parse 'no json [1] {"rule":""}')"
eq "발동: clear · compact 만" "1 1 0 0 0" "$(scv_dreams_start_trigger clear) $(scv_dreams_start_trigger compact) $(scv_dreams_start_trigger resume) $(scv_dreams_start_trigger startup) $(scv_dreams_start_trigger '')"
eq "발동: 날짜가 바뀔 때만" "1 0 1" "$(scv_dreams_day_trigger 20261020 20261021) $(scv_dreams_day_trigger 20261021 20261021) $(scv_dreams_day_trigger '' 20261021)"
eq "스위치: off 만 끈다" "off off on on" "$(scv_dreams_switch off) $(scv_dreams_switch ' "OFF" ') $(scv_dreams_switch '') $(scv_dreams_switch no)"
SUM="$(scv_dreams_render_summary "$(scv_dreams_periods "$TURNS" "$ARCH" 0 month)" "$TIPS" "scv/dreams/x.html" 8)"
eq "요약 한 줄" "[SCV 드림] 계획 하나에 사람 질의 2.0번(보관 3개 · 질의 6번) · 개선점: 요청에 완료 기준(무엇이 되면 끝인지)을 직접 말한 비율 1/4(25%) · 보고서 scv/dreams/x.html" "$SUM"
eq "요약: 보관이 없으면 '아직 셀 것이 없음'" "[SCV 드림] 아직 셀 것이 없음(보관된 계획 0개 · 사람 질의 0번) · 보고서 r" "$(scv_dreams_render_summary "" "" r 0)"
H="$(scv_dreams_render_html "$(scv_dreams_periods "$TURNS" "$ARCH" 0 month)" "$DIST" "$TIPS" "$EVID" "1	ok	finish	조언 <b>	예시" "stamp" month 8 3 4)"
H2="$(scv_dreams_render_html "$(scv_dreams_periods "$TURNS" "$ARCH" 0 month)" "$DIST" "$TIPS" "$EVID" "1	ok	finish	조언 <b>	예시" "stamp" month 8 3 4)"
[[ "$H" == "$H2" ]] && ok "HTML: 같은 입력이면 같은 출력" || fail "HTML 반복 가능성"
grep -q '<svg' <<<"$H" && grep -q '<table>' <<<"$H" && grep -q '조언 &lt;b&gt;' <<<"$H" && ! grep -q '«' <<<"$H" \
  && ok "HTML: SVG · 표 · 이스케이프 · 꺾쇠 자리표시 없음" || fail "HTML 모양"
grep -qE '<(script|link|img)[ >]|https?://[^"]*\.(js|css)' <<<"$H" && fail "HTML 이 외부 자원을 쓴다" || ok "HTML: 외부 자원 없음(한 파일)"
grep -q '조언 없음(판정자 결과 없음)' <<<"$H" && ok "HTML: 조언 줄이 없는 개선점은 '조언 없음(이유)'" || fail "HTML 조언 없음 칸"
if [[ -f "$CORE/scripts/check-purity.sh" ]]; then
  OUT="$(bash "$CORE/scripts/check-purity.sh" "$LIB" 2>&1)"
  grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과(lib/dreams.sh)" || fail "순수성 위반: $(printf '%s' "$OUT" | head -3)"
fi

# ------------------------------------------------------------------ T1 · T7 · T8 직접 실행
echo "── [T1] 직접 실행 — 보고서가 나온다 ──"
R="$(new_repo t1)"
JOK="$(judge_script ok ok)"; P_OK="$(profile_with_judge "$JOK" ok)"
_hash() { (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done); }
B_TR="$(_hash "$TR")"; B_AR="$(_hash "$R/scv/archive")"; B_CV="$(_hash "$R/scv/conversations")"
O="$(run_dream "$R" "$P_OK")"
HF="$(html_of "$R")"
[[ -n "$HF" && -f "$R/scv/dreams/latest.json" ]] && ok "보고서 · latest.json 생성" || fail "T1 파일 없음: $O"
eq "직접 실행은 요약 한 줄을 찍는다" "1" "$(printf '%s\n' "$O" | grep -c '^\[SCV 드림\] 계획 하나에 사람 질의 2.0번(보관 3개 · 질의 6번)')"
HT="$(cat "$HF" 2>/dev/null)"
grep -qF '<td>2026-09-01..2026-09-30</td><td class="n">6</td><td class="n">3</td><td class="n">2.0</td>' <<<"$HT" \
  && grep -qF '<td>2026-10-01..2026-10-31</td><td class="n">2</td><td class="n">0</td><td class="n">-</td>' <<<"$HT" \
  && ok "기간 표 숫자가 손으로 센 값(9월 6 · 3 · 2.0, 10월 2 · 0 · -)" || fail "T1 기간 표"
grep -qF '<td>20260901-x-plan-a</td><td class="n">4</td>' <<<"$HT" && grep -qF '<td>20260911-x-plan-c</td><td class="n">1</td>' <<<"$HT" \
  && grep -q '<svg' <<<"$HT" && ok "분포 차트(SVG) · 계획마다 질의(4 · 1 · 1)" || fail "T1 분포"
grep -qF '요청에 완료 기준(무엇이 되면 끝인지)을 직접 말한 비율 1/4(25%)' <<<"$HT" && grep -qF '근거: 로그인 버튼 만들어 줘' <<<"$HT" \
  && ok "개선점 1개 이상 + 근거 턴 발췌" || fail "T1 개선점"
eq "세션 · 질의 · 등록 수" "1" "$(grep -c '세션 3개 · 사람 질의 8번 · 등록 4건' <<<"$HT")"
grep -q 'ignored null byte' <<<"$O" && fail "NUL 경고가 나온다" || ok "기록 속 NUL 에도 경고 없음"
echo "── [T7] 입력을 바꾸지 않는다 ──"
[[ "$B_TR" == "$(_hash "$TR")" && "$B_AR" == "$(_hash "$R/scv/archive")" && "$B_CV" == "$(_hash "$R/scv/conversations")" ]] \
  && ok "세션 기록 · archive · 대화 기록 해시 그대로" || fail "T7 입력이 바뀌었다"
echo "── [T8] 개인 정보 없음 ──"
LEAK=0
for s in alice example.com abcSECRET123 3f2a1b4c 444455556666 /Users/ /opt/core 1111aaaa 2222bbbb 3333cccc "$TR" "$WORK"; do
  for f in "$HF" "$R/scv/dreams/latest.json" "$WORK/judge-ok.log"; do grep -qF -- "$s" "$f" 2>/dev/null && { LEAK=$((LEAK + 1)); echo "      leak: $s in ${f##*/}"; }; done
done
eq "보고서 · 요약 · 판정자 입력에 심은 값 0건" "0" "$LEAK"
[[ -s "$WORK/judge-ok.log" ]] && grep -qF '[경로]' "$WORK/judge-ok.log" && ok "판정자는 가린 발췌를 받았다" || fail "T8 판정자 입력이 비었다"

# ------------------------------------------------------------------ T9 판정자
echo "── [T9] 판정자 — 정상 · 실패 · 깨진 답 · 끔 · 판정자 없음, 캐시 ──"
grep -qF '조언(가이드 규칙: finish — State what counts as done): 완료 기준을 한 줄로 적어라' <<<"$HT" && grep -qF '다음에 이렇게 쓰면: <i>테스트가 통과하면 끝내 줘</i>' <<<"$HT" \
  && ok "정상: 조언 칸에 답 + 가이드 규칙 이름" || fail "T9 정상"
N1="$(grep -c . "$WORK/judge-ok.n" 2>/dev/null || echo 0)"
eq "정상: 개선점마다 한 번(2)" "2" "$N1"
O2="$(run_dream "$R" "$P_OK")"
eq "캐시 적중 시 판정자 호출 0(두 번째 실행 뒤에도 2)" "2" "$(grep -c . "$WORK/judge-ok.n" 2>/dev/null || echo 0)"
eq "캐시 적중 뒤에도 보고서 둘째" "2" "$(nhtml "$R")"
for c in fail:"판정자 실패" broken:"판정자 답이 깨짐"; do
  R="$(new_repo "t9-${c%%:*}")"; J="$(judge_script "${c%%:*}" "${c%%:*}")"
  run_dream "$R" "$(profile_with_judge "$J" "${c%%:*}")" >/dev/null
  HF="$(html_of "$R")"
  [[ -n "$HF" ]] && grep -qF "조언 없음(${c#*:})" "$HF" && ok "${c%%:*}: 보고서는 나오고 '조언 없음(${c#*:})'" || fail "T9 ${c%%:*}"
done
R="$(new_repo t9-off)"; printf '{"SCV_DREAMS_JUDGE":"off"}\n' > "$R/scv/scv_settings.json"; : > "$WORK/judge-ok.n"
run_dream "$R" "$P_OK" >/dev/null; HF="$(html_of "$R")"
[[ -n "$HF" ]] && grep -qF '조언 없음(꺼짐(SCV_DREAMS_JUDGE=off))' "$HF" && [[ ! -s "$WORK/judge-ok.n" ]] \
  && ok "끔: 보고서는 나오고 '조언 없음(꺼짐…)', 판정자 호출 0" || fail "T9 끔"
R="$(new_repo t9-none)"; run_dream "$R" "$WORK/profile.env" >/dev/null; HF="$(html_of "$R")"
[[ -n "$HF" ]] && grep -qF '조언 없음(판정자 없음)' "$HF" && ok "판정자 없음(코덱스): 보고서는 나오고 '조언 없음(판정자 없음)'" || fail "T9 판정자 없음"

# ------------------------------------------------------------------ 가장자리
echo "── 가장자리 — 기록 없음 · 보관 없음 ──"
R="$WORK/empty"; mkdir -p "$R/scv"; O="$(cd "$R" && CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile.env" XDG_CACHE_HOME="$WORK/c0" bash "$DR" 2>&1)"
grep -qF '아직 셀 것이 없음' <<<"$O" && [[ -n "$(html_of "$R")" ]] && ok "기록 · 보관이 없어도 보고서('아직 셀 것이 없음')" || fail "빈 저장소: $O"
O="$(cd "$WORK" && bash "$DR" 2>&1)"; _rc=$?
[[ "$_rc" == 1 ]] && grep -qF 'scv 폴더 없음' <<<"$O" && ok "scv 폴더가 없으면 한 줄 · 종료 1" || fail "scv 없음: $_rc $O"
O="$(cd "$WORK" && bash "$DR" --auto 2>&1)"; _rc=$?
[[ "$_rc" == 0 && -z "$O" ]] && ok "--auto 는 조용히 0" || fail "--auto scv 없음: $_rc $O"

# ------------------------------------------------------------------ T5 한 번에 하나
echo "── [T5] 한 번에 하나 — 잠금 · 오래된 잠금 ──"
R="$(new_repo t5)"; mkdir -p "$R/scv/dreams"
sleep 30 & SP=$!
ln -s "$SP" "$R/scv/dreams/.lock"
O="$(run_dream "$R" "$WORK/profile.env")"
grep -qF '이미 도는 중' <<<"$O" && [[ "$(nhtml "$R")" == 0 ]] && ok "살아 있는 잠금: 두 번째는 돌지 않는다" || fail "T5 잠금 무시: $O"
kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
O="$(run_dream "$R" "$WORK/profile.env")"
[[ "$(nhtml "$R")" == 1 && ! -L "$R/scv/dreams/.lock" ]] && ok "죽은 프로세스의 잠금은 치우고 돈다 · 끝나면 잠금이 풀린다" || fail "T5 오래된 잠금: $O"
R="$(new_repo t5b)"
SLOW="$WORK/judge-slow.sh"; printf '#!/usr/bin/env bash\ncat >/dev/null; sleep 2; echo "{\\"rule\\":\\"finish\\",\\"advice\\":\\"a\\"}"\n' > "$SLOW"
PS="$(profile_with_judge "$SLOW" slow)"
( run_dream "$R" "$PS" >/dev/null ) & BG=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -L "$R/scv/dreams/.lock" ]] && break; sleep 0.2; done
O="$(run_dream "$R" "$PS")"; wait "$BG" 2>/dev/null
grep -qF '이미 도는 중' <<<"$O" && [[ "$(nhtml "$R")" == 1 ]] && ok "도는 중 다시 발동: 동시 실행 0(보고서 1)" || fail "T5 동시: $O · $(nhtml "$R")"
[[ -f "$R/scv/dreams/.gitignore" ]] && grep -qx '.lock' "$R/scv/dreams/.gitignore" && ok "잠금 · 날짜 표식은 무시 목록에" || fail "T5 .gitignore"

# ------------------------------------------------------------------ 훅 (T3 · T4 · T6 · T10)
STUBC="$WORK/core-stub"; mkdir -p "$STUBC"; cp -R "$CORE/." "$STUBC/"
printf '#!/usr/bin/env bash\necho "$*" >> "$PWD/launch.log"\nsleep 2\n' > "$STUBC/scripts/dreams.sh"
_norm() { sed -E 's/[0-9]{2}:[0-9]{2}(:[0-9]{2})?/HH:MM/g'; }
_timed() {  # <저장소> <훅> <입력> <코어> → 걸린 초(소수)
  local s e
  s="$(perl -MTime::HiRes=time -e 'printf "%.3f", time' 2>/dev/null || python3 -c 'import time;print("%.3f"%time.time())')"
  (cd "$1" && printf '%s' "$3" | CLAUDE_PLUGIN_ROOT="$4" SCV_HOST_PROFILE="$WORK/profile.env" bash "$2" >/dev/null 2>&1)
  e="$(perl -MTime::HiRes=time -e 'printf "%.3f", time' 2>/dev/null || python3 -c 'import time;print("%.3f"%time.time())')"
  awk -v s="$s" -v e="$e" 'BEGIN { printf "%.3f", e - s }'
}
launches() { sleep 0.4; grep -c . "$1/launch.log" 2>/dev/null || echo 0; }
echo "── [T3] 자동 발동 — clear · compact ──"
for src in clear compact resume startup; do
  R="$(new_repo "t3-$src")"
  _t="$(_timed "$R" "$STUBC/template/hooks/on-session-start.sh" "{\"source\":\"$src\",\"session_id\":\"s1\"}" "$STUBC")"
  _base="$(sed -e '/^# ---------- dreams/,/^# ---------- \/dreams/d' "$STUBC/template/hooks/on-session-start.sh" > "$WORK/ss-base.sh"; _timed "$R" "$WORK/ss-base.sh" "{\"source\":\"$src\",\"session_id\":\"s1\"}" "$STUBC")"
  n="$(launches "$R")"
  want=0; [[ "$src" == clear || "$src" == compact ]] && want=1
  eq "$src: 뜬 횟수 $want" "$want" "$n"
  awk -v t="$_t" -v b="$_base" 'BEGIN { exit !(t - b <= 0.5 && t <= 1.5) }' && ok "$src: 훅 지연 ${_t}s(드림 구간 없는 훅 ${_base}s, 더한 지연 ≤ 0.5s)" || fail "$src: 훅 지연 ${_t}s (base ${_base}s)"
done
echo "── [T4] 자동 발동 — 날짜 바뀜 ──"
R="$(new_repo t4)"; mkdir -p "$R/scv/dreams"; printf '19990101\n' > "$R/scv/dreams/.last"
IN='{"prompt":"안녕","session_id":"s1"}'
_t1="$(_timed "$R" "$STUBC/template/hooks/on-user-prompt.sh" "$IN" "$STUBC")"
_timed "$R" "$STUBC/template/hooks/on-user-prompt.sh" "$IN" "$STUBC" >/dev/null
eq "어제 → 두 번 중 첫 번째에서만 뜸" "1" "$(launches "$R")"
eq "날짜를 오늘로 적었다" "$(date +%Y%m%d)" "$(cat "$R/scv/dreams/.last")"
R="$(new_repo t4b)"; mkdir -p "$R/scv/dreams"; date +%Y%m%d > "$R/scv/dreams/.last"
_timed "$R" "$STUBC/template/hooks/on-user-prompt.sh" "$IN" "$STUBC" >/dev/null
eq "오늘 → 안 뜸" "0" "$(launches "$R")"
R="$(new_repo t4c)"; mkdir -p "$R/scv/dreams"; printf '19990101\n' > "$R/scv/dreams/.last"
_timed "$R" "$STUBC/template/hooks/on-user-prompt.sh" '{"prompt":"<machine-event>x</machine-event>","session_id":"s1"}' "$STUBC" >/dev/null
eq "자동 알림 턴 → 안 뜸" "0" "$(launches "$R")"
echo "── [T6] 끄기 — 자동 발동 없음 · 직접 실행 한 줄 · 훅 출력 바이트 동일 ──"
sed -e '/^# ---------- dreams/,/^# ---------- \/dreams/d' "$STUBC/template/hooks/on-user-prompt.sh" > "$STUBC/template/hooks/base-prompt.sh"
sed -e '/^# ---------- dreams/,/^# ---------- \/dreams/d' "$STUBC/template/hooks/on-session-start.sh" > "$STUBC/template/hooks/base-start.sh"
grep -q '_scv_dr_' "$STUBC/template/hooks/base-prompt.sh" "$STUBC/template/hooks/base-start.sh" && fail "기능 전 훅을 만들지 못했다" || ok "기능 전 훅을 만들었다(표식 구간을 지움)"
off_repo() {  # <이름> → 끈 저장소(어제 날짜 · 안 알린 요약까지 둔다 — 꺼져 있으면 아무것도 안 해야 한다)
  local r; r="$(new_repo "$1")"; printf '{"SCV_DREAMS":"off"}\n' > "$r/scv/scv_settings.json"
  mkdir -p "$r/scv/dreams"; printf '19990101\n' > "$r/scv/dreams/.last"
  printf '{"date":"19990101","report":"r","summary":"[SCV 드림] x","announced":false}\n' > "$r/scv/dreams/latest.json"; printf '%s' "$r"
}
hook_out() { (cd "$1" && printf '%s' "$3" | CLAUDE_PLUGIN_ROOT="$STUBC" SCV_HOST_PROFILE="$WORK/profile.env" bash "$2" 2>/dev/null) | _norm; }
for v in off OFF '" Off "'; do
  _sv="$(jq -cn --arg v "$v" '{SCV_DREAMS: $v}')"
  # 같은 경로의 저장소에서 견준다 — 진단 줄에 저장소 경로가 찍힌다.
  RA="$(off_repo t6)"; printf '%s\n' "$_sv" > "$RA/scv/scv_settings.json"
  A="$(hook_out "$RA" "$STUBC/template/hooks/on-user-prompt.sh" "$IN")"
  AS="$(hook_out "$RA" "$STUBC/template/hooks/on-session-start.sh" '{"source":"clear","session_id":"s1"}')"
  eq "끔($v): 자동 발동 0 · 요약 줄 없음" "0 0" "$(launches "$RA") $(grep -c '드림' <<<"$A")"
  RB="$(off_repo t6)"; printf '%s\n' "$_sv" > "$RB/scv/scv_settings.json"
  B="$(hook_out "$RB" "$STUBC/template/hooks/base-prompt.sh" "$IN")"
  BS="$(hook_out "$RB" "$STUBC/template/hooks/base-start.sh" '{"source":"clear","session_id":"s1"}')"
  [[ -n "$A" && "$A" == "$B" ]] && ok "매 턴 훅($v): 기능 전과 바이트 동일" || { fail "매 턴 훅($v) 출력이 다르다"; diff <(printf '%s\n' "$B") <(printf '%s\n' "$A") | head -5; }
  [[ "$AS" == "$BS" ]] && ok "시작 훅($v): 기능 전과 바이트 동일" || { fail "시작 훅($v) 출력이 다르다"; diff <(printf '%s\n' "$BS") <(printf '%s\n' "$AS") | head -5; }
done
RA="$(off_repo t6c)"; O="$(cd "$RA" && CLAUDE_PLUGIN_ROOT="$CORE" bash "$DR" 2>&1)"
eq "끔: 직접 실행은 '꺼져 있음' 한 줄" "드림: 꺼져 있음 (SCV_DREAMS=off)" "$O"
eq "끔: 보고서를 만들지 않는다" "0" "$(nhtml "$RA")"
echo "── [T10] 다음 턴 요약 한 줄 ──"
R="$(new_repo t10)"; mkdir -p "$R/scv/dreams"; date +%Y%m%d > "$R/scv/dreams/.last"
hook_out "$R" "$STUBC/template/hooks/on-user-prompt.sh" "$IN" >/dev/null   # 첫 턴(진단 전체)을 지나 둔다 — 상한은 2턴째 기준(test-help-budget)
run_dream "$R" "$WORK/profile.env" --auto >/dev/null
eq "--auto: 요약을 찍지 않고 안 알림 표식" "false" "$(jq -r '.announced' "$R/scv/dreams/latest.json")"
eq "--auto: 날짜 표식" "$(date +%Y%m%d)" "$(cat "$R/scv/dreams/.last" 2>/dev/null)"
H1="$(hook_out "$R" "$STUBC/template/hooks/on-user-prompt.sh" "$IN")"; H2="$(hook_out "$R" "$STUBC/template/hooks/on-user-prompt.sh" "$IN")"
eq "첫 번째 턴에만 '드림:' 한 줄" "1 0" "$(grep -c '^\[SCV 드림\]' <<<"$H1") $(grep -c '^\[SCV 드림\]' <<<"$H2")"
L="$(grep '^\[SCV 드림\]' <<<"$H1")"
grep -qF '2.0번' <<<"$L" && grep -qF '개선점:' <<<"$L" && grep -qE 'scv/dreams/[0-9]{8}-[0-9]{6}\.html' <<<"$L" \
  && ok "요약: 비율 · 개선점 하나 · 보고서 위치" || fail "T10 요약 내용: $L"
_lb=$(printf '%s' "$L" | wc -c | tr -d ' ')
(( _lb <= 600 )) && ok "요약 줄 ${_lb}B ≤ 600B" || fail "요약 줄 ${_lb}B"
eq "알린 뒤 표식이 true" "true" "$(jq -r '.announced' "$R/scv/dreams/latest.json")"
_hb=$(printf '%s' "$H1" | wc -c | tr -d ' '); _bb=$(wc -c < "$CORE/protocols/help.md" | tr -d ' ')
_wb=$(cd "$R" && bash "$CORE/scripts/help.sh" --with-context 2>/dev/null | wc -c | tr -d ' ')
(( _hb + _bb + _wb <= ${SCV_HELP_TURN_MAX:-12000} )) && ok "요약이 실린 턴도 매 턴 상한 안($((_hb + _bb + _wb))B)" || fail "T10 매 턴 상한 초과 $((_hb + _bb + _wb))B"

# ------------------------------------------------------------------ T11
echo "── [T11] 직접 명령 · 설정 예시 · 규칙 한 곳 ──"
eq "설정 예시: SCV_DREAMS · SCV_DREAMS_JUDGE 기본 on, 설명 있음" "on on true true" \
  "$(jq -r '[.SCV_DREAMS, .SCV_DREAMS_JUDGE, (._doc.SCV_DREAMS | length > 0), (._doc.SCV_DREAMS_JUDGE | length > 0)] | map(tostring) | join(" ")' "$EXAMPLE")"
for a in '## 드림 규칙 (전문' '### 언제 도나' '### 개선점 규칙' '### 조언(판정자)' 'SCV_DREAMS=off' '조언 없음(이유)' 'scripts/dreams.sh'; do
  grep -qF -- "$a" "$PROTO" && ok "규칙 전문에 [$a]" || fail "protocols/dreams.md 에 [$a] 없음"
done
if [[ -f "$CORE/actions.json" ]]; then
  eq "명령 목록에 dreams(core · 규약 · 입구)" "core protocols/dreams.md scripts/dreams.sh" \
    "$(jq -r '.actions[] | select(.id == "dreams") | "\(.owner) \(.protocol) \(.entrypoint)"' "$CORE/actions.json")"
fi

echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
