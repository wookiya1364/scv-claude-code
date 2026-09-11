#!/usr/bin/env bash
# test-session-resume.sh — 비운 뒤에도 이어진다 (v0.47.0+).
#
# 대화를 지우거나 컨텍스트가 압축되거나 세션을 재개한 직후, 세션 시작 훅 템플릿이
# 진행 중 계획·최근 결정·활성 대화를 다시 실어 보내는가. 세 축을 본다: 켜진 프로젝트에서
# 실제로 싣는가 / 꺼졌거나 SCV 가 없는 프로젝트에서 아무 것도 내지 않고 막지도 않는가 /
# 래퍼가 압축·비움·재개에만 등록했는가. 코어에서 볼 수 있는 것은 항상 검사하고, 래퍼
# 파일은 옆에 체크아웃이 있을 때만 — 없으면 SKIP 이지 실패가 아니다.
#
# Covers TESTS.md T1–T15 of 20260911-wookiya1364-session-resume-recap (T16 은 실기기).
#
# Run: bash core/tests/test-session-resume.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-session-resume: payload not found from $HERE" >&2; exit 1; }

HOOK="$CORE/template/hooks/on-session-start.sh"
LIB="$CORE/scripts/lib/resume-recap.sh"
SETTINGS_LIB="$CORE/scripts/lib/settings.sh"
EXAMPLE="$CORE/template/scv/scv_settings.example.json"
MARK="[SCV resume]"

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  – SKIP: $1"; SKIP=$((SKIP + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# 하이드레이트된 임시 프로젝트 하나를 만들고 경로를 돌려준다.
mkproj() {  # <이름>
  local p="$WORK/$1"
  mkdir -p "$p"
  ( cd "$p" && git init -q . && git config user.name tester && git config user.email t@example.com \
    && bash "$CORE/scripts/hydrate.sh" init . >/dev/null 2>&1 )
  printf '%s' "$p"
}
plan() {  # <프로젝트> <slug> <title>
  mkdir -p "$1/scv/promote/$2"
  printf -- '---\ntitle: "%s"\nslug: %s\nstatus: planned\n---\n# %s\n' "$3" "$2" "$3" > "$1/scv/promote/$2/PLAN.md"
}
conv() {  # <프로젝트> <파일명> <status> <본문> [<mtime YYYYMMDDhhmm>] — touch -t 는 GNU·BSD 둘 다 같다
  mkdir -p "$1/scv/conversations"
  printf -- '---\nslug: %s\nstatus: %s\n---\n%s\n' "${2%.md}" "$3" "$4" > "$1/scv/conversations/$2"
  [[ -n "${5:-}" ]] && touch -t "$5" "$1/scv/conversations/$2" 2>/dev/null
  return 0
}
run_hook() {  # <프로젝트> [<stdin>] — stdout 은 OUT 에, 종료 코드는 RC 에 (서브셸이 아니라 전역)
  local p="$1" in="${2:-{\"source\":\"compact\"\}}"
  OUT="$( cd "$p" && printf "%s" "$in" | CLAUDE_PLUGIN_ROOT="$CORE" bash "$HOOK" 2>"$WORK/err" )"; RC=$?
  return 0
}

echo "test-session-resume: $CORE"

# ---------- T1 스위치 off → 빈 출력, exit 0 ----------
P="$(mkproj t1)"; plan "$P" 20260911-x-demo "데모 계획"
printf '{"SCV_RESUME_RECAP": "off"}\n' > "$P/scv/scv_settings.json"
run_hook "$P"; O="$OUT"
[[ -z "$O" && "$RC" == "0" ]] && ok "T1 off → 빈 출력, exit 0" || fail "T1 off 인데 출력 ${#O}바이트 / rc=$RC"
printf '{"SCV_RESUME_RECAP": "OFF"}\n' > "$P/scv/scv_settings.json"
run_hook "$P"; O="$OUT"
[[ -z "$O" ]] && ok "T1 OFF (대문자) 도 끈다" || fail "T1 OFF 대문자가 안 꺼진다"

# ---------- T2 미하이드레이트 → 빈 출력, exit 0 ----------
mkdir -p "$WORK/t2"
run_hook "$WORK/t2"; O="$OUT"
[[ -z "$O" && "$RC" == "0" ]] && ok "T2 scv/ 없음 → 빈 출력, exit 0" || fail "T2 미하이드레이트인데 출력/rc=$RC"

# ---------- T3 진행 중 계획이 실린다 ----------
P="$(mkproj t3)"; plan "$P" 20260911-x-demo "데모 계획"
run_hook "$P" '{"source":"clear"}'; O="$OUT"
[[ "$O" == *"$MARK"* && "$O" == *"20260911-x-demo"* && "$O" == *"데모 계획"* && "$RC" == "0" ]] \
  && ok "T3 표식 + 계획 slug + 제목이 실린다" || fail "T3 계획이 안 실린다 (rc=$RC)"
[[ ! -f "$P/scv/scv_settings.json" ]] || grep -q RESUME "$P/scv/scv_settings.json" || true
run_hook "$P" '{"source":"clear"}'; O2="$OUT"
[[ -n "$O2" ]] && ok "T3 스위치 키가 없어도(기본) 켜져 있다" || fail "T3 기본값이 off 로 동작"

# ---------- T4 최근 결정 5건 ----------
P="$(mkproj t4)"; plan "$P" 20260911-x-demo "데모 계획"
for i in 1 2 3 4 5 6; do
  ( cd "$P" && bash "$CORE/scripts/decisions-append.sh" --title "결정 번호 $i 제목" --verdict adopted --why "이유 $i" >/dev/null 2>&1 )
done
run_hook "$P"; O="$OUT"
miss=0; for i in 2 3 4 5 6; do [[ "$O" == *"결정 번호 $i 제목"* ]] || miss=$((miss+1)); done
[[ $miss -eq 0 ]] && ok "T4 최근 결정 5건(2~6)이 실린다" || fail "T4 최근 결정 ${miss}건 누락"
[[ "$O" != *"결정 번호 1 제목"* ]] && ok "T4 여섯 번째로 오래된 결정(1)은 없다" || fail "T4 오래된 결정까지 실린다"

# ---------- T5 활성 대화 — 전문, 가장 최근 것만 ----------
P="$(mkproj t5)"; plan "$P" 20260911-x-demo "데모 계획"
conv "$P" 20260911-000001-a.md promoted "CONV-A-BODY" "202001010000"
conv "$P" 20260911-000002-b.md active   "CONV-B-BODY" "202101010000"
conv "$P" 20260911-000003-c.md active   $'## Turn 1\nCONV-C-BODY\n\n## Turn 2\nCONV-C-LAST-TURN' "202201010000"
run_hook "$P"; O="$OUT"
[[ "$O" == *"20260911-000003-c.md"* && "$O" == *"CONV-C-BODY"* && "$O" == *"CONV-C-LAST-TURN"* ]] \
  && ok "T5 최신 활성 대화(c)의 경로와 전문(모든 턴)이 실린다" || fail "T5 최신 활성 대화 전문이 안 실린다"
nb="$(printf '%s' "$O" | grep -c "20260911-000002-b.md" || true)"
[[ "$nb" == "1" && "$O" != *"CONV-B-BODY"* ]] && ok "T5 다른 활성 대화(b)는 경로 1회, 본문 없음" || fail "T5 b: 경로 ${nb}회 / 본문 포함 여부 어긋남"
[[ "$O" != *"20260911-000001-a.md"* && "$O" != *"CONV-A-BODY"* ]] && ok "T5 promoted 대화(a)는 없다" || fail "T5 promoted 대화가 실린다"
mkdir -p "$P/scv/conversations/archive"; conv "$P" archive/20260911-000000-z.md active "CONV-Z-BODY"
run_hook "$P"; O="$OUT"
[[ "$O" != *"CONV-Z-BODY"* ]] && ok "T5 archive/ 아래는 보지 않는다" || fail "T5 archive/ 대화가 실린다"

# ---------- T5b 적대 검증에서 나온 경계 — 링크·특수 파일명·관대한 status·동률·폴더 고정 ----------
P="$(mkproj t5b)"; plan "$P" 20260911-x-demo "데모 계획"; mkdir -p "$P/scv/conversations"
printf -- '---\nstatus: active\n---\nOUTSIDE-SECRET-FILE\n' > "$WORK/outside.md"
ln -s "$WORK/outside.md" "$P/scv/conversations/20260911-000001-link.md"
run_hook "$P"; O="$OUT"
[[ "$O" != *"OUTSIDE-SECRET-FILE"* && "$O" != *"000001-link"* ]] && ok "T5b 심볼릭 링크 대화는 따라가지 않는다" || fail "T5b 링크 대상이 실린다"
rm -f "$P/scv/conversations/20260911-000001-link.md"
printf -- '---\nstatus: active\n---\nTAB-NAME-BODY\n' > "$P/scv/conversations/x"$'\t'"active"$'\t'"5.md"
printf 'ROOT-README' > "$P/README.md"
printf -- '---\nstatus: active\n---\nNL-NAME-BODY\n' > "$P/scv/conversations/x"$'\n'"README.md"
run_hook "$P"; O="$OUT"
[[ "$O" != *"TAB-NAME-BODY"* && "$O" != *"NL-NAME-BODY"* && "$O" != *"ROOT-README"* && "$RC" == "0" ]] \
  && ok "T5b 탭·개행이 든 파일명은 건너뛰고 엉뚱한 파일을 싣지 않는다" || fail "T5b 특수 파일명이 목록을 깨뜨린다"
rm -f "$P/scv/conversations/x"$'\t'"active"$'\t'"5.md" "$P/scv/conversations/x"$'\n'"README.md" "$P/README.md"
printf -- '\xef\xbb\xbf---\r\nslug: crlf\r\nstatus: "Active"  # note\r\n---\r\nCRLF-BODY\r\n' > "$P/scv/conversations/20260911-000002-crlf.md"
run_hook "$P"; O="$OUT"
[[ "$O" == *"CRLF-BODY"* ]] && ok "T5b BOM·CRLF·따옴표·대문자·주석이 붙은 status 도 active 로 본다" || fail "T5b 관대한 status 인식 실패"
rm -f "$P/scv/conversations/20260911-000002-crlf.md"
printf -- '---\nslug: nofm\n' > "$P/scv/conversations/20260911-000003-open.md"
for i in $(seq 1 70); do echo "line $i" >> "$P/scv/conversations/20260911-000003-open.md"; done
echo "status: active" >> "$P/scv/conversations/20260911-000003-open.md"; echo "DEEP-BODY" >> "$P/scv/conversations/20260911-000003-open.md"
run_hook "$P"; O="$OUT"
[[ "$O" != *"DEEP-BODY"* ]] && ok "T5b 닫히지 않은 frontmatter 의 본문 깊은 status 는 무시" || fail "T5b 본문 status 를 frontmatter 로 오인"
rm -f "$P/scv/conversations/20260911-000003-open.md"
{ printf -- '---\n'; for i in $(seq 1 28); do echo "k$i: v"; done; echo 'status: active'; for i in $(seq 1 70); do echo "LONG-OPEN-BODY $i"; done; } > "$P/scv/conversations/20260911-000003-longopen.md"
run_hook "$P"; O="$OUT"
[[ "$O" != *"LONG-OPEN-BODY"* && "$O" != *"000003-longopen"* ]] && ok "T5b 60줄 넘게 닫히지 않은 frontmatter 도 active 로 보지 않는다" || fail "T5b 미완 frontmatter 60줄 초과가 active 로 잡힌다"
rm -f "$P/scv/conversations/20260911-000003-longopen.md"
mkdir -p "$P/bin"; printf '#!/bin/bash\n/usr/bin/stat "$@"; exit 1\n' > "$P/bin/stat"; chmod +x "$P/bin/stat"
conv "$P" 20260911-000003-old.md active "STAT-OLD-BODY" "202001010000"
conv "$P" 20260911-000003-new.md active "STAT-NEW-BODY"
O="$( cd "$P" && printf '{}' | PATH="$P/bin:$PATH" CLAUDE_PLUGIN_ROOT="$CORE" bash "$HOOK" 2>/dev/null )"
nold="$(printf '%s' "$O" | grep -c "20260911-000003-old.md" || true)"
[[ "$O" == *"STAT-NEW-BODY"* && "$nold" == "1" ]] && ok "T5b stat 이 출력 뒤 실패해도 폴백이 겹치지 않는다 (경로 1회)" || fail "T5b stat 폴백 중복: old 경로 ${nold}회"
rm -rf "$P/bin" "$P/scv/conversations/20260911-000003-old.md" "$P/scv/conversations/20260911-000003-new.md"
conv "$P" 20260911-000004-a.md active "TIE-A-BODY" "202206010000"
conv "$P" 20260911-000005-b.md active "TIE-B-BODY" "202206010000"
run_hook "$P"; O="$OUT"
[[ "$O" == *"TIE-B-BODY"* && "$O" != *"TIE-A-BODY"* ]] && ok "T5b mtime 동률이면 이름이 뒤인(최신) 대화" || fail "T5b 동률 처리가 오래된 쪽을 고른다"
mkdir -p "$P/other/promote/20260911-y-other" "$P/other/conversations"
printf -- '---\ntitle: "다른 폴더 계획"\nslug: 20260911-y-other\nstatus: planned\n---\n' > "$P/other/promote/20260911-y-other/PLAN.md"
printf '{"SCV_RESUME_RECAP": "off"}\n' > "$P/other/scv_settings.json"
O="$( cd "$P" && printf '{}' | SCV_DIR=other CLAUDE_PLUGIN_ROOT="$CORE" bash "$HOOK" 2>/dev/null )"
[[ "$O" == *"20260911-x-demo"* && "$O" != *"20260911-y-other"* && "$O" == *"TIE-B-BODY"* ]] \
  && ok "T5b SCV_DIR 환경변수가 있어도 scv/ 로 고정 (스위치·recap·대화가 같은 폴더)" || fail "T5b SCV_DIR 에 따라 폴더가 어긋난다"

# ---------- T6 대화 디렉터리 없음 ----------
P="$(mkproj t6)"; plan "$P" 20260911-x-demo "데모 계획"; rm -rf "$P/scv/conversations"
run_hook "$P"; O="$OUT"
[[ "$O" == *"20260911-x-demo"* && "$RC" == "0" && ! -s "$WORK/err" ]] && ok "T6 conversations/ 없어도 recap 실리고 stderr 비어 있다" || fail "T6 rc=$RC stderr=$(cat "$WORK/err" 2>/dev/null | head -1)"

# ---------- T7 머리말이 비워진 이유를 말한다 ----------
P="$(mkproj t7)"; plan "$P" 20260911-x-demo "데모 계획"
for s in compact clear resume; do
  run_hook "$P" "{\"source\":\"$s\"}"; O="$OUT"
  [[ "$O" == *"(source: $s)"* ]] && ok "T7 머리말에 source=$s" || fail "T7 머리말에 $s 가 없다"
done
run_hook "$P" '{"session_id":"x"}'; O="$OUT"
[[ "$O" == *"$MARK"* && "$O" != *"(source:"* && "$RC" == "0" ]] && ok "T7 source 없으면 일반 머리말" || fail "T7 source 없을 때 rc=$RC"

# ---------- T8 잘못된 stdin ----------
run_hook "$P" 'not json'; O="$OUT"
[[ "$O" == *"20260911-x-demo"* && "$RC" == "0" ]] && ok "T8 JSON 아닌 stdin 도 막지 않는다" || fail "T8 rc=$RC"
O="$( cd "$P" && CLAUDE_PLUGIN_ROOT="$CORE" bash "$HOOK" </dev/null 2>/dev/null )"; RC=$?
[[ "$O" == *"20260911-x-demo"* && "$RC" == "0" ]] && ok "T8 빈 stdin 도 막지 않는다" || fail "T8 빈 stdin rc=$RC"

# ---------- T9 가림 필터 ----------
P="$(mkproj t9)"; plan "$P" 20260911-x-demo "데모 계획"
conv "$P" 20260911-000009-s.md active "line token=abc123secret end"
run_hook "$P"; O="$OUT"
[[ "$O" != *"abc123secret"* && "$O" == *"[REDACTED]"* ]] && ok "T9 대화 본문의 비밀값이 가려진다" || fail "T9 비밀값이 그대로 나간다"

# ---------- T10 아무 것도 쓰지 않는다 ----------
P="$(mkproj t10)"; plan "$P" 20260911-x-demo "데모 계획"; conv "$P" 20260911-000010-c.md active "BODY"
before="$( cd "$P" && find scv -type f | LC_ALL=C sort | xargs cksum )"
run_hook "$P" >/dev/null; run_hook "$P" >/dev/null
after="$( cd "$P" && find scv -type f | LC_ALL=C sort | xargs cksum )"
[[ "$before" == "$after" ]] && ok "T10 두 번 돌려도 scv/ 아래 파일이 그대로다" || fail "T10 훅이 무언가 썼다"

# ---------- T11 순수부 · 호스트 중립 ----------
if bash "$CORE/scripts/check-purity.sh" "$LIB" >/dev/null 2>&1; then ok "T11 순수부 @pure 통과"; else fail "T11 순수부가 순수성 검사에 걸린다"; fi
n="$(grep -c '^# @pure$' "$LIB" || true)"
[[ "$n" -ge 3 ]] && ok "T11 @pure 함수 ${n}개" || fail "T11 @pure 표기가 ${n}개뿐"
# 호스트 중립 — 이벤트 이름·matcher 값은 래퍼 소유다. 코어 저장소에서는 저장소 검사가
# 상한이고, 벤더링된 페이로드에서는 이벤트 이름 두 개만 직접 본다 (호스트 이름은 그 검사가 본다).
if [[ -f "$CORE/../tests/test-host-neutral.sh" ]]; then
  bash "$CORE/../tests/test-host-neutral.sh" >/dev/null 2>&1 && ok "T11 호스트 중립 검사 통과" || fail "T11 호스트 중립 검사 실패"
elif grep -qE 'SessionStart|PreCompact|compact\|clear' "$LIB" "$HOOK" 2>/dev/null; then
  fail "T11 순수부·템플릿에 호스트 이벤트 이름이 있다"
else
  ok "T11 순수부·템플릿 본문에 호스트 이벤트 이름 없음"
fi

# ---------- T12 래퍼 등록 (옆 체크아웃 있을 때) ----------
SIB="$(cd "$CORE/../.." 2>/dev/null && pwd)"
CC="$SIB/scv-claude-code"
if [[ -f "$CC/hooks/hooks.json" ]]; then
  python3 - "$CC/hooks/hooks.json" <<'PY' && ok "T12 래퍼: 세션 시작 항목 1개, matcher 는 압축·비움·재개만, 템플릿·CLAUDE_PLUGIN_ROOT 지정, 기존 항목 그대로" || fail "T12 래퍼 등록이 계획과 다르다"
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
ss = h.get("SessionStart", [])
assert len(ss) == 1, f"SessionStart entries: {len(ss)}"
m = set(ss[0].get("matcher", "").split("|"))
assert m == {"compact", "clear", "resume"}, f"matcher: {m}"
cmd = ss[0]["hooks"][0]["command"]
assert "on-session-start.sh" in cmd and "CLAUDE_PLUGIN_ROOT=" in cmd, cmd
for ev, n in (("UserPromptSubmit", 1), ("Stop", 1), ("PreToolUse", 3), ("UserPromptExpansion", 1)):
    assert len(h.get(ev, [])) == n, f"{ev}: {len(h.get(ev, []))}"
PY
  grep -q "on-session-start" "$CC/adapter/README.md" 2>/dev/null && ok "T12 래퍼 adapter/README.md 가 새 훅을 적는다" || fail "T12 adapter/README.md 에 언급 없음"
else
  skip "T12 래퍼 체크아웃 없음 ($CC)"
fi

# ---------- T13 템플릿 지문 ----------
if [[ -f "$CORE/TEMPLATE_DIGEST" ]]; then
  bash "$CORE/scripts/compute-template-digest.sh" --check "$CORE/TEMPLATE_DIGEST" >/dev/null 2>&1 && ok "T13 TEMPLATE_DIGEST 일치" || fail "T13 TEMPLATE_DIGEST 불일치 — 재계산 필요"
else
  skip "T13 TEMPLATE_DIGEST 없음"
fi

# ---------- T14 설정 등록부 ----------
grep -q 'SCV_RESUME_RECAP' "$SETTINGS_LIB" && ok "T14 SCV_PLAIN_KEYS 에 키가 있다" || fail "T14 등록부에 키 없음"
python3 - "$EXAMPLE" <<'PY' && ok "T14 예시 JSON: _doc + 기본값 on" || fail "T14 예시 JSON 에 키/문서/기본값이 어긋남"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("SCV_RESUME_RECAP") == "on", d.get("SCV_RESUME_RECAP")
assert "SCV_RESUME_RECAP" in d["_doc"] and "off" in d["_doc"]["SCV_RESUME_RECAP"]
PY
P="$(mkproj t14)"
printf '{\n  "PROJECT_NAME": "keep me $x",\n  "SCV_LANG": "korean"\n}\n' > "$P/scv/scv_settings.json"
( cd "$P" && bash "$CORE/scripts/settings-ensure.sh" >/dev/null 2>&1 )
grep -q '"SCV_RESUME_RECAP": "on"' "$P/scv/scv_settings.json" && grep -q 'keep me \$x' "$P/scv/scv_settings.json" && grep -q '"SCV_LANG": "korean"' "$P/scv/scv_settings.json" \
  && ok "T14 settings-ensure 가 키를 더하고 기존 값은 보존" || fail "T14 settings-ensure 뒤 값이 어긋남"

# ---------- T15 문서 ----------
DOC="$CORE/../docs/wrapper-integration.md"
if [[ -f "$DOC" ]]; then
  grep -q 'on-session-start.sh' "$DOC" && grep -qi 'not.*for a fresh session start\|fresh session start' "$DOC" \
    && ok "T15 wrapper-integration.md §6 에 셋째 템플릿과 startup 제외" || fail "T15 문서 언급 부족"
else
  skip "T15 docs/ 없음 (벤더링된 페이로드)"
fi

echo
echo "test-session-resume: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[[ $FAIL -eq 0 ]]
