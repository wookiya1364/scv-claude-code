#!/usr/bin/env bash
# test-settings.sh — 설정 읽기 이음매 검사 (1단계).
#
# 계획 20260823-wookiya1364-settings-json 의 TESTS.md 중 1단계 몫:
#   T1. 순수 조회 — 고정 입력, 고정 출력
#   T2. 순수부에 부수효과 없음 (정적 검사)
#   T3. 우선순위 해석 — 16가지 전수
#   T8. 없거나 깨져도 죽지 않는다
#
# 판정은 전부 문자열 비교다. "잘 된 것 같다" 는 자리가 없다.
#
# Run: bash core/tests/test-settings.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$REPO_ROOT/scripts/lib/settings.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi; }

[[ -f "$LIB" ]] || { echo "✖ 라이브러리 없음: $LIB"; exit 1; }
# shellcheck source=../scripts/lib/settings.sh
source "$LIB"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ============================================================ T3. 우선순위 전수
echo "T3. 우선순위 — 16가지 조합 전수"

# 후보 넷의 있음/없음 = 2^4 = 16. 표본이 아니라 전체를 본다.
# 기대: 환경변수 → 비밀 → 일반 → 기본값 순으로 첫 번째 있는 값.
T3_OK=0; T3_N=0
for e in "" "E"; do
 for s in "" "S"; do
  for p in "" "P"; do
   for d in "" "D"; do
     T3_N=$((T3_N + 1))
     want=""
     if   [[ -n "$e" ]]; then want="$e"
     elif [[ -n "$s" ]]; then want="$s"
     elif [[ -n "$p" ]]; then want="$p"
     else                     want="$d"
     fi
     got="$(settings_resolve "$e" "$s" "$p" "$d")"
     if [[ "$got" == "$want" ]]; then
       T3_OK=$((T3_OK + 1))
     else
       fail "T3 [e=$e s=$s p=$p d=$d] — expected [$want], got [$got]"
     fi
   done
  done
 done
done
if [[ $T3_OK -eq $T3_N ]]; then
  ok "16가지 조합 전부 기대와 일치"
  echo "OK [T3] $T3_OK/$T3_N"
else
  echo "✖ [T3] $T3_OK/$T3_N"
fi

# 같은 입력 100회 → 같은 출력. 반복 가능성 자체를 검사한다.
R1="$(settings_resolve "" "S" "P" "D")"
SAME=1
for _ in $(seq 1 100); do
  [[ "$(settings_resolve "" "S" "P" "D")" == "$R1" ]] || SAME=0
done
eq "같은 입력 100회 → 같은 출력" "1" "$SAME"

# ============================================================ T2. 정적 검사
echo
echo "T2. 순수부 — 부수효과 없음 (정적 검사)"

# 이 검사 자체가 순수함수다: 코드 텍스트를 받아 위반 목록을 낸다.
# 원칙이 문서에만 남지 않게 하는 장치 — 순수해야 할 자리에 효과가 섞이면 여기서 멈춘다.
extract_fn() {
  awk -v fn="$1" '
    $0 ~ "^"fn"\\(\\) \\{" { inside = 1 }
    inside { print }
    inside && /^\}$/ { exit }
  ' "$LIB"
}
strip_benign() {
  grep -vE '^[[:space:]]*#' \
    | sed -E 's/\(\([^)]*\)\)/@ARITH@/g' \
    | sed -E 's/<<</@HERESTRING@/g'
}
FORBIDDEN_CMD='(^|[;&|(][[:space:]]*|^[[:space:]]*)(date|curl|wget|git|ssh|mktemp|touch|rm|mv|cp|mkdir|sed|awk|grep|cat|head|tail|source)([[:space:]]|$)'
FORBIDDEN_REDIR='[^@<>&[:space:]][[:space:]]*(>>?|<)[[:space:]]*[^&@[:space:]]'
FORBIDDEN_RANDOM='\$RANDOM|\$\{RANDOM'

T2_VIOL=0
# settings_resolve 는 완전히 순수해야 한다 — 외부 명령조차 부르지 않는다.
body="$(extract_fn settings_resolve)"
if [[ -z "$body" ]]; then
  fail "T2 — settings_resolve 본문을 못 찾음"; T2_VIOL=$(( T2_VIOL + 1 ))
else
  hits="$(printf '%s\n' "$body" | strip_benign \
    | grep -nE "$FORBIDDEN_CMD|$FORBIDDEN_REDIR|$FORBIDDEN_RANDOM" || true)"
  if [[ -n "$hits" ]]; then
    fail "T2 — settings_resolve 에 부수효과가 있음:"
    printf '%s\n' "$hits" | sed 's/^/      /'
    T2_VIOL=$(( T2_VIOL + 1 ))
  else
    ok "settings_resolve — 외부 명령·파일·시각·무작위 없음"
  fi
fi

# settings_lookup_json 은 파서를 부르되 디스크는 만지지 않아야 한다.
body="$(extract_fn settings_lookup_json)"
if [[ -z "$body" ]]; then
  fail "T2 — settings_lookup_json 본문을 못 찾음"; T2_VIOL=$(( T2_VIOL + 1 ))
else
  DISK='(^|[;&|(][[:space:]]*|^[[:space:]]*)(date|curl|wget|git|mktemp|touch|rm|mv|cp|mkdir|source)([[:space:]]|$)|\$RANDOM'
  hits="$(printf '%s\n' "$body" | strip_benign | grep -nE "$DISK" || true)"
  if [[ -n "$hits" ]]; then
    fail "T2 — settings_lookup_json 이 디스크/시각을 만짐:"
    printf '%s\n' "$hits" | sed 's/^/      /'
    T2_VIOL=$(( T2_VIOL + 1 ))
  else
    ok "settings_lookup_json — 디스크·시각·무작위 없음 (파서 호출만)"
  fi
fi

# 검사기 자체가 도는지 확인한다 — 통과만 하고 아무것도 안 보는 검사기는 무의미하다.
CANARY='canary() {
  local x
  x="$(date +%s)"
  cat /etc/hosts > /tmp/x
}'
canary_hits="$(printf '%s\n' "$CANARY" | strip_benign \
  | grep -cE "$FORBIDDEN_CMD|$FORBIDDEN_REDIR|$FORBIDDEN_RANDOM" || true)"
if [[ "${canary_hits:-0}" -ge 2 ]]; then
  ok "검사기 자체 확인 — 일부러 넣은 부수효과를 잡는다 (${canary_hits}건)"
else
  fail "T2 — 검사기가 부수효과를 못 잡는다 (canary ${canary_hits}건)"
  T2_VIOL=$(( T2_VIOL + 1 ))
fi
if [[ ${T2_VIOL} -eq 0 ]]; then echo "OK [T2]"; else echo "✖ [T2] 위반 ${T2_VIOL}건"; fi

# ============================================================ T1. JSON 조회
echo
echo "T1. JSON 조회 — 고정 입력, 고정 출력"

J='{"SCV_LANG":"korean","NUM":3,"YES":true,"BLANK":"","SPACED":"a b  c","UNI":"한글 값"}'
eq "문자열"            "korean"    "$(settings_lookup_json "$J" SCV_LANG)"
eq "숫자"              "3"         "$(settings_lookup_json "$J" NUM)"
eq "참거짓"            "true"      "$(settings_lookup_json "$J" YES)"
eq "빈 문자열"         ""          "$(settings_lookup_json "$J" BLANK)"
eq "공백 포함 원문"    "a b  c"    "$(settings_lookup_json "$J" SPACED)"
eq "유니코드 원문"     "한글 값"    "$(settings_lookup_json "$J" UNI)"
eq "없는 키"           ""          "$(settings_lookup_json "$J" NOPE)"
eq "중첩은 안 본다"    ""          "$(settings_lookup_json '{"a":{"b":1}}' a.b)"

J1="$(settings_lookup_json "$J" SCV_LANG)"
SAME=1
for _ in $(seq 1 50); do
  [[ "$(settings_lookup_json "$J" SCV_LANG)" == "$J1" ]] || SAME=0
done
eq "같은 입력 50회 → 같은 출력" "1" "$SAME"

# ============================================================ T8. 죽지 않는다
echo
echo "T8. 없거나 깨져도 죽지 않는다"

T8_OK=0
declare -a BAD=('' '{oops' '[1,2]' '"just a string"' '{"a":')
for b in "${BAD[@]}"; do
  out="$(settings_lookup_json "$b" X)"; rc=$?
  if [[ $rc -eq 0 && -z "$out" ]]; then T8_OK=$((T8_OK + 1))
  else fail "T8 — 입력 [$b] 에서 exit=$rc out=[$out]"; fi
done
eq "깨진 JSON 5가지 전부 조용히 빈 값" "5" "$T8_OK"

# 설정 파일이 없어도 기본값으로 간다
( cd "$WORK" && rm -f .env
  eq2() { [[ "$2" == "$3" ]] && ok "$1" || fail "$1 — expected [$2], got [$3]"; }
  : ) >/dev/null 2>&1
cd "$WORK"
rm -f .env
eq "파일 없음 → 기본값"   "fallback"  "$(settings_get NOTIFIER_PROVIDER fallback)"
: > .env
eq "빈 파일 → 기본값"     "fallback"  "$(settings_get NOTIFIER_PROVIDER fallback)"
printf 'JUNK LINE WITHOUT EQUALS\n#comment\n' > .env
eq "형식이 이상해도 죽지 않음" "fallback" "$(settings_get NOTIFIER_PROVIDER fallback)"

# .env 는 더 이상 읽지 않는다 — 그것이 이 이사의 목적이다.
mkdir -p scv
rm -f scv/scv_settings.json scv/scv_settings.secret.json
printf 'NOTIFIER_PROVIDER=slack\nSCV_LANG=korean\n' > .env
eq ".env 의 값은 읽히지 않는다" "" "$(settings_get NOTIFIER_PROVIDER 2>/dev/null)"
eq ".env 가 있어도 기본값으로 간다" "fb" "$(settings_get NOTIFIER_PROVIDER fb 2>/dev/null)"

# 조용히 떨어지지는 않는다 — 이사가 안 됐으면 반드시 알린다
warn="$(bash -c 'cd "'"$PWD"'"; source "'"$LIB"'"; settings_get NOTIFIER_PROVIDER' 2>&1 >/dev/null)"
if grep -q "NO LONGER read" <<<"$warn"; then ok "이사 안내가 나온다"; else fail "T6 — 조용히 기본값으로 떨어졌다"; fi
if grep -q "settings-set" <<<"$warn"; then ok "안내에 다음 행동이 있다"; else fail "T6 — 무엇을 하라는지 없다"; fi

# 같은 프로세스에서 여러 번 읽어도 안내는 한 번뿐이다 — 매번 떠들면 무시하게 된다
n="$(bash -c 'cd "'"$PWD"'"; source "'"$LIB"'"; settings_get A; settings_get B; settings_get C' 2>&1 >/dev/null | grep -c 'NO LONGER read' || true)"
eq "안내는 한 번만" "1" "$n"

# SCV 키가 없는 .env 는 남의 파일이다 — 참견하지 않는다
printf 'DATABASE_URL=postgres://x\n' > .env
n="$(bash -c 'cd "'"$PWD"'"; source "'"$LIB"'"; settings_get NOTIFIER_PROVIDER' 2>&1 >/dev/null | grep -c 'NO LONGER read' || true)"
eq "SCV 키가 없으면 아무 말 안 한다" "0" "$n"

eq "환경변수는 여전히 최우선" "discord" \
   "$(NOTIFIER_PROVIDER=discord bash -c 'source "'"$LIB"'"; settings_get NOTIFIER_PROVIDER 2>/dev/null')"

# 이사 전용 파서는 살아 있어야 한다 — settings-migrate.sh 가 쓴다
printf 'QUOTED="korean"\nLAST=first\nLAST=second\nDANGER=${UNSET_ON_PURPOSE}\nGOOD=fine\n' > .env
eq "이사 파서: 따옴표를 벗긴다"      "korean" "$(_settings_from_env_file QUOTED)"
eq "이사 파서: 마지막 정의가 이긴다" "second" "$(_settings_from_env_file LAST)"
out="$(set -u; _settings_from_env_file GOOD 2>/dev/null)"; rc=$?
if [[ $rc -eq 0 && "$out" == "fine" ]]; then
  ok "이사 파서: unset 참조가 있는 .env 도 nounset 아래에서 살아남는다 (source 하지 않는다)"
else
  fail "T8 — 이사 파서가 \${UNSET} 참조에 죽었다 (exit=$rc out=[$out])"
fi
rm -f .env
cd "$REPO_ROOT"
[[ $FAIL -eq 0 ]] && echo "OK [T8]" || echo "✖ [T8]"

# ============================================================ T5·T6·T7·T9 (2단계)
echo
echo "T5·T7. 새 저장소에서 읽고, 비밀 키는 커밋되는 파일에서 읽지 않는다"

cd "$WORK"
mkdir -p scv
rm -f .env
cat > scv/scv_settings.json <<'J'
{"NOTIFIER_PROVIDER":"discord","SCV_LANG":"japanese","SCV_PLAIN_MAX_SENTENCES":"4"}
J
cat > scv/scv_settings.secret.json <<'J'
{"DISCORD_BOT_TOKEN":"tok-123","SLACK_CHANNEL_ID":"C9"}
J
eq "일반 설정에서 읽음"   "discord"  "$(settings_get NOTIFIER_PROVIDER)"
eq "일반 설정 두 번째"    "japanese" "$(settings_get SCV_LANG)"
eq "비밀 설정에서 읽음"   "tok-123"  "$(settings_get DISCORD_BOT_TOKEN)"
eq "비밀 채널 ID"         "C9"       "$(settings_get SLACK_CHANNEL_ID)"
eq "없는 키는 기본값"     "fb"       "$(settings_get NOPE fb)"

# 비밀 키가 커밋되는 파일에 있으면 읽지 않는다 — 그리고 값은 절대 안 찍는다
cat > scv/scv_settings.json <<'J'
{"SLACK_BOT_TOKEN":"xoxb-LEAKED","SCV_LANG":"korean"}
J
out="$(settings_get SLACK_BOT_TOKEN 2>/dev/null)"
warn="$(settings_get SLACK_BOT_TOKEN 2>&1 >/dev/null)"
eq "비밀 키를 일반 파일에서 읽지 않는다" "" "$out"
if grep -q "must not live in" <<<"$warn"; then ok "경고가 나온다"; else fail "T7 — 경고가 없다"; fi
if grep -q "LEAKED" <<<"$warn"; then fail "T7 — 경고에 값이 찍혔다"; else ok "경고에 값이 안 찍힌다"; fi
eq "같은 파일의 일반 키는 정상" "korean" "$(settings_get SCV_LANG 2>/dev/null)"
echo "OK [T5] [T7]"

echo
echo "T6. 두 저장소를 섞지 않는다 · 되돌아가기"
printf 'NOTIFIER_PROVIDER=slack\nSCV_LANG=korean\n' > .env
cat > scv/scv_settings.json <<'J'
{"NOTIFIER_PROVIDER":"discord"}
J
rm -f scv/scv_settings.secret.json
eq "새 파일이 있으면 .env 를 안 본다" "discord" "$(settings_get NOTIFIER_PROVIDER)"
eq "새 파일에 없는 키는 .env 로 안 새어든다" "fb" "$(settings_get SCV_LANG fb)"
rm -f scv/scv_settings.json
eq "새 파일이 없으면 .env 로 되돌아가지 않는다" "" "$(settings_get NOTIFIER_PROVIDER 2>/dev/null)"
echo "OK [T6]"

echo
echo "T9. 이전 절차 — 한 번만, 원본은 그대로"
MIG="$WORK/mig"
mkdir -p "$MIG/scv" && cd "$MIG" && git init -q . 2>/dev/null
cat > .env <<'J'
DATABASE_URL=postgres://x
NOTIFIER_PROVIDER=slack
SCV_LANG=korean
SLACK_BOT_TOKEN=xoxb-abc
GITLAB_TOKEN=glpat-xyz
J
cp .env .env.orig
bash "$REPO_ROOT/scripts/settings-migrate.sh" >/dev/null 2>&1
eq "일반 설정이 옮겨짐"  "slack"    "$(settings_get NOTIFIER_PROVIDER)"
eq "비밀값이 옮겨짐"     "xoxb-abc" "$(settings_get SLACK_BOT_TOKEN)"
if diff -q .env .env.orig >/dev/null 2>&1; then ok "원본 .env 는 그대로"; else fail "T9 — 원본이 바뀌었다"; fi
if grep -q 'DATABASE_URL' scv/scv_settings.json scv/scv_settings.secret.json 2>/dev/null; then
  fail "T9 — SCV 와 무관한 키가 옮겨졌다"
else ok "SCV 가 아는 키만 옮긴다"; fi
if grep -q 'SLACK_BOT_TOKEN\|GITLAB_TOKEN' scv/scv_settings.json 2>/dev/null; then
  fail "T9 — 비밀값이 커밋되는 파일로 갔다"
else ok "비밀값은 커밋되는 파일에 없다"; fi
before="$(cat scv/scv_settings.json)"
bash "$REPO_ROOT/scripts/settings-migrate.sh" >/dev/null 2>&1
eq "두 번 돌려도 같다" "$before" "$(cat scv/scv_settings.json)"
cd "$REPO_ROOT"
echo "OK [T9]"

echo
echo "T6b. 무시 규칙이 비밀 파일을 실제로 막는가"
IG="$WORK/ig"; mkdir -p "$IG/scv" && cd "$IG" && git init -q . 2>/dev/null
cat "$REPO_ROOT/template/.gitignore.fragment" > .gitignore
echo '{"SLACK_BOT_TOKEN":"x"}' > scv/scv_settings.secret.json
echo '{"SCV_LANG":"korean"}' > scv/scv_settings.json
if git check-ignore -q scv/scv_settings.secret.json 2>/dev/null; then ok "비밀 파일이 무시된다"; else fail "T6b — 비밀 파일이 무시되지 않는다"; fi
if git check-ignore -q scv/scv_settings.json 2>/dev/null; then fail "T6b — 일반 파일까지 무시된다"; else ok "일반 파일은 커밋 대상"; fi
git add -A 2>/dev/null
if git diff --cached --name-only 2>/dev/null | grep -q 'secret.json'; then
  fail "T6b — 비밀 파일이 스테이징됐다"
else ok "git add -A 후에도 비밀 파일은 안 올라간다"; fi
cd "$REPO_ROOT"
echo "OK [T6b]"

# ============================================================ T14–T17. 파일은 항상 있다 (0.34.0)
echo
echo "T14. 없으면 만든다 — 전체 키 + 기본값 + 설명 + .env 값"
EN="$WORK/ensure"; mkdir -p "$EN/scv" && : > "$EN/scv/PROMOTE.md" && cd "$EN" && git init -q . 2>/dev/null
printf 'DATABASE_URL=postgres://x\nSCV_LANG=korean\nSLACK_BOT_TOKEN=xoxb-abc\n' > .env; cp .env .env.orig
bash "$REPO_ROOT/scripts/settings-ensure.sh" >/dev/null 2>&1
[[ -f scv/scv_settings.json ]] && ok "설정 파일이 생겼다" || fail "T14 — 파일이 안 생겼다"
nkeys="$(python3 -c 'import json;d=json.load(open("scv/scv_settings.json"));print(len([k for k in d if not k.startswith("_")]))' 2>/dev/null || echo 0)"
[[ "$nkeys" -ge 26 ]] && ok "공개 키 전부($nkeys)" || fail "T14 — 키 부족: $nkeys"
grep -qF '"_doc"' scv/scv_settings.json && ok "_doc 설명이 있다" || fail "T14 — _doc 없음"
eq "SCV_LANG 은 .env 값" "korean" "$(settings_get SCV_LANG)"
eq "기본값이 채워진다 (첨부 범위)" "slug" "$(settings_get SCV_ATTACHMENTS_SCOPE)"
eq "기본값이 채워진다 (효과 모드)" "auto" "$(settings_get SCV_EFFORT_MODE)"
eq "자동 감지 키는 빈 값 (알림 채널)" "" "$(settings_lookup_json "$(cat scv/scv_settings.json)" NOTIFIER_PROVIDER)"
grep -q DATABASE_URL scv/scv_settings.json && fail "T14 — SCV 와 무관한 키가 들어갔다" || ok "SCV 가 아는 키만"
diff -q .env .env.orig >/dev/null && ok ".env 는 그대로" || fail "T14 — .env 가 바뀌었다"
before="$(cat scv/scv_settings.json)"; bash "$REPO_ROOT/scripts/settings-ensure.sh" >/dev/null 2>&1
eq "두 번 돌려도 같다" "$before" "$(cat scv/scv_settings.json)"
cd "$REPO_ROOT"; echo "OK [T14]"

echo
echo "T15. 있으면 없는 키만 — 사용자 값 불변, 지운 _doc 은 재추가 안 함"
MG="$WORK/merge"; mkdir -p "$MG/scv" && : > "$MG/scv/PROMOTE.md" && cd "$MG"
echo '{"SCV_LANG":"korean","MY_OWN":"mine","SCV_ATTACHMENTS_SCOPE":"all"}' > scv/scv_settings.json
bash "$REPO_ROOT/scripts/settings-ensure.sh" >/dev/null 2>&1
eq "사용자 값 그대로 (언어)" "korean" "$(settings_get SCV_LANG)"
eq "사용자 값 그대로 (기본값과 달라도)" "all" "$(settings_get SCV_ATTACHMENTS_SCOPE)"
grep -q '"MY_OWN": *"mine"' scv/scv_settings.json && ok "SCV 가 모르는 키도 그대로" || fail "T15 — 사용자 키가 사라졌다"
eq "없던 키가 더해진다" "auto" "$(settings_get SCV_EFFORT_MODE)"
grep -qF '"_doc"' scv/scv_settings.json && fail "T15 — 사용자가 안 둔 _doc 이 병합으로 들어갔다" || ok "설명 키는 병합 때 재추가하지 않는다"
before="$(cat scv/scv_settings.json)"; bash "$REPO_ROOT/scripts/settings-ensure.sh" >/dev/null 2>&1
eq "두 번째는 아무것도 안 바꾼다" "$before" "$(cat scv/scv_settings.json)"
cd "$REPO_ROOT"; echo "OK [T15]"

echo
echo "T16. 비밀 파일 — git 이 무시할 때만"
SG="$WORK/secret-git"; mkdir -p "$SG/scv" && : > "$SG/scv/PROMOTE.md" && cd "$SG" && git init -q . 2>/dev/null
printf 'SLACK_BOT_TOKEN=xoxb-abc\n' > .env
bash "$REPO_ROOT/scripts/settings-ensure.sh" >/dev/null 2>&1
[[ -f scv/scv_settings.secret.json ]] && ok "git 저장소: 비밀 파일 생성" || fail "T16 — 비밀 파일이 안 생겼다"
git check-ignore -q scv/scv_settings.secret.json && ok ".gitignore 에 무시 줄이 더해져 실제로 무시된다" || fail "T16 — 비밀 파일이 무시되지 않는다"
eq "토큰이 비밀 파일로" "xoxb-abc" "$(settings_get SLACK_BOT_TOKEN)"
grep -q SLACK_BOT_TOKEN scv/scv_settings.json && fail "T16 — 토큰이 커밋되는 파일에" || ok "커밋되는 파일에는 비밀 키 없음"
[[ "$(stat -c %a scv/scv_settings.secret.json 2>/dev/null || stat -f %Lp scv/scv_settings.secret.json)" == "600" ]] && ok "비밀 파일 600" || fail "T16 — 비밀 파일 권한"
n_ign="$(grep -cx 'scv/scv_settings.secret.json' .gitignore)"; bash "$REPO_ROOT/scripts/settings-ensure.sh" >/dev/null 2>&1
eq "무시 줄은 한 번만" "$n_ign" "$(grep -cx 'scv/scv_settings.secret.json' .gitignore)"
cd "$REPO_ROOT"
SN="$WORK/secret-nogit"; mkdir -p "$SN/scv" && : > "$SN/scv/PROMOTE.md" && cd "$SN"
err="$(bash "$REPO_ROOT/scripts/settings-ensure.sh" 2>&1 >/dev/null)"
[[ -f scv/scv_settings.json ]] && ok "git 이 아니어도 공개 파일은 생긴다" || fail "T16 — 공개 파일 없음"
[[ ! -f scv/scv_settings.secret.json ]] && ok "git 이 아니면 비밀 파일은 만들지 않는다" || fail "T16 — 무시 보장 없이 비밀 파일을 만들었다"
grep -q "not created" <<<"$err" && ok "이유를 한 줄 알린다" || fail "T16 — 알림 없음: $err"
cd "$REPO_ROOT"; echo "OK [T16]"

echo
echo "T17. 액션 시작(autosync)에서 생기고, 알림은 값이 다를 때만"
AS="$WORK/autosync"; mkdir -p "$AS" && cd "$AS" && git init -q . 2>/dev/null
bash "$REPO_ROOT/scripts/hydrate.sh" init . >/dev/null 2>&1
rm -f scv/scv_settings.json scv/scv_settings.secret.json
printf 'SCV_LANG=korean\n' > .env
bash -c 'source "'"$REPO_ROOT"'/scripts/lib/scvroot.sh"; scv_init_paths >/dev/null 2>&1' 2>/dev/null
[[ -f scv/scv_settings.json ]] && ok "액션 시작(scv_init_paths)에서 파일이 생긴다" || fail "T17 — autosync 경로가 파일을 안 만들었다"
eq ".env 값이 옮겨졌다" "korean" "$(settings_get SCV_LANG)"
warn="$(bash -c 'cd "'"$AS"'"; source "'"$LIB"'"; settings_get SCV_LANG' 2>&1 >/dev/null)"
[[ -z "$warn" ]] && ok "값이 같으면 .env 알림이 없다" || fail "T17 — 옮겨졌는데도 알린다: $warn"
printf 'SCV_LANG=japanese\n' > .env
warn="$(bash -c 'cd "'"$AS"'"; source "'"$LIB"'"; settings_get SCV_LANG' 2>&1 >/dev/null)"
grep -q "differ" <<<"$warn" && ok ".env 를 나중에 바꾸면 한 번 알린다" || fail "T17 — 값이 달라도 조용하다"
eq "그래도 읽는 값은 설정 파일" "korean" "$(settings_get SCV_LANG)"
cd "$REPO_ROOT"; echo "OK [T17]"

# ============================================================ T13. 병합 (업데이트)
echo
echo "T13. 업데이트가 사용자 설정을 바꾸지 않는다"

# 사용자가 정한 값은 절대 안 건드린다. 없는 키만 더한다.
U='{"SCV_TEST":"local","SCV_LANG":"korean","MY_OWN":"mine"}'
D='{"SCV_TEST":"online","SCV_LANG":"","SCV_BRAND_NEW":"new"}'
M="$(settings_merge_defaults "$U" "$D")"
eq "사용자 값이 기본값으로 안 바뀐다" "local"  "$(settings_lookup_json "$M" SCV_TEST)"
eq "빈 기본값이 사용자 값을 안 지운다" "korean" "$(settings_lookup_json "$M" SCV_LANG)"
eq "SCV 가 모르는 사용자 키도 남는다"  "mine"   "$(settings_lookup_json "$M" MY_OWN)"
eq "새 키는 더해진다"                  "new"    "$(settings_lookup_json "$M" SCV_BRAND_NEW)"

# 사용자가 일부러 빈 문자열로 둔 값도 기본값으로 덮이면 안 된다
M2="$(settings_merge_defaults '{"K":""}' '{"K":"default"}')"
eq "일부러 비운 값도 유지된다" "" "$(settings_lookup_json "$M2" K)"

# 두 번 병합해도 같다
eq "두 번 병합해도 같다" "$(settings_lookup_json "$M" SCV_TEST)" \
   "$(settings_lookup_json "$(settings_merge_defaults "$M" "$D")" SCV_TEST)"

# 깨진 입력에서는 사용자 원본을 그대로 낸다 — 병합하다 설정을 잃느니 낫다
eq "깨진 기본값 → 사용자 원본 그대로" "local" \
   "$(settings_lookup_json "$(settings_merge_defaults "$U" '{broken')" SCV_TEST)"
eq "기본값 없음 → 사용자 원본 그대로" "local" \
   "$(settings_lookup_json "$(settings_merge_defaults "$U" '')" SCV_TEST)"

# 병합도 순수해야 한다 — 디스크를 만지지 않는다
body="$(extract_fn settings_merge_defaults)"
DISK2='(^|[;&|(][[:space:]]*|^[[:space:]]*)(date|curl|wget|git|mktemp|touch|rm|mv|cp|mkdir|source)([[:space:]]|$)|\$RANDOM'
hits="$(printf '%s\n' "$body" | strip_benign | grep -nE "$DISK2" || true)"
if [[ -n "$hits" ]]; then
  fail "T13 — settings_merge_defaults 가 디스크/시각을 만짐:"; printf '%s\n' "$hits" | sed 's/^/      /'
else
  ok "settings_merge_defaults — 디스크·시각·무작위 없음"
fi
echo "OK [T13]"

# ============================================================ 요약
echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
