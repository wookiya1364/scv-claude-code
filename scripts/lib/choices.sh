#!/usr/bin/env bash
# lib/choices.sh — 고르게 할 때 규칙(contracts/choices.md)의 순수부. 효과(호스트 설정 읽기 · 경고 쓰기)는 scripts/choice-gate.sh.
#
#   scv_choice_line <도구 이름>                → 매 턴 안내 한 줄 | 빈 값(도구가 없으면)
#   scv_answer_body <답>                       → 코드 블록과 인용 줄(다시 쓴 요청 등)을 뺀 본문
#   scv_asks_in_text <본문>                    → 1(글로 묻거나 번호로 고르게 하면서 끝남) | 0
#   scv_choice_gate <묻나> <도구 이름> <계속 중> → ok | block | warn
#   scv_choice_reason <도구 이름>              → 막는 이유 한 줄
#   scv_choice_off_when <조건 이름=값> <지금 값> → 1(이 실행에는 선택지 도구가 없다) | 0
#
# 꺾쇠 글자는 쓰지 않는다 — 순수성 검사가 리다이렉션으로 본다(인용 표시는 \x3e 로 만든다).

# @pure
# <도구 이름> → 매 턴 안내 한 줄. 도구가 없으면 아무것도 내지 않는다(이 기능 전과 같은 출력).
scv_choice_line() {
  local tool="${1:-}"
  [[ -n "$tool" ]] || return 0
  # 매 턴 실리는 줄 — 래퍼(요구 항목 블록 약 1.5KB)와 함께 매 턴 스택 상한(test-help-budget T12, 12,000B) 안. 요지만, 전문은 규칙 문서.
  printf '%s\n' "[SCV choices] Ask the user's decisions with $tool, never in text: recommended option first; each option says how it avoids its own problems; over 4 questions, consecutive calls; over 4 options, two steps; names, suggested values; cancelled, stop. A turn that ends asking in text is blocked (contracts/choices.md)."
}

# @pure
# <답> → 코드 블록(``` 울타리 안)과 인용 줄을 뺀 본문. 인용 속 물음표(다시 쓴 요청 등)는 질문이 아니다.
scv_answer_body() {
  local text="${1:-}" line t fence=0 q=$'\x3e' out=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    t="${line#"${line%%[![:space:]]*}"}"
    if [[ "$t" == '```'* ]]; then fence=$(( 1 - fence )); continue; fi
    (( fence )) && continue
    [[ "${t:0:1}" == "$q" ]] && continue
    out+="$line"$'\n'
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# <본문> → 1 | 0. 답이 사용자에게 고르게 하거나 묻는 글로 끝나는가:
#   (a) 요청하는 말(끝 두 문단에서) — 번호로 답해 달라 · 골라 / 정해 / 선택해 달라 · "'다 추천대로'라고"(한 · 영 · 일). 요청형만 본다 —
#       "다 추천대로 반영했습니다" 같은 평서문은 잡지 않는다.
#   (b) 끝 두 문단에 결정 표 — 머리에 질문 · 추천 칸이 있고, 고른 것 · 답 · 결과 칸은 없다(되짚는 표는 정보다). 표 뒤에 안내
#       문단이 한 번 더 붙어도 잡는다(설치본 실측 2026-10-02 — "정해 주실 것" 줄 · 결정 표 · "…정해지면 …" 안내).
#   (c) 실제 끝 줄이 물음표로 끝남 — 끝에 붙은 보기 목록(1. · - · ①)은 건너뛰고 그 앞 줄을 본다. 끝의 괄호 덧붙임
#       "(추천: 예)" · 굵게 · 따옴표 · 이모티콘은 걷어 내고 본다. 걷는 것은 글자 그대로의 꼬리라 로캘과 무관하다.
#       표의 행으로 끝나는 답은 (c) 를 보지 않는다 — 표 안의 물음표는 정보다.
#   (d) 끝 문단의 줄(표 줄 제외, 끝 40줄 — 목록 줄도 본다) 가운데 사용자에게 묻는 물음표가 있는 줄(scv_choice_q_after)의 뒤 글 —
#       그 줄의 나머지와 아래 줄들 — 이 묻는 꼴이다(scv_choice_q_asks): "…할까요? 추천은 …입니다." · "다음 행동: …할까요? 추천은 예." /
#       "검증 기준: …" · "…할까요?" / "추천은 A." · "Should I …? CI is green. Let me know." 앞 문단이 그런 물음표로 끝나고 빈 줄 뒤
#       끝 문단이 이어지는 꼴("…할까요?" / 빈 줄 / "추천은 …")도 본다.
#   (a) 와 (d) 는 실제 답 모음(로컬 원본 230턴)에서 놓친 모양으로 넓혔다 — 질문 뒤 추천 문장, "답해 주시면 됩니다",
#       "할지 알려 주세요", "라고 해 주세요", 한 줄 보기 목록 "[1] … / [2] …" (2026-10-01 실측).
# 본문 중간의 물음표, 평서문으로 끝나는 답, 정보 표, "필요하면 말씀해 주세요" · "언제든지 알려 주세요" 같은 제안 · 맺음 인사는
# 묻는 것이 아니다. 빈 줄(문단 경계)은 ASCII 공백만으로 이뤄진 줄이다 — 로캘에 따라 문단이 달라지지 않게.
scv_asks_in_text() {
  local body="${1:-}" line t cue hit=0 nc=0 n=0 i last="" para="" ppara="" reset=0 prev pre after="" np=0 pq="" rest="" j k
  local -a PL=()
  local item_re='^([-*+]|[0-9]+[.)]|\([0-9]+\)|\[[0-9]+\]|①|②|③|④|⑤|⑥|⑦|⑧|⑨|⑩)[[:space:]]'
  local -a L=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    if _scv_choice_blank "$line"; then reset=1; continue; fi
    if (( reset )); then ppara="$para"; para=""; reset=0; fi
    para+="$line"$'\n'
    L[n]="$line"; n=$((n + 1))
  done <<< "$body"
  (( n )) || { printf '0'; return 0; }
  i=$((n - 1))
  while (( i > 0 )); do
    t="${L[i]#"${L[i]%%[![:space:]]*}"}"
    [[ "$t" =~ $item_re ]] || break
    i=$((i - 1))
  done
  last="${L[i]}"
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  for cue in "번호로 답해 주세요" "번호로 답해주세요" "번호로 답해 줘" "번호만 알려 주세요" "번호만 알려주세요" \
             "번호로 알려 주세요" "번호로 알려주세요" "추천대로'라고" "추천대로라고" "골라 주세요" "골라주세요" \
             "정해 주세요" "정해주세요" "선택해 주세요" "선택해주세요" "결정해 주세요" "결정해주세요" \
             "answer by number" "reply with the number" "answer with the number" "reply with a number" \
             "let me know which" "which one would you" "which would you prefer" "which do you prefer" \
             "please choose" "please pick" "please select" "please decide" \
             "番号でお答え" "番号で答えて" "番号でご回答" "選んでください" "決めてください" "お選びください" \
             "답해 주시면" "답해주시면" "답해 주세요" "답해주세요" "라고 해 주세요" "라고 해주세요" \
             "지 알려 주세요" "지 알려주세요" "지 알려 주시면" "지 알려주시면" "지 말씀해 주세요" "지 말씀해주세요" \
             "let me know whether" "tell me which" "tell me whether" "か教えてください" "とお答えください"; do
    if [[ "$para" == *"$cue"* || "$ppara" == *"$cue"* || "$last" == *"$cue"* ]]; then
      # "언제든지 알려 주세요" · "얼마든지 말씀해 주세요" 는 맺음 인사다 — "…할지 · …인지 알려 주세요" 만 묻는 말이다
      if [[ "$cue" == "지 "* ]]; then
        _scv_choice_cue_real "$para" "$cue" || _scv_choice_cue_real "$ppara" "$cue" || _scv_choice_cue_real "$last" "$cue" || continue
      fi
      hit=1; break
    fi
  done
  if (( ! hit )); then
    while IFS= read -r line || [[ -n "$line" ]]; do
      t="${line#"${line%%[![:space:]]*}"}"
      [[ "${t:0:1}" == "|" ]] || continue
      if [[ "$t" == *"질문"* || "$t" == *"question"* || "$t" == *"質問"* ]] \
         && [[ "$t" == *"추천"* || "$t" == *"recommend"* || "$t" == *"推奨"* ]] \
         && [[ "$t" != *"고른"* && "$t" != *"답"* && "$t" != *"결과"* && "$t" != *"chosen"* && "$t" != *"answer"* \
               && "$t" != *"result"* && "$t" != *"選んだ"* && "$t" != *"結果"* ]]; then hit=1; break; fi
    done <<< "$ppara"$'\n'"$para"
  fi
  (( nc )) || shopt -u nocasematch
  if (( ! hit )); then
    t="${last#"${last%%[![:space:]]*}"}"
    if [[ "${t:0:1}" != "|" ]]; then
      prev=""
      while [[ "$t" != "$prev" ]]; do
        prev="$t"
        t="${t%"${t##*[![:space:]]}"}"
        case "$t" in
          *':-)') t="${t%???}" ;;
          *'**'|*'__'|*':)'|*';)'|*'^^') t="${t%??}" ;;
          *'*'|*'_'|*'"'|*"'"|*'`'|*'~'|*'!'|*'.') t="${t%?}" ;;
          *'ㅎㅎ') t="${t%'ㅎㅎ'}" ;;
          *'ㅋㅋ') t="${t%'ㅋㅋ'}" ;;
          *'」') t="${t%'」'}" ;;
          *'』') t="${t%'』'}" ;;
          *'”') t="${t%'”'}" ;;
          *'’') t="${t%'’'}" ;;
          *'🙂') t="${t%'🙂'}" ;;
          *'😊') t="${t%'😊'}" ;;
          *'😀') t="${t%'😀'}" ;;
          *'🙏') t="${t%'🙏'}" ;;
          *'👍') t="${t%'👍'}" ;;
          *')')
            if [[ "$t" == *"("* ]]; then
              pre="${t%(*}"
              if [[ "$pre" == *[![:space:]]* ]]; then t="$pre"; else t="${t#(}"; t="${t%)}"; fi
            fi ;;
        esac
      done
      case "$t" in *'?'|*'？') hit=1 ;; esac
    fi
  fi
  if (( ! hit )); then
    while IFS= read -r line || [[ -n "$line" ]]; do
      t="${line#"${line%%[![:space:]]*}"}"
      [[ "${t:0:1}" == "|" ]] && continue
      _scv_choice_blank "$t" && continue
      PL[np]="$t"; np=$((np + 1))
    done <<< "$para"
    pq=""
    while IFS= read -r line || [[ -n "$line" ]]; do
      t="${line#"${line%%[![:space:]]*}"}"
      [[ "${t:0:1}" == "|" ]] && continue
      _scv_choice_blank "$t" && continue
      pq="$t"
    done <<< "$ppara"
    k=$np; j=0; rest=""
    while (( k > 0 && j < 40 )); do
      k=$((k - 1)); j=$((j + 1)); line="${PL[k]}"
      if [[ "$line" == *'?'* || "$line" == *'？'* ]] && after="$(scv_choice_q_after "$line")"; then
        [[ "$(scv_choice_q_asks "$after$rest")" == 1 ]] && { hit=1; break; }
      fi
      rest=$'\n'"$line$rest"
    done
    if (( ! hit && k == 0 )) && [[ "$pq" == *'?'* || "$pq" == *'？'* ]] && after="$(scv_choice_q_after "$pq")" \
       && ! _scv_choice_has_text "$after"; then
      [[ "$(scv_choice_q_asks "$rest")" == 1 ]] && hit=1
    fi
  fi
  printf '%s' "$hit"
}

# @pure
# <묻나 0|1> <도구 이름> <이미 계속 중 0|1> → ok | block | warn. 도구가 없으면 늘 ok(이 기능 전과 같다).
# 이미 계속 중이면 막지 않는다 — 같은 턴 한 번, 다음 턴 경고로 넘긴다.
scv_choice_gate() {
  local asks="${1:-0}" tool="${2:-}" active="${3:-0}"
  [[ -n "$tool" && "$asks" == "1" ]] || { printf 'ok'; return 0; }
  if [[ "$active" == "1" ]]; then printf 'warn'; else printf 'block'; fi
}

# @pure
# <도구 이름> → 막는 이유 한 줄 — 모델이 이것만 읽고 바로 다시 물을 수 있게 규칙 요지를 담는다.
scv_choice_reason() {
  local tool="${1:-the choice tool}"
  printf '%s' "[SCV 선택지] 사용자에게 고르게 하거나 묻는 글로 턴을 끝냈다 — $tool 로 다시 물어라: 결정 하나에 질문 하나, 첫 보기가 추천, 보기마다 그 보기가 부를 문제를 막는 방법, 질문이 4개를 넘으면 중요한 것부터 나눠 연달아, 보기가 4개를 넘으면 두 단계로. 고를 것이 아니면 질문 없이 끝내라(contracts/choices.md)."
}

# @pure
# <조건 "이름=값"> <지금 그 이름의 환경 값> → 1 | 0. 호스트가 선택지 도구를 빼는 실행(사람이 답할 수 없는 헤드리스 등)을
# 호스트 설정의 조건으로 알아본다 — 조건이 비었거나 모양이 틀리면 0(지금처럼 도구가 있다고 본다).
scv_choice_off_when() {
  local spec="${1:-}" now="${2:-}" name want
  [[ "$spec" == *=* ]] || { printf '0'; return 0; }
  name="${spec%%=*}"; want="${spec#*=}"
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -n "$want" ]] || { printf '0'; return 0; }
  [[ "$now" == "$want" ]] && printf '1' || printf '0'
}

# @pure
# <줄> → 0(빈 줄: ASCII 공백 · NBSP · 전각 공백뿐) | 1. 로캘과 무관하다 — [[:space:]] 는 로캘마다 NBSP 를 다르게 본다.
_scv_choice_blank() {
  local t="${1:-}" k=0
  [[ "$t" == *[!$' \t\r\v\f']* ]] || return 0
  while (( k < 16 )); do
    k=$((k + 1))
    case "$t" in
      '') return 0 ;;
      [$' \t\r\v\f']*) t="${t#?}" ;;
      $'\xc2\xa0'*) t="${t#$'\xc2\xa0'}" ;;
      '　'*) t="${t#'　'}" ;;
      $'\xe2\x80\x82'*) t="${t#$'\xe2\x80\x82'}" ;;
      $'\xe2\x80\x83'*) t="${t#$'\xe2\x80\x83'}" ;;
      $'\xe2\x80\x89'*) t="${t#$'\xe2\x80\x89'}" ;;
      $'\xe2\x80\x8b'*) t="${t#$'\xe2\x80\x8b'}" ;;
      *) return 1 ;;
    esac
  done
  return 1
}

# @pure
# <글> → 0(공백 · 굵게 · 닫는 괄호 말고 글이 있다) | 1.
_scv_choice_has_text() {
  local t="${1:-}"
  [[ "$t" == *[!$' \t\r\v\f*_)']* ]]
}

# @pure
# <글> <요청 말> → 0(맺음 인사가 아닌 요청이 한 군데라도 있다) | 1. "언제든지 · 얼마든지 알려 주세요" 처럼 "든" · "든지" 바로
# 뒤에 오는 것은 맺음 인사다 — 자리마다 본다(한 글에 진짜 요청과 맺음 인사가 같이 있어도 요청을 놓치지 않게).
_scv_choice_cue_real() {
  local s="${1:-}" cue="${2:-}" pre k=0
  while [[ "$s" == *"$cue"* ]] && (( k < 8 )); do
    k=$((k + 1)); pre="${s%%"$cue"*}"
    [[ "$pre" == *든 || "$pre" == *든지 || "$pre" == *"든지 " ]] || return 0
    s="${s#*"$cue"}"
  done
  return 1
}

# @pure
# <줄> → 그 줄에서 사용자에게 묻는 마지막 '문장 끝 물음표' 뒤의 글. 없으면 아무것도 내지 않고 1.
#   줄은 끝 2000바이트만 본다(바이트로 자른다 — 로캘과 무관, 큰 글에서 패턴 자르기가 제곱으로 느려지지 않게).
#   건너뛰는 물음표: 코드 조각(`…`) 안(앞의 백틱이 홀수), 뒤가 닫는 따옴표(옮겨 적은 질문), 뒤가 공백 · 줄 끝 · 괄호 · 굵게 ·
#   NBSP · 전각 공백이 아닌 것(주소의 ?id=), 반말 · 혼잣말 물음("…나?" · "…까?" — "…습니까?" 는 존댓말, "…のか？"),
#   "왜 · Why · なぜ" 로 여는 물음(스스로 묻고 답하는 설명). 전각 물음표(？)는 뒤에 띄어 쓰지 않아도 문장 끝이다.
scv_choice_q_after() {
  local x="${1:-}" head after k=0 f1 f2 a1 a2 q c qs
  local -a bt=()
  # 500글자 이하는 어느 로캘이든 2000바이트 이하(UTF-8 은 글자당 4바이트까지) — 자를 일이 없어 하위 셸을 띄우지 않는다
  (( ${#x} > 500 )) && x="$(LC_ALL=C; if (( ${#x} > 2000 )); then printf '%s' "${x: -2000}"; else printf '%s' "$x"; fi)"
  head="$x"
  while (( k < 8 )); do
    k=$((k + 1)); f1=0; f2=0; a1=""; a2=""
    [[ "$head" == *'?'* ]] && { a1="${head##*\?}"; f1=1; }
    [[ "$head" == *'？'* ]] && { a2="${head##*'？'}"; f2=1; }
    (( f1 || f2 )) || return 1
    if (( f2 )) && { (( ! f1 )) || (( ${#a2} <= ${#a1} )); }; then q='？'; head="${head%'？'*}"; else q='?'; head="${head%\?*}"; fi
    after="${x:${#head}}"; after="${after:${#q}}"
    bt=(); IFS='`' read -r -d '' -a bt <<<"$head" || true
    (( ${#bt[@]} % 2 == 0 )) && continue
    c="${after:0:1}"
    case "$c" in "'"|'"'|'`') continue ;; esac
    [[ "$after" == "”"* || "$after" == "’"* || "$after" == "」"* || "$after" == "』"* ]] && continue
    if [[ "$q" == '?' ]]; then
      case "$c" in ''|' '|$'\t'|')'|'('|'*'|'_') ;; *) [[ "$after" == $'\xc2\xa0'* || "$after" == '　'* ]] || continue ;; esac
    fi
    case "$head" in *니까) ;; *나|*까|*가|*지|*니|*냐|*래|*대|*のか|*だろうか|*かな) continue ;; esac
    # 물음 문장의 처음 — 앞 문장 끝 · 줄 머리 꾸밈(목록 · 굵게 · 이름표) 뒤
    qs="${head##*. }"; qs="${qs##*! }"; qs="${qs##*\? }"; qs="${qs##*。}"; qs="${qs##*: }"; qs="${qs##*：}"
    qs="${qs#"${qs%%[!$' \t*_#\x3e-']*}"}"
    case "$qs" in '왜 '*|'Why '*|'why '*|'なぜ'*|'どうして'*|'How come'*|'how come'*) continue ;; esac
    printf '%s' "$after"; return 0
  done
  return 1
}

# @pure
# <물음표 뒤 글 — 같은 줄의 나머지와 아래 줄들> → 1 | 0. 앞 2000바이트만 본다. 바로 답이 오면("네, …" · "Yes — …") 혼잣말
# 질문이라 0. 요청("알려 주세요" · "let me know" · "여쭤봅니다" …)이 조건부 제안("If you need …" · "필요하면 …" · "언제든지 …")이
# 아닌 문장에 있거나, 분명한 추천 말("추천은" · "(추천" · "I recommend" · "I'd suggest" · "おすすめは" · "권장합니다" …)이 있으면 1.
scv_choice_q_asks() {
  local a="${1:-}" t cue nc=0 hit=0 k=0 pre sen
  (( ${#a} > 500 )) && a="$(LC_ALL=C; if (( ${#a} > 2000 )); then printf '%s' "${a:0:2000}"; else printf '%s' "$a"; fi)"
  t="$a"
  while (( k < 16 )); do
    k=$((k + 1))
    case "$t" in
      [$' \t\r\v\f\n*_)']*) t="${t#?}" ;;
      $'\xc2\xa0'*) t="${t#$'\xc2\xa0'}" ;;
      '　'*) t="${t#'　'}" ;;
      *) break ;;
    esac
  done
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  for cue in "네," "네." "네!" "네:" "네 —" "네—" "예," "예." "예!" "예:" "예 —" "예—" "아니요" "아니오" "아뇨" \
             "Yes," "Yes." "Yes!" "Yes:" "Yes —" "Yes—" "Yes -" "No," "No." "No!" "No:" "No —" "No—" "No -" "はい" "いいえ"; do
    [[ "$t" == "$cue"* ]] && { (( nc )) || shopt -u nocasematch; printf '0'; return 0; }
  done
  for cue in "추천은" "추천:" "추천 :" "(추천" "（추천" "추천합니다" "를 추천" "을 추천" "제 추천" \
             "권장합니다" "를 권장" "을 권장" "권장은" "권장:" "(권장" \
             "i recommend" "i'd recommend" "i would recommend" "my recommendation" "(recommended" "recommended:" "recommendation:" \
             "i suggest" "i'd suggest" "i would suggest" "my suggestion" \
             "おすすめは" "おすすめします" "がおすすめ" "をおすすめ" "推奨は" "(推奨" "（推奨" "推奨します"; do
    [[ "$t" == *"$cue"* ]] && { hit=1; break; }
  done
  if (( ! hit )); then
    for cue in "알려 주세요" "알려주세요" "알려 주시면" "알려주시면" "말씀해 주세요" "말씀해주세요" "말씀해 주시면" "말씀해주시면" \
               "답해 주세요" "답해주세요" "여쭤" "여쭙" "let me know" "tell me" "教えてください" "お知らせください"; do
      [[ "$t" == *"$cue"* ]] || continue
      pre="${t%%"$cue"*}"
      sen="${pre##*. }"; sen="${sen##*! }"; sen="${sen##*\? }"; sen="${sen##*$'\n'}"; sen="${sen##*。}"
      case "$sen" in *"if "*|*"If "*|*필요하면*|*필요하시면*|*원하시면*|*있으면*|*언제든*|*얼마든*|*"anything else"*|*궁금한*) continue ;; esac
      hit=1; break
    done
  fi
  (( nc )) || shopt -u nocasematch
  printf '%s' "$hit"
}
