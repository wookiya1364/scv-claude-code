#!/usr/bin/env bash
# test-deck-picture-only.sh — 기획서는 그림만 (picture-only deck) contract.
#
# A slug folder's 기획서 renders the PICTURE doc (FEATURE_ARCHITECTURE.md) as its
# body; PLAN.md / TESTS.md keep travelling as source-panel tabs. A folder with no
# picture doc builds NOTHING — that prose already lives in PLAN.md / TESTS.md.
# Covers TESTS.md T1-T9 + T11 of 20260827-wookiya1364-deck-picture-only:
#   T1  folder input renders the picture doc only
#   T2  no picture doc → nothing built, reason printed, exit 0
#   T3  --full restores the three-doc combine byte-for-byte
#   T4  the source panel still carries all three tabs
#   T5  dropping PLAN.md from the body raises no extra lint warning
#   T6  a body with no picture at all still raises the picture-density warning
#   T7  the real archived plan renders its picture sections and its markers
#   T8  archived deck HTML files are untouched by a build to another path
#   T9  single-file input is unchanged
#   T11 callers get exit 0 (never an error) when nothing is built
#
# Structural assertions target a --no-source render so a grep can never match the
# raw-markdown side panel instead of the rendered body.
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$HERE/.."
REPO="$( cd "$ROOT/.." && pwd )"
DECKDOC="$ROOT/DeckUI/scripts/deckdoc"
DOC="$DECKDOC/doc.mjs"
DECK_SH="$ROOT/scripts/deck.sh"
DECK_MD="$ROOT/protocols/deck.md"

pass=0; fail=0
has()  { grep -qF -- "$2" "$1" && { pass=$((pass+1)); } || { echo "  ✗ $3 — missing: $2"; fail=$((fail+1)); }; }
hasnt(){ grep -qF -- "$2" "$1" && { echo "  ✗ $3 — should be absent: $2"; fail=$((fail+1)); } || { pass=$((pass+1)); }; }
ck()   { if [[ "$2" == "$3" ]]; then pass=$((pass+1)); else echo "  ✗ $1 — expected [$2] got [$3]"; fail=$((fail+1)); fi; }

command -v node >/dev/null 2>&1 || { echo "SKIP test-deck-picture-only: node not found"; exit 0; }
command -v pnpm >/dev/null 2>&1 || { echo "SKIP test-deck-picture-only: pnpm not found"; exit 0; }
if [[ ! -d "$DECKDOC/node_modules" ]]; then
  ( cd "$DECKDOC" && pnpm install ) >/dev/null 2>&1 || { echo "SKIP test-deck-picture-only: deckdoc install failed"; exit 0; }
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── fixture: a full slug folder — prose plan + picture doc + prose tests ──────
FULLDIR="$TMP/slug-full"; mkdir -p "$FULLDIR"
cat >"$FULLDIR/PLAN.md" <<'MD'
# 결제 한도 계획

## Summary

PLAN_ONLY_SENTINEL — 계획서에만 있는 문장.

## Goals / Non-Goals

- 목표: 한도를 올린다
- 비목표: 통화를 늘리지 않는다

## 순수함수 · 파이프라인 (Pure functions & pipeline)

flow(normalize, validate)

## Exit criteria

- 인수기준: 한도 초과 시 거절된다

## 성공지표 (Metrics)

| 지표 | 지금 | 목표 |
|---|---|---|
| 한도 | 1 | 2 |

## 예외처리 (Edge cases)

- 음수 금액
MD
cat >"$FULLDIR/FEATURE_ARCHITECTURE.md" <<'MD'
# Architecture — 결제 한도 계획

## 1. Component data flow

PICTURE_ONLY_SENTINEL — 구조 문서에만 있는 문장.

```mermaid
flowchart LR
  A[결제 요청] -->|"validate(amount)"| B[한도 검사]
```

## 2. Screen mockups

```screen
{
  "title": "결제 화면",
  "pageCode": "FO-PAY-01-01",
  "body": [
    { "type": "form", "marker": "1", "fields": [{ "label": "금액" }] },
    { "type": "button", "marker": "A", "label": "결제", "variant": "primary" }
  ],
  "functions": [{ "marker": "1", "title": "금액 인풋", "notes": ["한도 초과 입력 막음"] }],
  "actions": [{ "marker": "A", "title": "결제 버튼", "notes": ["한도 안일 때만 활성화"] }]
}
```
MD
cat >"$FULLDIR/TESTS.md" <<'MD'
# Test Plan — 결제 한도 계획

## Test scenarios

### T1. 한도 초과

TESTS_ONLY_SENTINEL — 테스트 문서에만 있는 문장.
MD

build() { # build <src> <out> [flags...]
  local src="$1" out="$2"; shift 2
  node "$DOC" "$src" --out "$out" --lang korean --mermaid cdn "$@" >"$TMP/log" 2>&1
}

echo "T1. 폴더를 넘기면 본문은 그림 문서만이다"
build "$FULLDIR" "$TMP/t1.html" --no-source || { echo "  ✗ T1 build failed"; cat "$TMP/log"; fail=$((fail+1)); }
has   "$TMP/t1.html" "PICTURE_ONLY_SENTINEL" "T1 구조 문서 문구가 본문에 있다"
hasnt "$TMP/t1.html" "PLAN_ONLY_SENTINEL"    "T1 계획 문서 문구가 본문에 없다"
hasnt "$TMP/t1.html" "TESTS_ONLY_SENTINEL"   "T1 테스트 문서 문구가 본문에 없다"

echo "T2/T11. 그림 문서가 없으면 만들지 않고 정상 종료한다"
NOPIC="$TMP/slug-nopic"; mkdir -p "$NOPIC"
cp "$FULLDIR/PLAN.md" "$FULLDIR/TESTS.md" "$NOPIC/"
node "$DOC" "$NOPIC" --lang korean --mermaid cdn >"$TMP/nopic.log" 2>&1
ck "T11 종료 코드 0 (오류가 아니다)" "0" "$?"
has "$TMP/nopic.log" "DECK_SKIPPED:" "T2 사유 줄이 출력된다"
hasnt "$TMP/nopic.log" "DECK_HTML:"  "T2 HTML 경로를 내지 않는다"
ck "T2 HTML 파일이 생기지 않는다" "0" "$(find "$NOPIC" -name '*.html' | wc -l | tr -d ' ')"
# 같은 폴더라도 되살리기 옵션이면 만들어진다 — 잃는 길이 아니라 기본값의 문제다
node "$DOC" "$NOPIC" --lang korean --mermaid cdn --full >"$TMP/nopicfull.log" 2>&1
has "$TMP/nopicfull.log" "DECK_HTML:" "T2 되살리기 옵션으로는 만들어진다"

echo "T3. 되살리기 옵션은 예전 전체 결합을 그대로 낸다"
build "$FULLDIR" "$TMP/t3.html" --no-source --full || { echo "  ✗ T3 build failed"; cat "$TMP/log"; fail=$((fail+1)); }
has "$TMP/t3.html" "PLAN_ONLY_SENTINEL"    "T3 계획 문서가 본문에 있다"
has "$TMP/t3.html" "PICTURE_ONLY_SENTINEL" "T3 구조 문서가 본문에 있다"
has "$TMP/t3.html" "TESTS_ONLY_SENTINEL"   "T3 테스트 문서가 본문에 있다"

echo "T4. 원문 사이드 패널은 세 탭을 그대로 유지한다"
build "$FULLDIR" "$TMP/t4.html" || { echo "  ✗ T4 build failed"; cat "$TMP/log"; fail=$((fail+1)); }
has "$TMP/t4.html" "PLAN.md"                 "T4 계획 탭"
has "$TMP/t4.html" "FEATURE_ARCHITECTURE.md" "T4 구조 탭"
has "$TMP/t4.html" "TESTS.md"                "T4 테스트 탭"
has "$TMP/t4.html" "PLAN_ONLY_SENTINEL"      "T4 본문에서 빠진 계획 원문이 패널에는 있다"
has "$TMP/t4.html" "TESTS_ONLY_SENTINEL"     "T4 본문에서 빠진 테스트 원문이 패널에는 있다"

echo "T5. 계획 문서를 본문에서 빼도 린트 경고가 늘지 않는다"
node "$DOC" "$FULLDIR" --out "$TMP/t5d.html" --lang korean --mermaid cdn --no-source >"$TMP/t5d.log" 2>&1
node "$DOC" "$FULLDIR" --out "$TMP/t5f.html" --lang korean --mermaid cdn --no-source --full >"$TMP/t5f.log" 2>&1
LD="$(sed -n 's/^LINT: \([0-9]*\) .*/\1/p' "$TMP/t5d.log")"
LF="$(sed -n 's/^LINT: \([0-9]*\) .*/\1/p' "$TMP/t5f.log")"
ck "T5 기본값과 되살리기의 경고 수가 같다" "$LF" "$LD"
ck "T5 갖춘 문서에는 경고가 없다" "0" "$LD"
for kw in 비목표 성공지표 인수기준 예외처리 파이프라인; do
  hasnt "$TMP/t5d.log" "$kw" "T5 '$kw' 거짓 경고가 없다"
done

echo "T6. 그림이 정말 없을 때의 경고는 그대로 뜬다"
NOPIC2="$TMP/slug-flatpic"; mkdir -p "$NOPIC2"
cp "$FULLDIR/PLAN.md" "$NOPIC2/"
printf '# Architecture\n\n## 1. 구성\n\n그림 없이 글만 있다.\n' >"$NOPIC2/FEATURE_ARCHITECTURE.md"
node "$DOC" "$NOPIC2" --out "$TMP/t6.html" --lang korean --mermaid cdn --no-source >"$TMP/t6.log" 2>&1
has "$TMP/t6.log" "DECK_HTML:" "T6 문서는 만들어진다"
has "$TMP/t6.log" "그림이 하나도 없습니다" "T6 그림 없음 경고가 뜬다"

echo "T7. 실제 아카이브 계획으로 그림 절만 나온다"
REAL="$REPO/scv/archive/20260826-wookiya1364-numbered-spec-deck"
if [[ -d "$REAL" ]]; then
  build "$REAL" "$TMP/t7.html" --no-source || { echo "  ✗ T7 build failed"; cat "$TMP/log"; fail=$((fail+1)); }
  has   "$TMP/t7.html" "Component data flow" "T7 구조 문서의 절이 있다"
  hasnt "$TMP/t7.html" "Exit criteria"       "T7 계획 문서의 절이 없다"
  hasnt "$TMP/t7.html" "Test scenarios"      "T7 테스트 문서의 절이 없다"
  has   "$TMP/t7.html" 'class="wf-marker'    "T7 번호식 마커가 렌더된다"
else
  echo "  · T7 건너뜀 (아카이브 슬러그 없음)"
fi

echo "T8. 다른 경로로 만들어도 아카이브 기획서 파일은 그대로다"
if [[ -d "$REAL" ]]; then
  BEFORE="$(find "$REPO/scv/archive" -name '*.deck.html' -exec md5sum {} + 2>/dev/null | sort)"
  build "$REAL" "$TMP/t8.html" --no-source
  AFTER="$(find "$REPO/scv/archive" -name '*.deck.html' -exec md5sum {} + 2>/dev/null | sort)"
  ck "T8 아카이브 기획서 해시가 그대로다" "$BEFORE" "$AFTER"
else
  echo "  · T8 건너뜀 (아카이브 슬러그 없음)"
fi

echo "T9. 단일 마크다운 파일 입력은 합치기를 거치지 않는다"
node "$DOC" "$FULLDIR/PLAN.md" --out "$TMP/t9.html" --lang korean --mermaid cdn --no-source >"$TMP/t9.log" 2>&1
has "$TMP/t9.log"  "DECK_HTML:"         "T9 파일 하나로도 만들어진다"
has "$TMP/t9.html" "PLAN_ONLY_SENTINEL" "T9 그 파일의 내용이 본문이다"

echo "T10. 되살리기 옵션이 실행 스크립트와 지침에 노출된다"
has "$DECK_SH" -- "--full" "T10 실행 스크립트가 옵션을 받는다"
has "$DECK_MD" -- "--full" "T10 지침이 옵션을 설명한다"
has "$DECK_MD" "DECK_SKIPPED" "T10 지침이 '만들 것 없음' 줄을 설명한다"

echo
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]] || exit 1
