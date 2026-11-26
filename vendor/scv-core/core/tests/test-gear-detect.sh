#!/usr/bin/env bash
# scv-test: serial
# test-gear-detect.sh — 반복 알아채기(계획 20261124-wookiya1364-gears-detect · TESTS.md T1 ~ T11 · T14,
# 계획 20261126-wookiya1364-gear-notice-unmask · T15 ~ T17: 기어가 맞아도 반복을 함께 알림 · 적어 두기 · 반복 꼬리의 세 갈래).
#
# 비슷한 요청이 2번째로 오면 알림 한 줄이 뜨는지, 맞는 기어가 있으면 그 기어를 알리는지, 겹치는 것이 없는 턴에는 한 글자도 더
# 실리지 않는지 본다. 요청 기록은 비밀 가림을 거쳐 기록 폴더에만 쌓여야 하고, 보는 범위에는 한도가 있어야 한다.
# 시간을 재는 시험(T10 · T11)이 있어 차례로 돈다 — 벽시계가 아니라 쓴 CPU 시간을 견준다(lib/cpu-time.sh).
# 픽스처는 중립 id 만 쓴다 — 코어 payload 에 제공자 · 모델 이름을 넣지 않는다(tests/test-host-neutral.sh).
#
# Run: bash core/tests/test-gear-detect.sh
set -uo pipefail
unset SCV_GEAR_DETECT SCV_GEAR_DETECT_SCORE SCV_GEAR_DETECT_MIN SCV_GEAR_DETECT_LINES SCV_GEARS_DIR SCV_JOURNAL_DIR SCV_GEAR_STATE_DIR 2>/dev/null || true

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HOOK="$CORE/template/hooks/on-user-prompt.sh"; G="$CORE/scripts/gear.sh"; FIX="$CORE/tests/fixtures/model-prompting"
# shellcheck source=lib/cpu-time.sh
source "$CORE/tests/lib/cpu-time.sh"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }

fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-gd.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\n' "$WORK/guides"; } > "$WORK/profile.env"
export SCV_HOST_PROFILE="$WORK/profile.env" SCV_GUARD_STATE="$WORK/gs"

KOREAN='{"SCV_LANG":"korean"}'
OFF='{"SCV_LANG":"korean","SCV_GEAR_DETECT":"off"}'
mkproj() {  # <이름> [설정 JSON] → 프로젝트 경로
  local p="$WORK/$1"; mkdir -p "$p/scv/journal"
  printf '%s\n' "${2:-$KOREAN}" > "$p/scv/scv_settings.json"; printf '%s' "$p"
}
turn() {  # <프로젝트> <요청 글> [세션] → 매 턴 훅 출력
  ( cd "$1" && jq -cn --arg p "$2" --arg s "${3:-s1}" '{prompt:$p,session_id:$s}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$HOOK" 2>/dev/null )
}
marks() { grep -c '^\[SCV 기어 알림\]' <<<"$1" || true; }
log_lines() { local f="$1/scv/journal/.gear-requests"; if [[ -f "$f" ]]; then grep -c . "$f" || true; else echo 0; fi; }
addgear() {  # <프로젝트> <이름> <낱말들> <하는 일>
  ( cd "$1" && export SCV_GEAR_STATE_DIR="$1/.gear-state"
    [[ -f scv/gears/teeth/upper.sh ]] || { bash "$G" new upper --kind tooth --mark pure --in text --out text --does "대문자로 바꾼다" --example '"ab" → "AB"' >/dev/null
      printf '#!/usr/bin/env bash\ntr a-z A-Z\n' > scv/gears/teeth/upper.sh; }
    bash "$G" new "$2" --kind gear --flow "upper" --words "$3" --does "$4" >/dev/null && bash "$G" index >/dev/null ) \
    || { echo "✖ 시험용 기어를 만들지 못함: $2" >&2; exit 1; }
}

# ---------- T1 — 같은 요청 1번째에는 알림이 없고, 2번째에는 한 줄 ----------
P="$(mkproj t1)"
a="$(turn "$P" "주간 보고서를 표로 정리해 줘")"; b="$(turn "$P" "주간 보고서를 표로 정리해 줘")"
if [[ "$(marks "$a")" == 0 && "$(marks "$b")" == 1 ]] && grep -qF '기어로 만들어 재사용' <<<"$b" && grep -qF '주간 보고서를 표로 정리해 줘' <<<"$b"; then
  ok "T1 첫 번째 알림 0 · 두 번째 알림 1(지난 요청과 묻는 말이 실림)"
else bad "T1 첫=$(marks "$a") 둘=$(marks "$b")"; fi

# ---------- T2 — 조사만 다른 비슷한 요청도 2번째로 본다 ----------
P="$(mkproj t2)"
turn "$P" "릴리스 노트 써줘 이번 판 것으로" >/dev/null; c="$(turn "$P" "릴리스 노트를 써 줘 이번 판 것으로")"
[[ "$(marks "$c")" == 1 ]] && ok "T2 조사만 다른 요청에 알림 1" || bad "T2 알림=$(marks "$c")"

# ---------- T17 — 반복만 있으면 꼬리에 세 갈래가 있다: 묻기 · 일이 아니면 적기 · 묻지 않은 이유 ----------
if grep -q '^\[SCV 기어 알림\] 비슷한 요청이 전에도 있었다' <<<"$b" && grep -qF '선택 도구로' <<<"$b" && grep -qF '일을 시키는 글이 아니면' <<<"$b" && grep -qF 'decline 으로 적어' <<<"$b" && grep -qF '묻지 않았으면 답 끝에 그 이유를 한 줄로' <<<"$b"; then
  ok "T17 반복 알림의 꼬리: 묻기 · 일이 아니면 적기 · 묻지 않은 이유"
else bad "T17 $(grep '^\[SCV 기어 알림\]' <<<"$b" | cut -c1-200)"; fi

# ---------- T3 — 겹치는 것이 없는 턴에는 한 글자도 더 실리지 않는다 ----------
P="$(mkproj t3)"; Q="$(mkproj t3off "$OFF")"
addgear "$P" make-list "목록 만들기 정리" "목록을 만든다"; addgear "$P" send-mail "메일 보내기 발송" "메일을 보낸다"
addgear "$Q" make-list "목록 만들기 정리" "목록을 만든다"; addgear "$Q" send-mail "메일 보내기 발송" "메일을 보낸다"
for q in "로그인 화면의 색을 바꿔 줘" "결제 한도 검사를 설명해 줘" "배포 서버 주소가 어디야 알려줘" "시험이 왜 느린지 찾아 줘" "새 직원 안내 문서를 써 줘"; do
  turn "$P" "$q" >/dev/null; turn "$Q" "$q" >/dev/null
done
turn "$P" "데이터베이스 색인을 다시 설계해 보자" > "$WORK/t3.on"; turn "$Q" "데이터베이스 색인을 다시 설계해 보자" > "$WORK/t3.off"
if cmp -s "$WORK/t3.on" "$WORK/t3.off" && [[ -s "$WORK/t3.on" ]]; then ok "T3 겹치지 않는 턴: 켠 훅과 끈 훅의 출력이 같음"
else bad "T3 출력이 다름 ($(wc -c < "$WORK/t3.on") B · $(wc -c < "$WORK/t3.off") B)"; fi

# ---------- T4 — 기어도 기록도 없는 프로젝트의 첫 턴은 끈 것과 같다 ----------
P="$(mkproj t4)"; Q="$(mkproj t4off "$OFF")"
# 첫 턴의 진단에는 프로젝트 경로가 실린다 — 두 프로젝트의 경로만 같은 말로 바꿔 견준다.
samepath() { sed -E 's#/[^ ()]*/t4(off)?([^A-Za-z0-9]|$)#PROJ\2#g'; }   # 임시 폴더는 실제 경로(/private/…)로도 찍힌다 — 앞부분째 바꾼다
turn "$P" "데이터베이스 색인을 다시 설계해 보자" | samepath > "$WORK/t4.on"; turn "$Q" "데이터베이스 색인을 다시 설계해 보자" | samepath > "$WORK/t4.off"
if cmp -s "$WORK/t4.on" "$WORK/t4.off" && [[ "$(log_lines "$Q")" == 0 && "$(log_lines "$P")" == 1 ]]; then ok "T4 첫 턴 출력이 끈 것과 같음 · 끈 프로젝트는 쌓지 않음"
else bad "T4 같음=$(cmp -s "$WORK/t4.on" "$WORK/t4.off" && echo y || echo n) 켬줄=$(log_lines "$P") 끔줄=$(log_lines "$Q")"; fi

# ---------- T5 — 겹치는 기어가 있으면 그 기어를 알린다(지난 요청보다 먼저) ----------
# 기어만 맞는 첫 요청: 전과 같은 글(만들기 권유 없음). 같은 요청의 두 번째: 한 줄에 기어 · 반복이 함께(계획 gear-notice-unmask T1 · T2).
P="$(mkproj t5)"; addgear "$P" make-list "목록 만들기 정리" "목록을 만든다"
d0="$(turn "$P" "할 일 목록 만들기 부탁해 정리해서")"; d="$(turn "$P" "할 일 목록 만들기 부탁해 정리해서")"
if [[ "$(marks "$d0")" == 1 ]] && grep -qF 'run make-list' <<<"$d0" && grep -qF '목록을 만든다' <<<"$d0" && grep -q '^\[SCV 기어 알림\].*다른 일이면 이 줄을 무시한다\.$' <<<"$d0" && ! grep -qF '기어로 만들어 재사용' <<<"$d0"; then
  ok "T5 맞는 기어를 한 줄로 알림(이름 · 하는 일 · 돌리는 명령), 반복이 없으면 만들기 권유 없음"
else bad "T5 알림=$(marks "$d0") $(grep '^\[SCV 기어 알림\]' <<<"$d0" | cut -c1-120)"; fi
if [[ "$(marks "$d")" == 1 ]] && grep -q '^\[SCV 기어 알림\].*run make-list.*그 기어가 하는 일과 다르면.*할 일 목록 만들기 부탁해 정리해서.*기어로 만들어 재사용' <<<"$d"; then
  ok "T15 기어가 맞아도 비슷한 요청이 전에 있었으면 한 줄에 함께 알림(기어 먼저 · 반복 뒤)"
else bad "T15 알림=$(marks "$d") $(grep '^\[SCV 기어 알림\]' <<<"$d" | cut -c1-160)"; fi
# 함께 실린 반복도 "만들지 않음"으로 적을 수 있고, 적은 뒤에는 기어만 알린다(T4)
dd="$( cd "$P" && bash "$G" decline 2>&1 )"; d2="$(turn "$P" "할 일 목록 만들기 부탁해 정리해서")"
if grep -qF '적음' <<<"$dd" && [[ "$(marks "$d2")" == 1 ]] && grep -qF 'run make-list' <<<"$d2" && ! grep -qF '기어로 만들어 재사용' <<<"$d2"; then
  ok "T16 기어와 함께 실린 반복을 적어 두면 다음부터는 기어만 알림"
else bad "T16 적음=[$dd] 알림=$(marks "$d2")"; fi

# ---------- T6 — 후보가 여럿이어도 알림은 한 줄, 가장 많이 겹치는 기어 ----------
P="$(mkproj t6)"
addgear "$P" list-two "목록 만들기" "둘 겹침"; addgear "$P" list-three "목록 만들기 정리" "셋 겹침"; addgear "$P" list-other "보고서 발송" "안 겹침"
e="$(turn "$P" "할 일 목록 만들기 부탁해 정리해서")"
if [[ "$(marks "$e")" == 1 ]] && grep -q '^\[SCV 기어 알림\].*list-three' <<<"$e"; then ok "T6 후보 셋 중 가장 많이 겹치는 기어 하나만"
else bad "T6 알림=$(marks "$e") $(grep '^\[SCV 기어 알림\]' <<<"$e" | cut -c1-90)"; fi

# ---------- T7 — 만들지 않음을 고른 요청은 다시 알리지 않는다 ----------
P="$(mkproj t7)"
turn "$P" "주간 보고서를 표로 정리해 줘" >/dev/null; turn "$P" "주간 보고서를 표로 정리해 줘" >/dev/null
( cd "$P" && bash "$G" decline >/dev/null 2>&1 )
f="$(turn "$P" "주간 보고서를 표로 정리해 줘")"
turn "$P" "회의록에서 할 일만 뽑아 줘" >/dev/null; g="$(turn "$P" "회의록에서 할 일만 뽑아 줘")"
if [[ "$(marks "$f")" == 0 && "$(marks "$g")" == 1 ]]; then ok "T7 거절한 요청은 알림 0 · 다른 요청의 두 번째는 알림 1"
else bad "T7 거절=$(marks "$f") 다른=$(marks "$g")"; fi

# ---------- T8 — 쌓지 않는 턴: 자동 알림 · 명령 · 짧은 맞장구 ----------
P="$(mkproj t8)"; n=0
for q in "<task-notification>끝남</task-notification> 뒤에서 돌던 일이 끝났다" "/status" "응 이어가"; do
  turn "$P" "$q" >/dev/null; h="$(turn "$P" "$q")"; n=$(( n + $(marks "$h") ))
done
if [[ "$(log_lines "$P")" == 0 && "$n" == 0 ]]; then ok "T8 자동 알림 · 명령 · 짧은 맞장구: 기록 0줄 · 알림 0"
else bad "T8 기록=$(log_lines "$P") 알림=$n"; fi

# ---------- T9 — 요청 기록은 가린 글만, 기록 폴더에만 ----------
SECRET="ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD"
P="$(mkproj t9)"
turn "$P" "배포 스크립트를 고쳐 줘. token: $SECRET 이 값을 써" >/dev/null
where="$( cd "$P" && find . -name '.gear-*' | LC_ALL=C sort | tr '\n' ' ' )"
leak="$(grep -rlF "$SECRET" "$P" 2>/dev/null | grep -c . || true)"
norm_leak="$(grep -cF 'abcdefghijklmnopqrstuvwxyz0123456789' "$P/scv/journal/.gear-requests" 2>/dev/null || true)"
if [[ "$(log_lines "$P")" == 1 && "$where" == "./scv/journal/.gear-requests " && "$leak" == 0 && "${norm_leak:-0}" == 0 && "$(ls -A "$P" | tr '\n' ' ')" == "scv " ]]; then
  ok "T9 요청 기록은 기록 폴더에 하나 · 프로젝트 어디에도 비밀 원문 0건(맞춰 보기용 글에도 없음) · scv 폴더 밖에는 아무것도 쓰지 않음"
else bad "T9 기록=$(log_lines "$P") 자리=[$where] 원문=$leak 조각=$norm_leak"; fi

# ---------- T10 — 보는 범위에 한도가 있다 ----------
P="$(mkproj t10)"; L="$P/scv/journal/.gear-requests"
printf '2026-01-01\t주간보고서를표로정리해줘\t주간 보고서를 표로 정리해 줘\n' > "$L"
i=0; while (( i < 2000 )); do printf '2026-01-02\t서로다른요청번호%05d번의일을해줘\t서로 다른 요청 %d\n' "$i" "$i"; i=$((i + 1)); done >> "$L"
Q="$(mkproj t10small)"; tail -n 200 "$L" > "$Q/scv/journal/.gear-requests"
k="$(turn "$P" "주간 보고서를 표로 정리해 줘")"
detect_cpu() {  # <프로젝트> → 맞춰 보기 다섯 번에 쓴 CPU 초
  local a b j=0
  cpu_mark a
  while (( j < 5 )); do ( cd "$1" && printf '%s' "분기 결산 자료를 한 장으로 줄여 줘" | bash "$G" detect >/dev/null 2>&1 ); j=$((j + 1)); done
  cpu_mark b
  awk -v a="$a" -v b="$b" 'BEGIN { printf "%.3f", b - a }'
}
ratio_ok() { awk -v x="$1" -v y="$2" 'BEGIN { exit !(y <= 0 || x <= y * 1.5 + 0.05) }'; }
big="$(detect_cpu "$P")"; small="$(detect_cpu "$Q")"
ratio_ok "$big" "$small" || { big="$(detect_cpu "$P")"; small="$(detect_cpu "$Q")"; }
if [[ "$(marks "$k")" == 0 ]] && ratio_ok "$big" "$small"; then ok "T10 한도 밖(오래된) 줄은 알리지 않음 · 큰 기록 ${big}s ≤ 작은 기록 ${small}s × 1.5"
else bad "T10 알림=$(marks "$k") 큰=${big}s 작은=${small}s"; fi

# ---------- T11 — 매 턴 시간: 켠 훅이 끈 훅의 1.5배 이내 ----------
P="$(mkproj t11)"; Q="$(mkproj t11off "$OFF")"
i=0; while (( i < 20 )); do addgear "$P" "gear-$i" "낱말$i 다른$i" "일 $i"; i=$((i + 1)); done
cp -R "$P/scv/gears" "$Q/scv/gears"
for r in "$P" "$Q"; do tail -n 200 "$L" > "$r/scv/journal/.gear-requests"; done
hook_cpu() {  # <프로젝트> → 훅 다섯 번에 쓴 CPU 초
  local a b j=0
  cpu_mark a
  while (( j < 5 )); do turn "$1" "분기 결산 자료를 한 장으로 줄여 줘" >/dev/null; j=$((j + 1)); done
  cpu_mark b
  awk -v a="$a" -v b="$b" 'BEGIN { printf "%.3f", b - a }'
}
hook_cpu "$Q" >/dev/null   # 첫 턴의 한 번뿐인 일을 빼려고 한 번 돌려 둔다
hook_cpu "$P" >/dev/null
on="$(hook_cpu "$P")"; off="$(hook_cpu "$Q")"
ratio_ok "$on" "$off" || { off="$(hook_cpu "$Q")"; on="$(hook_cpu "$P")"; }
if ratio_ok "$on" "$off"; then ok "T11 켠 훅 ${on}s ≤ 끈 훅 ${off}s × 1.5 (기어 스무 개 · 기록 200줄, 다섯 번)"
else bad "T11 켠=${on}s 끈=${off}s"; fi

# ---------- T14 — 점수는 어디서나 같은 값(바이트 단위) ----------
# shellcheck source=/dev/null
source "$CORE/scripts/lib/gear.sh"
s1="$(scv_gear_overlap_score "$(scv_gear_text_norm "릴리스 노트 써줘")" "$(scv_gear_text_norm "릴리스 노트를 써 줘")")"
s2="$(LC_ALL=C scv_gear_overlap_score "$(LC_ALL=C scv_gear_text_norm "릴리스 노트 써줘")" "$(LC_ALL=C scv_gear_text_norm "릴리스 노트를 써 줘")")"
s3="$(scv_gear_overlap_score "$(scv_gear_text_norm "Release Notes, v2!")" "$(scv_gear_text_norm "release notes v2")")"
if [[ "$s1" == 78 && "$s2" == 78 && "$s3" == 100 ]]; then ok "T14 점수가 글자 설정과 상관없이 같음(78 · 78 · 100)"
else bad "T14 [$s1] [$s2] [$s3]"; fi

exit "$fail"
