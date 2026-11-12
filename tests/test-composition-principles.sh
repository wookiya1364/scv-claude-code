#!/usr/bin/env bash
# test-composition-principles.sh — 합성 설계 원칙이 SCV 계약과 계획 절차에 들어갔는지, 체크리스트가 빠지면
# 기획서 검사가 경고하는지 본다 (계획 20261111-wookiya1364-composition-principles · TESTS.md T1 ~ T11).
#
# Run: bash core/tests/test-composition-principles.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
DOC="$CORE/contracts/composition.md"
PUR="$CORE/contracts/purity.md"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "T1. 계약 문서 — 합성 원칙의 낱말"
c=0; for k in '요소 단위' '순회는 한' '중간 모음' '지연 평가' '구조 공유' '단항'; do grep -q -- "$k" "$DOC" 2>/dev/null && c=$((c + 1)) || echo "      없음: $k"; done
[[ $c == 6 ]] && ok "OK [T1] 6/6" || fail "[T1] $c/6"

echo "T2. 계약 문서 — 언어별 수단 표 (언어 9개 + 셸, 칸 5개)"
rows="$(awk '/^## 언어별 수단/{f=1; next} /^## /{f=0} f && /^\| / && !/^\| 언어 /' "$DOC" 2>/dev/null)"
# 한 번 훑어 셋을 낸다: 줄 수 · 칸이 5개가 아닌 줄 수 · 60바이트(한글 스무 자)를 넘는 첫 칸. LC_ALL=C 라 어느 awk 든 바이트로 센다.
stat="$(LC_ALL=C awk -F'|' 'NF { n++; if (NF - 2 != 5) bad++; for (i = 2; i < NF; i++) { c = $i; gsub(/^ +| +$/, "", c); if (length(c) > 60 && long == "") long = c } } END { printf "%d\t%d\t%s", n, bad, long }' <<<"$rows")"
IFS=$'\t' read -r n bad long <<<"$stat"
miss=""; for l in 'TypeScript/JS' Python Java Kotlin 'C#' Go Rust Scala Haskell 셸; do grep -q "^| $l |" <<<"$rows" || miss="$miss $l"; done
[[ "$n" == 10 && "$bad" == 0 && -z "$miss" ]] && ok "OK [T2] 10 rows × 5 cells" || fail "[T2] rows=$n bad-rows=$bad missing:$miss"
[[ -z "$long" ]] && ok "OK [T2b] no prose cells" || fail "[T2b] long cell: $long"

echo "T3. 계약 문서 — 막는 것과 못 막는 것"
sec="$(awk '/^## SCV 가 막는 것과 못 막는 것/{f=1; next} /^## /{f=0} f' "$DOC" 2>/dev/null)"
grep -q '최대 성능은 증명할 수 없다' <<<"$sec" && ! grep -Eq '(최대|최고) ?성능(을|이|은)? ?보장' "$DOC" && ok "OK [T3] says it cannot be proven; never promises it" || fail "[T3]"

# 0.90.0 에는 재는 명령이, 0.91.0 에는 더 나은 엮음을 계산으로 찾는 일이 "아직 없다"고 적혀 있었다.
# 0.92.0 에 엮음 고르기 명령이 생겼다 — 이제 이 절은 그 명령을 이름으로 말하고, 아직 없는 것(계획 · 마무리 단계가
# 스스로 돌리지 않음)을 따로 밝힌다. 있는 것처럼만 말하고 없는 것을 감추면 실패한다.
grep -q 'pipe-arrange.sh' <<<"$sec" && grep -q '아직 없는 것' <<<"$sec" && ok "OK [T3b] names the arranging command and says what is still missing" || fail "[T3b] the doc must name pipe-arrange.sh and say what does not exist yet"

echo "T4. 계약 문서 — 체크리스트 10개"
n="$(awk '/^## 체크리스트/{f=1; next} /^## /{f=0} f && /^[0-9]+\. /' "$DOC" 2>/dev/null | grep -c .)"
[[ "$n" == 10 ]] && ok "OK [T4] 10 questions" || fail "[T4] $n"

echo "T5. 기존 순수성 문서가 새 문서를 가리킨다"
[[ "$(grep -c 'composition.md' "$PUR")" == 1 ]] && ok "OK [T5] one pointer" || fail "[T5] $(grep -c 'composition.md' "$PUR")"

echo "T6. 계획 템플릿 — 체크리스트 표"
PRO="$CORE/protocols/promote.md"
grep -q '^### 합성 설계 체크리스트' "$PRO" && grep -q '^| # | 물음 | 답 | 근거 |$' "$PRO" && grep -q 'core/contracts/composition.md' "$PRO" \
  && ok "OK [T6] the PLAN template carries the table" || fail "[T6]"

echo "T7. 작업 규약 — 보관을 정하는 단계의 첫 일로 코드로 다시 답한다"
WRK="$CORE/protocols/work.md"
h="$(grep -n '^### Step 9b — Archive decision' "$WRK" | head -1 | cut -d: -f1)"
a="$(grep -n 'the composition checklist — answered from the code' "$WRK" | head -1 | cut -d: -f1)"
b="$(grep -n '^#### Step 9b.0' "$WRK" | head -1 | cut -d: -f1)"
[[ -n "$h" && -n "$a" && -n "$b" && "$a" -gt "$h" && "$a" -lt "$b" ]] && ok "OK [T7] inside the archive step, before the decision log" || fail "[T7] h=$h a=$a b=$b"
grep -q 'Step 9a.5' "$WRK" && fail "[T7b] a separate step that the routes into 9b jump over" || ok "OK [T7b] no step for the 9a routes to skip"

echo "T8 ~ T11. 기획서 검사의 체크리스트 경고"
DOCJS="$CORE/DeckUI/scripts/deckdoc/doc.mjs"
DECKDOC="$CORE/DeckUI/scripts/deckdoc"
if command -v node >/dev/null 2>&1 && command -v pnpm >/dev/null 2>&1 && [[ ! -d "$DECKDOC/node_modules" ]]; then
  ( cd "$DECKDOC" && pnpm install ) >/dev/null 2>&1
fi
if ! command -v node >/dev/null 2>&1 || [[ ! -d "$DECKDOC/node_modules" ]]; then
  echo "  - SKIP [T8 ~ T11] node 또는 기획서 도구의 의존 묶음이 없음"
else
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  deck() { node "$DOCJS" "$1" --out "$2" --lang korean --no-source >"$TMP/log" 2>&1; }
  head_md() { printf '# 어떤 계획\n\n## 순수함수 · 파이프라인 (Pure functions & pipeline)\n\nflow(a, b)\n\n```mermaid\nflowchart LR\n  A --> B\n```\n\n'; }
  CK='합성 설계 체크리스트'

  head_md >"$TMP/none.md"
  deck "$TMP/none.md" "$TMP/none.html"; rc=$?
  n="$(grep -c "$CK" "$TMP/log")"
  [[ $rc == 0 && -s "$TMP/none.html" && "$n" == 1 ]] && ok "OK [T8] no table → one warning, deck still built" || fail "[T8] rc=$rc warnings=$n"

  { head_md; printf '### 합성 설계 체크리스트\n\n| # | 물음 | 답 | 근거 |\n|---|---|---|---|\n| 1 | 단항인가 | 예 | a.sh:10 |\n| 3 | 순회 한 번인가 | 예 | |\n| 7 | 부수효과는 끝에만 | 예 | <TODO> |\n| 9 | 변이를 막는가 | | |\n'; } >"$TMP/empty.md"
  deck "$TMP/empty.md" "$TMP/empty.html"; rc=$?
  ev="$(grep '근거가 빈 답' "$TMP/log")"; an="$(grep '답이 빈 줄' "$TMP/log")"
  [[ $rc == 0 && "$ev" == *"3, 7"* && "$ev" != *"1,"* ]] && ok "OK [T9] names both rows without evidence (3, 7), not row 1" || fail "[T9] $ev"
  [[ "$an" == *"9"* ]] && ok "OK [T9b] a row with no answer is named too" || fail "[T9b] $an"

  { head_md; printf '### 합성 설계 체크리스트\n\n| # | 물음 | 답 | 근거 |\n|---|---|---|---|\n| 1 | 단항인가 | 예 | a.sh:10 |\n| 그 밖 | 2 ~ 10 | 해당 없음 | 한 번 훑는 작은 글 |\n'; } >"$TMP/full.md"
  deck "$TMP/full.md" "$TMP/full.html"; rc=$?
  [[ $rc == 0 && "$(grep -c "$CK" "$TMP/log")" == 0 ]] && ok "OK [T10] every answer has evidence → no checklist warning" || fail "[T10] $(grep "$CK" "$TMP/log")"
  # 다른 절의 제목에 같은 낱말이 있어도(표 없음) 진짜 표를 찾는다
  { head_md; printf '## 시험 체크리스트\n\n- 하나\n\n### 합성 설계 체크리스트\n\n| # | 물음 | 답 | 근거 |\n|---|---|---|---|\n| 1 | 단항인가 | 예 | a.sh:10 |\n'; } >"$TMP/two.md"
  deck "$TMP/two.md" "$TMP/two.html"
  [[ "$(grep -c "$CK" "$TMP/log")" == 0 ]] && ok "OK [T10b] another heading with the same word does not hide the table" || fail "[T10b] $(grep "$CK" "$TMP/log")"

  # 반박 검증(2026-11-11)에서 나온 경우들
  { head_md; printf '### 합성 설계 체크리스트\n\n| # | 물음 | 답 | 근거 |\n|---|---|---|---|\n| 1 | 단항인가 | 예 | todo/store.ts:12 |\n| 2 | 입출력 | 예 | `TODO.md:3` |\n'; } >"$TMP/todo.md"
  deck "$TMP/todo.md" "$TMP/todo.html"
  [[ "$(grep -c "$CK" "$TMP/log")" == 0 ]] && ok "OK [T9c] a file named todo is evidence, not a placeholder" || fail "[T9c] $(grep "$CK" "$TMP/log")"
  { head_md; printf '### 합성 설계 체크리스트\n\n| # | 물음 | 답 | 근거 |\n|---|---|---|---|\n| 1 | 단항인가 | 예 | 없음 |\n| 2 | 입출력 | 예 | TBD |\n|  | 번호 없는 줄 | 예 | |\n'; } >"$TMP/weak.md"
  deck "$TMP/weak.md" "$TMP/weak.html"; ev="$(grep '근거가 빈 답' "$TMP/log")"
  [[ "$ev" == *"1, 2, #3"* ]] && ok "OK [T9d] a bare 없음 · TBD is no evidence; a row without a number is named by position" || fail "[T9d] $ev"
  { head_md; printf '### 합성 설계 체크리스트\n\n| # | 물음 | 답 | 근거 |\n|---|---|---|---|\n'; } >"$TMP/headonly.md"
  deck "$TMP/headonly.md" "$TMP/headonly.html"
  [[ "$(grep -c '체크리스트가 없습니다' "$TMP/log")" == 1 ]] && ok "OK [T8b] a table with no rows counts as missing" || fail "[T8b] $(grep "$CK" "$TMP/log")"
  { head_md; printf '## 수동 확인 체크리스트\n\n| # | 확인 | 답 | 근거 |\n|---|---|---|---|\n| 1 | 눌러 봄 | 예 | 화면 |\n\n### 합성 설계 체크리스트\n\n| # | 물음 | 답 | 근거 |\n|---|---|---|---|\n| 1 | 단항인가 | 예 | |\n'; } >"$TMP/other.md"
  deck "$TMP/other.md" "$TMP/other.html"
  [[ "$(grep -c '근거가 빈 답 1' "$TMP/log")" == 1 ]] && ok "OK [T10c] another checklist with the same columns does not stand in for it" || fail "[T10c] $(grep "$CK" "$TMP/log")"

  # 변경 지도: 체크리스트 표가 단계 표의 앞에 와도 · 뒤에 와도 단계는 단계 표에서 읽는다
  STEPS='| # | 단계 | 하는 일 | 받는 값 → 돌려주는 값 | 순수/부수효과 |\n|---|---|---|---|---|\n| 1 | `aa_one` | 읽는다 | 글 → 줄 | 순수 |\n| 2 | `bb_two` | 센다 | 줄 → 수 | 순수 |\n'
  CKT='### 합성 설계 체크리스트\n\n| # | 물음 | 답 | 근거 |\n|---|---|---|---|\n| 1 | 단항인가 | 예 | a.sh:10 |\n'
  for order in before after; do
    d="$TMP/plan-$order"; mkdir -p "$d"
    { printf '# 어떤 계획\n\n## 순수함수 · 파이프라인 (Pure functions & pipeline)\n\nflow(aa_one, bb_two)\n\n'
      if [[ $order == before ]]; then printf "$CKT\n$STEPS"; else printf "$STEPS\n$CKT"; fi; } >"$d/PLAN.md"
    printf '# Architecture\n\n## 1. 흐름\n\n```mermaid\nflowchart LR\n  A --> B\n```\n' >"$d/FEATURE_ARCHITECTURE.md"
    deck "$d" "$TMP/plan-$order.html"
    cm="$(grep '^CHANGE_MAP' "$TMP/log")"
    [[ "$cm" == *"steps=2"* ]] && grep -q 'aa_one' "$TMP/plan-$order.html" && ! grep -q '단항인가' "$TMP/plan-$order.html" && ok "OK [T12-$order] the change map reads the step table ($cm)" || fail "[T12-$order] $cm"
  done

  # 파이프라인 절이 아예 없는 글은 기존 경고 하나만 — 체크리스트 경고를 겹쳐 내지 않는다
  printf '# 옛 계획\n\n## Why\n\n설명.\n\n```mermaid\nflowchart LR\n  A --> B\n```\n' >"$TMP/old.md"
  deck "$TMP/old.md" "$TMP/old.html"; rc=$?
  [[ $rc == 0 && -s "$TMP/old.html" && "$(grep -c "$CK" "$TMP/log")" == 0 && "$(grep -c '파이프라인 섹션이 없습니다' "$TMP/log")" == 1 ]] \
    && ok "OK [T11] a plan without the pipeline part: built, one old warning, no new one" || fail "[T11] rc=$rc $(grep -c "$CK" "$TMP/log")"
fi

echo
echo "── $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
