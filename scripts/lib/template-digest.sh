#!/usr/bin/env bash
# template-digest.sh — 템플릿 갱신 판단. 순수 함수만 둔다.
#
# 이 파일의 판단 함수(scv_ver_lt / scv_template_decide)는 문자열만 받고 문자열만
# 낸다. 파일도, 시각도, 무작위도, 네트워크도 만지지 않는다. 그래서 같은 입력에는
# 언제나 같은 출력이고, 입력 조합을 전부 세어 검사할 수 있다.
#
# 파일을 읽는 일은 이 파일 바깥(scvroot.sh, sync.sh)이 맡는다. 경계를 넘지 말 것 —
# core/tests/test-template-digest.sh 의 정적 검사가 이 경계를 기계로 강제한다.
#
# scv_digest_fold 만 예외적으로 외부 도구(sha256sum/shasum)를 부른다. 표준입력을
# 받아 표준출력을 내는 결정적 변환이며 디스크를 만지지 않는다. 정적 검사 대상에서
# 제외되는 유일한 함수다.

# ---------------------------------------------------------------- 순수: 번호 비교

# scv_ver_lt A B — A 가 B 보다 앞 세 자리 기준으로 오래됐으면 참.
# 순수 bash. `sort -V` 는 이 스크립트가 도는 모든 곳에 있지는 않다.
# @pure
scv_ver_lt() {
  local a1 a2 a3 arest b1 b2 b3 brest
  IFS='.-' read -r a1 a2 a3 arest <<< "$1."
  IFS='.-' read -r b1 b2 b3 brest <<< "$2."
  a1="${a1//[!0-9]/}"; a2="${a2//[!0-9]/}"; a3="${a3//[!0-9]/}"
  b1="${b1//[!0-9]/}"; b2="${b2//[!0-9]/}"; b3="${b3//[!0-9]/}"
  local a=$(( ${a1:-0}*1000000 + ${a2:-0}*1000 + ${a3:-0} ))
  local b=$(( ${b1:-0}*1000000 + ${b2:-0}*1000 + ${b3:-0} ))
  (( a < b )) && return 0
  (( a > b )) && return 1
  # 숫자가 같을 때: semver 는 프리릴리스를 정식보다 앞에 둔다 (2.1.0-rc1 < 2.1.0).
  # 둘 다 프리릴리스면 보수적으로 "오래되지 않음" 으로 본다.
  [[ -n "${arest%.}" && -z "${brest%.}" ]]
}

# ---------------------------------------------------------------- 순수: 갱신 판단

# scv_template_decide <stamped_digest> <payload_digest> <stamped_ver> <payload_ver>
#
# 프로젝트에 찍힌 지문/번호와 배포본의 지문/번호를 받아, 무엇을 할지 한 낱말로 낸다.
#
#   refresh            지문이 다르다 → 갱신한다  (이번에 새로 생긴 경로)
#   refresh:version    번호가 다르다 → 갱신한다  (예전부터 있던 경로)
#   refresh:unstamped  프로젝트에 지문이 아직 없다 (이번 변경 이전의 모든 프로젝트)
#                      → 한 번 갱신하고 찍는다
#   skip:same          지문도 번호도 같다 → 할 일 없음
#   skip:backward      배포본이 프로젝트보다 오래됐다 → 절대 되돌리지 않는다
#
# 규칙은 세 줄이다.
#   1. 배포본 번호가 프로젝트보다 오래되면, 지문과 무관하게 갱신하지 않는다.
#      없애면 두 대의 기계가 서로의 템플릿을 무한히 뒤집는다.
#   2. 지문이 다르면 갱신한다. 번호가 같아도 갱신한다.   ← 이번 수정의 본체
#   3. 번호가 다르면 갱신한다. 지문이 같아도 갱신한다.   ← 예전 동작 그대로
#
# 2번과 3번이 **둘 다** 산다는 것이 중요하다. 지문은 번호를 대체하지 않고 더한다.
# 지문만 보게 만들면, 번호 스탬프만 낡고 내용은 같은 프로젝트가 영영 안 고쳐진다 —
# 그 번호를 읽는 다른 코드들이 계속 틀린 값을 본다.
# @pure
scv_template_decide() {
  local stamped_digest="${1:-}" payload_digest="${2:-}"
  local stamped_ver="${3:-}"    payload_ver="${4:-}"

  # 1. 되돌림 방지가 언제나 먼저다.
  if [[ -n "$stamped_ver" && -n "$payload_ver" ]] \
     && scv_ver_lt "$payload_ver" "$stamped_ver"; then
    printf 'skip:backward\n'
    return 0
  fi

  local ver_differs=0
  [[ "$stamped_ver" != "$payload_ver" ]] && ver_differs=1

  # 2. 배포본에 지문이 없다 (구형 배포본) — 예전처럼 번호로만 판단한다.
  if [[ -z "$payload_digest" ]]; then
    if (( ver_differs )); then printf 'refresh:version\n'; else printf 'skip:same\n'; fi
    return 0
  fi

  # 3. 프로젝트에 지문이 없다 = 이번 변경 이전의 정상 상태. 손상이 아니다.
  if [[ -z "$stamped_digest" ]]; then
    printf 'refresh:unstamped\n'
    return 0
  fi

  # 4. 내용이 다르면 갱신. 번호가 같아도 갱신한다.
  if [[ "$stamped_digest" != "$payload_digest" ]]; then
    printf 'refresh\n'
    return 0
  fi

  # 5. 내용은 같지만 번호 스탬프가 낡았다 — 예전 경로. 바로잡는다.
  if (( ver_differs )); then
    printf 'refresh:version\n'
    return 0
  fi

  printf 'skip:same\n'
}

# ---------------------------------------------------- 결정적 변환: 지문 접기

# scv_digest_fold — 표준입력의 "<해시>  <경로>" 줄들을 하나의 지문으로 접는다.
#
# 경로 순으로 정렬한 뒤 해싱하므로 입력 순서에 무관하다. 수정 시각·권한·소유자는
# 애초에 입력에 없으므로 지문에 섞이지 않는다. 같은 트리는 어느 기계에서 계산해도
# 같은 지문이 나온다.
#
# 디스크를 만지지 않는다 — 표준입력을 받아 표준출력을 낸다.
# @deterministic
scv_digest_fold() {
  LC_ALL=C sort | {
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum
    else
      shasum -a 256
    fi
  } | awk '{print $1}'
}
