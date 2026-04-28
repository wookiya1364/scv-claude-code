---
name: ralph-prompt
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team"]
tags: [ralph, entrypoint]
standard_version: 1.0.0
merge_policy: preserve
---

# RALPH_PROMPT — <프로젝트 이름>

> Ralph Loop 의 얇은 진입점. 이 파일은 **프로젝트별** 로 채워야 합니다. 명세 원천은 `INTAKE.md` 를 통해 완성된 표준 문서들입니다.
> **선행 조건**: 이 파일을 채우기 전에 `INTAKE.md` 의 단계 1~7 이 완료되어 모든 필수 표준 문서가 `status: active` 여야 합니다.

## How to elicit

1. "현재 이터레이션에서 집중할 **Phase 이름**은?" (예: "Phase 2 — 음성 코어")
2. "패키지 매니저는?" (npm / pnpm / yarn / pip / uv / cargo …)
3. "개발 서버 실행 명령?" / "빌드 명령?" / "테스트 명령?" / "E2E 명령?" / "의존성 설치 명령?"
4. "이번 이터레이션에서 특별히 주의할 점·이전 실패 원인·우회 전략은?"

## Completion criteria

- [ ] `focus_phase` 가 한 줄로 명시됨
- [ ] 모든 명령어 필드가 실제 동작하는 명령으로 채워짐 (또는 "해당 없음" 명시)
- [ ] `iteration_notes` 에 현재 컨텍스트 기록

---

## 표준 문서 위치

- `./INTAKE.md` — 대화 프로토콜 (수정 안 함)
- `./DOMAIN.md` — 도메인
- `./ARCHITECTURE.md` — 구조
- `./DESIGN.md` — UI/UX (해당 시)
- `./AGENTS.md` — AI 에이전트 (해당 시)
- `./TESTING.md` — 검증
- `./REPORTING.md` — 협업툴
- `./promote/*` — 승격된 주제·계획 문서

## 이번 실행에서 집중할 것

focus_phase: <TODO: 예: "Phase 1 — 인프라">

iteration_notes: |
  <TODO: 이번 이터레이션의 맥락·주의사항·이전 실패 요약>

## 프로젝트 고유 설정

package_manager: <TODO>
install_command: <TODO>
dev_command: <TODO>
build_command: <TODO>
test_command: <TODO>
e2e_command: <TODO>

## 검증 도구

- Playwright 설정 규약·아티팩트 경로는 `./TESTING.md` 참조
- Chrome DevTools MCP 사용 규약도 `./TESTING.md` 참조

## 보고

- 협업툴은 `.env` 의 `NOTIFIER_PROVIDER` 로 선택
- 보고는 **반드시 `/scv:report <phase> <status>` 슬래시 커맨드**로만 수행
- 채널 매핑은 `./REPORTING.md` 기준

## 종료 조건 (DONE 선언 기준)

1. 모든 Phase 가 `./TESTING.md` 의 성공 기준 통과
2. 각 Phase 완료 직후 `/scv:report "<phase>" passed` 응답이 `OK <thread_ref>`
3. 해당 시 `AGENTS.md` 의 분포 테스트·골든셋 통과율 임계치 이상

## 추가 참고

<TODO: 링크·이슈·이전 결정사항·외부 문서>
