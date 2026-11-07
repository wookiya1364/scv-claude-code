#!/usr/bin/env bash
export SCV_STOP_MODE=block   # 0.83.0+ — 이 시험은 막힘(block)을 본다. 기본(notice)은 test-stop-notice.sh
# (c) — test-choice-questions.sh 를 나눈 조각 3/3 (CI 가장 느린 조각 줄이기). 묶어 돌리기: test-choice-questions.sh
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
printf '# source: common.md\ngoal\tState the goal\tfixture quote a\nfinish\tState the done condition\tfixture quote b\n' > "$WORK/guides-cl/checklist-common.tsv"
printf '# source: model-a.md\nfinish\tState the done condition precisely\tfixture quote c\nsources\tName the sources to check\tfixture quote d\n' > "$WORK/guides-cl/checklist-model-a.tsv"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\nSCV_AUTO_PROMPT_TAGS=machine-event\nSCV_CHOICE_TOOL=PickTool\n' "$WORK/guides-cl"; } > "$WORK/profile-full.env"
SUB_OK="$(printf 'goal | msg | fix the login bug\nfinish | ctx | conversation turn 2: the test passes\nsources | asked | which log file? (recommended: app.log)\nrewrite | - | Fix the login bug until the login test passes')"
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
MPLIB="$CORE/scripts/lib/model-prompting.sh"
pt() { bash -c 'source "$1"; scv_mp_answer_has_problem_table "$2"' _ "$MPLIB" "$1"; }
PTA=$'| 단위 | 해결책 | 추천 | 생길 수 있는 문제 |\n|---|---|---|---|\n| a | ①x | ① 이유 | P1 |'
ow() { bash -c 'source "$1"; scv_choice_off_when "$2" "$3"' _ "$LIB" "$1" "$2"; }
cx_line() { jq -cn --arg r "$1" --arg t "$2" '{type:"response_item",payload:{type:"message",role:$r,content:[{type:(if $r=="user" then "input_text" else "output_text" end),text:$t}]}}'; }
jl_attach() { printf '%s\n' '{"type":"attachment","attachment":{"type":"fixture"}}'; }
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
echo "── [T35.0] 순수부 — 이미 전달 · 기록 · 지우기 · 이유 합치기 ──"
SGL="$CORE/scripts/lib/stop-gates.sh"
sgf() { bash -c 'source "$1"; shift; "$@"' _ "$SGL" "$@"; }
U=$'\x1f'; c=0; n=0
sgc() { n=$((n + 1)); [[ "$2" == "$3" ]] && c=$((c + 1)) || echo "      ✖ $1: [$(printf '%s' "$2" | tr '\037' '|')] ≠ [$(printf '%s' "$3" | tr '\037' '|')]"; }
sgc "첫 멈춤은 아무것도 전달 전"        "$(sgf scv_gates_delivered choice 0 S T "S${U}T${U}choice")" 0
sgc "턴 표 없음 — 이 기능 전과 같다"     "$(sgf scv_gates_delivered choice 1 S "" "")" 1
sgc "세션 id 없음 — 이 기능 전과 같다"   "$(sgf scv_gates_delivered choice 1 "" T "${U}T${U}prompt")" 1
sgc "계속 중 · 이번 턴 기록 없음 — 이 기능 전과 같다" "$(sgf scv_gates_delivered choice 1 S T "")" 1
sgc "기록에 있는 검사"                 "$(sgf scv_gates_delivered choice 1 S T "S${U}T${U}prompt,choice")" 1
sgc "기록에 없는 검사"                 "$(sgf scv_gates_delivered principle 1 S T "S${U}T${U}prompt,choice")" 0
sgc "다른 턴 표의 기록 — 이 기능 전과 같다" "$(sgf scv_gates_delivered principle 1 S T "S${U}X${U}choice")" 1
sgc "다른 세션의 기록 — 이 기능 전과 같다" "$(sgf scv_gates_delivered principle 1 S T "B${U}T${U}choice")" 1
sgc "깨진 기록(칸 하나)"               "$(sgf scv_gates_delivered choice 1 S T "garbage")" 1
sgc "깨진 기록(칸 둘)"                 "$(sgf scv_gates_delivered choice 1 S T "S${U}T")" 1
sgc "깨진 기록(칸 넷)"                 "$(sgf scv_gates_delivered choice 1 S T "S${U}T${U}a${U}b")" 1
sgc "이름이 겹치는 검사(부분 일치 아님)"  "$(sgf scv_gates_delivered choice 1 S T "S${U}T${U}choices")" 0
sgc "첫 멈춤 기록은 새로 시작"           "$(sgf scv_gates_record S T "S${U}T${U}choice" 0 principle)" "S${U}T${U}principle"
sgc "계속 중 기록은 이번 턴 것에 더함"     "$(sgf scv_gates_record S T "S${U}T${U}prompt" 1 choice)" "S${U}T${U}prompt,choice"
sgc "계속 중 · 다른 세션 기록은 새로"      "$(sgf scv_gates_record S T "B${U}T${U}prompt" 1 choice)" "S${U}T${U}choice"
sgc "같은 검사는 한 번만 적힌다"          "$(sgf scv_gates_record S T "S${U}T${U}choice" 1 choice,choice)" "S${U}T${U}choice"
sgc "막은 검사 없음 — 쓰지 않음"          "$(sgf scv_gates_record S T "" 0 "")" ""
sgc "턴 표 없음 — 쓰지 않음"             "$(sgf scv_gates_record S "" "" 0 choice)" ""
sgc "첫 멈춤 · 같은 세션 기록 — 지운다"    "$(sgf scv_gates_drop S "S${U}T${U}choice" 0)" 1
sgc "첫 멈춤 · 다른 세션 기록 — 둔다"      "$(sgf scv_gates_drop S "B${U}T${U}choice" 0)" 0
sgc "첫 멈춤 · 깨진 기록 — 지운다"         "$(sgf scv_gates_drop S "garbage" 0)" 1
sgc "계속 중에는 지우지 않는다"           "$(sgf scv_gates_drop S "S${U}T${U}choice" 1)" 0
sgc "이유 합치기 — 빈 것은 빼고 순서대로"  "$(sgf scv_gates_reason a "" c)" $'a\nc'
sgc "이유 합치기 — 모두 비면 빈 값"        "$(sgf scv_gates_reason "" "" "")" ""
[[ $c -eq $n ]] && ok "순수부 $n/$n" || fail "T35.0 순수부 $c/$n"

echo "── [T35.1] 재현 순서 — 첫 멈춤에 등록 · 선택지 두 이유가 함께 ──"
R="$(new_repo sg1)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
o="$(stop_p "$R" "$WORK/profile-full.env" "$C_J" false)"
[[ "$(sg_tags "$o")" == "block:prompt,choice" ]] && ok "등록 없이 결정 표로 끝 — 한 번의 막기에 [SCV 프롬프트] → [SCV 선택지]" || fail "T35.1: $(sg_tags "$o") [$o]"

echo "── [T35.2] 이어서 같은 결정 표 — 선택지 이유는 이미 전달됨 ──"
reg_full "$R" >/dev/null; rm -f "$(tf "$R" .help-warn)"
o="$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)"
[[ "$(sg_tags "$o")" == pass ]] && grep -q '^\[SCV 가이드\] 직전 턴: \[SCV 선택지\]' "$(tf "$R" .help-warn)" 2>/dev/null \
  && ok "함께 실린 것도 한 번으로 센다 — 막지 않고 다음 턴 경고" || fail "T35.2: $(sg_tags "$o") / $(cat "$(tf "$R" .help-warn)" 2>/dev/null)"

echo "── [T35.3] 등록에만 막힌 뒤 이어 쓴 답이 글로 묻는다 — 같은 턴에 선택지로 막는다 ──"
R="$(new_repo sg3)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
o1="$(stop_p "$R" "$WORK/profile-full.env" "$SG_DONE" false)"; reg_full "$R" >/dev/null
o2="$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)"
[[ "$(sg_tags "$o1")" == "block:prompt" && "$(sg_tags "$o2")" == "block:choice" ]] \
  && ok "첫 멈춤은 등록만, 계속 중인 두 번째 멈춤은 선택지로 막음" || fail "T35.3: $(sg_tags "$o1") / $(sg_tags "$o2")"

echo "── [T35.4] 원칙 검사도 같은 규칙 ──"
R="$(new_repo sg4)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
o1="$(stop_p "$R" "$WORK/profile-full.env" "$SG_DONE" false)"; reg_full "$R" >/dev/null
o2="$(stop_p "$R" "$WORK/profile-full.env" "$SG_QP" true)"
[[ "$(sg_tags "$o1")" == "block:prompt" && "$(sg_tags "$o2")" == "block:principle" ]] \
  && ok "등록에 막힌 뒤 이어 쓴 답의 문제 표 — 같은 턴에 원칙으로 막음" || fail "T35.4: $(sg_tags "$o1") / $(sg_tags "$o2")"

echo "── [T35.5] 상한 — 검사마다 한 번, 끝없는 반복 없음 ──"
R="$(new_repo sg5)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
s1="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_DONE" false)")"; reg_full "$R" >/dev/null
s2="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_QP" true)")"
s3="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)")"
rm -f "$(tf "$R" .help-warn)"
s4="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_ALL" true)")"
[[ "$s1|$s2|$s3|$s4" == "block:prompt|block:principle|block:choice|pass" && "$(sg_warns "$R")" == 3 ]] \
  && ok "세 번(등록 → 원칙 → 선택지) 막은 뒤 네 번째는 셋 다 걸려도 통과 · 경고 3줄" || fail "T35.5: $s1|$s2|$s3|$s4 · 경고 $(sg_warns "$R")"

echo "── [T35.6] 새 턴이면 다시 한 번씩 ──"
R="$WORK/sg1"; hook_p "$R" "$WORK/profile-full.env" "다음 일" >/dev/null   # T35.1 의 저장소 — 지난 턴에 등록 · 선택지를 전달했다
o1="$(stop_p "$R" "$WORK/profile-full.env" "$SG_DONE" false)"; reg_full "$R" >/dev/null
o2="$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)"
[[ "$(sg_tags "$o1")" == "block:prompt" && "$(sg_tags "$o2")" == "block:choice" ]] \
  && ok "지난 턴의 전달 기록은 새 턴에 이어지지 않는다" || fail "T35.6: $(sg_tags "$o1") / $(sg_tags "$o2")"

echo "── [T35.7] 사람 없는 실행 · 스위치 off 는 그대로 ──"
{ cat "$WORK/profile-full.env"; printf 'SCV_CHOICE_OFF_WHEN=SCV_TEST_ATTENDED=0\n'; } > "$WORK/profile-full-off.env"
R="$(new_repo sg7a)"; SCV_TEST_ATTENDED=0 hook_p "$R" "$WORK/profile-full-off.env" "로그인 고쳐" >/dev/null
o1="$(SCV_TEST_ATTENDED=0 stop_p "$R" "$WORK/profile-full-off.env" "$SG_DONE" false)"; reg_full "$R" >/dev/null; rm -f "$(tf "$R" .help-warn)"
o2="$(SCV_TEST_ATTENDED=0 stop_p "$R" "$WORK/profile-full-off.env" "$SG_QJ" true)"
[[ "$(sg_tags "$o1")" == "block:prompt" && "$(sg_tags "$o2")" == pass ]] && ! grep -q 'SCV 선택지' "$(tf "$R" .help-warn)" 2>/dev/null \
  && ok "사람 없는 실행 — 이어 쓴 글 질문도 막지 않고 선택지 경고도 없다" || fail "T35.7 (a): $(sg_tags "$o1") / $(sg_tags "$o2")"
R="$(new_repo sg7b)"; printf '{\n  "SCV_CHOICE_GATE": "off"\n}\n' > "$R/scv/scv_settings.json"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
o1="$(stop_p "$R" "$WORK/profile-full.env" "$SG_DONE" false)"; reg_full "$R" >/dev/null; rm -f "$(tf "$R" .help-warn)"
o2="$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)"
[[ "$(sg_tags "$o1")" == "block:prompt" && "$(sg_tags "$o2")" == pass ]] && ! grep -q 'SCV 선택지' "$(tf "$R" .help-warn)" 2>/dev/null \
  && ok "SCV_CHOICE_GATE=off — 그대로" || fail "T35.7 (b): $(sg_tags "$o1") / $(sg_tags "$o2")"
R="$(new_repo sg7c)"; printf '{\n  "SCV_REWRITE_PRINCIPLE": "off"\n}\n' > "$R/scv/scv_settings.json"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
o1="$(stop_p "$R" "$WORK/profile-full.env" "$SG_DONE" false)"; reg_full "$R" >/dev/null
o2="$(stop_p "$R" "$WORK/profile-full.env" "$SG_QP" true)"
[[ "$(sg_tags "$o1")" == "block:prompt" && "$(sg_tags "$o2")" == pass ]] && ok "SCV_REWRITE_PRINCIPLE=off — 그대로" || fail "T35.7 (c): $(sg_tags "$o1") / $(sg_tags "$o2")"

echo "── [T35.8] 턴 표를 못 읽으면 지금 동작 ──"
R="$(new_repo sg8)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
stop_p "$R" "$WORK/profile-full.env" "$SG_DONE" false >/dev/null; reg_full "$R" >/dev/null
rm -f "$(tf "$R" .help-turn)" "$(tf "$R" .help-warn)"
o="$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)"
[[ "$(sg_tags "$o")" == pass ]] && grep -q '^\[SCV 가이드\] 직전 턴: \[SCV 선택지\]' "$(tf "$R" .help-warn)" 2>/dev/null \
  && ok "턴 표 없음 — 계속 중이면 막지 않고 다음 턴 경고(이 기능 전과 같다)" || fail "T35.8 (a): $(sg_tags "$o")"
R="$(new_repo sg8b)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
stop_p "$R" "$WORK/profile-full.env" "$SG_DONE" false >/dev/null; reg_full "$R" >/dev/null
printf 'garbage-without-separator\n' > "$(tf "$R" .help-turn-gates)"
o="$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)"
[[ "$(sg_tags "$o")" == pass ]] && ok "전달 기록이 깨짐 — 막는 쪽으로 실패하지 않는다" || fail "T35.8 (b): $(sg_tags "$o")"

echo "── [T35.9] 자동 알림 턴 ──"
R="$(fresh_turn sg9)"
stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s' "$QUOTE" "끝났습니다.")" false >/dev/null   # 사람 턴이 끝난다
hook_p "$R" "$WORK/profile-full.env" $'<machine-event>\n<status>completed</status>\n</machine-event>' >/dev/null
o1="$(stop_p "$R" "$WORK/profile-full.env" "$C_J" false)"
o2="$(stop_p "$R" "$WORK/profile-full.env" "$C_J" true)"
[[ "$(sg_tags "$o1")" == "block:choice" && "$(sg_tags "$o2")" == pass ]] \
  && ok "등록 이유 없이 선택지로 한 번, 두 번째는 경고만" || fail "T35.9: $(sg_tags "$o1") / $(sg_tags "$o2")"

echo "── [T35.10] 턴 표가 그대로인 다음 턴(자동 알림 턴) — 지난 턴 기록을 이번 것으로 읽지 않는다 ──"
R="$(fresh_turn sg10)"
stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" false >/dev/null                                            # 사람 턴: 선택지를 전달
stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s' "$QUOTE" "끝났습니다.")" true >/dev/null       # 사람 턴이 끝난다
hook_p "$R" "$WORK/profile-full.env" $'<machine-event>\n<status>completed</status>\n</machine-event>' >/dev/null
o1="$(stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s' "$PTA" "끝났습니다.")" false)"
o2="$(stop_p "$R" "$WORK/profile-full.env" "$C_J" true)"
[[ "$(sg_tags "$o1")" == "block:principle" && "$(sg_tags "$o2")" == "block:choice" ]] \
  && ok "자동 알림 턴: 원칙으로 막힌 뒤 이어 쓴 글 질문도 같은 턴에 선택지로 막음(지난 턴의 '선택지 전달'을 잇지 않음)" || fail "T35.10 (a): $(sg_tags "$o1") / $(sg_tags "$o2")"
hook_p "$R" "$WORK/profile-full.env" $'<machine-event>\n<status>completed</status>\n</machine-event>' >/dev/null
o1="$(stop_p "$R" "$WORK/profile-full.env" "끝났습니다." false)"
o2="$(stop_p "$R" "$WORK/profile-full.env" "$C_J" true)"   # 다른 훅이 첫 멈춤을 이어 간 꼴 — 이번 턴 우리 기록은 없다
[[ "$(sg_tags "$o1")" == pass && "$(sg_tags "$o2")" == pass && ! -e "$(tf "$R" .help-turn-gates)" ]] \
  && ok "다른 훅이 이어 간 턴: 첫 멈춤이 지난 기록을 지우고, 이번 턴 기록이 없으니 이 기능 전과 같다(막지 않음)" || fail "T35.10 (b): $(sg_tags "$o1") / $(sg_tags "$o2")"

echo "── [T35.13] 전달 기록을 쓰지 못하면 — 같은 검사가 끝없이 막지 않는다 ──"
if [[ "$(id -u)" != 0 ]]; then
  R="$(new_repo sg13)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
  s1="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_DONE" false)")"; reg_full "$R" >/dev/null
  chmod a-w "$R/scv/journal" "$(tf "$R" "")"
  s2="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)")"
  s3="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)")"
  s4="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)")"
  chmod u+w "$R/scv/journal" "$(tf "$R" "")"
  [[ "$s1|$s2|$s3|$s4" == "block:prompt|pass|pass|pass" ]] \
    && ok "읽기 전용 저널 — 첫 멈춤만 막고, 계속 중인 멈춤은 기록을 못 남겨 막지 않음" || fail "T35.13: $s1|$s2|$s3|$s4"
else
  echo "  (root 로 도는 중 — 읽기 전용이 효과가 없어 T35.13 생략)"
fi

echo "── [T35.14] 전달 기록 자리가 심볼릭 링크 — 따라가지 않고, 끝없이 막지 않는다 ──"
R="$(new_repo sg14)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
s1="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_DONE" false)")"; reg_full "$R" >/dev/null
printf 'untouched\n' > "$WORK/sg14-target"; rm -f "$(tf "$R" .help-turn-gates)"; ln -s "$WORK/sg14-target" "$(tf "$R" .help-turn-gates)"
s2="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)")"
s3="$(sg_tags "$(stop_p "$R" "$WORK/profile-full.env" "$SG_QJ" true)")"
[[ "$s1|$s2|$s3" == "block:prompt|pass|pass" && "$(cat "$WORK/sg14-target")" == untouched ]] \
  && grep -q '^\[SCV 가이드\] 직전 턴: \[SCV 선택지\]' "$(tf "$R" .help-warn)" 2>/dev/null \
  && ok "링크 대상은 그대로, 계속 중 멈춤은 막지 않고 다음 턴 경고" || fail "T35.14: $s1|$s2|$s3 / $(cat "$WORK/sg14-target")"

echo "── [T35.15] 한 저장소 · 두 세션 — 다른 세션의 기록으로 한 검사가 두 번 막지 않는다 ──"
stop_s() {  # <저장소> <세션> <답> <계속 중 true|false> → 종료 훅 stdout (프로필 full, 세션 id 실음)
  local r="$1" tr="$WORK/tr-s-$RANDOM$RANDOM.jsonl"
  printf '{"type":"user","message":{"content":[{"type":"text","text":"q"}]}}\n' > "$tr"
  jq -cn --arg t "$3" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"text",text:$t}]}}' >> "$tr"
  (cd "$r" && jq -cn --arg p "$tr" --arg a "$3" --arg s "$2" --argjson act "$4" '{session_id:$s,transcript_path:$p,last_assistant_message:$a,stop_hook_active:$act}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile-full.env" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null)
}
# v0.65.0+ (계획 rewrite-stays-current 목표 5) — 이번 턴 상태가 세션마다 따로다. 두 세션이 각자 사람 턴을 열고 등록한다.
# 사람 메시지를 받지 않은 세션(하위 세션)은 검사하지 않는다 — 그 경우는 test-rewrite-stays-current 의 T9.
turn_s() {  # <저장소> <세션> — 그 세션의 사람 턴을 열고 등록한다
  (cd "$1" && jq -cn --arg s "$2" '{prompt:"로그인 고쳐",session_id:$s}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile-full.env" bash "$PROMPT_HOOK" >/dev/null 2>&1)
  (cd "$1" && SCV_HOST_PROFILE="$WORK/profile-full.env" bash "$MP" helped --session "$2" >/dev/null 2>&1)   # 0.80.0+ help 를 부른 턴
  (cd "$1" && printf '%s\n' "$SUB_OK" | SCV_HOST_PROFILE="$WORK/profile-full.env" bash "$MP" register --model vendor-model-a --session "$2" >/dev/null 2>&1)
}
R="$(new_repo sg15)"; turn_s "$R" sess-a; turn_s "$R" sess-b
a1="$(sg_tags "$(stop_s "$R" sess-a "$SG_QJ" false)")"; b1="$(sg_tags "$(stop_s "$R" sess-b "$SG_QP" false)")"
a2="$(sg_tags "$(stop_s "$R" sess-a "$SG_QJ" true)")"
[[ "$a1|$b1|$a2" == "block:choice|block:principle|pass" ]] && ok "A 선택지 → B 원칙 → A 계속 중 같은 질문: 막지 않음(A 는 자기 기록으로 — 세션마다 따로)" || fail "T35.15 (a): $a1|$b1|$a2"
R="$(new_repo sg15b)"; turn_s "$R" sess-a; turn_s "$R" sess-b
a1="$(sg_tags "$(stop_s "$R" sess-a "$SG_QJ" false)")"; b1="$(sg_tags "$(stop_s "$R" sess-b "$(printf '%s\n\n%s' "$QUOTE" "끝났습니다.")" false)")"   # 인용을 갖춰 아무 검사도 걸리지 않는 첫 멈춤
a2="$(sg_tags "$(stop_s "$R" sess-a "$SG_QJ" true)")"
[[ "$a1|$b1|$a2" == "block:choice|pass|pass" ]] && ok "B 의 첫 멈춤은 A 의 기록을 지우지 않는다 — A 의 선택지는 이미 전달" || fail "T35.15 (b): $a1|$b1|$a2"

echo "── [T35.16] 코덱스 모양 원본 — 앞선 인용을 못 보니 계속 중 등록 검사는 막지 않는다 ──"
stop_tra() {  # <저장소> <원본> <마지막 답> <계속 중 true|false> → 종료 훅 stdout (프로필 full)
  (cd "$1" && jq -cn --arg p "$2" --arg a "$3" --argjson act "$4" '{session_id:"s1",transcript_path:$p,last_assistant_message:$a,stop_hook_active:$act}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile-full.env" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null)
}
R="$(fresh_turn sg16)"; TR="$WORK/sg16.jsonl"; A1="$(printf '%s\n\n%s\n\n%s' "$QUOTE" "결론." "$PTA")"
{ printf '%s\n' '{"type":"session_meta","payload":{"originator":"fixture"}}'; cx_line user "로그인 고쳐"; cx_line assistant "$A1"; } > "$TR"
o1="$(stop_tra "$R" "$TR" "$A1" false)"
A2=$'표를 고쳤습니다.\n\n| 단위 | 해결책 | 추천 |\n|---|---|---|\n| a | ①x | ① 이유 |'
cx_line assistant "$A2" >> "$TR"
o2="$(stop_tra "$R" "$TR" "$A2" true)"
[[ "$(sg_tags "$o1")" == "block:principle" && "$(sg_tags "$o2")" == pass ]] \
  && ok "원칙에 막힌 뒤 인용 없이 표만 고친 답 — 등록 이유로 새로 막지 않음" || fail "T35.16: $(sg_tags "$o1") / $(sg_tags "$o2") [$o2]"

echo "── [T35.17] 첫 멈춤에서 새 기록 쓰기만 실패 — 지난 기록을 먼저 지워 같은 검사가 한 번 더 막지 않는다 ──"
# 재검토(2026-10-02)가 재현한 꼴: 자동 알림 턴(턴 표 그대로)의 첫 멈춤이 막으면서 기록을 못 쓰면 지난 턴 기록이 남아, 다음 멈춤이
# 같은 검사를 또 막았다. 첫 멈춤은 기록을 쓰기 전에 같은 세션의 지난 기록부터 지운다. 쓰기 실패는 가짜 mktemp 로 만든다.
mkdir -p "$WORK/nomktemp"; printf '#!/bin/sh\nexit 1\n' > "$WORK/nomktemp/mktemp"; chmod +x "$WORK/nomktemp/mktemp"
R="$(fresh_turn sg17)"
stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s\n\n%s' "$QUOTE" "결론." "$PTA")" false >/dev/null   # 사람 턴: 원칙을 전달
stop_p "$R" "$WORK/profile-full.env" "$(printf '%s\n\n%s' "$QUOTE" "끝났습니다.")" true >/dev/null       # 사람 턴이 끝난다
hook_p "$R" "$WORK/profile-full.env" $'<machine-event>\n<status>completed</status>\n</machine-event>' >/dev/null
TR="$WORK/sg17.jsonl"; { jl_user "q"; jl_asst "$C_J"; } > "$TR"
o1="$(cd "$R" && jq -cn --arg p "$TR" --arg a "$C_J" '{session_id:"s1",transcript_path:$p,last_assistant_message:$a,stop_hook_active:false}' \
       | PATH="$WORK/nomktemp:$PATH" CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile-full.env" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null)"
gone=0; [[ ! -e "$(tf "$R" .help-turn-gates)" ]] && gone=1
o2="$(stop_p "$R" "$WORK/profile-full.env" "$C_J" true)"
[[ "$(sg_tags "$o1")" == "block:choice" && "$gone" == 1 && "$(sg_tags "$o2")" == pass ]] \
  && ok "첫 멈춤: 지난 기록 지우고 막음(새 기록은 못 씀) → 계속 중 같은 질문은 막지 않음" || fail "T35.17: $(sg_tags "$o1") gone=$gone / $(sg_tags "$o2")"

echo "── [T35.18] 세션 id 를 주지 않는 호스트 — 계속 중이면 이 기능 전과 같다 ──"
# 재검토(2026-10-02): 세션 id 가 없으면 한 저장소의 두 세션을 가를 수 없어, 한 검사가 한 턴에 세 번까지 막혔다.
stop_ns() {  # <저장소> <답> <계속 중 true|false> → 종료 훅 stdout (프로필 full, 세션 id 없음)
  local r="$1" tr="$WORK/tr-ns-$RANDOM$RANDOM.jsonl"
  printf '{"type":"user","message":{"content":[{"type":"text","text":"q"}]}}\n' > "$tr"
  jq -cn --arg t "$2" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"text",text:$t}]}}' >> "$tr"
  (cd "$r" && jq -cn --arg p "$tr" --arg a "$2" --argjson act "$3" '{transcript_path:$p,last_assistant_message:$a,stop_hook_active:$act}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/profile-full.env" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null)
}
R="$(new_repo sg18)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null
o1="$(stop_ns "$R" "$SG_DONE" false)"; reg_full "$R" >/dev/null
o2="$(stop_ns "$R" "$SG_QJ" true)"
[[ "$(sg_tags "$o1")" == "block:prompt" && "$(sg_tags "$o2")" == pass ]] \
  && ok "세션 id 없음 — 첫 멈춤은 막고, 계속 중 글 질문은 막지 않음(이 기능 전과 같다)" || fail "T35.18: $(sg_tags "$o1") / $(sg_tags "$o2")"

echo "── [T35.11] 맥 기본 bash 3.2 와 지금 bash 에서 같은 결과 — 출력 · 전달 기록 · 다음 턴 경고를 바이트로 ──"
# 계획 TESTS T11: T1~T9 의 흐름을 두 bash 로 돌려, 멈춤마다 훅 출력과 남긴 파일(전달 기록 · 다음 턴 경고)을 바이트로 비교한다.
# 저장소마다 다른 턴 표(8자리 16진)만 TOK 로 바꾼다 — 그 밖의 바이트는 그대로 같아야 한다(재검토 2026-10-02: 꼬리표 요약만
# 비교하던 것을 넓힘).
SG_PROF="$WORK/profile-full.env"
stop_g() {  # <bash 실행 파일> <저장소> <답> <계속 중 true|false> → 종료 훅 stdout (프로필 SG_PROF, 세션 s1)
  local b="$1" r="$2" tr="$WORK/tr-g-$RANDOM$RANDOM.jsonl" pth="$PATH"
  [[ "$b" == /bin/bash ]] && pth="$SYSB:$PATH"
  printf '{"type":"user","message":{"content":[{"type":"text","text":"q"}]}}\n' > "$tr"
  jq -cn --arg t "$3" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"text",text:$t}]}}' >> "$tr"
  (cd "$r" && jq -cn --arg p "$tr" --arg a "$3" --argjson act "$4" '{session_id:"s1",transcript_path:$p,last_assistant_message:$a,stop_hook_active:$act}' \
     | PATH="$pth" CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$SG_PROF" GIT_AUTHOR_NAME="Hook User" "$b" "$STOP_HOOK" 2>/dev/null)
}
sg_dump() {  # <저장소> <훅 출력> → 정규화한 출력 · 전달 기록 · 다음 턴 경고 (턴 표 → TOK, 칸 구분 → |)
  { printf 'OUT %s\n' "$2"; printf 'REC %s\n' "$(cat "$(tf "$1" .help-turn-gates)" 2>/dev/null)"
    printf 'WARN %s\n' "$(cat "$(tf "$1" .help-warn)" 2>/dev/null)"; } \
    | tr '\037' '|' | sed -E 's/턴\([0-9a-f]{8}\)/턴(TOK)/g; s/^(REC [^|]*)\|[0-9a-f]{8}\|/\1|TOK|/'
}
sg_step() {  # <bash> <저장소> <답> <계속 중> — 꼬리표는 SG_T 에, 정규화한 덤프는 SG_D 에 덧붙인다
  local o; o="$(stop_g "$1" "$2" "$3" "$4")"
  SG_T="$SG_T|$(sg_tags "$o")"; SG_D="$SG_D$(sg_dump "$2" "$o")"$'\n'
}
sg_run() {  # <bash 실행 파일> <이름> → 첫 줄: 꼬리표 요약, 나머지: 정규화한 덤프
  local b="$1" R; SG_T=""; SG_D=""; SG_PROF="$WORK/profile-full.env"
  R="$(new_repo "$2-a")"; hook_p "$R" "$SG_PROF" "로그인 고쳐" >/dev/null                       # T1 · T2
  sg_step "$b" "$R" "$C_J" false; reg_full "$R" >/dev/null; sg_step "$b" "$R" "$SG_QJ" true
  hook_p "$R" "$SG_PROF" "다음 일" >/dev/null                                                    # T6 — 새 턴
  sg_step "$b" "$R" "$SG_DONE" false; reg_full "$R" >/dev/null; sg_step "$b" "$R" "$SG_QJ" true
  R="$(new_repo "$2-b")"; hook_p "$R" "$SG_PROF" "로그인 고쳐" >/dev/null                       # T3 · T4 · T5
  sg_step "$b" "$R" "$SG_DONE" false; reg_full "$R" >/dev/null
  sg_step "$b" "$R" "$SG_QP" true; sg_step "$b" "$R" "$SG_QJ" true; sg_step "$b" "$R" "$SG_ALL" true
  R="$(new_repo "$2-c")"; hook_p "$R" "$SG_PROF" "로그인 고쳐" >/dev/null; reg_full "$R" >/dev/null   # T9 — 자동 알림 턴
  sg_step "$b" "$R" "$(printf '%s\n\n%s' "$QUOTE" "끝났습니다.")" false
  hook_p "$R" "$SG_PROF" $'<machine-event>\n<status>completed</status>\n</machine-event>' >/dev/null
  sg_step "$b" "$R" "$C_J" false; sg_step "$b" "$R" "$C_J" true
  R="$(new_repo "$2-d")"; hook_p "$R" "$SG_PROF" "로그인 고쳐" >/dev/null                       # T8 — 턴 표 없음
  sg_step "$b" "$R" "$SG_DONE" false; reg_full "$R" >/dev/null; rm -f "$(tf "$R" .help-turn)"; sg_step "$b" "$R" "$SG_QJ" true
  SG_PROF="$WORK/profile-full-off.env"; export SCV_TEST_ATTENDED=0                               # T7 — 사람 없는 실행
  R="$(new_repo "$2-e")"; hook_p "$R" "$SG_PROF" "로그인 고쳐" >/dev/null
  sg_step "$b" "$R" "$SG_DONE" false; reg_full "$R" >/dev/null; sg_step "$b" "$R" "$SG_QJ" true
  unset SCV_TEST_ATTENDED; SG_PROF="$WORK/profile-full.env"
  printf '%s\n%s' "${SG_T#|}" "$SG_D"
}
if [[ -x /bin/bash ]]; then
  SYSB="$WORK/sysbash"; mkdir -p "$SYSB"; ln -sf /bin/bash "$SYSB/bash"; v="$(/bin/bash -c 'echo "$BASH_VERSION"')"
  g1="$(sg_run bash sgb1)"; g2="$(sg_run /bin/bash sgb2)"
  want="block:prompt,choice|pass|block:prompt|block:choice|block:prompt|block:principle|block:choice|pass|pass|block:choice|pass|block:prompt|pass|block:prompt|pass"
  [[ "$g1" == "$g2" && "$(head -1 <<<"$g1")" == "$want" ]] \
    && ok "시스템 bash $v 와 지금 bash — 멈춤 15번의 출력 · 전달 기록 · 다음 턴 경고가 바이트로 같다" \
    || fail "T35.11: [$(head -1 <<<"$g1")] vs [$(head -1 <<<"$g2")] / $(diff <(printf '%s\n' "$g1") <(printf '%s\n' "$g2") | head -4)"
else
  echo "  (시스템 bash 없음 — T35.11 생략)"
fi

echo "── [T35.12] 큰 끝 메시지 속도 — 세 검사를 모두 보는 멈춤 ──"
# 끝 메시지는 앞 64KB 만 본다(0.64.0 부터의 동작) — 질문이 그 안에 들도록 63KB 로 만든다. 맥 실측(2026-10-02, 시스템 bash 3.2):
# 고치기 전 2.40초(등록 이유 하나) → 고친 뒤 2.69초(두 이유). 상한은 병적인 느려짐(예전 같은 꼴 158초)을 잡는 자리다 —
# 10초였으나 시험을 동시에 돌리는 러너(codex 래퍼 CI, 4개 동시)에서 11초가 나와 30초로(2026-10-29, 158초는 여전히 잡힌다).
if [[ -x /bin/bash ]]; then
  R="$(new_repo sg12)"; hook_p "$R" "$WORK/profile-full.env" "로그인 고쳐" >/dev/null   # 등록 없음 → 등록 검사가 걸린 채로 셋 다 판정
  BIGA="$( { for i in $(seq 1 1500); do printf '진행 메모 %s — 이번 단계에서 확인한 것을 적는다.\n' "$i"; done; } | head -c 63000; printf '\n\n릴리스할까요?')"
  t0=$SECONDS; o="$(stop_g /bin/bash "$R" "$BIGA" false)"; t1=$SECONDS
  [[ "$(sg_tags "$o")" == "block:prompt,choice" ]] && (( t1 - t0 <= 30 )) \
    && ok "끝 메시지 $(printf '%s' "$BIGA" | wc -c | tr -d ' ')바이트 — 시스템 bash $v 로 $((t1 - t0))s, 두 이유 함께" || fail "T35.12 $((t1 - t0))s: $(sg_tags "$o")"
else
  echo "  (시스템 bash 없음 — T35.12 생략)"
fi

echo "── [NI.T1 · NI.T2] 다음 할 일은 결정이 아니다 — 규약 규칙 8 + 매 턴 줄 (20261021-wookiya1364-no-idle-next-question) ──"
# 실사용(2026-10-21): 긴 세션 하나의 창 225개 중 115개가 배경 작업 끝 알림 바로 뒤의 '다음으로 무엇을?' 창이었다.
r8="$(awk '/^8\. What to do next is not/{p=1} p&&/^Information is not a decision/{exit} p' "$RULE")"
[[ -n "$r8" ]] && grep -q "take that step without asking" <<<"$r8" && grep -q "automatic-notification turns alike" <<<"$r8" \
  && grep -q "without a question" <<<"$r8" && grep -q "hard to reverse or reaches outside" <<<"$r8" \
  && grep -q "taste or scope" <<<"$r8" && grep -q "cannot" <<<"$r8" \
  && ok "규약 규칙 8 — 막힌 것 없으면 계속 · 끝났으면 서술 · 진짜 결정 세 종류 · 자동 알림 턴 포함" || fail "NI.T1: [$r8]"
l="$(bash -c 'source "$1"; scv_choice_line PickTool' _ "$LIB")"
grep -q "Next step is no decision (bar first-run check): unblocked, go on; work done, state it unasked." <<<"$l" \
  && [[ -z "$(bash -c 'source "$1"; scv_choice_line ""' _ "$LIB")" ]] \
  && ok "매 턴 줄에 '다음 할 일은 결정 아님' 구절, 도구 없으면 줄 없음" || fail "NI.T2: [$l]"

echo; echo "test-choice-questions: pass=$PASS fail=$FAIL"
(( FAIL == 0 ))
