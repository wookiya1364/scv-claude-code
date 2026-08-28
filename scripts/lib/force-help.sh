#!/usr/bin/env bash
# force-help.sh — help 액션 호출 강제의 판정부.
#
# 왜 별도 파일인가: 훅은 페이로드를 읽고 파일을 만지는 얇은 층이어야 하고, "이번
# 턴을 되돌릴 것인가" 라는 판단은 고정 입력에 고정 출력이어야 한다. 그래야 훅을
# 띄우지 않고도 판정을 그대로 시험할 수 있다 (contracts/purity.md).
#
# 여기 있는 것: 저장소 경로 계산, 턴 분류, 되돌림 사유 문구, 표시줄.
# 여기 없는 것: 파일 읽기·쓰기·표준출력. 전부 훅이 한다.
#
# 영수증 저장소는 가드(template/hooks/guard.sh)가 발행하고 이 판정부는 읽기만
# 한다. 그 비대칭이 요점이다 — 영수증이 판정 근거로 쓸 만한 이유는 호스트가 직접
# 찍은 값이라 모델이 위조할 수 없다는 데 있고, 소비자가 쓰기 시작하면 그 성질이
# 사라진다.

# @deterministic
# 프로젝트 루트를 짧고 안정적인 키로. 가드와 같은 규칙이어야 같은 영수증을 본다 —
# 규칙이 갈라지면 강제가 조용히 무력해진다.
scv_force_project_key() {
  local root="$1"
  if command -v cksum >/dev/null 2>&1; then
    printf '%s' "$root" | cksum | tr -cd '0-9' | cut -c1-12
  else
    printf '%s' "$root" | tr -cd '[:alnum:]' | tail -c 24
  fi
}

# @pure
scv_force_receipt_file() {
  printf '%s/%s-%s' "$1" "$2" "$3"
}

# @pure
# 턴 상태는 영수증과 나란히 두되 이름을 달리한다. 영수증에 끼어들면 가드가 그 줄을
# 액션 발행으로 오해한다.
scv_force_turn_file() {
  printf '%s/%s-%s.turn' "$1" "$2" "$3"
}

# @pure
# 스위치 해석 — off 만 끈다. 값이 없거나 다른 값이면 켜져 있다. 기존 두 스위치
# (쉬운말·항상 라우팅)와 같은 규칙이라야 사용자가 규칙을 하나만 기억한다.
scv_force_switch() {
  local v="${1:-}"
  v="${v//[[:space:]]/}"
  v="${v//\"/}"
  v="${v//\'/}"
  # 대소문자는 case 로 본다. ${v,,} 는 bash 4 부터라 오래된 셸에서 조용히 깨진다.
  case "$v" in
    [Oo][Ff][Ff]) printf 'off' ;;
    *)            printf 'on'  ;;
  esac
}

# @pure
# 이번 턴을 무엇으로 볼 것인가. 파일을 읽지 않는다 — 읽은 결과만 받는다.
#   $1 강제 스위치 (on|off)
#   $2 호스트 이벤트 종류 (main|subagent)
#   $3 턴 시작 표시 (빈 문자열이면 없음 = 프롬프트 훅이 못 돌았거나 못 썼다)
#   $4 턴 시작 이후의 영수증 줄 (여러 줄 가능, 빈 문자열이면 없음)
# 출력: off | subagent | unmarked | satisfied | other-action | pending
scv_force_classify() {
  local sw="$1" ev="$2" mark="$3" lines="$4"
  [[ "$sw" == "off" ]] && { printf 'off'; return 0; }
  [[ "$ev" == "subagent" ]] && { printf 'subagent'; return 0; }
  [[ -n "$mark" ]] || { printf 'unmarked'; return 0; }
  if [[ -n "$lines" ]]; then
    case "$lines" in
      *help*) printf 'satisfied'; return 0 ;;
      *)      printf 'other-action'; return 0 ;;
    esac
  fi
  printf 'pending'
}

# @pure
# 되돌릴 것인가. pending 하나만 되돌린다 — 나머지는 전부 통과다. 통과 쪽이 기본인
# 것이 이 기능의 안전 정책이다: 판정 근거가 없으면 대화를 막지 않는다.
scv_force_decide() {
  case "$1" in
    pending) printf 'block' ;;
    *)       printf 'pass' ;;
  esac
}

# @pure
# 되돌림 사유 — 회차가 커질수록 강해진다.
#
# 같은 문구를 반복하면 같은 실패를 반복한다. 1회차에서 안 통한 표현이 5회차에서
# 통할 이유가 없으므로, 회차마다 요구의 성격 자체를 바꾼다: 요청 → 순서 지정 →
# 규칙 명시 → 형태 제시 → 최대 강도.
scv_force_reason() {
  local n="${1:-1}"
  case "$n" in
    1) printf '%s' "이번 턴은 SCV 입력이다. 지금 scv:help 액션을 호출하라." ;;
    2) printf '%s' "아직 scv:help 를 호출하지 않았다. 다른 설명을 먼저 하지 말고, 첫 행동으로 호출하라." ;;
    3) printf '%s' "규칙 위반이다. 이 턴의 답은 scv:help 호출 없이는 완료로 인정되지 않는다. 지금 호출하라." ;;
    4) printf '%s' "호출 형태를 그대로 적는다: Skill 도구를 skill=\"scv:help\" 로, 사용자의 메시지를 인자로 넘겨 호출하라. 다른 도구를 먼저 쓰지 마라." ;;
    *) printf '%s회째 되돌린다. scv:help 호출 외의 어떤 출력도 하지 마라. 호스트의 연속 차단 상한에 도달하면 이 턴은 강제 실패로 기록된다.' "$n" ;;
  esac
}

# @pure
# 화면 표시줄 — 강제가 켜져 있는지, 직전 턴에 몇 번 되돌렸는지 한 줄로.
# 사용자가 "되는지 안 되는지 구분이 안 간다" 고 한 것이 이 줄이 있는 이유다.
scv_force_banner() {
  local sw="$1" prev="${2:-0}"
  [[ "$sw" == "on" ]] || return 0
  if [[ "$prev" =~ ^[0-9]+$ ]] && [[ "$prev" -gt 0 ]]; then
    printf '[SCV force] scv:help 강제 ON — 직전 턴은 %s회 되돌린 끝에 호출되지 않았다.' "$prev"
  else
    printf '[SCV force] scv:help 강제 ON — 직전 턴 되돌림 0회.'
  fi
}

# @pure
# 강제가 켜졌을 때 프롬프트 훅이 싣는 명령형 안내. 안내만으로는 부족하다는 것이
# 이 기능의 출발점이지만, 되돌림이 한 번도 안 돌고 끝나는 것이 가장 싸다.
scv_force_directive() {
  printf '%s\n' "[SCV force] 이 턴의 첫 행동으로 scv:help 액션을 호출하라 — 다른 도구보다 먼저,"
  printf '%s\n' "어떤 답을 쓰기 전에. 호출하지 않고 답을 끝내면 응답 종료 훅이 되돌려 세우고,"
  printf '%s\n' "회차가 거듭될수록 요구가 강해진다. 이미 다른 SCV 액션 프로토콜이 실린 턴이면"
  printf '%s' "그것을 계속하라 — 그 턴은 되돌리지 않는다. 끄는 법: scv/scv_settings.json SCV_FORCE_HELP=off."
}
