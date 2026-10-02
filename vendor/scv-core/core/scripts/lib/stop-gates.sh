#!/usr/bin/env bash
# lib/stop-gates.sh — 종료 훅의 세 검사(등록 · 원칙 · 선택지)가 검사마다 한 턴에 한 번씩 막게 하는 순수부 (v0.64.2+).
# 효과(훅 입력 · 턴 표 · 전달 기록 읽기, 막기 출력 · 전달 기록 쓰기 · 지우기)는 template/hooks/on-stop.sh.
#
#   scv_gates_delivered <검사> <계속 중 0|1> <세션> <턴 표> <전달 기록 한 줄>   → 1(이번 턴에 이미 이유를 전달함) | 0
#   scv_gates_record <세션> <턴 표> <전달 기록 한 줄> <계속 중 0|1> <막은 검사들> → 새 전달 기록 한 줄 | 빈 값(쓰지 않음)
#   scv_gates_drop <세션> <전달 기록 한 줄> <계속 중 0|1>                        → 1(지난 턴 기록 — 지금 지운다) | 0
#   scv_gates_reason <등록 이유> <원칙 이유> <선택지 이유>                         → 막는 이유 — 빈 것은 빼고 이 순서로 줄마다 하나
#
# 검사 이름은 prompt · principle · choice, 막은 검사들은 쉼표로 잇는다. 전달 기록은 "<세션>\x1f<턴 표>\x1f<검사들>" 한 줄이다.
# 계속 중이 아닌 멈춤(종료 훅이 막아서 이어진 멈춤이 아님)은 턴의 첫 멈춤이다 — 아직 어떤 검사도 이유를 전달하지 않았고, 같은
# 세션의 지난 기록은 지운다(자동 알림 턴처럼 턴 표가 그대로인 다음 턴이 지난 기록을 이번 것으로 읽지 않게).
# 계속 중인 멈춤: 기록이 이 세션 · 이 턴 표의 것이면 거기 있는 검사만 1 — 이 턴에 우리 검사가 막은 적이 있어야 나머지 검사가
# 제 몫을 쓴다. 기록이 없거나(다른 훅이 먼저 이어 간 턴 · 첫 멈춤의 기록 쓰기 실패), 세션 id 나 턴 표가 없거나, 기록이 깨졌거나,
# 다른 세션 · 다른 턴 표의 것이면 모두 1 — 이 기능 전과 같은 동작(계속 중이면 막지 않음)이고, 막는 쪽으로 실패하지 않는다.
# 세션 id 가 없으면 한 저장소의 두 세션을 가를 수 없어 한 검사가 여러 번 막힐 수 있다(재검토 2026-10-02) — 그런 호스트는 이 기능
# 전과 같게 둔다.
#
# 꺾쇠 글자는 쓰지 않는다 — 순수성 검사가 리다이렉션으로 본다.

# @pure
# <검사> <계속 중 0|1> <세션> <턴 표> <전달 기록 한 줄> → 1 | 0.
scv_gates_delivered() {
  local gate="${1:-}" active="${2:-0}" sess="${3:-}" tok="${4:-}" rec="${5:-}" us=$'\x1f' rs rest rt rl
  [[ "$active" == "1" ]] || { printf '0'; return 0; }
  [[ -n "$sess" && -n "$tok" && -n "$rec" ]] || { printf '1'; return 0; }
  rs="${rec%%"$us"*}"; rest="${rec#*"$us"}"
  [[ "$rest" != "$rec" && "$rest" == *"$us"* ]] || { printf '1'; return 0; }   # 칸이 셋보다 적다 — 깨진 기록
  rt="${rest%%"$us"*}"; rl="${rest#*"$us"}"
  [[ "$rl" != *"$us"* ]] || { printf '1'; return 0; }                           # 칸이 셋보다 많다 — 깨진 기록
  [[ "$rs" == "$sess" && "$rt" == "$tok" ]] || { printf '1'; return 0; }
  case ",$rl," in
    *",$gate,"*) printf '1' ;;
    *) printf '0' ;;
  esac
}

# @pure
# <세션> <턴 표> <전달 기록 한 줄> <계속 중 0|1> <막은 검사들> → 새 기록 한 줄 | 빈 값.
# 막은 검사가 없거나 턴 표가 없으면 쓰지 않는다. 첫 멈춤이면 새로 시작하고, 계속 중이면 이 세션 · 이 턴 표의 기록에 더한다.
scv_gates_record() {
  local sess="${1:-}" tok="${2:-}" rec="${3:-}" active="${4:-0}" blocked="${5:-}" us=$'\x1f' head list="" rest g
  [[ -n "$tok" && -n "$blocked" ]] || return 0
  head="$sess$us$tok$us"
  [[ "$active" == "1" && "$rec" == "$head"* ]] && list="${rec#"$head"}"
  [[ "$list" == *"$us"* ]] && list=""
  rest="$blocked,"
  while [[ -n "$rest" ]]; do
    g="${rest%%,*}"; rest="${rest#*,}"
    [[ -n "$g" ]] || continue
    case ",$list," in
      *",$g,"*) ;;
      *) list="${list:+$list,}$g" ;;
    esac
  done
  printf '%s%s' "$head" "$list"
}

# @pure
# <세션> <전달 기록 한 줄> <계속 중 0|1> → 1 | 0. 첫 멈춤에서 이 세션의 지난 기록과 깨진 기록을 지운다. 다른 세션의 기록은
# 그 세션의 것이라 두고 간다.
scv_gates_drop() {
  local sess="${1:-}" rec="${2:-}" active="${3:-0}" us=$'\x1f' rs rest
  [[ "$active" != "1" && -n "$rec" ]] || { printf '0'; return 0; }
  rs="${rec%%"$us"*}"; rest="${rec#*"$us"}"
  if [[ "$rest" == "$rec" || "$rest" != *"$us"* || "${rest#*"$us"}" == *"$us"* ]]; then printf '1'; return 0; fi
  if [[ "$rs" == "$sess" ]]; then printf '1'; else printf '0'; fi
}

# @pure
# <등록 이유> <원칙 이유> <선택지 이유> → 막는 이유. 빈 것은 빼고 이 순서로, 이유마다 한 줄. 모두 비면 빈 값.
scv_gates_reason() {
  local out="" r nl=$'\n'
  for r in "${1:-}" "${2:-}" "${3:-}"; do
    [[ -n "$r" ]] || continue
    out="${out:+$out$nl}$r"
  done
  printf '%s' "$out"
}
