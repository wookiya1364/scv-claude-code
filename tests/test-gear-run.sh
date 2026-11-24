#!/usr/bin/env bash
# test-gear-run.sh — 기어(스킬 — 맨 위 flow 줄로 톱니를 잇는다)와 톱니(아주 작은 sh)의 실행기(gear.sh)를 본다
# (계획 20261124-wookiya1364-gears-run · TESTS.md T1 ~ T25 · 계획 20261124-wookiya1364-gears-io-args T26 ~ T43. 순수 함수 사전 검사와 사용자 확인은 따로 한다).
#
# 시험용 프로젝트를 임시 폴더에 만든다: 톱니 다섯 · 기어 다섯. 실행 도중의 상태는 프로젝트 밖(SCV_GEAR_STATE_DIR)에 둔다.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
G="$CORE/scripts/gear.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export SCV_GEAR_STATE_DIR="$WORK/state"
unset SCV_GEARS_DIR SCV_GEAR_TOOTH_MAX_LINES SCV_JOURNAL_DIR 2>/dev/null || true
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

# @effect mkproj
# 이유: 임시 폴더에 빈 시험용 프로젝트(.host-skills 파일 하나 포함)를 만들고 그리로 옮긴다
mkproj() {
  P="$WORK/$1"; mkdir -p "$P/scv" "$P/.host-skills/skills"; printf 'keep\n' > "$P/.host-skills/skills/mine.md"
  cd "$P" || exit 1
}
# @effect tooth
# 이유: 톱니 하나를 만들고 본문 파일을 주어진 글로 바꿔 쓴다 — 인자: 이름 · 표시 · 받는 값 · 돌려주는 값 · 본문 · (예시)
tooth() {
  if [[ -n "${6:-}" ]]; then bash "$G" new "$1" --kind tooth --mark "$2" --in "$3" --out "$4" --does "$1 톱니" --example "$6" >/dev/null
  else bash "$G" new "$1" --kind tooth --mark "$2" --in "$3" --out "$4" --does "$1 톱니" >/dev/null; fi
  printf '#!/usr/bin/env bash\n%s\n' "$5" > "scv/gears/teeth/$1.sh"
}
# @effect token_of
# 이유: 실행기가 멈추며 낸 글에서 이어가기 표를 꺼낸다(글을 읽기만 한다)
token_of() { sed -n -e 's/^GEAR_HANDOFF: //p' -e 's/^GEAR_CONFIRM: //p' <<< "$1" | head -n 1; }
# @effect tag_of
# 이유: 실행기가 확인 앞에서 낸 글에서 질문에 넣을 확인 표([기어 확인 표:단계])를 꺼낸다(글을 읽기만 한다)
tag_of() { grep -o '\[기어 확인 [0-9a-f]*:[0-9]*\]' <<< "$1" | head -n 1; }
# @effect lim
# 이유: 명령을 시간 한도(초) 안에서 돌린다 — 끝없이 도는 결함을 시험이 붙잡고 있지 않게
lim() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }

mkproj main
tooth upper pure text text "tr 'a-z' 'A-Z'" '"ab" → "AB"'
tooth count pure text number "wc -c | tr -d ' '" '"abc" → "3"'
tooth tail-step effect summary text ': > tail.marker; sed "s/^/끝: /"'
tooth send outward text text ': > sent.marker; cat'
tooth first-mark effect text text ': > first.marker; cat'
bash "$G" new g-sh --kind gear --flow "upper | count" --does "대문자로 바꾸고 센다" >/dev/null
bash "$G" new g-mixed --kind gear --flow "upper | @ | tail-step" --does "대문자 → 요약 → 표시" --words "요약 표시" >/dev/null
printf 'flow: upper | @ | tail-step\ndoes: 대문자 → 요약 → 표시\nwords: 요약 표시\n\nSKILL-SUMMARIZE-TEXT\n앞 톱니의 결과를 한 줄로 요약해 돌려준다.\n' > scv/gears/g-mixed/GEAR.md
bash "$G" new other --kind gear --flow "@" --does "쓰이지 않는 글" >/dev/null
printf 'flow: @\ndoes: 쓰이지 않는 글\n\nSKILL-OTHER-TEXT\n' > scv/gears/other/GEAR.md
bash "$G" new g-out --kind gear --flow "upper | send" --does "대문자로 바꿔 밖으로 보낸다" >/dev/null
bash "$G" new nested --kind gear --flow "g-mixed | upper" --does "다른 기어의 흐름을 품는다" >/dev/null
bash "$G" index >/dev/null

# T1 — 같은 입력이면 톱니 단계 결과가 매번 같다 (값도 정해진 그대로: "hello" + 줄바꿈 = 6바이트)
printf 'hello\n' | bash "$G" run g-sh > "$WORK/o1" 2>/dev/null; r1=$?
printf 'hello\n' | bash "$G" run g-sh > "$WORK/o2" 2>/dev/null; r2=$?
if [[ $r1 == 0 && $r2 == 0 ]] && cmp -s "$WORK/o1" "$WORK/o2" && [[ "$(cat "$WORK/o1")" == 6 ]]; then ok "T1 기어 두 번 → 같은 결과(6)"
else bad "T1 r1=$r1 r2=$r2 o1=$(cat "$WORK/o1" 2>/dev/null)"; fi

# T2 — 판단 단계(@)에서만 멈추고, 그 기어의 글 · 앞 결과 · 이어가기 표만 넘긴다(맨 위 flow 줄도 다른 기어의 글도 없다)
out="$(printf 'hello\n' | bash "$G" run g-mixed 2>/dev/null)"; rc=$?
tok="$(token_of "$out")"
if [[ $rc == 10 && -n "$tok" ]] && grep -q 'SKILL-SUMMARIZE-TEXT' <<< "$out" && grep -q '^HELLO$' <<< "$out" \
   && ! grep -q 'SKILL-OTHER-TEXT' <<< "$out" && ! grep -q '^flow:' <<< "$out" && [[ ! -e tail.marker ]]; then ok "T2 판단 단계에서 멈춤(10) — 그 기어의 글 · 앞 결과 · 표만"
else bad "T2 rc=$rc tok=$tok"; fi

# T3 — 결과를 돌려주면 남은 톱니가 이어지고, 같은 표는 다시 못 쓴다
out3="$(printf '요약 결과\n' | bash "$G" resume "$tok" 2>/dev/null)"; rc=$?
printf 'x\n' | bash "$G" resume "$tok" >/dev/null 2>&1; rc2=$?
[[ $rc == 0 && "$out3" == "끝: 요약 결과" && -e tail.marker && $rc2 != 0 ]] && ok "T3 이어가기 → 마지막 톱니 실행, 같은 표 재사용 거절" || bad "T3 rc=$rc out=$out3 rc2=$rc2"

# T4 — 밖으로 나가는 톱니는 확인 없이 돌지 않는다
out="$(printf 'hello\n' | bash "$G" run g-out 2>/dev/null)"; rc=$?
tok="$(token_of "$out")"; tag="$(tag_of "$out")"
bash "$G" resume "$tok" >/dev/null 2>&1 </dev/null; rcA=$?
m1=no; [[ -e sent.marker ]] && m1=yes
bash "$G" confirm --question "이 단계를 실행할까요? $tag" --answer "실행하지 않음" >/dev/null 2>&1
bash "$G" resume "$tok" >/dev/null 2>&1 </dev/null; rcB=$?
m2=no; [[ -e sent.marker ]] && m2=yes
bash "$G" confirm --question "이 단계를 실행할까요? $tag" --answer "실행" >/dev/null 2>&1
out4="$(bash "$G" resume "$tok" 2>/dev/null </dev/null)"; rcC=$?
if [[ $rc == 11 && -n "$tok" && "$tag" == "[기어 확인 $tok:2]" && $rcA == 11 && $m1 == no && $rcB == 11 && $m2 == no && $rcC == 0 && "$out4" == HELLO && -e sent.marker ]]; then ok "T4 밖으로 톱니: 확인 전 멈춤(11) · 거절 답으로는 안 돎 · 실행 답 뒤에만 돎"
else bad "T4 rc=$rc rcA=$rcA m1=$m1 rcB=$rcB m2=$m2 rcC=$rcC out4=$out4"; fi

# T5 — 검사가 표시 없는 위험 명령을 잡고, 잡힌 톱니는 예시로도 돌리지 않는다(밖으로 표시가 있으면 지목하지 않는다)
mkproj risky
tooth bad-push pure text text $': > ran.marker\ncat\ngit push origin main' '"a" → "a"'
tooth bad-rm effect text text $'cat\n\nrm -rf build'
tooth bad-curl pure text text 'curl -s https://example.com' '"a" → "a"'
tooth good-out outward text text $'git push origin main\ncurl -s https://example.com'
bash "$G" index >/dev/null
out="$(bash "$G" check 2>&1)"; rc=$?
n="$(grep -c '^GEAR_RISK: ' <<< "$out")"
if [[ $rc != 0 && $n == 3 && ! -e ran.marker ]] && grep -q '^GEAR_RISK: bad-push:4 ' <<< "$out" && grep -q '^GEAR_RISK: bad-rm:4 ' <<< "$out" \
   && grep -q '^GEAR_RISK: bad-curl:2 ' <<< "$out" && ! grep -q 'good-out' <<< "$out"; then ok "T5 표시 없는 위험 명령 3건 지목(이름 · 줄 번호), 그 톱니는 돌리지 않음, 밖으로 표시는 통과"
else bad "T5 rc=$rc n=$n ran=$([[ -e ran.marker ]] && echo yes || echo no)"; printf '%s\n' "$out" | head -5 >&2; fi

# T6 — 잘못된 흐름은 한 단계도 돌기 전에 막힌다: 없는 이름 · 값 이름 불일치
cd "$WORK/main" || exit 1
rm -f first.marker
bash "$G" new g-missing --kind gear --flow "first-mark | no-such-tooth" --does x >/dev/null
bash "$G" new g-shape --kind gear --flow "first-mark | count | tail-step" --does x >/dev/null
e1="$(printf 'a\n' | bash "$G" run g-missing 2>&1 >/dev/null)"; r1=$?
e2="$(printf 'a\n' | bash "$G" run g-shape 2>&1 >/dev/null)"; r2=$?
if [[ $r1 == 1 && $r2 == 1 && ! -e first.marker ]] && grep -q '2단계' <<< "$e1" && grep -q 'no-such-tooth' <<< "$e1" && grep -q '3단계' <<< "$e2"; then ok "T6 없는 이름 · 값 이름 불일치 → 실행 전 거절(단계 번호), 첫 톱니도 안 돎"
else bad "T6 r1=$r1 r2=$r2 e1=$e1 e2=$e2"; fi
rm -rf scv/gears/g-missing scv/gears/g-shape; bash "$G" index >/dev/null

# T7 — 사전은 스크립트가 만들고, 손으로 고치면 검사가 잡는다
mkproj fresh
bash "$G" new one --kind tooth --does "하나" --in text --out text >/dev/null
n="$(grep -c . scv/gears/INDEX.tsv)"; bash "$G" check >/dev/null 2>&1; c1=$?
printf 'one\ttooth\tpure\ttext\ttext\t손으로 고친 줄\t\n' > scv/gears/INDEX.tsv
out="$(bash "$G" check 2>&1)"; c2=$?
[[ $n == 1 && $c1 == 0 && $c2 != 0 ]] && grep -q 'GEAR_INDEX_STALE.*one' <<< "$out" && ok "T7 만들면 사전 1줄 · 검사 통과, 손으로 고치면 검사 실패(이름 지목)" || bad "T7 n=$n c1=$c1 c2=$c2"

# T8 — 호스트 스킬 폴더는 그대로, 새 파일은 scv/gears 아래에만 (실행 상태는 프로젝트 밖으로 돌린 상태)
mkproj clean
before="$(find .host-skills -type f -exec cksum {} + | LC_ALL=C sort)"
: > "$WORK/stamp"; sleep 1
bash "$G" new a --kind tooth --does "그대로 넘긴다" --in text --out text >/dev/null
bash "$G" new c --kind gear --flow "a | @ | a" --does "글을 사이에 둔다" >/dev/null
bash "$G" list >/dev/null; bash "$G" check >/dev/null 2>&1
out="$(printf 'x\n' | bash "$G" run c 2>/dev/null)"; printf 'y\n' | bash "$G" resume "$(token_of "$out")" >/dev/null 2>&1
after="$(find .host-skills -type f -exec cksum {} + | LC_ALL=C sort)"
stray="$(find . -type f -newer "$WORK/stamp" ! -path './scv/gears/*' | head -3)"
[[ "$before" == "$after" && -z "$stray" && -d "$WORK/state" ]] && ok "T8 .host-skills 그대로, 새 파일은 scv/gears 아래에만" || bad "T8 stray=$stray"

# T9 — 기어 없는 프로젝트: 목록은 한 줄 · 종료 코드 0, 매 턴 훅은 기어를 부르지 않는다
mkproj empty
out="$(bash "$G" list 2>&1)"; rc=$?
[[ $rc == 0 && "$out" == "기어 없음" && ! -d scv/gears ]] && ! grep -rq 'gear\.sh' "$CORE/template/hooks/" && ok "T9 기어 없음 한 줄(0), 폴더를 만들지 않음, 훅은 그대로" || bad "T9 rc=$rc out=$out"

# T10 — 명령 글이 있고 명령 개수가 23 이다
n="$(jq '.actions | length' "$CORE/actions.json" 2>/dev/null)"
if [[ "$n" == 23 ]] && jq -e '.actions[] | select(.id == "gear" and .protocol == "protocols/gear.md" and .entrypoint == "scripts/gear.sh")' "$CORE/actions.json" >/dev/null 2>&1 \
   && grep -q 'gear.sh" list' "$CORE/protocols/gear.md" && grep -q ' new ' "$CORE/protocols/gear.md" && grep -q ' check' "$CORE/protocols/gear.md" && grep -q ' run ' "$CORE/protocols/gear.md"; then ok "T10 명령 23개, gear 명령 글이 목록 · 만들기 · 검사 · 실행을 안내"
else bad "T10 actions=$n"; fi

# T11 — 사전 글은 정해진 그대로다(맥 · 리눅스가 같은 바이트를 낸다)
cd "$WORK/fresh" || exit 1
bash "$G" index >/dev/null
want="$(printf 'one\ttooth\tpure\ttext\ttext\t하나\t')"
[[ "$(cat scv/gears/INDEX.tsv)" == "$want" ]] && ok "T11 사전 한 줄이 정해진 글과 같음" || bad "T11 [$(cat scv/gears/INDEX.tsv)]"

# T12 — 순수 톱니는 예시로 검사한다: 맞으면 통과, 틀리면 실패, 예시가 없으면 실패
mkproj examples
tooth up pure text text "tr 'a-z' 'A-Z'" "\$'a\\tb\\n가' → \$'A\\tB\\n가'"
bash "$G" check >/dev/null 2>&1; c1=$?
tooth wrong pure text text "tr 'a-z' 'A-Z'" '"ab" → "ab"'
o2="$(bash "$G" check 2>&1)"; c2=$?
rm -f scv/gears/teeth/wrong.sh; grep -v 'wrong' scv/gears/teeth/TEETH.md | grep -v '"ab" → "ab"' > "$WORK/t.md"
printf '\n### noex\n- 역할: 예시 없음\n- 표시: pure\n- 값: text → text\n' >> "$WORK/t.md"; cp "$WORK/t.md" scv/gears/teeth/TEETH.md
printf '#!/usr/bin/env bash\ncat\n' > scv/gears/teeth/noex.sh; bash "$G" index >/dev/null
o3="$(bash "$G" check 2>&1)"; c3=$?
if [[ $c1 == 0 && $c2 != 0 && $c3 != 0 ]] && grep -q '^GEAR_EXAMPLE: wrong — 예시 1: 기대 \[ab\] 실제 \[AB\]' <<< "$o2" && grep -q '^GEAR_BAD: noex — 예시가 없다' <<< "$o3"; then ok "T12 예시가 맞으면 통과 · 틀리면 실패(기대 · 실제) · 없으면 실패"
else bad "T12 c1=$c1 c2=$c2 c3=$c3"; printf '%s\n' "$o2" "$o3" | head -4 >&2; fi

# T13 — 한 가지 일만: 본문이 한도를 넘는 톱니와 흐름 가운데의 순수하지 않은 톱니는 알림(검사는 통과)
mkproj small
tooth big pure text text "$(printf 'cat |\n'; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'cat |\n'; done; printf 'cat')" '"a" → "a"'
tooth p pure text text 'cat' '"a" → "a"'
tooth mid effect text text 'cat'
bash "$G" new g --kind gear --flow "p | mid | p" --does x >/dev/null
out="$(bash "$G" check 2>&1)"; rc=$?
if [[ $rc == 0 ]] && grep -q '^GEAR_WARN: big — 본문 14줄(한도 12줄)' <<< "$out" && grep -q '^GEAR_WARN: g: 2단계 mid — 표시가 effect 인데 흐름의 가운데' <<< "$out" && grep -q '알림 2건' <<< "$out"; then ok "T13 큰 톱니 · 가운데의 effect 톱니 → 알림 2건, 검사는 통과"
else bad "T13 rc=$rc"; printf '%s\n' "$out" | head -4 >&2; fi

# T14 — 기어의 flow 에 다른 기어를 적으면 그 흐름이 펼쳐진다. 자기 자신으로 돌아오는 흐름은 실행 전에 막힌다
cd "$WORK/main" || exit 1
rm -f tail.marker
out="$(printf 'hello\n' | bash "$G" run nested 2>/dev/null)"; rc=$?
out2="$(printf 'ok\n' | bash "$G" resume "$(token_of "$out")" 2>/dev/null)"; rc2=$?
bash "$G" new loop-a --kind gear --flow "loop-b | upper" --does x >/dev/null; bash "$G" new loop-b --kind gear --flow "upper | loop-a" --does x >/dev/null
e="$(printf 'a\n' | bash "$G" run loop-a 2>&1 >/dev/null)"; rc3=$?
if [[ $rc == 10 && $rc2 == 0 && "$out2" == "끝: OK" && $rc3 == 1 ]] && grep -q 'SKILL-SUMMARIZE-TEXT' <<< "$out" && grep -q '@g-mixed' <<< "$out" && grep -q '자기 자신으로 돌아온다' <<< "$e"; then ok "T14 품은 기어의 흐름이 펼쳐짐(글은 그 기어의 것), 도는 흐름은 거절"
else bad "T14 rc=$rc rc2=$rc2 out2=$out2 rc3=$rc3 e=$e"; fi
rm -rf scv/gears/loop-a scv/gears/loop-b; bash "$G" index >/dev/null

# T15 — 이름: 기어와 톱니는 같은 이름을 못 쓰고, teeth 는 못 쓴다. 새 톱니 파일에는 주석이 없다(첫 줄 #! 만)
bash "$G" new upper --kind gear --flow "count" --does x >/dev/null 2>&1; r1=$?
bash "$G" new g-sh --kind tooth --does x >/dev/null 2>&1; r2=$?
bash "$G" new teeth --kind gear --flow "upper" --does x >/dev/null 2>&1; r3=$?
bash "$G" new plain --kind tooth --does "그대로" >/dev/null 2>&1
nc="$(grep -c '^[[:space:]]*#' scv/gears/teeth/plain.sh)"
[[ $r1 == 1 && $r2 == 1 && $r3 == 2 && $nc == 1 ]] && ok "T15 같은 이름 거절(1) · teeth 거절(2) · 새 톱니 파일은 주석 없이 본문만" || bad "T15 r1=$r1 r2=$r2 r3=$r3 nc=$nc"

# T16 — 실행 도중의 상태는 기본으로 기록 폴더의 숨김 자리에 둔다(훅과 같은 자리)
out="$(printf 'hello\n' | env -u SCV_GEAR_STATE_DIR bash "$G" run g-mixed 2>/dev/null)"; tok="$(token_of "$out")"
[[ -n "$tok" && -f "scv/journal/.gear-run/$tok/wait" ]] && ok "T16 실행 상태는 scv/journal/.gear-run/<표>/" || bad "T16 tok=$tok"
rm -rf scv/journal

# T17 — 선택 답 훅의 길: 질문에 확인 표가 있고 답이 "실행"이면 턴 검사가 실행기에 확인을 적는다
rm -f sent.marker
out="$(printf 'hello\n' | bash "$G" run g-out 2>/dev/null)"; tok="$(token_of "$out")"; tag="$(tag_of "$out")"
bash "$CORE/scripts/turn-check.sh" choice --question "밖으로 보낼까요? $tag" --answer "실행 (Recommended)" >/dev/null 2>&1
out17="$(bash "$G" resume "$tok" 2>/dev/null </dev/null)"; rc=$?
# 계획 기록 검사를 꺼 두어도 확인은 적힌다
rm -f sent.marker
out="$(printf 'hello\n' | bash "$G" run g-out 2>/dev/null)"; tok2="$(token_of "$out")"; tag="$(tag_of "$out")"
SCV_TURN_PLAN_CHECK=off bash "$CORE/scripts/turn-check.sh" choice --question "밖으로 보낼까요? $tag" --answer "실행" >/dev/null 2>&1
bash "$G" resume "$tok2" >/dev/null 2>&1 </dev/null; rcOff=$?
[[ $rc == 0 && "$out17" == HELLO && $rcOff == 0 && -e sent.marker ]] && ok "T17 선택 답(실행) → 턴 검사 → 실행기 확인 → 이어가기(계획 기록 검사를 꺼도)" || bad "T17 rc=$rc out=$out17 rcOff=$rcOff"
rm -rf scv/journal

# T18 — 톱니 사전에 폴더 밖을 가리키는 이름이 적혀 있어도 돌리지 않는다
mkproj escape
printf '#!/usr/bin/env bash\n: > escaped.marker\ncat\n' > evil.sh
mkdir -p scv/gears/teeth
printf '### ../../evil\n- 역할: 밖의 파일\n- 표시: effect\n- 값: * → *\n' > scv/gears/teeth/TEETH.md
e="$(printf 'a\n' | bash "$G" run ../../evil 2>&1 >/dev/null)"; r1=$?
bash "$G" new g --kind gear --flow "../../evil" --does x >/dev/null 2>&1
e2="$(printf 'a\n' | bash "$G" run g 2>&1 >/dev/null)"; r2=$?
[[ $r1 != 0 && $r2 == 1 && ! -e escaped.marker ]] && grep -q '쓸 수 없는 톱니 이름' <<< "$e2" && ok "T18 폴더 밖을 가리키는 톱니 이름은 실행 전에 거절" || bad "T18 r1=$r1 r2=$r2 e2=$e2"

# T19 — 이름이 겹쳐도 밖으로 톱니는 확인 없이 돌지 않는다: 같은 이름의 기어 폴더 · 톱니 사전의 두 번째 항목
cd "$WORK/main" || exit 1
rm -f sent.marker
mkdir -p scv/gears/send; printf 'flow: upper\ndoes: 이름이 겹치는 기어\n' > scv/gears/send/GEAR.md
printf 'hello\n' | bash "$G" run g-out >/dev/null 2>&1; r1=$?
m1=no; [[ -e sent.marker ]] && m1=yes
rm -rf scv/gears/send
cp scv/gears/teeth/TEETH.md "$WORK/teeth.bak"
printf '\n### send\n- 역할: 두 번째 항목\n- 표시: effect\n- 값: text → text\n' >> scv/gears/teeth/TEETH.md
e="$(printf 'hello\n' | bash "$G" run g-out 2>&1 >/dev/null)"; r2=$?
printf 'hello\n' | bash "$G" run send >/dev/null 2>&1; r3=$?
m2=no; [[ -e sent.marker ]] && m2=yes
cp "$WORK/teeth.bak" scv/gears/teeth/TEETH.md
[[ $r1 == 11 && $m1 == no && $r2 == 1 && $r3 == 1 && $m2 == no ]] && grep -q '2번 적혀' <<< "$e" && ok "T19 같은 이름의 기어 폴더 → 여전히 확인에서 멈춤(11), 사전의 중복 항목 → 실행 전 거절(1)" || bad "T19 r1=$r1 m1=$m1 r2=$r2 r3=$r3 m2=$m2"

# T20 — 실행처럼 보이는 거절 답은 확인이 아니고, 나중의 거절은 앞의 확인을 거두고, 지난 단계의 물음으로 다음 단계가 열리지 않는다
rm -f sent.marker
t20=""
for a in "실행 하지 마세요" "실행 안 함" "Run later" "실행하지 않음"; do
  out="$(printf 'hello\n' | bash "$G" run g-out 2>/dev/null)"; tok="$(token_of "$out")"; tag="$(tag_of "$out")"
  bash "$G" confirm --question "보낼까요? $tag" --answer "$a" >/dev/null 2>&1
  bash "$G" resume "$tok" >/dev/null 2>&1 </dev/null; [[ $? == 11 && ! -e sent.marker ]] || t20="$t20 [$a]"
done
out="$(printf 'hello\n' | bash "$G" run g-out 2>/dev/null)"; tok="$(token_of "$out")"; tag="$(tag_of "$out")"
bash "$G" confirm --question "보낼까요? $tag" --answer "실행" >/dev/null 2>&1
bash "$G" confirm --question "보낼까요? $tag" --answer "실행하지 않음" >/dev/null 2>&1
bash "$G" resume "$tok" >/dev/null 2>&1 </dev/null; [[ $? == 11 && ! -e sent.marker ]] || t20="$t20 [거절이 확인을 못 거둠]"
tooth send2 outward text text ': > sent2.marker; cat'
bash "$G" new g-two --kind gear --flow "send | send2" --does "밖으로 두 번" >/dev/null
out="$(printf 'hello\n' | bash "$G" run g-two 2>/dev/null)"; tok="$(token_of "$out")"; tag1="$(tag_of "$out")"
bash "$G" confirm --question "보낼까요? $tag1" --answer "실행" >/dev/null 2>&1
bash "$G" resume "$tok" >/dev/null 2>&1 </dev/null; rA=$?
bash "$G" confirm --question "보낼까요? $tag1" --answer "실행" >/dev/null 2>&1
bash "$G" resume "$tok" >/dev/null 2>&1 </dev/null; rB=$?
[[ $rA == 11 && $rB == 11 && -e sent.marker && ! -e sent2.marker ]] || t20="$t20 [지난 물음으로 다음 단계가 열림 rA=$rA rB=$rB]"
[[ -z "$t20" ]] && ok "T20 거절처럼 읽히는 답 넷 · 나중의 거절 · 지난 단계의 물음 — 모두 확인이 아님" || bad "T20 틀림:$t20"
rm -rf scv/gears/g-two; rm -f scv/gears/teeth/send2.sh sent.marker sent2.marker; cp "$WORK/teeth.bak" scv/gears/teeth/TEETH.md; bash "$G" index >/dev/null

# T21 — 표시를 잘못 적은 밖으로 톱니는 어느 언어 설정에서도 그냥 돌지 않는다(확인에서 멈추거나 거절)
mkproj marks
printf '#!/usr/bin/env bash\n: > out.marker\ncat\n' > "$WORK/out.sh"
t21=""
for v in 'outward (push)' $'\toutward' 'outward'$'\xc2\xa0' 'Outward' ''; do
  for form in '- 표시: %s' '-  표시: %s' '- 표시:%s'; do
    mkdir -p scv/gears/teeth; cp "$WORK/out.sh" scv/gears/teeth/o.sh
    { printf '### o\n- 역할: 밖으로\n'; [[ -z "$v" ]] || printf -- "$form\n" "$v"; printf -- '- 값: * → *\n'; } > scv/gears/teeth/TEETH.md
    for loc in C en_US.UTF-8; do
      printf 'a\n' | LC_ALL=$loc bash "$G" run o >/dev/null 2>&1; rc=$?
      [[ ( $rc == 1 || $rc == 11 ) && ! -e out.marker ]] || t21="$t21 [$form|$v|$loc → $rc]"
      rm -f out.marker; rm -rf scv/journal "$WORK/state"
    done
  done
done
[[ -z "$t21" ]] && ok "T21 잘못 적힌 표시 다섯 가지 × 적는 모양 셋 × 언어 설정 둘 — 한 번도 그냥 돌지 않음" || bad "T21 그냥 돎:$t21"

# T22 — 검사는 파일을 바꾸는 '순수' 톱니를 돌리지 않고, 끝나지 않는 예시를 붙잡고 있지 않는다
mkproj sneaky
printf 'keep\n' > victim.txt; printf 'keep\n' > victim2.txt
tooth eraser pure text text 'rm victim.txt; cat' '"a" → "a"'
tooth mover pure text text 'mv victim2.txt gone.txt; cat' '"a" → "a"'
tooth writer pure text text 'cat > written.txt' '"a" → ""'
tooth hang pure text text "sleep 297.$$; cat" '"a" → "a"'
t0=$SECONDS
out="$(SCV_GEAR_EXAMPLE_SECONDS=1 bash "$G" check 2>&1)"; rc=$?
dt=$((SECONDS - t0))
if [[ $rc != 0 && -f victim.txt && -f victim2.txt && ! -e gone.txt && ! -e written.txt && $dt -lt 20 ]] && grep -q '^GEAR_RISK: eraser:2 rm' <<< "$out" \
   && grep -q '^GEAR_BAD: mover — 순수 톱니에 둘 수 없는 명령(2번째 줄 mv)' <<< "$out" && grep -q '^GEAR_BAD: writer — 순수 톱니에 둘 수 없는 명령(2번째 줄 >)' <<< "$out" \
   && grep -q '^GEAR_EXAMPLE: hang — 예시 1: 1초 안에 끝나지 않았다' <<< "$out"; then ok "T22 지우기 · 옮기기 · 파일로 쓰기는 돌리지 않고 지목, 끝나지 않는 예시는 1초에서 끊음(${dt}초)"
else bad "T22 rc=$rc dt=$dt"; printf '%s\n' "$out" | head -6 >&2; fi
# 끊긴 톱니가 띄운 명령이 남아 돌지 않는다(자식을 찾는 도구가 있을 때)
if command -v pgrep >/dev/null 2>&1; then
  sleep 1
  if pgrep -f "sleep 297.$$" >/dev/null 2>&1; then bad "T22b 끊긴 톱니의 명령이 남아 있다"; pkill -9 -f "sleep 297.$$" 2>/dev/null; else ok "T22b 끊긴 톱니가 띄운 명령도 함께 끝남"; fi
fi

# T23 — 값이 빠진 인자는 끝없이 돌지 않고 쓰는 법(2)으로 끝난다
lim 10 bash "$G" new zz --kind >/dev/null 2>&1; r1=$?
lim 10 bash "$G" confirm --question >/dev/null 2>&1; r2=$?
[[ $r1 == 2 && $r2 == 2 ]] && ok "T23 값이 빠진 인자 → 종료 코드 2" || bad "T23 r1=$r1 r2=$r2"

# T24 — 톱니 사전이 CRLF 이거나 값 끝에 빈칸이 있어도 같은 결과다
mkproj crlf
tooth up pure text text "tr 'a-z' 'A-Z'" '"ab" → "AB"'
tooth cnt pure text number "wc -c | tr -d ' '" '"abc" → "3"'
bash "$G" new g --kind gear --flow "up | cnt" --does "둘을 잇는다" >/dev/null
LC_ALL=C awk '{ if ($0 ~ /^- 값: /) $0 = $0 "  "; printf "%s\r\n", $0 }' scv/gears/teeth/TEETH.md > "$WORK/crlf.md"; cp "$WORK/crlf.md" scv/gears/teeth/TEETH.md
bash "$G" index >/dev/null
o="$(printf 'hello\n' | bash "$G" run g 2>&1)"; r1=$?
bash "$G" check >/dev/null 2>&1; r2=$?
cr="$(LC_ALL=C grep -c $'\r' scv/gears/teeth/TEETH.md)"
[[ $r1 == 0 && "$o" == 6 && $r2 == 0 && $cr -gt 0 ]] && ok "T24 CRLF · 값 끝 빈칸이 있는 톱니 사전 → 실행 · 검사 모두 그대로" || bad "T24 r1=$r1 o=$o r2=$r2 cr=$cr"

# T25 — 품은 기어에 flow 줄이 없으면 조용히 건너뛰지 않고 실행 전에 거절한다
printf '# inner\n\n글만 있다\n' > "$WORK/inner.md"; mkdir -p scv/gears/inner; cp "$WORK/inner.md" scv/gears/inner/GEAR.md
bash "$G" new outer --kind gear --flow "up | inner | up" --does x >/dev/null
e="$(printf 'a\n' | bash "$G" run outer 2>&1 >/dev/null)"; rc=$?
[[ $rc == 1 ]] && grep -q 'flow 줄이 없다' <<< "$e" && ok "T25 flow 줄이 없는 품은 기어 → 실행 전 거절" || bad "T25 rc=$rc e=$e"

# ── 인자 · 기어의 in · out · 예 (계획 20261124-wookiya1364-gears-io-args · TESTS.md T26 ~ T43) ──
# @effect io_teeth
# 이유: 지금 프로젝트에 인자를 받는 순수 톱니 head-n(앞 count 줄만, 기본값 3)과 순수 톱니 upper 를 만든다
io_teeth() {
  bash "$G" new head-n --kind tooth --mark pure --in lines --out lines --does "앞 count 줄만 낸다" --arg "count=3 — 낼 줄 수" \
    --example "\$'a\\nb\\nc\\nd' → \$'a\\nb\\nc'" >/dev/null
  printf '#!/usr/bin/env bash\nhead -n "$count"\n' > scv/gears/teeth/head-n.sh
  printf -- '- 예: %s\n' "count=1 \$'a\\nb' → \"a\"" >> scv/gears/teeth/TEETH.md
  tooth upper pure lines lines "tr 'a-z' 'A-Z'" '"ab" → "AB"'
}
# @effect six
# 이유: 소문자 여섯 줄을 표준 출력에 쓴다(시험 입력)
six() { printf 'a\nb\nc\nd\ne\nf\n'; }
# @effect nlines
# 이유: 파일의 줄 수를 센다(파일을 읽기만 한다)
nlines() { grep -c '' "$1" 2>/dev/null || true; }

mkproj io
io_teeth
bash "$G" new send --kind tooth --mark outward --in lines --out lines --does "보낸다" --arg "target=dev — 보낼 곳" >/dev/null
printf '#!/usr/bin/env bash\nprintf "%%s" "$target" > sent.marker; cat\n' > scv/gears/teeth/send.sh
tooth peek effect lines lines 'printf "[%s]" "${count:-}" > peek.marker; cat'
bash "$G" new g-hu --kind gear --flow "head-n | upper" --does "앞 줄을 대문자로" >/dev/null
bash "$G" new g-made --kind gear --flow "head-n | upper" --does "앞 두 줄을 대문자로" --arg count=2 --example "count=2 \$'a\\nb\\nc' → \$'A\\nB'" >/dev/null
bash "$G" check > "$WORK/c41" 2>&1; rc41=$?
bash "$G" new g-arg --kind gear --flow "head-n | upper" --does "앞 네 줄" --arg count=4 >/dev/null
bash "$G" new g-outer --kind gear --flow "g-arg" --does "바깥이 이긴다" --arg count=2 >/dev/null
bash "$G" new g-outer2 --kind gear --flow "g-arg" --does "안쪽 값 그대로" >/dev/null
bash "$G" new g-peek --kind gear --flow "head-n | peek" --does "선언 안 한 톱니" >/dev/null
bash "$G" new g-send --kind gear --flow "upper | send" --does "밖으로 보낸다" >/dev/null
bash "$G" new g-judge --kind gear --flow "upper | @ | head-n" --does "판단을 거친다" >/dev/null
printf 'flow: upper | @ | head-n\nin: lines — 글 줄들\nout: lines — 고른 줄들\narg: count=5\n예: "a" → "A"\ndoes: 판단을 거친다\n\nJUDGE-TEXT\n고른 줄만 돌려준다.\n' > scv/gears/g-judge/GEAR.md
printf 'flow: head-n | upper\nin: lines — 글 줄들\nout: lines — 대문자 줄들\ndoes: 값이 보이는 기어\n\n# g-sig\n' > "$WORK/gsig.md"
mkdir -p scv/gears/g-sig && cp "$WORK/gsig.md" scv/gears/g-sig/GEAR.md
bash "$G" index >/dev/null

# T26 — 같은 기어, 다른 인자: 출력이 인자를 따른다
six | bash "$G" run g-hu count=2 > "$WORK/a2" 2>/dev/null; r1=$?
six | bash "$G" run g-hu count=5 > "$WORK/a5" 2>/dev/null; r2=$?
if [[ $r1 == 0 && $r2 == 0 && "$(cat "$WORK/a2")" == $'A\nB' && "$(cat "$WORK/a5")" == $'A\nB\nC\nD\nE' ]]; then ok "T26 같은 기어 · count=2 → 2줄, count=5 → 5줄"
else bad "T26 r1=$r1 r2=$r2 a2=$(tr '\n' ' ' < "$WORK/a2") a5=$(tr '\n' ' ' < "$WORK/a5")"; fi

# T27 — 인자를 주지 않으면 사전의 기본값(3)
o="$(six | bash "$G" run g-hu 2>/dev/null)"; rc=$?
[[ $rc == 0 && "$o" == $'A\nB\nC' ]] && ok "T27 인자 없음 → 사전의 기본값 3줄" || bad "T27 rc=$rc o=$o"

# T28 — 기어 파일의 arg 줄이 기본값을 덮고, 실행 때 준 값이 그것을 덮는다
o1="$(six | bash "$G" run g-arg 2>/dev/null)"; r1=$?
o2="$(six | bash "$G" run g-arg count=1 2>/dev/null)"; r2=$?
[[ $r1 == 0 && $r2 == 0 && "$o1" == $'A\nB\nC\nD' && "$o2" == A ]] && ok "T28 기어 파일 값 4줄, 실행 때 준 값 1줄" || bad "T28 r1=$r1 r2=$r2 o1=$o1 o2=$o2"

# T29 — 안에 든 기어의 인자: 바깥 기어가 안쪽을 이기고, 바깥에 없으면 안쪽 값 그대로
o1="$(six | bash "$G" run g-outer 2>/dev/null)"; r1=$?
o2="$(six | bash "$G" run g-outer2 2>/dev/null)"; r2=$?
[[ $r1 == 0 && $r2 == 0 && "$o1" == $'A\nB' && "$o2" == $'A\nB\nC\nD' ]] && ok "T29 바깥 기어 값 2줄, 바깥에 없으면 안쪽 값 4줄" || bad "T29 r1=$r1 r2=$r2 o1=$o1 o2=$o2"

# T30 — 선언하지 않은 인자 · 모양이 틀린 인자는 한 단계도 돌기 전에 거부한다(2)
o="$(six | bash "$G" run g-hu nope=1 2> "$WORK/e30")"; rc=$?
t30=1
[[ $rc == 2 && -z "$o" ]] && grep -q 'nope' "$WORK/e30" && grep -q 'count' "$WORK/e30" || t30=0
for w in 'Count=1' '=1' 'count'; do
  o="$(six | bash "$G" run g-hu "$w" 2>/dev/null)"; rc=$?
  [[ $rc == 2 && -z "$o" ]] || t30=0
done
[[ $t30 == 1 ]] && ok "T30 모르는 인자 · 틀린 모양 → 거부(2), 출력 없음, 오류 글에 모르는 이름과 쓸 수 있는 이름" || bad "T30 $(cat "$WORK/e30")"

# T31 — 선언하지 않은 값은 톱니 안으로 들어가지 않는다(바깥 환경에 같은 이름이 있어도)
rm -f peek.marker
o="$(six | count=9 bash "$G" run g-peek count=2 2>/dev/null)"; rc=$?
[[ $rc == 0 && "$o" == $'a\nb' && "$(cat peek.marker 2>/dev/null)" == "[]" ]] && ok "T31 선언한 톱니만 값을 받음 — 선언 안 한 톱니가 읽은 값은 빈 글" || bad "T31 rc=$rc o=$o peek=$(cat peek.marker 2>/dev/null)"

# T32 — 판단 단계에서 멈췄다 이어 가도 인자가 그대로다. 이어가기에는 인자를 줄 수 없다
out="$(printf 'a\nb\n' | bash "$G" run g-judge count=2 2>/dev/null)"; r1=$?; tok="$(token_of "$out")"
o="$(printf 'p\nq\nr\ns\nt\n' | bash "$G" resume "$tok" 2>/dev/null)"; r2=$?
out="$(printf 'a\nb\n' | bash "$G" run g-judge count=2 2>/dev/null)"; tok="$(token_of "$out")"
printf 'p\nq\n' | bash "$G" resume "$tok" count=4 >/dev/null 2>&1; r3=$?
[[ $r1 == 10 && $r2 == 0 && "$o" == $'p\nq' && $r3 == 2 ]] && ok "T32 멈췄다 이어도 count=2 그대로(2줄), 이어가기에 인자 → 거부(2)" || bad "T32 r1=$r1 r2=$r2 o=$o r3=$r3"

# T33 — 인자로는 밖으로 나가는 확인을 건너뛸 수 없고, 확인 글에 인자 값이 보인다
rm -f sent.marker
out="$(printf 'hi\n' | bash "$G" run g-send target=stage 2>/dev/null)"; r1=$?; tok="$(token_of "$out")"; tag="$(tag_of "$out")"
bash "$G" resume "$tok" >/dev/null 2>&1; r2=$?
m1=no; [[ -e sent.marker ]] && m1=yes
bash "$G" confirm --question "보낼까요? $tag" --answer "실행" >/dev/null 2>&1
o="$(bash "$G" resume "$tok" 2>/dev/null)"; r3=$?
if [[ $r1 == 11 && $r2 == 11 && $m1 == no && $r3 == 0 && "$o" == HI && "$(cat sent.marker 2>/dev/null)" == stage ]] && grep -q 'target=stage' <<< "$out"; then ok "T33 인자를 줘도 확인에서 멈춤(11) · 확인 글에 target=stage · 확인 뒤 stage 로 실행"
else bad "T33 r1=$r1 r2=$r2 m1=$m1 r3=$r3 o=$o sent=$(cat sent.marker 2>/dev/null)"; fi

# T35 — 같은 입력 + 같은 인자면 출력이 바이트까지 같다
six | bash "$G" run g-hu count=2 > "$WORK/b1" 2>/dev/null; r1=$?
six | bash "$G" run g-hu count=2 > "$WORK/b2" 2>/dev/null; r2=$?
[[ $r1 == 0 && $r2 == 0 ]] && cmp -s "$WORK/b1" "$WORK/b2" && ok "T35 같은 입력 + 같은 인자 → 같은 바이트" || bad "T35 r1=$r1 r2=$r2"

# T36 — 기어 파일의 in · out 과 인자가 목록에 나온다
o="$(bash "$G" list 2>/dev/null)"; rc=$?
row="$(grep '^g-sig'$'\t' <<< "$o")"
[[ $rc == 0 && "$row" == *"lines → lines"* && "$row" == *"count=3"* ]] && ok "T36 목록의 기어 줄에 lines → lines 와 count=3" || bad "T36 rc=$rc row=$row"

# T41 — 기어를 만들 때 in · out 을 첫 · 끝 톱니에서 채우고, --arg · --example 이 맨 위 줄로 들어간다(만든 직후 검사 통과)
if [[ $rc41 == 0 ]] && grep -q '^in: lines' scv/gears/g-hu/GEAR.md && grep -q '^out: lines' scv/gears/g-hu/GEAR.md \
   && grep -q '^arg: count=2$' scv/gears/g-made/GEAR.md && grep -q '^예: count=2 ' scv/gears/g-made/GEAR.md; then ok "T41 만들기 — in · out 자동, arg · 예 줄, 만든 직후 검사 통과"
else bad "T41 rc41=$rc41 $(head -n 5 scv/gears/g-hu/GEAR.md | tr '\n' '|') $(tail -n 3 "$WORK/c41" | tr '\n' '|')"; fi

# T43 — 판단 단계에서 넘기는 글에 맨 위 줄(flow · in · out · 예 · arg)이 실리지 않는다
out="$(printf 'a\n' | bash "$G" run g-judge 2>/dev/null)"; rc=$?
if [[ $rc == 10 ]] && grep -q 'JUDGE-TEXT' <<< "$out" && ! grep -qE '^(flow|in|out|예|arg):' <<< "$out"; then ok "T43 넘기는 글에 맨 위 줄 없음"
else bad "T43 rc=$rc $(grep -E '^(flow|in|out|예|arg):' <<< "$out" | tr '\n' '|')"; fi

# T34 — 인자가 든 예시로 순수 톱니를 검사한다: 틀린 예시의 톱니만 짚고, 고치면 통과
mkproj io-ex
io_teeth
bash "$G" new cut2 --kind tooth --mark pure --in lines --out lines --does "앞 count 줄만" --arg "count=2" --example "count=2 \$'a\\nb\\nc' → \"a\"" >/dev/null
printf '#!/usr/bin/env bash\nhead -n "$count"\n' > scv/gears/teeth/cut2.sh
bash "$G" index >/dev/null
out="$(bash "$G" check 2>&1)"; r1=$?
sed -i.bak 's/^- 예: count=2 .*/- 예: count=2 $'"'"'a\\nb\\nc'"'"' → $'"'"'a\\nb'"'"'/' scv/gears/teeth/TEETH.md && rm -f scv/gears/teeth/TEETH.md.bak
out2="$(bash "$G" check 2>&1)"; r2=$?
if [[ $r1 == 1 && $r2 == 0 ]] && grep -q '^GEAR_EXAMPLE: cut2 ' <<< "$out" && ! grep -q '^GEAR_[A-Z]*: head-n' <<< "$out"; then ok "T34 인자가 든 예시 — 틀린 톱니만 실패(1), 고치면 통과"
else bad "T34 r1=$r1 r2=$r2 $(tr '\n' '|' <<< "$out") // $(tr '\n' '|' <<< "$out2")"; fi

# T37 — 기어의 in · out 이 첫 · 끝 톱니와 다르면 검사가 잡는다
mkproj io-sig
io_teeth
mkdir -p scv/gears/g-in scv/gears/g-out
printf 'flow: head-n | upper\nin: number\nout: lines\ndoes: 받는 값이 틀린 기어\n\n# g-in\n' > scv/gears/g-in/GEAR.md
printf 'flow: head-n | upper\nin: lines\nout: number\ndoes: 돌려주는 값이 틀린 기어\n\n# g-out\n' > scv/gears/g-out/GEAR.md
bash "$G" index >/dev/null
out="$(bash "$G" check 2>&1)"; rc=$?
if [[ $rc == 1 && "$(grep -c '^GEAR_SIG: ' <<< "$out")" == 2 ]] && grep -q '^GEAR_SIG: g-in: in number .*lines' <<< "$out" && grep -q '^GEAR_SIG: g-out: out number .*lines' <<< "$out"; then ok "T37 in · out 이 톱니와 다르면 실패(1) — 기어 · 적은 이름 · 톱니의 이름"
else bad "T37 rc=$rc $(tr '\n' '|' <<< "$out")"; fi

# T38 — 순수 톱니로만 된 기어의 예시는 실제로 돌려 맞춰 본다
mkproj io-gex
io_teeth
mkdir -p scv/gears/g-ok scv/gears/g-wrong
printf 'flow: head-n | upper\nin: lines\nout: lines\n예: count=2 $'"'"'a\\nb\\nc'"'"' → $'"'"'A\\nB'"'"'\ndoes: 맞는 예시\n\n# g-ok\n' > scv/gears/g-ok/GEAR.md
printf 'flow: head-n | upper\nin: lines\nout: lines\n예: $'"'"'a\\nb'"'"' → $'"'"'a\\nb'"'"'\ndoes: 틀린 예시\n\n# g-wrong\n' > scv/gears/g-wrong/GEAR.md
bash "$G" index >/dev/null
out="$(bash "$G" check 2>&1)"; rc=$?
if [[ $rc == 1 && "$(grep -c '^GEAR_EXAMPLE: g-wrong ' <<< "$out")" == 1 ]] && ! grep -q '^GEAR_[A-Z]*: g-ok' <<< "$out"; then ok "T38 기어 예시 — 순수 흐름은 돌려 맞춤, 틀린 기어만 실패(1)"
else bad "T38 rc=$rc $(tr '\n' '|' <<< "$out")"; fi

# T39 — 판단 단계나 순수하지 않은 톱니가 든 기어의 예시는 보기용: 돌리지 않는다
mkproj io-show
io_teeth
tooth mark-it effect lines lines ': > ran.marker; cat'
mkdir -p scv/gears/g-j scv/gears/g-e
printf 'flow: upper | @ | head-n\nin: lines\nout: lines\n예: "a" → "A"\ndoes: 판단이 든 기어\n\nJ-TEXT\n' > scv/gears/g-j/GEAR.md
printf 'flow: upper | mark-it\nin: lines\nout: lines\n예: "a" → "A"\ndoes: 부수효과가 든 기어\n\n# g-e\n' > scv/gears/g-e/GEAR.md
bash "$G" index >/dev/null
out="$(bash "$G" check 2>&1)"; rc=$?
if [[ $rc == 0 && ! -e ran.marker ]] && grep -q '보기용 예시 2개' <<< "$out"; then ok "T39 보기용 예시 2개 — 돌리지 않음, 검사 통과"
else bad "T39 rc=$rc marker=$([[ -e ran.marker ]] && echo yes || echo no) $(tr '\n' '|' <<< "$out")"; fi

# T40 — 0.100.0 모양의 기어와 톱니 사전(in · out · 예 · arg · 인자 줄 없음)은 그대로 돈다 — 빠진 줄은 알림만
mkproj old
mkdir -p scv/gears/teeth scv/gears/g-old
printf '# 톱니 사전\n\n### up\n- 역할: 대문자로\n- 표시: pure\n- 값: text → text\n- 예: "ab" → "AB"\n\n### cnt\n- 역할: 센다\n- 표시: pure\n- 값: text → number\n- 예: "abc" → "3"\n' > scv/gears/teeth/TEETH.md
printf '#!/usr/bin/env bash\ntr a-z A-Z\n' > scv/gears/teeth/up.sh
printf '#!/usr/bin/env bash\nwc -c | tr -d " "\n' > scv/gears/teeth/cnt.sh
printf 'flow: up | cnt\ndoes: 대문자로 바꾸고 센다\nwords: 세기\n\n# g-old\n' > scv/gears/g-old/GEAR.md
bash "$G" index >/dev/null
o="$(printf 'hello\n' | bash "$G" run g-old 2>/dev/null)"; r1=$?
out="$(bash "$G" check 2>&1)"; r2=$?
if [[ $r1 == 0 && "$o" == 6 && $r2 == 0 ]] && grep -q '^GEAR_WARN: g-old' <<< "$out"; then ok "T40 옛 모양 기어 — 실행 결과 6, 검사 통과, 빠진 줄은 알림"
else bad "T40 r1=$r1 o=$o r2=$r2 $(tr '\n' '|' <<< "$out")"; fi

# T42 — 뜻이 이미 있는 이름 · 틀린 모양의 인자 이름은 만들 때(2)와 검사(1)에서 거부한다
mkproj io-badarg
t42=1
for a in 'http_proxy=x' 'Count=1' '1st=1'; do
  bash "$G" new bad1 --kind tooth --arg "$a" >/dev/null 2>&1; rc=$?
  [[ $rc == 2 && ! -e scv/gears/teeth/bad1.sh ]] || t42=0
done
mkdir -p scv/gears/teeth
printf '# 톱니 사전\n\n### px\n- 역할: 그대로 낸다\n- 표시: pure\n- 값: text → text\n- 인자: no_proxy=x\n- 예: "a" → "a"\n' > scv/gears/teeth/TEETH.md
printf '#!/usr/bin/env bash\ncat\n' > scv/gears/teeth/px.sh
bash "$G" index >/dev/null
out="$(bash "$G" check 2>&1)"; rc=$?
[[ $t42 == 1 && $rc == 1 ]] && grep -q 'no_proxy' <<< "$out" && ok "T42 인자 이름 — 만들 때 거부(2 · 파일 없음), 검사에서 실패(1)" || bad "T42 t42=$t42 rc=$rc $(tr '\n' '|' <<< "$out")"

# T52 — 사전의 기어 줄 셋째 칸: 펼친 흐름에서 가장 센 표시(순수만 pure · 부작용 effect · 밖으로 outward · 판단 단계 judge), 안에 든 기어도 펼쳐서 본다
mkproj io-mark
io_teeth
bash "$G" new save --kind tooth --mark effect --in lines --out lines --does "파일에 쓴다" >/dev/null
bash "$G" new send --kind tooth --mark outward --in lines --out lines --does "보낸다" >/dev/null
bash "$G" new g-pure --kind gear --flow "head-n | upper" --does "앞 줄을 대문자로" >/dev/null
bash "$G" new g-eff --kind gear --flow "head-n | save" --does "앞 줄을 쓴다" >/dev/null
bash "$G" new g-out --kind gear --flow "head-n | send" --does "앞 줄을 보낸다" >/dev/null
bash "$G" new g-judge --kind gear --flow "head-n | @ | upper" --does "앞 줄을 보고 고친다" >/dev/null
bash "$G" new g-nest --kind gear --flow "g-pure | save" --does "대문자로 바꿔 쓴다" >/dev/null
bash "$G" index >/dev/null
m="$(for g in g-pure g-eff g-out g-judge g-nest; do LC_ALL=C awk -F'\t' -v n="$g" '$1 == n { printf "%s ", $3 }' scv/gears/INDEX.tsv; done)"
tc="$(LC_ALL=C awk -F'\t' '$1 == "upper" { print NF }' scv/gears/INDEX.tsv)"
[[ "$m" == "pure effect outward judge effect " && "$tc" == 7 ]] && ok "T52 기어 줄의 표시 칸 — pure · effect · outward · judge, 안에 든 기어는 펼쳐서" || bad "T52 [$m] 톱니 칸 수=$tc"

# T53 — gear.sh ask: 인자마다 이름 · 지금 값 · 정해 둠 여부 · 설명, 받는 값이 있으면 input 줄. 없는 이름은 2
bash "$G" new g-fix --kind gear --flow "head-n | upper" --arg count=2 --does "앞 두 줄을 대문자로" >/dev/null
bash "$G" index >/dev/null
a1="$(bash "$G" ask g-pure)"; a2="$(bash "$G" ask g-fix)"; a3="$(bash "$G" ask upper)"
bash "$G" ask nope >/dev/null 2>&1; rc=$?
w1=$'GEAR_ASK: g-pure\narg\tcount\t3\topen\t낼 줄 수\ninput\tlines'
w2=$'GEAR_ASK: g-fix\narg\tcount\t2\tfixed\t낼 줄 수\ninput\tlines'
w3=$'GEAR_ASK: upper\ninput\tlines'
[[ "$a1" == "$w1" && "$a2" == "$w2" && "$a3" == "$w3" && $rc == 2 ]] && ok "T53 값 안내 줄 — 열린 인자 · 기어가 정해 둔 인자 · 받는 값, 없는 이름은 2" || bad "T53 rc=$rc [$a1] [$a2] [$a3]"

# T54 — 기어 규약 글에 값 안내 규칙 네 가지가 있다(core 밖에서 도는 사본은 규약 글이 같은 자리에 있다)
GMD="$CORE/protocols/gear.md"
if [[ -f "$GMD" ]]; then
  t54=1
  for want in 'gear.sh" ask' 'through the choice tool' 'default is the first option' 'already gives' 'nobody can answer'; do
    grep -qF -- "$want" "$GMD" || { t54=0; echo "  없음: $want" >&2; }
  done
  [[ $t54 == 1 ]] && ok "T54 기어 규약 — 빠진 값은 선택 도구로 안내(기본값이 첫 보기 · 준 값은 안 물음 · 사람 없으면 기본값)" || bad "T54 규약 글에 빠진 구절"
else ok "T54 (규약 글 없음 — 건너뜀)"; fi

if [[ $fail -ne 0 ]]; then echo "test-gear-run: FAIL" >&2; exit 1; fi
echo "test-gear-run: all passed"
