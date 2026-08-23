#!/usr/bin/env bash
# record-read.sh — 기록 하나를 파일을 훑지 않고 이름으로 읽는다.
#
# SCV 의 기록은 append-only 로 자란다 — 저널은 모든 턴을, DECISIONS 는 모든
# 결정을. 지난 것을 찾으려고 파일 전체를 읽으면 컨텍스트가 그만큼 찬다.
# 색인이 위치를 들고 있으므로 그 구간만 읽는다.
#
# Usage:
#   record-read.sh --key NAME        그 이름의 최신 기록을 읽는다
#   record-read.sh --list [KIND]     기록 목록 (본문은 안 읽는다)
#   record-read.sh --mark KIND       그 종류를 전부 읽는다 (decision|plan|blocker|pivot)
#
# Env:
#   SCV_DIR   scv 디렉터리 (기본: scv)
#
# 색인이 없거나 깨져 있으면 빈 결과와 함께 exit 0. 읽기가 실패해도 부르는 쪽의
# 작업을 막지 않는다.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/record-index.sh
source "$SCRIPT_DIR/lib/record-index.sh"

MODE=""; ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --key)  MODE="key";  ARG="${2:-}"; shift 2 ;;
    --mark) MODE="mark"; ARG="${2:-}"; shift 2 ;;
    --list) MODE="list"; ARG="${2:-}"; [[ -n "$ARG" ]] && shift 2 || shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "record-read.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$MODE" ]] || { sed -n '2,17p' "$0"; exit 2; }

SCV_DIR_RESOLVED="${SCV_DIR:-scv}"
INDEX_FILE="$SCV_DIR_RESOLVED/INDEX.tsv"
# 0.32.0 은 저널 아래에 두었다. 그 자리도 읽어 준다 — 옮겼다고 남의 기록을 잃으면 안 된다.
LEGACY_INDEX="${SCV_JOURNAL_DIR:-$SCV_DIR_RESOLVED/journal}/INDEX.tsv"
[[ -f "$INDEX_FILE" || ! -f "$LEGACY_INDEX" ]] || INDEX_FILE="$LEGACY_INDEX"

if [[ ! -f "$INDEX_FILE" || -L "$INDEX_FILE" ]]; then
  echo "scv: no record index yet ($INDEX_FILE) — decisions index themselves; mark turns with journal-append.sh --mark." >&2
  exit 0
fi
INDEX="$(cat "$INDEX_FILE" 2>/dev/null || true)"
[[ -n "$INDEX" ]] || { echo "scv: the record index is empty." >&2; exit 0; }

# 한 레코드를 읽어 찍는다. 저널을 훑지 않는다 — 오프셋으로 건너뛰고 길이만큼 읽는다.
read_record() {
  local rec="$1" mark key file off len ts summary
  { read -r mark; read -r key; read -r file; read -r off
    read -r len;  read -r ts;  read -r summary
  } < <(record_index_fields "$rec")

  if [[ ! -f "$file" ]]; then
    echo "scv: [$key] the recorded file is gone ($file) — index entry skipped." >&2
    return 0
  fi
  # 저널을 훑지 않는다 — 오프셋만큼 건너뛰고 길이만큼만 읽는다.
  local body
  body="$(tail -c "+$((off + 1))" "$file" 2>/dev/null | head -c "$len" || true)"
  # 길이는 **읽어 온 구간에서 직접** 잰다. $(...) 는 끝 줄바꿈을 지우고 ${#…} 는
  # 글자 수를 세므로(한글 한 글자가 3바이트), 둘 다 여기서는 틀린 답을 준다.
  local got
  got="$(tail -c "+$((off + 1))" "$file" 2>/dev/null | head -c "$len" | wc -c | tr -d '[:space:]')"
  [[ "$got" =~ ^[0-9]+$ ]] || got=0
  printf '─── %s · %s · %s ───\n' "$mark" "$key" "$ts"
  printf '%s\n' "$body"

  # 저널이 손으로 편집되면 위치가 어긋난다. 조용히 엉뚱한 내용을 주지 않는다.
  #
  # 두 가지를 본다. 길이는 **잘림**을 잡고, 시작 모양은 **밀림**을 잡는다 —
  # 앞줄이 지워지면 길이는 그대로인데 다른 항목이 읽힌다.
  if (( got < len )); then
    echo "scv: [$key] expected ${len} bytes, read ${got} — the journal was truncated or edited by hand." >&2
  fi
  # 기록은 언제나 빈 줄 + 제목 줄로 시작한다. 저널 항목은 "### [", 결정 엔트리는
  # "## [". 아니면 위치가 밀린 것이다 — 앞줄이 지워지면 길이는 그대로인데
  # 다른 내용이 읽힌다.
  case "$body" in
    $'\n'"### ["*|$'\n'"## ["*) : ;;
    *) echo "scv: [$key] the indexed position no longer starts an entry — the file was edited directly; re-record it." >&2 ;;
  esac
}

case "$MODE" in
  list)
    RECS="$(record_index_filter "$INDEX" "$ARG")"
    [[ -n "$RECS" ]] || { echo "scv: nothing marked${ARG:+ as $ARG} yet." >&2; exit 0; }
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      { read -r m; read -r k; read -r f; read -r o; read -r l; read -r t; read -r s
      } < <(record_index_fields "$rec")
      printf '%-9s %-28s %s  (%s bytes)\n' "$m" "$k" "$t" "$l"
      [[ -n "$s" ]] && printf '          %s\n' "$s"
    done <<< "$RECS"
    ;;
  key)
    [[ -n "$ARG" ]] || { echo "record-read.sh: --key needs a NAME" >&2; exit 2; }
    REC="$(record_index_lookup "$INDEX" "$ARG")"
    [[ -n "$REC" ]] || { echo "scv: no marked turn named [$ARG]." >&2; exit 0; }
    read_record "$REC"
    ;;
  mark)
    [[ -n "$ARG" ]] || { echo "record-read.sh: --mark needs a KIND" >&2; exit 2; }
    RECS="$(record_index_filter "$INDEX" "$ARG")"
    [[ -n "$RECS" ]] || { echo "scv: nothing marked as [$ARG]." >&2; exit 0; }
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      read_record "$rec"
      echo
    done <<< "$RECS"
    ;;
esac
