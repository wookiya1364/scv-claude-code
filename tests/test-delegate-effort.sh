#!/usr/bin/env bash
# test-delegate-effort.sh — 깊은 질문은 배경 조사로, 세션 effort 는 그대로 (v0.46.0+).
#
# 세션의 노력 단계(effort)는 사용자 것이다 — 0.45.0 이 세션 모델에서 내린 것과 같은
# 원칙. SCV 가 할 수 있는 것은 스위치(기본 off)를 켠 프로젝트에서 깊은 질문을 배경
# 조사 에이전트에 넘기라는 지시를 매 턴 싣는 것뿐이다. 이 검사는 세 축을 본다:
# off 면 아무 것도 안 달라지는가, on 이면 블록이 실리는가, 래퍼가 에이전트를 싣는가.
# 코어에서 볼 수 있는 것은 항상 검사하고, 래퍼 파일은 옆에 체크아웃이 있을 때만 —
# 없으면 SKIP 이지 실패가 아니다.
#
# Covers TESTS.md T1–T11 of 20260904-wookiya1364-effort-auto-level (T12 는 실기기).
#
# Run: bash core/tests/test-delegate-effort.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-delegate-effort: payload not found from $HERE" >&2; exit 1; }

HOOK="$CORE/template/hooks/on-user-prompt.sh"
FORCE_LIB="$CORE/scripts/lib/force-help.sh"
SETTINGS_LIB="$CORE/scripts/lib/settings.sh"
EXAMPLE="$CORE/template/scv/scv_settings.example.json"
HELP_PROTO="$CORE/protocols/help.md"
MARK="[SCV delegate]"

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  – SKIP: $1"; SKIP=$((SKIP + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

P=""
new_proj() {  # <이름> [설정 JSON]
  P="$WORK/$1"; mkdir -p "$P/scv/raw"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$P/scv/scv_settings.json"
  return 0
}
run_hook() {  # <프로젝트> → 훅 stdout
  ( cd "$1" && printf '{"prompt":"안녕","session_id":"s"}' \
    | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/state" bash "$HOOK" 2>/dev/null )
}
has_mark() { grep -qF "$MARK" <<<"${1:-}"; }

echo "── [T1] 코어 설정 등록부에 스위치 키가 있다 ──"
# shellcheck source=/dev/null
source "$SETTINGS_LIB"
grep -qE '(^|[[:space:]])SCV_DELEGATE_EFFORT([[:space:]]|$|")' <<<"$SCV_PLAIN_KEYS" \
  && ok "공개 키 목록에 SCV_DELEGATE_EFFORT" || fail "공개 키 목록에 없음"
grep -q "SCV_DELEGATE_EFFORT" <<<"$SCV_SECRET_KEYS" && fail "비밀 키 목록에 들어갔다" || ok "비밀 키가 아니다"
python3 - "$EXAMPLE" <<'PY' && ok "예시 기본값 off + 설명 있음" || fail "예시 파일에 키·기본값·설명 중 빠진 것이 있다"
import json,sys
d=json.load(open(sys.argv[1]))
assert d.get("SCV_DELEGATE_EFFORT")=="off", d.get("SCV_DELEGATE_EFFORT")
doc=d.get("_doc",{}).get("SCV_DELEGATE_EFFORT","")
assert doc.strip() and "off" in doc and "on" in doc, doc
PY

echo "── [T2] 하이드레이트한 새 프로젝트의 설정 파일에 키가 생긴다 ──"
HP="$WORK/hydrated"; mkdir -p "$HP"
( cd "$HP" && git init -q . && git config user.email t@e && git config user.name t \
  && bash "$CORE/scripts/hydrate.sh" init . >/dev/null 2>&1 )
if [[ -f "$HP/scv/scv_settings.json" ]]; then
  python3 - "$HP/scv/scv_settings.json" <<'PY' && ok "새 프로젝트 설정에 SCV_DELEGATE_EFFORT=off" || fail "새 프로젝트 설정에 키가 없거나 값이 다르다"
import json,sys; d=json.load(open(sys.argv[1])); assert d.get("SCV_DELEGATE_EFFORT")=="off", d.get("SCV_DELEGATE_EFFORT")
PY
else
  fail "하이드레이트가 설정 파일을 만들지 않았다"
fi

echo "── [T3] off 면 훅 출력이 지금과 같다 ──"
# 같은 프로젝트 폴더에서 설정만 바꿔 가며 비교한다 — 진단에 폴더 경로가 찍히므로
# 폴더가 다르면 바이트 비교가 성립하지 않는다. 기준은 스위치 키가 없는 설정 파일.
new_proj t3 '{}'; BASE="$(run_hook "$P")"
has_mark "$BASE" && fail "스위치 없음인데 위임 블록이 있다" || ok "스위치 없음 → 위임 블록 없음"
for v in off OFF maybe "" "on!"; do
  printf '{"SCV_DELEGATE_EFFORT": "%s"}\n' "$v" > "$P/scv/scv_settings.json"
  OUT="$(run_hook "$P")"
  if has_mark "$OUT"; then fail "'$v' 인데 위임 블록이 있다"
  elif [[ "$OUT" == "$BASE" ]]; then ok "'$v' → 출력이 스위치 없음과 바이트 동일"
  else fail "'$v' → 위임 블록은 없지만 출력이 달라졌다"; fi
done
( source "$FORCE_LIB"; [[ "$(scv_delegate_switch '')" == "off" && "$(scv_delegate_switch 'maybe')" == "off" \
  && "$(scv_delegate_switch 'off')" == "off" && "$(scv_delegate_switch 'ON!')" == "off" ]] ) \
  && ok "정규화: 빈값·maybe·off·ON! → off" || fail "정규화가 on 이 아닌 값을 켰다"

echo "── [T4] on 이면 블록이 실린다 ──"
# 정규화는 기존 스위치와 같다 — 공백과 따옴표를 벗기고 대소문자를 가리지 않는다.
for v in on ON " on "; do
  printf '{"SCV_DELEGATE_EFFORT": "%s"}\n' "$v" > "$P/scv/scv_settings.json"
  OUT="$(run_hook "$P")"
  has_mark "$OUT" && ok "'$v' → 위임 블록 있음" || fail "'$v' 인데 위임 블록이 없다"
done
( source "$FORCE_LIB"; [[ "$(scv_delegate_switch '"on"')" == "on" && "$(scv_delegate_switch "' On '")" == "on" ]] ) \
  && ok "정규화: 따옴표·공백·대소문자만 다른 on → on" || fail "정규화가 따옴표 붙은 on 을 껐다"
printf '{"SCV_DELEGATE_EFFORT": "on"}\n' > "$P/scv/scv_settings.json"; OUT="$(run_hook "$P")"
[[ "$(grep -cF "$MARK" <<<"$OUT")" == "1" ]] && ok "표식이 정확히 한 번" || fail "표식이 $(grep -cF "$MARK" <<<"$OUT")번"
for phrase in "세션 그대로" "배경" "scv-investigator" "scv/raw/" "대화 파일" "SCV_DELEGATE_EFFORT=off"; do
  grep -qF "$phrase" <<<"$OUT" && ok "본문에 '$phrase'" || fail "본문에 '$phrase' 없음"
done
BLOCK_LINES="$( ( source "$FORCE_LIB"; scv_delegate_block ) | grep -c . )"
[[ "$BLOCK_LINES" -le 12 ]] && ok "블록 ${BLOCK_LINES}행 (≤ 12)" || fail "블록이 ${BLOCK_LINES}행 — 12줄을 넘는다"
TOTAL="$(grep -c . <<<"$OUT")"
[[ "$TOTAL" -le 80 ]] && ok "훅 전체 ${TOTAL}행 (≤ 80)" || fail "훅 전체 ${TOTAL}행 — 80줄 상한 초과"

echo "── [T5] 새 블록이 기존 블록과 스위치를 건드리지 않는다 ──"
new_proj t5a '{"SCV_DELEGATE_EFFORT": "on", "SCV_PLAIN_LANGUAGE": "off"}'; OUT="$(run_hook "$P")"
has_mark "$OUT" && ok "쉬운 말 off 여도 위임 블록 있음" || fail "쉬운 말 off 가 위임 블록을 껐다"
grep -qF "[SCV plain language]" <<<"$OUT" && fail "쉬운 말 off 인데 그 블록이 있다" || ok "쉬운 말 블록은 꺼진 그대로"
new_proj t5b '{"SCV_DELEGATE_EFFORT": "on", "SCV_ALWAYS_ON": "off"}'; OUT="$(run_hook "$P")"
has_mark "$OUT" && ok "항상-켬 off 여도 위임 블록 있음" || fail "항상-켬 off 가 위임 블록을 껐다"
grep -q "SCV: 이 턴의 첫 행동" <<<"$OUT" && fail "항상-켬 off 인데 지시가 있다" || ok "라우팅 지시는 꺼진 그대로"
new_proj t5c '{"SCV_DELEGATE_EFFORT": "on", "SCV_FORCE_HELP": "off"}'; OUT="$(run_hook "$P")"
has_mark "$OUT" && ok "preflight off 여도 위임 블록 있음" || fail "preflight off 가 위임 블록을 껐다"
grep -q "Current project diagnosis" <<<"$OUT" && fail "preflight off 인데 진단이 있다" || ok "진단은 꺼진 그대로"
new_proj t5d '{"SCV_DELEGATE_EFFORT": "on"}'; OUT="$(run_hook "$P")"
n_dir="$(grep -n 'SCV: 이 턴의 첫 행동' <<<"$OUT" | head -1 | cut -d: -f1)"
n_diag="$(grep -n 'Current project diagnosis' <<<"$OUT" | head -1 | cut -d: -f1)"
n_del="$(grep -nF "$MARK" <<<"$OUT" | head -1 | cut -d: -f1)"
if [[ -n "$n_dir" && -n "$n_diag" && -n "$n_del" && "$n_dir" -lt "$n_del" && "$n_del" -lt "$n_diag" ]]; then
  ok "순서: 지시(${n_dir}) < 위임(${n_del}) < 진단(${n_diag}) — 지시는 진단 앞에 (0.40.0 의 교훈)"
else
  fail "순서가 어긋났다 (지시=$n_dir 진단=$n_diag 위임=$n_del)"
fi
new_proj t5e '{"SCV_PLAIN_LANGUAGE": "off", "SCV_ALWAYS_ON": "off", "SCV_DELEGATE_EFFORT": "off"}'
[[ -z "$(run_hook "$P")" ]] && ok "셋 다 off → 완전 침묵" || fail "셋 다 off 인데 출력이 있다"

echo "── [T6] 순수 함수는 순수하다 ──"
OUT="$(bash "$CORE/scripts/check-purity.sh" "$FORCE_LIB" 2>&1)"
grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성 위반: $OUT"
pure_marked() {  # <함수 이름> — 직전 함수 정의 이후에 @pure 표시가 있는가
  awk -v fn="$1" '/^# @pure/{p=1} /^[a-z_]+\(\)/{ if (index($0, fn "()")==1) { print (p ? "yes" : "no"); exit } p=0 }' "$FORCE_LIB"
}
[[ "$(pure_marked scv_delegate_switch)" == "yes" ]] && ok "정규화 함수에 @pure" || fail "정규화 함수에 @pure 표시 없음"
[[ "$(pure_marked scv_delegate_block)" == "yes" ]] && ok "본문 함수에 @pure" || fail "본문 함수에 @pure 표시 없음"

echo "── [T7] 코어 본문은 호스트 중립이다 ──"
BLOCK="$( ( source "$FORCE_LIB"; scv_delegate_block ) )"
DOC="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["_doc"]["SCV_DELEGATE_EFFORT"])' "$EXAMPLE")"
SECTION="$(sed -n '/^## Deep questions go to a background investigator/,/^## Answer shape/p' "$HELP_PROTO")"
[[ -n "$SECTION" ]] && ok "help 규약에 위임 단락이 있다" || fail "help 규약에 위임 단락이 없다"
# 호스트 이름은 저장소 전체 검사(test-host-neutral)가 본다 — 이 파일에 그 이름을 적으면
# 그 검사에 이 파일이 걸린다. 여기서는 단계 이름만 직접 본다.
for text in "$BLOCK" "$DOC" "$SECTION"; do
  grep -qiE '\b(ultracode|xhigh|low|medium|high|max)\b' <<<"$text" && fail "단계 이름이 코어 본문에 있다" || ok "단계 이름 없음"
done
grep -q "never changes that dial" "$HELP_PROTO" && ok "규약: 세션 다이얼은 손대지 않는다" || fail "규약에 세션 다이얼 불변 문장이 없다"
if [[ -f "$CORE/../tests/test-host-neutral.sh" ]]; then
  bash "$CORE/../tests/test-host-neutral.sh" >/dev/null 2>&1 && ok "호스트 중립 검사 전체 통과" || fail "호스트 중립 검사 실패"
else
  skip "호스트 중립 검사 파일 없음 (래퍼 안에서 실행)"
fi

echo "── [T8] 템플릿 지문이 새 훅·설정 예시와 맞는다 ──"
if [[ -f "$CORE/scripts/compute-template-digest.sh" && -f "$CORE/TEMPLATE_DIGEST" ]]; then
  [[ "$(bash "$CORE/scripts/compute-template-digest.sh" 2>/dev/null | tail -1)" == "$(tr -d '[:space:]' < "$CORE/TEMPLATE_DIGEST")" ]] \
    && ok "지문 최신" || fail "지문이 오래됐다 — bash core/scripts/compute-template-digest.sh > core/TEMPLATE_DIGEST"
else
  skip "지문 도구 없음"
fi

# ── 래퍼 검사: 옆에 체크아웃이 있을 때만 ──
REPO_ROOT="$(cd "$CORE/.." 2>/dev/null && pwd)"
SIB="$(cd "$REPO_ROOT/.." 2>/dev/null && pwd || true)"
CC="$SIB/scv-claude-code"; CX="$SIB/scv-codex"

if [[ -d "$CC/commands" ]]; then
  echo "── [T9] 래퍼가 배경 조사 에이전트를 싣는다 ──"
  A="$CC/agents/scv-investigator.md"
  if [[ -f "$A" ]]; then
    ok "agents/scv-investigator.md 있음"
    FM="$(awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f' "$A")"
    grep -qE '^name:[[:space:]]*scv-investigator[[:space:]]*$' <<<"$FM" && ok "이름이 scv-investigator" || fail "이름이 다르다"
    grep -qE '^background:[[:space:]]*true' <<<"$FM" && ok "배경 실행" || fail "background: true 없음"
    grep -qE '^model:[[:space:]]*inherit' <<<"$FM" && ok "모델 상속" || fail "model: inherit 가 아니다 — 세션 모델을 바꾸면 안 된다"
    grep -qE '^effort:' <<<"$FM" && fail "effort 줄이 있다 — 세션 effort 를 바꾸지 않는다" || ok "effort 줄 없음"
    grep -qE '^tools:.*\bEdit\b' <<<"$FM" && fail "편집 도구가 있다" || ok "편집 도구 없음"
    grep -qE '^disallowedTools:.*\bEdit\b' <<<"$FM" && ok "편집 도구가 명시적으로 금지돼 있다" || fail "disallowedTools 에 Edit 이 없다"
    grep -q 'scv/raw/' "$A" && ok "결과를 scv/raw 파일로 남기라고 적혀 있다" || fail "결과 파일 위치가 없다"
    grep -qiE 'never (modify|edit|write)[^.]*outside' "$A" && ok "scv/raw 밖 쓰기 금지" || fail "scv/raw 밖 쓰기 금지 문장이 없다"
  else
    fail "래퍼에 agents/scv-investigator.md 가 없다"
  fi
  echo "── [T10] 래퍼 계약 검사가 새 파일을 잠근다 ──"
  T="$CC/tests/test-core-contract.sh"
  grep -q 'scv-investigator' "$T" && ok "계약 검사가 에이전트 파일을 본다" || fail "계약 검사에 에이전트 단언이 없다"
  grep -q 'carries a model: line' "$T" && ok "기존 model 줄 단언 유지" || fail "기존 model 줄 단언이 사라졌다"
else
  skip "T9/T10 — 명령 래퍼 체크아웃 없음 ($CC)"
fi

if [[ -d "$CX" ]]; then
  echo "── [T11] 스킬 래퍼(agents 없는 호스트)는 무변경 ──"
  if [[ -e "$CX/agents" || -e "$CX/plugins/scv/agents" ]]; then fail "스킬 래퍼에 agents 가 생겼다"; else ok "스킬 래퍼에 에이전트 없음 (전과 같음)"; fi
  grep -rq "SCV_DELEGATE_EFFORT" "$CX/plugins/scv/adapter" 2>/dev/null && fail "스킬 래퍼 어댑터가 스위치를 안다 — 무변경이어야" || ok "스킬 래퍼 어댑터 무변경"
else
  skip "T11 — 스킬 래퍼 체크아웃 없음"
fi

echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL · 건너뜀 $SKIP"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
