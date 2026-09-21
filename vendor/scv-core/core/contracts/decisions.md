# Contract — 결정 로그 (decisions)

결정은 `scv/DECISIONS.md` 에 쌓인다. 이 문서가 그 로그의 규칙을 적는 **유일한** 본문이다 — 프로토콜은 이 문서를
가리키고 자기 지점의 엔트리 모양만 갖는다(`scv/SCV.md` Top-level rules 4조: 같은 요구는 한 곳에만).

## 왜

결정은 세 지점에서 **자동으로** 쌓인다 — 계획 승인(promote), 보관(work), 폐기 판정(regression). 세 프로토콜이 같은
설명(append-only · 시드 · 형식 · 스크립트 · 색인)을 각자 길게 갖고 있어 규칙 헌법 검사 (b) 가 중복으로 잡았다
(2026-09-21, 미결 4). 규칙은 여기 한 곳, 지점별 차이(verdict 값과 필드)는 각 프로토콜에.

## 무엇을

1. **append-only** — 기존 엔트리는 고쳐 쓰지 않는다. 파일이 없으면 sync 액션이 시드한다.
2. **형식은 핸드오프 결정 형식** — `## [<YYYY-MM-DD HH:MM>] <author> — <제목>` 헤더 아래 `verdict` · `why` · 지점별
   필드(`discarded alternatives` / `path delta` / `refs` / `conversation`).
3. **author 는 필수** — 익명 엔트리는 없다. `git config user.name` → `GIT_AUTHOR_NAME` → `USER` 순으로 정한다.
4. **스크립트로만 쓴다** — `scripts/decisions-append.sh`. 손으로 쓰면 형식이 흔들리고 색인이 남지 않는다.
5. **색인** — 스크립트가 엔트리의 위치를 `scv/INDEX.tsv` 에 적어, 결정 하나를 로그 전체를 열지 않고
   `record-read.sh --key <이름>` 으로 읽는다. 성숙한 프로젝트의 로그는 이미 수백 줄이다.

## 어디서 가리키나

promote(계획 승인) · work(보관) · regression(폐기)의 결정 로그 절. 각 절은 스크립트 호출 한 블록과 자기 엔트리
블록을 갖고, 규칙은 이 문서를 참조한다.

## 검사

- `core/tests/run-dry.sh` [16]: 세 프로토콜에 엔트리 헤더 형식과 "author is mandatory" 가 있다.
- `core/tests/test-rule-constitution.sh` 검사 (b): 로그 규칙의 본문이 두 문서 이상에 있으면 기준선을 넘는다.
