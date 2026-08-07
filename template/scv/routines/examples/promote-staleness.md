---
name: promote-staleness
cadence: 1w
guardrails:
  - "PLAN.md / TESTS.md 를 수정하지 않고, 폴더를 이동·삭제·아카이브하지 않는다 — 리마인드만"
  - "같은 슬러그에 대한 리마인드를 무한 반복하지 않는다 — 직전 보고와 목록이 동일하면 생략"
  - "permanent 브랜치 직접 쓰기 금지"
exit:
  - "기준 초과 폴더 목록(슬러그·경과일)이 보고되면 종료"
  - "초과 폴더가 없으면 보고 없이 종료"
report: always
---

`scv/promote/` 아래 `status: planned` 인 계획 폴더 중 `created_at` 이 N일
(기본 14일)을 초과한 것을 찾아, 슬러그와 경과일을 담은 리마인드를 보고한다 —
착수(action:work)할지, 계획을 접을지 팀이 결정하도록 방치된 계획을 가시화하는
루틴이다.
