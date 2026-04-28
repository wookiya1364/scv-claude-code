---
name: agents
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team-ai"]
tags: [standard, optional, ai, agents]
standard_version: 1.0.0
merge_policy: preserve
optional_when: "no probabilistic AI components (LLM/STT/TTS/classifier)"
---

# AGENTS — AI 에이전트 스펙 (선택 문서)

> **이 문서는 프로젝트에 LLM/STT/TTS/분류기 등 확률적 구성요소가 있을 때만 채웁니다.** 해당 없으면 `status: N/A` 로 표시하고 건너뜁니다.
> Claude 는 `INTAKE.md` 단계 4 와 아래 `How to elicit` 를 따릅니다.

## How to elicit (Claude 가 물어볼 순서)

1. **적용 여부**: "이 시스템에 확률적(비결정론적) AI 구성요소가 있나요?" — 없으면 `status: N/A` 후 종료
2. **에이전트 목록**: "어떤 역할의 에이전트가 몇 개 있나요? (이름·역할을 한 줄씩)"
3. **입출력 계약**: "각 에이전트의 입력·출력 데이터 형태는?"
4. **모델·제공자**: "모델/제공자가 이미 정해졌나요, 아니면 선택해야 하나요?"
5. **SLA**: "지연·비용·정확도 목표는?"
6. **프롬프트 관리**: "프롬프트를 파일로 버저닝할 건가요? 경로 규칙은?"
7. **검증 가능성**: "각 에이전트 출력이 어떻게 **검증 가능**한가요? 결정론적 스냅샷 가능? 아니면 분포 기반?"
8. **가드레일**: "유해성·PII·금지 토픽 필터가 필요한가요?"
9. **롤백 절차**: "모델·프롬프트 변경 시 어떤 기준으로 롤백하나요?"

## Completion criteria

- [ ] 적용 여부 결정 (`status: active` 또는 `N/A`)
- [ ] (해당 시) 에이전트 목록 최소 1개 + 입출력·SLA
- [ ] (해당 시) 프롬프트 저장 경로 규칙 합의
- [ ] (해당 시) 검증 방식(결정론/분포)을 각 에이전트마다 결정
- [ ] (해당 시) 가드레일 필요 여부 결정
- [ ] (해당 시) 롤백 기준 기록
- [ ] 사용자가 "이 에이전트 스펙으로 진행해도 좋음" 확인

## Structure

### 1. 에이전트 목록

| 에이전트 | 모델/제공자 | 역할 | 입력 | 출력 | SLA |
|---|---|---|---|---|---|
| <TODO> | ... | ... | ... | ... | ... |

### 2. 프롬프트 저장·버저닝

<TODO: 경로 규칙 (예: `prompts/<agent>/<version>.md`), major/minor/patch 기준, active 심볼릭 링크 정책.>

### 3. 확률적 동작 검증 기준

> 각 에이전트마다 아래 중 **최소 하나** 선택.

- **결정론 테스트** (가능 시): temperature=0 + 고정 시드 + 스냅샷 비교
- **분포 테스트**: 동일 입력 N회 실행, assertion 의 `min_ratio` 기준

Assertion 타입 레퍼런스:

| 타입 | 용도 |
|---|---|
| `contains_any` / `contains_all` | 키워드 포함 |
| `not_contains` | 회피 금지 |
| `regex_match` | 정규식 |
| `semantic_similarity` | 임베딩 기반 의미 유사도 |
| `latency_p95` | 지연 분포 |
| `tool_called` | 함수 호출 여부 |
| `schema_valid` | 구조화 출력 스키마 |

시나리오 템플릿:

```yaml
- id: <TODO>
  agent: <TODO>
  scenario: "<TODO: 사용자 입력/상황>"
  input: {}
  runs: 20
  assertions:
    - type: <TODO>
      ...
      min_ratio: 0.9
```

### 4. 골든셋 회귀

<TODO: 경로, 통과율 임계치, 실행 주기.>

### 5. 유해성·PII 가드

<TODO: 필요 여부·룰셋 경로·테스트 방법.>

### 6. 모델·프롬프트 교체·롤백 절차

<TODO: 카나리 단계, 롤백 조건(통과율/지연/불만).>

### 7. 오케스트레이션

<TODO: 에이전트 간 호출 순서, 타임아웃, 폴백. 단일 에이전트면 생략.>

## 관련 모듈

<!-- MODULES:AUTO START applies_to=agents -->
<!-- MODULES:AUTO END -->
