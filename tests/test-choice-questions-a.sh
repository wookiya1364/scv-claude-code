#!/usr/bin/env bash
export SCV_STOP_MODE=block   # 0.83.0+ — 이 시험은 막힘(block)을 본다. 기본(notice)은 test-stop-notice.sh
# (a) — test-choice-questions.sh 를 나눈 조각 1/3 (CI 가장 느린 조각 줄이기). 묶어 돌리기: test-choice-questions.sh
# test-choice-questions.sh — "결정은 고르는 선택지로" 검사 (v0.64.0+).
#
# 왜 있나: 호스트 설정에 선택지 도구가 있으면 SCV 가 사용자에게 고르게 하는 결정은 그 도구로 묻는다 — 매 턴 안내 한 줄이
# 실리고, 마지막 답이 글로 묻거나 번호로 고르게 하면서 끝나면 종료 훅이 같은 턴에 한 번 막는다(v0.64.2+ 검사마다 한 턴에 한 번 —
# 이 검사가 이미 이유를 냈으면 다음 턴 경고). 도구가 없으면(기본 · 코덱스) 모든 출력과 판정이 이 기능 전과 같다. 규칙은
# contracts/choices.md 한 곳뿐이다.
#
# Covers TESTS.md T1~T9 · T13~T15 of 20261001-wookiya1364-restore-choice-questions
#   and T19 · T20 (등록 판정 경로 — 답 모양 검사 경로의 T19 는 test-answer-lint-source [T11]), T23 · T25 · T26,
#   T27~T31 · T33 (추정 해소 — 사람 없는 실행 · 코덱스 모양 원본 · 도구 출처 표시 · 실제 긴 턴 모양 · 판정 정확도 ·
#   시스템 bash 3.2 속도와 출력).
#   (T16 = test-host-neutral · test-model-prompting · test-help-budget, T21 · T22 = test-model-prompting,
#    T10~T12 · T17 · T18 = 설치본 · CI 실측).
# 픽스처는 중립 도구 이름(PickTool)만 쓴다 — 코어에는 호스트 도구 이름을 적지 않는다.
# Run: bash core/tests/test-choice-questions.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-choice-questions: payload not found from $HERE" >&2; exit 1; }
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
LIB="$CORE/scripts/lib/choices.sh"; GATE="$CORE/scripts/choice-gate.sh"; MP="$CORE/scripts/model-prompting.sh"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"; STOP_HOOK="$CORE/template/hooks/on-stop.sh"
RULE="$CORE/contracts/choices.md"; FIX="$CORE/tests/fixtures/model-prompting"
for f in "$LIB" "$GATE" "$PROMPT_HOOK" "$STOP_HOOK" "$RULE" "$FIX/profile.env" "$FIX/guides/INDEX.tsv"; do
  [[ -f "$f" ]] || { echo "✖ 없음: $f"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-choice.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
{ cat "$FIX/profile.env"; printf 'SCV_CHOICE_TOOL=PickTool\n'; } > "$WORK/profile-pick.env"
cp "$FIX/profile.env" "$WORK/profile-none.env"
# 등록 판정까지 켠 프로필 — 요구 항목 목록 · 자동 알림 태그 · 선택지 도구.
cp -R "$FIX/guides" "$WORK/guides-cl"
# 0.88.0+ — 요구 항목 표 파일은 만들지 않는다(다시 쓰기 · 등록 장치는 가이드 색인만으로 켜진다).
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\nSCV_AUTO_PROMPT_TAGS=machine-event\nSCV_CHOICE_TOOL=PickTool\n' "$WORK/guides-cl"; } > "$WORK/profile-full.env"
SUB_OK="$(printf 'scope | - | src/login.js\nrewrite | - | Fix the login bug until the login test passes')"
# (0.76.0+) 보이는 곳 — 답 맨 위 전문 인용(계획 answer-bullets). 그 전에는 맨 위 한 줄 + 결론 뒤 인용.
QUOTE=$'> **Rewritten request**: Fix the login bug until the login test passes'

new_repo() {  # <이름> → 빈 scv 저장소 경로 (세션 s1 의 help 표식 포함)
  local d="$WORK/$1"; mkdir -p "$d/scv/journal"
  printf '{"session":"s1","protocol":1,"turn":3,"diag":"","diag_at":"","nonce":"abcd1234"}\n' > "$d/scv/journal/.help-state"
  printf '%s' "$d"
}
# (v0.65.0+) 이번 턴 상태는 세션마다 따로 있다 — 매 턴 훅을 세션 s1 로 부른 검사는 그 자리에서 읽는다(계획 rewrite-stays-current 목표 5).
tf() { printf '%s/scv/journal/.help-turns/%s/%s' "$1" "${3:-s1}" "$2"; }
asks() { bash -c 'source "$1"; scv_asks_in_text "$(scv_answer_body "$2")"' _ "$LIB" "$1"; }
hook_p() {  # <저장소> <프로필> <프롬프트> [코어] → 매 턴 훅 출력
  local core="${4:-$CORE}"
  (cd "$1" && jq -cn --arg p "$3" '{prompt:$p,session_id:"s1"}' \
     | CLAUDE_PLUGIN_ROOT="$core" SCV_HOST_PROFILE="$2" bash "$core/template/hooks/on-user-prompt.sh" 2>/dev/null)
  # 0.80.0+ — 이 시험의 사람 턴은 help 를 부른 턴으로 둔다(help 먼저 판정은 test-help-first.sh 가 본다).
  [[ -f "$core/scripts/model-prompting.sh" ]] && (cd "$1" && SCV_HOST_PROFILE="$2" bash "$core/scripts/model-prompting.sh" helped --session s1 >/dev/null 2>&1) || true
}
stop_p() {  # <저장소> <프로필> <마지막 답> <계속 중 true|false> [코어] → 종료 훅 stdout
  local r="$1" core="${5:-$CORE}" tr="$WORK/tr-$RANDOM$RANDOM.jsonl"
  printf '{"type":"user","message":{"content":[{"type":"text","text":"q"}]}}\n' > "$tr"
  jq -cn --arg t "$3" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"text",text:$t}]}}' >> "$tr"
  (cd "$r" && jq -cn --arg p "$tr" --arg a "$3" --argjson act "$4" '{session_id:"s1",transcript_path:$p,last_assistant_message:$a,stop_hook_active:$act}' \
     | CLAUDE_PLUGIN_ROOT="$core" SCV_HOST_PROFILE="$2" GIT_AUTHOR_NAME="Hook User" bash "$core/template/hooks/on-stop.sh" 2>/dev/null)
}
reg_full() { (cd "$1" && printf '%s\n' "$SUB_OK" | SCV_HOST_PROFILE="$WORK/profile-full.env" bash "$MP" register --model vendor-model-a 2>/dev/null); }

# 픽스처 — 잡을 것(T1)과 잡지 않을 것(T2)
C_A=$'| # | 질문 | 내 추천 |\n|---|---|---|\n| 1 | 계획 폴더 이름 | restore-choice |\n\n\'다 추천대로\'라고 하시거나, 바꿀 번호만 알려 주세요.'
C_B=$'남은 것: 커밋 안 된 기록 2개.\n질문: 세 로컬 작업 폴더를 개발 브랜치 최신으로 옮겨 둘까요? (추천: 예)'
C_C=$'| # | 질문 | 추천 |\n|---|---|---|\n| 1 | 릴리스 | 예 |\n\n번호로 답해 주세요.'
C_D1=$'Two decisions are open.\n\nReply with the numbers.'
C_D2=$'Please answer by number.'
C_E=$'All tests passed.\n\nShould I proceed?'
N_A=$'| 단위 | 해결책 | 추천 |\n|---|---|---|\n| 판정 | ①순수 함수 | ① 재사용 |\n\n| 단계 | 결과 |\n|---|---|\n| 검사 | 통과 |\n\n| 번호 | 위치 | 조건 | 깨지는 것 | 확인 |\n|---|---|---|---|---|\n| P1 | a.sh:3 | 빈 값 | 없음 | 확인 |'
N_B=$'결론입니다.\n\n> **다시 쓴 요청**: 다 끝난거 맞아? 지금 상태를 알려 줘.\n\n남은 것은 없습니다.'
N_C=$'설명입니다.\n\n```\necho "ok?"\n```\n\n끝났습니다.'
N_D=$'고르지 않으셔서 여기서 멈춥니다.'
N_E=$'왜 그럴까? 원인은 설정이다.\n\n그래서 고쳤습니다.'

echo "── [T1] 글로 묻는 답 판정 — 잡을 것 ──"
c=0
# 독립 검토가 찾은 누락 모양: 질문 뒤 보기 목록 · 요청형("정해 주세요" · "Let me know which") · 이모티콘 · 괄호 · 굵은 괄호 · 따옴표
C_F1=$'어떻게 진행할까요?\n\n1. A 방식 (추천)\n2. B 방식'
C_F2=$'Which approach do you prefer?\n- Option A (recommended)\n- Option B'
C_F3='…어느 쪽으로 할지 정해 주세요.'
C_F4='Let me know which one you want.'
C_F5='진행할까요? 🙂'
C_F6='(이대로 진행할까요?)'
C_F7='Ready to merge? :)'
C_F8='진행할까요? **(추천: 예)**'
C_F9=$'Done.\n\nShall I \xe2\x80\x9cship it?\xe2\x80\x9d'
for x in "$C_A" "$C_B" "$C_C" "$C_D1" "$C_D2" "$C_E" "$C_F1" "$C_F2" "$C_F3" "$C_F4" "$C_F5" "$C_F6" "$C_F7" "$C_F8" "$C_F9"; do
  [[ "$(asks "$x")" == 1 ]] && c=$((c + 1)) || echo "      ✖ not caught: $(head -c 60 <<<"$x")"
done
[[ $c -eq 15 ]] && ok "화면 문구 · (추천: 예) · 번호로 답 · 영어 · 물음표 끝 + 검토 누락 9 모양 — 15/15" || fail "T1 $c/15"
c=0
for L in C en_US.UTF-8; do [[ "$(LC_ALL=$L bash -c 'source "$1"; scv_asks_in_text "$2"' _ "$LIB" "$C_F9")" == 1 ]] && c=$((c + 1)); done
[[ $c -eq 2 ]] && ok "로캘과 무관 — C · UTF-8 같은 판정" || fail "T1 로캘 $c/2"

echo "── [T2] 글로 묻는 답 판정 — 잡지 않을 것 ──"
c=0
# 독립 검토가 찾은 오탐 모양: 되짚는 표 · 상태 표의 물음표 · 평서문 속 "추천대로" · "番号だけ" · "번호로 골라 주신" · "pick a number"
N_F1=$'| 질문 | 고른 것 |\n|---|---|\n| 릴리스할까? | 예 |'
N_F2=$'| 항목 | 상태 |\n|---|---|\n| 원격 CI | ? |'
N_F3='말씀하신 대로 다 추천대로 반영했습니다.'
N_F4='バージョン番号だけ上げました。'
N_F5='번호로 골라 주신 2번으로 바꿨습니다.'
N_F6='The script will pick a number between 1 and 10.'
N_F7=$'바꾼 것:\n- a\n- b'
for x in "$N_A" "$N_B" "$N_C" "$N_D" "$N_E" "$N_F1" "$N_F2" "$N_F3" "$N_F4" "$N_F5" "$N_F6" "$N_F7"; do
  [[ "$(asks "$x")" == 0 ]] && c=$((c + 1)) || echo "      ✖ wrongly caught: $(head -c 60 <<<"$x")"
done
[[ $c -eq 12 ]] && ok "정보 표 · 인용 · 코드 · 평서문 · 중간 물음표 + 검토 오탐 7 모양 — 12/12" || fail "T2 $c/12"
if [[ -f "$CORE/scripts/check-purity.sh" ]]; then
  o="$(bash "$CORE/scripts/check-purity.sh" "$LIB" "$CORE/scripts/lib/help-state.sh" 2>&1)"
  grep -q '^OK  purity' <<<"$o" && ok "순수성 계약 통과 (판정 함수 · 턴 끝 메시지)" || fail "순수성: $(head -2 <<<"$o")"
fi

echo "── [T31] 판정 정확도 — 실제 답 모음에서 놓친 모양 · 잡지 않을 모양 ──"
# 로컬 원본 230턴 실측(2026-10-01): 고치기 전 실제로 묻는 답 60개 중 35개(58%)를 잡음, 고친 뒤 60개 모두 · 잘못 잡은 것 0.
# "필요하면 말씀해 주세요" 같은 조건부 제안(약 17개)은 묻는 것이 아니다(contracts/choices.md 7 — 질문 없이 적는 제안).
# 아래는 실측에서 놓친 모양을 바꿔 쓴 것이다(원문 아님).
c=0
C_G1='지금 계획서 초안을 만들까요? 추천은 바로 만드는 것입니다. 이 대화가 근거로 남습니다.'
C_G2='어느 쪽으로 할까요? 제 추천은 A입니다.'
C_G3='다음 계획으로 넘길까요? (추천: 예) 예라고 하시면 이어서 진행합니다.'
C_G4='전부 다시 돌릴까요? 에픽 건은 다음 메모로 넘깁니다. (추천: 예)'
C_G5='번호로 답해 주시면 됩니다 (예: "추천대로").'
C_G6='다음으로 커밋까지 할지 알려 주세요.'
C_G7='맞다면 "2"라고만 답해 주세요. 그러면 저장하겠습니다.'
C_G8=$'예를 들어 "4번"이라고 하시면 바로 넣겠습니다. 추천대로 하려면 "1번"이라고 해 주세요.\n\n지금 코드 파일은 그대로입니다.'
C_G9='말씀하신 증상이 이것이 맞나요? 다른 증상이면 알려 주세요.'
C_G10=$'**질문 하나:** 출력 언어를 무엇으로 할까요? **[2] 한국어**를 추천합니다.\n[1] English / [2] 한국어 / [3] 日本語'
C_G11='Should I open the PR now? I recommend yes, since the checks are green.'
C_G12='어떤 맥락에서 보신 것인지 알려주시면 좋겠습니다.'
# 독립 검토(2026-10-02)가 찾은 누락 — 전각 물음표 뒤 붙여 쓴 추천, 주소의 ? 뒤에 숨은 질문
C_G13='どちらにしますか？おすすめはAです。'
C_G14='Should I deploy? I recommend yes. Logs: https://x.example/run?id=3'
C_G15='어떤 걸 할까요? 네 가지 방법이 있습니다. 추천은 A입니다.'
for x in "$C_G1" "$C_G2" "$C_G3" "$C_G4" "$C_G5" "$C_G6" "$C_G7" "$C_G8" "$C_G9" "$C_G10" "$C_G11" "$C_G12" "$C_G13" "$C_G14" "$C_G15"; do
  [[ "$(asks "$x")" == 1 ]] && c=$((c + 1)) || echo "      ✖ not caught: $(head -c 60 <<<"$x")"
done
[[ $c -eq 15 ]] && ok "질문 뒤 추천 · 요청 문장, 넓힌 요청 말투, 한 줄 보기 목록, 앞 문단의 요청, 전각 물음표, 주소 뒤 — 15/15" || fail "T31 잡을 것 $c/15"
c=0
N_G1='PR 번호나 링크가 필요하면 말씀해 주세요.'
N_G2='원하시면 로그인한 뒤 알려 주세요.'
N_G3="'다 끝난거 맞아?'에 답하면, 네 — 모두 끝났습니다. 더 필요하면 알려 주세요."
N_G4='결과: https://example.com/run?id=3 — 추천 설정 그대로 통과했습니다.'
N_G5='어느 부분이 걸리시는지 짚어 주시면 그 부분만 더 풀어 드리겠습니다.'
N_G6=$'왜 막혔나? 이번 턴이 길어서였다.\n\n추천 수정은 넓혀 찾기였고, 반영했습니다.'
# 독립 검토(2026-10-02)가 찾은 오탐 — 맺음 인사("언제든지"), 답한 혼잣말 질문, 연산자 ??, 낱말만 "recommended", 특수 공백 줄
N_G7='모두 반영했습니다. 궁금한 점이 있으면 언제든지 알려 주세요.'
N_G8='얼마든지 말씀해 주세요.'
N_G9='Did all tests pass? Yes — all 55 passed with the recommended settings.'
N_G10='Is it merged? Yes. If you need anything else, let me know.'
N_G11='The fix uses `a ?? b`, which is the recommended idiom here.'
N_G12='왜 막혔나? 이번 턴이 길어서였다. 추천 수정은 넓혀 찾기였고, 반영했습니다.'
N_G13=$'Was it the cache? It was.\n\xc2\xa0\nThe recommended settings are unchanged.'
N_G14='어떤 걸 할까요? 네 가지 방법이 있습니다.'
for x in "$N_G1" "$N_G2" "$N_G3" "$N_G4" "$N_G5" "$N_G6" "$N_G7" "$N_G8" "$N_G9" "$N_G10" "$N_G11" "$N_G12" "$N_G13"; do
  [[ "$(asks "$x")" == 0 ]] && c=$((c + 1)) || echo "      ✖ wrongly caught: $(head -c 60 <<<"$x")"
done
[[ $c -eq 13 ]] && ok "조건부 제안 · 맺음 인사 · 옮겨 적은 질문 · 주소 · 연산자 ?? · 답한 혼잣말 질문 · 특수 공백 줄 — 13/13" || fail "T31 잡지 않을 것 $c/13"
# "네 가지" 는 "네(예)" 가 아니다 — 답한 혼잣말 질문으로 보지 않는다(추천이 없으면 묻는 말로도 잡지 않는다)
[[ "$(asks "$N_G14")" == 0 && "$(asks "$C_G15")" == 1 ]] && ok "\"네 가지\" 는 답이 아니다 — 추천이 붙으면 잡고, 없으면 잡지 않는다" || fail "T31 네 가지"
c=0
for L in C en_US.UTF-8; do
  [[ "$(LC_ALL=$L bash -c 'source "$1"; scv_asks_in_text "$2"' _ "$LIB" "$C_G2")" == 1 && "$(LC_ALL=$L bash -c 'source "$1"; scv_asks_in_text "$2"' _ "$LIB" "$N_G3")" == 0 \
     && "$(LC_ALL=$L bash -c 'source "$1"; scv_asks_in_text "$2"' _ "$LIB" "$N_G13")" == 0 && "$(LC_ALL=$L bash -c 'source "$1"; scv_asks_in_text "$2"' _ "$LIB" "$C_G13")" == 1 ]] && c=$((c + 1))
done
[[ $c -eq 2 ]] && ok "넓힌 판정도 로캘과 무관 — C · UTF-8 같은 판정" || fail "T31 로캘 $c/2"

echo "── [T31] 판정 정확도 — 3차 독립 검토(2026-10-02)의 사례 — 고친 곳을 되돌리면 붉어지는 모양으로 ──"
c=0
C_H=( 'Should I delete `old.sh`? I recommend yes.' 'Should I bump `VERSION`? Let me know.'
      'Should I deploy? Logs: https://x.example/run?id=3 — I recommend yes.'
      "Should I merge it? You asked 'is it done?' — I recommend merging."
      'A안으로 갈지 B안으로 갈지 알려 주세요. 다른 궁금한 점도 언제든지 알려 주세요.'
      'Should I deploy now?? I recommend yes.' 'Should I merge? Yes or no — I recommend yes.'
      $'Should I deploy now?\n\xc2\xa0' '진행하시겠습니까? 추천은 예입니다.' $'어느 쪽으로 할까요?\n추천은 A입니다.' )
for x in "${C_H[@]}"; do [[ "$(asks "$x")" == 1 ]] && c=$((c + 1)) || echo "      ✖ not caught: $(head -c 60 <<<"$x")"; done
[[ $c -eq 10 ]] && ok "코드 조각 뒤 물음표 · 주소 · 옮긴 질문 뒤로 걷기 · 맺음 인사와 함께 둔 요청 · ?? · Yes or no · NBSP 줄 · 습니까 · 두 줄 — 10/10" || fail "T31 3차 잡을 것 $c/10"
c=0
N_H=( 'テストは通りましたか？　はい、すべて通りました。おすすめは今の設定のままです。'
      'ご質問「どちらが良いですか？」への答え：おすすめはAです。'
      '原因は何だったのか？古いキャッシュでした。おすすめは毎回の削除です。'
      '무엇이 문제였나? 캐시였습니다. 궁금한 점이 있으면 언제든지 알려 주세요.'
      'Was it the cache? It was. If you need anything else, let me know.'
      '왜 느렸나? 캐시 때문이었다. 설정을 추천 값으로 되돌렸습니다.'
      'Did it pass? Yes — I recommend keeping the current settings.'
      'The fix uses `a ?? b`, which I recommend here.' )
for x in "${N_H[@]}"; do [[ "$(asks "$x")" == 0 ]] && c=$((c + 1)) || echo "      ✖ wrongly caught: $(head -c 60 <<<"$x")"; done
[[ $c -eq 8 ]] && ok "전각 공백 뒤 답 · 옮긴 ？ · 혼잣말(のか · 나?) · 답한 질문 뒤 추천 · 코드 조각 안 ?? — 8/8" || fail "T31 3차 잡지 않을 것 $c/8"
c=0
for L in C en_US.UTF-8; do
  for x in "${C_H[0]}" "${C_H[7]}"; do [[ "$(LC_ALL=$L bash -c 'source "$1"; scv_asks_in_text "$(scv_answer_body "$2")"' _ "$LIB" "$x")" == 1 ]] && c=$((c + 1)); done
  for x in "${N_H[0]}" "${N_H[2]}"; do [[ "$(LC_ALL=$L bash -c 'source "$1"; scv_asks_in_text "$(scv_answer_body "$2")"' _ "$LIB" "$x")" == 0 ]] && c=$((c + 1)); done
done
[[ $c -eq 8 ]] && ok "3차 사례도 로캘과 무관 — C · UTF-8 같은 판정" || fail "T31 3차 로캘 $c/8"

echo "── [T31] 판정 정확도 — 마지막 검토(2026-10-02)의 사례 — 여러 줄 · 빈 줄 · 흔한 추천 말투 · 답한 굵은 질문 ──"
c=0
C_I=( $'현재 상태: 통과.\n다음 행동: CHANGELOG 도 고칠까요? 추천은 예입니다.\n검증 기준: 테스트 통과.'
      $'Summary:\n- Next: should I bump VERSION? I recommend yes.' 'Should I deploy now? CI is green. Let me know.'
      $'Should I update the CHANGELOG?\n\nI recommend yes.' $'Which option?\n1. A\n2. B\nI recommend option 2.'
      "Should I merge? I'd recommend yes." 'どちらにしますか？Aがおすすめです。' 'A안으로 할까요? A안을 권장합니다.'
      '어떻게 할까요? 말씀해 주시면 진행하겠습니다.' )
for x in "${C_I[@]}"; do [[ "$(asks "$x")" == 1 ]] && c=$((c + 1)) || echo "      ✖ not caught: $(head -c 60 <<<"$x")"; done
[[ $c -eq 9 ]] && ok "가운데 줄의 질문 · 목록 줄 · 다음 문장의 요청 · 빈 줄 뒤 추천 · 보기 뒤 추천 · I'd recommend · がおすすめ · 권장 · 말씀해 주시면 — 9/9" || fail "T31 마지막 잡을 것 $c/9"
c=0
N_I=( $'**Is it safe to merge?**\nYes — I recommend merging after CI.' 'Why did it fail? The window was short. Recommended: widen it.'
      '왜 막혔을까요? 창이 짧았습니다. 추천은 넓혀 찾기입니다.' 'Was it the cache? Yes - I recommend clearing it.'
      'Was it the cache? It was. If you need anything else, let me know.' )
for x in "${N_I[@]}"; do [[ "$(asks "$x")" == 0 ]] && c=$((c + 1)) || echo "      ✖ wrongly caught: $(head -c 60 <<<"$x")"; done
[[ $c -eq 5 ]] && ok "굵은 질문 뒤 줄의 답 · Why · 왜 …을까요 · Yes - · 조건부 제안 — 5/5" || fail "T31 마지막 잡지 않을 것 $c/5"

echo "── [T34] 설치본 실측(2026-10-02)의 꼴 — 결정 표 뒤에 안내 문단이 한 번 더 ──"
C_J=$'**정해 주실 것** (예: "1 좋아, 2 좋아"처럼 번호로 답하거나, 원하는 이름을 적어 주세요)\n\n| # | 질문 | 내 추천 |\n|---|---|---|\n| 1 | 계획 폴더 이름 | `login-retry` |\n| 2 | 계획 제목 | "로그인 자동 재시도" |\n\n이름과 제목이 정해지면 나머지 질문 두 가지를 이어서 드리겠습니다.'
N_J=$'| # | 질문 | 고른 것 |\n|---|---|---|\n| 1 | 계획 폴더 이름 | login-retry |\n\n고르신 대로 계획 폴더를 만들었습니다.'
[[ "$(asks "$C_J")" == 1 && "$(asks "$N_J")" == 0 ]] && ok "결정 표 + 안내 문단은 잡고, 고른 것을 되짚는 표 + 안내는 잡지 않는다" || fail "T34: $(asks "$C_J") / $(asks "$N_J")"

echo "── [T3] 막기 판정 — 순수 함수 ──"
g() { bash -c 'source "$1"; scv_choice_gate "$2" "$3" "$4"' _ "$LIB" "$@"; }
c=0
[[ "$(g 1 PickTool 0)" == block ]] && c=$((c + 1)) || echo "      (1,PickTool,0)"
[[ "$(g 1 PickTool 1)" == warn ]] && c=$((c + 1)) || echo "      (1,PickTool,1)"
[[ "$(g 0 PickTool 0)" == ok && "$(g 0 PickTool 1)" == ok ]] && c=$((c + 1)) || echo "      (0,PickTool,*)"
[[ "$(g 1 '' 0)" == ok && "$(g 1 '' 1)" == ok ]] && c=$((c + 1)) || echo "      (1,'',*)"
[[ $c -eq 4 ]] && ok "block · warn · ok · 도구 없음 ok — 4/4" || fail "T3 $c/4"

echo "── [T4] 종료 훅 — 등록을 마친 사람 턴이 글로 묻고 끝나면 같은 턴에 한 번 막는다 ──"
R="$(new_repo t4)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null; reg_full "$R" >/dev/null
o="$(stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s\n\n%s' "$QUOTE" "결론." "$C_A")" false)"
if [[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && grep -q 'SCV 선택지' <<<"$o" && grep -q 'PickTool' <<<"$o" \
   && grep -q '첫 보기가 추천' <<<"$o" && grep -q '4개를 넘으면' <<<"$o"; then ok "첫 번째: 막음 — 이유에 도구 이름 · 추천 첫 보기 · 나누기"; else fail "T4 첫 번째: [$o]"; fi
rm -f "$(tf "$R" .help-warn)"
o="$(stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s\n\n%s' "$QUOTE" "결론." "$C_A")" true)"
[[ -z "$o" ]] && grep -q '^\[SCV 가이드\] 직전 턴: \[SCV 선택지\]' "$(tf "$R" .help-warn)" 2>/dev/null \
  && ok "이미 계속 중: 막지 않고 다음 턴 경고" || fail "T4 계속 중: [$o] / $(cat "$(tf "$R" .help-warn)" 2>/dev/null)"
(cd "$R" && bash "$CORE/scripts/help-state.sh" reset --turn-dir scv/journal/.help-turns/s1 >/dev/null 2>&1)
grep -q '^\[SCV 가이드\] 직전 턴: \[SCV 선택지\]' "$(tf "$R" .help-warn)" 2>/dev/null \
  && ok "경고는 컨텍스트 초기화(clear · 압축 · 재개) 뒤에도 남는다" || fail "T4 초기화 뒤 경고 사라짐"
o="$(stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s' "결론." "$C_A")" false)"
# v0.64.2+ (계획 stop-gates-each-once) — 한 멈춤에 걸린 이유는 함께 싣는다: 예전에는 등록 이유 하나만 내고 선택지 판정을 건너뛰었다.
_r="$(jq -r .reason <<<"$o" 2>/dev/null)"
[[ "$_r" == *'[SCV 프롬프트]'*'[SCV 선택지]'* ]] && ok "등록 · 인용과 선택지가 함께 걸리면 두 이유를 한 번에(등록 → 선택지 순)" \
  || fail "T4 함께 싣기: [$o]"

echo "── [T5] 종료 훅 — 자동 알림 턴에도 적용된다 ──"
R="$(new_repo t5)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null; reg_full "$R" >/dev/null
stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s\n\n%s' "$QUOTE" "결론." "끝났습니다.")" false >/dev/null   # 사람 턴이 끝난다
hook_p "$R" "$WORK/profile-full.env" $'<machine-event>\n<status>completed</status>\n</machine-event>' >/dev/null
gate_auto="$(cd "$R" && printf '%s' "$C_B" | SCV_HOST_PROFILE="$WORK/profile-full.env" bash "$MP" stop --active 0 2>/dev/null | grep '^STOP_GATE')"
o="$(stop_p "$R" "$WORK/profile-full.env" "$C_B" false)"
[[ "$gate_auto" == "STOP_GATE: auto" ]] && [[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && grep -q 'SCV 선택지' <<<"$o" \
  && ok "등록 판정은 auto 로 건너뛰고, 선택지 판정은 막는다" || fail "T5: gate=[$gate_auto] out=[$o]"

echo "── [T6] 종료 훅 — 정보만 준 턴 · 선택지로 물은 뒤 평서문으로 끝난 턴은 통과 ──"
R="$(new_repo t6)"; c=0
for x in "$N_A" "$N_B" "$N_C" "$N_D" "$N_E" "고르신 대로 진행합니다. 결과는 끝에 정리하겠습니다."; do
  o="$(stop_p "$R" "$WORK/profile-pick.env" "$x" false)"; [[ -z "$o" ]] && c=$((c + 1)) || echo "      ✖ blocked: $(head -c 50 <<<"$x") → $o"
done
[[ $c -eq 6 ]] && ok "막지 않음 — 6/6" || fail "T6 $c/6"

echo "── [T7] 도구가 없으면 지금과 같다 (코덱스 · 기본) ──"
# 같은 훅을 도구 없음 · 도구 있음으로 돌린다 — 차이는 안내 한 줄뿐이어야 한다(도구가 없으면 그 줄도 없다).
R1="$(new_repo t7a)"; R2="$(new_repo t7b)"
# (v0.66.0+) 실체 보여 주기 안내도 같은 도구 유무로 확인 통로(선택 창 · 글 질문)를 고른다(contracts/show-real.md) — 이 검사는
# 선택지 줄만 보므로 두 저장소 모두 그 안내를 끈다. 그 안내의 통로 차이는 test-show-real 의 T1 · T3 이 본다.
printf '{"SCV_SHOW_REAL": "off"}\n' > "$R1/scv/scv_settings.json"; cp "$R1/scv/scv_settings.json" "$R2/scv/scv_settings.json"
# 진단 줄의 저장소 경로는 폴더 이름만 다르다(임시 경로의 // 는 출력에서 / 로 접힌다) — 이름만 맞춘다.
o1="$(hook_p "$R1" "$WORK/profile-none.env" "안녕" | sed -E 's#/t7[ab]\)#/REPO)#g')"
o2="$(hook_p "$R2" "$WORK/profile-pick.env" "안녕" | sed -E 's#/t7[ab]\)#/REPO)#g' | grep -v '^\[SCV choices\] ')"
[[ "$o1" == "$o2" ]] && ! grep -q 'SCV choices' <<<"$o1" && ok "매 턴 훅: 도구가 없으면 안내 줄이 없고, 나머지 출력은 도구가 있을 때와 같다" || fail "T7 매 턴 훅 출력: $(diff <(printf '%s' "$o1") <(printf '%s' "$o2") | head -5)"
[[ -z "$(cd "$R1" && SCV_HOST_PROFILE="$WORK/profile-none.env" bash "$GATE" line 2>/dev/null)" ]] && ok "안내 한 줄 없음" || fail "T7 안내 줄이 있다"
c=0
for x in "$C_A" "$C_B" "$C_C" "$C_D1" "$C_E"; do o="$(stop_p "$R1" "$WORK/profile-none.env" "$x" false)"; [[ -z "$o" ]] && c=$((c + 1)); done
[[ $c -eq 5 ]] && ok "글로 물어도 선택지 판정으로 막지 않는다 — 5/5" || fail "T7 막음 $c/5"

echo "── [T8] 앞쪽 안내 — 도구가 있을 때만 한 줄, 자동 알림 턴에도 ──"
line="$(bash -c 'source "$1"; scv_choice_line PickTool' _ "$LIB")"
c=0
for k in "PickTool" "recommended option first" "avoids its own problems" "over 4 questions" "over 4 options" "names, suggested values" "cancelled, stop" "contracts/choices.md"; do
  [[ "$line" == *"$k"* ]] && c=$((c + 1)) || echo "      line lacks: $k"
done
[[ -z "$(bash -c 'source "$1"; scv_choice_line ""' _ "$LIB")" ]] && c=$((c + 1)) || echo "      empty tool must print nothing"
[[ $c -eq 9 ]] && ok "순수부: 요지 8개 + 도구 없으면 빈 값" || fail "T8 순수부 $c/9"
R="$(new_repo t8)"
o="$(hook_p "$R" "$WORK/profile-pick.env" "안녕")"
[[ "$(grep -c '^\[SCV choices\] Ask decisions with PickTool' <<<"$o")" == 1 ]] && ok "사람 턴: 한 줄 실림" || fail "T8 사람 턴: $(head -3 <<<"$o")"
R="$(new_repo t8b)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null; reg_full "$R" >/dev/null
stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s' "$QUOTE" "끝.")" false >/dev/null
o="$(hook_p "$R" "$WORK/profile-full.env" $'<machine-event>\n<status>completed</status>\n</machine-event>')"
grep -q '^\[SCV choices\]' <<<"$o" && ! grep -q 'SCV 프롬프트' <<<"$o" && ok "자동 알림 턴: 안내는 실리고 등록 안내는 없다" || fail "T8 자동 턴: $o"

echo "── [T9] 규칙은 한 곳에, 나머지는 가리키기만 ──"
RULE_FLAT="$(tr '\n' ' ' < "$RULE" | tr -s ' ')"   # 문서의 줄바꿈이 문구를 끊지 않게
c=0
for k in "One decision is one question" "The recommended option comes first" "how it avoids the problems it would cause" \
         "consecutive calls, the most important first" "two steps" "one or two recommended values" \
         "do not go ahead on the recommendation" "Never end a turn by asking in text" "automatic-notification" \
         "When the host names none" "numbered table"; do
  [[ "$RULE_FLAT" == *"$k"* ]] && c=$((c + 1)) || echo "      rule lacks: $k"
done
hits="$(grep -rlF 'One decision is one question' "$CORE" 2>/dev/null | grep -vxF "$RULE" | grep -v '/tests/' || true)"
[[ -z "$hits" ]] && c=$((c + 1)) || echo "      rule text also in: $hits"
for f in protocols/regression.md contracts/host-profile.md contracts/rewrite-principle.md; do
  grep -qF 'contracts/choices.md' "$CORE/$f" && c=$((c + 1)) || echo "      no pointer in $f"
done
for k in 'protocols/help.md' 'protocols/help/full.md' 'protocols/regression.md' 'plain-language' 'Question: … options:' 'resolution order 2' 'renewed with that wording on 2026-10-01'; do
  grep -qF "$k" "$RULE" && c=$((c + 1)) || echo "      precedence lacks: $k"
done
# 도움말 답 모양의 결정 자리가 규칙을 직접 적는다(사용자 결정 2026-10-01 — 잠금은 새 문구로 다시 걸었다).
SHAPE="$(awk '/^## Answer shape/{f=1} f&&/^## /&&!/^## Answer shape/{exit} f' "$CORE/protocols/help.md" | tr '\n' ' ' | tr -s ' ')"
[[ "$SHAPE" == *"When the host names a choice tool, ask each decision through it instead"* && "$SHAPE" == *"core/contracts/choices.md"* ]] \
  && c=$((c + 1)) || echo "      help answer shape does not state the choice rule"
[[ "$SHAPE" == *"with a choice tool, one call of up to four questions"* ]] && c=$((c + 1)) || echo "      help answer shape lacks the four-per-call clause"
[[ $c -eq 24 ]] && ok "규칙 요소 11 · 한 곳뿐 · 가리키기 3 · 대체 선언 7 · 도움말 결정 자리 직접 2 — 24/24" || fail "T9 $c/24"

echo "── [T13] 취소 · 무응답 — 멈추고 추천으로 진행하지 않는다 ──"
grep -qF 'Cancelled or unanswered: do not go ahead on the recommendation' "$RULE" && grep -qF 'without ending on a question' "$RULE" \
  && [[ -z "$(stop_p "$(new_repo t13)" "$WORK/profile-pick.env" "$N_D" false)" ]] \
  && ok "규칙 문장 + 평서문으로 멈춘 답은 막히지 않는다" || fail "T13"

echo "── [T14] 단계 밖 질문 — 작업 끝의 '다음에 무엇을 할까요?' ──"
o="$(stop_p "$(new_repo t14)" "$WORK/profile-pick.env" $'작업을 마쳤습니다.\n\n다음에 무엇을 할까요?' false)"
[[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && grep -q 'PickTool' <<<"$o" && ok "막고 이유에 도구 이름" || fail "T14: [$o]"

echo "── [T15] 회귀 삭감 — 선택지로, CI 모드는 묻지 않는다 ──"
REG="$CORE/protocols/regression.md"; c=0
grep -qF 'the triage goes through it instead (`core/contracts/choices.md`)' "$REG" && c=$((c + 1)) || echo "      Never-list pointer missing"
grep -qF 'one question per failed slug with the three verdicts as options' "$REG" && c=$((c + 1)) || echo "      Step 2 pointer missing"
grep -qF -- '--ci` mode must NOT ask interactive questions' "$REG" && c=$((c + 1)) || echo "      --ci rule changed"
grep -qF 'one decisions table' "$REG" && grep -qF 'replaces the earlier' "$REG" && c=$((c + 1)) || echo "      rule-constitution phrases changed"
[[ $c -eq 4 ]] && ok "가리키기 둘 + CI 규칙 · 대체 선언 그대로 — 4/4" || fail "T15 $c/4"

# ---------------------------------------------------------------- 종료 훅의 턴 자르기 (두 번째 결함)
jl_user() { jq -cn --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}'; }
jl_meta() { jq -cn --arg t "$1" '{type:"user",isMeta:true,message:{content:[{type:"text",text:$t}]}}'; }
jl_asst() { jq -cn --arg t "$1" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"text",text:$t}]}}'; }
jl_tool() { printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}' '{"type":"user","message":{"content":[{"type":"tool_result","content":"x"}]}}'; }
stop_tr() {  # <저장소> <프로필> <원본> <마지막 답> → 종료 훅 stdout
  (cd "$1" && jq -cn --arg p "$3" --arg a "$4" '{transcript_path:$p,last_assistant_message:$a,stop_hook_active:false}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$2" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null)
}
fresh_turn() {  # <이름> → 등록까지 마친 사람 턴의 저장소
  local r; r="$(new_repo "$1")"; hook_p "$r" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null; reg_full "$r" >/dev/null; printf '%s' "$r"
}

echo; echo "test-choice-questions: pass=$PASS fail=$FAIL"
(( FAIL == 0 ))
