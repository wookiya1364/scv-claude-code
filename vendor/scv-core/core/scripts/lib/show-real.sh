#!/usr/bin/env bash
# lib/show-real.sh — 실체 보여 주기(contracts/show-real.md)의 순수부 (v0.66.0+). 효과는 둘:
# scripts/show-real.sh(매 턴 안내 — 설정 · 호스트 설정 · 훅 입력 읽기, 출력)와 scripts/show-real-report.sh(실사용 보고 — 세션
# 기록 읽기, 출력).
#
# 매 턴 안내 — flow(scv_show_real_switch, scv_show_real_channel, scv_show_real_rule):
#   scv_show_real_switch  <설정 값 원문>                                → on | off
#   scv_show_real_channel <선택 창 이름> <사람 없는 실행 1|0> <human|auto> → choice | text | none
#   scv_show_real_rule    <on|off> <choice|text|none>                   → 매 턴 블록에 덧붙일 세 줄(off 면 빈 값)
#
# 실사용 보고 — 기록 읽기(효과) → scv_show_real_entries → scv_show_real_split → scv_show_real_classify
#               → scv_show_real_count → scv_show_real_render → 출력(효과)
# 읽는 기록: 줄마다 JSON 하나인 세션 기록(JSONL) — 사용자 · 모델 메시지의 내용 배열에 글 · 도구 호출 · 도구 결과 블록이 든 모양.
# 다른 모양의 파일은 항목이 나오지 않아 '읽지 못한 파일'로 센다(보고에 그 수가 나온다).
# 세는 기준 — 기록만으로 가를 수 있는 모양을 센다(숫자는 방향을 보는 용도다):
#   · 사람 턴: 사람이 쓴 메시지 하나부터 다음 사람 메시지 전까지. 일하는 도중에 입력해 첨부로 남은 메시지(프롬프트가 든 첨부 줄)도
#     사람 메시지다. 메타 · 기록에만 보이는 줄(압축 요약) · 도구 결과 · 하위 에이전트 줄은 빼고, 호스트 설정의 자동 입력 모양
#     (scv_mp_prompt_kind — 배경 작업 알림 등)은 새 턴을 열지 않고 그 턴의 일로 남는다. 모델이 아무것도 하지 않은 턴(명령 출력 줄 ·
#     중단 표시 등 — 글 · 도구 호출이 하나도 없는 턴)은 세지 않는다.
#   · 편집(E): 입력에 파일 경로와 쓸 내용(내용 · 바꿀 글 · 편집 목록 · 새 셀)이 있는 도구 호출. 실행(R): 입력에 명령이 있는 호출.
#     확인 창(C): 호스트 설정의 선택 창 이름과 같은 호출 — 그 질문 가운데 계속할지와 고칠 점을 함께 묻는 것
#     (scv_show_real_is_confirm)이 있으면 K. 그 밖의 도구 호출(읽기 등)은 O. 글(T): 모델의 글 블록. 편집 · 실행은 도구 이름이 아니라
#     입력 모양으로 가른다(호스트 중립).
#   · 결과물이 바뀐 턴: 편집이 하나라도 있고, 턴의 마지막 글에 '결과물 변화 없음'(안내가 결과물이 안 바뀌는 일에 쓰게 하는 표시 —
#     scv_show_real_is_nochange)이 없는 턴.
#   · 실제 결과를 보여 준 턴: 바뀐 턴 중 '첫 편집 → 실행 → 계속 · 고칠 점을 묻는 확인(K, 또는 턴을 끝내는 그런 글 질문)' 순서가
#     있는 턴. 모양만 보면 일하다 묻는 다른 결정 창도 잡혀 켜기 전 기준선이 높았다(실제 기록 53%, 2026-10-07) — 사용자 결정으로
#     질문 내용까지 본다.
#   · 완료 보고: 편집이 있는 턴이 모델의 글로 끝나고 그 글이 질문이 아님(도구 호출에서 끊긴 턴은 완료가 아니다).
#   · 완료 뒤 수정 요구: 같은 세션에서 완료 보고 뒤 처음으로 모델이 답한 사람 메시지(앞 1000자)가 고쳐 달라는 말
#     (scv_show_real_is_correction)인 것. 모델이 아무것도 하지 않은 턴은 그 판단도 끊지 않는다.
#   · 확인 질문: 확인 창 수 + 턴을 끝낸 글 질문 수(lib/choices.sh 의 판정).
#   · 날짜: 기록 시각(끝이 Z 이거나 시간대가 없으면 UTC, ±HH:MM 이 붙으면 그만큼 옮긴 UTC)을 지역 오프셋(분)으로 옮긴 날.
#     턴은 사람 메시지의 날로 기간에 든다.
#
# 꺾쇠 글자는 순수 함수 안에 쓰지 않는다 — 순수성 검사가 리다이렉션으로 본다(lib/choices.sh 와 같은 이유).
# 긴 글에 글자 단위 치환(${x//…})을 쓰지 않는다 — bash 3.2 에서 긴 한글에 제곱으로 느려진다(1.6만 자 9초, 독립 검토 2026-10-07).
# jq 에서도 줄마다 정규식을 돌리지 않고 글자 그대로 나누고 잇는다(1,500턴 기록에서 52초 → 몇 초).
# 글 자르기는 jq 에서 글자 단위로 끝낸다 — bash 의 자르기는 로캘(C 면 바이트)에 따라 결과가 달라진다. 턴 · 줄은 모아 두지 않고
# 바로 내보낸다(모아 붙이면 긴 세션에서 제곱으로 느려진다).
# 보고의 나누기 · 분류는 lib/model-prompting.sh(scv_mp_prompt_kind)와 lib/choices.sh(scv_asks_in_text · scv_answer_body)를
# 함께 불러 둔 셸에서 부른다.

# ---------------------------------------------------------------- 매 턴 안내

# @pure
# <설정 값 원문> → on | off. off 만 끈다(대소문자 · 공백 · 따옴표 무관) — 없거나 다른 값은 on(다른 SCV 스위치와 같은 규칙).
scv_show_real_switch() {
  local v="${1:-}"
  v="${v//[[:space:]]/}"; v="${v//\"/}"; v="${v//\'/}"
  case "$v" in
    [Oo][Ff][Ff]) printf 'off' ;;
    *)            printf 'on'  ;;
  esac
}

# @pure
# <이번 실행에 쓸 수 있는 선택 창 이름 — 빈 값 가능> <사람 없는 실행 1|0> <이번 입력 human|auto> → choice | text | none.
# 사람이 없는 실행이거나 자동 알림 턴이면 none(묻지 않는다 — 계약의 예외). 아니면 이름이 있으면 choice, 없으면 text.
# 이름과 사람 없는 실행은 고르게 할 때 규칙과 같은 판단의 값이다(choice-gate.sh tool · unattended).
scv_show_real_channel() {
  local tool="${1:-}" un="${2:-0}" kind="${3:-human}"
  if [[ "$un" == "1" || "$kind" == "auto" ]]; then printf 'none'; return 0; fi
  if [[ -n "${tool//[[:space:]]/}" ]]; then printf 'choice'; else printf 'text'; fi
}

# @pure
# <on|off> <choice|text|none> → 매 턴 블록에 덧붙일 세 줄. off 면 빈 값(이 기능 전과 같은 출력). 문구는 2026-10-06 두 번째 긴 과제
# 실측에서 잰 지시(사용자 승인)를 바탕으로 한다 — 본문은 contracts/show-real.md 한 곳.
scv_show_real_rule() {
  local sw="${1:-on}" ch="${2:-text}" second
  [[ "$sw" == "on" ]] || return 0
  case "$ch" in
    choice) second="그 결과(명령 출력 · 화면 · 함수 호출 결과)를 그대로 보여 주고, '이대로 계속할까요, 고칠 점이 있나요?'를 선택 창으로 짧게 물어라(보기는 2개 이상 — 계속 · 고칠 점). 설명은 한두 줄로." ;;
    none)   second="그 결과(명령 출력 · 화면 · 함수 호출 결과)를 보고에 그대로 남겨라 — 사람이 없는 실행이나 자동 알림 턴이라 묻지 않는다. 설명은 한두 줄로." ;;
    *)      second="그 결과(명령 출력 · 화면 · 함수 호출 결과)를 그대로 보여 주고, '이대로 계속할까요, 고칠 점이 있나요?'를 글 질문 한 번으로 짧게 물어라. 설명은 한두 줄로." ;;
  esac
  printf '%s\n' \
    "[SCV 실체 보여 주기] 결과물이 바뀌는 일이면, 설명이나 글로 된 견본 대신 처음 돌아가는 순간에 가장 작은 것을 실제로 실행해" \
    "$second" \
    "결과물이 바뀌지 않는 일은 보여 주지도 묻지도 말고 '결과물 변화 없음'이라고 적어라. 본문: contracts/show-real.md"
}

# ---------------------------------------------------------------- 실사용 보고

# @deterministic
# 표준입력: 세션 기록 JSONL(한 세션). <선택 창 이름> → 기록 항목 줄들(기록 순서 그대로):
#   "U<탭><시각><탭><앞 1000자><탭><판별용 글>"(사용자 메시지 · 프롬프트가 든 첨부 — 줄바꿈 · 탭은 공백. 판별용 글은 8000자가 넘으면
#                                            앞 6000자 + 끝 2000자)
#   "E"(편집) · "R"(실행) · "O"(그 밖의 도구 호출)
#   "C<탭><질문들>"(확인 창 — 입력 안의 question 값들, 없으면 첫 글. 질문 사이는 \x1f, 질문마다 앞 1000자)
#   "T<탭><마지막 두 줄><탭><글>"(모델의 글 — 마지막 두 줄은 빈 줄을 뺀 끝 두 줄(공백으로 이음, 1000자), 글은 끝 60줄 · 4000자 —
#                                질문 판정(scv_asks_in_text)은 끝 두 문단 · 끝 40줄만 본다. 줄바꿈 \x1e · 탭은 공백. 자른 자리가
#                                코드 블록 안이면 앞에 여는 울타리를 붙인다 — 종료 훅과 같은 처리)
# 깨진 줄 · 객체가 아닌 줄 · 메타 · 기록에만 보이는 줄(압축 요약 등) · 도구 결과만 든 사용자 줄 · 하위 에이전트(isSidechain) 줄은
# 건너뛴다.
scv_show_real_entries() {
  jq -rR --arg tool "${1:-}" '
    def sp: split("\t") | join(" ") | split("\r") | join(" ") | split("\n") | join(" ");
    def enc: split("\t") | join(" ") | split("\r") | join("") | split("\n") | join("\u001e");
    def obj: type == "object";
    def head_tail: if (.[8000:] | length) != 0 then .[0:6000] + " " + .[-2000:] else . end;
    def fences: [split("\n")[] | select(index("```") != null) | select(test("^\\s*```"))] | length;
    def tailcut: . as $t
                 | (split("\n") | .[-60:] | join("\n")) as $l
                 | ($l | if (.[4000:] | length) != 0 then .[-4000:] else . end) as $k
                 | ($t | .[0:(length - ($k | length))] | fences % 2) as $open
                 | if $open == 1 then "```\n" + $k else $k end;
    def lastq: [split("\n")[] | select(length != 0)] | .[-4:] | map(select(test("\\S"))) | .[-2:] | join(" ") | .[-1000:] | sp;
    (fromjson? // empty) | select(obj) | select((.isSidechain // false) != true)
    | if .type == "user" and ((.isMeta // false) != true) and ((.isVisibleInTranscriptOnly // false) != true)
         and ((.isCompactSummary // false) != true) then
        (.message.content // null) as $c
        | (if ($c | type) == "string" then $c
           elif ($c | type) == "array"
                and ([$c[] | select(obj and .type == "tool_result")] | length) == 0
                and ([$c[] | select(obj and .type == "text")] | length) != 0
           then [$c[] | select(obj and .type == "text") | (.text // "")] | join("\n")
           else empty end) as $m
        | "U\t\(.timestamp // "" | sp)\t\($m | .[0:1000] | sp)\t\($m | head_tail | sp)"
      elif .type == "attachment" and ((.attachment.prompt // null) | type) == "string" then
        .attachment.prompt as $m
        | "U\t\(.timestamp // .attachment.timestamp // "" | sp)\t\($m | .[0:1000] | sp)\t\($m | head_tail | sp)"
      elif .type == "assistant" then
        (.message.content // null) | if type == "array" then .[] else empty end | select(obj)
        | if .type == "tool_use" then
            (.input // null) as $in
            | if $tool != "" and (.name // "") == $tool then
                ([$in | .. | objects | .question? | strings]
                 | if length == 0 then [([$in | .. | strings] | first // "")] else . end
                 | map(.[0:1000] | sp) | join("\u001f")) as $q
                | "C\t\($q)"
              elif ($in | obj)
                   and (($in.file_path // $in.notebook_path // $in.path // null) | type) == "string"
                   and (($in.content // $in.new_string // $in.edits // $in.new_source // null) != null) then "E"
              elif ($in | obj) and (($in.command // null) | type) == "string" then "R"
              else "O" end
          elif .type == "text" then "T\t\((.text // "") | lastq)\t\((.text // "") | tailcut | enc)"
          else empty end
      else empty end' 2>/dev/null
}

# @pure
# <\x1e 로 줄을 나눈 글> → 줄바꿈으로 나눈 글. 글자 단위 치환 대신 한 번에 나눠 잇는다(bash 3.2 의 긴 한글 치환이 제곱으로 느리다).
scv_show_real_lines() {
  local IFS=$'\x1e' parts n
  [[ -n "${1:-}" ]] || return 0
  read -r -d '' -a parts <<< "$1"
  n=${#parts[@]}
  (( n )) || return 0
  parts[n-1]="${parts[n-1]%$'\n'}"
  printf '%s\n' "${parts[@]}"
}

# @pure
# <확인 창의 질문 또는 글 질문> → 1(계속할지와 고칠 점을 함께 묻는 확인) | 0. 계속 쪽 단서와 고칠 쪽 단서(한 · 영 · 일)가 둘 다
# 있어야 한다 — 실체 보여 주기 안내의 질문('이대로 계속할까요, 고칠 점이 있나요?')을 다른 결정 창과 가른다. 보기 설명은 보지 않고
# '진행' 같은 흔한 말은 단서로 쓰지 않는다(실제 기록에서 다른 결정 창이 그것으로 잡혔다, 2026-10-07).
scv_show_real_is_confirm() {
  local m="${1:-}" go=0 fx=0 cue nc=0
  local re_go='(^|[^a-z])(continue|proceed|keep going|go on)([^a-z]|$)' re_fix='(^|[^a-z])(fix|change|adjust|tweak)'
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  for cue in "계속" "続け"; do [[ "$m" == *"$cue"* ]] && { go=1; break; }; done
  (( go )) || { [[ "$m" =~ $re_go ]] && go=1; }
  for cue in "고칠" "고쳐" "수정할" "바꿀" "直" "修正"; do [[ "$m" == *"$cue"* ]] && { fx=1; break; }; done
  (( fx )) || { [[ "$m" =~ $re_fix ]] && fx=1; }
  (( nc )) || shopt -u nocasematch
  if (( go && fx )); then printf '1'; else printf '0'; fi
}

# @pure
# <세션 이름> <기록 항목 줄들> <자동 입력 태그> <앞말> <뒷말> → 사람 턴 줄들(기록 순서 그대로):
#   "<세션><탭><시각><탭><사건 글자들 E·R·O·C·K·T><탭><사람 메시지 앞 1000자><탭><마지막 글의 끝 두 줄><탭><마지막 글(\x1e 줄바꿈)>"
# 첫 사람 메시지 앞의 항목은 버리고, 자동 입력(scv_mp_prompt_kind 가 auto)은 턴을 열지 않는다. 확인 창은 질문 가운데 하나라도
# 계속할지와 고칠 점을 함께 묻는 것이면 K, 아니면 C 로 적는다. 턴을 모으지 않고 끝날 때마다 내보낸다.
scv_show_real_split() {
  local sess="${1:-}" entries="${2:-}" tags="${3:-}" pfx="${4:-}" sfx="${5:-}"
  local tab=$'\t' us=$'\x1f' line k rest ts head txt q cf cur=0 c_ts="" c_seq="" c_msg="" c_lq="" c_last="" IFS
  local -a qs
  while IFS= read -r line || [[ -n "$line" ]]; do
    k="${line%%"$tab"*}"
    case "$k" in
      U)
        rest="${line#U"$tab"}"; ts="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
        head="${rest%%"$tab"*}"; txt="${rest#*"$tab"}"
        [[ "$(scv_mp_prompt_kind "$txt" "$tags" "$pfx" "$sfx")" == "human" ]] || continue
        (( cur )) && printf '%s\n' "$sess$tab$c_ts$tab$c_seq$tab$c_msg$tab$c_lq$tab$c_last"
        cur=1; c_ts="$ts"; c_seq=""; c_msg="$head"; c_lq=""; c_last="" ;;
      E|R|O)
        (( cur )) && c_seq+="$k" ;;
      C)
        if (( cur )); then
          cf=0; qs=()
          IFS="$us" read -r -a qs <<< "${line#C"$tab"}"
          for q in ${qs[@]+"${qs[@]}"}; do
            [[ "$(scv_show_real_is_confirm "$q")" == "1" ]] && { cf=1; break; }
          done
          if (( cf )); then c_seq+="K"; else c_seq+="C"; fi
        fi ;;
      T)
        if (( cur )); then
          c_seq+="T"; rest="${line#T"$tab"}"; c_lq="${rest%%"$tab"*}"; c_last="${rest#*"$tab"}"
        fi ;;
    esac
  done <<< "$entries"
  (( cur )) && printf '%s\n' "$sess$tab$c_ts$tab$c_seq$tab$c_msg$tab$c_lq$tab$c_last"
  return 0
}

# @pure
# <모델의 글> → 1(결과물 변화 없음 표시가 있다) | 0. 안내가 결과물이 안 바뀌는 일에 쓰게 하는 말과 그 영 · 일 대응말을 본다.
scv_show_real_is_nochange() {
  local m="${1:-}" cue nc=0 hit=0
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  for cue in "결과물 변화 없음" "결과물 변화는 없" "no change to the result" "no result change" "result unchanged" \
             "成果物の変化なし" "成果物に変化なし" "成果物は変わらない"; do
    [[ "$m" == *"$cue"* ]] && { hit=1; break; }
  done
  (( nc )) || shopt -u nocasematch
  printf '%s' "$hit"
}

# @pure
# <사람 메시지> → 1(고쳐 달라는 말) | 0. 단서 낱말(한 · 영 · 일)을 본다 — 기록에서 '완료 뒤 수정 요구'를 세는 용도라 거칠다.
# '아니면'(또는)은 단서가 아니다.
scv_show_real_is_correction() {
  local m="${1:-}" cue nc=0 hit=0
  local re_word='(^|[^a-z])(wrong|fix|instead|broken|revert|undo|incorrect|redo|bug|error|failed|failing)([^a-z]|$)'
  local re_phrase='(not what|doesn.t work|does not work|didn.t work|not right|should be|should have)'
  m="${m//아니면/}"
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  for cue in "아니" "말고" "고쳐" "고치" "수정해" "수정 해" "바꿔" "바꾸" "틀렸" "틀린" "잘못" "안 돼" "안돼" "안 되" "안되" \
             "빠졌" "빠진" "없잖" "이상해" "이상하" "되돌려" "원래대로" "다시 해" "다시 만들" "버그" "오류" "에러" "실패" \
             "깨졌" "깨진" "違う" "ちがう" "直して" "修正" "やり直" "おかしい" "じゃなくて" "ではなく" "動かない" "戻して" \
             "バグ" "エラー"; do
    [[ "$m" == *"$cue"* ]] && { hit=1; break; }
  done
  if (( ! hit )); then
    [[ "$m" =~ $re_word ]] && hit=1
    [[ "$m" =~ $re_phrase ]] && hit=1
  fi
  (( nc )) || shopt -u nocasematch
  printf '%s' "$hit"
}

# @pure
# <사람 턴 줄들> → 턴마다 "<세션><탭><시각><탭><바뀜 0|1><탭><보여 줌 0|1><탭><완료 0|1><탭><수정 요구 0|1><탭><확인 질문 수>".
# 모델이 아무것도 하지 않은 턴은 줄을 내지 않고, 앞 턴의 완료 상태도 끊지 않는다. 바뀜은 편집이 있고 마지막 글에 '결과물 변화
# 없음'이 없을 때. 완료는 편집이 있는 턴이 모델의 글로 끝나고 그 글이 질문이 아닐 때. 수정 요구는 같은 세션에서 완료 보고 뒤
# 처음으로 모델이 답한 사람 메시지만 본다. 줄은 모으지 않고 바로 내보낸다.
scv_show_real_classify() {
  local turns="${1:-}" tab=$'\t' line sess ts seq msg lq last rest
  local edited changed shown fin corr asks tail_ask tail_conf s1 c_only prev_fin=0 prev_sess=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    sess="${line%%"$tab"*}"; rest="${line#*"$tab"}"
    ts="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    seq="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    msg="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    lq="${rest%%"$tab"*}"; last="${rest#*"$tab"}"
    [[ "$sess" == "$prev_sess" ]] || { prev_fin=0; prev_sess="$sess"; }
    [[ -n "$seq" ]] || continue
    edited=0; [[ "$seq" == *E* ]] && edited=1
    tail_ask=0; tail_conf=0
    if [[ "$seq" == *T && -n "$last" ]]; then
      tail_ask="$(scv_asks_in_text "$(scv_answer_body "$(scv_show_real_lines "$last")")")"
      [[ "$tail_ask" == "1" ]] || tail_ask=0
      (( tail_ask )) && [[ "$(scv_show_real_is_confirm "$lq")" == "1" ]] && tail_conf=1
    fi
    changed=$edited
    (( edited )) && [[ "$seq" == *T && "$(scv_show_real_is_nochange "$last")" == "1" ]] && changed=0
    c_only="${seq//[^CK]/}"; asks=$(( ${#c_only} + tail_ask ))
    shown=0
    if (( changed )); then
      s1="${seq#*E}"
      if [[ "$s1" == *R* ]]; then
        s1="${s1#*R}"
        [[ "$s1" == *K* ]] && shown=1
        (( tail_conf )) && [[ "$s1" == *T ]] && shown=1
      fi
    fi
    fin=0; (( edited && ! tail_ask )) && [[ "$seq" == *T ]] && fin=1
    corr=0
    (( prev_fin )) && corr="$(scv_show_real_is_correction "$msg")"
    printf '%s\n' "$sess$tab$ts$tab$changed$tab$shown$tab$fin$tab$corr$tab$asks"
    prev_fin=$fin
  done <<< "$turns"
  return 0
}

# @pure
# <기록 시각 YYYY-MM-DDTHH:MM…> <지역 오프셋(분)> → 그 지역의 날짜 YYYYMMDD. 못 읽으면 빈 값.
# 시각 끝이 Z 이거나 시간대가 없으면 UTC, ±HH:MM(또는 ±HHMM)이 붙으면 그만큼 빼서 UTC 로 본다.
# 율리우스 일수로 옮겨 하루를 더하거나 뺀다 — 달 · 해 · 윤년 경계를 바깥 명령 없이 넘는다.
scv_show_real_local_date() {
  local ts="${1:-}" off="${2:-0}" y m d hh mi tz=0 mins sh a y2 m2 j b c e f g
  [[ "$off" =~ ^-?[0-9]+$ ]] || off=0
  [[ "$ts" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}) ]] || return 0
  y=$(( 10#${BASH_REMATCH[1]} )); m=$(( 10#${BASH_REMATCH[2]} )); d=$(( 10#${BASH_REMATCH[3]} ))
  hh=$(( 10#${BASH_REMATCH[4]} )); mi=$(( 10#${BASH_REMATCH[5]} ))
  if [[ "$ts" =~ ([+-])([0-9]{2}):?([0-9]{2})$ ]]; then
    tz=$(( 10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]} ))
    [[ "${BASH_REMATCH[1]}" == "-" ]] && tz=$(( 0 - tz ))
  fi
  mins=$(( hh * 60 + mi - tz + off ))
  sh=$(( (mins + 4320) / 1440 - 3 ))
  a=$(( (14 - m) / 12 )); y2=$(( y + 4800 - a )); m2=$(( m + 12 * a - 3 ))
  j=$(( d + (153 * m2 + 2) / 5 + 365 * y2 + y2 / 4 - y2 / 100 + y2 / 400 - 32045 + sh ))
  a=$(( j + 32044 )); b=$(( (4 * a + 3) / 146097 )); c=$(( a - 146097 * b / 4 ))
  e=$(( (4 * c + 3) / 1461 )); f=$(( c - 1461 * e / 4 )); g=$(( (5 * f + 2) / 153 ))
  d=$(( f - (153 * g + 2) / 5 + 1 )); m=$(( g + 3 - 12 * (g / 10) )); y=$(( 100 * b + e - 4800 + g / 10 ))
  printf '%04d%02d%02d' "$y" "$m" "$d"
}

# @pure
# <지역 오프셋 "+HHMM" · "-HHMM"(date +%z 모양)> → 분(예: +0900 → 540). 모양이 다르면 0.
scv_show_real_offset() {
  local z="${1:-}" mm
  [[ "$z" =~ ^([+-])([0-9]{2})([0-9]{2})$ ]] || { printf '0'; return 0; }
  mm=$(( 10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]} ))
  [[ "${BASH_REMATCH[1]}" == "-" ]] && mm=$(( 0 - mm ))
  printf '%s' "$mm"
}

# @pure
# <YYYY> <MM> <DD> → 1(있는 날) | 0. 달마다 날 수 · 윤년을 본다(2026-02-30 은 없는 날).
scv_show_real_valid_day() {
  local y=$(( 10#${1:-0} )) m=$(( 10#${2:-0} )) d=$(( 10#${3:-0} )) dim=31
  (( m >= 1 && m <= 12 && d >= 1 )) || { printf '0'; return 0; }
  case "$m" in
    4|6|9|11) dim=30 ;;
    2) dim=28; (( (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 )) && dim=29 ;;
  esac
  if (( d <= dim )); then printf '1'; else printf '0'; fi
}

# @pure
# <기간 "YYYY-MM-DD..YYYY-MM-DD"> → "YYYYMMDD YYYYMMDD"(시작 · 끝, 끝 날 포함). 모양이 다르거나, 없는 날이거나, 시작이 끝보다
# 늦으면 빈 값.
scv_show_real_range() {
  local r="${1:-}" y1 m1 d1 y2 m2 d2
  [[ "$r" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})\.\.([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || return 0
  y1="${BASH_REMATCH[1]}"; m1="${BASH_REMATCH[2]}"; d1="${BASH_REMATCH[3]}"
  y2="${BASH_REMATCH[4]}"; m2="${BASH_REMATCH[5]}"; d2="${BASH_REMATCH[6]}"
  [[ "$(scv_show_real_valid_day "$y1" "$m1" "$d1")$(scv_show_real_valid_day "$y2" "$m2" "$d2")" == "11" ]] || return 0
  (( 10#$y1$m1$d1 <= 10#$y2$m2$d2 )) || return 0
  printf '%s %s' "$y1$m1$d1" "$y2$m2$d2"
}

# @pure
# <분류된 턴 줄들> <지역 오프셋(분)> <켜기 전 "시작 끝"> <켠 뒤 "시작 끝"> → 두 줄
#   "before<탭><세션 수><탭><사람 턴><탭><바뀐 턴><탭><보여 준 턴><탭><완료 뒤 수정 요구><탭><확인 질문>" · "after<탭>…"
# 턴은 사람 메시지의 지역 날짜로 기간에 든다. 두 기간에 다 들지 않는 턴은 세지 않는다. 세션은 그 기간에 턴이 있는 것만 센다.
scv_show_real_count() {
  local rows="${1:-}" off="${2:-0}" br="${3:-}" ar="${4:-}" tab=$'\t' nl=$'\n'
  local line sess ts ch sh fin corr asks rest d p bf bt af at
  local b_s="$nl" b_n=0 b_t=0 b_c=0 b_w=0 b_r=0 b_q=0 a_s="$nl" a_n=0 a_t=0 a_c=0 a_w=0 a_r=0 a_q=0
  bf="${br%% *}"; bt="${br##* }"; af="${ar%% *}"; at="${ar##* }"
  [[ "$bf$bt" =~ ^[0-9]{16}$ ]] || { bf=""; bt=""; }
  [[ "$af$at" =~ ^[0-9]{16}$ ]] || { af=""; at=""; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    sess="${line%%"$tab"*}"; rest="${line#*"$tab"}"
    ts="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    ch="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    sh="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    fin="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    corr="${rest%%"$tab"*}"; asks="${rest#*"$tab"}"
    [[ "$ch" =~ ^[01]$ && "$sh" =~ ^[01]$ && "$corr" =~ ^[01]$ && "$asks" =~ ^[0-9]+$ ]] || continue
    d="$(scv_show_real_local_date "$ts" "$off")"
    [[ -n "$d" ]] || continue
    p=""
    if [[ -n "$bf" ]] && (( 10#$d >= 10#$bf && 10#$d <= 10#$bt )); then p=b
    elif [[ -n "$af" ]] && (( 10#$d >= 10#$af && 10#$d <= 10#$at )); then p=a
    fi
    if [[ "$p" == b ]]; then
      [[ "$b_s" == *"$nl$sess$nl"* ]] || { b_s+="$sess$nl"; b_n=$(( b_n + 1 )); }
      b_t=$(( b_t + 1 )); b_c=$(( b_c + ch )); b_w=$(( b_w + sh )); b_r=$(( b_r + corr )); b_q=$(( b_q + asks ))
    elif [[ "$p" == a ]]; then
      [[ "$a_s" == *"$nl$sess$nl"* ]] || { a_s+="$sess$nl"; a_n=$(( a_n + 1 )); }
      a_t=$(( a_t + 1 )); a_c=$(( a_c + ch )); a_w=$(( a_w + sh )); a_r=$(( a_r + corr )); a_q=$(( a_q + asks ))
    fi
  done <<< "$rows"
  printf 'before\t%s\t%s\t%s\t%s\t%s\t%s\n' "$b_n" "$b_t" "$b_c" "$b_w" "$b_r" "$b_q"
  printf 'after\t%s\t%s\t%s\t%s\t%s\t%s\n' "$a_n" "$a_t" "$a_c" "$a_w" "$a_r" "$a_q"
}

# @pure
# <부분> <전체> → "N% (부분)". 전체가 0 이면 "- (부분)".
scv_show_real_pct() {
  local x="${1:-0}" n="${2:-0}"
  if (( n == 0 )); then printf -- '- (%s)' "$x"; else printf '%s%% (%s)' "$(( x * 100 / n ))" "$x"; fi
}

# @pure
# <합> <세션 수> → "A.BC (합)" — 세션당 값(소수 둘째 자리까지 버림). 세션이 0 이면 "- (합)".
scv_show_real_per() {
  local x="${1:-0}" n="${2:-0}" v
  if (( n == 0 )); then printf -- '- (%s)' "$x"; return 0; fi
  v=$(( x * 100 / n ))
  printf '%s.%02d (%s)' "$(( v / 100 ))" "$(( v % 100 ))" "$x"
}

# @pure
# <셈 두 줄(scv_show_real_count)> <언어 SCV_LANG> <켜기 전 기간 원문> <켠 뒤 기간 원문> <읽은 기록 파일 수> <읽지 못한 파일 수>
# → 표 한 장과 범례. 숫자와 날짜만 낸다 — 대화 내용 · 경로 · 세션 이름은 내지 않는다.
scv_show_real_render() {
  local counts="${1:-}" lang="${2:-}" braw="${3:-}" araw="${4:-}" nf="${5:-0}" nu="${6:-0}" tab=$'\t' line k rest
  local n t c w r q row1="" row2="" h1 h2 l1 l2 l3 l4 l5 l6="" title pb pa
  case "$lang" in
    [Kk]orean|ko|KO|한국어)
      title="실체 보여 주기 — 실사용 보고 (켜기 전 · 켠 뒤)"
      h1="| 기간 | 세션 | 바뀐 턴 | (a) 보여 줌 | (b) 수정/세션 | (c) 확인/세션 |"
      pb="켜기 전"; pa="켠 뒤"
      l1="(a) 결과물이 바뀐 턴 중 '편집 → 실행 → 계속 · 고칠 점을 묻는 확인' 순서가 있는 턴의 비율 (괄호: 턴 수)"
      l2="(b) 완료 보고 뒤 처음 답한 사람 메시지가 고쳐 달라는 말인 수 ÷ 세션 (괄호: 합)"
      l3="(c) 확인 창 + 턴을 끝낸 글 질문 ÷ 세션 (괄호: 합)"
      l4="숫자는 방향을 보는 용도다 — 두 기간은 일의 종류가 다를 수 있다. 세는 기준: core/scripts/lib/show-real.sh 머리말."
      l5="읽은 세션 기록 파일: ${nf}개"
      (( nu == 0 )) || l6="대화 항목이 없거나 읽지 못한 파일(권한 · 기록 모양): ${nu}개 — 숫자에 들지 않았다" ;;
    [Jj]apanese|ja|JA|日本語)
      title="実物を見せる — 実利用レポート（有効化前・後）"
      h1="| 期間 | セッション | 変更ターン | (a) 見せた | (b) 修正/セッション | (c) 確認/セッション |"
      pb="有効化前"; pa="有効化後"
      l1="(a) 成果物が変わったターンのうち「編集 → 実行 → 続けるか・直す点を尋ねる確認」の順があるターンの割合（括弧: ターン数）"
      l2="(b) 完了報告の後に最初に応答した人のメッセージが修正の依頼である数 ÷ セッション（括弧: 合計）"
      l3="(c) 確認ウィンドウ + ターンを終えた文章の質問 ÷ セッション（括弧: 合計）"
      l4="数字は方向を見るためのもの — 二つの期間は仕事の種類が違いうる。数え方: core/scripts/lib/show-real.sh の冒頭。"
      l5="読んだセッション記録ファイル: ${nf}件"
      (( nu == 0 )) || l6="会話項目がないか読めなかったファイル（権限・記録の形）: ${nu}件 — 数字に含まれていない" ;;
    *)
      title="Show the real thing — real-use report (before · after)"
      h1="| Period | Sessions | Changed turns | (a) Shown | (b) Fixes/session | (c) Asks/session |"
      pb="Before"; pa="After"
      l1="(a) Share of changed turns with 'edit → run → a continue-or-fix confirmation' in that order (in brackets: turns)"
      l2="(b) First answered person message after a completion report that asks for a fix, per session (in brackets: total)"
      l3="(c) Choice windows + turn-ending text questions, per session (in brackets: total)"
      l4="The numbers show direction only — the two periods may hold different kinds of work. Counting rules: header of core/scripts/lib/show-real.sh."
      l5="Session record files read: ${nf}"
      (( nu == 0 )) || l6="Files with no conversation entries or not readable (permission · record shape): ${nu} — not in the numbers" ;;
  esac
  h2="|---|---|---|---|---|---|"
  while IFS= read -r line || [[ -n "$line" ]]; do
    k="${line%%"$tab"*}"; rest="${line#*"$tab"}"
    [[ "$k" == before || "$k" == after ]] || continue
    n="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    t="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    c="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    w="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    r="${rest%%"$tab"*}"; q="${rest#*"$tab"}"
    if [[ "$k" == before ]]; then
      row1="| $pb $braw | $n | $c | $(scv_show_real_pct "$w" "$c") | $(scv_show_real_per "$r" "$n") | $(scv_show_real_per "$q" "$n") |"
    else
      row2="| $pa $araw | $n | $c | $(scv_show_real_pct "$w" "$c") | $(scv_show_real_per "$r" "$n") | $(scv_show_real_per "$q" "$n") |"
    fi
  done <<< "$counts"
  printf '%s\n' "$title" "" "$h1" "$h2" "$row1" "$row2" "" "$l1" "$l2" "$l3" "$l4" "$l5"
  [[ -z "$l6" ]] || printf '%s\n' "$l6"
}
