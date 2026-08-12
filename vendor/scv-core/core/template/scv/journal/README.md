---
name: journal-guide
version: 1.0.0
status: active
last_updated: 2026-08-07
tags: [journal, attribution, append-only]
standard_version: 1.0.0
merge_policy: preserve
---

# scv/journal — 작성자 귀속 저널 (대화·작업 원문)

> feature 단위 검증(promote→work→archive)이 담지 못하는 **프로젝트 수준 맥락**을
> 여기에 축적합니다. 대화 원문·작업 로그는 journal 에, 구조화된 결정·할일은
> `scv/DECISIONS.md` / `scv/TODO.md` 에 — 하이브리드 방식입니다.

## 커밋 여부 — 기본은 올리지 않음 (v0.23.0+)

hydrate 가 `.gitignore` 에 `scv/journal/` 을 넣습니다. **기본값은 로컬 보관**입니다.

`scv/conversations/` 에는 계획으로 이어진 대화만 남지만, journal 에는 훅이
자유대화까지 전부 받아씁니다. 그것을 저장소에 올릴지는 저장소가 공개인지,
팀 규모가 어떤지에 따라 달라지므로 사용자가 정합니다.

팀 맥락으로 공유하려면 `.gitignore` 에서 `scv/journal/` 줄을 지우세요.
**지우기 전에 저장소 공개 범위와 지금까지 쌓인 내용을 먼저 확인하세요** —
아래 redaction 은 휴리스틱이라 패턴 밖 비밀은 걸러지지 않습니다.

한 번 커밋한 뒤에는 `.gitignore` 를 다시 넣어도 이미 추적 중인 파일은 빠지지
않습니다. `git rm --cached scv/journal/<file>` 로 추적을 끊어야 하고, 그래도
과거 커밋에는 내용이 남습니다.

## 파일 규약

- 파일명: `<YYYYMMDD>-<author>.md` — **일 단위 · 사용자 단위 분리**.
  같은 날 두 사람이 기록하면 파일이 두 개 — 다인 동시 작업의 git 충돌을
  원천 차단합니다.
- 블록: `### [HH:MM:SS] <speaker>` 아래에 해당 턴의 내용.
- `author` 해석: `git config user.name` → `$GIT_AUTHOR_NAME` → `$USER` 순
  (`core/scripts/lib/author.sh`). **모든 기록은 작성자 귀속 — 익명 항목 금지.**

## 쓰는 법

수동 기록·프로토콜 기록 모두 `journal-append.sh` 를 거칩니다:

```bash
echo "결제 한도 정책을 논의함" | bash "$SCV_CORE_ROOT/scripts/journal-append.sh" --speaker user
```

호스트 훅이 등록된 환경(wrapper 소유 — `core/template/hooks/` 의
`on-user-prompt.sh` / `on-stop.sh`)에서는 자유대화의 사용자 프롬프트와
어시스턴트 응답 요약이 자동으로 append 됩니다. **훅이 없는 호스트에서는
자유대화가 캡처되지 않습니다** — 세션 종료 시 요약 기록으로 부분 보완되는
알려진 격차입니다.

## Redaction — 비밀 마스킹 (통과 없이 저장 금지)

`journal-append.sh` 는 기록 전에 다음 패턴을 `[REDACTED]` 로 마스킹합니다:
`password/passwd/pwd/secret/token/api[_-]?key` 의 값, `Bearer <토큰>`,
`AKIA…` (AWS access key).

**redaction 은 휴리스틱입니다** — 패턴 밖 비밀은 남을 수 있습니다.
`scv/raw/` 와 동일한 규약이 병행 적용됩니다:

- **비밀번호·토큰·개인정보를 journal 에 쓰지 마세요.** 마스킹은 안전망이지
  허가가 아닙니다.
- 실수로 커밋된 비밀은 즉시 로테이트하고 git 이력을 정리하세요.
- journal 을 커밋하기로 했다면 이 항목이 특히 중요합니다 — 자유대화가 전부
  들어오므로 무엇이 쌓이는지 주기적으로 확인하세요.

## Append-only

- 기존 블록의 수정·삭제 금지. 정정도 새 블록으로 append 합니다.
- 파일이 비대해지면 월 단위 아카이빙은 후속 계획입니다 — 임의로 지우지 마세요.
- 드물게 충돌이 나면(같은 파일 동시 편집) **둘 다 보존(union merge)** 합니다.
