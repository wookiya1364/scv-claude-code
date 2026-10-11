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
# 실사용 보고 — 기록 읽기(효과) → scv_show_real_entries → scv_show_real_split → scv_show_real_classify(규칙 단계)
#               → 판정자 단계(규칙만으로 못 가린 턴만 — 아래 '판정자 단계' 절, 판정자 부르기 · 저장 파일은 보고 스크립트의 효과)
#               → scv_show_real_merge → scv_show_real_count → scv_show_real_render → 출력(효과)
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
#   · 실제 결과를 보여 준 턴: 바뀐 턴 중 첫 편집 뒤 실행의 출력을 글이나 확인 창에 그대로 인용해 보인 뒤(또는 보이며) 묻는 턴 —
#     규칙 단계는 그 뒤의 선택 창이나 턴을 끝내는 글 질문(물음표)을 묻기로 센다(계획 20261011-wookiya1364-show-real-classifier-rules).
#     결과를 보인 뒤 물음표 없이 끝난 턴(예: '리뷰 부탁드립니다')은 뜻을 읽어야 갈리므로 판정자에게 끝 글 발췌로 묻는다(계획
#     20261011-wookiya1364-show-real-classifier-hybrid) — 판정자가 없거나 답하지 못하면 보여 주지 않음으로 세고 그 수를 보고에 낸다.
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
# 실측에서 잰 지시(사용자 승인)를 바탕으로 한다 — 본문은 contracts/show-real.md 한 곳. 묻는 통로(choice · text)의 둘째 줄에는
# 사용자가 정해 둔 검토 시점 문구가 붙는다(계획 20261009-wookiya1364-show-real-at-checkpoint — 그 시점을 앞당기지 않고, 그때 요약 대신
# 실제 실행 결과를 보인다). 묻지 않는 통로(none)는 그대로.
scv_show_real_rule() {
  local sw="${1:-on}" ch="${2:-text}" second ckpt
  [[ "$sw" == "on" ]] || return 0
  ckpt="사용자가 검토 시점을 정해 두었으면(예: 커밋 뒤 검토) 앞당기지 말고 그 시점에, 요약 대신 실제로 돌린 결과를 보이며 물어라."
  case "$ch" in
    choice) second="그 결과(명령 출력 · 화면 · 함수 호출 결과)를 그대로 보여 주고, '이대로 계속할까요, 고칠 점이 있나요?'를 선택 창으로 짧게 물어라(보기는 2개 이상 — 계속 · 고칠 점). $ckpt 설명은 한두 줄로." ;;
    none)   second="그 결과(명령 출력 · 화면 · 함수 호출 결과)를 보고에 그대로 남겨라 — 사람이 없는 실행이나 자동 알림 턴이라 묻지 않는다. 설명은 한두 줄로." ;;
    *)      second="그 결과(명령 출력 · 화면 · 함수 호출 결과)를 그대로 보여 주고, '이대로 계속할까요, 고칠 점이 있나요?'를 글 질문 한 번으로 짧게 물어라. $ckpt 설명은 한두 줄로." ;;
  esac
  printf '%s\n' \
    "[SCV 실체 보여 주기] 결과물이 바뀌는 일이면, 설명이나 글로 된 견본 대신 처음 돌아가는 순간에 가장 작은 것을 실제로 실행해" \
    "$second" \
    "결과물이 바뀌지 않는 일은 보여 주지도 묻지도 말고 '결과물 변화 없음'이라고 적어라. 본문: contracts/show-real.md"
}

# ---------------------------------------------------------------- 실사용 보고

# @deterministic
# 표준입력: 세션 기록 JSONL(한 세션). <선택 창 이름> [<거절 표시>] → 기록 항목 줄들(기록 순서 그대로):
#   "U<탭><시각><탭><앞 1000자><탭><판별용 글>"(사용자 메시지 · 프롬프트가 든 첨부 — 줄바꿈 · 탭은 공백. 판별용 글은 8000자가 넘으면
#                                            앞 6000자 + 끝 2000자)
#   "E"(편집) · "R"(실행) · "O"(그 밖의 도구 호출)
#   "X<탭><출력 조각>"(실행 결과 — 앞에 나온 실행(R) 호출의 결과만. 앞 20줄 + 끝 20줄, 줄마다 200자, 색 제어 문자 뺌, 줄 사이 \x1e)
#   "C<탭><질문들><탭><창 글>"(확인 창 — 질문들은 입력 안의 question 값들, 없으면 첫 글. 질문 사이는 \x1f, 질문마다 앞 1000자.
#                              창 글은 입력 안의 모든 글(질문 · 보기 이름 · 설명 · 미리보기)을 \x1e 로 이음, 글마다 2000자 · 모두 12000자)
#   "Z"(거절된 확인 창 — 앞에 나온 확인 창 호출의 결과가 오류(is_error)이고 그 글이 거절 표시(호스트 설정
#       SCV_CHOICE_REJECTED_PREFIX)로 시작한다. 호스트가 거절해 사람에게 보이지 않은 창이다 — 예: 보기가 하나뿐인 창. 사람이 보고
#       닫은 창(오류지만 거절 표시가 없음)은 물은 것이라 Z 가 아니다. 거절 표시가 비면 Z 를 내지 않는다. 계획
#       20261011-wookiya1364-show-real-classifier-hybrid)
#   "T<탭><마지막 두 줄><탭><글>"(모델의 글 — 마지막 두 줄은 빈 줄을 뺀 끝 두 줄(공백으로 이음, 1000자), 글은 끝 60줄 · 4000자 —
#                                질문 판정(scv_asks_in_text)은 끝 두 문단 · 끝 40줄만 본다. 줄바꿈 \x1e · 탭은 공백. 자른 자리가
#                                코드 블록 안이면 앞에 여는 울타리를 붙인다 — 종료 훅과 같은 처리)
# 기록은 표준입력을 통째로 받아(--rawfile) jq 안에서 줄로 나눈다 — 원문 그대로 읽기(-R)는 jq 1.6 · 1.7 에서 4,096바이트 경계에
# 걸친 여러 바이트 글자를 깨뜨린다(2026-10-11 확인). 깨진 줄 · 객체가 아닌 줄 · 메타 · 기록에만 보이는 줄(압축 요약 등) · 하위
# 에이전트(isSidechain) 줄은 건너뛴다. 도구 결과만 든 사용자 줄은 실행 결과(X)와 거절된 창(Z)만 낸다 — 어느 결과가 실행 · 확인
# 창의 것인지 알려고 앞에서 본 호출의 id 를 기억하며 읽는다. 실행은 무언가를
# 돌린 명령이다 — 파일을 읽거나 찾기만 하는 명령(cat · sed · grep · ls · git diff 등)은 빼되, 결과 파일(.out · .log · .json · .txt
# 등)을 읽는 명령은 넣는다(배경 작업의 결과를 보는 일). 문서를 읽어 들인 출력은 실행 결과가 아니다.
scv_show_real_entries() {
  jq -nr --rawfile in /dev/stdin --arg tool "${1:-}" --arg rej "${2:-}" '
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
    def rtext: if type == "string" then .
               elif type == "array" then [.[] | select(obj and .type == "text") | (.text // "")] | join("\n")
               else "" end;
    def frag: split("\n") | (if (.[40:] | length) != 0 then .[0:20] + .[-20:] else . end)
              | map(split("\t") | join(" ") | split("\r") | join("") | .[0:400]
                    | (if index("\u001b") != null then gsub("\u001b\\[[0-9;?]*[A-Za-z]"; "") else . end) | .[0:200])
              | map(select(length != 0)) | join("\u001e");
    def wtext: [.. | strings] | map(.[0:2000] | enc) | join("\u001e") | .[0:12000];
    def readers: ["cat","head","tail","sed","grep","egrep","fgrep","rg","awk","less","more","nl","bat","ls","find","wc","stat",
                  "file","tree","echo","printf","pwd","cd","date","which","type","true","sleep","export","set","test","[","du","diff"];
    def word1: sub("^\\s*(?:[A-Za-z_][A-Za-z0-9_]*=\\S*\\s+)*"; "") | (split(" ")[0] // "") | split("/")[-1];
    def seg_reads: word1 as $w
                   | any(readers[]; . == $w)
                     or ($w == "git" and test("git\\s+(?:-C\\s+\\S+\\s+)?(?:--no-pager\\s+)?(?:diff|show|blame|cat-file)\\b"));
    def results_file: test("\\.(out|output|log|jsonl?|txt|csv|tsv|err)(?:[\\s;&|)\u0027\"]|$)");
    def executes: ([.[0:2000] | splits("\\|\\||&&|[;|\\n]")] | map(select(test("\\S"))) | any(.[]; seg_reads | not))
                  or (.[0:2000] | results_file);
    def is_run($b): ($b.type == "tool_use") and (($b.name // "") != $tool or $tool == "")
                    and (($b.input // null) | obj) and (($b.input.command // null) | type) == "string"
                    and ((($b.input.file_path // $b.input.notebook_path // $b.input.path // null) | type) != "string"
                         or (($b.input.content // $b.input.new_string // $b.input.edits // $b.input.new_source // null) == null))
                    and ($b.input.command | executes);
    def runs($o): if $o.type == "assistant" then
                    [($o.message.content // null) | if type == "array" then .[] else empty end | select(obj) | select(is_run(.))
                     | (.id // "")]
                  else [] end;
    def wins($o): if $o.type == "assistant" and $tool != "" then
                    [($o.message.content // null) | if type == "array" then .[] else empty end | select(obj)
                     | select(.type == "tool_use" and (.name // "") == $tool) | (.id // "")]
                  else [] end;
    def events($o; $runs):
      if $o.type == "user" and (($o.isMeta // false) != true) and (($o.isVisibleInTranscriptOnly // false) != true)
         and (($o.isCompactSummary // false) != true) then
        ($o.message.content // null) as $c
        | if ($c | type) == "array" and ([$c[] | select(obj and .type == "tool_result")] | length) != 0 then
            $c[] | select(obj and .type == "tool_result") | $runs[(.tool_use_id // "")] as $k
            | if $k == true then "X\t\((.content // "") | rtext | frag)"
              elif $k == "w" and (.is_error // false) == true and $rej != ""
                   and ((.content // "") | rtext | startswith($rej)) then "Z"
              else empty end
          else
            (if ($c | type) == "string" then $c
             elif ($c | type) == "array" and ([$c[] | select(obj and .type == "text")] | length) != 0
             then [$c[] | select(obj and .type == "text") | (.text // "")] | join("\n")
             else empty end) as $m
            | "U\t\($o.timestamp // "" | sp)\t\($m | .[0:1000] | sp)\t\($m | head_tail | sp)"
          end
      elif $o.type == "attachment" and (($o.attachment.prompt // null) | type) == "string" then
        $o.attachment.prompt as $m
        | "U\t\($o.timestamp // $o.attachment.timestamp // "" | sp)\t\($m | .[0:1000] | sp)\t\($m | head_tail | sp)"
      elif $o.type == "assistant" then
        ($o.message.content // null) | if type == "array" then .[] else empty end | select(obj)
        | if .type == "tool_use" then
            (.input // null) as $in
            | if $tool != "" and (.name // "") == $tool then
                ([$in | .. | objects | .question? | strings]
                 | if length == 0 then [([$in | .. | strings] | first // "")] else . end
                 | map(.[0:1000] | sp) | join("\u001f")) as $q
                | "C\t\($q)\t\($in | wtext)"
              elif ($in | obj)
                   and (($in.file_path // $in.notebook_path // $in.path // null) | type) == "string"
                   and (($in.content // $in.new_string // $in.edits // $in.new_source // null) != null) then "E"
              elif ($in | obj) and (($in.command // null) | type) == "string" then "R"
              else "O" end
          elif .type == "text" then "T\t\((.text // "") | lastq)\t\((.text // "") | tailcut | enc)"
          else empty end
      else empty end;
    foreach ($in | split("\n")[] | (fromjson? // null) | select(obj) | select((.isSidechain // false) != true)) as $o
      ({}; reduce (runs($o)[]) as $i (.; .[$i] = true) | reduce (wins($o)[]) as $i (.; .[$i] = "w"); events($o; .))' 2>/dev/null
}

# @deterministic
# <실행 출력 줄들(\x1e 또는 줄바꿈으로 이음)> <묻는 글 · 창(\x1e 또는 줄바꿈으로 이음)> → 1(출력이 그대로 인용됨) | 0.
# 인용: (가) 공백을 하나로 줄인 출력 한 줄(16바이트 이상, 숫자가 있거나 낱말 셋 이상)이 글 안에 그대로 있다, (나) 출력 한 줄의 이웃한
# 두 낱말(앞뒤 문장부호를 떼고 소문자로, 둘 다 영문이나 숫자를 품고 숫자가 든 6바이트 이상 — 예: '849 passed', 'pass=87 fail=0')이
# 글 안에서도 이웃해 있다, 또는 (다) 출력에서 결과 낱말(passed · failed · errors · warnings · skipped · tests · ok · 통과 · 실패 · 경고 ·
# 오류 · 건너뜀 · 성공, 평가 수치 tp · tn · fp · fn · 잘못 · 놓침 등) 바로 옆의 수(2 이상 — 예: '9 passed', 'pass=87', '통과 57', '57개 통과')가 글 안에서 홀로 선 수로('9개' 는
# 되고 'T9' · '1.9' 는 안 됨) 앞뒤 세 낱말 안에 결과 낱말(앞부분 일치 — '통과했습니다')과 함께 있다, 또는 (라) 출력의 모양 있는 값
# (분수 · 소수 · 판 번호 · 시각 · 백분율 — 예: '42/42', '0.64.2', '0.96', '87%')이 글 안에 낱말 그대로 있다. 한글 문장끼리의 우연한 겹침
# ('전제 6개' 같은)은 인용으로 치지 않는다 — 이 저장소의 도움 스크립트 출력에는 문서 문장이 섞인다. 바이트 단위(LC_ALL=C)로 본다 —
# 맥 awk 와 리눅스 awk 가 같은 답을 내도록. 셸에서 긴 한글을 치환하지 않고 tr · awk 한 번씩만 부른다(bash 3.2 의 긴 한글 처리 비용).
# 셋째 인자가 line 이면 1 · 0 대신 인용된 출력 줄(공백을 하나로 줄인 원래 줄)을 내고, 인용이 없으면 빈 값 — 판정은 같다(판정자
# 단계가 '보인 출력'으로 쓴다, 계획 20261011-wookiya1364-show-real-classifier-hybrid).
scv_show_real_quotes() {
  local mode="${3:-}"
  [[ -n "${1:-}" && -n "${2:-}" ]] || { [[ "$mode" == line ]] || printf '0'; return 0; }
  printf '%s\n\035\n%s\n' "$1" "$2" | LC_ALL=C tr '\036' '\n' | LC_ALL=C awk -v mode="$mode" '
    function hit(i) { if (mode == "line") print norm(lines[i]); else print 1; exit }
    function norm(s) { gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
    function tok(s) { gsub(/^[][(){}"`,.;:!?*|_]+/, "", s); gsub(/[][(){}"`,.;:!?*|_]+$/, "", s); return tolower(s) }
    function lead(s) { return (match(s, /^[0-9]+/) && substr(s, RLENGTH + 1) !~ /[0-9a-z.,\/=:-]/) ? substr(s, 1, RLENGTH) : "" }
    function isrw(t,   w) { for (w in rw) if (index(t, w) == 1) return 1; return 0 }
    function value(t, nb1, nb2,   p, k) {
      if (t ~ /^[a-z]+[=:][0-9]+$/) { p = t; sub(/[=:].*$/, "", p); k = t; sub(/^[^=:]*[=:]/, "", k); return (p in rw) ? k : "" }
      k = lead(t); if (k == "") return ""
      return ((nb1 in rw) || (nb2 in rw)) ? k : ""
    }
    BEGIN {
      SHAPED = "^[0-9]+([./:][0-9]+)+%?$|^[0-9]+%$"
      part = 0; nl = 0; ctx = ""
      split("passed pass failed fail failures failure errors error warnings warning skipped skip tests test ok succeeded tp tn fp fn 통과 실패 경고 오류 건너뜀 성공 잘못 놓침", rwl, " ")
      for (i in rwl) rw[rwl[i]] = 1
    }
    $0 == "\035" { part = 1; next }
    part == 0 { lines[++nl] = $0; next }
    { ctx = ctx " " $0 }
    END {
      ctx = tolower(norm(ctx)); split(ctx, ct, " ")
      for (i = 1; i in ct; i++) ct[i] = tok(ct[i])
      for (i = 1; (i + 1) in ct; i++) if (ct[i] != "" && ct[i + 1] != "") bg[ct[i] " " ct[i + 1]] = 1
      for (i = 1; i in ct; i++) if (ct[i] ~ SHAPED) shaped[ct[i]] = 1
      for (i = 1; i in lines; i++) {
        l = tolower(norm(lines[i])); if (l == "") continue
        split(l, w, " ")
        if (substr(l, 16) != "" && (l ~ /[0-9]/ || (3 in w)) && index(ctx, l)) hit(i)
        split("", v); m = 0
        for (j = 1; j in w; j++) { t = tok(w[j]); if (t != "") v[++m] = t }
        for (j = 1; (j + 1) in v; j++) {
          f = v[j] " " v[j + 1]
          if (v[j] ~ /[0-9a-z]/ && v[j + 1] ~ /[0-9a-z]/ && f ~ /[0-9]/ && substr(f, 6) != "" && (f in bg)) hit(i)
        }
        for (j = 1; j in v; j++) if (v[j] ~ SHAPED && (v[j] in shaped)) hit(i)
        for (j = 1; j in v; j++) {
          k = value(v[j], (((j - 1) in v) ? v[j - 1] : ""), (((j + 1) in v) ? v[j + 1] : ""))
          if (k != "" && (k + 0) != 0 && (k + 0) != 1 && !((k + 0) in num)) num[k + 0] = i
        }
      }
      for (i = 1; i in ct; i++) {
        k = (ct[i] ~ /^[a-z]+[=:][0-9]+$/) ? ct[i] : lead(ct[i])
        if (k ~ /[=:]/) sub(/^[^=:]*[=:]/, "", k)
        if (k == "" || !((k + 0) in num)) continue
        for (d = -3; d != 4; d++) if (((i + d) in ct) && isrw(ct[i + d])) hit(num[k + 0])
      }
      if (mode != "line") print 0
    }'
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
#   "<세션><탭><시각><탭><사건 글자들 E·R·O·C·K·Q·T·q><탭><사람 메시지 앞 1000자><탭><마지막 글의 끝 두 줄><탭><마지막 글(\x1e 줄바꿈)>
#    <탭><보인 출력 줄>"
# 첫 사람 메시지 앞의 항목은 버리고, 자동 입력(scv_mp_prompt_kind 가 auto)은 턴을 열지 않는다. 확인 창은 질문 가운데 하나라도
# 계속할지와 고칠 점을 함께 묻는 것이면 K, 아니면 C 로 적는다. 첫 편집 뒤 실행의 출력이 있을 때, 그 뒤의 모델 글이나 확인 창(바로
# 앞 모델 글과 함께)이 그 출력을 인용하면(scv_show_real_quotes) '보임'이 되고 — 보인 뒤(또는 보이며) 묻는 확인 창 글자 뒤에 Q 를,
# 보임이 있고 턴이 모델 글로 끝나면 사건 글자 끝에 q 를 붙인다(보이는 글과 묻는 글이 달라도 된다). 인용은 그때까지 실행 20번의
# 출력에서 찾고, 한 턴에서 한 번 보이면 더 찾지 않는다 — 그때 인용된 출력 줄이 '보인 출력 줄'(보임이 없으면 빈 값). 확인 창이
# 거절됐으면(Z — 사람에게 보이지 않음) 바로 앞 확인 창이 더한 글자(C · K · Q)와 그 창 때문에 생긴 보임을 되돌린다(알려진 한계:
# 한 메시지에 확인 창이 둘이고 앞 창만 거절되면 뒤 창을 되돌린다 — 로컬 기록 1,758개에 0건, 2026-10-11). 턴을 모으지 않고 끝날
# 때마다 내보낸다.
scv_show_real_split() {
  local sess="${1:-}" entries="${2:-}" tags="${3:-}" pfx="${4:-}" sfx="${5:-}"
  local tab=$'\t' us=$'\x1f' rs=$'\x1e' line k rest ts head txt q cf wq wctx qm cur=0 seen_e=0 shown=0 p_text=""
  local c_ts="" c_seq="" c_msg="" c_lq="" c_last="" c_quote="" w_pos=0 w_len=0 w_shown=0 w_quote="" IFS
  local -a qs outs
  while IFS= read -r line || [[ -n "$line" ]]; do
    k="${line%%"$tab"*}"
    case "$k" in
      U)
        rest="${line#U"$tab"}"; ts="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
        head="${rest%%"$tab"*}"; txt="${rest#*"$tab"}"
        [[ "$(scv_mp_prompt_kind "$txt" "$tags" "$pfx" "$sfx")" == "human" ]] || continue
        (( cur )) && _scv_show_real_turn_line
        cur=1; c_ts="$ts"; c_seq=""; c_msg="$head"; c_lq=""; c_last=""; c_quote=""; seen_e=0; shown=0; outs=(); p_text=""; w_len=0 ;;
      E)
        (( cur )) && { c_seq+="E"; seen_e=1; } ;;
      R|O)
        (( cur )) && c_seq+="$k" ;;
      X)
        (( cur && seen_e )) && outs+=("${line#X"$tab"}") ;;
      C)
        if (( cur )); then
          w_pos=${#c_seq}; w_shown=$shown; w_quote="$c_quote"
          cf=0; qs=(); wq=""; wctx=""
          IFS="$tab" read -r wq wctx <<< "${line#C"$tab"}"
          IFS="$us" read -r -a qs <<< "$wq"
          for q in ${qs[@]+"${qs[@]}"}; do
            [[ "$(scv_show_real_is_confirm "$q")" == "1" ]] && { cf=1; break; }
          done
          if (( cf )); then c_seq+="K"; else c_seq+="C"; fi
          if (( ${#outs[@]} )); then
            if (( ! shown )); then
              qm="$(scv_show_real_quotes "$(_scv_show_real_recent_outs)" "$p_text$rs$wctx" line)"
              [[ -n "$qm" ]] && { shown=1; c_quote="$qm"; }
            fi
            (( shown )) && c_seq+="Q"
          fi
          w_len=$(( ${#c_seq} - w_pos ))
        fi ;;
      Z)
        if (( cur && w_len )); then   # 거절된 창 — 그 창이 더한 글자와 그 창 때문에 생긴 보임을 되돌린다
          c_seq="${c_seq:0:w_pos}${c_seq:w_pos+w_len}"; shown=$w_shown; c_quote="$w_quote"; w_len=0
        fi ;;
      T)
        if (( cur )); then
          c_seq+="T"; rest="${line#T"$tab"}"; c_lq="${rest%%"$tab"*}"; c_last="${rest#*"$tab"}"; p_text="$c_last"
          if (( ${#outs[@]} && ! shown )); then
            qm="$(scv_show_real_quotes "$(_scv_show_real_recent_outs)" "$c_last" line)"
            [[ -n "$qm" ]] && { shown=1; c_quote="$qm"; }
          fi
        fi ;;
    esac
  done <<< "$entries"
  (( cur )) && _scv_show_real_turn_line
  return 0
}

# scv_show_real_split 의 한 부분 — 그 함수의 지역 변수(outs)를 읽어 묻기 직전 실행 20번까지의 출력을 \x1e 로 이어 낸다.
_scv_show_real_recent_outs() {
  local n=${#outs[@]} s IFS=$'\x1e'
  s=$(( n > 20 ? n - 20 : 0 ))
  printf '%s' "${outs[*]:s}"
}

# scv_show_real_split 의 한 부분 — 그 함수의 지역 변수로 턴 줄 하나를 낸다. 턴에서 첫 편집 뒤 실행의 출력을 보였고(shown) 턴이
# 모델 글로 끝나면 사건 글자 끝에 q 를 붙인다.
_scv_show_real_turn_line() {
  local seq="$c_seq"
  (( shown )) && [[ "$seq" == *T ]] && seq+="q"
  printf '%s\n' "$sess"$'\t'"$c_ts"$'\t'"$seq"$'\t'"$c_msg"$'\t'"$c_lq"$'\t'"$c_last"$'\t'"$c_quote"
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
# 없음'이 없을 때. 보여 줌은 바뀐 턴에서 첫 편집 뒤 실행의 출력을 보인 뒤(또는 보이며) 묻는 확인 창(Q)이 있거나, 보인 턴(q)의 끝
# 모델 글이 질문일 때(계획 20261011-wookiya1364-show-real-classifier-rules — 실행 · 그 뒤 묻기 · 출력의 줄 · 숫자 그대로). 완료는 편집이
# 있는 턴이 모델의 글로 끝나고 그 글이 질문이 아닐 때. 수정 요구는 같은 세션에서 완료 보고 뒤 처음으로 모델이 답한 사람 메시지만
# 본다. 줄은 모으지 않고 바로 내보낸다.
scv_show_real_classify() {
  local turns="${1:-}" tab=$'\t' line sess ts seq msg lq last rest
  local edited changed shown fin corr asks tail_ask tq c_only prev_fin=0 prev_sess=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    sess="${line%%"$tab"*}"; rest="${line#*"$tab"}"
    ts="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    seq="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    msg="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    lq="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"; last="${rest%%"$tab"*}"
    [[ "$sess" == "$prev_sess" ]] || { prev_fin=0; prev_sess="$sess"; }
    [[ -n "$seq" ]] || continue
    tq=0; [[ "$seq" == *q ]] && { tq=1; seq="${seq%q}"; }
    edited=0; [[ "$seq" == *E* ]] && edited=1
    tail_ask=0
    if [[ "$seq" == *T && -n "$last" ]]; then
      tail_ask="$(scv_asks_in_text "$(scv_answer_body "$(scv_show_real_lines "$last")")")"
      [[ "$tail_ask" == "1" ]] || tail_ask=0
    fi
    changed=$edited
    (( edited )) && [[ "$seq" == *T && "$(scv_show_real_is_nochange "$last")" == "1" ]] && changed=0
    c_only="${seq//[^CK]/}"; asks=$(( ${#c_only} + tail_ask ))
    shown=0
    if (( changed )); then
      [[ "$seq" == *Q* ]] && shown=1
      (( tail_ask && tq )) && shown=1
    fi
    fin=0; (( edited && ! tail_ask )) && [[ "$seq" == *T ]] && fin=1
    corr=0
    (( prev_fin )) && corr="$(scv_show_real_is_correction "$msg")"
    printf '%s\n' "$sess$tab$ts$tab$changed$tab$shown$tab$fin$tab$corr$tab$asks"
    prev_fin=$fin
  done <<< "$turns"
  return 0
}

# ---------------------------------------------------------------- 실사용 보고 — 판정자 단계 (계획 20261011-wookiya1364-show-real-classifier-hybrid)
# 규칙 단계가 정하지 못하는 애매한 턴만 판정자(호스트의 새 모델 — 래퍼가 준 명령)에게 묻는다. 순서:
#   scv_show_real_pick → scv_show_real_excerpts → scv_show_real_keys → scv_show_real_lookup(저장된 답)
#   → [남은 턴 20개씩] scv_show_real_judge_prompt → 판정자(효과) → scv_show_real_judge_parse → scv_show_real_zip
#   → scv_show_real_merge(분류된 턴 줄에 합침) · scv_show_real_judge_count(판정자 몫)
# 판정자에게는 애매한 턴의 끝 글 마지막 1,500자와 보인 출력 줄 하나만 간다 — 턴 전체 · 다른 턴 · 사람 메시지는 가지 않는다.

# @pure
# <사람 턴 줄들(scv_show_real_split)> <지역 오프셋(분)> <켜기 전 "시작 끝"> <켠 뒤 "시작 끝"> → 애매한 턴마다
#   "<세션><탭><시각><탭><기간 b|a><탭><보인 출력 줄><탭><마지막 글(\x1e 줄바꿈)>".
# 애매한 턴: 두 기간 중 하나에 든 바뀐 턴 가운데 첫 편집 뒤 실행의 출력을 인용해 보였고(q), 그 뒤 묻는 확인 창이 없고(Q 없음),
# 끝 글이 질문이 아닌 턴 — 규칙 단계(scv_show_real_classify)가 '보여 주지 않음'으로 센 턴 가운데 뜻을 읽어야 갈리는 턴이다
# (예: 결과를 보인 뒤 '리뷰 부탁드립니다'로 끝남). 기간 밖의 턴은 묻지 않는다.
scv_show_real_pick() {
  local turns="${1:-}" off="${2:-0}" br="${3:-}" ar="${4:-}" tab=$'\t' line sess ts seq last quote rest d p bf bt af at
  bf="${br%% *}"; bt="${br##* }"; af="${ar%% *}"; at="${ar##* }"
  [[ "$bf$bt" =~ ^[0-9]{16}$ ]] || { bf=""; bt=""; }
  [[ "$af$at" =~ ^[0-9]{16}$ ]] || { af=""; at=""; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    sess="${line%%"$tab"*}"; rest="${line#*"$tab"}"
    ts="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    seq="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    rest="${rest#*"$tab"}"; rest="${rest#*"$tab"}"
    last="${rest%%"$tab"*}"; quote=""; [[ "$rest" == *"$tab"* ]] && quote="${rest#*"$tab"}"
    [[ "$seq" == *E*Tq && "$seq" != *Q* && -n "$last" && -n "$quote" ]] || continue
    [[ "$(scv_show_real_is_nochange "$last")" == "1" ]] && continue
    [[ "$(scv_asks_in_text "$(scv_answer_body "$(scv_show_real_lines "$last")")")" == "1" ]] && continue
    d="$(scv_show_real_local_date "$ts" "$off")"
    [[ -n "$d" ]] || continue
    p=""
    if [[ -n "$bf" ]] && (( 10#$d >= 10#$bf && 10#$d <= 10#$bt )); then p=b
    elif [[ -n "$af" ]] && (( 10#$d >= 10#$af && 10#$d <= 10#$at )); then p=a
    fi
    [[ -n "$p" ]] || continue
    printf '%s\n' "$sess$tab$ts$tab$p$tab$quote$tab$last"
  done <<< "$turns"
  return 0
}

# @deterministic
# <애매한 턴 줄들(scv_show_real_pick)> → "<세션><탭><시각><탭><기간><탭><발췌(\x1e 줄바꿈)>". 발췌는 보인 출력 줄과 끝 글의 마지막
# 1,500자(글자 단위 — jq 에서 자른다) — 묻는 말은 끝에 있다. 끝 글에서 '=== Excerpt' 로 시작하는 줄은 '== Excerpt' 로 바꿔 질문의
# 구분선을 흉내 내지 못하게 한다. 줄마다 jq 인자로 넘긴다 — jq 1.6 은 원문 그대로 읽기(-R)에서 4,096바이트
# 경계에 걸친 여러 바이트 글자를 깨뜨린다(2026-10-11 확인).
scv_show_real_excerpts() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    jq -nr --arg l "$line" '
      $l | split("\t") as $f
      | ($f[4] // "" | split("\u001e") | join("\n")) as $t
      | ($t | if (.[1500:] | length) != 0 then .[-1500:] else . end
         | split("\n") | map(if startswith("=== Excerpt") then "== Excerpt" + .[11:] else . end) | join("\n")) as $tail
      | ("[Shown output] " + ($f[3] // "") + "\n[Final message]\n" + $tail) as $x
      | "\($f[0])\t\($f[1])\t\($f[2])\t\($x | split("\t") | join(" ") | split("\r") | join("") | split("\n") | join("\u001e"))"'
  done <<< "${1:-}"
  return 0
}

# @deterministic
# <글> → SHA-256 16진(sha256sum 또는 shasum -a 256 — 같은 값). 둘 다 없으면 cksum 의 수(그 기계 안에서만 같은 값).
scv_show_real_hash() {
  local h
  if command -v sha256sum >/dev/null 2>&1; then h="$(printf '%s' "${1:-}" | sha256sum)"
  elif command -v shasum >/dev/null 2>&1; then h="$(printf '%s' "${1:-}" | shasum -a 256)"
  else h="$(printf '%s' "${1:-}" | cksum)"
  fi
  printf '%s' "${h%% *}"
}

# @deterministic
# <발췌 줄들(scv_show_real_excerpts)> → 줄마다 앞에 "<열쇠><탭>". 열쇠는 (세션 파일 이름 · 시각 · 발췌)의 해시 — 끝 글이나 보인
# 출력이 바뀌면 열쇠가 달라져 다시 묻는다. 세션 이름의 '<폴더 번호>/' 앞부분은 빼고 쓴다(보고마다 폴더 순서가 달라도 같은 열쇠).
scv_show_real_keys() {
  local tab=$'\t' line sess rest ts
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    sess="${line%%"$tab"*}"; rest="${line#*"$tab"}"
    ts="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    printf '%s\t%s\n' "$(scv_show_real_hash "${sess#*/}$tab$ts$tab${rest#*"$tab"}")" "$line"
  done <<< "${1:-}"
  return 0
}

# @deterministic
# <열쇠 붙은 발췌 줄들(scv_show_real_keys)> <저장된 답 "<열쇠><탭><yes|no>" 줄들> → 줄마다
#   저장된 답이 있으면 "A<탭><열쇠><탭><세션><탭><시각><탭><기간><탭><yes|no>",
#   없으면 "Q<탭><열쇠><탭><세션><탭><시각><탭><기간><탭><발췌>"(물을 턴). 같은 열쇠가 여러 번 저장돼 있으면 마지막 답.
scv_show_real_lookup() {
  [[ -n "${1:-}" ]] || return 0
  printf '%s\n\035\n%s\n' "${2:-}" "$1" | LC_ALL=C awk -F '\t' '
    $0 == "\035" && !part { part = 1; next }
    !part { if (NF == 2 && ($2 == "yes" || $2 == "no")) a[$1] = $2; next }
    NF != 0 { if ($1 in a) print "A\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" a[$1]; else print "Q\t" $0 }'
}

# @deterministic
# <물을 턴 줄들("Q<탭>…", 20개까지)> → 판정자에게 보낼 글 하나. 묻는 뜻은 정답 매기기의 질문과 같다(실제 결과를 보인 뒤 계속할지 ·
# 고칠지를 물었나 — '물음'의 정의 포함) — 애매한 턴이라 결과는 이미 보였으니 끝 글의 묻는 말만 가르면 된다. 답은 발췌 순서대로
# yes · no 의 JSON 배열. jq 인자로 넘기지 않고 셸에서 잇는다 — 묶음이 커도 인자 길이 한도(리눅스 한 인자 128KB)에 걸리지 않게.
scv_show_real_judge_prompt() {
  local tab=$'\t' line n i
  local -a xs=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] && xs+=("${line##*"$tab"}")
  done <<< "${1:-}"
  n=${#xs[@]}
  (( n )) || return 0
  printf '%s\n\n' "You judge excerpts from an AI coding assistant's work log. Answer with one JSON array only."
  printf '%s\n\n' "Below are $n excerpts. Each comes from one turn in which the assistant edited files, ran something, and showed part of the run's actual output to the user. [Shown output] is an output line the assistant showed; [Final message] is the end of the assistant's last message in that turn."
  printf '%s\n\n' "Question: in each turn, after showing the actual result, did the assistant ask the user whether to continue or what to fix? Asking can be a choice window or a text question. Even without a question mark, it counts as asking when the assistant asks the user to look at this result and say whether to continue or what to change (e.g. \"리뷰 부탁드립니다\" / \"Please review\", \"고칠 점이 있으면 알려 주세요\" / \"Let me know anything to fix\", \"검토 후 ship it 이면 끝냅니다\" / \"If it is a ship it after review, I am done\"). It does not count when the assistant only reports that the work is done, only says it is waiting for someone's review, announces what it will do next, or offers a separate follow-up task (e.g. \"다음 작업으로 계획할지는 말씀해 주시면 됩니다\" / \"Tell me if you want these planned as the next task\")."
  printf '%s\n\n' "Answer with one JSON array of $n items only — \"yes\" or \"no\" for each excerpt, in order."
  for (( i = 0; i != n; i++ )); do
    (( i )) && printf '\n\n'
    printf '=== Excerpt %s ===\n' "$(( i + 1 ))"
    printf '%s' "${xs[i]}" | tr '\036' '\n'
  done
  printf '\n'
}

# @deterministic
# <판정자 답 글> <발췌 수 n> → n 줄(yes · no). 답 글에서 길이가 n 이고 항목이 모두 yes · no 인 JSON 배열(안에 대괄호가 없는 것,
# 대소문자 · 앞뒤 공백 무관)을 찾아, 하나뿐이거나 모두 같을 때만 그 답. 설명 속의 다른 괄호('[1]' 같은)는 건너뛴다. 아니면 빈 값 —
# 깨진 응답(배열이 없음 · 수가 안 맞음 · 서로 다른 배열 · 한도 안내)은 그 묶음 전체를 판정 못 한 턴으로 세고 저장하지 않는다.
scv_show_real_judge_parse() {
  [[ "${2:-}" =~ ^[1-9][0-9]*$ && -n "${1:-}" ]] || return 0
  jq -nr --arg s "$1" --argjson n "$2" '
    [$s | scan("\\[[^\\[\\]]*\\]") | (fromjson? // empty) | select(type == "array" and length == $n)
     | map(if type == "string" then ascii_downcase | gsub("^\\s+|\\s+$"; "") else "" end)
     | select(all(.[]; . == "yes" or . == "no"))] as $ok
    | if ($ok | length) != 0 and ($ok | unique | length) == 1 then $ok[0][] else empty end' 2>/dev/null
  return 0
}

# @pure
# <물을 턴 줄들("Q<탭>…")> <답 줄들(scv_show_real_judge_parse — 빈 값이면 판정 못 함)> → 턴마다
#   "A<탭><열쇠><탭><세션><탭><시각><탭><기간><탭><yes|no|unjudged>". 답 수가 물은 턴 수와 다르면 모두 unjudged.
scv_show_real_zip() {
  local tab=$'\t' nl=$'\n' line rest ans="${2:-}" n=0 m=0 a
  local -a qs=() as=()
  while IFS= read -r line || [[ -n "$line" ]]; do [[ -n "$line" ]] && qs+=("$line"); done <<< "${1:-}"
  while IFS= read -r line || [[ -n "$line" ]]; do [[ -n "$line" ]] && as+=("$line"); done <<< "$ans"
  n=${#qs[@]}; m=${#as[@]}
  for (( i = 0; i != n; i++ )); do
    rest="${qs[i]#Q"$tab"}"
    a=unjudged; (( m == n )) && a="${as[i]}"
    printf 'A\t%s\n' "${rest%"$tab"*}$tab$a"
  done
  return 0
}

# @deterministic
# <분류된 턴 줄들(scv_show_real_classify)> <답 줄들("A<탭>…")> → 분류된 턴 줄들. 답이 yes 인 턴의 보여 줌 칸만 1 로 바꾼다 — 다른
# 칸 · 다른 턴은 그대로(no · unjudged 인 턴은 규칙 단계 값 0 그대로).
scv_show_real_merge() {
  printf '%s\n\035\n%s\n' "${2:-}" "${1:-}" | LC_ALL=C awk -F '\t' -v OFS='\t' '
    $0 == "\035" && !part { part = 1; next }
    !part { if ($1 == "A" && $6 == "yes") y[$3 "\t" $4] = 1; next }
    NF == 0 { next }
    { if (($1 "\t" $2) in y) $4 = 1; print }'
}

# @pure
# <답 줄들("A<탭>…")> → 두 줄 "before<탭><판정자가 정한 턴><탭><그중 보여 줌><탭><판정 못 한 턴>" · "after<탭>…".
scv_show_real_judge_count() {
  local tab=$'\t' line a p bj=0 by=0 bu=0 aj=0 ay=0 au=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == A"$tab"* ]] || continue
    a="${line##*"$tab"}"; p="${line%"$tab"*}"; p="${p##*"$tab"}"
    case "$p.$a" in
      b.yes) bj=$(( bj + 1 )); by=$(( by + 1 )) ;;
      b.no) bj=$(( bj + 1 )) ;;
      b.unjudged) bu=$(( bu + 1 )) ;;
      a.yes) aj=$(( aj + 1 )); ay=$(( ay + 1 )) ;;
      a.no) aj=$(( aj + 1 )) ;;
      a.unjudged) au=$(( au + 1 )) ;;
    esac
  done <<< "${1:-}"
  printf 'before\t%s\t%s\t%s\nafter\t%s\t%s\t%s\n' "$bj" "$by" "$bu" "$aj" "$ay" "$au"
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
# [<판정자 몫 두 줄(scv_show_real_judge_count)>] → 표 한 장과 범례. 숫자와 날짜만 낸다 — 대화 내용 · 경로 · 세션 이름은 내지 않는다.
# 판정자 몫이 주어지면 규칙만으로 못 가린 턴 가운데 판정자가 정한 턴(그중 보여 줌) · 판정 못 한 턴을 기간마다 한 줄로 더한다.
scv_show_real_render() {
  local counts="${1:-}" lang="${2:-}" braw="${3:-}" araw="${4:-}" nf="${5:-0}" nu="${6:-0}" judge="${7:-}" tab=$'\t' line k rest
  local n t c w r q row1="" row2="" h1 h2 l1 l2 l3 l4 l5 l6="" l7="" l8="" title pb pa jl ju jn
  local bj=0 by=0 bu=0 aj=0 ay=0 au=0
  case "$lang" in
    [Kk]orean|ko|KO|한국어)
      title="실체 보여 주기 — 실사용 보고 (켜기 전 · 켠 뒤)"
      h1="| 기간 | 세션 | 바뀐 턴 | (a) 보여 줌 | (b) 수정/세션 | (c) 확인/세션 |"
      pb="켜기 전"; pa="켠 뒤"
      l1="(a) 결과물이 바뀐 턴 중 '편집 → 실행 → 그 결과를 보이고 계속 · 고칠 점을 물음'이 있는 턴의 비율 (괄호: 턴 수)"
      l2="(b) 완료 보고 뒤 처음 답한 사람 메시지가 고쳐 달라는 말인 수 ÷ 세션 (괄호: 합)"
      l3="(c) 확인 창 + 턴을 끝낸 글 질문 ÷ 세션 (괄호: 합)"
      l4="숫자는 방향을 보는 용도다 — 두 기간은 일의 종류가 다를 수 있다. 세는 기준: core/scripts/lib/show-real.sh 머리말."
      l5="읽은 세션 기록 파일: ${nf}개"
      (( nu == 0 )) || l6="대화 항목이 없거나 읽지 못한 파일(권한 · 기록 모양): ${nu}개 — 숫자에 들지 않았다" ;;
    [Jj]apanese|ja|JA|日本語)
      title="実物を見せる — 実利用レポート（有効化前・後）"
      h1="| 期間 | セッション | 変更ターン | (a) 見せた | (b) 修正/セッション | (c) 確認/セッション |"
      pb="有効化前"; pa="有効化後"
      l1="(a) 成果物が変わったターンのうち「編集 → 実行 → その結果を見せて続けるか・直す点を尋ねる」があるターンの割合（括弧: ターン数）"
      l2="(b) 完了報告の後に最初に応答した人のメッセージが修正の依頼である数 ÷ セッション（括弧: 合計）"
      l3="(c) 確認ウィンドウ + ターンを終えた文章の質問 ÷ セッション（括弧: 合計）"
      l4="数字は方向を見るためのもの — 二つの期間は仕事の種類が違いうる。数え方: core/scripts/lib/show-real.sh の冒頭。"
      l5="読んだセッション記録ファイル: ${nf}件"
      (( nu == 0 )) || l6="会話項目がないか読めなかったファイル（権限・記録の形）: ${nu}件 — 数字に含まれていない" ;;
    *)
      title="Show the real thing — real-use report (before · after)"
      h1="| Period | Sessions | Changed turns | (a) Shown | (b) Fixes/session | (c) Asks/session |"
      pb="Before"; pa="After"
      l1="(a) Share of changed turns with 'edit → run → the result shown, then a continue-or-fix ask' (in brackets: turns)"
      l2="(b) First answered person message after a completion report that asks for a fix, per session (in brackets: total)"
      l3="(c) Choice windows + turn-ending text questions, per session (in brackets: total)"
      l4="The numbers show direction only — the two periods may hold different kinds of work. Counting rules: header of core/scripts/lib/show-real.sh."
      l5="Session record files read: ${nf}"
      (( nu == 0 )) || l6="Files with no conversation entries or not readable (permission · record shape): ${nu} — not in the numbers" ;;
  esac
  h2="|---|---|---|---|---|---|"
  if [[ -n "$judge" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      k="${line%%"$tab"*}"; rest="${line#*"$tab"}"
      jl="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"; jn="${rest%%"$tab"*}"; ju="${rest#*"$tab"}"
      [[ "$jl$jn$ju" =~ ^[0-9]+$ ]] || continue
      case "$k" in
        before) bj="$jl"; by="$jn"; bu="$ju" ;;
        after)  aj="$jl"; ay="$jn"; au="$ju" ;;
      esac
    done <<< "$judge"
    case "$lang" in
      [Kk]orean|ko|KO|한국어)
        l7="(a) 의 판정자 몫 — 규칙만으로 못 가린 턴(결과를 보인 뒤 물음표 없이 끝남) 중 판정자가 정한 턴: $pb $bj(보여 줌 $by) · $pa $aj(보여 줌 $ay)"
        l8="판정 못 한 턴(판정자 명령 없음 · 실패 · 깨진 답 — 보여 주지 않음으로 셈): $pb $bu · $pa $au" ;;
      [Jj]apanese|ja|JA|日本語)
        l7="(a) の判定者分 — ルールだけでは決められなかったターン（結果を見せた後、疑問符なしで終わった）のうち判定者が決めたもの: $pb $bj（見せた $by）・$pa $aj（見せた $ay）"
        l8="判定できなかったターン（判定コマンドなし・失敗・壊れた応答 — 見せていないとして数えた）: $pb $bu・$pa $au" ;;
      *)
        l7="(a) judge share — turns the rules alone could not settle (result shown, ended without a question mark) decided by the judge: $pb $bj (shown $by) · $pa $aj (shown $ay)"
        l8="Turns not judged (no judge command · a failed call · a broken answer — counted as not shown): $pb $bu · $pa $au" ;;
    esac
  fi
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
  printf '%s\n' "$title" "" "$h1" "$h2" "$row1" "$row2" "" "$l1" "$l2" "$l3"
  [[ -z "$l7" ]] || printf '%s\n' "$l7" "$l8"
  printf '%s\n' "$l4" "$l5"
  [[ -z "$l6" ]] || printf '%s\n' "$l6"
}
