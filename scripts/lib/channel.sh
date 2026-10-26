#!/usr/bin/env bash
# lib/channel.sh — 채널(개발 · 스테이징 · 운영)의 순수부 (0.71.0+). 규칙 전문: protocols/channel.md.
#
# 채널마다 래퍼 저장소의 브랜치 하나에서 받는다: 개발 → channel/dev, 스테이징 → channel/stage, 운영 → 브랜치 없음(기본 브랜치).
# channel/* 브랜치는 래퍼의 채널 동기화가 만든다 — 래퍼 develop · stage 와 릴리스 체인은 건드리지 않는다.
# 여기 함수는 모두 순수하다(인자만 읽고 stdout 으로만 돌려준다). 호스트의 플러그인 명령으로 옮기는 일은 래퍼 몫.
#
#   scv_channel_ref <채널>                  → 브랜치 (운영은 빈 줄). 모르는 채널은 종료 코드 2.
#   scv_channel_of_ref <브랜치>              → 채널 이름 (빈 값 · main → prod, 그 밖의 브랜치 → other:<브랜치>)
#   scv_channel_plan <있음 0|1> <지금 브랜치> <목표 브랜치>
#                                          → 바꿔 끼우기 단계 줄들: "remove" / "add <브랜치|->" / "install". 이미 그 채널이면 아무것도.
#   scv_channel_version <기준 버전> <채널> <커밋>
#                                          → 운영은 기준 그대로, 개발 · 스테이징은 다음 패치에 -dev.<커밋7> / -stage.<커밋7>.

scv_channel_ref() {
  case "${1:-}" in
    dev) echo 'channel/dev' ;;
    stage) echo 'channel/stage' ;;
    prod) echo '' ;;
    *) return 2 ;;
  esac
}

scv_channel_of_ref() {
  case "${1:-}" in
    ''|main) echo 'prod' ;;
    channel/dev) echo 'dev' ;;
    channel/stage) echo 'stage' ;;
    *) echo "other:$1" ;;
  esac
}

scv_channel_plan() {
  local present=$1 current=$2 target=$3
  if [[ $present -eq 1 && "$current" == "$target" ]]; then return 0; fi
  [[ $present -eq 1 ]] && echo 'remove'
  echo "add ${target:--}"
  echo 'install'
}

scv_channel_version() {
  local base=$1 channel=$2 sha=$3 core major minor patch
  [[ "$channel" == prod ]] && { echo "$base"; return 0; }
  case "$channel" in dev|stage) ;; *) return 2 ;; esac
  core="${base%%-*}"
  IFS=. read -r major minor patch <<<"$core"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ && -n "$sha" ]] || return 2
  echo "${major}.${minor}.$((patch + 1))-${channel}.${sha:0:7}"
}
