#!/usr/bin/env bash
# journal-read.sh — 표시된 저널 항목을 저널을 훑지 않고 읽는다.
#
# 저널은 모든 턴을 그대로 쌓는다. 지난 이야기를 찾으려고 파일 전체를 읽으면
# 컨텍스트가 그만큼 찬다. 색인이 위치를 들고 있으므로 그 구간만 읽는다 —
# 파일이 얼마나 크든 읽는 양은 그 항목만큼이다.
#
# Usage:
#   journal-read.sh --key NAME        그 이름의 최신 항목을 읽는다
#   journal-read.sh --list [KIND]     표시된 항목 목록 (본문은 안 읽는다)
#   journal-read.sh --mark KIND       그 표시가 붙은 항목을 전부 읽는다
#
# Env:
#   SCV_JOURNAL_DIR   저널 디렉터리 (기본: scv/journal)
#
# 색인이 없거나 깨져 있으면 빈 결과와 함께 exit 0. 읽기가 실패해도 부르는 쪽의
# 작업을 막지 않는다.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/journal-index.sh
source "$SCRIPT_DIR/lib/journal-index.sh"

MODE=""; ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --key)  MODE="key";  ARG="${2:-}"; shift 2 ;;
    --mark) MODE="mark"; ARG="${2:-}"; shift 2 ;;
    --list) MODE="list"; ARG="${2:-}"; [[ -n "$ARG" ]] && shift 2 || shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "journal-read.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$MODE" ]] || { sed -n '2,17p' "$0"; exit 2; }

JOURNAL_DIR="${SCV_JOURNAL_DIR:-scv/journal}"
INDEX_FILE="$JOURNAL_DIR/INDEX.tsv"

if [[ ! -f "$INDEX_FILE" || -L "$INDEX_FILE" ]]; then
  echo "scv: no journal index yet ($INDEX_FILE) — mark turns with journal-append.sh --mark." >&2
  exit 0
fi
INDEX="$(cat "$INDEX_FILE" 2>/dev/null || true)"
[[ -n "$INDEX" ]] || { echo "scv: the journal index is empty." >&2; exit 0; }

# 한 레코드를 읽어 찍는다. 저널을 훑지 않는다 — 오프셋으로 건너뛰고 길이만큼 읽는다.
read_record() {
  local rec="$1" mark key file off len ts summary
  { read -r mark; read -r key; read -r file; read -r off
    read -r len;  read -r ts;  read -r summary
  } < <(journal_index_fields "$rec")

  if [[ ! -f "$file" ]]; then
    echo "scv: [$key] the journal file is gone ($file) — index entry skipped." >&2
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
  # 항목은 언제나 빈 줄 + "### [" 로 시작한다. 아니면 위치가 밀린 것이다.
  local head2="${body:0:6}"
  if [[ "$head2" != $'\n### [' ]]; then
    echo "scv: [$key] the indexed position no longer starts an entry — the journal was edited by hand; re-mark it." >&2
  fi
}

case "$MODE" in
  list)
    RECS="$(journal_index_filter "$INDEX" "$ARG")"
    [[ -n "$RECS" ]] || { echo "scv: nothing marked${ARG:+ as $ARG} yet." >&2; exit 0; }
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      { read -r m; read -r k; read -r f; read -r o; read -r l; read -r t; read -r s
      } < <(journal_index_fields "$rec")
      printf '%-9s %-28s %s  (%s bytes)\n' "$m" "$k" "$t" "$l"
      [[ -n "$s" ]] && printf '          %s\n' "$s"
    done <<< "$RECS"
    ;;
  key)
    [[ -n "$ARG" ]] || { echo "journal-read.sh: --key needs a NAME" >&2; exit 2; }
    REC="$(journal_index_lookup "$INDEX" "$ARG")"
    [[ -n "$REC" ]] || { echo "scv: no marked turn named [$ARG]." >&2; exit 0; }
    read_record "$REC"
    ;;
  mark)
    [[ -n "$ARG" ]] || { echo "journal-read.sh: --mark needs a KIND" >&2; exit 2; }
    RECS="$(journal_index_filter "$INDEX" "$ARG")"
    [[ -n "$RECS" ]] || { echo "scv: nothing marked as [$ARG]." >&2; exit 0; }
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      read_record "$rec"
      echo
    done <<< "$RECS"
    ;;
esac
