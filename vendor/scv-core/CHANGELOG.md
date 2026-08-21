# Changelog

All notable changes to SCV Core are documented here.

## [0.31.2] - 2026-08-21

### 기록 훅의 바이트 자르기가 한글을 반으로 — journal 은 항상 온전한 UTF-8

on-stop.sh 가 답변 꼬리를 tail -c 4000(바이트)으로 잘라 한글·일본어·이모지 한
글자 중간에서 끊겼고, 일지 첫머리의 깨진 바이트 하나가 편집기에서 파일 전체를
"다 깨진" 것처럼 보이게 했다(실제 프로젝트 실측 59KB 중 1곳). 캡 뒤 반쪽
시퀀스를 떨어낸다 — iconv -c(바이트를 버리면 exit 1 이므로 출력으로 판단), 없으면
python3, 둘 다 없으면 원문. test-journal [6u]: 긴 한글 답변 → 일지 유효 UTF-8 +
꼬리 생존. 정리는 POSIX 도구만으로(head/tail/od 로 선두 연속 바이트 제거) 하고
iconv -c 는 있을 때만 두 번째 패스 — macOS(BSD) iconv 는 깨진 입력에 아무것도
내놓지 않아 첫 구현이 그쪽 CI 에서 실패했다.

## [0.31.1] - 2026-08-21

### run-dry 배치 가드 — 래퍼 투영에서도 TEMPLATE_VERSION 검사가 돈다

0.31.0 의 run-dry [15q] 가 core/TEMPLATE_VERSION 과 루트 복사본을 비교했는데,
Claude 래퍼는 페이로드를 자기 루트에 투영해 run-dry 를 돌리므로 부모 복사본이
없다 — 래퍼의 core-sync 검증이 그 한 줄로 실패해 0.31.0 봇 PR 이 열리지 않았다
(Codex 래퍼는 vendor/ 아래에서 돌려 통과). 루트 복사본이 있을 때만 비교하고 없으면
단일 복사본 배치로 통과한다. 교훈: Core 의 테스트는 저장소 배치가 아니라 페이로드
배치를 전제해야 한다(래퍼가 그대로 돌린다). 가드: 부모에 TEMPLATE_VERSION 없는
복사본 배치에서 run-dry FAIL 0.

## [0.31.0] - 2026-08-21

### 쉬운 말 2단계 — 답의 모양, 매 턴 전달, .env 스위치

0812 의 "쉬운 말 먼저" 규칙은 문체 조언이라 지켜지지 않았다 — 답의 모양을
정하지 않았고, `/scv:*` 명령 안에만 있어 일반 대화에는 한 줄도 전달되지
않았으며, 어겨도 검사가 없었다. 세 가지를 한 번에 고친다.

- 13개 프로토콜의 `## Plain language first` 본문을 **답의 모양**으로 교체
  (제목 유지 — 누적 회귀 T4 호환, 13곳 바이트 동일): 먼저 1–2문장 → 예시
  하나 → 묻기 전 코드값 금지 → 자세한 건 원할 때. 사용자가 행동에 필요한
  식별자(다음 명령·생성 파일)는 요약 뒤에 그대로. 좋은 답/나쁜 답 예시 한 쌍
  포함. help 대화 모드는 매 턴 "짧은 답 → 예시 → 질문 하나"(one question per
  turn).
- `core/template/hooks/on-user-prompt.sh` 가 SCV 프로젝트에서 매 턴 답의 모양
  요약(5줄)을 stdout 으로 낸다 — Claude Code·Codex 모두 이 이벤트의 stdout 을
  모델 컨텍스트에 넣는다(공식 문서 확인, 2026-08-21). 기록(journal)·비차단
  보장은 그대로, 요약은 journal 에 쓰지 않는다. 등록은 래퍼 소유(§6): Claude
  Code 래퍼는 이미 등록돼 Core 반영만으로 켜지고, Codex 래퍼는
  `UserPromptSubmit` 등록이 따라붙는다.
- `.env` `SCV_PLAIN_LANGUAGE` 스위치 — 없음/`on`/그 밖의 값 = 켜짐, `off`
  (대소문자 무관)만 꺼짐. 꺼지면 훅은 침묵하고 프로토콜 절은 첫 줄 규칙으로
  스스로 비켜선다. `.env.example.scv` 에 기본 on 으로 문서화. 템플릿
  `scv/SCV.md` 에 "How SCV talks to you" 절. 예시 루틴 `plain-language-audit`
  추가(내장 예시 8 → 9). TEMPLATE_VERSION 2.2.0 → 2.3.0 — 기존 프로젝트는 다음
  액션 때 autosync 로 자동 수령.
- 가드: run-dry [15p]/[15q] (앵커 7종·위치·옛 문구 부재·help 매 턴·템플릿·
  버전 일치·루틴), test-journal [6p] (훅 on/off/OFF/따옴표/이상값/미적용/journal
  오염 없음/비차단), test-routines (새 예시 lint). 어블레이션 재측정:
  promote 241/919 (26.2%), work 222/678 (32.7%).
- 문장 수 스위치 — `.env` `SCV_PLAIN_MAX_SENTENCES=<n>`(양의 정수)이 있으면
  "먼저 1–2문장"의 상한이 n 이 된다. 없음/이상값은 2, `SCV_PLAIN_LANGUAGE=off`
  가 우선. 13개 프로토콜 본문에 한 문장(제목·앵커·동일성 유지), 훅 요약은
  숫자를 치환해 찍는다(`1` 은 "one sentence"). `.env.example.scv`·`SCV.md` 한
  줄씩, TEMPLATE_VERSION 은 2.3.0 그대로(미출시 판, 같은 릴리스). 가드:
  run-dry 앵커, test-journal [6p] 값별(4·1·abc·0·-3·2.5·빈값·off 우선).
- 한계(그대로): 모델이 실제로 쉽게 말하는지 자동 보장하는 테스트는 없다 —
  archive 직전 사람 판정 3건으로 닫는다(TESTS T7).

### 회귀 러너의 경로 표시 누수 — 시나리오는 자기 scv 경로를 본다

위 계획의 보관 계약이 누적 회귀에서 처음 돌며 드러낸 러너 결함. 러너가 시작할
때 export 하는 경로 표시(SCV_DIR·RAW_DIR·STATE_FILE·PROMOTE_DIR·ARCHIVE_DIR)가
자식 시나리오에 상속돼, 임시 프로젝트 안의 헬퍼가 이 저장소의 scv/ 를 봤다
(run-dry [19] 이 러너 안에서만 실패, 단독 972/972). 0818 의 SCV_AUTOSYNC_RUNNING
누수와 같은 자리에서 같은 방식으로 — run_scenario_clean 이 자기 표시 5개를 더
빼고 시나리오를 돌린다. 사용자 env 는 그대로. test-regression-env T5 추가.

## [0.30.0] - 2026-08-19

### .env.example.scv 자동 최신화 — root 불가침의 명명된 예외

"root 는 user-owned, sync 는 손대지 않는다"는 원칙 때문에, 옛날에 hydrate 한
프로젝트는 새 `.env` 옵션의 문서 블록을 영영 받지 못했다. 0.29.0 의
SCV_EFFORT_MODE 가 공백을 구체화했다 — unset 은 auto 라 동작은 무해하지만,
사용자가 `cp .env.example.scv .env` 하라고 안내받는 바로 그 파일에서 ask/off
모드의 존재를 발견할 수 없다.

예외는 이 파일 하나다. hydrate 가 루트에 심은 파일이니 SCV 소유로 재분류하고,
기존 장치에 그대로 태웠다 — basename 정책 한 줄(overwrite)과
process_template_file 호출 하나가 새 코드의 전부다. HEAD 가 복원 못 하는
수정은 DIRTY 로 거부(--force 만 오버라이드), 부재 시 재생성(삭제가 조용한
opt-out 이 되지 않도록), scv/ 심볼링크면 패스 전체와 함께 스킵, 거부 시
스탬프 미전진으로 다음 액션이 재시도한다. `.env` 자체는 절대 쓰지 않는다.
TEMPLATE_VERSION 2.1.0 → 2.2.0 이 마이그레이션 트리거 — 기존 프로젝트는
다음 액션 시작 시 autosync 로 자동 수령하며 별도 명령이 없다.
신규 스위트 test-sync-env-example.sh 10 시나리오 23 단언 (Red 13 → Green).

### 회귀 러너의 autosync 가드 누수 — 시나리오는 깨끗한 환경에서 돈다

위 계획의 아카이브 직전 누적 회귀가 잡아낸 러너 자신의 결함. 러너는 시작할 때
재진입 방지 표시(SCV_AUTOSYNC_RUNNING=1)를 export 하는데, 그 표시가 러너가
실행하는 모든 시나리오에 상속됐다 — autosync 훅 자체를 검증하는 아카이브
계약(sync-autopilot)이 러너 안에서만 10/11 적색, 깨끗한 환경에서는 21/21.
오염 환경 주입으로 10/11 이 정확히 재현됐다.

수정은 실행 지점 하나: run_scenario_clean 이 자식 환경에서 그 표시만 지운다
(env -u). 러너 프로세스 자신의 표시는 유지되어 재진입 방지가 살아 있고,
사용자가 export 한 env(SCV_AUTOSYNC=off 포함)는 그대로 통과한다. 스위트와
scvroot.sh 는 무수정 — 스위트가 호출자의 누수를 방어하면 다음 호출자의 같은
버그를 가리기 때문이며, 이 맹점은 계획의 Risk 로 남겼다. 검증 함정 하나도
기록됐다: 러너 자체를 고치는 플랜의 누적 회귀는 repo 의 runner 로 돌려야
한다 — 플러그인 캐시 runner 는 배포본이라 수정이 실릴 수 없다.
신규 스위트 test-regression-env.sh 6 시나리오 9 단언, 누적 회귀 11/11 복원.

## [0.29.0] - 2026-08-18

### effort governor — 작업 무게에 맞춰 알아서 돈다

"가벼운 작업에도 항상 최대 강도가 돌아 비용 낭비"라는 지적에서 시작했다. 세션의
effort 다이얼은 사용자 소유라 건드리지 않는다 — 건드릴 필요도 없었다. 비용의
지배항은 다이얼이 아니라 **오케스트레이션**이다(실측: 팬아웃 1회 40만~130만
토큰). 그래서 실행 방식을 판정에 맞춘다.

**판정은 백테스트를 통과한 것만.** 아카이브 14건 전부에 후보 규칙을 소급
적용했다(판독 14 에이전트 + 종합 1). 살아남은 것은 셋뿐이다: `effort_class:`
선언이 항상 이기고, `parallel_groups` 는 orchestration, 래퍼 후속 언급은 heavy,
나머지는 standard — 13/14 적중, 유일 미스는 과소 방향이라 그 신호 조합(2-of-3)
이 자동 승급을 미리 장전한다. 그럴듯했지만 데이터가 기각한 규칙들은 의도적으로
없다: 시나리오 수(0개짜리가 heavy 4건, 21개짜리가 standard), Guardrails 수
(역상관), light 밴드 예측(실측 0건).

**집행은 밴드×단계 격자.** 무게는 작업이 아니라 단계에 붙는다 — 기계 단계는
항상 최저, 종합은 차저, 구현·검증만 밴드를 따른다. 핵심 규칙 하나:
**standard 판정 계획에서는 다중 에이전트 팬아웃을 띄우지 않는다.** 자동 승급은
위로만: 같은 단계 적색 2회나 반박 반복이면 재승인 없이 한 밴드 위로, 검증 중
강등은 없다. `SCV_EFFORT_MODE=auto|ask|off` — off 는 분류기 호출 자체가 없는
완전 무동작이다. 모든 아카이브가 (판정·실사용·승급)을 기록해 다음 백테스트의
데이터가 된다.

**첫 판정 대상은 이 계획 자신이었다.** heavy(armed) — 정책대로 팬아웃 대신 단일
강검증으로 갔고, 그 검증이 결함 셋을 잡았다: CRLF 가 frontmatter 신호를 숨기고
(orchestration 을 standard 로 읽는 비싼 방향), raw_sources 경로 순회로 저장소
밖 파일이 계측되고(20KB 실증 — 첫 픽스처는 scv/raw 부재로 우연히 안전해
보였다), 무효 선언이 소리 없이 사라졌다. 전부 수정하고 T10 으로 고정했다.
그리고 BSD sed 의 \| 무지원에 두 번째로 걸렸다 — guard.sh 에 적어둔 그 교훈
그대로, -e 3개로.

### TESTS 내구성 규칙 (0.28.0 보수 건의 재발 방지)

PROMOTE.md 의 TESTS 체크리스트에 "How-to-run 은 아카이브된 뒤에도 참"이 박혔다
— 커밋 상태 단언 금지, PR 이 싣지 않는 파일 참조 금지, 슬러그 안 전체 스위트
재실행 금지. tests-smell.sh 가 두 냄새를 경고한다(경고 전용). 영원히 빨갛던
아카이브 4건을 만든 바로 그 병의 백신이다.

## [0.28.0] - 2026-08-18

### sync 가 사본을 만들지 않는다 — 복구 경로는 git 하나다

`sync.sh` 는 한 파일 안에서 "이전 내용은 어떻게 되찾나"에 두 가지 답을 하고
있었다. 은퇴 문서 삭제 패스는 "git 이력이 복구 경로"라며 백업 없이 지웠고, 템플릿
덮어쓰기는 `.scv-backup/<타임스탬프>/` 에 사본을 쌓았다 — 그것도 `.gitignore` 에
들어가는, 추적 안 되는 사본을.

이제 답이 하나다. **git 이 되살릴 수 있는 파일은 바꾸고, 못 되살리는 파일은 이름을
불러 거부한다.** 수정-미커밋, 스테이징, 미추적, gitignore 대상, 그리고 git 저장소가
아닌 프로젝트의 모든 상이 파일이 `DIRTY` 로 보고되고 건드려지지 않는다.
`--force <파일>` 이 preserve 우회와 같은 방식으로 이 거부도 우회한다.

merge-on-markers 파일(SCV.md)의 판정 기준도 바로잡았다. hydrate 가 버전·날짜
스탬프를 찍으므로 손대지 않은 프로젝트도 원본 템플릿과는 영원히 다르다 — "템플릿과
다른가"가 아니라 **"머지가 이 파일을 바꾸는가"** 를 묻는다. 머지를 시뮬레이션하고
스탬프 구간을 중립화해 비교한다. 이걸 안 했더니 갓 수화한 프로젝트의 첫 sync 가
거부 보고로 뒤덮였다 — 테스트가 출시 전에 잡았다.

### 낡은 템플릿은 다음 액션이 알아서 메운다

"update 하면 문서 포맷도 자동 최신화"가 요구였는데, update **안에서는** 불가능하다.
플러그인 payload 는 버전별로 캐시되므로 update 시점의 세션은 옛 payload 의 sync 를
물고 있다 — 거기서 sync 를 부르면 옛 템플릿을 다시 깔고 "완료"라고 찍는다.

그래서 격차는 **다음 액션**이 메운다. `lib/scvroot.sh` 의 `scv_autosync` 가 액션
시작 시 프로젝트 스탬프와 payload `TEMPLATE_VERSION` 을 비교해서, 프로젝트가
낡았으면 그 자리에서 sync 를 돌리고 stderr 한 줄로 보고한다. sync 가 끝에서
스탬프를 다시 찍으므로 한 번이면 수렴한다.

안 도는 경우가 도는 경우만큼 중요하다:

- **미도입/미수화 프로젝트** — 자동 sync 가 수화를 대신하지 않는다
- **pre-2.x 레거시** — 2.0.0 은퇴 패스가 사용자 문서 7종을 지우는데, 프로토콜은
  삭제 전 DECISIONS.md 이관 제안을 요구한다. 그 대화를 건너뛸 수 없으므로 한 줄
  안내만 낸다
- **프로젝트가 payload 보다 새로울 때** — 동료가 먼저 업데이트한 프로젝트를 옛
  세션이 "새로고침"하며 되돌리면, 두 기계가 서로의 템플릿을 영원히 뒤집는다.
  위로만 간다. (9.9.9 스탬프 픽스처가 2.1.0 으로 돌아오는 걸 테스트가 잡았다)
- 재귀 금지, `SCV_AUTOSYNC=off` (환경변수만), 실패는 경고 후 액션 계속

`update` 프로토콜 5항("동기화는 별도 sync 액션으로")을 이에 맞게 개정했다. `sync`
액션은 수동 재실행과 레거시 대화형 마이그레이션용으로 남는다.

### 가드 실효 3건

**`SCV_GUARD_SCRIPTS` 가 콜론 목록을 받는다.** 고정 문자열 한 개로는 어댑터 자기
스크립트 디렉터리를 실을 수 없어서, Codex 의 어댑터 라우팅 액션 4개가 영수증을 전혀
발급하지 못했다 — 계약(guard.md)이 요구하는 것을 변수 구조상 지킬 수 없었다.
항목별로 기존과 동일한 고정 문자열 비교를 유지한다. 글로브도 정규식도 없다.

**영수증 저장소를 못 쓸 때, 닫힌 채 말한다.** fail open 으로 돌리지 않았다 — 셸
도구가 저장소를 chmod 할 수 있으므로 열리는 실패는 가드 해제와 같다. 고친 것은
침묵이다. mint 실패는 stderr 한 줄을 남기고, gate 의 거부 사유는 "액션을 실행하라"
(같은 저장소에 발급하므로 무익) 대신 저장소 경로와 `SCV_GUARD_STATE` 안내를 담는다.

**그 버그를 감춘 테스트 둘을 실효화했다.** T15 는 면제 대상(`README.md`)으로
검사해서 가드가 뭘 하든 통과했고 — 계약의 틀린 fail-open 서술이 살아남은 이유다 —
비면제 경로와 새 사유 단언으로 바꿨다. T21 은 아카이브로 이동한 계획 문서를
조건으로 삼아 영영 돌지 않았고, 두 스크립트(guard·provenance 게이트)의 면제 집합
직접 비교로 바꿨다.

### 래퍼 투영본이 어느 배치에서든 돈다

`test-guard.sh` 는 루트를 `<파일>/../..` 로 잡아 Core 배치에서만 맞았다.
claude-code 래퍼(투영: `tests/` + `vendor/scv-core/core/`)에서는 한 단계 위를
가리켜 13 케이스가 실패했는데, **어느 CI 도 그 파일을 돌리지 않아** 빨간 채로
보이지 않았다. 후보 탐색으로 바꾸고, 시뮬레이션한 래퍼 배치에서 전체 스위트를
재생하는 T30 을 넣었다. 새 스위트 둘(test-autosync·test-sync-dirty)도 같은 해석을
쓴다.


### 출시 전 적대 검증이 잡은 것 — 33건 중 배송 차단급 셋

네 렌즈(작업 소실·수렴·가드 공격·계약 정합)로 구현을 공격시켰고, 셋은 그대로
나갔으면 실전 사고였다.

**심링크 관통 덮어쓰기.** `git status` 는 추적된 심링크를 깨끗하다고 보고하고,
`cp` 는 링크를 관통해 **저장소 밖 파일**에 쓴다 — 검증자가 853줄짜리 파일을 이
경로로 실제로 날렸다. 더티 판정을 상태 조회에서 **HEAD 와의 내용 비교**로 바꿨다:
심링크·미추적·gitignore·`assume-unchanged` 전부 "git 이 못 돌려준다" 쪽으로
떨어진다. 심링크된 `scv/` 디렉터리는 템플릿 패스 전체를 한 줄 경고와 함께 건넌다.

**거부됐는데 스탬프가 전진.** DIRTY 로 한 파일이 거부돼도 끝의 스탬프 블록이
버전을 새로 찍어서, 프로젝트는 옛 템플릿인 채 "완료" 도장이 박히고 자동 최신화는
**영원히 침묵**했다 — 사용자가 더트를 치운 뒤에도. 이제 거부가 하나라도 있으면
스탬프는 제자리이고, 보고는 "refreshed" 가 아니라 **PARTIAL** 이며, 다음 액션이
재시도한다. 스탬프 쓰기 자체도 보고 라인(`STAMP`)을 남긴다 — "(none)" 이 거짓말이
되지 않도록.

**deny JSON 제어문자 주입.** 거부 사유에 payload 의 파일 경로가 들어가는데, 경로에
제어문자를 넣으면 훅 출력이 JSON 으로 깨진다 — 판정 불능은 허용과 같다. 경로는
공격자가 정하는 값이므로 제어문자를 제거한다. "사유는 고정 문자열"이라던 주석도
사실이 아니었기에 고쳤다.

나머지 중 값진 것: sync 가 방금 쓴 자기 발자국(미커밋) 때문에 다음 새로고침이
스스로 막히던 것(스탬프 구간 중립화로 해소), 액션 하나가 하위 헬퍼마다 검사를
반복하던 것(프로세스 트리 가드로 1회), `SCV_GUARD_SCRIPTS` 의 공백·상대경로 항목이
**모든 명령에 매치**되던 것(절대경로 강제), 영수증 파일만 못 쓰는 모양도 같은
정직한 사유를 받도록, 프리릴리스 버전 비교(semver tie-break).

한 건은 **의도적으로 반영하지 않았다**: 은퇴 문서 7종의 무백업 삭제에 거부를
넣자는 지적. 그 삭제는 기록된 사용자 결정이고, 프로토콜이 삭제 전 DECISIONS.md
이관 제안을 강제하며, 자동 새로고침은 pre-2.x 에 아예 닿지 않는다. 규칙 주석에
예외를 명시하는 것으로 답했다.

> 래퍼 후속: codex hooks.json 콜론 목록 채택(+ 두 항목 환경 대칭), claude-code CI 에
> test-guard.sh 등록. Core 벤더링 뒤 각 래퍼 PR 로 나간다.


## [0.27.0] - 2026-08-14

### 승격이 초록인 채로 실패하던 것

0.26.0 승격에서 `promote.yml` 이 두 번 3초 만에 포기하고, 두 번 다 손으로 머지했다.
원인은 대기 조건이었다. **체크가 몇 개 존재하는지**를 물었는데, 경로 필터로 건너뛴
매트릭스 잡이 **확장되지 않은 이름 그대로** 목록에 먼저 올라온다. 그래서 개수는 즉시
1이 되고, 대기가 끝나고, `gh pr checks --watch` 는 "완료된 항목 하나"를 보고 성공을
돌려주고, 정작 필수 체크는 아직 생기지도 않은 상태에서 머지가 거부된다.

이 블록이 틀린 건 두 번째다. 처음엔 **체크가 통과했는지**를 물었는데 `gh pr checks` 는
하나라도 대기 중이면 0이 아닌 값으로 끝나므로 대기 내내 "아직"으로 읽혔다. 두 번의
오답이 서로 반대 방향이라, 이번엔 판정을 GitHub 자신에게 넘겼다 — 머지를 결정하는
그 값(`mergeStateStatus`)을 그대로 본다. 세 가지가 모두 성립해야 머지한다: 실패한
체크가 없고, 도는 체크가 없고, GitHub 이 더 이상 `BLOCKED` 이라 하지 않을 것.

`CLEAN` 만 요구하면 반대쪽 함정에 빠진다. 아까 그 건너뛴 자리표시자가 상태를 계속
`UNSTABLE` 로 붙잡아서 아무것도 머지되지 않는다. 그래서 조건이 세 개다.

`tests/test-promote-wait.sh` 가 워크플로에서 이 블록을 **잘라내 그대로 실행**한다.
문자열 검사가 아니다 — 실제로 문제가 됐던 그 rollup 을 재생한다. 옛 코드에서 10개,
새 코드에서 0개 실패한다.

> 이 수정은 **다음** 릴리스부터 듣는다. `workflow_dispatch` 는 기본 브랜치의
> 워크플로 파일을 실행하므로, 이 릴리스 자체는 아직 옛 로직으로 승격된다.

### 벤더 게이트 — Core 를 손으로 심는 것을 막는다

0.25.0 과 0.26.0 에서 같은 일이 반복됐다. 릴리스 브랜치에 버전 올리는 김에 Core 트리도
같이 복사해 넣었고, 봇이 연 동기화 PR 은 도착하자마자 "이미 반영됨"이 되어 닫혔다.

문제는 중복이 아니라 **두 경로가 같은 일을 하지 않는다**는 것이다. 봇은 게시된 릴리스
아티팩트를 해석해서 canonical 과 materialized 해시를 둘 다 기록한다. 손으로 복사하면
그 시점 작업 트리에 있던 것이 기록된다. 작업 트리가 깨끗했을 때만 같은 결과고, 나중에
둘을 구분할 방법이 없다.

`core/scripts/check-vendor-provenance.sh` 가 머지 시점에 막는다. `*/vendor/scv-core/`
를 건드리는 PR 은 봇 브랜치이거나, 릴리스 체인이거나, 제목에
`[manual-vendor: <이유>]` 를 달아야 통과한다 — 기존 `[no-plan: <이유>]` 와 같은 모양.
Core 계약이 바뀌면 봇이 못 따라오는 경우가 실제로 있으므로 금지가 아니라 **선언**이다.

### `check-provenance.sh` 에 처음으로 테스트가 붙었다

머지를 막는 게이트인데 검증이 없었다. 실패 방향이 양쪽 다 조용하다 — 안 막게 된
게이트는 "아무도 위반하지 않는 저장소"와 구별되지 않고, 다 막게 된 게이트는 처음
막힌 사람이 발견한다.

`core/tests/test-provenance-gates.sh` 가 두 게이트를 **실제 git 저장소** 픽스처로
검증한다(각 9개). 스텁이 아닌 이유는 검증 대상에 diff 를 읽는 방식 자체가 포함되기
때문이다. 마지막 케이스는 두 게이트가 무언가를 실제로 거부하는지 확인한다 — 첫 줄에서
0으로 끝나는 스크립트는 통과 케이스를 전부 통과시킨다.

## [0.26.0] - 2026-08-13

### 데크 재설계 — 다크 전용, 그리고 읽히는 다이어그램

"디자인이 심각하게 구려서 쓸 엄두가 안 난다"는 지적에서 시작했다. 재보니 지적이
맞았고, 원인은 보이는 것과 달랐다.

#### 다이어그램

색 문제로 접수됐지만 더 큰 절반은 **크기**였다. SVG 가 `width="100%"` 와 max-width 를
그대로 들고 있어서 1388px 그래프가 840px 칼럼에 0.483 배로 눌렸고, 16px 글자가
**7.7px** 로 나왔다. 팔레트를 아무리 고쳐도 안 고쳐지는 문제다.

색이 얼어붙은 이유는 mermaid 가 팔레트를 세 겹으로 굽기 때문이다 —
`#mermaid-<타임스탬프>` 로 묶인 내부 스타일, 거기 붙은 `!important`, 그리고
`classDef` 노드의 인라인 `style="fill:… !important"`. 마지막 것은 어떤 스타일시트로도
못 이긴다(실험으로 확인). `static-mermaid.mjs` 가 구운 SVG 에서 셋을 다 벗겨내
평범한 규칙으로 칠할 수 있게 만든다.

팔레트 자체는 **산문에 박혀 있었다**. `promote.md` 가 모델에게 모든 펜스에
`%%{init}%%` 를 붙여넣게 하고, 그게 렌더러를 이긴다. 데크가 읽는 사본에서만 떼어낸다
— 디스크의 `.md` 는 그대로라 GitHub 렌더링이 유지되고, 그 파일이 회귀 픽스처가 된다.

| | 전 | 후 |
|---|---|---|
| 배율 | 0.483 | 0.997 @1920 · 0.656 @1440 |
| 글자 | 7.73px | 16px |
| 화살표 대비 | 1.21:1 (라이트) | 14.10:1 |
| 노드 테두리 | 2.95:1 | 3.69:1 |
| 잘린 라벨 | 25 | 0 |

라벨 잘림은 원인이 둘 더 있었다. mermaid 에 `fontFamily:"inherit"` 를 줬는데 그건
폰트 **이름이 아니라서** 폭을 못 재고 라벨마다 200px 을 박았다. 그리고 다이어그램이
`<pre>` 안에 있어 `white-space:pre` 가 라벨까지 상속돼, mermaid 가 두 줄로 잡아둔
상자에서 텍스트가 줄바꿈을 거부했다.

#### 다크 전용

화면은 다크 하나다. 라이트 토큰 세트와 테마 토글을 지웠다. 라이트 값은 독자가 닿을
수 없는 `@media print` 한 곳에만 남는다 — SCV 데크는 PR 옆 `scv/archive/` 에 놓이고
리뷰어가 인쇄한다. 전에는 흰 종이에 검은 판이 20 쪽 찍혔다.

토큰은 대표님 DesignSystem 의 `.dark` 램프(shadcn oklch → sRGB, 전부 무채색)다.
브랜드 장미는 **두 값**으로 쓴다: `#a50036` 은 칠하고, 글자는 `#fc7184` 다. 하나로는
둘 다 못 한다 — `#a50036` 을 글자로 쓰면 2.50:1 이다.

크롬은 스크롤에서 꺼내 3 행 그리드로. 내용 전 높이 268px → 108.8px. 목차는 알약
19 개가 감기던 154px 격자에서 34px 한 줄로.

#### 초록이었지만 망가져 있던 것 셋

- **`static-mermaid.mjs` 가 Chrome 149 에서 한 바이트도 못 내놓고 있었다.** 그래서 모든
  데크가 구운 SVG 대신 CDN 로더를 실어 보냈고, 메시지는 "offline? CDN blocked?" 로
  엉뚱한 곳을 가리켰다. 출력을 죽이는 조건이 둘인데 재시도 사다리가 하나만 바꿨다.
- **`font:<굵기> <크기>/1 inherit` 5 곳이 문법 오류**였다. `font` 축약형은 family 자리에
  `inherit` 를 못 받아 선언 전체가 버려지고, 컨트롤 6 개가 13.333px/400/Arial 로 떴다.
- **`--muted` 를 12 개 소비처 전부에서 글자색으로** 쓰고 있었다. shadcn 에서 그 이름은
  표면이다.

#### 측정으로 검증한다

`core/tests/deck-probe.mjs` 를 새로 넣었다. 빌드된 데크 사본에 측정 스크립트를 주입해
브라우저에서 **계산된 스타일과 실제 기하**를 읽는다. 위 숫자는 전부 여기서 나왔다.
문자열 고정 검사는 버려진 선언으로 가득한 스타일시트를 151 개 단언 전부 통과시켰다.

프로브가 내 실수도 둘 잡았다. `--border-strong` 를 페이지 배경 기준으로만 재고 실제로
놓이는 노드 위(2.12:1)를 안 봤던 것, 그리고 프로브 자신이 숨은 페이지의 요소를 재서
0px 이라고 보고하던 것.

#### 이식하지 않은 것

`ScreenSlide` 의 주석 칸, `Flow`, `TransitionList`, `SchemaTable`. 사람이 써넣는 프롭을
먹는 컴포넌트인데 마크다운에 그 데이터가 없다. 산문에서 지어내면 규약 위반이다.
Inter 는 임베드하지 않는다 — 한글이 없어 한 문장 안에서 글꼴이 갈리고, 한글까지 넣으면
promote 마다 커밋되는 파일이 3~7 배로 붓는다.

## [0.25.1] - 2026-08-12

### 가드 테스트가 벤더된 트리에서 거짓 실패하던 것 수정

`test-guard.sh` 의 T19 가 `tests/test-host-neutral.sh` 를 무조건 불렀다. 그 파일은
Core 저장소 소유이고 배포 payload 에 들어가지 않는다 — 래퍼 CI 는 `core/` 만 임시
디렉터리에 복사해서 돌리므로, 파일이 없는 것이 "호스트 누출"로 보고됐다. codex 의
"Vendored SCV Core regressions" 가 이것 때문에 빨갛게 떴다.

파일이 없으면 건너뛰는 대신 **가드 스크립트 자체의 중립성을 직접 검사**한다. 이
스위트가 다루는 대상이 바로 그 파일이고, 저장소 하네스 없이도 확인 가능하기
때문이다.

금지 문자열 목록은 실행 시점에 조립한다. 그대로 적으면 `core/` 안에 리터럴이
남아, 중립성을 단언하는 테스트가 스스로 그 규칙을 어긴다.

## [0.25.0] - 2026-08-12

### scv 명령 호출을 기계적으로 강제한다 (가드 훅)

지금까지 SCV 는 LLM 이 scv 명령을 쓰도록 **강제하지 못했다**. 전부 설명문이었고,
모델이 안 쓰기로 고르면 그만이었다. 이번 릴리스는 `PreToolUse` 훅으로 실제 거부를
건다.

- **Rule A (기본 켜기)** — 영수증 없이 `scv/promote/<slug>/` 의 `PLAN.md`,
  `TESTS.md`, `FEATURE_ARCHITECTURE.md` 를 **새로 만드는 것**을 거부한다. 이미 있는
  파일 수정은 언제나 허용 — `<TODO>` 채우기와 상태 전이가 정상 경로다.
- **Rule B (기본 켜기)** — 세션에 영수증이 없으면 `scv/` 밖 파일 쓰기를 거부한다.
  면제: `*.md`, `.gitignore`, `.gitattributes`, `LICENSE`, 호스트 설정.
- **영수증** — 호스트가 스스로 발생시키는 이벤트로만 발급된다. 모델이 훅 이벤트를
  위조할 수 없으므로 "진짜 scv 명령이 돌고 있다"는 사실은 조작되지 않는다.
  15 개 명령 **전부**가 발급한다.
- 두 호스트 다 동작한다. Codex 는 매니페스트 `hooks` 키 없이 플러그인 루트의
  `hooks/hooks.json` 기본 경로로 로드된다(codex-cli 0.146.1 에서 실증).

**정직한 한계**: 이 가드가 보장하는 것은 "이 세션에서 SCV 를 썼다" 이지 "이 쓰기가
계획된 작업이다" 가 아니다. 읽기 전용 명령 하나로도 세션이 열린다 — 그게 오탐 0 의
대가다. 계획 여부는 아래 CI 게이트가 머지 시점에 본다. 그리고 모델이 파일을
하나도 안 건드리고 말로만 때우는 대화는 훅의 사정권 밖이다.

### 프로버넌스 게이트 — 계획 없는 구현 PR 이 머지되지 않는다

`core/scripts/check-provenance.sh` 가 PR 이 **추가한** `scv/archive/*/PLAN.md` 를
검사한다. `scv/promote/` 가 아니라 `scv/archive/` 를 보는 이유는, work 가 PR 을 열기
전에 아카이브하기 때문이다 — promote/ 만 보는 검사는 정작 감시해야 할 PR 에서 볼
것이 없다.

면제: `stage`/`main` 대상 릴리스 체인 PR, `chore/core-*` 봇 PR, 문서만 바꾼 PR,
그리고 제목의 `[no-plan: <이유>]`. 대괄호가 비어 있으면 예외로 인정하지 않는다.

### 초록이지만 망가져 있던 것 세 가지

- `check-frontmatter.sh` 가 CI 에서 **실제 저장소를 한 번도 검사하지 않았다.**
  합성 픽스처로만 돌고 있었다. 이제 `core-ci.yml` 이 저장소 자신에게 돌린다.
- 그 검사의 glob 이 `scv/promote/*/PLAN.md` 뿐이라, promote/ 가 비면
  `✓ All frontmatter valid` 로 통과했다. 같은 시점에 아카이브된 계획 8 개는 한 번도
  검사된 적이 없었다. glob 에 `scv/archive/*/PLAN.md` 를 더했다.
- `test-routines.sh` 가 래퍼에서 항상 실패하고 있었다 — Core 기준 경로를 그대로
  복사해서 `actions.json` 을 못 찾았다. CI 가 이 파일을 돌지 않아 아무도 몰랐다.

### 문서가 가드와 모순되지 않는다 (그리고 앞으로도)

배포되는 Core 문서에서 "명령 없이 해도 된다"고 사인하던 문장을 정리했다. 빠른
경로는 **없애지 않고** `action:work --fast "<intent>"` 로 선언하게 만들었다 —
정상 예외와 실패 모드가 둘 다 "작은 커밋에 promote 폴더 없음"이라 구분이 안 됐는데,
선언 하나가 그 둘을 가른다.

`tests/test-guard-consistency.sh` 가 이 정합성을 고정한다. 영어와 한국어를 함께
훑고(한국어 전용 문서가 11 개다), 예외는 `file:line` 앵커로만 인정하며, 앵커가
가리키는 문구가 사라지면 실패한다. 명령 토큰 기반 면제는 쓰지 않는다 —
`"via action:promote or by hand"` 가 면제돼버리기 때문이다.

`core/actions.json` 에 16 번째 명령을 더하면 `core/contracts/guard.md` 에 가드 결정을
기록할 때까지 CI 가 빨갛다.

### 그 밖에

- `core/scripts/env-set.sh` — `.env` 한 줄을 이식성 있게 쓰는 새 스크립트.
  `sed -i` 없이, `&` `/` `\` 가 든 값도 원문 그대로 보존한다. 프로토콜 네 곳의
  손수 `.env` 편집 지시가 이 호출로 바뀌었다.
- `help` 프로토콜의 순서 자기 차단이 닫혔다. 언어 설정 `.env` 쓰기가 첫 헬퍼
  호출보다 **앞서** 있어서, 영수증 기반 호스트에서 프로젝트 첫 사용이 벽돌이 됐다.
  이제 그 쓰기 자체가 첫 스크립트 호출이다.
- `test-guidance.sh` 의 phase-1 범위 단언 제거. 작업 트리 vs HEAD 비교라 CI 에서는
  트리가 항상 깨끗해 한 번도 발동하지 않고, 로컬에서는 promote/work 외 프로토콜을
  건드리는 모든 작업에 거짓 실패를 냈다.

## [0.24.0] - 2026-08-12

### CI 가 3분 30초에서 30초대로 (테스트만 변경, 동작 무변경)

- `Contracts` 잡의 208초 중 184초를 `tests/test-deck-runtime.sh` 하나가 쓰고 있었다.
  나머지 7개 테스트를 합쳐도 24초다. **macOS 러너는 원인이 아니었다** — 오히려
  ubuntu(208초)가 macOS(115초)보다 느렸다.
- 원인 1: `make_dead_pid()` 가 죽은 PID 를 얻으려고 `sleep 30 &` 을 띄우고
  `kill` 한 뒤 `wait` 했다. 신호가 갓 fork 된 자식에게 닿지 못하면 `wait` 이
  sleep 의 수명을 통째로 기다린다 — 호출 5곳 중 1곳에서 30초를 실제로 잡아먹었고
  나머지 4곳은 1밀리초였다. 즉 **느린 게 아니라 플레이키**했다. 신호에 의존하지
  않고 `( exit 0 ) &` 로 스스로 끝나게 바꿨다.
- 원인 2: 경쟁 테스트가 legacy `dist-deck` 에 파일 **4000개**를 만들었다. 복사가
  descriptor-relative 라 파일당 약 7밀리초여서 29초가 걸린다. 그런데 그 시간은
  경쟁 창(window)의 폭일 뿐이고, 어서션이 필요로 하는 창은 밀리초 단위다
  (staging 디렉터리를 찾는 스핀 루프). **800개**로 줄여 창을 6초로 두었다 —
  여전히 필요량의 수백 배다.
- 결과: `tests/run.sh` 로컬 230초 → 55초. 3회 반복 실행으로 안정성 확인.
- 두 OS 매트릭스는 유지한다. 이 저장소는 Linux 와 macOS 를 오가며 개발하고,
  느린 쪽은 macOS 가 아니었다.

### scv/journal 은 기본 ignore (동작 변경)

- hydrate 가 `.gitignore` 에 `scv/journal/` 을 넣는다. `scv/conversations/` 에는
  계획으로 이어진 대화만 남지만 journal 에는 훅이 **자유대화까지 전부** 받아쓴다.
  그것을 저장소에 올릴지는 저장소 공개 범위와 팀 규모에 따라 달라지므로,
  기본값을 "올리지 않음"으로 두고 선택은 사용자에게 남긴다.
- 공유하려면 `.gitignore` 에서 그 줄을 지우면 된다. `journal/README.md` 에 그
  방법과 함께, **한 번 커밋한 뒤에는 `.gitignore` 를 되돌려도 추적이 끊기지
  않는다**는 점(`git rm --cached` 가 필요하고 과거 커밋에는 남는다)을 적었다.

## [0.23.0] - 2026-08-12

### 쉬운 말 먼저 — 사용자 대상 출력의 기본 규칙

- SCV는 어떤 **언어**로 말할지는 정해 두었지만 얼마나 **쉽게** 말할지는 정해
  두지 않았다. 그래서 계획 설명과 진행 보고가 길고 어려워졌다. 이해되지 않은
  계획은 승인받을 수 없고, 이해되지 않은 보고는 판단 재료가 되지 못한다.
- `## Plain language first` 절을 프로토콜 **13개**의 `## Language preference`
  옆에 추가했다. 핵심은 "짧게 먼저 말하고, 더 원하면 그때 자세히". 한 문장에
  한 가지, 범주명 대신 실제 이름, 사용자에게 무슨 일이 생기는지 먼저, 필요하면
  비유, 전문 용어는 처음 쓸 때 그 자리에서 정의.
- `set-models.md` / `update.md`는 제외했다. 어댑터 소유 스텁이고 사용자 대상
  출력이 없다.
- 문구는 13개 파일에서 **동일**하다. 회귀 가드가 존재·동일성·스텁 제외를
  고정한다(`run-dry.sh` [15p]).
- **분류 이월**: 어블레이션 기준으로는 채팅 출력 코칭이라 GUIDANCE지만,
  1단계 범위가 promote·work 외 프로토콜의 마커를 금지한다. 그래서 13개 전부
  마커 없이(= CONTRACT) 넣었다. 2단계에서 나머지 프로토콜에 마커를 도입할 때
  함께 GUIDANCE로 감쌀 것.
- **한계**: 규칙이 프로토콜에 있다는 것까지만 테스트한다. 에이전트가 실제로
  쉽게 말하는지 검증하는 수단은 없다.


### 릴리스 알림이 실패하면 릴리스 run 도 실패한다

- `release.yml` 의 dispatch 스텝에서 `if: env.SCV_WRAPPER_SYNC_TOKEN != ''` 와
  `continue-on-error: true` 를 **둘 다 제거**했다. 토큰이 없으면 스텝이
  **skipped** 되어 run 이 초록불로 남았고, v0.22.0 릴리스 run 이 실제로 그
  상태였다(스텝은 skipped, run 은 success). 이제 토큰 부재는 스텝 안에서 명시적
  error 로 실패하고, "래퍼가 통보받지 못했다"가 **한 가지 신호**로 통일된다.
- 릴리스 자산 게시는 dispatch 보다 **앞** 스텝이므로 빨간불이어도 아티팩트는
  항상 온전하다. job 재실행도 안전하다 — 기존 릴리스를 감지해 `--clobber`
  업로드 경로를 탄다.
- dispatch 루프의 **반쪽 실행**을 고쳤다. 기본 셸이 `bash -e {0}` 라 첫 래퍼가
  실패하면 루프가 중단되어 `scv-codex` 는 시도조차 되지 않았다. 이제 래퍼별로
  독립적인 3회 백오프 재시도를 받고, 실패는 `::error::` 와 재발송 명령이 담긴
  job summary 로 남는다.
- **`core_tag` 는 Core 에 추가하지 않았다.** `scv-codex` 가 읽던 그 키는 Core
  계약(`docs/wrapper-integration.md` §8 의 `version`/`tag`/`asset_url`/
  `checksum_url`)에 존재한 적이 없다. 계약에 없는 키를 Core 가 맞춰 보내는
  대신 래퍼가 계약에 맞추는 쪽으로 정리했다(scv-codex PR #21). 두 래퍼의 폴링
  주기도 매일로 통일했다.

### 토큰 헬스체크 — 만료를 릴리스 전에 잡는다

- `.github/workflows/token-health.yml` 을 추가했다(주 1회 + 수동). 릴리스는
  드물어서 토큰이 죽어도 다음 태그까지 모른다. fine-grained PAT 은 만료되므로
  그 사이가 길다.
- 검사 3종, 전부 부작용 없는 GET: ① 시크릿 존재 ② 토큰이 API 에 아직
  수락되는가 + `github-authentication-token-expiration` 헤더 기반 만료 14일
  전 경고(헤더가 없는 토큰 종류면 조용히 건너뜀) ③ 두 래퍼에 대한
  `permissions.push` — `repository_dispatch` 가 요구하는 권한이다.
- 모든 API 실패를 값으로 흡수한다. 기본 셸이 `bash -e -o pipefail` 이라
  `x=$(gh api ...)` 를 그대로 쓰면 403 한 번에 스텝이 죽어 **어느 저장소가
  문제인지 말하지 못한 채** 빨간불만 남는다.

### check-frontmatter — PLAN 은 PLAN 스키마로 검사한다 (동작 변경)

- `core/scripts/check-frontmatter.sh` 가 단일 `REQUIRED_KEYS`(표준문서 스키마
  `name`/`version`/`last_updated`/`standard_version`/`merge_policy`)를
  `scv/promote/**` 에도 적용하고 있었다. `PROMOTE.md` §4 가 규정한 PLAN 필수
  필드(`title`/`slug`/`author`/`created_at`/`status`/`tags`)와는 `status`
  하나만 겹쳐서, **문서화된 템플릿으로 쓴 PLAN 은 전부 이 린트에 실패**했다
  (실측: 계획 7건 기준 35 violations). run-dry 는 표준문서 키를 넣어 만든 자체
  픽스처만 돌려서 초록불이었다.
- 스키마를 `STANDARD_DOC_KEYS` / `PLAN_KEYS` 로 분리하고, **status 값 목록도
  함께 분리**했다(`STANDARD_DOC_STATUS` / `PLAN_STATUS`). 필수 키만 쪼개고
  status 를 병합해 두면 PLAN 이 `status: draft` 를 써도 통과하는 절충이 남는다.
- 계약에 없는 `scv/promote/*.md` · `*/index.md` 글롭은 검사 대상에서 **제거**
  했다. `PROMOTE.md` §3 은 promotion 을 "PLAN.md 를 담은 폴더"로 정의한다 —
  린트가 계약에 없는 형식에 스키마를 발명해 부여하지 않는다.
- 픽스처 4건을 실제 PLAN 템플릿 형태로 교체하고, 회귀 가드 4종을 추가했다:
  템플릿 PLAN 통과 / `author` 누락 거부 / **표준문서 헤더를 단 PLAN 거부** /
  **`status: draft` 인 PLAN 거부**. 뒤의 두 개가 이 결함을 초록불로 유지했던
  바로 그 형태다.

### 구현 원칙 4종 — work·codegen 기본값

- `action:work` Step 6 과 `action:codegen` Step 7 에 **구현 원칙 4종**을 CONTRACT
  로 넣었다: ① 기존 코드를 먼저 찾아 재활용 — 이미 한 방식이 있는 일에 두 번째
  방식을 만들지 않는다 ② 현재 요구를 완전히 충족하는 가장 단순한 구현 ③ 관심사
  하나당 컴포넌트 하나, 독자가 이름 붙일 수 있는 경계 ④ 되돌리기 비싼 결정(데이터
  모델·모듈 경계·공개 계약)은 장기 관점 — 나중에 교체할 임시방편 금지.
  **PLAN 의 `Guardrails` 가 항상 우선한다** — Core 가 프로젝트 정책을 덮어쓰지
  않는다.
- ②와 ③·④의 긴장은 의도된 것이라, 판별 기준을 GUIDANCE 로 붙였다: 미래 변경이
  재작성이면 아키텍처이고, 아키텍처는 지름길이 아니라 계획에 넣는다.
- `codegen` 은 work Step 6 을 상속하지 않는다(자체 Red/Green/Refactor 루프).
  Step 7 Green 반복에서 정본을 참조하게 했다 — TDD 의 최소 코드 규칙이 ②를 이미
  덮지만, 재활용과 경계는 Step 8 리팩터가 아니라 코드를 쓰는 중에 결정된다.
- **넣지 않은 것**: "하위호환을 유지하지 마라" 는 보류했다. SCV 자신이 legacy
  `## Steps` · `.conversations` 마이그레이션 · `CLAUDE.md`/`CODEX.md` 포인터로
  후방호환을 광범위하게 유지하므로, 배포되는 도구와 사용자 프로젝트 코드의 층위
  정리가 먼저다. "주기적 데드코드 제거" 도 넣지 않았다 — 이미
  `routines/examples/dead-code.md`(`cadence: 1d`) 가 그 루틴이다.
- **알려진 마찰**: `test-guidance.sh` [6] 은 promote·work 밖 프로토콜의 **커밋되지
  않은** 변경을 전부 실패로 본다(어블레이션 1단계 스코프 가드). `codegen.md` 편집은
  커밋 전까지 이 검사 1건을 빨갛게 만든다 — 회귀가 아니라 가드의 설계다. 2단계에서
  다른 프로토콜을 손대면 같은 마찰이 재발하므로, 가드를 "마커 유출 검사"로 좁힐지
  판단이 필요하다.

### 결정 로그 실작동 — 실행 경로 복구 + 구현 델타 기록

- **문제**: v0.22.0 이 `scv/DECISIONS.md` 와 자동 append 3지점을 도입했지만,
  이 저장소에서 결정 엔트리는 **0건**이었고 파일 자체가 git 이력에 존재한 적이
  없었다. 원인은 기록할 필드 부족이 아니라 **기록 지시가 실행되는 경로의 부재**
  다 — 아카이브 5건이 전부 수동 `git mv` 로 처리됐고(`scv/archive/INDEX.yaml`
  부재가 확증), 유일한 자동 경로인 `action:work` Step 9b.0 은 한 번도 도달하지
  않았다.
- `action:work` **Step 0 archive short-circuit 이 Step 9b.0 만은 수행**하도록
  바꿨다. 이전에는 `action:work <slug> --archive` 가 Steps 1+ 를 통째로 끊어
  결정 로그가 남지 않았다. 이 경로는 대화 밖에서 구현한 작업의 수동 아카이브에
  쓰이므로, 델타를 모를 때는 `path delta: unknown (archived outside this
  conversation)` 을 쓰도록 명시했다.
- archive 결정 엔트리에 **`- path delta:` 1필드**를 추가했다 (Step 9b.0).
  PLAN 의 `Suggested path`(legacy: `Steps`; 둘 다 없으면 Step 6 에서 사용자에게
  말한 경로) 대비 실제로 간 경로와 이탈 이유를 한 줄로 남긴다. `refs:` /
  `conversation:` 과 달리 **생략 불가** — 그대로 갔으면 `as planned` 한 단어로
  끝난다. Step 6 은 "더 나은 경로를 찾으면 그리로 가라"이고 Step 5c 는 자율
  완주 계약이므로, 이탈 이유는 세션이 끝나면 어디에도 남지 않는 유일한 정보축
  이었다.
- **`new invariants:` 필드는 만들지 않았다.** 기존 `- why:` 가 이미 "what was
  learned while implementing it" 을 요구하므로 부분집합이다 — 대신 그 문구에
  "including anything that must not break from now on" 절을 덧붙여 흡수했다.
- Step 8 에서 **`drift-detect.sh`** 를 호출해 PLAN 의 `scope:` 밖에서 바뀐
  파일(`SCOPE_OUTSIDE_FILES`)을 델타 서술의 근거로 쓰게 했다. 이 헬퍼는
  promote-only 이므로 archive 가 폴더를 옮기기 전인 Step 8 이 실행 가능한
  마지막 시점이다. 호출은 `scope:` 를 선언한 계획에서만 하도록 **CONTRACT 에**
  조건을 뒀다(예외가 GUIDANCE 에 있으면 `minimal` 투영에서 예외만 사라져
  no-scope 계획에서 헬퍼가 헛돈다). 이 헬퍼는 nested 모듈을 스스로 해석하지
  못하므로 모노레포에서는 `PROMOTE_DIR=<SCV_DIR>/promote` 를 앞에 붙인다 —
  스크립트 무수정 원칙을 지키면서 exit 2 실패를 피하는 유일한 방법이다.
  한계도 문안에 적었다: `git diff HEAD` 기반이라 **untracked 신규 파일은 보지
  못하며**, `DRIFT: no` 는 "추적되는 파일이 이탈하지 않았다"이지 "계획대로
  갔다"가 아니다.
- 예시 루틴 `decision-log-integrity` 를 추가했다 (예시 7종 → 8종). 아카이브
  슬러그와 DECISIONS 엔트리를 대조해 누락을 보고한다.
- **분류**: `- path delta:` 필드와 "생략 불가" 의무 문장, Step 0 예외,
  `drift-detect.sh` 호출은 전부 CONTRACT(마커 밖). 근거 산문만 GUIDANCE —
  `promote.md` Step 5.1 의 "discarded alternatives" 배치와 동일한 패턴이다.
- **회귀 보호**: `run-dry.sh` [16] 에 `- path delta:` / `Step 9b.0 only` /
  `drift-detect.sh` assert 3개, `test-guidance.sh` 의 work.min.md 생존 배열에
  같은 앵커를 등록했다. 그 배열이 오분류를 잡는 **유일한** 수단이라는 사실을
  배열 위 주석으로 남겼다 — [19a] 는 스크립트 호출·컬럼0 frontmatter 만 보고
  [19b] 는 에이전트를 실행하지 않기 때문이다. 오분류 시 실패가 실제로 재현되는
  것을 역방향으로 1회 확인했다.
- **재측정**: `core/protocols/work.md` GUIDANCE 222줄 / 전체 589줄 (37.7%).
  직전 문서값 `203 / 521` 은 갱신되지 않아 낡아 있었다 —
  `docs/guidance-ablation.md` 표를 실측값으로 고쳤다.
- **강제력의 정직한 범위**: DECISIONS.md 를 쓰는 스크립트는 존재하지 않는다.
  테스트가 보장하는 것은 "프로토콜에 지시가 있다"와 "그 지시가
  `SCV_GUIDANCE=minimal` 에서 사라지지 않는다" 두 가지뿐이다. **에이전트가
  필드를 빠뜨려도 실패하는 테스트는 없다** — 누락은 위 루틴으로만 드러난다.
- `action:codegen` 은 수정 0줄 (`codegen.md` 가 Steps 8–9e 를 work.md verbatim
  으로 위임). `action:promote` / `action:regression` 엔트리는 의도적으로 그대로
  둔다 — 그 두 결정에는 구현 단계가 없다.
- `core/template/scv/DECISIONS.md` 의 스키마 정본도 갱신했다. 이 파일은
  `merge_policy: preserve` 라 **기존 프로젝트에는 전파되지 않는다** — 실효
  전파 매체는 프로토콜 md 이며 래퍼 재벤더링으로 도달한다.

## [0.22.0] - 2026-08-07

### 가이던스 어블레이션 1단계 — CONTRACT/GUIDANCE 분리 + `SCV_GUIDANCE=minimal` (promote·work)

- 프로토콜 md 의 행동 코칭(GUIDANCE)을 `<!-- SCV:GUIDANCE -->` …
  `<!-- /SCV:GUIDANCE -->` HTML 주석 마커로 감싸는 규약을 도입했다.
  분류 기준: **삭제해도 산출물의 형식·경로·불변식(생성 파일 목록 ·
  frontmatter 스키마 · 스크립트 호출 시퀀스)이 변하지 않으면 GUIDANCE** —
  규약/기준 문서는 `docs/guidance-ablation.md`.
- 주입 필터 `core/scripts/guidance-filter.sh` 를 추가하고 래퍼 주입 지점인
  `tools/materialize-profile.sh` 에 연결했다. `SCV_GUIDANCE=full`(기본,
  미설정 포함)은 주입 내용이 원본과 바이트 동일하고,
  `SCV_GUIDANCE=minimal` 은 GUIDANCE 블록을 제거한 투영본을 주입한다.
  원본 프로토콜 파일은 어떤 모드에서도 불변. 잘못된 마커(닫힘 누락 ·
  고아 닫힘 · 중첩 · malformed)는 `파일:줄` 에러로 전체 주입을 중단한다
  (fail-closed — 부분 주입 없음; full 모드도 동일하게 검증).
- 어블레이션 동등성 하네스: `core/tests/run-dry.sh` [19] 가 promote·work
  경로를 두 모드로 실행해 생성 파일 목록 · frontmatter 스키마 · 스크립트
  호출 시퀀스가 동일함을 강제한다(차이 = CONTRACT 오분류 → 재분류).
  마커 lint · fail-closed · 타 프로토콜 바이트 불변 · deck 마커 비노출은
  `core/tests/test-guidance.sh` 가 검증하고, deck transform 은 마커 줄만
  드롭한다(GUIDANCE 본문은 deck 문서에서 계속 렌더).
- **1단계 분류 결과 (목표 비율 없이 기준 적용 후 측정)** —
  `promote.md`: GUIDANCE 241줄 / 전체 883줄 (27.3%),
  `work.md`: GUIDANCE 203줄 / 전체 529줄 (38.4%).
  다른 프로토콜 파일들은 이 웨이브에서 바이트 불변이다 (2단계는 minimal
  모드 실사용 피드백 후 별도 계획).

### BREAKING — adoption 단일화 + 표준 문서 7종 제거 (TEMPLATE_VERSION 2.0.0)

- `hydrate.sh --new` (greenfield mode) is removed. Passing `--new` now exits 1
  with a migration notice and changes no files (fail-closed). Hydrate has a
  single path and no longer seeds the seven standard docs
  (`DOMAIN.md` / `ARCHITECTURE.md` / `DESIGN.md` / `AGENTS.md` / `TESTING.md` /
  `INTAKE.md` / `RALPH_PROMPT.md`) — their templates are deleted from
  `core/template/scv/`. Kept files are unchanged in behavior: `SCV.md`,
  `PROMOTE.md`, `REPORTING.md`, `raw/README.md`, `WORKSPACE.yaml.example`,
  and the `.env` / `.gitignore` fragments.
- `action:sync` now **deletes** those seven files from existing projects,
  **without backup** (deliberate decision — git history is the recovery path),
  and reports each as `DELETED scv/<file>` in the CHANGES summary.
  `--dry-run` previews the deletions without touching files. No file outside
  the seven is ever deleted; a symlinked target is left in place with a
  `WARN` instead of being deleted (fail-closed). The `sync.md` protocol
  instructs the host agent to check each doomed file for user-authored content
  first and, when found, propose migrating the decisions worth keeping into a
  version-controlled team note (e.g. `DECISIONS.md` / journal) before applying.
- Cascade cleanup: the draft/N/A status gate, the INTAKE flow, and all
  standard-doc references are removed from `check-frontmatter.sh`, `help.sh` /
  `help.md` (incl. the greenfield hydrate option), `promote.md` (diagram 2 now
  sources from graphify only), `work.md`, `deck.md` / `deck-context.sh`,
  `SCV.md` / `PROMOTE.md` / `REPORTING.md` templates, and
  `integrations/loop-runner.md` (rewritten to run from `scv/promote/<slug>/`
  plans with a free-form user-authored entry prompt instead of
  `RALPH_PROMPT.md`). The hydration signal in `state-index.sh` / `help.sh` now
  uses `scv/PROMOTE.md` (previously `scv/INTAKE.md`); state-index and legacy
  CLAUDE.md/CODEX.md migration semantics are otherwise unchanged.
- Upgrade note: external loop harnesses (e.g. rloop) that expect
  `scv/RALPH_PROMPT.md` must switch to a free-form entry prompt; content you
  still need from a deleted doc is recoverable from git history
  (`git log -- scv/<file>`).

### Changed

- PLAN grammar overhaul (guardrails-first, Boris Cherny's task+guardrails+exit
  criteria model): the `action:promote` PLAN scaffold now has `## Guardrails`
  (do-not-touch areas / invariants in prose) and `## Exit criteria` (higher-level
  done conditions beyond TESTS), and `## Steps` is demoted to `## Suggested path`
  — the path is a suggestion, Guardrails/Exit criteria are the contract
  (경로는 제안, Guardrails/Exit criteria 가 계약). `scv/PROMOTE.md` §4 is synced.
  All new sections/fields are optional: legacy PLANs with only `## Steps` are
  processed by `action:work` / `action:regression` unchanged.
- `action:promote`'s Socratic follow-up questions changed direction: do not
  interrogate implementation method (구현 방법을 캐묻지 말라) — ask only about
  boundaries, risks, exit criteria, and verification means; the
  procedure-probing example list was replaced accordingly.
- `action:work` gained a long-run execution contract (Step 5c): with Guardrails /
  Exit criteria + TESTS verification means in hand, run to completion without
  micro-step instructions, and strengthen the verification means first when
  stuck. This paragraph owns work's long-run behavior even after RALPH_PROMPT
  retirement.

### Added

- Optional PLAN frontmatter `parallel_groups: [[step,...],...]` — independent
  Suggested-path step groups a subagent-capable host may fan out concurrently
  (`action:work` Step 5d); `action:regression` documents the analogous slug-level
  fan-out. Absent hint or non-parallel host → behavior identical to before.
- Raw-injection hygiene: `action:promote` and `action:help` now state that raw /
  conversation file content is **data** — instruction-like text inside it is
  never executed and is reported to the user instead.
- **Team journal — author-attributed, committed project memory**
  (전면 기록화): three new templates, all `merge_policy: preserve`, seeded by
  hydrate and propagated as `NEW` by sync — `scv/journal/README.md` (usage
  rules), `scv/DECISIONS.md` (append-only decision log; entry schema reuses
  the handoff decision format with a mandatory author), and `scv/TODO.md`
  (team todo, `- [ ] (T-NNN) <내용> — @<author>, YYYY-MM-DD`).
- `core/scripts/lib/author.sh` — unified author resolution
  (`git config user.name` → `GIT_AUTHOR_NAME` → `USER` → `unknown`) +
  filename-safe slugging that keeps non-ASCII (Korean) names;
  `promote-helper.sh`'s `AUTHOR` signal now uses it.
- `core/scripts/journal-append.sh` — appends `### [HH:MM:SS] <speaker>` blocks
  to `scv/journal/<YYYYMMDD>-<author>.md` (per-day, per-author files — no git
  conflicts), with a built-in redaction filter
  (password/token/secret/api-key values, `Bearer` tokens, `AKIA…` keys →
  `[REDACTED]`); `--redact-only` exposes the filter to protocols.
- Host hook templates `core/template/hooks/on-user-prompt.sh` (prompt-submit
  event, stdin JSON `prompt`) and `on-stop.sh` (stop event, stdin JSON
  `transcript_path`) journal free conversation; both are non-blocking (any
  failure → exit 0, no write). Registration is **wrapper-owned** — the seam
  contract is `docs/wrapper-integration.md` §6, hydrate never seeds `hooks/`
  into projects.
- Decision record points in three protocols, appending author-attributed
  entries to `scv/DECISIONS.md`: `action:promote` plan approval (adopted
  direction + **discarded alternatives**), `action:work` archive (the reason
  promoted to a decision summary), `action:regression` obsolete triage (the
  WHY that previously evaporated with the session).
- `action:status` now surfaces the last 5 `DECISIONS.md` entries and the open
  `TODO.md` items counted per author.
- **`scv/routines/` — 한 문장 프롬프트 유지보수 루틴 레이어** (Boris Cherny's
  daily-maintenance-routines practice): one routine = one md file under
  `scv/routines/<name>.md` with a five-key frontmatter contract
  (`name` / `cadence` / `guardrails` / `exit` / `report`) and a task-only body
  (plan-grammar — 과업+가드레일+종료 조건, 절차 나열 금지). hydrate seeds ONLY
  `scv/routines/README.md` (the convention doc, `merge_policy: overwrite`);
  sync propagates it to existing projects the same explicit-line way as
  `raw/README.md`. Routine files themselves are user/agent-authored.
- **`action:routine` — the 15th action** (core-owned): `--list` shows a
  NAME/CADENCE/REPORT table (guidance line when none are defined), `<name>`
  parses the routine md via the new `core/scripts/routine.sh`
  (frontmatter signals + task body + host-scheduling guidance block;
  unknown name → error with the available list, exit 1; `--lint <file>`
  validates the five-key schema). The `routine.md` protocol binds execution
  to the routine's task/guardrails/exit contract, forbids direct writes to
  permanent branches (working branch + PR or report only), makes the
  `report:` summary follow the `action:report` format, and ends with
  host-specific schedule-registration EXAMPLES — **SCV itself never
  schedules**: no cron registration, no daemon, no loop (host-owned, like
  `update` / `set-models` installation ownership). Action-count contracts
  updated 14 → 15 (`tests/test-actions.sh`, `tools/verify-core.sh`, READMEs,
  `docs/wrapper-integration.md`, `docs/core-wrapper-ownership.ko.md`);
  wrappers must register the new command surface (handoff drafts in
  `scv/promote/20260807-wookiya1364-routines/HANDOFF-DRAFTS.md`).
- Seven built-in routine templates under `core/template/scv/routines/examples/`
  (copy into `scv/routines/` to adopt; never auto-seeded): 4 SCV maintenance
  routines — `regression-runner` (run `action:regression`, report failures),
  `outdated-verifier` (semantically verify `readpath.sh outdated`'s
  `OUTDATED-CANDIDATE` docs against current code — completes the 0.21.0
  heuristic), `promote-staleness` (remind about `status: planned` folders
  older than N days), `archive-integrity` (regenerate `INDEX.yaml`, verify
  `supersedes` links) — plus 3 project-agnostic codebase routines imported
  from the Boris interview: `dead-code`, `abstraction-police`,
  `useless-tests`. All pass the routine frontmatter lint
  (`core/tests/test-routines.sh` covers seeding, list/prepare/error paths,
  outdated wiring, the 15-action catalog, and a no-scheduler-code sweep).

### Changed (team journal wave)

- Conversations are now **committed**: `.gitignore.fragment` no longer ignores
  `/scv/.conversations/`; `action:help` persists conversation files to
  `scv/conversations/` through the `journal-append.sh --redact-only` filter,
  and offers a one-time migration when it detects a legacy local
  `scv/.conversations/` (`LEGACY_CONVERSATIONS:` helper line).

## [0.21.0] - 2026-08-04

### Added

- Offline-ready 기획서 decks: after the doc build, `deck.sh` bakes every
  mermaid diagram into the HTML as inline SVG via a locally installed headless
  Chrome (`deckdoc/static-mermaid.mjs` + render.mjs's `?scv-static` build
  mode), so the deck opens fully rendered with no CDN at view time.
  Best-effort by contract — without Chrome or network the deck keeps the
  existing CDN + text-fallback rendering; opt out with `--no-static` or
  `SCV_DECK_STATIC=0`.

- Raw-doc lifecycle: `action:promote` Step 8 now runs `readpath.sh consume`,
  which moves consumed originals (content unchanged) into `scv/raw/stale/` and
  records which promote slugs used each doc in `scv/readpath.json`'s new
  `ref_docs` map (schema v2; a doc reused by several features accumulates all
  their slugs plus `ref_commit`/`consumed_at`). Files still directly under
  `scv/raw/` are therefore exactly the never-promoted **unused** docs.
- New `readpath.sh` subcommands: `consume`, `unused`, `refs`,
  `lifecycle-counts`, and `outdated` — a content-staleness heuristic that flags
  consumed docs mentioning repo files changed since their `ref_commit`
  (`OUTDATED-CANDIDATE`), with semantic verification delegated to the host
  agent in `action:promote` / `action:status`.
- `action:status` shows the unused/consumed split, per-doc `ref_docs` slugs,
  and outdated candidates; `action:help`'s banner surfaces the unused count;
  `promote-helper.sh` emits `RAW_STALE_COUNT` / `RAW_OUTDATED_COUNT` and no
  longer counts consumed docs toward the split heuristic.
- `action:status` documents a one-time legacy backfill: retro-consuming raw
  docs referenced by `raw_sources:` of existing promote/archive plans.

### Fixed

- Deck mermaid diagrams were near-invisible (white init-palette edges on the
  renderer's light card). The doc renderer now emits the
  `scv-mermaid-contrast` overrides (transparent diagram card, theme-variable
  edges and edge labels) and the promote protocol's `%%{init}%%` template
  aligns with the deck's own theme tokens (`#9096a8`/`#e7e9f0`/`#171922`), so
  architecture diagrams stay readable in both light and dark themes.

### Changed

- readpath schema is now v2 (`files` + `ref_docs`, each entry also recording
  its pre-move `origin`). v1 state files remain readable, `update` preserves
  `ref_docs`, and v1 readers ignore the new block. Caveat: a **v1** `update`
  rewrites the file without `ref_docs` — mixed-version teams should upgrade
  wrappers together.
- `consume` is fail-closed: preflight validates every path (normalization of
  `//`·`/./` variants, raw-dir prefix, no `..`, no symlinked leaf **or path
  component**, no duplicate arguments, README excluded, no
  quote/backslash/control characters) before any file moves. A shared source
  that an earlier promote folder already moved is remapped via its recorded
  `origin` (`REMAPPED` output) instead of failing.
- The ref_docs parser tolerates pretty-printed state files (e.g. after
  `jq .`) via brace-depth tracking, and empty TSV fields use a `-` placeholder
  so IFS tab-collapsing can no longer shift columns (previously an empty
  `ref_commit` silently corrupted the state on the next `update`).
- `diff`/`status-counts` no longer crash on filenames containing spaces
  (pre-existing `compute_diff` word-splitting bug); filenames with quotes,
  backslashes, tabs, or newlines are skipped by `scan`/`diff` with a warning
  and rejected by `consume` (the narrow no-jq schema cannot represent them).
- `action:sync` now propagates `scv/raw/README.md` (merge_policy `overwrite`)
  so existing projects receive the raw lifecycle guide instead of keeping the
  old "raw files are never moved" text that contradicts Step 8's stale-move.

## [0.20.6] - 2026-07-29

### Fixed

- Centralized canonical, legacy, conflict, and broken-pointer state resolution
  in one host-neutral Core entrypoint so Claude Code and Codex cannot classify
  the same project differently.
- Standardized compatibility pointers on the exact
  `SCV:HOST-POINTER target=SCV.md` marker and made both host directions share
  the same inspect, preview, backup, and pointer-finalization behavior.
- Kept projects with readable state and `scv/INTAKE.md` classified as hydrated
  during a fail-closed conflict, preventing a conflict from being mistaken for
  an unhydrated project.

### Security

- Made canonical seeding no-replace and revalidated every active legacy file
  against its recoverable backup before publishing any pointer.
- Preserved read-only and dry-run trees byte-for-byte across the full
  canonical/legacy/pointer conflict matrix.

## [0.20.5] - 2026-07-29

### Changed

- Kept legacy Deck runtime migration strict by default and added the explicit
  `migrate --from LEGACY_DECKUI --reuse-existing` opt-in for persistent legacy
  sources.
- Made cache reuse authoritative and all-or-none: if preflight finds any
  pre-existing destination that differs from its legacy source, the entire
  legacy source is skipped, including equal and missing destinations. With no
  mismatch, migration retains its existing additive behavior.
- Required ephemeral existing-vendor recovery to remain strict so a wrapper
  cannot discard runtime data when that vendor is removed after a successful
  swap. Core API remains `1`.

### Security

- Preflight now evaluates every eligible runtime entry before any copy or
  authoritative-reuse decision. A destination collision that appears after
  preflight still fails closed instead of changing policy mid-transaction.

## [0.20.4] - 2026-07-28

### Security

- Anchored the Deck runtime cache base, payload namespace, target, staging,
  migration destinations, installation, and cleanup to verified directory
  descriptors opened with no-follow semantics.
- Made lock acquisition install a complete owner record through an atomic
  no-replace rename, and bound stale quarantine and release to the original
  lock inode and owner token.
- Added deterministic late-symlink, ancestor-replacement, quarantine-collision,
  and release-race regressions that assert external sentinels remain unchanged.

## [0.20.3] - 2026-07-28

### Fixed

- Made first-use and migration installs in the shared DeckUI cache use
  platform-native atomic no-replace renames on Linux and macOS.
- Rejected cache/legacy overlap before initialization and opened every
  migration destination ancestor without following links.
- Limited stale lock reclamation to a valid dead-owner record with no
  unexpected lock data; malformed or surprising state is preserved and fails
  closed.

## [0.20.2] - 2026-07-28

### Fixed

- Moved mutable DeckUI dependencies, build output, and generated deck data out
  of the immutable Core/plugin tree into a payload-keyed external cache.
- Added an idempotent legacy DeckUI migration that preserves pnpm links,
  generated decks, and build output without deleting or rewriting the source.
- Prevented wrapper Core replacement from treating DeckUI runtime data as
  distributable payload and removed excluded empty deck directories from
  exports.
- Expanded the cross-host state matrix to cover approved `CLAUDE.md` and
  `CODEX.md` migrations, both supported readpath encodings, workspace markers,
  and mutating conflict failure with byte-for-byte preservation.

### Security

- Added atomic cache initialization, per-payload locking, collision detection,
  unsafe target rejection, and link/special-file checks for immutable DeckUI
  inputs.

## [0.20.1] - 2026-07-28

### Fixed

- Materialized source-checkout metadata links as regular files in exported and
  released payloads so strict wrapper archive validation can reject every link
  and special-file entry consistently.
- Added export, vendoring, and release hygiene checks that fail if any
  non-regular entry is present.

## [0.20.0] - 2026-07-28

### Added

- Extracted the shared SCV protocols, scripts, template, DeckUI, assets, docs,
  and regression tests into a host-neutral Core payload.
- Added a strict Core API v1 host-profile contract and deterministic
  materialization for template-string and argv-array hosts.
- Added verified export, vendoring, lock generation, deterministic release
  artifacts, and SHA-256 integrity metadata.
- Added legacy `CLAUDE.md`/`CODEX.md` read compatibility with explicit,
  non-destructive migration to `SCV.md`.
- Added CI for contracts, host-neutrality, state migration, shared regression,
  DeckUI, cross-platform shell behavior, deterministic artifacts, and branch
  flow.

### Changed

- Made `scv/SCV.md` the canonical shared state index.
- Moved host installation (`update`) and model selection (`set-models`) behind
  adapter-owned boundaries.
- Made sync fail closed when independent state indexes diverge and preserve
  project-local metadata and existing lifecycle status during migration.

### Security

- Host profiles are parsed as data without `source` or `eval`.
- Exports reject escaping or directory symlinks and exclude development
  dependencies, build outputs, caches, and temporary files.
