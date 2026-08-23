#!/usr/bin/env bash
# recap.sh — 컨텍스트를 비운 직후, 무엇을 하고 있었는지 싸게 되찾는다.
#
# 왜 있나: 매번 "지금 내용 저장하고 앞으로 할 일 리스트 만드는" 손일을 없애기
# 위해서다. 저장은 이미 자동으로 되고 있다 — 결정은 세 지점에서 DECISIONS 로,
# 계획은 promote/archive 로, 대화는 journal 로. 여기서는 **아무것도 새로 쓰지
# 않고** 그것들을 조립해서 보여 준다.
#
# status 와 다른 점: status 는 프로젝트 전체 상태(원자료 변경 목록까지)를 보여
# 준다. recap 은 "지금 무엇을 하던 중이었나" 만 본다 — 짧을수록 좋다.
#
# 읽는 양: 색인이 있으면 결정 본문을 안 읽는다. 계획은 frontmatter 만 본다.
#
# Usage:
#   recap.sh [--decisions N]   최근 결정 N건 (기본 5)
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/record-index.sh
source "$SCRIPT_DIR/lib/record-index.sh"

N=5
while [[ $# -gt 0 ]]; do
  case "$1" in
    --decisions) N="${2:-5}"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "recap.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$N" =~ ^[0-9]+$ ]] || N=5

SCV_DIR_RESOLVED="${SCV_DIR:-scv}"
[[ -d "$SCV_DIR_RESOLVED" ]] || { echo "scv: no $SCV_DIR_RESOLVED/ here — nothing to recap." >&2; exit 0; }

field() {  # <파일> <키> — frontmatter 한 줄
  sed -n "s/^$2:[[:space:]]*//p" "$1" 2>/dev/null | head -n 1 | sed -e 's/^"//' -e 's/"$//'
}

echo "──────────────────────────────────────────────────────────────"
echo " Recap — $(basename "$(pwd)")"
echo "──────────────────────────────────────────────────────────────"

# ---------- 진행 중인 계획 ----------
echo
echo "[진행 중]"
FOUND=0
if [[ -d "$SCV_DIR_RESOLVED/promote" ]]; then
  for d in "$SCV_DIR_RESOLVED"/promote/*/; do
    [[ -f "$d/PLAN.md" ]] || continue
    FOUND=$((FOUND + 1))
    printf '  · %s\n' "$(basename "$d")"
    T="$(field "$d/PLAN.md" title)"; [[ -n "$T" ]] && printf '      %s\n' "$T"
    S="$(field "$d/PLAN.md" status)"; [[ -n "$S" ]] && printf '      상태: %s\n' "$S"
  done
fi
[[ $FOUND -eq 0 ]] && echo "  (없음 — 다음 계획은 promote 액션으로)"

# ---------- 최근 결정 ----------
echo
echo "[최근 결정 — 본문은 이름으로 펼친다]"
INDEX_FILE="$SCV_DIR_RESOLVED/INDEX.tsv"
LEGACY="${SCV_JOURNAL_DIR:-$SCV_DIR_RESOLVED/journal}/INDEX.tsv"
[[ -f "$INDEX_FILE" || ! -f "$LEGACY" ]] || INDEX_FILE="$LEGACY"

SHOWN=0
if [[ -f "$INDEX_FILE" && ! -L "$INDEX_FILE" ]]; then
  # 색인이 있으면 본문을 안 읽는다 — 요약 줄만 본다.
  IDX="$(cat "$INDEX_FILE" 2>/dev/null || true)"
  RECS="$(record_index_filter "$IDX" decision)"
  if [[ -n "$RECS" ]]; then
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      { read -r k; read -r key; read -r f; read -r o; read -r l; read -r ts; read -r sm
      } < <(record_index_fields "$rec")
      printf '  · %s  %s\n' "$ts" "$sm"
      printf '      펼치기: record-read.sh --key %s\n' "$key"
      SHOWN=$((SHOWN + 1))
    done <<< "$(printf '%s' "$RECS" | tail -n "$N")"
  fi
fi
if [[ $SHOWN -eq 0 ]]; then
  # 색인이 아직 없는 프로젝트 — 결정 로그 꼬리를 그대로 본다.
  D="$SCV_DIR_RESOLVED/DECISIONS.md"
  if [[ -f "$D" ]]; then
    grep '^## \[' "$D" 2>/dev/null | grep -v '^## \[YYYY' | tail -n "$N" | sed 's/^## /  · /'
    echo "  (색인 없음 — 앞으로 쌓이는 결정은 이름으로 펼칠 수 있다)"
  else
    echo "  (없음)"
  fi
fi

# ---------- 막힌 것 ----------
if [[ -f "$INDEX_FILE" && ! -L "$INDEX_FILE" ]]; then
  BL="$(record_index_filter "$(cat "$INDEX_FILE" 2>/dev/null || true)" blocker)"
  if [[ -n "$BL" ]]; then
    echo
    echo "[막힌 것]"
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      { read -r k; read -r key; read -r f; read -r o; read -r l; read -r ts; read -r sm
      } < <(record_index_fields "$rec")
      printf '  · %s  (%s)\n' "$sm" "$key"
    done <<< "$BL"
  fi
fi

# ---------- 미결 사항 ----------
# 진행 중인 계획과 **최근** 보관 계획만 본다. 오래된 계획의 미결 사항은
# 지금 하던 일과 무관하고, 그것까지 보여 주면 금방 안 읽게 된다.
RECENT_DIRS=""
[[ -d "$SCV_DIR_RESOLVED/promote" ]] && RECENT_DIRS="$(ls -d "$SCV_DIR_RESOLVED"/promote/*/ 2>/dev/null || true)"
if [[ -d "$SCV_DIR_RESOLVED/archive" ]]; then
  RECENT_DIRS="$RECENT_DIRS
$(ls -d "$SCV_DIR_RESOLVED"/archive/*/ 2>/dev/null | LC_ALL=C sort | tail -n 3 || true)"
fi
{
  while IFS= read -r d; do
    [[ -n "$d" && -f "$d/PLAN.md" ]] || continue
    awk '/^## (미결 사항|Risks \/ Open Questions|Open Questions)/{f=1;next} /^## /{f=0} f && /^- /{print}' \
      "$d/PLAN.md" 2>/dev/null | head -n 2 | while IFS= read -r line; do
        printf '  · %s  ← %s\n' "${line:2:100}" "$(basename "$d")"
      done
  done <<< "$RECENT_DIRS"
} > /tmp/.scv_recap_open.$$ 2>/dev/null || true
if [[ -s /tmp/.scv_recap_open.$$ ]]; then
  echo
  echo "[미결 — 계획에 적힌 것]"
  head -n 6 /tmp/.scv_recap_open.$$
fi
rm -f /tmp/.scv_recap_open.$$

echo
echo "  더 자세히: status 액션 · 결정 하나: record-read.sh --key <이름>"
