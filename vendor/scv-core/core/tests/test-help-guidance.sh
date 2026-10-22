#!/usr/bin/env bash
# test-help-guidance.sh — 새 사용자가 보는 안내가 자동 라우팅에 맞는지 잠근다 (0.69.1).
#
# 매 턴 훅이 일반 대화를 help 로 보내 주므로(SCV_ALWAYS_ON, 기본 켬) 입구는 "그냥 말하기"다.
# 그런데 진단은 알림 토큰이 없다는 이유로 "설정 예시를 설정 파일 위에 복사하라"를 첫 할 일로
# 내놓았고(복사하면 언어 설정이 지워진다), 설치 · 문서는 help "…" 를 직접 치라고만 했다.
# 새 폴더에 설치한 세션이 바로 그 안내에 막혔다. 이 파일은 그 길을 다시 막지 않게 한다.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/help.sh" && -f "$up/$sub/protocols/promote.md" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-help-guidance: payload not found from $HERE" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-help-guidance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
HELP_CMD='[a-z/$]*:help'   # /scv:help 와, 래퍼가 바꿔 쓴 호스트 명령 모두

# 새 폴더에 설치하고 설정 파일을 주어진 내용으로 둔다(빈 값이면 설정 파일 없음).
new_proj() {
  local d="$WORK/$1"; mkdir -p "$d"
  (cd "$d" && bash "$CORE/scripts/hydrate.sh" init . >"$d/.hydrate.out" 2>&1)
  rm -f "$d/scv/scv_settings.json"
  [[ -n "$2" ]] && printf '%s\n' "$2" >"$d/scv/scv_settings.json"
  echo "$d"
}
# 진단의 "추천 다음 행동" 블록만 잘라낸다.
next_block() { (cd "$1" && bash "$CORE/scripts/help.sh" 2>&1) | awk '/Recommended next action/{f=1} f&&/Learn more/{exit} f'; }

echo "── [T1] 알림 미설정(언어만)이어도 설정 단계에서 멈추지 않는다 ──"
P1="$(new_proj t1 '{"SCV_LANG": "ko"}')"
OUT1="$(next_block "$P1")"
grep -q 'Configure settings' <<<"$OUT1" && fail "알림이 없다고 설정이 첫 할 일이 됐다" || ok "설정이 첫 할 일이 아니다"
grep -q 'cp scv/scv_settings.example.json scv/scv_settings.json' <<<"$OUT1" \
  && fail "설정 파일을 덮어쓰는 복사를 안내한다" || ok "덮어쓰는 복사 안내가 없다"
[[ "$(grep -ci 'notif' <<<"$OUT1")" -ge 1 ]] && grep -qi 'optional' <<<"$OUT1" \
  && ok "알림은 선택 줄로 남는다" || fail "알림 선택 줄이 없다: $OUT1"

echo "── [T2] 설정 파일이 없어도 설정 단계에서 멈추지 않는다 ──"
P2="$(new_proj t2 '')"
OUT2="$(next_block "$P2")"
grep -q 'Configure settings' <<<"$OUT2" && fail "설정 파일이 없다고 멈췄다" || ok "설정 단계에서 멈추지 않는다"
grep -q 'Ready — no immediate action' <<<"$OUT2" && ok "준비됨 추천" || fail "준비됨 추천이 아니다: $OUT2"

echo "── [T3] 준비됨 안내의 첫 입구는 그냥 말하기 ──"
grep -q 'Ready — no immediate action' <<<"$OUT1" && ok "준비됨 문구 유지" || fail "준비됨 문구가 없다"
first="$(grep -m1 -E '^  - ' <<<"$OUT1")"
grep -qi 'just say' <<<"$first" && ok "첫 항목이 그냥 말하기: ${first# }" || fail "첫 항목이 그냥 말하기가 아니다: $first"

echo "── [T4] 자동 라우팅을 끄면 명령 입력을 안내한다 ──"
P4="$(new_proj t4 '{"SCV_LANG": "ko", "SCV_ALWAYS_ON": "off"}')"
OUT4="$(next_block "$P4")"
grep -qE "$HELP_CMD \"" <<<"$OUT4" && ok "help \"…\" 명령 안내" || fail "명령 안내가 없다: $OUT4"
grep -qi 'just say' <<<"$OUT4" && fail "꺼졌는데 그냥 말하라고 한다" || ok "그냥 말하기 안내 없음"

echo "── [T5] 설치 마지막 안내 ──"
H="$(cat "$P1/.hydrate.out")"
grep -qi 'just say' <<<"$H" && ok "그냥 말하면 된다" || fail "설치 안내에 그냥 말하기가 없다"
grep -q 'your the host' <<<"$H" && fail "오타가 남아 있다" || ok "오타 없음"

echo "── [T6] 문서 · 메시지가 그냥 말하기를 기본 입구로 적는다 ──"
TPL="$CORE/template/scv"
check_doc() { # $1 이름  $2 본문
  grep -qiE 'just (say|describe)|그냥 (말|적)' <<<"$2" && ok "$1" || fail "$1 — 그냥 말하기가 없다"
}
check_doc "계획 규약 §1.4" "$(awk '/^## 1\.4\./{f=1;next} f&&/^## /{exit} f' "$TPL/PROMOTE.md")"
check_doc "raw 안내" "$(awk '/원자료가 아직 없다면/{f=1} f&&/계획 폴더를 손으로/{exit} f' "$TPL/raw/README.md")"
check_doc "promote 의 다듬을 것 없음 메시지" "$(grep 'Nothing to refine' "$CORE/protocols/promote.md")"
check_doc "대화 멈춤 안내" "$(grep -i 'pause for now' "$CORE/protocols/help/promote-handoff.md")"
check_doc "help 규약 Mode B" "$(awk '/^## Mode B —/{f=1;next} f&&/^## /{exit} f' "$CORE/protocols/help/full.md")"
check_doc "못 끝낸 대화 이어가기 안내" "$(grep 'unfinished conversation(s)' "$CORE/protocols/help/hydrate.md")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
