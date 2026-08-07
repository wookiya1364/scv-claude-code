---
name: regression-runner
cadence: 1d
guardrails:
  - "아카이브된 TESTS.md / ARCHIVED_AT.md 본문 수정 금지 (불변 아카이브)"
  - "실패 슬러그를 사용자 트리아지 없이 obsolete 로 마킹하지 않는다"
  - "코드 수정 시도는 이 루틴의 범위 밖 — permanent 브랜치 직접 쓰기 금지"
exit:
  - "action:regression 실행이 완료되고 전 슬러그 통과가 확인되면 종료"
  - "실패 슬러그가 있으면 실패 요약을 report 로 발행한 뒤 종료 (수정은 별도 세션)"
report: on-failure
---

아카이브에 누적된 회귀 스위트를 실행한다 — `action:regression` 을 `--ci` 로
돌려 supersede/obsolete 스킵 그래프를 존중한 전체 결과를 얻고, 실패가 있으면
실패 슬러그 목록과 개수를 `action:report` 형식으로 팀에 알린다.
