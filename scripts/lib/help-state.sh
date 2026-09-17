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

# @pure
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
# 파싱된 상태 → JSON 한 줄. (세션 번호에 따옴표·역슬래시가 있으면 벗긴다 — 값이 아니라 식별자다.)
scv_hstate_render() {
  local st="${1:-}" us=$'\x1f' session protocol turn diag diag_at nonce
  IFS="$us" read -r session protocol turn diag diag_at nonce <<<"$st"
  session="${session//\"/}"; session="${session//\\/}"
  printf '{"session":"%s","protocol":%s,"turn":%s,"diag":"%s","diag_at":"%s","nonce":"%s"}' \
    "$session" "${protocol:-0}" "${turn:-0}" "${diag:-}" "${diag_at:-}" "${nonce:-}"
}

# @pure
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
# 상태 [+ 새 지문] → protocol=1 로 세운 상태 (help 가 규약 전체를 읽은 뒤 mark).
# 지문을 주면 바꿔 끼우고, 안 주면 있던 것을 유지한다 (무작위 생성은 효과부의 일).
scv_hstate_mark() {
  local st="${1:-}" new="${2:-}" us=$'\x1f' session protocol turn diag diag_at nonce
  IFS="$us" read -r session protocol turn diag diag_at nonce <<<"$st"
  [[ -n "$new" ]] && nonce="$new"
  printf '%s%s1%s%s%s%s%s%s%s%s' "$session" "$us" "$us" "${turn:-0}" "$us" "$diag" "$us" "$diag_at" "$us" "${nonce:-}"
}

# @pure
# 상태 → 지문 필드.
scv_hstate_nonce() {
  local st="${1:-}" us=$'\x1f' session protocol turn diag diag_at nonce
  IFS="$us" read -r session protocol turn diag diag_at nonce <<<"$st"
  printf '%s' "${nonce:-}"
}

# @deterministic
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
# 진단이 안 바뀐 턴에 진단 전체 대신 싣는 한 줄.
scv_hstate_brief_line() {
  local at="${1:-}"
  printf '[SCV preflight] 진단 변동 없음 — 마지막 전체 진단 %s 과 같다 (바뀌면 전체가 다시 실린다).' "${at:-?}"
}

# @pure
# 상태 + 스위치(on|off) → "PROTOCOL: load" | "PROTOCOL: loaded". off 면 항상 load(이전 동작).
scv_hstate_protocol_line() {
  local st="${1:-}" sw="${2:-on}" us=$'\x1f' session protocol rest
  IFS="$us" read -r session protocol rest <<<"$st"
  if [[ "$sw" == "off" || "${protocol:-0}" != "1" ]]; then printf 'PROTOCOL: load'; else printf 'PROTOCOL: loaded'; fi
}

# @pure
# 설정값 → on|off (기본 on; "off" 만 끈다, 대소문자·따옴표 무시).
scv_hstate_switch() {
  local v="${1:-}"
  v="${v//\"/}"; v="${v//\'/}"; v="${v//[[:space:]]/}"; v="${v,,}"
  if [[ "$v" == "off" ]]; then printf 'off'; else printf 'on'; fi
}

# ---------------------------------------------------------------- 지문 메아리 · 답 모양 린트 (v0.50.0+)
#
# 왜 있나: 규약을 "읽었지만 흐릿해진" 상태는 모델의 주의를 잴 수 없어 직접 못 잡는다. 대신 행동으로
# 판정한다 — 통신의 체크섬과 재전송 요청처럼. (1) 규약을 읽은 컨텍스트에만 있는 지문을 매 턴 기록에
# 적게 하고 못 적으면 규약이 빠진 것으로 본다. (2) 답의 골격이 계약을 벗어나면 같은 신호로 본다.
# 둘 다 결과는 protocol=0 (다음 턴 다시 읽기) 과 경고 한 줄뿐 — 답을 막거나 고치지 않는다.

# @pure
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
# 답 본문 + 첫 문단 문장 상한 → 위반 줄들 (없으면 빈 출력). 골격만 본다 — 내용은 판정하지 않는다.
#   lead-missing              결론 문단 없이 표·목록·제목으로 시작
#   lead-sentences=<n>><cap>  첫 문단 문장 수가 상한 초과 (마침표·물음표·느낌표 뒤 공백/끝 기준 — "0.49.1" 은 안 센다,
#                             따옴표·괄호 안의 마침표도 안 센다 v0.51.0+)
#   lead-code=<값>            첫 문단의 코드값 (백틱 안 경로·버전·파일·설정 키)
#   decision-no-reco=<행>     결정표(| # | … |) 행의 셋째 열(추천)이 비어 있음
# 코드 블록 안은 보지 않는다. 근사이며, 오탐의 비용은 재읽기 한 번이다.
scv_answer_lint() {
  local text="${1:-}" cap="${2:-2}" line infence=0 lead="" lead_done=0 lead_kind="" n=0 rest tok
  local intable=0 is_decision=0 row c1 c2 c3 bt='`' gt=$'\x3e' pat_code pat_end pat_num
  [[ "$cap" =~ ^[1-9][0-9]*$ ]] || cap=2
  pat_code="${bt}([^${bt}]+)${bt}(.*)\$"
  pat_end='^(.*)[.!?]([[:space:]].*)?$'
  pat_num='^[0-9]+[.)][[:space:]]'
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*\`\`\` ]]; then infence=$((1 - infence)); continue; fi
    (( infence )) && continue
    if (( ! lead_done )); then
      if [[ -z "${line//[[:space:]]/}" ]]; then
        [[ -n "$lead" ]] && lead_done=1
        continue
      fi
      if [[ -z "$lead" ]]; then
        if [[ "$line" =~ $pat_num ]]; then lead_kind="structure"; lead_done=1   # 번호 목록
        else
          case "$line" in
            \|*|\#*|-\ *|\*\ *|+\ *|"$gt"*) lead_kind="structure"; lead_done=1 ;;   # 표·제목·목록·인용
            *) lead="$line" ;;
          esac
        fi
      else
        lead="$lead $line"
      fi
    fi
    if [[ "$line" =~ ^[[:space:]]*\| ]]; then
      if (( ! intable )); then
        intable=1; is_decision=0
        [[ "$line" =~ ^[[:space:]]*\|[[:space:]]*#[[:space:]]*\| ]] && is_decision=1
        continue
      fi
      (( is_decision )) || continue
      [[ "$line" =~ ^[[:space:]]*\|[[:space:]]*:?-+ ]] && continue
      row="${line#*|}"; c1="${row%%|*}"; row="${row#*|}"; c2="${row%%|*}"
      if [[ "$row" == *\|* ]]; then row="${row#*|}"; c3="${row%%|*}"; else c3=""; fi
      [[ -z "${c3//[[:space:]]/}" ]] && printf 'decision-no-reco=%s\n' "${c1//[[:space:]]/}"
    else
      intable=0
    fi
  done <<<"$text"
  [[ "$lead_kind" == "structure" ]] && printf 'lead-missing\n'
  if [[ -n "$lead" ]]; then
    rest="$(scv_lint_strip_quoted "$lead")"; rest="${rest//.../.}"; rest="${rest//…/.}"; n=0
    while [[ "$rest" =~ $pat_end ]]; do rest="${BASH_REMATCH[1]}"; n=$((n + 1)); done
    (( n > cap )) && printf "lead-sentences=%s${gt}%s\n" "$n" "$cap"
    rest="$lead"
    while [[ "$rest" =~ $pat_code ]]; do
      tok="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
      if [[ "$tok" == */* || "$tok" =~ ^[0-9]+\.[0-9]+ || "$tok" =~ ^[A-Z][A-Z0-9_]+$ || "$tok" =~ \.(sh|md|json|ya?ml|js|ts|py)$ ]]; then
        printf 'lead-code=%s\n' "$tok"
      fi
    done
  fi
  return 0
}

# @pure
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
  if [[ "$lsw" == "on" && -n "${viol//[[:space:]]/}" ]]; then
    while IFS= read -r line; do [[ -n "${line//[[:space:]]/}" ]] && nviol=$((nviol + 1)); done <<<"$viol"
    if (( nviol > 0 )); then
      reload=1; [[ -n "$warn" ]] && warn+=$'\n'
      warn+="[SCV 답 모양] 직전 답이 답 모양 계약을 벗어났다 (${viol//$'\n'/ · }) — 규약을 이번 턴에 다시 싣는다."
    fi
  fi
  printf '%s%s%s' "$reload" "$us" "$warn"
}

# @pure
# <시각> <turn> <메아리 판정> <위반 줄들> <reload> → 드리프트 로그 한 줄. 세션 뒤 "흐려진 턴" 을 세는 자료.
scv_drift_line() {
  local now="${1:-?}" turn="${2:-0}" echo_r="${3:-skip}" viol="${4:-}" reload="${5:-0}" src="${6:-}" nviol=0 line
  while IFS= read -r line; do [[ -n "${line//[[:space:]]/}" ]] && nviol=$((nviol + 1)); done <<<"$viol"
  printf '%s turn=%s echo=%s lint=%s reload=%s' "$now" "$turn" "$echo_r" "$nviol" "$reload"
  # v0.51.0+: 린트가 본 본문의 출처. 안 주면 0.50.0 형식 그대로 — 옛 줄과 같은 정규식으로 집계된다.
  [[ -n "$src" ]] && printf ' src=%s' "$src"
  return 0
}

# @pure
# 턴 스트림 → 이번 턴의 어시스턴트 텍스트. 스트림은 줄마다 "U"(사람이 쓴 프롬프트) 또는
# "A\x1f<텍스트, 줄바꿈은 \x1e>"(어시스턴트 텍스트 블록들). 마지막 U 이후의 A 만 줄바꿈으로 이어붙인다.
# U 가 하나도 없으면 빈값 — 창 안에서 턴 경계를 못 찾았으니 낡은 답을 볼 바에는 검사를 생략한다(안전 쪽).
# 도구 결과(tool_result)는 사람 프롬프트가 아니므로 효과부의 필터가 U 로 내지 않는다.
scv_turn_slice() {
  local stream="${1:-}" line buf="" seen=0 us=$'\x1f' rs=$'\x1e' t
  while IFS= read -r line; do
    case "$line" in
      U) seen=1; buf="" ;;
      A"$us"*)
        t="${line#A"$us"}"; t="${t//$rs/$'\n'}"
        [[ -n "${t//[[:space:]]/}" ]] || continue
        [[ -n "$buf" ]] && buf+=$'\n'
        buf+="$t" ;;
    esac
  done <<<"$stream"
  (( seen )) || return 0
  printf '%s' "$buf"
}

# @pure
# <호스트가 넘긴 마지막 답> <원본의 이번 턴 텍스트> → "<src>\x1f<본문>". src ∈ host | transcript | none.
# 호스트 값이 1순위(공식 문서: 원본은 늦게 적힐 수 있다), 없으면 원본의 이번 턴, 그래도 없으면 none(린트 생략).
scv_stop_pick_source() {
  local host="${1:-}" turn="${2:-}" us=$'\x1f'
  if [[ -n "${host//[[:space:]]/}" ]]; then printf 'host%s%s' "$us" "$host"
  elif [[ -n "${turn//[[:space:]]/}" ]]; then printf 'transcript%s%s' "$us" "$turn"
  else printf 'none%s' "$us"; fi
}
