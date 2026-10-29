#!/usr/bin/env bash
# deck-source.sh (lib) — deck 엔진(DeckUI) 폴더를 고르는 순수부 (0.72.2+).
#
# 왜 있나: 코어 트리는 보통 엔진을 코어 루트 바로 아래(DeckUI/)에 둔다 — 코어 저장소 · codex 사본 · claude 의 코어 사본.
# claude 래퍼의 스킬은 플러그인 최상위를 코어 루트로 삼아 돌고, 그 자리에는 엔진이 없다(맨 위 사본을 없앴다).
# 그래서 래퍼 설정(호스트 프로필 SCV_DECKUI_DIR, 코어 루트 기준 상대 경로)이 엔진 자리를 알려 준다.
# 순서: 코어 루트 아래 DeckUI 가 있으면 그것(코어 · codex 동작 그대로), 없으면 설정 값, 둘 다 없으면 코어 루트 아래 DeckUI
# (없다는 오류는 런타임이 낸다). 폴더가 있는지는 부르는 쪽이 보고 넘긴다 — 여기서는 파일을 읽지 않는다.

# @pure
# <코어 루트> <설정 값> <코어 루트 아래 DeckUI 가 있나 yes|no> → 엔진 폴더 경로 한 줄.
# 설정 값이 절대 경로이거나 '..' 조각을 담으면 아무것도 내지 않고 2 를 돌려준다(플러그인 밖을 가리키지 못하게).
scv_deck_source_dir() {
  local root="${1%/}" v="${2:-}" own="${3:-no}" seg rest
  if [[ -n "$v" ]]; then
    case "$v" in /*) return 2 ;; esac
    rest="$v"
    while [[ -n "$rest" ]]; do
      seg="${rest%%/*}"
      [[ "$seg" == ".." ]] && return 2
      [[ "$rest" == */* ]] && rest="${rest#*/}" || rest=""
    done
  fi
  if [[ "$own" == yes || -z "$v" ]]; then
    printf '%s/DeckUI\n' "$root"
  else
    printf '%s/%s\n' "$root" "${v%/}"
  fi
}
