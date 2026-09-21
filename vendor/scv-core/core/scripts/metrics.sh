#!/usr/bin/env bash
# metrics.sh — 과정 계기판. 이 프로젝트의 파일로 SCV 과정을 숫자로 본다.
#
# 이미 디스크에 있는 기록만 읽는다 — 아카이브 색인, 계획서, 대화 파일, 결정 로그.
# 어떤 파일도 쓰지 않고, 시각·난수·네트워크를 읽지 않는다. 같은 입력에 같은 출력.
#
# 지표 넷 (각각 적용 범위 n/m 과 함께):
#   계획당 대화 턴 수      — 계획서 raw_sources 가 가리키는 대화 파일들의 Turn 수 합
#   승인→보관 리드타임(분) — 결정 로그의 같은 slug adopted → archived 시각 차
#   후속 재발률            — obsoleted_by 의 대상이거나 supersedes 가 비어 있지 않은 계획
#   순수 절 보유율         — 계획서에 "## 순수함수 · 파이프라인" 절이 있는 계획
#
# 이것은 각 프로젝트가 자기 파일로 자기를 재는 계기판이지 제품 통계가 아니다.
# 데이터가 없는 계획은 0 이 아니라 none — 적용 범위의 분모에만 든다.
#
# Usage:
#   metrics.sh            표 (파이프 구분)
#   metrics.sh --tsv      원자료 (metric \t slug \t value; 매칭 안 된 결정은 unmatched)
#
# Env:
#   SCV_DIR   scv 디렉터리 (기본: scv)
#
# 색인이 없으면 stderr 한 줄과 exit 0 — 부르는 쪽의 작업을 막지 않는다.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/metrics.sh
source "$SCRIPT_DIR/lib/metrics.sh"

MODE="table"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tsv) MODE="tsv"; shift ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "metrics.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

SCV_DIR="${SCV_DIR:-scv}"
INDEX_FILE="$SCV_DIR/archive/INDEX.yaml"
DECISIONS_FILE="$SCV_DIR/DECISIONS.md"

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "metrics.sh: no archive index ($INDEX_FILE)" >&2
  exit 0
fi

# ---------------------------------------------------------------- 효과: 읽기 (입구)

index_text="$(<"$INDEX_FILE")"
index_lines="$(scv_mx_parse_index "$index_text")"

decisions_text=""
[[ -f "$DECISIONS_FILE" ]] && decisions_text="$(<"$DECISIONS_FILE")"
decision_lines="$(scv_mx_parse_decisions "$decisions_text")"

turn_lines=""; sup_lines=""; purity_lines=""
while IFS=$'\t' read -r slug status obs || [[ -n "$slug" ]]; do
  [[ -z "$slug" ]] && continue
  plan_file="$SCV_DIR/archive/$slug/PLAN.md"
  convs=""; sup_n=0; purity=0
  if [[ -f "$plan_file" ]]; then
    plan_text="$(<"$plan_file")"
    IFS=$'\t' read -r convs sup_n purity <<< "$(scv_mx_parse_plan "$plan_text")"
    [[ "$convs" == "-" ]] && convs=""
  fi
  turns="none"
  if [[ -n "$convs" ]]; then
    total=0; found=0
    IFS=',' read -r -a conv_paths <<< "$convs"
    for p in "${conv_paths[@]}"; do
      while IFS= read -r cand || [[ -n "$cand" ]]; do
        [[ -z "$cand" ]] && continue
        f="$SCV_DIR/$cand"
        if [[ -f "$f" ]]; then
          conv_text="$(<"$f")"
          total=$(( total + $(scv_mx_count_turns "$conv_text") ))
          found=1
          break
        fi
      done <<< "$(scv_mx_resolve_conv_path "$p")"
    done
    (( found )) && turns="$total"
  fi
  turn_lines+="$slug	$turns"$'\n'
  sup_lines+="$slug	$sup_n"$'\n'
  purity_lines+="$slug	$purity"$'\n'
done <<< "$index_lines"

# ---------------------------------------------------------------- 순수: 지표 → 요약

lead_lines="$(scv_mx_metric_lead_time "$index_lines" "$decision_lines")"
followup_lines="$(scv_mx_metric_followup "$index_lines" "$sup_lines")"

# ---------------------------------------------------------------- 효과: 출력 (출구)

if [[ "$MODE" == "tsv" ]]; then
  printf 'metric\tslug\tvalue\n'
  scv_mx_render_tsv turns "$turn_lines"
  scv_mx_render_tsv lead_time_minutes "$lead_lines"
  scv_mx_render_tsv followup "$followup_lines"
  scv_mx_render_tsv purity_section "$purity_lines"
  while IFS=$'\t' read -r dslug verdict mins || [[ -n "$dslug" ]]; do
    [[ "$dslug" == "unmatched" ]] && printf 'unmatched\t%s\t%s\n' "$verdict" "$mins"
  done <<< "$decision_lines"
  exit 0
fi

scv_mx_render_table \
  "$(scv_mx_aggregate "$turn_lines")" \
  "$(scv_mx_aggregate "$lead_lines")" \
  "$(scv_mx_aggregate "$followup_lines")" \
  "$(scv_mx_aggregate "$purity_lines")"
