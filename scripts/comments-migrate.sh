#!/usr/bin/env bash
# comments-migrate.sh — 프로젝트 코드의 주석을 순수 함수 사전으로 옮기고 코드에서 지운다 (0.98.0+, 계획 comments-to-catalog).
#
#   comments-migrate.sh files [--root DIR]     옮길 대상 코드 파일(저장소 추적 파일 · 언어 sh/js/ts/py/rs/go · 의존성 · 생성물 ·
#                                              scv 폴더 제외)을 절대 경로로 한 줄씩
#   comments-migrate.sh run [--root DIR] [--dry-run]
#                                              옮기기: 표식 → 사전 항목, @effect → effects.md, 그 밖의 설명 · 도구 표시 줄 →
#                                              notes.md, 그리고 코드에서 주석을 지운다. 사전 폴더에 SOURCE 표시를 남긴다(사전이 원본).
#                                              옮긴 뒤 사전 항목 수가 옮기기 전보다 적으면 코드를 건드리지 않고 멈춘다.
#   comments-migrate.sh auto [--root DIR]      설정 SCV_CATALOG_SOURCE 가 off 가 아닌데(기본 on) 아직 옮기지 않은 프로젝트면 run 을 한 번 돌리고
#                                              보고 한 줄을 낸다. 그 밖에는 아무것도 하지 않는다(매 턴 진단이 부른다).
#
# 커밋은 하지 않는다 — 옮긴 결과는 사람이 보고 커밋한다(되돌리기: git checkout -- .).
# Exit: 0 · 1 멈춤(잃는 항목 · 도구 없음) · 2 사용법
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true

MODE="${1:-}"; shift || true
ROOT="."; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-.}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "comments-migrate.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
ROOT="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || { [[ "$MODE" == auto ]] && exit 0; echo "✖ git 저장소가 아니다: $ROOT" >&2; exit 2; }
CATALOG="$ROOT/scv/core/catalog/pure"
EXCLUDE="${SCV_COMMENTS_EXCLUDE:-node_modules vendor dist build target scv .git}"

# @pure cm_field
# 역할: 탭으로 나뉜 '이름=값' 줄에서 한 이름의 값을 꺼낸다(없으면 빈 값)
# 종류: 꺼내기/catalog
# 예: $'MIGRATE\tfiles=3\tnotes=2' "notes" → "2"
# 예: $'MIGRATE\tfiles=3' "x" → ""
cm_field() {
  local line="${1:-}" key="${2:-}" part
  local IFS=$'\t'
  for part in $line; do
    [[ "$part" == "$key="* ]] && { printf '%s' "${part#"$key="}"; return 0; }
  done
  return 0
}

# @effect cm_files
# 이유: 저장소의 추적 파일 목록을 읽는다
cm_files() {
  local f seg skip
  git -C "$ROOT" ls-files 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    case "$f" in *.sh|*.bash|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.mts|*.cts|*.py|*.rs|*.go) ;; *) continue ;; esac
    skip=0
    for seg in $EXCLUDE; do [[ "/$f" == *"/$seg/"* ]] && { skip=1; break; }; done
    [[ $skip -eq 0 && -f "$ROOT/$f" ]] && printf '%s\n' "$ROOT/$f"
  done
}

# @effect cm_catalog_keys
# 이유: 사전 파일을 읽어 순수 함수 항목의 '파일<탭>이름' 줄을 낸다
cm_catalog_keys() {
  local f
  for f in "$CATALOG"/*.md; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in INDEX.md|effects.md|notes.md) continue ;; esac
    LC_ALL=C awk '/^### /{n=substr($0,5)} /^- 위치: /{v=$0; sub(/^- 위치: /,"",v); split(v,p," · "); print p[1] "\t" n}' "$f"
  done
}

# @effect cm_run
# 이유: 사전 파일을 쓰고 코드 파일에서 주석을 지운다
cm_run() {
  command -v python3 >/dev/null 2>&1 || { echo "✖ python3 가 없다 — 옮기기를 할 수 없다" >&2; return 1; }
  local tmp list ents before after summary merged
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/scv-cm.XXXXXX")" || return 1
  list="$tmp/files"; ents="$tmp/entries.tsv"
  cm_files > "$list"
  # 옮기기 전 사전 — 아직 원본이 아니면 코드 표식에서 한 번 만들어 둔다(잃는 항목 비교의 기준).
  [[ -f "$CATALOG/SOURCE" ]] || bash "$SCRIPT_DIR/pure-catalog.sh" build --project "$ROOT" >/dev/null 2>&1 || true
  before="$(cm_catalog_keys | LC_ALL=C sort -u | grep -c . || true)"
  if (( DRY )); then
    summary="$(python3 -I "$SCRIPT_DIR/code-comments.py" migrate --root "$ROOT" --list "$list" --catalog "$CATALOG" --entries-out "$ents")"
    printf '%s\tcatalog_before=%s\tdry_run=1\n' "$summary" "${before:-0}"
    rm -rf "$tmp"; return 0
  fi
  # 잃는 항목이 없는지 먼저 본다: 쓰지 않고 뽑기만 해서 합친 수를 세고, 적으면 코드를 건드리지 않는다.
  python3 -I "$SCRIPT_DIR/code-comments.py" migrate --root "$ROOT" --list "$list" --catalog "$tmp/probe" --entries-out "$ents" --write-entries-only >/dev/null
  merged="$( { LC_ALL=C awk -F'\t' 'NF >= 3 { print $1 "\t" $3 }' "$ents" 2>/dev/null; cm_catalog_keys; } | LC_ALL=C sort -u | grep -c . || true)"
  if [[ "${merged:-0}" -lt "${before:-0}" ]]; then
    echo "✖ 옮긴 뒤 사전 항목($merged)이 옮기기 전($before)보다 적다 — 코드를 건드리지 않고 멈춘다" >&2
    rm -rf "$tmp"; return 1
  fi
  summary="$(python3 -I "$SCRIPT_DIR/code-comments.py" migrate --root "$ROOT" --list "$list" --catalog "$CATALOG" --entries-out "$ents" --write)"
  bash "$SCRIPT_DIR/pure-catalog.sh" import --project "$ROOT" --entries "$ents" >/dev/null 2>&1 || { echo "✖ 사전 쓰기 실패" >&2; rm -rf "$tmp"; return 1; }
  after="$(cm_catalog_keys | LC_ALL=C sort -u | grep -c . || true)"
  printf '%s\tcatalog_before=%s\tcatalog_after=%s\n' "$summary" "${before:-0}" "${after:-0}"
  rm -rf "$tmp"
}

case "$MODE" in
  files) cm_files ;;
  run) cm_run ;;
  auto)
    _sw=""; declare -F settings_get >/dev/null 2>&1 && _sw="$(cd "$ROOT" && settings_get SCV_CATALOG_SOURCE 2>/dev/null | tr -d '"[:space:]' | tr '[:upper:]' '[:lower:]')"
    # 기본 on — 키가 없으면(새로 설치 · 업데이트) 켬, 적힌 off 는 그대로 존중한다.
    [[ "$_sw" != off && -d "$ROOT/scv" && ! -f "$CATALOG/SOURCE" ]] || exit 0
    _out="$(cm_run 2>&1)" || { printf '[SCV 주석 옮김] 멈춤 — %s\n' "$(printf '%s' "$_out" | tail -1)"; exit 0; }
    _l="$(printf '%s\n' "$_out" | grep '^MIGRATE' | tail -1)"
    printf '[SCV 주석 옮김] 코드 파일 %s개에서 주석 %s줄을 지우고 사전(scv/core/catalog/pure)으로 옮김 — 순수 함수 %s개 · 부수효과 %s개 · 메모 %s개. 사전이 이제 원본이다. 커밋은 직접(되돌리기: git checkout -- .).\n' \
      "$(cm_field "$_l" files)" "$(cm_field "$_l" comment_lines)" "$(cm_field "$_l" catalog_after)" "$(cm_field "$_l" effects)" "$(cm_field "$_l" notes)"
    ;;
  *) sed -n '2,15p' "$0" >&2; exit 2 ;;
esac
