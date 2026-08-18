---
name: raw-intake
version: 1.1.0
status: active
last_updated: 2026-08-04
tags: [raw, intake, guide]
standard_version: 1.0.0
merge_policy: overwrite
---

# scv/raw — 자유 투입 공간

> 이 디렉토리는 **아무거나 던져 넣는 곳**입니다. 회의록·설계 스케치·이미지·PDF·녹화·초안·경쟁사 분석·외부 링크 스크랩 — 전부 환영합니다.
> 형식·정리·분류 신경 쓰지 마세요. `action:promote` 가 알아서 정리 제안을 해 줍니다.

## 쓰는 법 (두 줄 요약)

1. **던진다**: 파일을 `scv/raw/` 아무 위치에 저장한다. 파일명만 의미 있게.
2. **그대로 둔다**: 지우지 마세요. Raw 는 역사(history)입니다. 승격(`action:promote`)에 사용된 파일은 SCV 가 `scv/raw/stale/` 로 옮겨 보관합니다 (내용 불변).

## 라이프사이클: unused → stale

| 위치 | 의미 |
|---|---|
| `scv/raw/` 바로 아래 (stale 밖) | **unused** — 아직 어떤 promote 에도 사용되지 않은 문서 |
| `scv/raw/stale/` | **consumed** — 승격에 사용된 문서. 어떤 계획(slug)들이 사용했는지 `scv/readpath.json` 의 `ref_docs` 에 누적 기록됩니다 |

- 이동은 `action:promote` Step 8 (`readpath.sh consume`) 만 수행합니다 — 손으로 옮기거나 지우지 마세요.
- 한 문서가 여러 기능에 재사용되면 `ref_docs` 의 slug 배열에 계속 쌓입니다.
- `action:status` 가 unused 목록과, 소비 후 코드가 바뀌어 내용이 낡았을 수 있는 문서(`OUTDATED-CANDIDATE`)를 보여줍니다.

## 허용 형식

제한 없음. 예시:
- `.md` — 노트, 회의록, 초안
- `.png`, `.jpg`, `.svg` — 스케치, 와이어프레임, 스크린샷
- `.pdf` — 계약서, 논문, 외부 자료
- `.mp4`, `.webm` — 화면 녹화, 데모
- `.txt`, `.json`, `.yaml` — 로그, 샘플 데이터
- `.mermaid`, `.puml` — 다이어그램 소스

## 선택: frontmatter 또는 파일명 규칙

강제 아님. 있으면 승격 시 SCV 가 더 잘 분류합니다.

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

### 방법 A (권장) — SCV 에 맡기기

```
action:promote
```

- SCV 가 `scv/raw/` 의 unused 문서 전체를 훑어 주제별 승격 후보를 제안
- 각 후보마다 사용자 확인(**Approve / Edit / Skip / Defer**)
- 승인한 것만 `scv/promote/<YYYYMMDD>-<author>-<slug>/` 폴더에 `PLAN.md` + `TESTS.md` 로 생성 (`status: planned` 으로)
- PLAN.md 의 `raw_sources` frontmatter 에 원본 경로 자동 기록
- **Raw 원본은 절대 삭제하지 않음** — 사용된 원본은 `scv/raw/stale/` 로 이동(내용 불변)하고 `ref_docs` 에 사용 이력이 남음

옵션:
- `action:promote --source "scv/raw/2026-04-*"` — 특정 파일만 대상
- `action:promote --topic feature-onboarding` — 주제 힌트
- `action:promote --dry-run` — 제안만, 파일 생성 안 함

### 원자료가 아직 없다면

`action:promote` 는 다듬을 것이 없으면 거절합니다. 아이디어만 있는 상태라면
대화부터 시작하세요:

```
action:help "<하려는 것 한 줄>"
```

대화가 충분히 구체화되면 그 자리에서 `action:promote` 로 넘어가고, 대화 기록이
`raw_sources` 에 남아 출처가 역추적됩니다.

계획 폴더를 손으로 만들지 마세요. 파일 모양은 같아도 원자료 소비(`readpath.sh
consume`)와 출처 기록이 빠지기 때문에, 나중에 "이 계획이 무엇에서 나왔는지" 를
되짚을 수 없습니다. 작업 공간 가드도 손으로 만든 계획 파일 생성을 거부합니다.

## 금지 사항

- **비밀번호·토큰·개인정보** — 절대 raw 에 커밋 금지. `.env.example` 에도 실제 값 금지
- **압축 파일** (`.zip`, `.tar.gz`) — 풀어서 넣으세요
- **너무 큰 바이너리** (> 50MB) — git 저장소 팽창. 외부 스토리지 + 링크로
