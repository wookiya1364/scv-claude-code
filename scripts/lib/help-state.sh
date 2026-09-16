#!/usr/bin/env bash
# help-state.sh — "규약은 세션당 한 번" 의 상태 표식 순수부 (v0.49.0+).
#
# 왜 있나: help 규약 전체를 매 턴 다시 싣지 않고 세션에 한 번만 읽게 하려면 "다시 읽을 때"를
# 누군가 정해야 한다. 모델의 판단("컨텍스트에 안 보이면 읽어라")은 비결정적이라 쓰지 않는다.
# 대신 훅이 보는 사실 — 세션 번호가 바뀜 · 컨텍스트가 비워짐(압축·/clear·재개) · N턴이 지남 —
# 만으로 정한다. 같은 표식으로 매 턴 진단도 "바뀐 턴에만 전체, 아니면 한 줄" 이 된다.
#
# 표식 한 줄 JSON: {"session":"<id>","protocol":0|1,"turn":<n>,"diag":"<해시 앞 16자>","diag_at":"HH:MM"}
#   protocol 0 = 다음 help 호출 때 규약 전체를 읽어라(load), 1 = 이미 읽었다(loaded).
#
# 순수: 문자열만 받아 문자열만 낸다. 파일 읽기·쓰기는 scripts/help-state.sh (효과부).
# 필드 구분자는 \x1f (단위 구분자) — 탭은 IFS 공백류라 빈 값이 밀린다.

# @pure
# 표식 문자열(JSON 한 줄, 깨져도 됨) → "session\x1fprotocol\x1fturn\x1fdiag\x1fdiag_at"
scv_hstate_parse() {
  local s="${1:-}" us=$'\x1f' session="" protocol=0 turn=0 diag="" diag_at="" v
  if [[ "$s" =~ \"session\":\"([^\"]*)\" ]]; then session="${BASH_REMATCH[1]}"; fi
  if [[ "$s" =~ \"protocol\":([01]) ]]; then protocol="${BASH_REMATCH[1]}"; fi
  if [[ "$s" =~ \"turn\":([0-9]+) ]]; then turn="${BASH_REMATCH[1]}"; fi
  if [[ "$s" =~ \"diag\":\"([0-9a-f]*)\" ]]; then diag="${BASH_REMATCH[1]}"; fi
  if [[ "$s" =~ \"diag_at\":\"([0-9:]*)\" ]]; then diag_at="${BASH_REMATCH[1]}"; fi
  printf '%s%s%s%s%s%s%s%s%s' "$session" "$us" "$protocol" "$us" "$turn" "$us" "$diag" "$us" "$diag_at"
}

# @pure
# 파싱된 상태 → JSON 한 줄. (세션 번호에 따옴표·역슬래시가 있으면 벗긴다 — 값이 아니라 식별자다.)
scv_hstate_render() {
  local st="${1:-}" us=$'\x1f' session protocol turn diag diag_at
  IFS="$us" read -r session protocol turn diag diag_at <<<"$st"
  session="${session//\"/}"; session="${session//\\/}"
  printf '{"session":"%s","protocol":%s,"turn":%s,"diag":"%s","diag_at":"%s"}' \
    "$session" "${protocol:-0}" "${turn:-0}" "${diag:-}" "${diag_at:-}"
}

# @pure
# 상태 + 세션 번호 + 사건(prompt|reset) + N(N턴마다 재읽기, 0=끔) → 새 상태.
#   prompt: 세션이 다르면 session 갱신·protocol=0·turn=1·diag 비움. 같으면 turn+1;
#           N>0 이고 turn 이 N 의 배수면 protocol=0 (주기적 재읽기).
#           세션 번호가 비어 있으면(호스트가 안 줌) 매 턴 protocol=0 — 이전과 같은 비용, 같은 동작.
#   reset : protocol=0 만 (압축·/clear·재개 뒤). 세션·turn 은 그대로.
scv_hstate_reload() {
  local st="${1:-}" sid="${2:-}" event="${3:-prompt}" every="${4:-0}" us=$'\x1f'
  local session protocol turn diag diag_at
  IFS="$us" read -r session protocol turn diag diag_at <<<"$st"
  protocol="${protocol:-0}"; turn="${turn:-0}"
  [[ "$every" =~ ^[0-9]+$ ]] || every=0
  case "$event" in
    reset) protocol=0 ;;
    *)
      if [[ -z "$sid" ]]; then
        protocol=0; turn=$((turn + 1))
      elif [[ "$sid" != "$session" ]]; then
        session="$sid"; protocol=0; turn=1; diag=""; diag_at=""
      else
        turn=$((turn + 1))
        if (( every > 0 )) && (( turn % every == 0 )); then protocol=0; fi
      fi ;;
  esac
  printf '%s%s%s%s%s%s%s%s%s' "$session" "$us" "$protocol" "$us" "$turn" "$us" "$diag" "$us" "$diag_at"
}

# @pure
# 상태 → protocol=1 로 세운 상태 (help 가 규약 전체를 읽은 뒤 mark).
scv_hstate_mark() {
  local st="${1:-}" us=$'\x1f' session protocol turn diag diag_at
  IFS="$us" read -r session protocol turn diag diag_at <<<"$st"
  printf '%s%s1%s%s%s%s%s%s' "$session" "$us" "$us" "${turn:-0}" "$us" "$diag" "$us" "$diag_at"
}

# @deterministic
# 상태 + 진단 본문 + 시각(HH:MM) → "mode\x1f<새 상태>". mode=full(바뀜·첫 턴) | brief(직전과 같음).
scv_hstate_diag() {
  local st="${1:-}" text="${2:-}" now="${3:-}" us=$'\x1f' session protocol turn diag diag_at h
  IFS="$us" read -r session protocol turn diag diag_at <<<"$st"
  h="$(printf '%s' "$text" | sha256sum | cut -c1-16)"
  if [[ -n "$diag" && "$h" == "$diag" ]]; then
    printf 'brief%s%s%s%s%s%s%s%s%s%s' "$us" "$session" "$us" "${protocol:-0}" "$us" "${turn:-0}" "$us" "$diag" "$us" "$diag_at"
  else
    printf 'full%s%s%s%s%s%s%s%s%s%s' "$us" "$session" "$us" "${protocol:-0}" "$us" "${turn:-0}" "$us" "$h" "$us" "$now"
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
