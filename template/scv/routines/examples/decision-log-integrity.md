---
name: decision-log-integrity
cadence: 1w
guardrails:
  - "DECISIONS.md 는 append-only — 기존 엔트리 수정·삭제 금지. 누락분을 소급 작성하지도 않는다(보고만)"
  - "아카이브 폴더 내용은 읽기만 한다 — 수정 금지"
  - "직전 실행에서 이미 보고한 슬러그를 반복 보고하지 않는다"
  - "permanent 브랜치 직접 쓰기 금지 — 산출물이 필요하면 PR 경유"
exit:
  - "모든 아카이브 슬러그가 대응 엔트리를 갖고 각 엔트리에 path delta 가 있으면 종료"
  - "누락 슬러그 또는 필드 결손 목록을 보고한 뒤 종료"
report: on-failure
---

`scv/archive/` 의 각 슬러그에 대응하는 결정 엔트리가 `scv/DECISIONS.md` 에
존재하는지, 그리고 그 엔트리가 `- path delta:` 를 담고 있는지 대조한다 —
`action:work` Step 9b.0 의 기록 지시가 실제로 실행됐는지 사후에 확인하는
유일한 수단이다. 엔트리를 쓰는 스크립트가 없어 런타임 강제가 불가능하므로,
누락은 이 루틴으로만 드러난다. 슬러그 대조는 엔트리의 `refs:` 경로를 기준으로
하고, 수동 `--archive` 로 들어온 `path delta: unknown (…)` 은 결손이 아니라
정상 값으로 취급한다.
