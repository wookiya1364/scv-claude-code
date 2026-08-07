---
name: routines-guide
version: 1.0.0
status: active
last_updated: 2026-08-07
tags: [routines, maintenance, guide]
standard_version: 1.0.0
merge_policy: overwrite
---

# scv/routines — 한 문장 프롬프트 유지보수 루틴

> 매일/매주 반복할 유지보수 과업을 **루틴 1개 = md 파일 1개**로 정의하는 곳입니다.
> 실행은 `action:routine <name>`, 목록은 `action:routine --list`.
> **스케줄링(주기 실행)은 SCV 가 하지 않습니다** — 호스트(에이전트의 반복 실행
> 기능, cron, CI 스케줄 잡)가 소유합니다. SCV 는 정의 형식과 실행 프로토콜만
> 제공합니다.

## 파일 규약

- 경로: `scv/routines/<name>.md` — 루틴 1개당 파일 1개. `README.md` 는 예외(이 문서).
- hydrate 는 이 README 만 시딩합니다. 루틴 파일은 사용자/에이전트가 추가합니다.
- 시작 템플릿: SCV Core 의 `core/template/scv/routines/examples/` 에 내장 예시
  7종이 있습니다 — 필요한 것을 이 폴더로 복사해 수정하세요.

## Frontmatter 스키마 (5개 키 전부 필수)

```yaml
---
name: dead-code            # 루틴 이름 (파일 basename 과 일치 권장)
cadence: 1d                # 제안 주기 (1d, 1w, ...) — 제안일 뿐, 등록은 호스트에서
guardrails:                # 하지 말 것 / 넘지 말 것 (계약)
  - "삭제는 반드시 PR 경유 — permanent 브랜치 직접 쓰기 금지"
exit:                      # 종료 조건 (이 상태가 되면 멈춘다)
  - "제안 PR 발행 또는 후보 없음 확인"
report: never              # always | on-failure | never — action:report 형식 보고 여부
---
```

| 키 | 의미 |
|---|---|
| `name` | 루틴 이름. `action:routine <name>` 로 호출됩니다. |
| `cadence` | **제안** 주기. SCV 는 이 값으로 스케줄을 등록하지 않습니다 — 호스트 등록 예시에 인용될 뿐입니다. |
| `guardrails` | 실행 중 넘지 말아야 할 경계 목록. 비워 두지 마세요 — 최소한 "permanent 브랜치 직접 쓰기 금지"와 중복 제안 억제(직전 실행에서 거절된 제안 반복 금지)를 담으세요. |
| `exit` | 종료 조건 목록. 루틴 폭주(같은 제안 무한 반복)를 막는 안전판입니다. |
| `report` | `always`(항상 보고) / `on-failure`(문제 발견 시만) / `never`(PR 등 산출물로 갈음). 보고는 `action:report` 형식을 따릅니다. |

## 본문 형식 — 과업 + 가드레일 + 종료 조건 (절차 나열 금지)

본문은 **한 문장~한 단락의 과업 서술**입니다. "1단계 …, 2단계 …" 식의 절차
나열은 금지 — PLAN 문법(plan-grammar)과 동일하게 **경로는 실행하는 에이전트가
정하고, guardrails/exit 가 계약**입니다.

```markdown
---
name: dead-code
cadence: 1d
guardrails:
  - "공개 API·외부 진입점은 참조 0 이어도 제외"
  - "삭제는 반드시 PR 경유 — permanent 브랜치 직접 쓰기 금지"
exit:
  - "제안 PR 발행 또는 후보 없음 확인"
report: never
---

저장소에서 어디서도 참조되지 않는 코드(사용되지 않는 함수·export·파일)를 찾아
제거를 제안하는 PR 을 연다.
```

## 실행 계약 (요약 — 전체는 `action:routine` 프로토콜)

- 루틴은 **permanent 브랜치(main/master/develop 등)에 직접 쓰지 않습니다.**
  변경은 작업 브랜치 + PR, 또는 보고로만 흘러갑니다.
- `report:` 가 켜진 루틴의 결과 요약은 `action:report` 규약을 따릅니다.
- 실행 마지막에 호스트별 스케줄 등록 예시가 안내됩니다 — 등록 자체는 항상
  사용자가 호스트에서 합니다.
