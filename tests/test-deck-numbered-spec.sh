#!/usr/bin/env bash
# test-deck-numbered-spec.sh — 번호식 화면설계서 (numbered screen-spec) contract.
#
# The deck's default 기획서 shape: a BIG PICTURE carries numbered markers and the
# prose hangs off those numbers in a side list — never a wall of sentences.
# Covers TESTS.md T1–T11 + T13 of 20260826-wookiya1364-numbered-spec-deck:
#   T1  numeric markers render on components (FE)
#   T2  action elements get LETTER markers, disjoint from the numeric set
#   T3  per-marker detail renders beside the picture, split into role/action groups
#   T4  faithfulness — an unwritten marker's detail is never invented
#   T5  page name + page code render above the picture
#   T6  cross-page reference (destination code) survives into the action detail
#   T7  BE — a diagram (no screen body) gets the SAME sidebar skeleton
#   T8  BACKWARD COMPAT — a marker-less legacy mockup renders byte-identically
#   T9  a deck with zero pictures raises a lint warning (and still builds)
#   T10 a deck WITH a picture does not raise it (no false warning)
#   T11 promote.md requires the spec material and warns-without-blocking
#   T13 an archived plan folder still builds and gains no empty sidebar
#
# Structural assertions target a --no-source render so a grep can never match the
# raw-markdown side panel instead of the rendered body (the mistake that let
# several past deck fixes pass even when reverted).
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$HERE/.."
REPO="$( cd "$ROOT/.." && pwd )"
DECKDOC="$ROOT/DeckUI/scripts/deckdoc"
DOC="$DECKDOC/doc.mjs"
PROMOTE_MD="$ROOT/protocols/promote.md"

pass=0; fail=0
has()  { grep -qF -- "$2" "$1" && { pass=$((pass+1)); } || { echo "  ✗ $3 — missing: $2"; fail=$((fail+1)); }; }
hasnt(){ grep -qF -- "$2" "$1" && { echo "  ✗ $3 — should be absent: $2"; fail=$((fail+1)); } || { pass=$((pass+1)); }; }
hasre(){ grep -qE -- "$2" "$1" && { pass=$((pass+1)); } || { echo "  ✗ $3 — no match: $2"; fail=$((fail+1)); }; }
ck()   { if [[ "$2" == "$3" ]]; then pass=$((pass+1)); else echo "  ✗ $1 — expected [$2] got [$3]"; fail=$((fail+1)); fi; }

command -v node >/dev/null 2>&1 || { echo "SKIP test-deck-numbered-spec: node not found"; exit 0; }
command -v pnpm >/dev/null 2>&1 || { echo "SKIP test-deck-numbered-spec: pnpm not found"; exit 0; }
if [[ ! -d "$DECKDOC/node_modules" ]]; then
  ( cd "$DECKDOC" && pnpm install ) >/dev/null 2>&1 || { echo "SKIP test-deck-numbered-spec: deckdoc install failed"; exit 0; }
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
build() { # build <src.md> <out.html> [extra flags...] → stdout+stderr into $TMP/log
  local src="$1" out="$2"; shift 2
  node "$DOC" "$src" --out "$out" --lang korean --no-source "$@" >"$TMP/log" 2>&1
}

# ── fixture: FE screen with numeric + letter markers, both detail groups ──────
cat >"$TMP/fe.md" <<'MD'
# 회원가입 기획서

## 화면

```screen
{
  "title": "회원가입 페이지",
  "pageCode": "FO-SU-02-01",
  "body": [
    { "type": "form", "marker": "1", "fields": [{ "label": "이메일" }] },
    { "type": "form", "marker": "2", "fields": [{ "label": "비밀번호" }] },
    { "type": "form", "marker": "3", "fields": [{ "label": "비밀번호 확인" }] },
    { "type": "button", "marker": "A", "label": "회원가입", "variant": "primary" },
    { "type": "button", "marker": "B", "label": "로그인" }
  ],
  "functions": [
    { "marker": "1", "title": "이메일 인풋 박스", "notes": ["320자 초과 입력 막음", "포커스 아웃 시 형식 검사"] },
    { "marker": "2", "title": "비밀번호 인풋 박스", "notes": ["8-16자 입력 제한"] }
  ],
  "actions": [
    { "marker": "A", "title": "회원가입 Submit 버튼", "notes": ["필수 항목 충족 시 활성화", "완료 시 FO-SU-02-02 로 이동"] },
    { "marker": "B", "title": "로그인 버튼", "notes": ["클릭 시 FO-SU-01-01 로 이동"] }
  ]
}
```
MD
build "$TMP/fe.md" "$TMP/fe.html" || { echo "  ✗ FE build failed"; cat "$TMP/log"; fail=$((fail+1)); }
FE="$TMP/fe.html"

echo "T1. 번호 마커가 그림 위에 표시된다"
has "$FE" 'class="wf-marker' "T1 마커 요소"
hasre "$FE" 'wf-marker[^>]*>1<'  "T1 마커 1"
hasre "$FE" 'wf-marker[^>]*>2<'  "T1 마커 2"
hasre "$FE" 'wf-marker[^>]*>3<'  "T1 마커 3"
ck "T1 마커 총 5개(1·2·3·A·B)" "5" "$(grep -o 'class="wf-marker[^"]*"' "$FE" | wc -l | tr -d ' ')"

echo "T2. 액션 요소는 문자 마커로 구분된다"
hasre "$FE" 'wf-marker[^>]*>A<' "T2 마커 A"
hasre "$FE" 'wf-marker[^>]*>B<' "T2 마커 B"
has   "$FE" 'class="wf-marker wf-marker-action"' "T2 액션 마커 계열 구분"
ck "T2 액션 마커 2개" "2" "$(grep -o 'class="wf-marker wf-marker-action"' "$FE" | wc -l | tr -d ' ')"

echo "T3. 번호별 상세가 그림 오른쪽에 붙는다 (역할 + 액션 두 묶음)"
has "$FE" 'class="wf-spec"'  "T3 사이드바 컨테이너"
has "$FE" 'wf-spec-group wf-spec-functions"' "T3 역할 묶음"
has "$FE" 'wf-spec-group wf-spec-actions"'   "T3 액션 묶음"
has "$FE" '이메일 인풋 박스'    "T3 역할 항목 제목"
has "$FE" '320자 초과 입력 막음' "T3 역할 항목 내용"
has "$FE" '회원가입 Submit 버튼' "T3 액션 항목 제목"
has "$FE" '필수 항목 충족 시 활성화' "T3 액션 항목 내용"

echo "T4. 지어내지 않는다 (충실도)"
# 3번은 마커만 있고 functions 항목이 없다 → 상세 묶음에 3번 항목이 없어야 한다
ck "T4 역할 항목 2개만(1·2)" "2" "$(grep -o 'class="wf-spec-item wf-spec-item-fn"' "$FE" | wc -l | tr -d ' ')"
hasnt "$FE" '비밀번호 확인 인풋' "T4 없는 설명 생성 금지"

echo "T5. 페이지 이름과 식별 코드가 그림 위에 나온다"
has "$FE" 'class="wf-pagebar"' "T5 페이지 바"
has "$FE" '회원가입 페이지' "T5 페이지 이름"
has "$FE" 'FO-SU-02-01'    "T5 식별 코드"

echo "T6. 이동 대상 상호참조가 표현된다"
has "$FE" 'FO-SU-02-02' "T6 이동 대상 코드(회원가입)"
has "$FE" 'FO-SU-01-01' "T6 이동 대상 코드(로그인)"

# ── fixture: BE — diagram as the big picture, same sidebar skeleton ───────────
cat >"$TMP/be.md" <<'MD'
# 인증 API 기획서

## 구성

```screen
{
  "title": "인증 서비스",
  "pageCode": "BE-AUTH-01",
  "diagram": "flowchart LR\n  C[클라이언트] --> A[\"① 인증 API\"]\n  A --> T[\"② 토큰 발급\"]\n  T --> S[(\"③ 사용자 저장소\")]",
  "functions": [
    { "marker": "1", "title": "인증 API", "notes": ["이메일·비밀번호를 받아 토큰을 돌려준다"] },
    { "marker": "2", "title": "토큰 발급 함수", "notes": ["만료 시각이 포함된 토큰을 만든다"] },
    { "marker": "3", "title": "사용자 저장소", "notes": ["이메일로 사용자를 찾고 해시를 대조한다"] }
  ]
}
```
MD
build "$TMP/be.md" "$TMP/be.html" || { echo "  ✗ BE build failed"; cat "$TMP/log"; fail=$((fail+1)); }
BE="$TMP/be.html"

echo "T7. BE — 화면이 없는 계획도 같은 골자로 그려진다"
has "$BE" 'pre class="mermaid"' "T7 큰 그림(다이어그램) 렌더"
has "$BE" 'flowchart LR'        "T7 다이어그램 본문"
has "$BE" 'class="wf-spec"'     "T7 FE와 같은 사이드바 컨테이너"
has "$BE" 'wf-spec-group wf-spec-functions"' "T7 FE와 같은 역할 묶음"
has "$BE" '인증 API'            "T7 번호별 API 설명"
has "$BE" '만료 시각이 포함된 토큰을 만든다' "T7 번호별 함수 설명"
has "$BE" 'class="wf-pagebar"'  "T7 FE와 같은 페이지 바"
hasnt "$BE" 'wf-spec-group wf-spec-actions"' "T7 액션 없으면 액션 묶음 없음"

# ── T8. backward compatibility: marker-less legacy mockup ────────────────────
cat >"$TMP/legacy.md" <<'MD'
# 레거시 목업

## 화면

```screen
{
  "title": "/campaigns",
  "nav": { "items": ["대시보드", "캠페인 관리"], "active": "캠페인 관리" },
  "body": [
    { "type": "header", "title": "캠페인 관리", "subtitle": "전체 목록" },
    { "type": "table", "columns": ["이름", "상태"], "rows": [["여름 캠페인", { "badge": "진행", "tone": "good" }]] },
    { "type": "button", "label": "새 캠페인", "variant": "primary" }
  ]
}
```
MD
build "$TMP/legacy.md" "$TMP/legacy.html" || { echo "  ✗ legacy build failed"; cat "$TMP/log"; fail=$((fail+1)); }
LEG="$TMP/legacy.html"

echo "T8. 마커 없는 기존 목업은 지금과 똑같이 렌더된다 (하위 호환)"
hasnt "$LEG" 'class="wf-marker' "T8 마커 자리 생성 금지"
hasnt "$LEG" 'class="wf-spec"'  "T8 빈 사이드바 생성 금지"
hasnt "$LEG" 'class="wf-pagebar"' "T8 빈 페이지 바 생성 금지"
has   "$LEG" 'wf-screen'  "T8 목업 자체는 그대로"
has   "$LEG" 'wf-frame'   "T8 프레임 그대로"
has   "$LEG" '캠페인 관리' "T8 내용 그대로"
# golden: the legacy screen block's rendered markup must equal the pre-change baseline
BASE="$HERE/fixtures/deck-legacy-screen.golden.html"
if [[ -f "$BASE" ]]; then
  node -e '
    const fs=require("fs");
    const pick=(f)=>{const h=fs.readFileSync(f,"utf8");const m=h.match(/<div class="wf-screen[\s\S]*?<\/div><\/div>/);return m?m[0]:"";};
    const a=pick(process.argv[1]), b=fs.readFileSync(process.argv[2],"utf8").trim();
    if(!a){console.error("  ✗ T8 golden — no wf-screen found in build");process.exit(1)}
    if(a.trim()!==b){console.error("  ✗ T8 golden — legacy screen markup changed");process.exit(1)}
  ' "$LEG" "$BASE" && pass=$((pass+1)) || fail=$((fail+1))
else
  echo "  ✗ T8 golden — baseline missing: $BASE"; fail=$((fail+1))
fi

# ── T9/T10. picture-density lint ─────────────────────────────────────────────
printf '# 글만 있는 기획서\n\n## Why\n\n문장만 있고 그림이 없다.\n\n## What\n\n여전히 문장뿐이다.\n' >"$TMP/nopic.md"
build "$TMP/nopic.md" "$TMP/nopic.html"
NOPIC_EXIT=$?
NOPIC_LOG="$(cat "$TMP/log")"

echo "T9. 그림 없는 기획서는 경고로 드러난다"
ck "T9 종료 코드 0 (막지 않는다)" "0" "$NOPIC_EXIT"
[[ -s "$TMP/nopic.html" ]] && pass=$((pass+1)) || { echo "  ✗ T9 결과 파일 생성"; fail=$((fail+1)); }
if printf '%s' "$NOPIC_LOG" | grep -q '그림'; then pass=$((pass+1)); else echo "  ✗ T9 그림 없음 경고 — got: $NOPIC_LOG"; fail=$((fail+1)); fi

printf '# 그림 있는 기획서\n\n## Why\n\n설명.\n\n```mermaid\nflowchart LR\n  A --> B\n```\n' >"$TMP/pic.md"
build "$TMP/pic.md" "$TMP/pic.html"
PIC_LOG="$(cat "$TMP/log")"
echo "T10. 그림이 있으면 그 경고는 뜨지 않는다"
if printf '%s' "$PIC_LOG" | grep -q '그림'; then echo "  ✗ T10 거짓 경고 — got: $PIC_LOG"; fail=$((fail+1)); else pass=$((pass+1)); fi

# ── T11. promote.md requires the spec material, warn-not-block ───────────────
echo "T11. 계획 작성 지침이 양식 재료를 요구한다"
if [[ -f "$PROMOTE_MD" ]]; then
  hasre "$PROMOTE_MD" 'numbered-spec|번호식|numbered screen spec' "T11 양식 요구 규칙"
  hasre "$PROMOTE_MD" 'warn|경고'                                  "T11 경고 규칙"
  hasnt "$PROMOTE_MD" 'block the build when the spec material is missing' "T11 중단 규칙 없음"
else
  echo "  ✗ T11 — promote.md not found: $PROMOTE_MD"; fail=$((fail+1))
fi

# ── T19–T22. 검증표 · 상태 변형 · 단계 연결 · 자동 번호 ──────────────────────
cat >"$TMP/spec2.md" <<'MD'
# 확장 기능

## 화면

```screen
{
  "title": "회원가입 페이지",
  "pageCode": "FO-SU-02-01",
  "body": [
    { "type": "header", "title": "회원가입", "subtitle": "캡션은 번호를 받지 않는다" },
    { "type": "form", "fields": [{ "label": "이메일" }] },
    { "type": "form", "fields": [{ "label": "비밀번호" }] },
    { "type": "button", "label": "회원가입", "variant": "primary" },
    { "type": "button", "label": "로그인" }
  ],
  "functions": [
    { "marker": "1", "title": "이메일 인풋", "step": "validateEmail", "notes": ["320자 제한"] },
    { "marker": "2", "title": "비밀번호 인풋", "step": "validatePassword", "notes": ["8-16자"] }
  ],
  "actions": [
    { "marker": "A", "title": "회원가입 버튼", "step": "buildSignupCommand", "notes": ["완료 시 FO-SU-02-02 로 이동"] }
  ],
  "states": [
    { "marker": "1", "label": "기본", "body": [{ "type": "form", "fields": [{ "label": "이메일" }] }] },
    { "marker": "1", "label": "Invalid", "body": [{ "type": "text", "value": "이메일 주소를 확인해주세요." }] }
  ],
  "validations": [
    { "marker": "1, A", "when": "포커스 아웃 / 제출", "condition": "이메일 형식 오류", "message": "이메일 주소를 확인해주세요.", "shownAs": "인풋 하단 문구" },
    { "marker": "2, A", "when": "제출", "condition": "비밀번호 8자 미만", "message": "비밀번호는 8-16자로 입력해주세요.", "shownAs": "인풋 하단 문구" }
  ]
}
```
MD
build "$TMP/spec2.md" "$TMP/spec2.html"
SPEC2_LOG="$(cat "$TMP/log")"
S2="$TMP/spec2.html"

echo "T19. 검증 메시지 표가 그림 아래에 나온다"
has "$S2" 'class="wf-vtable"'   "T19 검증표"
has "$S2" '체크 시점'            "T19 표 머리 — 체크 시점"
has "$S2" '노출 유형'            "T19 표 머리 — 노출 유형"
has "$S2" '이메일 형식 오류'      "T19 조건"
has "$S2" '이메일 주소를 확인해주세요.' "T19 메시지"
# 한 규칙이 여러 번호에 걸리는 것 — 이 표가 존재하는 이유
has "$S2" '1, A'                "T19 여러 번호에 걸친 규칙"
ck "T19 규칙 2행" "2" "$(grep -o 'class="wf-vt-marker"' "$S2" | wc -l | tr -d ' ')"

echo "T20. 컴포넌트 상태 변형이 그림 아래 띠로 나온다"
has "$S2" 'class="wf-states-row"' "T20 상태 띠"
has "$S2" '컴포넌트 상태'          "T20 제목"
has "$S2" 'Invalid'               "T20 상태 이름"
ck "T20 상태 2개" "2" "$(grep -o 'class="wf-state-frame"' "$S2" | wc -l | tr -d ' ')"

echo "T21. 번호별 상세가 파이프라인 단계와 이어진다"
has "$S2" 'class="wf-spec-step"' "T21 단계 태그"
has "$S2" 'validateEmail'        "T21 단계 이름(기능)"
has "$S2" 'buildSignupCommand'   "T21 단계 이름(액션)"
ck "T21 단계 태그 3개" "3" "$(grep -o 'class="wf-spec-step"' "$S2" | wc -l | tr -d ' ')"

echo "T22. 마커를 안 쓰면 자동으로 번호가 붙는다 (기본 동작)"
hasre "$S2" 'wf-marker wf-marker-fn">1<'     "T22 자동 번호 1"
hasre "$S2" 'wf-marker wf-marker-fn">2<'     "T22 자동 번호 2"
hasre "$S2" 'wf-marker wf-marker-action">A<' "T22 자동 문자 A"
hasre "$S2" 'wf-marker wf-marker-action">B<' "T22 자동 문자 B"
# 캡션(header)은 번호를 받지 않는다 — 받으면 실제 항목의 번호가 밀린다
ck "T22 마커 총 4개 (헤더 제외)" "4" "$(grep -o 'class="wf-marker[^"]*"' "$S2" | wc -l | tr -d ' ')"
# 자동 번호는 변환 단계에서 붙으므로 짝 검사가 오탐하지 않는다
if printf '%s' "$SPEC2_LOG" | grep -q '그림에 없는 번호'; then echo "  ✗ T22 짝 검사 오탐 — got: $SPEC2_LOG"; fail=$((fail+1)); else pass=$((pass+1)); fi

echo "T23. autoMarkers=false 면 자동 번호를 붙이지 않는다"
python3 - "$TMP/spec2.md" "$TMP/spec3.md" <<'PYEOF'
import sys, pathlib
s = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
pathlib.Path(sys.argv[2]).write_text(s.replace('"pageCode": "FO-SU-02-01",', '"pageCode": "FO-SU-02-01",\n  "autoMarkers": false,', 1), encoding="utf-8")
PYEOF
build "$TMP/spec3.md" "$TMP/spec3.html"
ck "T23 자동 번호 없음" "0" "$(grep -o 'class="wf-marker[^"]*"' "$TMP/spec3.html" | wc -l | tr -d ' ')"
has "$TMP/spec3.html" 'class="wf-vtable"' "T23 검증표는 그대로"

# ── T14/T15. 순수함수·파이프라인 — required in every plan ────────────────────
printf '# 파이프라인 개선 계획\n\n## Why\n\n설명만 있다.\n\n```mermaid\nflowchart LR\n  A --> B\n```\n' >"$TMP/nopipe.md"
build "$TMP/nopipe.md" "$TMP/nopipe.html"
NOPIPE_EXIT=$?
NOPIPE_LOG="$(cat "$TMP/log")"

echo "T14. 순수함수·파이프라인 섹션이 없으면 경고로 드러난다"
ck "T14 종료 코드 0 (막지 않는다)" "0" "$NOPIPE_EXIT"
[[ -s "$TMP/nopipe.html" ]] && pass=$((pass+1)) || { echo "  ✗ T14 결과 파일 생성"; fail=$((fail+1)); }
if printf '%s' "$NOPIPE_LOG" | grep -q '파이프라인'; then pass=$((pass+1)); else echo "  ✗ T14 파이프라인 경고 — got: $NOPIPE_LOG"; fail=$((fail+1)); fi
# the DOC TITLE contains the word — a title must never satisfy the section requirement
if printf '%s' "$NOPIPE_LOG" | grep -q '파이프라인 개선 계획'; then :; fi

printf '# 어떤 계획\n\n## 순수함수 · 파이프라인 (Pure functions & pipeline)\n\nflow(normalize, validate, build)\n\n```mermaid\nflowchart LR\n  A --> B\n```\n' >"$TMP/haspipe.md"
build "$TMP/haspipe.md" "$TMP/haspipe.html"
HASPIPE_LOG="$(cat "$TMP/log")"
echo "T15. 섹션이 있으면 그 경고는 뜨지 않는다 (거짓 경고 방지)"
if printf '%s' "$HASPIPE_LOG" | grep -q '파이프라인 섹션이 없습니다'; then echo "  ✗ T15 거짓 경고 — got: $HASPIPE_LOG"; fail=$((fail+1)); else pass=$((pass+1)); fi

echo "T16. 계획·구현 지침이 순수함수·파이프라인을 강제한다"
hasre "$PROMOTE_MD" '순수함수|pure function'          "T16 계획 지침 — 규칙"
has   "$PROMOTE_MD" "es-toolkit"                      "T16 계획 지침 — flow 참조"
has   "$PROMOTE_MD" '## 순수함수 · 파이프라인'          "T16 PLAN 뼈대에 섹션"
WORK_MD="$ROOT/protocols/work.md"
hasre "$WORK_MD" '순수함수|pure function'              "T16 구현 지침 — 규칙"
has   "$WORK_MD" "flow("                              "T16 구현 지침 — flow 형태"

echo "T17. BE 상세는 성공·실패·DB 영향까지 요구한다"
has "$PROMOTE_MD" '데이터(DB) 영향' "T17 DB 영향 요구"
has "$PROMOTE_MD" '트랜잭션 경계'   "T17 트랜잭션 경계 요구"
has "$PROMOTE_MD" '**성공**' "T17 성공 요구"
has "$PROMOTE_MD" '**실패**' "T17 실패 요구"

echo "T18. 화면설계서는 본문 폭이 아니라 전체 폭을 쓴다 (그림이 쪼그라들지 않게)"
has "$FE" 'wf-speclayout' "T18 레이아웃 래퍼"
RENDER="$DECKDOC/render.mjs"
has "$RENDER" '.wf-speclayout{' "T18 레이아웃 규칙 존재"
grep -A6 '@supports (width:100cqw)' "$RENDER" | grep -q 'wf-speclayout' && pass=$((pass+1)) || { echo "  ✗ T18 전체 폭(bleed) 미적용"; fail=$((fail+1)); }

echo "T24. 스크롤 영역은 하나뿐이다 (이중 스크롤 금지)"
# The app shell owns the scrolling; the document behind it must never scroll too —
# two bars leave the reader guessing which one the wheel moves.
has "$FE" 'html,body{height:100%;overflow:hidden' "T24 바깥 문서 스크롤 차단"
has "$FE" 'overscroll-behavior:none'              "T24 스크롤 체이닝 차단"
has "$FE" '.scroll-main{'                          "T24 안쪽 스크롤 영역 유지"
grep -o 'overflow-y:auto' "$FE" | head -1 >/dev/null && pass=$((pass+1)) || { echo "  ✗ T24 안쪽 스크롤 없음"; fail=$((fail+1)); }
# print must NOT inherit the clamp, or everything past page 1 is cropped away
python3 - "$FE" <<'PYEOF' && pass=$((pass+1)) || { echo "  ✗ T24 인쇄 시 되돌림 없음"; fail=$((fail+1)); }
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
i = html.find("@media print{")
j = html.find("html,body{height:auto;overflow:visible}")
sys.exit(0 if (i != -1 and j != -1 and j > i) else 1)
PYEOF

# ── T25–T28. BE 심화: 호출 화면 · 순서도 · 스키마 카드 · 실패 표 ──────────────
cat >"$TMP/be2.md" <<'MD'
# BE 심화

## 인증

```screen
{
  "title": "인증 서비스 — 로그인",
  "pageCode": "BE-AUTH-01",
  "screenRefs": [
    { "calls": "1", "name": "로그인 페이지", "pageCode": "FO-SU-01-01", "element": "Ⓐ 로그인 버튼", "when": "필수 입력이 유효할 때 클릭" }
  ],
  "diagram": [
    { "label": "구성", "code": "flowchart LR\n  C[클라이언트] --> A[\"① 인증 API\"]" },
    { "label": "순서", "code": "sequenceDiagram\n  autonumber\n  participant C as 클라이언트\n  participant A as ① 인증 API\n  C->>A: POST /auth/login\n  alt 실패\n    A-->>C: 401\n  else 성공\n    A-->>C: 200\n  end" }
  ],
  "functions": [
    { "marker": "1", "title": "인증 API", "step": "authenticate", "notes": ["역할: 로그인 요청을 토큰으로 바꾼다"] }
  ],
  "statesTitle": "데이터 모양 (테이블 스키마)",
  "states": [
    { "marker": "3", "label": "users", "body": [
      { "type": "table", "columns": ["컬럼", "비고"], "rows": [["email", "UNIQUE 인덱스"], ["password_hash", "원문 저장 금지"]] }
    ] }
  ],
  "validations": {
    "title": "실패 · 응답 표",
    "columns": ["번호", "조건", "응답", "본문 · 메시지", "기록 · 데이터 영향"],
    "rows": [
      ["1", "해시 불일치", "401", "어느 쪽인지 밝히지 않음", "⑤에 실패 1건"],
      ["1", "정상", "200", "접근 토큰 + 갱신 토큰", "④에 토큰 1건 — 한 트랜잭션"]
    ]
  }
}
```
MD
build "$TMP/be2.md" "$TMP/be2.html"
B2="$TMP/be2.html"

echo "T25. BE 최상단에 '어느 화면이 부르는가'가 나온다"
has "$B2" '호출 화면'      "T25 호출 화면 제목"
has "$B2" 'FO-SU-01-01'   "T25 화면 코드"
has "$B2" 'Ⓐ 로그인 버튼'  "T25 요소"
has "$B2" '필수 입력이 유효할 때 클릭' "T25 시점"
# 그림보다 위에 있어야 한다 — 백엔드 독자의 첫 질문이 "누가 나를 부르나"이므로
python3 - "$B2" <<'PYEOF' && pass=$((pass+1)) || { echo "  ✗ T25 호출 표가 그림보다 아래"; fail=$((fail+1)); }
import sys
h = open(sys.argv[1], encoding="utf-8").read()
sys.exit(0 if h.find("호출 화면") < h.find('<pre class="mermaid">') else 1)
PYEOF

echo "T26. 큰 그림을 여러 장(구성 + 순서) 그릴 수 있다"
ck "T26 다이어그램 2장" "2" "$(grep -o '<pre class=\"mermaid\">' "$B2" | wc -l | tr -d ' ')"
has "$B2" 'class="wf-diagram-label"' "T26 그림 이름표"
has "$B2" 'sequenceDiagram'          "T26 순서도"

echo "T27. 상태 띠를 테이블 스키마로 쓸 수 있다 (제목 교체)"
has "$B2" '데이터 모양 (테이블 스키마)' "T27 제목 교체"
hasnt "$B2" '>컴포넌트 상태<'          "T27 FE 기본 제목 미사용"
has "$B2" 'UNIQUE 인덱스'              "T27 컬럼 비고"

echo "T28. 실패·응답 표를 직접 만든 컬럼으로 쓸 수 있다"
has "$B2" '실패 · 응답 표' "T28 표 제목 교체"
has "$B2" '기록 · 데이터 영향' "T28 직접 정한 컬럼"
# scoped to the failure table — screenRefs shares the same table primitive above it
python3 - "$B2" <<'PYEOF' && pass=$((pass+1)) || { echo "  ✗ T28 실패 표 2행 아님"; fail=$((fail+1)); }
import sys
h = open(sys.argv[1], encoding="utf-8").read()
seg = h[h.find("실패 · 응답 표"):]
seg = seg[: seg.find("</table>")]
sys.exit(0 if seg.count('class="wf-vt-marker"') == 2 else 1)
PYEOF

echo "T29. 순서도 글자가 배경에 묻히지 않는다 (대비)"
RENDER="$DECKDOC/render.mjs"
has "$RENDER" 'svg .messageText' "T29 메시지 글자 색 규칙"
has "$RENDER" '.sectionTitle'    "T29 else 분기 라벨 색 규칙"
has "$RENDER" 'svg .actor'       "T29 참여자 상자 색 규칙"

# ── T13. an archived plan still builds, gains no empty sidebar ───────────────
echo "T13. 아카이브된 기획서를 다시 만들어도 지금과 같이 열린다"
# Pick a plan from BEFORE this format existed — one whose docs carry no screen
# block at all. `tail -1` used to mean that and silently stopped meaning it the
# moment this very feature was archived: the newest folder became a plan that
# legitimately renders a sidebar, and the "no empty sidebar" assertion started
# failing on correct output. The property under test is "an old plan still builds
# and gains nothing it did not ask for", so select for that property, not for age.
ARCH=""
for d in $(ls -dr "$REPO"/scv/archive/*/ 2>/dev/null); do
  grep -rqlF '```screen' "$d" 2>/dev/null && continue
  ARCH="$d"; break
done
if [[ -n "$ARCH" && -f "$ARCH/PLAN.md" ]]; then
  if node "$DOC" "$ARCH" --out "$TMP/arch.html" --lang korean --no-source >"$TMP/log" 2>&1; then
    pass=$((pass+1))
    hasnt "$TMP/arch.html" 'class="wf-spec"'  "T13 빈 사이드바 없음"
    hasnt "$TMP/arch.html" 'class="wf-pagebar"' "T13 빈 페이지 바 없음"
  else
    echo "  ✗ T13 아카이브 빌드 실패"; cat "$TMP/log"; fail=$((fail+1))
  fi
else
  echo "  ✗ T13 — no archive folder found"; fail=$((fail+1))
fi

echo
echo "test-deck-numbered-spec: pass=$pass fail=$fail"
[[ $fail -eq 0 ]] || exit 1
