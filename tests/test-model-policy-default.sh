#!/usr/bin/env bash
# test-model-policy-default.sh — SCV 명령이 세션 모델을 바꾸지 않는다.
#
# 명령 파일 머리말의 model 줄은 그 명령이 도는 동안 세션 모델을 바꾼다. 0.43.0 의
# 무조건 호출과 결합되자 사용자가 고른 모델 대신 매 턴 다른 모델이 답했다. 기본은
# "줄 없음" 이어야 하고, 매핑은 켠 사람에게만 붙어야 한다. 코어 페이로드는 호스트
# 중립이라 이 파일은 특정 모델 이름을 적지 않는다 — 줄의 유무와 서로 다름만 본다. 코어에서 볼 수 있는 것(설정
# 등록부)은 항상 검사하고, 래퍼 파일은 옆에 체크아웃이 있을 때만 본다 — 없으면
# SKIP 이지 실패가 아니다.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-model-policy-default: payload not found from $HERE" >&2; exit 1; }

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  – SKIP: $1"; SKIP=$((SKIP + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

echo "── [T1] 코어 설정 등록부에 정책 키가 있다 ──"
grep -qE '(^|[[:space:]])SCV_MODEL_POLICY([[:space:]]|$|")' "$CORE/scripts/lib/settings.sh" \
  && ok "공개 키 목록에 SCV_MODEL_POLICY" || fail "공개 키 목록에 없음"
EX="$CORE/template/scv/scv_settings.example.json"
python3 - "$EX" <<'PY' && ok "예시 기본값 session-default + 설명 있음" || fail "예시 파일에 키·기본값·설명 중 빠진 것이 있다"
import json,sys
d=json.load(open(sys.argv[1]))
assert d.get("SCV_MODEL_POLICY")=="session-default", d.get("SCV_MODEL_POLICY")
assert "SCV_MODEL_POLICY" in d.get("_doc",{}) and "session-default" in d["_doc"]["SCV_MODEL_POLICY"]
PY

echo "── [T2] 하이드레이트한 새 프로젝트의 설정 파일에 키가 생긴다 ──"
P="$WORK/proj"; mkdir -p "$P"
( cd "$P" && git init -q . && git config user.email t@e && git config user.name t \
  && bash "$CORE/scripts/hydrate.sh" init . >/dev/null 2>&1 )
if [[ -f "$P/scv/scv_settings.json" ]]; then
  python3 - "$P/scv/scv_settings.json" <<'PY' && ok "새 프로젝트 설정에 SCV_MODEL_POLICY=session-default" || fail "새 프로젝트 설정에 키가 없거나 값이 다르다"
import json,sys; d=json.load(open(sys.argv[1])); assert d.get("SCV_MODEL_POLICY")=="session-default", d.get("SCV_MODEL_POLICY")
PY
else
  fail "하이드레이트가 설정 파일을 만들지 않았다"
fi

# ── 래퍼 검사: 옆에 체크아웃이 있을 때만 ──
REPO_ROOT="$(cd "$CORE/.." 2>/dev/null && pwd)"
SIB="$(cd "$REPO_ROOT/.." 2>/dev/null && pwd || true)"
CC="$SIB/scv-claude-code"; CX="$SIB/scv-codex"

if [[ -d "$CC/commands" && -f "$CC/scripts/apply-model-policy.sh" ]]; then
  echo "── [T3] 래퍼 명령 파일에 모델 지정 줄이 없다 ──"
  n=$(grep -l '^model:' "$CC"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
  [[ "$n" == "0" ]] && ok "명령 파일 $(ls "$CC"/commands/*.md | wc -l | tr -d ' ')개 모두 model 줄 없음" \
                    || fail "model 줄이 남은 명령 파일 ${n}개: $(grep -l '^model:' "$CC"/commands/*.md | xargs -n1 basename | tr '\n' ' ')"

  # 스크립트를 임시 배치에 복사 — PLUGIN_ROOT 는 스크립트 위치에서 계산되므로 배치를 흉내낸다.
  mk_wrap() {  # <이름> → 경로
    local d="$WORK/$1"; mkdir -p "$d/scripts" "$d/commands" "$d/vendor/scv-core/core/scripts/lib"
    cp "$CC/scripts/apply-model-policy.sh" "$d/scripts/"; cp "$CC"/commands/*.md "$d/commands/"
    cp "$CORE/scripts/lib/settings.sh" "$d/vendor/scv-core/core/scripts/lib/"
    printf '%s' "$d"
  }

  echo "── [T4] 매핑을 켜면 줄이 생기고, 끄면 사라진다 (멱등) ──"
  Wd="$(mk_wrap w4)"
  bash "$Wd/scripts/apply-model-policy.sh" --policy recommended >/dev/null 2>&1
  h="$(grep -E '^model: ' "$Wd/commands/help.md" | head -1)"; s="$(grep -E '^model: ' "$Wd/commands/status.md" | head -1)"
  [[ -n "$h" && -n "$s" && "$h" != "$s" ]] \
    && ok "recommended → 무거운 액션(help)과 가벼운 액션(status)에 서로 다른 model 줄이 생겼다" || fail "recommended 적용 결과가 다르다 (help=[$h] status=[$s])"
  bash "$Wd/scripts/apply-model-policy.sh" --policy session-default >/dev/null 2>&1
  [[ "$(grep -l '^model:' "$Wd"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')" == "0" ]] \
    && ok "session-default → 전부 제거" || fail "session-default 뒤에도 줄이 남았다"
  before="$(cat "$Wd"/commands/*.md | cksum)"; bash "$Wd/scripts/apply-model-policy.sh" --policy session-default >/dev/null 2>&1
  [[ "$before" == "$(cat "$Wd"/commands/*.md | cksum)" ]] && ok "두 번 적용해도 같다 (멱등)" || fail "멱등이 아니다"

  echo "── [T5] 정책을 설정 파일에서 읽는다 ──"
  Wd="$(mk_wrap w5)"; Pd="$WORK/p5"; mkdir -p "$Pd/scv"
  printf '{\n  "SCV_MODEL_POLICY": "recommended"\n}\n' > "$Pd/scv/scv_settings.json"
  out="$(SCV_PROJECT_DIR="$Pd" bash "$Wd/scripts/apply-model-policy.sh" --from-env 2>&1)"
  grep -q '^model: ' "$Wd/commands/help.md" && ok "설정 파일의 정책(recommended)이 적용됐다 — model 줄이 생겼다" \
    || fail "설정 파일을 읽지 않았다: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"

  echo "── [T6] 옛 .env 만 있는 프로젝트도 읽는다 ──"
  Wd="$(mk_wrap w6)"; Pd="$WORK/p6"; mkdir -p "$Pd"
  printf 'SCV_MODEL_POLICY=recommended\n' > "$Pd/.env"
  out="$(SCV_PROJECT_DIR="$Pd" bash "$Wd/scripts/apply-model-policy.sh" --from-env 2>&1)"
  grep -q '^model: ' "$Wd/commands/status.md" && ok ".env 의 정책(recommended)이 호환 경로로 적용됐다" \
    || fail ".env 호환 읽기가 안 된다: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"

  echo "── [T6b] 아무 데도 없으면 세션 모델 — 줄을 만들지 않는다 ──"
  Wd="$(mk_wrap w6b)"; Pd="$WORK/p6b"; mkdir -p "$Pd/scv"; printf '{}\n' > "$Pd/scv/scv_settings.json"
  SCV_PROJECT_DIR="$Pd" bash "$Wd/scripts/apply-model-policy.sh" --from-env >/dev/null 2>&1
  [[ "$(grep -l '^model:' "$Wd"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')" == "0" ]] \
    && ok "정책 없음 → 줄 없음 그대로" || fail "정책이 없는데 줄이 생겼다"

  echo "── [T7] set-models 문서가 없는 스크립트를 부르지 않는다 ──"
  SM="$CC/commands/set-models.md"
  grep -q "env-set.sh" "$SM" && fail "사라진 env-set.sh 를 아직 부른다" || ok "env-set.sh 언급 없음"
  grep -q "settings-set.sh" "$SM" && ok "저장은 settings-set.sh 로" || fail "settings-set.sh 로 저장하지 않는다"
  first="$(grep -m1 -E '^\[1\] "' "$SM" || true)"
  grep -q "session-default" <<<"$first" && ok "첫 선택지가 session-default" || fail "첫 선택지가 session-default 가 아니다: $first"

  echo "── [T8] 래퍼 검사가 새 기본을 잠근다 ──"
  TC="$CC/tests/test-core-contract.sh"
  grep -q 'lost .* model metadata' "$TC" && fail "옛 단언('model 줄 있어야')이 남아 있다" || ok "옛 단언 없음"
  grep -qE 'model: .*(session|default|carries|shipped)' "$TC" && ok "새 단언('기본은 없어야') 있음" || fail "새 단언이 없다"
else
  skip "commands 형 래퍼(scv-claude-code) 체크아웃 없음 — T3~T8 건너뜀"
fi

if [[ -d "$CX/plugins/scv" ]]; then
  echo "── [T9] skills 형 래퍼는 무변경 — 모델 지정 줄이 없다 ──"
  n=$(grep -rl '^model:' "$CX/plugins/scv" --include='*.md' 2>/dev/null | grep -v '/vendor/' | wc -l | tr -d ' ')
  [[ "$n" == "0" ]] && ok "skills 형 래퍼에 model 줄 없음" || fail "skills 형 래퍼에 model 줄 ${n}개"
else
  skip "skills 형 래퍼(scv-codex) 체크아웃 없음 — T9 건너뜀"
fi

echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL · 건너뜀 $SKIP"
[[ $FAIL -eq 0 ]] && echo "  ALL GATES OK" || exit 1
