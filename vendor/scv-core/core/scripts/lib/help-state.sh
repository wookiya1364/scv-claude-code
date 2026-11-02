#!/usr/bin/env bash
# help-state.sh — "규약은 세션당 한 번" 의 상태 표식 순수부 (v0.49.0+).
#
# 왜 있나: help 규약 전체를 매 턴 다시 싣지 않고 세션에 한 번만 읽게 하려면 "다시 읽을 때"를
# 누군가 정해야 한다. 모델의 판단("컨텍스트에 안 보이면 읽어라")은 비결정적이라 쓰지 않는다.
# 대신 훅이 보는 사실 — 세션 번호가 바뀜 · 컨텍스트가 비워짐(압축·/clear·재개) · N턴이 지남 —
# 만으로 정한다. 같은 표식으로 매 턴 진단도 "바뀐 턴에만 전체, 아니면 한 줄" 이 된다.
#
# 표식 한 줄 JSON: {"session":"<id>","protocol":0|1,"turn":<n>,"diag":"<해시 앞 16자>","diag_at":"HH:MM","nonce":"<8자리 16진>"}
#   protocol 0 = 다음 help 호출 때 규약 전체를 읽어라(load), 1 = 이미 읽었다(loaded).
#   nonce (v0.50.0+) = 규약 전체를 읽은 턴에 mark 가 만든 이 세션의 규약 지문. 모델은 매 턴 대화 기록에
#   이 지문을 적고, 종료 훅이 그것을 표식과 비교한다 — 없거나 다르면 규약이 컨텍스트에서 빠진 것이므로
#   protocol=0 (다음 턴 다시 읽기). 0.49.0 표식(필드 없음)은 nonce="" 로 읽힌다.
#
# 순수: 문자열만 받아 문자열만 낸다. 파일 읽기·쓰기는 scripts/help-state.sh (효과부).
# 필드 구분자는 \x1f (단위 구분자) — 탭은 IFS 공백류라 빈 값이 밀린다.

# shellcheck source=switch.sh
declare -F scv_switch >/dev/null 2>&1 || source "${BASH_SOURCE[0]%/*}/switch.sh"
# shellcheck source=text.sh
declare -F scv_is_rewrite_quote >/dev/null 2>&1 || source "${BASH_SOURCE[0]%/*}/text.sh"

# @pure
# 역할: 표식 JSON 한 줄(깨져도 됨)을 \x1f 로 구분한 상태 필드 여섯 개로 풀어 낸다
# 종류: 꺼내기
# 예: '{"session":"s1","protocol":1,"turn":3,"diag":"ab12","diag_at":"09:30","nonce":"deadbeef"}' → $'s1\x1f1\x1f3\x1fab12\x1f09:30\x1fdeadbeef'
# 예: 'garbage' → $'\x1f0\x1f0\x1f\x1f\x1f'
# 표식 문자열(JSON 한 줄, 깨져도 됨) → "session\x1fprotocol\x1fturn\x1fdiag\x1fdiag_at\x1fnonce"
scv_hstate_parse() {
  local s="${1:-}" us=$'\x1f' session="" protocol=0 turn=0 diag="" diag_at="" nonce=""
  if [[ "$s" =~ \"session\":\"([^\"]*)\" ]]; then session="${BASH_REMATCH[1]}"; fi
  if [[ "$s" =~ \"protocol\":([01]) ]]; then protocol="${BASH_REMATCH[1]}"; fi
  if [[ "$s" =~ \"turn\":([0-9]+) ]]; then turn="${BASH_REMATCH[1]}"; fi
  if [[ "$s" =~ \"diag\":\"([0-9a-f]*)\" ]]; then diag="${BASH_REMATCH[1]}"; fi
  if [[ "$s" =~ \"diag_at\":\"([0-9:]*)\" ]]; then diag_at="${BASH_REMATCH[1]}"; fi
  if [[ "$s" =~ \"nonce\":\"([0-9a-f]*)\" ]]; then nonce="${BASH_REMATCH[1]}"; fi
  printf '%s%s%s%s%s%s%s%s%s%s%s' "$session" "$us" "$protocol" "$us" "$turn" "$us" "$diag" "$us" "$diag_at" "$us" "$nonce"
}

# @pure
# 역할: \x1f 로 구분한 상태를 표식 JSON 한 줄로 만든다
# 종류: 조립
# 예: $'s1\x1f1\x1f3\x1fab12\x1f09:30\x1fdeadbeef' → '{"session":"s1","protocol":1,"turn":3,"diag":"ab12","diag_at":"09:30","nonce":"deadbeef"}'
# 파싱된 상태 → JSON 한 줄. (세션 번호에 따옴표·역슬래시가 있으면 벗긴다 — 값이 아니라 식별자다.)
scv_hstate_render() {
  local st="${1:-}" us=$'\x1f' session protocol turn diag diag_at nonce
  IFS="$us" read -r session protocol turn diag diag_at nonce <<<"$st"
  session="${session//\"/}"; session="${session//\\/}"
  printf '{"session":"%s","protocol":%s,"turn":%s,"diag":"%s","diag_at":"%s","nonce":"%s"}' \
    "$session" "${protocol:-0}" "${turn:-0}" "${diag:-}" "${diag_at:-}" "${nonce:-}"
}

# @pure
# 역할: 상태 · 세션 번호 · 사건(prompt|reset) · N 으로 규약 재읽기 여부를 반영한 새 상태를 낸다
# 종류: 변환
# 예: $'s1\x1f1\x1f3\x1fab12\x1f09:30\x1fdeadbeef' s1 prompt 0 → $'s1\x1f1\x1f4\x1fab12\x1f09:30\x1fdeadbeef'
# 예: $'s1\x1f1\x1f3\x1fab12\x1f09:30\x1fdeadbeef' s2 prompt 0 → $'s2\x1f0\x1f1\x1f\x1f\x1f'
# 예: $'s1\x1f1\x1f3\x1fab12\x1f09:30\x1fdeadbeef' s1 reset 0 → $'s1\x1f0\x1f3\x1fab12\x1f09:30\x1f'
# 상태 + 세션 번호 + 사건(prompt|reset) + N(N턴마다 재읽기, 0=끔) → 새 상태.
#   prompt: 세션이 다르면 session 갱신·protocol=0·turn=1·diag 비움. 같으면 turn+1;
#           N>0 이고 turn 이 N 의 배수면 protocol=0 (주기적 재읽기).
#           세션 번호가 비어 있으면(호스트가 안 줌) 매 턴 protocol=0 — 이전과 같은 비용, 같은 동작.
#   reset : protocol=0 · nonce 비움 (압축·/clear·재개 뒤). 세션·turn 은 그대로.
#   지문(nonce)은 규약을 읽은 컨텍스트에 묶인 값이라, 컨텍스트가 바뀌는 전이(세션 전환·reset)에서 비운다.
scv_hstate_reload() {
  local st="${1:-}" sid="${2:-}" event="${3:-prompt}" every="${4:-0}" us=$'\x1f'
  local session protocol turn diag diag_at nonce
  IFS="$us" read -r session protocol turn diag diag_at nonce <<<"$st"
  protocol="${protocol:-0}"; turn="${turn:-0}"
  [[ "$every" =~ ^[0-9]+$ ]] || every=0
  case "$event" in
    reset) protocol=0; nonce="" ;;
    *)
      if [[ -z "$sid" ]]; then
        protocol=0; turn=$((turn + 1))
      elif [[ "$sid" != "$session" ]]; then
        session="$sid"; protocol=0; turn=1; diag=""; diag_at=""; nonce=""
      else
        turn=$((turn + 1))
        if (( every > 0 )) && (( turn % every == 0 )); then protocol=0; fi
      fi ;;
  esac
  printf '%s%s%s%s%s%s%s%s%s%s%s' "$session" "$us" "$protocol" "$us" "$turn" "$us" "$diag" "$us" "$diag_at" "$us" "$nonce"
}

# @pure
# 역할: 상태를 "규약을 읽었다"(protocol=1)로 바꾸고, 새 지문을 주면 그것으로 갈아 끼운다
# 종류: 변환
# 예: $'s1\x1f0\x1f3\x1fab12\x1f09:30\x1f' cafe0000 → $'s1\x1f1\x1f3\x1fab12\x1f09:30\x1fcafe0000'
# 상태 [+ 새 지문] → protocol=1 로 세운 상태 (help 가 규약 전체를 읽은 뒤 mark).
# 지문을 주면 바꿔 끼우고, 안 주면 있던 것을 유지한다 (무작위 생성은 효과부의 일).
scv_hstate_mark() {
  local st="${1:-}" new="${2:-}" us=$'\x1f' session protocol turn diag diag_at nonce
  IFS="$us" read -r session protocol turn diag diag_at nonce <<<"$st"
  [[ -n "$new" ]] && nonce="$new"
  printf '%s%s1%s%s%s%s%s%s%s%s' "$session" "$us" "$us" "${turn:-0}" "$us" "$diag" "$us" "$diag_at" "$us" "${nonce:-}"
}

# @pure
# 역할: 상태에서 규약 지문(nonce) 필드만 꺼낸다
# 종류: 꺼내기
# 예: $'s1\x1f1\x1f3\x1fab12\x1f09:30\x1fdeadbeef' → "deadbeef"
# 상태 → 지문 필드.
scv_hstate_nonce() {
  local st="${1:-}" us=$'\x1f' session protocol turn diag diag_at nonce
  IFS="$us" read -r session protocol turn diag diag_at nonce <<<"$st"
  printf '%s' "${nonce:-}"
}

# @deterministic
# 역할: 진단 본문의 해시를 직전과 견줘 "full"(바뀜) 또는 "brief"(같음)와 새 상태를 \x1f 로 이어 낸다
# 종류: 판정
# 예: $'s1\x1f1\x1f3\x1f\x1f\x1f' "diag text" 09:30 → $'full\x1fs1\x1f1\x1f3\x1f99c262b5b4fbdc2a\x1f09:30\x1f'
# 상태 + 진단 본문 + 시각(HH:MM) → "mode\x1f<새 상태>". mode=full(바뀜·첫 턴) | brief(직전과 같음).
scv_hstate_diag() {
  local st="${1:-}" text="${2:-}" now="${3:-}" us=$'\x1f' session protocol turn diag diag_at nonce h
  IFS="$us" read -r session protocol turn diag diag_at nonce <<<"$st"
  h="$(printf '%s' "$text" | sha256sum | cut -c1-16)"
  if [[ -n "$diag" && "$h" == "$diag" ]]; then
    printf 'brief%s%s%s%s%s%s%s%s%s%s%s%s' "$us" "$session" "$us" "${protocol:-0}" "$us" "${turn:-0}" "$us" "$diag" "$us" "$diag_at" "$us" "${nonce:-}"
  else
    printf 'full%s%s%s%s%s%s%s%s%s%s%s%s' "$us" "$session" "$us" "${protocol:-0}" "$us" "${turn:-0}" "$us" "$h" "$us" "$now" "$us" "${nonce:-}"
  fi
}

# @pure
# 역할: 진단이 안 바뀐 턴에 진단 전체 대신 싣는 한 줄 알림을 만든다
# 종류: 조립
# 예: 09:30 → "[SCV preflight] 진단 변동 없음 — 마지막 전체 진단 09:30 과 같다 (바뀌면 전체가 다시 실린다)."
# 진단이 안 바뀐 턴에 진단 전체 대신 싣는 한 줄.
scv_hstate_brief_line() {
  local at="${1:-}"
  printf '[SCV preflight] 진단 변동 없음 — 마지막 전체 진단 %s 과 같다 (바뀌면 전체가 다시 실린다).' "${at:-?}"
}

# @pure
# 역할: 상태와 스위치로 "PROTOCOL: load"(읽어라) 또는 "PROTOCOL: loaded"(이미 읽음)를 정한다
# 종류: 판정
# 예: $'s1\x1f1\x1f3' on → "PROTOCOL: loaded"
# 예: $'s1\x1f1\x1f3' off → "PROTOCOL: load"
# 상태 + 스위치(on|off) → "PROTOCOL: load" | "PROTOCOL: loaded". off 면 항상 load(이전 동작).
scv_hstate_protocol_line() {
  local st="${1:-}" sw="${2:-on}" us=$'\x1f' session protocol rest
  IFS="$us" read -r session protocol rest <<<"$st"
  if [[ "$sw" == "off" || "${protocol:-0}" != "1" ]]; then printf 'PROTOCOL: load'; else printf 'PROTOCOL: loaded'; fi
}

# 설정값 → on|off (기본 on; "off" 만 끈다, 대소문자·따옴표 무시).
# 같은 규칙의 구현은 lib/switch.sh 의 scv_switch 하나다 — 이 이름은 기존 호출을 위해 남긴다.
scv_hstate_switch() { scv_switch "$@"; }

# ---------------------------------------------------------------- 지문 메아리 · 답 모양 린트 (v0.50.0+)
#
# 왜 있나: 규약을 "읽었지만 흐릿해진" 상태는 모델의 주의를 잴 수 없어 직접 못 잡는다. 대신 행동으로
# 판정한다 — 통신의 체크섬과 재전송 요청처럼. (1) 규약을 읽은 컨텍스트에만 있는 지문을 매 턴 기록에
# 적게 하고 못 적으면 규약이 빠진 것으로 본다. (2) 답의 골격이 계약을 벗어나면 같은 신호로 본다.
# 둘 다 결과는 protocol=0 (다음 턴 다시 읽기) 과 경고 한 줄뿐 — 답을 막거나 고치지 않는다.

# @pure
# 역할: 이번 턴 기록의 지문과 표식 지문을 견줘 skip | ok | missing | mismatch 중 하나를 낸다
# 종류: 판정/answer
# 예: abc abc 1 yes → "ok"
# 예: "" abc 1 yes → "missing"
# 예: abc abc 0 yes → "skip"
# 지문 메아리 판정. <이번 턴 기록의 지문> <표식 지문> <protocol> <이번 턴에 기록이 있었나 yes|no>
#   → skip | ok | missing | mismatch
#   skip: 읽기 전(protocol 0)·표식에 지문이 없음(0.49 표식)·이번 턴에 기록 자체가 없음(진단 모드 등).
scv_echo_check() {
  local got="${1:-}" want="${2:-}" protocol="${3:-0}" appended="${4:-no}"
  if [[ "$protocol" != "1" || -z "$want" || "$appended" != "yes" ]]; then printf 'skip'; return 0; fi
  if [[ -z "$got" ]]; then printf 'missing'
  elif [[ "$got" == "$want" ]]; then printf 'ok'
  else printf 'mismatch'; fi
}

# @pure
# 역할: 글에서 따옴표 · 괄호 안을 비워 인용문 속 마침표를 문장 끝으로 세지 않게 한다
# 종류: 다듬기
# 예: 'a "b. c" d' → "a   d"
# 첫 문단에서 따옴표(" " “ ” ‘ ’)와 괄호(( ) （ ）) 안을 비운다 — 인용문 안의 마침표를 문장 끝으로 세지 않기 위해.
# 짝이 안 맞는 기호는 그대로 둔다(그러면 0.50.0 과 같은 세기). 곧은 작은따옴표는 영어 축약형과 겹쳐 손대지 않는다.
scv_lint_strip_quoted() {
  local s="${1:-}"
  while [[ "$s" =~ ^(.*)\"[^\"]*\"(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
  while [[ "$s" =~ ^(.*)“.*”(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
  while [[ "$s" =~ ^(.*)‘.*’(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
  while [[ "$s" =~ ^(.*)\([^()]*\)(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
  while [[ "$s" =~ ^(.*)（.*）(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
  printf '%s' "$s"
}

# @pure
# 역할: 한 덩어리 글의 문장 수를 센다 — 따옴표 · 괄호 안 마침표와 "0.49.1" 같은 숫자는 세지 않는다
# 종류: 세기
# 예: "결론이다. 둘째. 셋째." → "3"
# 예: '버전 0.49.1 이다 "a. b" 끝.' → "1"
# 예: "" → "0"
scv_lint_sentences() {
  local rest pat_end='^(.*)[.!?]([[:space:]].*)?$' n=0
  rest="$(scv_lint_strip_quoted "${1:-}")"; rest="${rest//.../.}"; rest="${rest//…/.}"
  while [[ "$rest" =~ $pat_end ]]; do rest="${BASH_REMATCH[1]}"; n=$((n + 1)); done
  printf '%s' "$n"
}

# @pure
# 역할: 불릿 한 줄이 존댓말 서술형('~습니다' · '~해요')으로 끝나면 1, 개조식 · 물음이면 0 을 낸다
# 종류: 판정/answer
# 예: "통과했습니다." → "1"
# 예: "README 검사 통과함" → "0"
# 예: "이대로 쓸까요?" → "0"
# 끝의 공백 · 마침표 · 느낌표 · 굵게 표시 · 닫는 괄호는 떼고 본다. 물음표로 끝나면 질문이라 예외. 한국어 어미만 본다.
scv_lint_bullet_polite() {
  local t="${1:-}"
  t="${t%"${t##*[![:space:]]}"}"
  [[ "$t" == *"?" || "$t" == *"？" ]] && { printf '0'; return 0; }
  while [[ "$t" == *"." || "$t" == *"!" || "$t" == *"。" || "$t" == *"*" || "$t" == *")" || "$t" == *"）" || "$t" == *" " ]]; do t="${t%?}"; done
  case "$t" in
    *니다|*세요|*어요|*아요|*해요|*예요|*에요|*지요|*죠) printf '1' ;;
    *) printf '0' ;;
  esac
}

# @pure
# 역할: 글에서 한글 글자가 한글 · 영문 글자 중 몇 퍼센트인지 센다(앞 4000바이트만)
# 종류: 세기
# 예: "로그인 버그를 고침" → "100"
# 예: "fixed the login bug" → "0"
# 예: "" → "0"
# 바이트로 센다(LC_ALL=C): 한글 음절의 첫 바이트(0xEA–0xED) 수와 ASCII 영문 글자 수. 맥 기본 bash 3.2 의 큰 글 치환이 느려 앞
# 4000바이트만 본다.
scv_lint_hangul_ratio() {
  local LC_ALL=C t="${1:-}" h l
  t="${t:0:4000}"
  h="${t//[^$'\xea'-$'\xed']/}"; l="${t//[^A-Za-z]/}"
  if (( ${#h} + ${#l} == 0 )); then printf '0'; return 0; fi
  printf '%s' "$(( ${#h} * 100 / (${#h} + ${#l}) ))"
}

# @pure
# 역할: 설정 언어가 한국어인데 답 글에 한글이 거의 없으면 위반 한 줄을 낸다
# 종류: 판정/answer
# 예: korean 0 50 → "lang-mismatch=0%"
# 예: korean 60 50 → ""
# 예: english 0 50 → ""
# <설정 언어> <한글 비율> <글자 수> → 위반 줄 | 빈 값. 글자 40개 미만의 짧은 답 · 한국어가 아닌 설정은 보지 않는다(0.77.0+).
scv_lint_lang_verdict() {
  local lang="${1:-}" ratio="${2:-0}" n="${3:-0}"
  [[ "$lang" == korean || "$lang" == ko ]] || return 0
  (( n >= 40 && ratio < 20 )) && printf 'lang-mismatch=%s%%\n' "$ratio"
  return 0
}

# @pure
# 역할: 답 본문의 골격(다시 쓴 요청 위치 · 줄글 문단 길이 · 불릿 어미 · 첫 내용의 코드값 · 결정표 추천 칸)이 계약을 벗어난 줄들을 낸다
# 종류: 판정/answer
# 예: $'> **다시 쓴 요청**: x\n\n**주제**\n- 결과임\n- 풀이함\n' → ""
# 예: $'결론이다. 둘째. 셋째.\n' 2 → "prose-long=3>2"
# 예: $'결론이다.\n\n> **다시 쓴 요청**: x\n' → "rewrite-not-top"
# 답 본문 + 줄글 문단 문장 상한 → 위반 줄들 (없으면 빈 출력). 골격만 본다 — 내용은 판정하지 않는다. 본문: contracts/writing.md.
#   rewrite-not-top           다시 쓴 요청 인용이 있는데 답 맨 위가 아님
#   prose-long=<n>><cap>      목록 · 표 · 제목 · 인용 · 굵은 주제가 아닌 줄글 문단의 문장 수가 상한 초과(첫 문단 하나만 알림)
#   bullet-polite=<개수>      '~습니다' · '~해요' 로 끝나는 불릿 수(개조식 '~함 · ~임' 이 아님, 물음은 예외)
#   lead-code=<값>            첫 내용 줄(불릿이나 줄글)의 코드값 (백틱 안 경로·버전·파일·설정 키)
#   decision-no-reco=<행>     결정표(| # | … |) 행의 셋째 열(추천)이 비어 있음
#   lang-mismatch=<n>%        셋째 인자(설정 언어)가 korean 인데 코드 · 인용 밖 글에 한글이 20% 미만(0.77.0+)
# 코드 블록 안은 보지 않는다. 근사이며, 오탐의 비용은 재읽기 한 번이다.
scv_answer_lint() {
  local text="${1:-}" cap="${2:-2}" lang="${3:-}" prose="" pl line t infence=0 seen=0 inquote=0 para="" first="" n polite=0 prose_done=0
  local intable=0 is_decision=0 row c1 c3 bt='`' gt=$'\x3e' pat_code pat_num rest tok
  [[ "$cap" =~ ^[1-9][0-9]*$ ]] || cap=2
  pat_code="${bt}([^${bt}]+)${bt}(.*)\$"
  pat_num='^[0-9]+[.)][[:space:]]'
  _scv_lint_flush() {
    [[ -n "$para" ]] || return 0
    [[ -z "$first" ]] && first="$para"
    if (( ! prose_done )); then
      n="$(scv_lint_sentences "$para")"
      (( n > cap )) && { printf "prose-long=%s${gt}%s\n" "$n" "$cap"; prose_done=1; }
    fi
    para=""
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    t="${line#"${line%%[![:space:]]*}"}"
    if [[ "$t" == '```'* ]]; then _scv_lint_flush; infence=$((1 - infence)); continue; fi
    (( infence )) && continue
    if [[ -z "$t" ]]; then _scv_lint_flush; inquote=0; intable=0; continue; fi
    if (( ! seen )); then
      seen=1
      [[ "$(scv_is_rewrite_quote "$t")" == "1" ]] && { inquote=1; continue; }
    fi
    if [[ "${t:0:1}" == "$gt" ]]; then
      _scv_lint_flush
      (( inquote )) && continue
      [[ "$(scv_is_rewrite_quote "$t")" == "1" ]] && printf 'rewrite-not-top\n'
      continue
    fi
    inquote=0
    pl="$t"; while [[ "$pl" =~ ^(.*)\`[^\`]*\`(.*)$ ]]; do pl="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
    (( ${#prose} < 4000 )) && prose+="$pl "
    if [[ "$t" == \|* ]]; then
      _scv_lint_flush
      if (( ! intable )); then
        intable=1; is_decision=0
        [[ "$t" =~ ^\|[[:space:]]*#[[:space:]]*\| ]] && is_decision=1
        continue
      fi
      (( is_decision )) || continue
      [[ "$t" =~ ^\|[[:space:]]*:?-+ ]] && continue
      row="${t#*|}"; c1="${row%%|*}"; row="${row#*|}"
      if [[ "$row" == *\|* ]]; then row="${row#*|}"; c3="${row%%|*}"; else c3=""; fi
      [[ "$c3" != *[![:space:]]* ]] && printf 'decision-no-reco=%s\n' "${c1//[[:space:]]/}"
      continue
    fi
    intable=0
    if [[ "$t" =~ $pat_num || "$t" == "- "* || "$t" == "* "* || "$t" == "+ "* ]]; then
      _scv_lint_flush
      if [[ "$t" =~ $pat_num ]]; then t="${t#*[.)]}"; else t="${t:2}"; fi
      [[ -z "$first" ]] && first="$t"
      [[ "$(scv_lint_bullet_polite "$t")" == "1" ]] && polite=$((polite + 1))
      continue
    fi
    if [[ "$t" == \#* || "$t" == \*\** ]]; then _scv_lint_flush; continue; fi
    para="${para:+$para }$t"
  done <<<"$text"
  _scv_lint_flush
  unset -f _scv_lint_flush
  (( polite > 0 )) && printf 'bullet-polite=%s\n' "$polite"
  if [[ -n "$lang" ]]; then
    local LC_ALL=C letters="${prose//[^A-Za-z$'\xea'-$'\xed']/}"
    scv_lint_lang_verdict "$lang" "$(scv_lint_hangul_ratio "$prose")" "${#letters}"
  fi
  rest="$first"
  while [[ "$rest" =~ $pat_code ]]; do
    tok="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
    if [[ "$tok" == */* || "$tok" =~ ^[0-9]+\.[0-9]+ || "$tok" =~ ^[A-Z][A-Z0-9_]+$ || "$tok" =~ \.(sh|md|json|ya?ml|js|ts|py)$ ]]; then
      printf 'lead-code=%s\n' "$tok"
    fi
  done
  return 0
}

# @pure
# 역할: 메아리 판정 · 린트 위반 · 스위치로 규약을 다시 실을지(1|0)와 다음 턴 경고 줄을 정한다
# 종류: 판정/gate
# 예: missing "" on on → $'1\x1f[SCV 규약 지문] 직전 턴 기록에 이 세션의 규약 지문이 없다 — 규약이 컨텍스트에서 빠진 것으로 보고 이번 턴에 다시 싣는다.'
# 예: ok "" on on → $'0\x1f'
# <메아리 판정> <린트 위반 줄들> <메아리 스위치 on|off> <린트 스위치 on|off>
#   → "<reload 0|1>\x1f<다음 턴 경고 줄들(\n 구분, 없으면 빈)>"
# 판정만 한다 — 표식·경고 파일 쓰기는 효과부. 스위치가 꺼진 쪽은 무시된다.
scv_drift_decide() {
  local echo_r="${1:-skip}" viol="${2:-}" esw="${3:-on}" lsw="${4:-on}" us=$'\x1f' reload=0 warn="" nviol=0 line
  if [[ "$esw" == "on" ]]; then
    case "$echo_r" in
      missing)  reload=1; warn="[SCV 규약 지문] 직전 턴 기록에 이 세션의 규약 지문이 없다 — 규약이 컨텍스트에서 빠진 것으로 보고 이번 턴에 다시 싣는다." ;;
      mismatch) reload=1; warn="[SCV 규약 지문] 직전 턴 기록의 지문이 이 세션의 것과 다르다 — 규약을 이번 턴에 다시 싣는다." ;;
    esac
  fi
  if [[ "$lsw" == "on" && "$viol" == *[![:space:]]* ]]; then
    while IFS= read -r line; do [[ "$line" == *[![:space:]]* ]] && nviol=$((nviol + 1)); done <<<"$viol"
    if (( nviol > 0 )); then
      reload=1; [[ -n "$warn" ]] && warn+=$'\n'
      warn+="[SCV 답 모양] 직전 답이 답 모양 계약을 벗어났다 (${viol//$'\n'/ · }) — 규약을 이번 턴에 다시 싣는다."
    fi
  fi
  printf '%s%s%s' "$reload" "$us" "$warn"
}

# @pure
# 역할: 시각 · 턴 · 메아리 판정 · 위반 수 · reload 를 드리프트 로그 한 줄로 만든다
# 종류: 조립
# 예: 09:30 3 ok $'lead-missing\n' 1 → "09:30 turn=3 echo=ok lint=1 reload=1"
# 예: 09:30 3 ok "" 0 host → "09:30 turn=3 echo=ok lint=0 reload=0 src=host"
# <시각> <turn> <메아리 판정> <위반 줄들> <reload> → 드리프트 로그 한 줄. 세션 뒤 "흐려진 턴" 을 세는 자료.
scv_drift_line() {
  local now="${1:-?}" turn="${2:-0}" echo_r="${3:-skip}" viol="${4:-}" reload="${5:-0}" src="${6:-}" nviol=0 line
  while IFS= read -r line; do [[ "$line" == *[![:space:]]* ]] && nviol=$((nviol + 1)); done <<<"$viol"
  printf '%s turn=%s echo=%s lint=%s reload=%s' "$now" "$turn" "$echo_r" "$nviol" "$reload"
  # v0.51.0+: 린트가 본 본문의 출처. 안 주면 0.50.0 형식 그대로 — 옛 줄과 같은 정규식으로 집계된다.
  [[ -n "$src" ]] && printf ' src=%s' "$src"
  return 0
}

# @pure
# 역할: 턴 스트림에서 마지막 사람 프롬프트 뒤의 어시스턴트 텍스트만 줄바꿈으로 이어 낸다
# 종류: 꺼내기
# 예: $'U\nA\x1fold\nU\nA\x1fnew1\x1esub\nA\x1fnew2\n' → $'new1\nsub\nnew2'
# 턴 스트림 → 이번 턴의 어시스턴트 텍스트. 스트림은 줄마다 "U"(사람이 쓴 프롬프트) 또는
# "A\x1f<텍스트, 줄바꿈은 \x1e>"(어시스턴트 텍스트 블록들). 마지막 U 이후의 A 만 줄바꿈으로 이어붙인다.
# U 가 하나도 없으면 빈값 — 창 안에서 턴 경계를 못 찾았으니 낡은 답을 볼 바에는 검사를 생략한다(안전 쪽).
# 도구 결과(tool_result)는 사람 프롬프트가 아니므로 효과부의 필터가 U 로 내지 않는다.
scv_turn_slice() {
  local stream="${1:-}" line buf="" seen=0 us=$'\x1f' rs=$'\x1e' t k
  local -a parts=()
  while IFS= read -r line; do
    case "$line" in
      U) seen=1; buf="" ;;
      A"$us"*)
        t="${line#A"$us"}"
        # \x1e → 줄바꿈. 패턴 치환(${t//…/…})을 쓰지 않는다 — 맥 기본 bash 3.2 는 큰 글(한 메시지 10만 바이트)의 치환에
        # 2분 넘게 걸렸다(2026-10-01 실측). 구분 글자로 나눠 다시 잇는다 — 히어스트링이 끝에 붙이는 줄바꿈 하나만 걷어 내면
        # 앞 · 뒤 · 연속 구분 글자까지 치환과 바이트로 같다.
        if [[ "$t" == *"$rs"* ]]; then
          parts=(); IFS="$rs" read -r -d '' -a parts <<<"$t" || true
          t=""; for (( k = 0; k < ${#parts[@]}; k++ )); do (( k )) && t+=$'\n'; t+="${parts[k]}"; done
          t="${t%$'\n'}"
        fi
        [[ "$t" == *[![:space:]]* ]] || continue
        [[ -n "$buf" ]] && buf+=$'\n'
        buf+="$t" ;;
    esac
  done <<<"$stream"
  (( seen )) || return 0
  printf '%s' "$buf"
}

# @pure
# 역할: 호스트가 넘긴 답을 먼저, 없으면 원본의 이번 턴 텍스트를 골라 "출처\x1f본문" 으로 낸다 (둘 다 없으면 none)
# 종류: 고르기
# 예: "host text" "turn text" → $'host\x1fhost text'
# 예: "" "" → $'none\x1f'
# <호스트가 넘긴 마지막 답> <원본의 이번 턴 텍스트> → "<src>\x1f<본문>". src ∈ host | transcript | none.
# 호스트 값이 1순위(공식 문서: 원본은 늦게 적힐 수 있다), 없으면 원본의 이번 턴, 그래도 없으면 none(린트 생략).
scv_stop_pick_source() {
  local host="${1:-}" turn="${2:-}" us=$'\x1f'
  if [[ "$host" == *[![:space:]]* ]]; then printf 'host%s%s' "$us" "$host"
  elif [[ "$turn" == *[![:space:]]* ]]; then printf 'transcript%s%s' "$us" "$turn"
  else printf 'none%s' "$us"; fi
}
