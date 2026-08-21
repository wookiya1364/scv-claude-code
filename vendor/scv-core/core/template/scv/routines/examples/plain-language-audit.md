---
name: plain-language-audit
cadence: 1w
guardrails:
  - "판정 대상은 scv/journal/ 의 assistant 턴만 — user 턴과 코드 블록은 제외"
  - "기준은 답의 모양 네 가지(먼저 1~2문장 · 예시 하나 · 묻기 전 코드값 금지 · 자세한 건 원할 때)만 — 문체 취향으로 지적하지 않는다"
  - "파일을 고치거나 지우지 않는다 — 보고만 한다 (journal 은 append-only)"
  - ".env 에 SCV_PLAIN_LANGUAGE=off 인 프로젝트에서는 실행하지 않는다"
exit:
  - "직전 실행 이후의 assistant 턴을 모두 훑어 위반 목록(파일:시각 · 어긴 항목 · 첫 문장)을 보고하면 종료"
  - "위반이 없음을 확인하면 종료"
report: on-failure
---

지난 실행 이후 scv/journal/ 에 쌓인 assistant 턴을 훑어, 첫 답이 답의 모양을
어긴 곳 — 첫 문장이 두 문장을 넘거나, 예시가 없거나, 사용자가 묻기 전에 파일
경로·변수명·버전·설정값으로 말한 곳 — 을 찾아 파일:시각과 어긴 항목, 그
첫 문장을 목록으로 보고한다.
