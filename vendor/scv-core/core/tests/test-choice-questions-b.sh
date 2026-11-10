#!/usr/bin/env bash
export SCV_STOP_MODE=block   # 0.83.0+ — 이 시험은 막힘(block)을 본다. 기본(notice)은 test-stop-notice.sh
# (b) — test-choice-questions.sh 를 나눈 조각 2/3 (CI 가장 느린 조각 줄이기). 묶어 돌리기: test-choice-questions.sh
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
# (0.82.0+) 끝 보고 확인 범위 검사(SCV_FINISH_REPORT)는 이 시험의 대상이 아니다 — 꺼서 다른 검사만 본다(설정 읽기는 환경 변수를 먼저 본다).
export SCV_FINISH_REPORT=off
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

# ── 앞 조각에서 정의된 도우미(그대로 옮김) ──
C_F1=$'어떻게 진행할까요?\n\n1. A 방식 (추천)\n2. B 방식'
C_F2=$'Which approach do you prefer?\n- Option A (recommended)\n- Option B'
C_F3='…어느 쪽으로 할지 정해 주세요.'
C_F4='Let me know which one you want.'
C_F5='진행할까요? 🙂'
C_F6='(이대로 진행할까요?)'
C_F7='Ready to merge? :)'
C_F8='진행할까요? **(추천: 예)**'
C_F9=$'Done.\n\nShall I \xe2\x80\x9cship it?\xe2\x80\x9d'
N_F1=$'| 질문 | 고른 것 |\n|---|---|\n| 릴리스할까? | 예 |'
N_F2=$'| 항목 | 상태 |\n|---|---|\n| 원격 CI | ? |'
N_F3='말씀하신 대로 다 추천대로 반영했습니다.'
N_F4='バージョン番号だけ上げました。'
N_F5='번호로 골라 주신 2번으로 바꿨습니다.'
N_F6='The script will pick a number between 1 and 10.'
N_F7=$'바꾼 것:\n- a\n- b'
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
C_G13='どちらにしますか？おすすめはAです。'
C_G14='Should I deploy? I recommend yes. Logs: https://x.example/run?id=3'
C_G15='어떤 걸 할까요? 네 가지 방법이 있습니다. 추천은 A입니다.'
N_G1='PR 번호나 링크가 필요하면 말씀해 주세요.'
N_G2='원하시면 로그인한 뒤 알려 주세요.'
N_G3="'다 끝난거 맞아?'에 답하면, 네 — 모두 끝났습니다. 더 필요하면 알려 주세요."
N_G4='결과: https://example.com/run?id=3 — 추천 설정 그대로 통과했습니다.'
N_G5='어느 부분이 걸리시는지 짚어 주시면 그 부분만 더 풀어 드리겠습니다.'
N_G6=$'왜 막혔나? 이번 턴이 길어서였다.\n\n추천 수정은 넓혀 찾기였고, 반영했습니다.'
N_G7='모두 반영했습니다. 궁금한 점이 있으면 언제든지 알려 주세요.'
N_G8='얼마든지 말씀해 주세요.'
N_G9='Did all tests pass? Yes — all 55 passed with the recommended settings.'
N_G10='Is it merged? Yes. If you need anything else, let me know.'
N_G11='The fix uses `a ?? b`, which is the recommended idiom here.'
N_G12='왜 막혔나? 이번 턴이 길어서였다. 추천 수정은 넓혀 찾기였고, 반영했습니다.'
N_G13=$'Was it the cache? It was.\n\xc2\xa0\nThe recommended settings are unchanged.'
N_G14='어떤 걸 할까요? 네 가지 방법이 있습니다.'
C_H=( 'Should I delete `old.sh`? I recommend yes.' 'Should I bump `VERSION`? Let me know.'
      'Should I deploy? Logs: https://x.example/run?id=3 — I recommend yes.'
      "Should I merge it? You asked 'is it done?' — I recommend merging."
      'A안으로 갈지 B안으로 갈지 알려 주세요. 다른 궁금한 점도 언제든지 알려 주세요.'
      'Should I deploy now?? I recommend yes.' 'Should I merge? Yes or no — I recommend yes.'
      $'Should I deploy now?\n\xc2\xa0' '진행하시겠습니까? 추천은 예입니다.' $'어느 쪽으로 할까요?\n추천은 A입니다.' )
N_H=( 'テストは通りましたか？　はい、すべて通りました。おすすめは今の設定のままです。'
      'ご質問「どちらが良いですか？」への答え：おすすめはAです。'
      '原因は何だったのか？古いキャッシュでした。おすすめは毎回の削除です。'
      '무엇이 문제였나? 캐시였습니다. 궁금한 점이 있으면 언제든지 알려 주세요.'
      'Was it the cache? It was. If you need anything else, let me know.'
      '왜 느렸나? 캐시 때문이었다. 설정을 추천 값으로 되돌렸습니다.'
      'Did it pass? Yes — I recommend keeping the current settings.'
      'The fix uses `a ?? b`, which I recommend here.' )
C_I=( $'현재 상태: 통과.\n다음 행동: CHANGELOG 도 고칠까요? 추천은 예입니다.\n검증 기준: 테스트 통과.'
      $'Summary:\n- Next: should I bump VERSION? I recommend yes.' 'Should I deploy now? CI is green. Let me know.'
      $'Should I update the CHANGELOG?\n\nI recommend yes.' $'Which option?\n1. A\n2. B\nI recommend option 2.'
      "Should I merge? I'd recommend yes." 'どちらにしますか？Aがおすすめです。' 'A안으로 할까요? A안을 권장합니다.'
      '어떻게 할까요? 말씀해 주시면 진행하겠습니다.' )
N_I=( $'**Is it safe to merge?**\nYes — I recommend merging after CI.' 'Why did it fail? The window was short. Recommended: widen it.'
      '왜 막혔을까요? 창이 짧았습니다. 추천은 넓혀 찾기입니다.' 'Was it the cache? Yes - I recommend clearing it.'
      'Was it the cache? It was. If you need anything else, let me know.' )
C_J=$'**정해 주실 것** (예: "1 좋아, 2 좋아"처럼 번호로 답하거나, 원하는 이름을 적어 주세요)\n\n| # | 질문 | 내 추천 |\n|---|---|---|\n| 1 | 계획 폴더 이름 | `login-retry` |\n| 2 | 계획 제목 | "로그인 자동 재시도" |\n\n이름과 제목이 정해지면 나머지 질문 두 가지를 이어서 드리겠습니다.'
N_J=$'| # | 질문 | 고른 것 |\n|---|---|---|\n| 1 | 계획 폴더 이름 | login-retry |\n\n고르신 대로 계획 폴더를 만들었습니다.'
g() { bash -c 'source "$1"; scv_choice_gate "$2" "$3" "$4"' _ "$LIB" "$@"; }
RULE_FLAT="$(tr '\n' ' ' < "$RULE" | tr -s ' ')"   # 문서의 줄바꿈이 문구를 끊지 않게
SHAPE="$(awk '/^## Answer shape/{f=1} f&&/^## /&&!/^## Answer shape/{exit} f' "$CORE/protocols/help.md" | tr '\n' ' ' | tr -s ' ')"
REG="$CORE/protocols/regression.md"; c=0
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
echo "── [T19] 턴 자르기 — 내부 메시지 뒤에 끝나도 앞서 보인 인용을 인정한다 ──"
R="$(fresh_turn t19)"; TR="$WORK/t19.jsonl"
{ jl_user "로그인 고쳐"; jl_asst "$(printf '%s\n\n결론.' "$QUOTE")"; jl_meta "Base directory for this skill: /x"; jl_tool; jl_asst "끝났습니다."; } > "$TR"
o="$(stop_tr "$R" "$WORK/profile-full.env" "$TR" "끝났습니다.")"
[[ -z "$o" ]] && ok "내부 메시지(스킬 불러오기)는 경계가 아니다 — 막지 않음" || fail "T19 (a): [$o]"
R="$(fresh_turn t19b)"; TR="$WORK/t19b.jsonl"
{ jl_user "로그인 고쳐"; jl_asst "$(printf '%s\n\n결론.' "$QUOTE")"; jl_user "다음"; jl_tool; jl_asst "끝났습니다."; } > "$TR"
o="$(stop_tr "$R" "$WORK/profile-full.env" "$TR" "끝났습니다.")"
[[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && grep -q '인용' <<<"$o" && ok "진짜 사람 프롬프트는 지금처럼 경계 — 그 뒤에 인용이 없으면 막는다" || fail "T19 (b): [$o]"

echo "── [T20] 긴 턴 — 원본 창(400줄)을 넘어도 이번 사람 턴의 인용을 인정한다 ──"
R="$(fresh_turn t20)"; TR="$WORK/t20.jsonl"
{ jl_user "로그인 고쳐"; jl_asst "$(printf '%s\n\n결론.' "$QUOTE")"; for i in $(seq 1 230); do jl_tool; done; jl_asst "끝났습니다."; } > "$TR"
o="$(stop_tr "$R" "$WORK/profile-full.env" "$TR" "끝났습니다.")"
[[ "$(wc -l < "$TR" | tr -d ' ')" -gt 400 && -z "$o" ]] && ok "$(wc -l < "$TR" | tr -d ' ')줄 턴: 창을 넓혀 경계를 찾고 막지 않음" || fail "T20 (a): [$o]"
R="$(fresh_turn t20b)"; TR="$WORK/t20b.jsonl"
{ for i in $(seq 1 230); do jl_tool; done; jl_asst "끝났습니다."; } > "$TR"
o="$(stop_tr "$R" "$WORK/profile-full.env" "$TR" "끝났습니다.")"
[[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && grep -q 'turn-boundary=not-found' "$R/scv/journal/.help-drift" 2>/dev/null \
  && ok "경계를 끝내 못 찾으면 지금처럼(마지막 메시지만) 판정하고, 판정 기록에 남긴다" || fail "T20 (b): [$o] / $(tail -2 "$R/scv/journal/.help-drift" 2>/dev/null)"

# ---------------------------------------------------------------- 문제 표 · 문제 칸 막기 (세 번째 요구)
echo "── [T23] 문제 표 · '생길 수 있는 문제' 칸 — 판정 (세 언어) ──"
MPLIB="$CORE/scripts/lib/model-prompting.sh"
pt() { bash -c 'source "$1"; scv_mp_answer_has_problem_table "$2"' _ "$MPLIB" "$1"; }
c=0
for x in "| 단위 | 해결책 | 추천 | 생길 수 있는 문제 |" "| 번호 | 위치 | 조건 | 깨지는 것 | 확인 |" \
         "| Unit | Solutions | Recommendation | Possible problems |" "| No. | Location | Condition | What breaks | Check |" \
         "| 単位 | 解決策 | 推奨 | 起こりうる問題 |" "| 番号 | 場所 | 条件 | 壊れるもの | 確認 |"; do
  [[ "$(pt "$(printf '결론.\n\n%s\n|---|\n' "$x")")" == 1 ]] && c=$((c + 1)) || echo "      ✖ not caught: $x"
done
for x in $'| 단위 | 해결책 | 추천 |\n|---|---|---|\n| a | ①x | ① 이유 |' $'설명.\n```\n| 번호 | 위치 | 조건 | 깨지는 것 | 확인 |\n```' \
         $'> | 단위 | 해결책 | 추천 | 생길 수 있는 문제 |' $'문제 표는 이제 쓰지 않는다 — 생길 수 있는 문제는 해결책이 막는다.'; do
  [[ "$(pt "$x")" == 0 ]] && c=$((c + 1)) || echo "      ✖ wrongly caught: $(head -c 50 <<<"$x")"
done
[[ $c -eq 10 ]] && ok "잡을 것 6(한 · 영 · 일 × 문제 칸 · 문제 표) · 잡지 않을 것 4(세 칸 단위 표 · 코드 블록 · 인용 · 줄글)" || fail "T23 판정 $c/10"

echo "── [T23] 문제 표 · 문제 칸 — 종료 훅이 같은 턴에 한 번 막는다 ──"
PTA=$'| 단위 | 해결책 | 추천 | 생길 수 있는 문제 |\n|---|---|---|---|\n| a | ①x | ① 이유 | P1 |'
R="$(fresh_turn t23)"
o="$(stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s\n\n%s\n\n%s' "$QUOTE" "결론." "$PTA" "끝났습니다.")" false)"
[[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && grep -q 'SCV 원칙' <<<"$o" && grep -q '해결책 안에서 막아' <<<"$o" \
  && ok "문제 칸이 있는 끝 메시지 — 막음, 이유에 해결책 안에서 막으라는 말" || fail "T23 막기: [$o]"
rm -f "$(tf "$R" .help-warn)"
o="$(stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s\n\n%s' "$QUOTE" "결론." "$PTA")" true)"
[[ -z "$o" ]] && grep -q '^\[SCV 가이드\] 직전 턴: \[SCV 원칙\]' "$(tf "$R" .help-warn)" 2>/dev/null && ok "이미 계속 중: 막지 않고 다음 턴 경고" || fail "T23 계속 중: [$o]"
o="$(stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s\n\n%s\n\n%s' "$QUOTE" "결론." "$PTA" "릴리스할까요?")" false)"
# v0.64.2+ (계획 stop-gates-each-once) — 예전에는 원칙 이유 하나만 냈다. 이제 한 멈춤에 걸린 이유를 함께 싣는다.
_r="$(jq -r .reason <<<"$o" 2>/dev/null)"
[[ "$_r" == *'[SCV 원칙]'*'[SCV 선택지]'* ]] && ok "문제 표와 글 질문이 함께 있으면 두 이유를 한 번에(원칙 → 선택지 순)" || fail "T23 함께 싣기: [$o]"
R="$(fresh_turn t23off)"; printf '{\n  "SCV_REWRITE_PRINCIPLE": "off"\n}\n' > "$R/scv/scv_settings.json"
o="$(stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s\n\n%s' "$QUOTE" "결론." "$PTA")" false)"
[[ -z "$o" ]] && ok "원칙 스위치 off — 판정 없음(이 기능 전과 같다)" || fail "T23 off: [$o]"
o="$(stop_p "$(new_repo t23nc)" "$WORK/profile-pick.env" "$(printf '%s\n\n%s' "결론." "$PTA")" false)"
[[ -z "$o" ]] && ok "원칙이 실리지 않는 호스트(가이드 색인 없음) — 판정 없음" || fail "T23 no checklist: [$o]"

echo "── [T25] 프로젝트 스위치 · 끝 메시지 없음 · 실행부 인자 ──"
R="$(new_repo t25)"; printf '{\n  "SCV_CHOICE_GATE": "off"\n}\n' > "$R/scv/scv_settings.json"
o="$(hook_p "$R" "$WORK/profile-pick.env" "안녕")"; ! grep -q 'SCV choices' <<<"$o" && ok "SCV_CHOICE_GATE=off — 안내 줄 없음" || fail "T25 off 안내"
o="$(stop_p "$R" "$WORK/profile-pick.env" "$C_E" false)"; [[ -z "$o" ]] && ok "SCV_CHOICE_GATE=off — 글로 물어도 막지 않음" || fail "T25 off 판정: [$o]"
R="$(new_repo t25b)"; TR="$WORK/t25b.jsonl"; { jl_user "q"; jl_asst "$C_E"; } > "$TR"
o="$(cd "$R" && jq -cn --arg p "$TR" '{transcript_path:$p}' | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile-pick.env" GIT_AUTHOR_NAME=t bash "$STOP_HOOK" 2>/dev/null)"
[[ -z "$o" ]] && ok "호스트가 끝 메시지를 주지 않으면 판정하지 않는다(원본의 앞선 글로 막지 않음)" || fail "T25 끝 메시지 없음: [$o]"
rc="$(printf 'x?' | SCV_HOST_PROFILE="$WORK/profile-pick.env" perl -e 'alarm 5; exec @ARGV' bash "$GATE" stop --active >/dev/null 2>&1; echo $?)"
[[ "$rc" == 0 ]] && ok "값 없는 --active 에도 끝난다" || fail "T25 --active 값 없음 rc=$rc"

echo "── [T26] 긴 턴 — 종료 훅이 이번 턴만 작게 잘라 빨리 끝난다 ──"
R="$(fresh_turn t26)"; TR="$WORK/t26.jsonl"
{ jl_user "로그인 고쳐"; jl_asst "$(printf '%s\n\n결론.' "$QUOTE")"
  for i in $(seq 1 1500); do jl_tool; jl_asst "진행 메모 $i — 이번 단계에서 확인한 것을 적는다. 다음 단계로 넘어간다."; done; } > "$TR"
t0=$(date +%s); o="$(stop_tr "$R" "$WORK/profile-full.env" "$TR" "끝났습니다.")"; t1=$(date +%s)
[[ -z "$o" ]] && ok "$(wc -l < "$TR" | tr -d ' ')줄 · 답 1501개 턴: 앞선 인용을 찾고 막지 않음 ($((t1 - t0))s)" || fail "T26: [$o]"
(( t1 - t0 <= 30 )) && ok "30초 안에 끝난다 (검토 전 방식은 같은 꼴에서 수십 초)" || fail "T26 느림: $((t1 - t0))s"

# ---------------------------------------------------------------- 추정 해소 (다섯 번째 요구)
echo "── [T27] 사람 없는 실행(호스트가 도구를 빼는 조건) — 안내도 막기도 없다 ──"
ow() { bash -c 'source "$1"; scv_choice_off_when "$2" "$3"' _ "$LIB" "$1" "$2"; }
c=0
[[ "$(ow 'X_ATT=0' '0')" == 1 ]] && c=$((c + 1)); [[ "$(ow 'X_ATT=0' '1')" == 0 ]] && c=$((c + 1))
[[ "$(ow 'X_ATT=0' '')" == 0 ]] && c=$((c + 1)); [[ "$(ow '' '0')" == 0 ]] && c=$((c + 1))
[[ "$(ow 'bad name=0' '0')" == 0 ]] && c=$((c + 1)); [[ "$(ow 'X_ATT=' '')" == 0 ]] && c=$((c + 1))
[[ $c -eq 6 ]] && ok "순수 판정 6가지(값 같음만 1 · 다름 · 비어 있음 · 조건 없음 · 틀린 이름 · 빈 값은 0)" || fail "T27 순수 $c/6"
{ cat "$WORK/profile-pick.env"; printf 'SCV_CHOICE_OFF_WHEN=SCV_TEST_ATTENDED=0\n'; } > "$WORK/profile-off.env"
R="$(new_repo t27)"
o="$(SCV_TEST_ATTENDED=0 hook_p "$R" "$WORK/profile-off.env" "안녕")"; ! grep -q 'SCV choices' <<<"$o" && ok "조건이 맞는 실행(값 0) — 매 턴 안내 줄 없음" || fail "T27 안내 0"
o="$(SCV_TEST_ATTENDED=0 stop_p "$R" "$WORK/profile-off.env" "$C_E" false)"; [[ -z "$o" ]] && ok "조건이 맞는 실행 — 글로 물어도 막지 않음(번호 표로 묻는 예전 길)" || fail "T27 막기 0: [$o]"
o="$(SCV_TEST_ATTENDED=1 hook_p "$R" "$WORK/profile-off.env" "안녕")"; grep -q 'SCV choices' <<<"$o" && ok "사람이 있는 실행(값 1) — 안내 줄 그대로" || fail "T27 안내 1"
o="$(SCV_TEST_ATTENDED=1 stop_p "$R" "$WORK/profile-off.env" "$C_E" false)"; [[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && ok "사람이 있는 실행 — 글로 물으면 그대로 막는다" || fail "T27 막기 1: [$o]"
o="$(env -u SCV_TEST_ATTENDED bash -c 'cd "$1" && jq -cn "{prompt:\"안녕\",session_id:\"s1\"}" | CLAUDE_PLUGIN_ROOT="$2" SCV_HOST_PROFILE="$3" bash "$2/template/hooks/on-user-prompt.sh" 2>/dev/null' _ "$R" "$CORE" "$WORK/profile-off.env")"
grep -q 'SCV choices' <<<"$o" && ok "환경 변수가 없는 실행 — 도구가 있다고 본다(조건은 값이 같을 때만)" || fail "T27 변수 없음"

echo "── [T28] 코덱스 모양 원본 — 넓혀 찾지 않고, 판정은 이 기능 전과 같다 ──"
cx_line() { jq -cn --arg r "$1" --arg t "$2" '{type:"response_item",payload:{type:"message",role:$r,content:[{type:(if $r=="user" then "input_text" else "output_text" end),text:$t}]}}'; }
R="$(fresh_turn t28)"; TR="$WORK/t28.jsonl"
{ printf '%s\n' '{"type":"session_meta","payload":{"originator":"fixture"}}'; cx_line user "로그인 고쳐"; cx_line assistant "$(printf '%s\n\n결론.' "$QUOTE")"
  awk 'BEGIN { for (i = 0; i < 45000; i++) printf "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"n\":%d}}\n", i }'; cx_line assistant "끝났습니다."; } > "$TR"
t0=$(date +%s); o="$(stop_tr "$R" "$WORK/profile-full.env" "$TR" "$(printf '%s\n\n결론.' "$QUOTE")")"; t1=$(date +%s)
[[ -z "$o" ]] && ! grep -q 'turn-boundary=not-found' "$R/scv/journal/.help-drift" 2>/dev/null \
  && ok "$(wc -l < "$TR" | tr -d ' ')줄 코덱스 모양: 끝 메시지의 인용으로 통과, 경계 없음 기록을 남기지 않는다 ($((t1 - t0))s)" || fail "T28 (a): [$o] / $(tail -1 "$R/scv/journal/.help-drift" 2>/dev/null)"
_fns="$(sed -n '/^_scv_turn_stream() {/,/^}/p;/^_scv_turn_stream_wide() {/,/^}/p' "$CORE/scripts/lib/turn-stream.sh")"
_wide="$(TRANSCRIPT="$TR" bash -c 'eval "$1"; _scv_turn_stream_wide' _ "$_fns")"
[[ "$_wide" == "N" ]] && ok "첫 창(400줄)에서 '이 형식이 아님'(N)으로 끝난다 — 넓혀 찾지 않는다" || fail "T28 넓혀 찾기: [$(head -c 40 <<<"$_wide")]"
R="$(fresh_turn t28b)"
o="$(stop_tr "$R" "$WORK/profile-full.env" "$TR" "끝났습니다.")"
[[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] && ok "끝 메시지에 인용이 없으면 이 기능 전처럼 막는다(코덱스는 끝 메시지로만 판정)" || fail "T28 (b): [$o]"

echo "── [T29] 도구 출처 표시만 있는 사용자 몫 글도 경계가 아니다 ──"
R="$(fresh_turn t29)"; TR="$WORK/t29.jsonl"
{ jl_user "로그인 고쳐"; jl_asst "$(printf '%s\n\n결론.' "$QUOTE")"
  jq -cn '{type:"user",sourceToolUseID:"toolu_fixture",message:{content:[{type:"text",text:"Base directory for this skill: /x"}]}}'; jl_tool; jl_asst "끝났습니다."; } > "$TR"
o="$(stop_tr "$R" "$WORK/profile-full.env" "$TR" "끝났습니다.")"
[[ -z "$o" ]] && ok "내부 표시가 없어도 도구 출처 표시가 있으면 경계가 아니다 — 막지 않음" || fail "T29: [$o]"

echo "── [T30] 실제 긴 턴 모양 — 이 릴리스를 마무리하던 세션에서 이전 종료 훅이 막은 꼴 ──"
# 원본 467줄: 16번째 줄 사람 프롬프트 · 43번째 줄 스킬 불러오기(내부 표시 + 도구 출처) · 231번째 줄 인용 · 끝은 인용 없는 답.
jl_attach() { printf '%s\n' '{"type":"attachment","attachment":{"type":"fixture"}}'; }
R="$(fresh_turn t30)"; TR="$WORK/t30.jsonl"
{ for i in $(seq 1 15); do jl_attach; done; jl_user "어디까지 됐어?"; for i in $(seq 1 13); do jl_tool; done
  jq -cn '{type:"user",isMeta:true,sourceToolUseID:"toolu_fixture",message:{content:[{type:"text",text:"Base directory for this skill: /x"}]}}'
  for i in $(seq 1 93); do jl_tool; done; jl_attach; jl_asst "$(printf '%s\n\n결론.' "$QUOTE")"
  for i in $(seq 1 117); do jl_tool; done; jl_attach; jl_asst "검사 사슬을 배경에 걸어 두었습니다."; } > "$TR"
_qline="$(grep -n 'Rewritten request' "$TR" | head -1 | cut -d: -f1)"
_win_u="$(tail -n 400 "$TR" | jq -Rr 'fromjson? | select(.type == "user" and (.isMeta != true) and ((.message.content | type) == "array") and any(.message.content[]; .type == "text")) | "U"' | grep -c U)"
[[ "$(wc -l < "$TR" | tr -d ' ')" == 467 && "$_qline" == 231 && "$_win_u" == 0 ]] && ok "모양 그대로: 467줄 · 인용 231번째 줄 · 끝 400줄 안의 사람 프롬프트 0개(이전 훅이 빈 턴으로 본 조건)" || fail "T30 모양: $(wc -l < "$TR") / $_qline / $_win_u"
o="$(stop_tr "$R" "$WORK/profile-full.env" "$TR" "검사 사슬을 배경에 걸어 두었습니다.")"
[[ -z "$o" ]] && ok "넓혀 찾아 16번째 줄을 경계로 삼고, 231번째 줄의 인용을 인정한다 — 막지 않음" || fail "T30: [$o]"

echo "── [T33] 시스템 bash(맥 기본 3.2)로 — 긴 답 · 긴 턴의 종료 훅이 빠르고, 매 턴 출력이 같다 ──"
# 훅은 PATH 의 bash 로 돈다 — 맥 기본 PATH 면 bash 3.2. 3.2 는 큰 글의 패턴 치환(${x//…/…})이 매우 느려, 고치기 전에는 답 하나
# 10만 바이트에서 158초 · 4,500줄 턴에서 79초 걸렸다(2026-10-01 실측). 리눅스의 /bin/bash 는 최신이라 그냥 통과하고, 맥 CI 가 지킨다.
if [[ -x /bin/bash ]]; then
  SYSB="$WORK/sysbash"; mkdir -p "$SYSB"; ln -sf /bin/bash "$SYSB/bash"; v="$(/bin/bash -c 'echo "$BASH_VERSION"')"
  stop_sys() {  # <저장소> <프로필> <원본> <마지막 답> → 시스템 bash 로 돈 종료 훅 stdout
    (cd "$1" && jq -cn --arg p "$3" --arg a "$4" '{transcript_path:$p,last_assistant_message:$a,stop_hook_active:false}' \
       | PATH="$SYSB:$PATH" CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$2" GIT_AUTHOR_NAME="Hook User" /bin/bash "$STOP_HOOK" 2>/dev/null)
  }
  R="$(fresh_turn t33a)"; TR="$WORK/t33a.jsonl"
  BIG="$(printf '%s\n\n결론.\n\n' "$QUOTE"; for i in $(seq 1 1500); do printf '진행 메모 %s — 이번 단계에서 확인한 것을 적는다.\n' "$i"; done)"
  { jl_user "로그인 고쳐"; jl_asst "$BIG"; } > "$TR"
  t0=$(date +%s); o="$(stop_sys "$R" "$WORK/profile-full.env" "$TR" "$BIG")"; t1=$(date +%s)
  [[ -z "$o" ]] && (( t1 - t0 <= 30 )) && ok "답 하나 $(printf '%s' "$BIG" | wc -c | tr -d ' ')바이트 — 시스템 bash $v 로 $((t1 - t0))s, 막지 않음" || fail "T33 (a) $((t1 - t0))s: [$o]"
  # 첫 줄에 물음표가 있는 큰 끝 메시지 — 판정의 (d) 가 큰 글을 제곱으로 자르면 3.2 에서 수십 초(독립 검토 2026-10-02)
  BIGQ="$(printf 'What did it find? Log:\n'; for i in $(seq 1 2000); do printf -- '- note %s: verified this step. 확인했다.\n' "$i"; done)"
  t0=$(date +%s); o="$(PATH="$SYSB:$PATH" /bin/bash -c 'source "$1"; scv_asks_in_text "$(scv_answer_body "$2")"' _ "$LIB" "$(printf '%s' "$BIGQ" | head -c 65536)")"; t1=$(date +%s)
  [[ "$o" == 0 ]] && (( t1 - t0 <= 10 )) && ok "첫 줄 물음표 · 64KB 끝 메시지 판정 — 시스템 bash $v 로 $((t1 - t0))s, 묻지 않음" || fail "T33 (d) $((t1 - t0))s: [$o]"
  R="$(fresh_turn t33b)"
  t0=$(date +%s); o="$(stop_sys "$R" "$WORK/profile-full.env" "$WORK/t26.jsonl" "끝났습니다.")"; t1=$(date +%s)
  [[ -z "$o" ]] && (( t1 - t0 <= 30 )) && ok "$(wc -l < "$WORK/t26.jsonl" | tr -d ' ')줄 턴 — 시스템 bash $v 로 $((t1 - t0))s, 앞선 인용을 찾고 막지 않음" || fail "T33 (b) $((t1 - t0))s: [$o]"
  R="$(new_repo t33c)"; cp -R "$R" "$R.bak"
  o1="$(cd "$R" && jq -cn '{prompt:"로그인 고쳐",session_id:"s1"}' | PATH="$SYSB:$PATH" CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile-full.env" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
  rm -rf "$R"; cp -R "$R.bak" "$R"
  o2="$(hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐")"
  [[ -n "$o1" && "$o1" == "$o2" ]] && ! grep -qF 'id\}' <<<"$o1" \
    && ok "매 턴 출력이 시스템 bash $v 와 지금 bash 에서 같다(모델 id 자리 표시에 역슬래시 없음)" || fail "T33 (c): $(diff <(printf '%s\n' "$o1") <(printf '%s\n' "$o2") | head -3)"
else
  echo "  (시스템 bash 없음 — T33 생략)"
fi

# ---------------------------------------------------------------- 검사마다 한 턴에 한 번 (v0.64.2+, 계획 stop-gates-each-once)
# 2026-10-02 설치본 0.64.1 대화형 재현: 등록 없이 결정 표로 끝난 답이 등록 이유로만 막히고, 등록 뒤 같은 결정 표는 계속 중이라
# 다음 턴 경고로만 남아 화면에 그대로 보였다. 이제 세 검사(등록 · 원칙 · 선택지)가 각자 한 턴에 한 번씩 막고, 한 멈춤에 걸린 이유는
# 함께 싣는다. 계획 TESTS.md 번호와의 대응: T35.1~T35.9 · T35.11 · T35.12 = T1~T9 · T11 · T12, T35.0 = T14, T35.10 = T15,
# T35.13~T35.18 = T16~T21 (T10 은 이 파일 · test-model-prompting 전체가 통과하는 것, T13 은 릴리스 뒤 설치본 실측).
sg_tags() {  # <종료 훅 출력> → "pass" | "block:<꼬리표들>" — 이유 줄 머리의 꼬리표를 나온 순서대로(prompt · principle · choice)
  local o="$1" r l names=""
  [[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block ]] || { printf 'pass'; return 0; }
  r="$(jq -r .reason <<<"$o" 2>/dev/null)"
  while IFS= read -r l; do
    case "$l" in
      '[SCV 프롬프트]'*) names="$names,prompt" ;;
      '[SCV 원칙]'*)     names="$names,principle" ;;
      '[SCV 선택지]'*)   names="$names,choice" ;;
    esac
  done <<<"$r"
  printf 'block:%s' "${names#,}"
}
sg_warns() { grep -c '^\[SCV 가이드\] 직전 턴:' "$(tf "$1" .help-warn)" 2>/dev/null || true; }
SG_DONE="작업을 마쳤습니다."                                                       # 묻지도 표도 없음
SG_QJ="$(printf '%s\n\n%s\n\n%s' "$QUOTE" "결론." "$C_J")"                         # 인용 + 실측 결정 표로 끝
SG_QP="$(printf '%s\n\n%s\n\n%s\n\n%s' "$QUOTE" "결론." "$PTA" "끝났습니다.")"       # 인용 + 문제 표
SG_ALL="$(printf '%s\n\n%s' "$PTA" "$C_J")"                                         # 인용 없음 + 문제 표 + 결정 표로 끝

echo; echo "test-choice-questions: pass=$PASS fail=$FAIL"
(( FAIL == 0 ))
