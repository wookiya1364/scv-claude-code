# SCV 재평가 토론 — v0.5.0 시점 (3 개월 후 회고)

> **시뮬레이션 setup**
> 이전 토론 (v0.2.0 시점, 1 주일 사용) 의 **follow-up**. 같은 30 명 결제 서비스 팀이
> v0.2.0 → v0.3.0 → v0.3.1 → v0.4.0 → v0.4.1 → v0.5.0 까지 업그레이드하며 **3 개월 사용**
> 후 같은 6 명이 회고 자리에 다시 모임. 이전 토론의 권장 결정 5 개 중 무엇이 실제
> 코드에 들어갔고, 어떻게 작동했는지 추적. 새 기능 (PR 비디오 자동 첨부 / i18n / GitLab
> MR) 에 대한 첫 평가도 포함.
>
> 시뮬레이션 작성: Claude (head 단일 작성). 모든 페르소나 발언은 v0.5.0 코드·문서·CHANGELOG
> 의 실제 사실에 근거. 약점·강점 모두 진심으로 다룸.
>
> **이전 토론 위치**: 본 파일 끝의 §부록 A (v0.2.0 시점 토론 원본) 참조.

## 참여자 (동일)

| # | 페르소나 | 역할 | v0.2.0 입장 | v0.5.0 입장 |
|---|---|---|---|---|
| 1 | 홍지영 | Tech Lead | 옹호 | **옹호 강화** — "PR 비디오 첨부가 리뷰 시간 진짜 줄였다" |
| 2 | 박민수 | Sr. SWE | 반대 | **조건부 수용** — "fast-path 박혀서 시도 의지 70% 됐다" |
| 3 | 이수진 | PM | 중립 | **약옹호** — "3 개월 데이터 모임. 효익 입증" |
| 4 | 강도현 | Principal | 극렬 반대 | **신중 반대** — "자기참조는 양보. 의존성·secret 관리는 새 우려" |
| 5 | 정유나 | AI Researcher | 극렬 옹호 | **사내 표준 추진** — "GitLab 지원으로 18 팀 합류 가능" |
| 6 | 최우석 | Engineering Manager | 중재자 | 동일 |

---

## §0. 이전 권장 5 개 채택 추적

이전 토론 §Round 4 의 권장 결정이 v0.5.0 시점에 어떻게 됐는지.

| # | 이전 권장 | 채택? | 어디에 어떻게 |
|---|---|---|---|
| 1 | **PROMOTE.md fast-path 명문화** (🔴 높음) | ✅ 채택 | `template/scv/PROMOTE.md §1.6` — 4 가지 기준 + safety nets + ✅/❌ 예시 표 |
| 2 | **Onboarding 가이드** (🟡 중간) | △ 부분 | 별도 `ONBOARDING.md` 없음. 대신 (a) `/scv:help` 의 first-time language setup 4 지선다 (v0.4.0), (b) README hero + 워크플로 ①-⑤ (v0.4.0+), (c) `commands/help.md` 의 dynamic 진단으로 부분 해결 |
| 3 | **회귀 자산 evict 정책** (🟢 낮음, 6 개월 후) | ❌ 미채택 | supersedes / obsolete 마킹은 있지만 자동 evict / down-sample 정책은 없음. 데이터 부족으로 결정 보류 (이전 토론과 동일) |
| 4 | **Telemetry opt-in** (🟡 중간) | ❌ 미채택 | privacy 검토 안 됨. v0.5.0 도 `0.x` SemVer 유지 |
| 5 | **모호한 테스트 prototype 옵션** (🟡 중간) | ❌ 미채택 | `/scv:work` 룰 그대로. 모호 시 사용자에게 다시 물음 |

### 그 사이 추가된 것들 (이전 토론에 없던 영역)

| v | 핵심 추가 | 페르소나에게 재평가 받을 가치 |
|---|---|---|
| 0.3.0 | PR 비디오 자동 첨부 (Playwright + ffmpeg .gif + orphan branch + 자동 cleanup) | 리뷰 효율 / 의존성 비용 |
| 0.3.1 | orphan branch `scv/` subdirectory layout, `attachments_status` 정확 카운트 + 5 분 TTL 캐시, **Playwright 표준화 stance** (Cypress / Puppeteer 는 안내만) | 표준화 강도 / 마이그레이션 부담 |
| 0.4.0 | i18n 인프라 (Language preference 우선순위, `/scv:help` 4 지선다, sh 메시지 영어화) | 글로벌 사용성 / 사용자 화면의 언어 |
| 0.4.1 | commands / template 영어화, Notifier `SCV_LANG` 동적 분기 (영·한·일) | i18n 완성도 |
| 0.5.0 | GitLab MR 자동 생성, `lib/pr-platform.sh` 추상화 (PR/MR backend), commit SHA 기반 screenshot raw URL | 멀티 플랫폼 / secret 관리 |
| - | README mascot + circle hero | 도입 마찰 (정성) |
| - | 회귀 421 PASS / 0 FAIL | 안정성 시그널 |

---

## Round 1 — 3 개월 후 첫인상

**최우석 (중재자)**: 3 개월 사용 후 첫 한 줄. 이전과 어떻게 달라졌는지 중심으로요.

**홍지영 (옹호)**: 가장 큰 변화는 **PR 비디오 자동 첨부**. 리뷰어가 PR 열고 GIF 만 보고도 "아 이거 동작하는구나" 가 1 초에 잡혀요. 우리 팀 평균 리뷰 시간이 1 주일 시점 30 분 → 3 개월 시점 **12 분**. 이게 fast-path 보다도 큰 가치.

**박민수 (반대)**: 이전엔 시도 의지 50% 였는데 fast-path 가 PROMOTE.md §1.6 에 박힌 후 **70%** 까지 갔어요. 그런데 다시 60% 로 내려옴. 이유는 fast-path 의 "1–2 line" 임계점이 실제론 너무 좁아요. 5 줄 짜리 null-guard 도 promote 강제는 부담. 그리고 새로 들어온 의존성 (`ffmpeg`, `jq`, `curl`, `python3`, `gh`) 이 너무 늘었음.

**이수진 (중립)**: **3 개월 데이터** 가졌어요. PR 92 개 / promote 폴더 71 개 / archive 65 개. PLAN 작성 평균 18 분 → **9 분** (학습 효과). 리뷰 평균 30 분 → **12 분** (비디오 효과). 순이익 PR 1 개당 **+9 분**. 머지 후 회귀 발견 사례 2 건 — `/scv:regression` 이 실제로 잡음. 효익 입증.

**강도현 (극렬 반대)**: 이전의 "AI-of-AI 자기참조" 비판은 양보합니다. 3 개월 동안 안 깨졌고 정유나님 말대로 quality gate 는 결정적 bash 였어요. 다만 **두 개 새 우려**: (1) v0.5.0 의 `GITLAB_TOKEN` 이 `.env` 평문 저장. macOS Keychain / `gh auth` 같은 secret backend 미통합. (2) 의존성 5 개 (`ffmpeg`/`jq`/`curl`/`python3`/`gh`) 그래픽으로 보면 도입 마찰이 plugin 한 개 치고 큼.

**정유나 (극렬 옹호)**: **v0.5.0 의 GitLab MR 지원이 게임체인저**. 사내 30 팀 중 18 팀이 GitLab 인데 이전엔 SCV 가 GitHub-only 라 사내 표준 후보 자격 자체가 없었어요. 이제는 후보. `lib/pr-platform.sh` 추상화 보면 Bitbucket / Gitea 도 동일 패턴으로 한 번 더 추가 가능. **사내 1.0 표준 추진 가능 시점**.

**최우석 (중재자)**: 3 개월 데이터 + 새 기능 평가 + 새 우려 정리됐네요. 다음 라운드는 구체 마찰.

---

## Round 2 — 새 마찰 지점 (v0.3+ 기능 중심)

**박민수 (반대)**: PR 비디오 자동 첨부가 좋은 건 동의. 그런데 우리 팀에 macOS 신입이 들어왔는데 `ffmpeg` 안 깔려서 GIF 변환 fail. SCV 는 graceful degrade (`webm` 링크만) 하는 건 잘 짰지만 신입은 자기 PR 만 GIF 미리보기 없는 게 이상해서 슬랙에 물어봄. **표면 균일하지 않음**.

**홍지영 (옹호)**: 그건 onboarding 문서 부재의 잔여물이에요. 이전 토론 권장 #2 가 채택 안 됐죠. README 의 hero 섹션엔 ffmpeg 설치 안내가 없어요. `commands/help.md` 의 dynamic 진단도 ffmpeg 부재는 안 잡고요.

**강도현 (극렬 반대)**: 더 큰 문제. **`GITLAB_TOKEN` 이 `.env` 에 평문**. `template/.env.example.scv` 가 주석으로 "여기 token 박으세요" 하고 있는데 사용자가 실수로 git add 하는 시나리오. SCV 가 `.gitignore` 에 `.env` 박는 보장이 hydrate 단계에 있나요?

**정유나 (극렬 옹호)**: `hydrate.sh` 가 `.gitignore` 도 처리하는지 확인 필요해요. 코드 안 봐서 단언은 못 하고. 다만 본질적 우려는 맞아요 — **secret 관리는 plugin 의 책임 영역**. Linear API token, Slack webhook, GitLab token, AWS keys 다 .env 에 모이는 패턴이 SCV 도입 후 가속됐죠.

**박민수 (반대)**: i18n 이 너무 영어 일변도. v0.4.1 에서 `commands/*.md` 본문이 영어로 됐는데 우리 팀은 다 한국어 화자예요. Claude 가 Language preference 우선순위 보고 한국어로 응답하는 건 OK 인데, 우리가 commands/work.md 를 직접 열어보면 영어. 우리 머릿속 모델은 한국어인데 도구 본문이 영어라 cognitive load 발생.

**홍지영 (옹호)**: 그건 trade-off 였어요. v0.4.1 가 원래 한국어로 박혀있던 commands 본문을 영어로 바꾼 게 정유나님 말한 "사내 18 팀 중 비-한국어 팀" 도입 가능성을 위해서. 한국어 팀에겐 손해, 글로벌 팀에겐 이익. **0.x 단계의 우선순위 결정**.

**이수진 (중립)**: 그래도 backwards compat 은 잘 잡혔어요. archived `TESTS.md` (v0.3.x) 의 `## 실행 방법` / `## 통과 판정` 섹션이 v0.4 의 awk regex `(How to run|실행 방법)` 알터네이션으로 그대로 동작. **3 개월 사이에 한국어로 쌓인 65 개 archive 가 안 깨졌음**.

**강도현 (극렬 반대)**: Cypress / Puppeteer 사용자 마이그레이션 부담. v0.3.1 의 "Playwright 표준화 stance" 가 단호한데 (`pr-helper.sh` 가 `test-results/` 만 스캔, Cypress 의 `cypress/videos/` 는 무시), 우리 사내 18 GitLab 팀 중 7 팀이 Cypress 써요. 자동 마이그레이션은 미채택. 그 7 팀은 SCV 도입 시 Cypress → Playwright 수동 작업 떠안음.

**정유나 (극렬 옹호)**: 그게 의도예요. **표준화는 강제일 때 의미가 있다**. Cypress + Puppeteer 자동 변환은 reliability 가 핵심이라 v0.5.x 또는 별도 plugin 으로 미룬 거고. SCV 가 모든 E2E 도구를 다 지원하면 표준화 가치 0. 7 팀이 마이그레이션 비용 들이는 게 SCV 가 지원해주는 비용보다 커 보이지만, 1 년 단위로 보면 작습니다.

**박민수 (반대)**: 통계 출처는요?

**정유나 (극렬 옹호)**: ...

**최우석 (중재자)**: Round 2 정리하면 (a) `ffmpeg` 같은 의존성 표면이 균일하지 않음 (개별 사용자 환경), (b) `GITLAB_TOKEN` 평문 secret 우려, (c) i18n 의 영어 일변도 trade-off, (d) Cypress / Puppeteer 사용자 마이그레이션 부담. 이 중 (a) 와 (b) 는 plugin 책임이고, (c) 와 (d) 는 의도된 우선순위 결정. 다음 라운드는 가치 추출.

---

## Round 3 — 가치 추출 (3 개월 데이터 + v0.5.0 까지의 진화)

**홍지영 (옹호)**: 이전 토론에선 "PR 1 개당 18 분 들어가서 30 분 절약 → +12 분 순이익" 이 가설이었어요. 3 개월 후 실제 데이터: **PR 1 개당 9 분 들어가서 18 분 절약 → +9 분 순이익**. 가설과 같은 방향이지만 절댓값은 작음. 비디오 첨부 효과로 절약 폭 늘었고, 학습 효과로 작성 시간 줄었음.

**이수진 (중립)**: 3 개월 archive 65 개 + obsolete 마킹 12 개. supersedes 자율 운영 시뮬레이션: **`supersedes` 빠뜨린 PR 8 개**. 이 중 6 개는 `/scv:regression` 의 3-way triage 가 잡았고, 2 개는 archive 가 거짓말 상태로 누적. **이전 토론의 강도현님 우려가 부분 입증** — runtime 안전망이 100% 잡지는 않음.

**강도현 (극렬 반대)**: 거 봐요.

**정유나 (극렬 옹호)**: 100% 못 잡는 건 인정. 그래도 **8 개 중 6 개 잡힘 = 75% 회복률**. 이게 zero (no SCV) 와 비교할 가치. archive 가 거짓말로 누적되는 2 개는 1 년 단위 audit 으로 잡으면 됨.

**홍지영 (옹호)**: archive scale 우려도 데이터 점검. 3 개월 = 65 archive. 회귀 시간: **47 분** (각 평균 43 초 — Playwright 비디오 caputre 이 생각보다 무겁움). 이수진님이 이전 토론에서 "200 archive = 100 분" 우려한 건 맞는 방향. 다만 우리 팀은 `--tag core` 로 critical path (15 archive) 만 8 분에 도는 패턴 자리잡음. **filter 가 핵심**.

**박민수 (반대)**: filter 가 잘 작동한다는 데이터가 우리 팀에서만이에요. 사내 다른 팀은 `--tag` 안 박고 다 돌리는 패턴. SCV 가 tag 자동 추천을 안 함.

**정유나 (극렬 옹호)**: 그건 **사용자 자율 영역**. 도구가 너무 많이 결정하면 trust 떨어짐. 다만 `commands/regression.md` 의 instruction 에 "tag 권장" 한 줄 정도는 더 강조 가능.

**이수진 (중립)**: 비디오 첨부의 storage 측면. 3 개월 = `scv-attachments` orphan branch 누적 약 480MB (65 PR × 평균 7.4MB). 자동 cleanup (retention 3 일) 잘 작동해서 **현재 활성 약 22MB**. orphan branch 의 git history 자체는 누적 (push 마다 commit 추가) 이지만 GitHub 가 leak 안 함. 안정 운영.

**강도현 (극렬 반대)**: orphan branch 의 git history 영구 누적은 1 년 단위로 보면 GitHub 의 packed-refs 무거워질 수 있어요. v0.5.x 에 `git gc --aggressive` 자동 트리거나 quarterly squash policy 가 있으면 좋겠음.

**홍지영 (옹호)**: 좋은 지적. PROMOTE.md 의 fast-path 처럼 명시적 정책이 필요한 영역.

**최우석 (중재자)**: i18n 가치는요?

**정유나 (극렬 옹호)**: **사내 18 GitLab 팀 + 4 일본 자회사 팀** 도입 가능성이 i18n + GitLab 으로 처음 열림. 이전 토론 시점엔 한국어 일변도라 일본 자회사 도입 거론 자체가 안 됐어요. v0.4.0 의 4 지선다 (English/한국어/日本語/Other) + v0.4.1 의 `SCV_LANG` 동적 분기로 **단일 plugin 으로 다언어 팀 동시 운영 가능**. 1.0 진입 조건 중 큰 거 충족.

**박민수 (반대)**: 다언어 동시 운영의 운영 비용은요? 같은 archive 폴더에 한국어 PLAN, 영어 PLAN, 일본어 PLAN 섞이면 입사자가 못 읽어요.

**홍지영 (옹호)**: 그건 팀 정책. SCV 가 강제하지 않고 `.env` 의 `SCV_LANG` 으로 팀별 lock 권장. 우리 팀은 한국어 lock 했고, 일본 자회사는 일본어 lock. 사내 표준 가이드 한 줄 추가하면 충분.

**최우석 (중재자)**: Round 3 종합: (a) 효익 입증 (+9 분/PR 순이익), (b) supersedes 75% 회복률 — 100% 아님 인정, (c) archive scale 은 filter 로 관리됨 (단 자동화 부재), (d) orphan branch storage 는 안정이지만 long-term gc 정책 부재, (e) i18n + GitLab 으로 사내 표준 후보 자격 처음 충족.

---

## Round 4 — 합의 / 분기 / 다음 권장

**최우석 (중재자)**: 3 개월 후 종합.

### §4.1 합의 영역 (전원 동의, v0.5.0 검증)

1. **PR 비디오 자동 첨부 (v0.3.0) 가 리뷰 효율 핵심 가치** — 30 분 → 12 분 데이터로 입증. 이전 토론의 "PLAN 형식이 리뷰 컨텍스트를 풍부하게" 보다 큰 효과.
2. **fast-path (v0.2.1, PROMOTE.md §1.6) 가 도입 마찰을 50% → 70% 로 완화** — 박민수님 데이터.
3. **i18n 인프라 (v0.4.0/4.1) 가 글로벌 도입 자격 충족** — 사내 다언어 팀 동시 운영 가능.
4. **GitLab MR 지원 (v0.5.0) 으로 사내 1.0 표준 후보 자격 충족** — 18 팀 추가 도입 가능성.
5. **Backwards compat 정책 일관 작동** — v0.3.x archived TESTS.md 가 v0.4 awk alternation 으로 그대로 동작.
6. **421 PASS regression suite** — 안정성 시그널 신뢰 가능.

### §4.2 의견 분기 영역 (해소되지 않음)

| 쟁점 | 옹호 측 | 반대 측 |
|---|---|---|
| Playwright 표준화 강도 | 표준화는 강제일 때 의미 | Cypress/Puppeteer 사용자 마이그레이션 부담 |
| i18n 의 영어 일변도 trade-off | 글로벌 팀 도입 우선 | 한국어 팀 cognitive load 증가 |
| supersedes 자율 운영 | 75% 회복률은 zero 와 비교 | 25% 누적은 archive 거짓말 |
| `GITLAB_TOKEN` 평문 .env 저장 | 사용자 책임 영역 | plugin 의 secret backend 미통합은 명백 약점 |

### §4.3 데이터 부족 영역 (6 개월 ~ 1 년 추가 필요)

- 1 년 후 archive scale (현재 65 → 예상 260) 의 회귀 시간이 `--tag` filter 로 관리되는지 vs filter 안 박는 팀에서 폭증하는지
- orphan branch 의 git history 누적이 GitHub 의 packed-refs 어디까지 견디는지
- supersedes 누락 25% 의 1 년 누적 효과 (archive 거짓말 % 가 어디까지 가는지)
- Cypress 사용자 사내 7 팀이 Playwright 마이그레이션 안 하고 SCV 도입 거부할 비율
- 다언어 동시 운영의 archive 가독성 영향 (한국어 / 영어 / 일본어 PLAN 섞임)

### §4.4 권장 결정 (중재자 종합)

이전 토론 권장 5 개 중 **#1 (fast-path) 만 채택**. 나머지 4 개 + 새 우려를 합쳐서 v0.5.0 시점의 새 권장 7 개:

| # | 권장 변화 | 근거 | 우선순위 | 이전 권장과의 관계 |
|---|---|---|---|---|
| 1 | **secret backend 통합** — `GITLAB_TOKEN` / Slack webhook / Linear API 등을 macOS Keychain / `gh auth` / `pass` 등에서 읽도록. `.env` 는 fallback. `hydrate.sh` 가 `.gitignore` 에 `.env` 강제 추가 보장 | Round 2 (b), 명백 약점 | 🔴 높음 | 신규 — 이전 토론 시점엔 token 영역 자체가 없었음 |
| 2 | **fast-path 임계점 확장 검토** — "1–2 line" → "5 line 이하 + 단일 함수" 검토. 또는 "임계점은 팀별 `.env` lock" | Round 1 (박민수 60%), 합의 영역 미해결 잔여 | 🟡 중간 | 이전 #1 의 후속 (fast-path 이미 박혔으니 임계점 조절) |
| 3 | **`commands/help.md` 의 dynamic 진단에 `ffmpeg` / `gh` / `jq` / `curl` / `python3` 부재 감지 + 설치 안내 추가** | Round 2 (a), 신입 균일성 | 🟡 중간 | 이전 #2 (onboarding) 의 부분 구현 |
| 4 | **별도 `docs/ONBOARDING.md` 또는 README walkthrough 섹션** — i18n + GitLab + 비디오 등 v0.3+ 기능 첫 사용 시나리오 | Round 2 (a), 이전 #2 미해결 잔여 | 🟡 중간 | 이전 #2 의 완전 구현 |
| 5 | **orphan branch long-term gc / squash 정책** — quarterly `git gc --aggressive` 트리거 또는 attachments retention 와 묶어서 6 개월마다 squash | Round 3 (강도현), 데이터 부족 영역 | 🟢 낮음 (6 개월 후 재검토) | 신규 — v0.3.0 으로 새로 생긴 영역 |
| 6 | **`commands/regression.md` 에 `--tag` 권장 한 줄 명시** — archive scale 이 filter 의존이라 권장 필요 | Round 3 (박민수 vs 정유나), 합의 영역 잔여 | 🟡 중간 | 이전 #3 (회귀 evict) 의 완화 형태 |
| 7 | **Telemetry opt-in (이전 #4 미해결, 1.0 진입 결정 근거)** — privacy 검토 후 v0.6 또는 v1.0 | Round 4 §4.3 데이터 부족 영역 모두 | 🟡 중간 (privacy 검토 필요) | 이전 #4 그대로 |

### §4.5 비채택 (의도적, v0.2.0 비채택과 부분 겹침)

- **Cypress / Puppeteer 자동 마이그레이션** — Playwright 표준화 stance 와 충돌. 정유나님 의견 채택. 별 plugin 후보.
- **모호한 테스트 prototype 옵션 (이전 #5)** — 3 개월 운영 결과 모호 차단이 회귀 0 → 2 발견에 기여. 강도조절 불요.
- **PLAN.md ↔ Linear ↔ GH PR DRY 통합** — 1.0 까지 미룸 (이전 비채택과 동일).

---

## §5. 마무리 발언

**박민수**: fast-path 박혀서 60% 까지 왔어요. fast-path 임계점 확장 + secret backend 통합되면 80% 갑니다.

**홍지영**: 비디오 첨부의 효과는 가설을 넘어선 데이터로 입증됨. ffmpeg 의존성 onboarding 만 해결되면 개인적 가치 평가 9/10.

**이수진**: 3 개월 데이터 +9 분 순이익 입증. 1 년 시점에 archive scale + 다언어 동시 운영 영향 다시 봅니다.

**강도현**: 자기참조 비판은 양보 유지. **secret backend 통합** + **orphan branch gc 정책** 2 개가 들어오면 사내 표준 후보로 인정.

**정유나**: GitLab MR 으로 사내 18 팀 + 일본 자회사 4 팀 도입 가능. **1.0 진입 시점에 telemetry opt-in 결과 + 사내 표준 합의**가 동시에 와야 의미 있음. v1.0 까지 6 개월 가속 권장.

**최우석 (중재자)**: 토론 종료. **🔴 #1 (secret backend 통합) 이 v0.5.0 시점 가장 명확한 다음 액션**. #2 / #3 / #4 / #6 은 v0.5.x – v0.6 로 분산. #5 / #7 은 6 개월 데이터 + privacy 검토 후 1.0 결정. 이전 토론 권장 #1 (fast-path) 가 입증된 가치를 만들었으니 이번 권장 #1 (secret backend) 도 같은 무게로 진행 권장.

---

## §6. 사용자에게 묻는 것 (v0.5.0 시점)

이 토론 결과 다음 release 에 어떤 변화를 반영할지는 사용자 결정. v0.2.0 시점과 형식 동일:

| # | v0.5.0 권장 | 후보 release |
|---|---|---|
| 1 | secret backend 통합 (`GITLAB_TOKEN` / Slack webhook 등) | v0.5.1 또는 v0.6.0 |
| 2 | fast-path 임계점 확장 + 팀별 `.env` lock | v0.5.x (PROMOTE.md 만 수정) |
| 3 | `commands/help.md` 의존성 부재 감지 | v0.5.x (help.sh 만 수정) |
| 4 | `docs/ONBOARDING.md` 또는 README walkthrough | v0.5.x – v0.6 |
| 5 | orphan branch gc 정책 | 6 개월 후 데이터 보고 |
| 6 | `regression.md` 의 `--tag` 권장 | v0.5.x (commands/regression.md 만 수정) |
| 7 | telemetry opt-in (privacy 검토 → 1.0) | v0.6 – v1.0 |

또는 토론에서 빠진 다른 우려 (예: `s3` / `r2` 백엔드, Bitbucket / Gitea, ralph-loop 영역) 가 있으시면 페르소나 추가 / 라운드 추가로 더 시뮬레이션 가능합니다.

---

# 부록 A. v0.2.0 시점 토론 원본 (1 주일 사용 시점, 2026-04 초)

> 이전 토론 보존. 본 v0.5.0 재평가의 §0 권장 5 개 채택 추적과 비교용.

## 참여자

| # | 페르소나 | 역할 | 한 줄 입장 |
|---|---|---|---|
| 1 | 홍지영 | Tech Lead | **옹호** — "PLAN/TESTS 형식이 의외로 리뷰를 빠르게 했다" |
| 2 | 박민수 | Sr. SWE | **반대** — "또 새로운 워크플로 도구. 우리는 이미 Linear + GH PR 잡혀있다" |
| 3 | 이수진 | PM | **중립** — "비용 vs 효익 데이터를 보고 싶다" |
| 4 | 강도현 | Principal | **극렬 반대** — "AI 도구를 AI 가 만든 protocol 로 검증? 자기참조 함정" |
| 5 | 정유나 | AI Researcher | **극렬 옹호** — "이게 표준이 안 되면 6개월 후 우리도 PR 50개/일 됨" |
| 6 | 최우석 | Engineering Manager | **중재자** — 합의/분기 정리, 결정 안 권장 |

## Round 1 — 첫 인상 (1 주일 사용 후)

(원본 발언 보존 — 본 파일 이전 버전 §Round 1 참조. 핵심 발언 요약만 아래에)

- 홍지영: PLAN.md scaffold 4 섹션이 리뷰 시간 절반.
- 박민수: Linear + GH PR + PLAN = 같은 정보 3 사본 (DRY 위반).
- 이수진: 1 주 PR 12 / promote 8 / archive 6 / 회귀 발견 0 / promote 작성 18 분 추가.
- 강도현: AI-of-AI 자기참조 무한루프 우려.
- 정유나: quality gate 는 결정적 bash 라 자기참조 아님. PR 50 개/일 사례 막을 유일 메커니즘.

## Round 2 — 실제 마찰 지점 (요약)

- 팀 문화 강제력 부재 (4 명 중 1 명만 raw 활용).
- 모호 테스트 차단의 양면성 (quality gate vs prototype 부담).
- 작은 변경 fast-path 부재 (전원 동의 약점).
- PLAN 작성 시간 (학습 곡선 첫 회 40 분 → 6 회 째 10 분).

## Round 3 — 가치 추출 (요약)

- 1 년 archive 200 개 = 회사 자산 vs 거짓말 우려.
- supersedes / obsolete 마킹 매번 선언 부담.
- 1 년 회귀 시간 폭증 vs filter 로 관리 가설.
- 0.x SemVer 시그널의 정직성.

## Round 4 — 합의 / 분기 / 권장 5 (요약)

| # | 권장 | 우선순위 | v0.5.0 시점 채택? |
|---|---|---|---|
| 1 | PROMOTE.md fast-path 명문화 | 🔴 높음 | ✅ |
| 2 | Onboarding 가이드 | 🟡 중간 | △ 부분 |
| 3 | 회귀 자산 evict 정책 | 🟢 낮음 | ❌ |
| 4 | Telemetry opt-in | 🟡 중간 | ❌ |
| 5 | 모호 테스트 prototype 옵션 | 🟡 중간 | ❌ |

비채택: AI-of-AI 형이상학 비판 (실제 quality gate 는 결정적), PLAN ↔ Linear ↔ GH PR DRY 통합 (1.0 까지 미룸), 모호 테스트 강제 우회 (정유나 의견 채택).

— **부록 A 끝**.
