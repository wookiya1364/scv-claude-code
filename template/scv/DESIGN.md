---
name: design
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team-fe", "@team-design"]
tags: [standard, core, ui-ux]
standard_version: 1.0.0
merge_policy: preserve
optional_when: "no user-facing UI"
---

# DESIGN — UI/UX 스펙

> **이 문서는 사용자 대면 UI(웹/앱)가 있는 프로젝트에만 필요**합니다. CLI/백엔드 전용 프로젝트는 `status: N/A` 로 표시하고 건너뜁니다.
> Claude 는 `INTAKE.md` 단계 3 과 아래 `How to elicit` 를 따라 사용자에게 물어 채웁니다.

## How to elicit (Claude 가 물어볼 순서)

1. **적용 여부**: "UI 가 있나요? 없으면 이 문서를 건너뜁니다." (없으면 `status: N/A` 기록)
2. **페르소나**: "주 사용자 페르소나는 누구인가요? (1~3명, 목표·제약·사용 빈도)"
3. **핵심 플로우**: "페르소나가 이 시스템에서 수행하는 **가장 중요한 여정**은? (관찰 가능한 시작·끝 사이의 단계)"
4. **화면 목록**: "각 플로우는 어떤 화면들을 거치나요? (경로·제목·목적)"
5. **상태머신**: "화면 중 **여러 상태가 있는 복잡한 화면**이 있나요? 각 상태 전이는?"
6. **디자인 토큰**: "색상·간격·타이포 토큰이 이미 있나요? 없으면 이 프로젝트에서 정의할 건가요?"
7. **접근성**: "접근성 기준이 있나요? (WCAG 등급, 키보드 전용, 스크린리더)"
8. **에러·빈 상태**: "오류·권한 거부·빈 데이터 상황의 UX 원칙은?"

## Completion criteria

- [ ] 적용 여부 결정 (`status: active` 또는 `N/A`)
- [ ] (해당 시) 페르소나 최소 1명
- [ ] (해당 시) 핵심 플로우 최소 1개
- [ ] (해당 시) 화면 목록 최소 1개 + 각 화면 목적
- [ ] (해당 시) 디자인 토큰 출처 명시
- [ ] (해당 시) 접근성 기준 합의
- [ ] 사용자가 "이 설계로 진행해도 좋음" 확인

## Structure

### 1. 페르소나

<TODO: 1~3명. P1, P2 형태로 코드 부여.>

### 2. 핵심 플로우

<TODO: F1, F2 … Mermaid sequenceDiagram 권장.>

### 3. 화면 목록

| ID | 경로 | 제목 | 목적 | 주 페르소나 |
|---|---|---|---|---|
| <TODO> | ... | ... | ... | ... |

### 4. 화면 상태머신

<TODO: 상태가 복잡한 화면만. Mermaid stateDiagram.>

### 5. 디자인 토큰

<TODO: Figma URL / 토큰 패키지 경로. 주요 카테고리만 요약.>

### 6. 접근성

<TODO: WCAG 등급, 키보드, 스크린리더, 마이크·카메라 권한 대체 플로우(해당 시).>

### 7. 에러·빈 상태 UX

| 상황 | 표기 | 행동 유도 |
|---|---|---|
| <TODO> | ... | ... |

## 관련 모듈

<!-- MODULES:AUTO START applies_to=design -->
<!-- MODULES:AUTO END -->
