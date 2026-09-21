# Contract — 경계 (boundaries)

액션이 손대지 않는 것. 이 문서가 그 요구의 **유일한** 본문이다 — codegen·work·regression 은 이 문서를 가리키고
자기 말로 다시 적지 않는다(`scv/SCV.md` Top-level rules 4조: 같은 요구는 한 곳에만).

## 왜

같은 세 문장이 세 프로토콜의 "Non-negotiable rules" 에 각각 있었다. 규칙 헌법 검사 (b) 가 그것을 중복 후보로 잡아
기준선의 마지막 빚 3건으로 남아 있었다(2026-09-21). 요구는 하나이고 지키는 액션이 셋일 뿐이다.

## 무엇을

1. **범위 밖 파일** — 계획의 범위(`scope:` 또는 Suggested path 가 자연히 정하는 범위) 밖의 파일을 지우거나 옮기지 않는다.
2. **보관된 TESTS.md 본문** — 보관 폴더의 TESTS.md 는 고쳐 쓰지 않는다. 폐기(obsolete) 표시는 그 폴더 PLAN.md
   프런트매터의 세 필드로만 한다: `status: obsolete` · `obsoleted_at` · `obsoleted_by`.
3. **ARCHIVED_AT.md 와 보관 폴더의 나머지** — 보관 기록은 불변이다. supersede 전파(work 9c · regression 삭감)도
   위 세 필드 외에는 아무것도 만지지 않는다.

codegen 의 "구현 중 TESTS.md 본문을 고치지 않는다 — 테스트가 스펙이다" 는 이 계약이 아니라 codegen 고유의 요구다.
보관 전 TESTS.md 를 다루기 때문이다.

## 어디서 가리키나

codegen · work · regression 의 Non-negotiable rules 한 줄. 9c 폐기 표시 질문 템플릿(work · regression)은 사용자에게
보여주는 문장이라 두 액션이 같은 템플릿을 갖는다 — 검사 (b) 허용목록에 이유와 함께.

## 검사

- `core/tests/run-dry.sh` [11s]: 세 프로토콜에 `contracts/boundaries.md` 참조가 있다.
- `core/tests/test-rule-constitution.sh` 검사 (b): 경계 문장이 두 문서 이상에 있으면 기준선을 넘는다.
