---
name: archive-integrity
cadence: 1w
guardrails:
  - "아카이브 폴더 내용(PLAN.md / TESTS.md / ARCHIVED_AT.md)은 수정하지 않는다 — 허용되는 쓰기는 INDEX.yaml 재생성뿐"
  - "불일치의 자동 수정 금지 — 발견한 불일치는 보고만 한다"
  - "INDEX.yaml 재생성분도 permanent 브랜치 직접 쓰기 금지 — PR 경유"
exit:
  - "INDEX.yaml 이 실제 아카이브 폴더와 일치하고 모든 supersedes / supersedes_scenarios 링크가 존재하는 슬러그를 가리키면 종료"
  - "불일치(누락·고아 항목·깨진 링크) 발견 시 목록을 보고한 뒤 종료"
report: on-failure
---

`scv/archive/INDEX.yaml` 을 재생성해 실제 아카이브 폴더 목록과 대조하고, 각
PLAN.md 의 `supersedes:` / `supersedes_scenarios:` 링크가 존재하는 슬러그를
가리키는지 검증한다 — 누락된 항목, 폴더 없는 고아 항목, 깨진 supersedes
링크를 찾아 보고하는 아카이브 무결성 점검 루틴이다.
