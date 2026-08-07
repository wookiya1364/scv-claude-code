---
name: outdated-verifier
cadence: 1w
guardrails:
  - "raw 문서를 수정·삭제·이동하지 않는다 — 판정만 한다"
  - "휴리스틱 신호를 그대로 결론으로 삼지 않는다 — 현재 코드와의 의미 대조 없이 outdated 판정 금지"
  - "판정 결과는 보고로만 흘려보낸다 — permanent 브랜치 직접 쓰기 금지"
exit:
  - "모든 OUTDATED-CANDIDATE 에 대해 fresh / outdated 판정과 근거가 보고되면 종료"
  - "후보가 없으면 (readpath.sh outdated 가 exit 0) 보고 없이 즉시 종료"
report: always
---

`readpath.sh outdated` 의 출력을 입력으로 삼아, 각 `OUTDATED-CANDIDATE` 줄이
가리키는 소비된(raw/stale) 문서의 주장 — 그 문서가 언급하는 파일·동작 — 을
현재 코드와 의미 대조하고, 문서가 실제로 낡았는지(outdated) 아직 유효한지
(fresh)를 후보별 근거와 함께 판정해 보고한다. 후보 산출은 휴리스틱이고 판정은
이 루틴의 의미 검증이다.
