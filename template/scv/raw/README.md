---
name: raw-intake
version: 1.0.0
status: active
last_updated: 2026-04-20
tags: [raw, intake, guide]
---

# scv/raw — 자유 투입 공간

> 이 디렉토리는 **아무거나 던져 넣는 곳**입니다. 회의록·설계 스케치·이미지·PDF·녹화·초안·경쟁사 분석·외부 링크 스크랩 — 전부 환영합니다.
> 형식·정리·분류 신경 쓰지 마세요. `/scv:promote` 가 알아서 정리 제안을 해 줍니다.

## 쓰는 법 (두 줄 요약)

1. **던진다**: 파일을 `scv/raw/` 아무 위치에 저장한다. 파일명만 의미 있게.
2. **그대로 둔다**: 지우지 마세요. Raw 는 역사(history)입니다.

## 허용 형식

제한 없음. 예시:
- `.md` — 노트, 회의록, 초안
- `.png`, `.jpg`, `.svg` — 스케치, 와이어프레임, 스크린샷
- `.pdf` — 계약서, 논문, 외부 자료
- `.mp4`, `.webm` — 화면 녹화, 데모
- `.txt`, `.json`, `.yaml` — 로그, 샘플 데이터
- `.mermaid`, `.puml` — 다이어그램 소스

## 선택: frontmatter 또는 파일명 규칙

강제 아님. 있으면 승격 시 Claude 가 더 잘 분류합니다.

**A. 파일명에 날짜·주제 힌트**
```
2026-04-17-design-review-notes.md
2026-04-18-customer-interview-v2.pdf
sketches-onboarding-flow.png
```

**B. `.md` 상단에 간단 frontmatter**
```yaml
---
author: "@seongUk"
date: 2026-04-17
topic: onboarding
related_uc: [UC-001]
---
# 회의 메모
...
```

**C. 하위 폴더로 묶기** (회의·워크숍·세션 단위)
```
scv/raw/
├── 2026-04-17-design-review/
│   ├── notes.md
│   ├── whiteboard-01.jpg
│   └── whiteboard-02.jpg
└── 2026-04-20-customer-workshop/
    ├── transcript.md
    └── user-journey.pdf
```

## Raw → Promote 승격 (정제)

Raw 자료 중 팀이 "이건 공식화하자" 라고 합의한 것은 `scv/promote/<topic>/` 로 **정제본을 작성**합니다.

### 방법 A (권장) — Claude 에게 맡기기

```
/scv:promote
```

- Claude 가 `scv/raw/` 전체를 훑어 주제별 승격 후보를 제안
- 각 후보마다 사용자 확인(**Approve / Edit / Skip / Defer**)
- 승인한 것만 `scv/promote/<topic>/index.md` 로 생성 (`status: draft` 로)
- `raw_sources` frontmatter 에 원본 경로 자동 기록
- **Raw 원본은 절대 삭제·이동하지 않음**

옵션:
- `/scv:promote --source "scv/raw/2026-04-*"` — 특정 파일만 대상
- `/scv:promote --topic feature-onboarding` — 주제 힌트
- `/scv:promote --dry-run` — 제안만, 파일 생성 안 함

### 방법 B — 수동 작성

1. 주제 디렉토리 생성 (예: `scv/promote/feature-onboarding/`)
2. `index.md` 에 frontmatter + 요약
3. 필요 시 `design.md`, `api.md`, `assets/*` 추가
4. frontmatter 에 `raw_sources: [scv/raw/...]` 로 출처 역추적

## 금지 사항

- **비밀번호·토큰·개인정보** — 절대 raw 에 커밋 금지. `.env.example` 에도 실제 값 금지
- **압축 파일** (`.zip`, `.tar.gz`) — 풀어서 넣으세요
- **너무 큰 바이너리** (> 50MB) — git 저장소 팽창. 외부 스토리지 + 링크로
