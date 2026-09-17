#!/usr/bin/env bash
# graph.sh — SCV 자체 그래프의 효과부 (v0.51.0+): 재료를 읽고, 순수부(lib/graph.sh)로 그래프를 만들어 scv/.graph/ 에 쓴다.
#
#   graph.sh build                 그래프를 (다시) 만든다 → GRAPH_STATUS: built
#   graph.sh status                missing | stale | built | off | unavailable (한 줄, 파일은 손대지 않음)
#   graph.sh ensure                stale/missing 이면 build, 아니면 그대로 → GRAPH_STATUS 한 줄
#   graph.sh impact [--json] <path>…   수정 범위 — 함께 바뀌는 파일(가중치·근거) · 건드린 계획 · 얽힌 결정 · 링크한 문서
#   graph.sh report                GRAPH_REPORT.md 를 그대로 찍는다
#
# 재료: 설정 SCV_GRAPH_DOCS 의 마크다운(기본 "docs README.md README.*.md core/contracts") · scv/archive/*/PLAN.md ·
#       scv/promote/*/PLAN.md(active) · scv/DECISIONS.md. 산출물: scv/.graph/graph.json · GRAPH_REPORT.md (무시 파일).
# 원칙: 새 외부 의존 없음(bash · jq). jq 없으면 unavailable, SCV_GRAPH=off 면 off — 어느 쪽도 부르는 쪽을 막지 않는다(exit 0).
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/graph.sh"
# shellcheck disable=SC1091
[[ -f "$SCRIPT_DIR/lib/settings.sh" ]] && source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true

SCV_DIR="${SCV_DIR:-scv}"
OUT_DIR="$SCV_DIR/.graph"
GRAPH_JSON="$OUT_DIR/graph.json"
REPORT_MD="$OUT_DIR/GRAPH_REPORT.md"
US=$'\x1f'

_get() { declare -F settings_get >/dev/null 2>&1 || return 0; settings_get "$1" 2>/dev/null || true; }
_norm() { printf '%s' "${1:-}" | tr -d '"[:space:]' | tr -d "'" | tr '[:upper:]' '[:lower:]'; }
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

CMD="${1:-status}"; shift || true

if [[ "$(_norm "$(_get SCV_GRAPH)")" == "off" ]]; then echo "GRAPH_STATUS: off"; exit 0; fi
if ! command -v jq >/dev/null 2>&1; then echo "GRAPH_STATUS: unavailable"; exit 0; fi

DOCS_GLOBS="$(_get SCV_GRAPH_DOCS | tr -d '"' | tr -d "'")"
[[ -n "${DOCS_GLOBS//[[:space:]]/}" ]] || DOCS_GLOBS="docs README.md README.*.md core/contracts"

# 문서 목록 — 폴더는 안의 *.md 전부(심볼릭 링크 제외), 그 외는 글롭.
_docs() {
  local g f
  for g in $DOCS_GLOBS; do
    if [[ -d "$g" ]]; then
      find "$g" -type f -name '*.md' ! -path '*/node_modules/*' 2>/dev/null
    else
      for f in $g; do [[ -f "$f" && ! -L "$f" ]] && printf '%s\n' "$f"; done
    fi
  done | sed 's#^\./##' | LC_ALL=C sort -u
}
_plans() {  # "<path>\x1f<active>"
  local d
  for d in "$SCV_DIR"/archive/*/; do [[ -f "$d/PLAN.md" ]] && printf '%s%s0\n' "${d%/}/PLAN.md" "$US"; done
  for d in "$SCV_DIR"/promote/*/; do [[ -f "$d/PLAN.md" ]] && printf '%s%s1\n' "${d%/}/PLAN.md" "$US"; done
}
_newest_source_mtime() {
  local f m best=0
  while IFS= read -r f; do [[ -n "$f" ]] || continue; m="$(_mtime "$f")"; (( m > best )) && best=$m; done < <(_docs; _plans | cut -d"$US" -f1; [[ -f "$SCV_DIR/DECISIONS.md" ]] && echo "$SCV_DIR/DECISIONS.md"; [[ -f "$SCV_DIR/scv_settings.json" ]] && echo "$SCV_DIR/scv_settings.json")
  printf '%s' "$best"
}
_status() {
  local ex=0; [[ -f "$GRAPH_JSON" ]] && ex=1
  scv_graph_status_of "$ex" "$(_mtime "$GRAPH_JSON")" "$(_newest_source_mtime)"
}
_build() {
  local links="" touches="" refs="" docs="" f p a slug rec exists="" now
  docs="$(_docs)"
  while IFS= read -r f; do [[ -n "$f" ]] || continue; links+="$(scv_graph_doc_links "$f" "$(<"$f")")"$'\n'; done <<<"$docs"
  # 계획 전부를 awk 한 번으로 — 파일마다 프로세스를 띄우면 55개 계획에 0.7초가 든다.
  local -a plan_files=()
  while IFS="$US" read -r p a; do [[ -n "$p" ]] && plan_files+=("$p"); done < <(_plans)
  if (( ${#plan_files[@]} )); then
    touches="$(scv_graph_plans_batch "$(awk -v us="$US" "$_SCV_GRAPH_AWK_PLAN" "${plan_files[@]}")")"$'\n'
  fi
  [[ -f "$SCV_DIR/DECISIONS.md" ]] && refs="$(scv_graph_decision_refs "$(<"$SCV_DIR/DECISIONS.md")")"
  # 존재하는 경로 목록 — 링크 대상·계획 파일 후보 중 실제로 있는 것
  while IFS= read -r f; do [[ -n "$f" && -e "$f" ]] && exists+="$f"$'\n'; done < <( { printf '%s\n' "$docs"; printf '%s\n' "$links" | cut -d"$US" -f2; printf '%s\n' "$touches" | awk -F"$US" '{print $5}' | tr ' ' '\n'; } | LC_ALL=C sort -u )
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
  local json
  json="$(scv_graph_build "$links" "$touches" "$refs" "$exists" "$docs" "$DOCS_GLOBS" "$now")" || { echo "graph: build failed" >&2; echo "GRAPH_STATUS: unavailable"; return 0; }
  if ! mkdir -p "$OUT_DIR" 2>/dev/null; then echo "graph: cannot write $OUT_DIR" >&2; echo "GRAPH_STATUS: unavailable"; return 0; fi
  printf '%s\n' "$json" > "$GRAPH_JSON.tmp" && mv -f "$GRAPH_JSON.tmp" "$GRAPH_JSON" || { echo "graph: cannot write $GRAPH_JSON" >&2; rm -f "$GRAPH_JSON.tmp"; echo "GRAPH_STATUS: unavailable"; return 0; }
  scv_graph_report "$json" > "$REPORT_MD" 2>/dev/null || true
  echo "GRAPH_STATUS: built"
}

case "$CMD" in
  build)  _build ;;
  status) echo "GRAPH_STATUS: $(_status)" ;;
  ensure) s="$(_status)"; if [[ "$s" == "built" ]]; then echo "GRAPH_STATUS: built"; else _build; fi ;;
  impact)
    mode=text; [[ "${1:-}" == "--json" ]] && { mode=json; shift; }
    [[ $# -gt 0 ]] || { echo "usage: graph.sh impact [--json] <path>…" >&2; exit 2; }
    [[ -f "$GRAPH_JSON" ]] || _build >/dev/null
    [[ -f "$GRAPH_JSON" ]] || { echo "GRAPH_STATUS: unavailable"; exit 0; }
    scv_graph_impact "$(cat "$GRAPH_JSON")" "$mode" "$@" ;;
  report) [[ -f "$REPORT_MD" ]] && cat "$REPORT_MD" || echo "GRAPH_STATUS: missing" ;;
  -h|--help|help) sed -n '2,12p' "$0" ;;
  *) echo "usage: graph.sh build|status|ensure|impact [--json] <path>…|report" >&2; exit 2 ;;
esac
exit 0
