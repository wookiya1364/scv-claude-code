#!/usr/bin/env bash
# lib/evidence.sh — 증적 영상은 사람 속도로.
#
# 사람은 화면 전환당 ~2초가 있어야 인지한다. e2e 스펙이 기계 속도로 달리면
# 영상이 그보다 짧아진다 — 임계(SCV_EVIDENCE_MIN_SECONDS, 기본 4초)보다 짧은
# 증적 영상에 경고 한 줄을 낸다. 경고만 한다: 첨부·PR·알림은 그대로 진행되고,
# ffprobe 가 없는 환경에서는 조용히 건너뛴다 (새 필수 의존성을 만들지 않는다).

evidence_min_seconds() {
  local v="${SCV_EVIDENCE_MIN_SECONDS:-}"
  v="$(printf '%s' "$v" | tr -d '"[:space:]' | tr -d "'")"
  [[ "$v" =~ ^[1-9][0-9]*$ ]] || v=4
  printf '%s\n' "$v"
}

# 영상 길이(초, 내림 정수). ffprobe 없음/실패/파일 없음 → 빈 값, exit 0.
evidence_video_seconds() {
  local f="${1:-}" dur
  [[ -n "$f" && -f "$f" ]] || return 0
  command -v ffprobe >/dev/null 2>&1 || return 0
  dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)" || return 0
  [[ "$dur" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 0
  printf '%d\n' "${dur%%.*}"
  return 0
}

# 임계보다 짧으면 stderr 한 줄. 항상 exit 0.
evidence_warn_short() {
  local f="${1:-}" min secs
  min="$(evidence_min_seconds)"
  secs="$(evidence_video_seconds "$f")"
  [[ -n "$secs" ]] || return 0
  if (( secs < min )); then
    echo "evidence: $(basename "$f") is ${secs}s — shorter than ${min}s (humans need ~2s per screen transition; pace the spec — see work.md Step 5b; threshold: SCV_EVIDENCE_MIN_SECONDS)" >&2
  fi
  return 0
}
