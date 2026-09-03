#!/usr/bin/env bash
# test-help-shape.sh — help 규약의 "답 모양" 절이 온전한지 잠근다.
#
# 답은 모델이 쓰므로 출력 자체는 검사하지 않는다 — 그 길은 0.39.0 이 갔다가 답이
# 통째로 재생성되는 값을 치르고 걷어냈다. 대신 규약에 필요한 문장이 다 있는지를
# 본다. 문장이 없으면 다음 사람이 모르고 지우고, 지우면 답 모양이 조용히 무너진다.
#
# 핵심은 T2 다: 여섯 자리는 채워야 할 칸이 아니라 골라 쓰는 어휘다. "모두 채우라"
# 로 읽히는 문장이 하나라도 생기면 모델은 점검표처럼 칸을 채우려 든다.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/protocols/help.md" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-help-shape: payload not found from $HERE" >&2; exit 1; }
PROTO="$CORE/protocols/help.md"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

# 답 모양 절만 잘라낸다 — 절 제목부터 다음 "## " 까지.
SECTION="$(awk '/^## Answer shape/{f=1} f&&/^## /&&!/^## Answer shape/{exit} f' "$PROTO")"
[[ -n "$SECTION" ]] || { echo "✖ 답 모양 절이 없다"; exit 1; }
# 문장은 줄바꿈을 넘어 이어질 수 있다 — 구절 검사는 한 줄로 편 본문에서 한다.
FLAT="$(tr '\n' ' ' <<<"$SECTION" | tr -s ' ')"

echo "── [T1] 여섯 자리가 어휘로 있고, 상대 순서가 정해져 있다 ──"
n1="$(grep -n '\*\*Lead\*\*'          <<<"$SECTION" | head -1 | cut -d: -f1)"
n2="$(grep -n '\*\*Surprises\*\*'     <<<"$SECTION" | head -1 | cut -d: -f1)"
n3="$(grep -n '\*\*Item table\*\*'    <<<"$SECTION" | head -1 | cut -d: -f1)"
n4="$(grep -n '\*\*Detail\*\*'        <<<"$SECTION" | head -1 | cut -d: -f1)"
n5="$(grep -n '\*\*Cross-cutting\*\*' <<<"$SECTION" | head -1 | cut -d: -f1)"
n6="$(grep -n '\*\*Decisions\*\*'     <<<"$SECTION" | head -1 | cut -d: -f1)"
if [[ -n "$n1$n2$n3$n4$n5$n6" && "$n1" -lt "$n2" && "$n2" -lt "$n3" && "$n3" -lt "$n4" && "$n4" -lt "$n5" && "$n5" -lt "$n6" ]]; then
  ok "여섯 자리가 모두 있고 순서가 결론→예상 밖→항목표→상세→횡단→결정표다"
else
  fail "자리가 빠졌거나 순서가 다르다 (${n1:-?} ${n2:-?} ${n3:-?} ${n4:-?} ${n5:-?} ${n6:-?})"
fi
grep -q "they appear in this order" <<<"$FLAT" && ok "상대 순서 규칙이 문장으로 있다" || fail "순서 규칙 문장 없음"
grep -q "vocabulary, not a form" <<<"$FLAT" && ok "어휘이지 양식이 아니라고 못 박았다" || fail "어휘/양식 구분 없음"

echo "── [T2] 질문이 부르는 자리만 고르고, 자리를 더하지 않는다 ──"
grep -q "only the slots the question calls for" <<<"$FLAT" && ok "질문이 부르는 자리만 쓴다" || fail "고르는 기준 없음"
grep -q "The only slot every answer has" <<<"$FLAT" && ok "결론 자리만 항상 있다" || fail "항상 있는 자리가 명시되지 않았다"
grep -q "never adds a slot to look complete" <<<"$FLAT" && ok "완성돼 보이려고 자리를 더하지 않는다" || fail "자리 추가 금지 없음"
grep -qiE "fill (in )?(all|every) (six|slot)|all six slots (must|always)" <<<"$FLAT" \
  && fail "'모두 채우라' 로 읽히는 문장이 있다" || ok "'모두 채우라' 로 읽히는 문장 없음"

echo "── [T3] 짧은 턴은 결론 자리 하나만 부른다 ──"
grep -q "one-word acknowledgement → Lead only" <<<"$FLAT" && ok "맞장구 → 결론만" || fail "짧은 턴의 예가 없다"

echo "── [T4] 백지 아이디어는 '없음' 표다 ──"
grep -q 'now. reads .none. — that is a fact, not an empty table' <<<"$FLAT" \
  && ok "'지금'=없음 은 사실이지 빈 표가 아니라고 적혀 있다" || fail "'없음' 표 구분이 없다"
grep -q "fresh idea with no code behind it → Lead, Item table" <<<"$FLAT" \
  && ok "백지 아이디어 → 결론 + 항목표" || fail "백지 아이디어의 예가 없다"

echo "── [T5] 결정표는 추천이 필수이고 번호로 답하게 한다 ──"
grep -q "my recommendation" <<<"$FLAT" && ok "추천 열이 있다" || fail "추천 열 없음"
grep -q "The recommendation column is never omitted" <<<"$FLAT" && ok "추천 열은 생략 불가" || fail "추천 필수 규칙 없음"
grep -q "answer by" <<<"$FLAT" && grep -q "number" <<<"$FLAT" && ok "번호로 답하게 한다" || fail "번호 답변 규칙 없음"

echo "── [T6] 의존 질문은 하나씩, 독립 결정은 한 표 ──"
grep -q "When the next question depends on" <<<"$FLAT" && ok "의존 → 질문 하나" || fail "의존 갈래 없음"
grep -q "independent of each other, put them in one Decisions table" <<<"$FLAT" && ok "독립 → 결정표 하나" || fail "독립 갈래 없음"
grep -q "Don't dump all questions at once" "$PROTO" \
  && fail "옛 '한 번에 묻지 말라' 문장이 조건 없이 남아 있다" || ok "옛 무조건 문장이 없다"
grep -q "either one\s*$" "$PROTO" || grep -q "either one" "$PROTO" \
  && grep -q "dependent question or one Decisions table — never both" "$PROTO" \
  && ok "대화 루프도 같은 구분을 따른다" || fail "대화 루프의 리듬이 갱신되지 않았다"

echo "── [T7] 쉬운말은 결론을, 이 절은 그 뒤를 다스린다 ──"
grep -q "governs the lead" <<<"$FLAT" && grep -q "governs everything after the lead" <<<"$FLAT" \
  && ok "역할 분담이 적혀 있다" || fail "쉬운말과의 역할 분담 없음"
# 쉬운말 절 본문은 바이트 단위로 그대로여야 한다 — 기준선은 저장소 HEAD 다.
if git -C "$CORE/.." rev-parse --verify HEAD >/dev/null 2>&1; then
  REL="$(cd "$CORE/.." && git ls-files --full-name -- core/protocols/help.md 2>/dev/null | head -1)"
  if [[ -n "$REL" ]]; then
    plain_now="$(awk '/^## Plain language first/{f=1} f&&/^## /&&!/^## Plain language first/{exit} f' "$PROTO")"
    plain_head="$(cd "$CORE/.." && git show "HEAD:$REL" 2>/dev/null | awk '/^## Plain language first/{f=1} f&&/^## /&&!/^## Plain language first/{exit} f')"
    if [[ -n "$plain_head" ]]; then
      [[ "$plain_now" == "$plain_head" ]] && ok "쉬운말 절 본문이 HEAD 와 동일하다" || fail "쉬운말 절 본문이 바뀌었다"
    else
      echo "  – T7 쉬운말 비교 SKIP (HEAD 에 파일 없음)"
    fi
  else
    echo "  – T7 쉬운말 비교 SKIP (git 추적 밖)"
  fi
else
  echo "  – T7 쉬운말 비교 SKIP (git 저장소 아님)"
fi

echo "── [T8] 사실에는 '확인됨' 을 붙인다 ──"
grep -q "Facts and estimates never mix" <<<"$FLAT" && ok "사실과 추정을 섞지 않는다" || fail "사실/추정 규칙 없음"
grep -q "(confirmed)" <<<"$FLAT" && ok "'(confirmed)' 표시가 명시돼 있다" || fail "확인됨 표시 없음"

echo "── [T9] 되돌림을 만들지 않았다 ──"
grep -qiE "\bblock\b|\bretry\b|되돌" <<<"$SECTION" && fail "답 모양 절에 차단·되돌림 문구가 있다" || ok "차단·되돌림 문구 없음"
STOP_HOOK="$CORE/template/hooks/on-stop.sh"
if [[ -f "$STOP_HOOK" ]] && git -C "$CORE/.." rev-parse --verify HEAD >/dev/null 2>&1; then
  ( cd "$CORE/.." && git diff --quiet HEAD -- core/template/hooks/on-stop.sh 2>/dev/null ) \
    && ok "종료 훅은 바뀌지 않았다" || fail "종료 훅이 바뀌었다"
fi

echo "── [T10] 사람의 말로 — 만든 이름을 사용자에게 내보내지 않는다 ──"
grep -q "never coin a label" <<<"$FLAT" && ok "이름을 지어내지 않는다" || fail "이름 짓기 금지 없음"
grep -q "are for you, not for the user; they never appear in an answer" <<<"$FLAT" \
  && ok "절의 이름은 모델용이고 답에 나가지 않는다" || fail "이름의 용도 구분 없음"
grep -q "reuse the user's own word" <<<"$FLAT" && ok "사용자의 말을 그대로 쓴다" || fail "사용자 어휘 규칙 없음"
grep -q "define it in the same sentence with an example, then stop using it" <<<"$FLAT" \
  && ok "피할 수 없는 용어는 한 번 설명하고 그 뒤로는 쓰지 않는다" || fail "용어 처리 규칙 없음"

echo "── [T11] 옛 계약 문구가 살아 있다 ──"
grep -q "one question per turn" "$PROTO" && ok "'one question per turn' 유지" || fail "옛 계약 문구가 사라졌다 — run-dry 가 막는다"

echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && echo "  ALL GATES OK" || exit 1
