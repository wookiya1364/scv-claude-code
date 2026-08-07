---
name: team-todo
version: 1.0.0
status: active
last_updated: 2026-08-07
tags: [todo, append-only, attribution]
standard_version: 1.0.0
merge_policy: preserve
---

# TODO — 팀 공유 할일

> 세션과 함께 사라지던 할일을 커밋되는 문서로 축적합니다. 누구든 작업을
> 이어받아도 무엇이 남았는지 보이게.

## 규약

- **append-only** — 항목의 본문 수정·삭제 금지. 완료 처리는 체크박스만
  `[ ]` → `[x]` 로 바꿉니다. 내용이 바뀌면 새 항목을 append 하고 이전 항목을
  완료 처리합니다.
- **author 필수** — 모든 항목은 작성자 귀속 (`@<author>`). 익명 항목 금지.
- **ID 규율** — `(T-NNN)` 일련번호. 마지막 항목의 번호 +1 을 씁니다.
- **충돌 시 둘 다 보존(union merge)** — append-only + ID 규율 덕에 같은 줄을
  다투는 일은 드뭅니다. 충돌이 나면 양쪽 항목을 모두 남기고, ID 가 겹쳤으면
  나중 항목의 번호만 다음 빈 번호로 조정합니다.
- `action:status` 가 미완료 항목을 작성자별로 노출합니다.

## 항목 형식

```markdown
  - [ ] (T-001) <내용> — @<author>, YYYY-MM-DD
```

## Items

<!-- append items below this line (format above, unindented) -->
