#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: generate-manifest.sh --root EXPORT_ROOT" >&2
}

ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
[[ -d "$ROOT/core" && -f "$ROOT/VERSION" ]] || { usage; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "sha256sum or shasum is required" >&2
    return 1
  fi
}

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
CORE_API="$(tr -d '[:space:]' < "$ROOT/CORE_API")"
TEMPLATE_VERSION="$(tr -d '[:space:]' < "$ROOT/TEMPLATE_VERSION")"
SOURCE_COMMIT=""
SOURCE_REPOSITORY=""
if [[ -f "$ROOT/SOURCE_COMMIT" ]]; then
  SOURCE_COMMIT="$(tr -d '[:space:]' < "$ROOT/SOURCE_COMMIT")"
fi
if [[ -f "$ROOT/SOURCE_INFO" ]]; then
  SOURCE_REPOSITORY="$(sed -n 's/^source_repository:[[:space:]]*//p' "$ROOT/SOURCE_INFO" | head -1)"
fi
PROFILE_ID="canonical"
if [[ -f "$ROOT/core/host-profile.env" ]]; then
  PROFILE_ID="$(sed -n 's/^SCV_HOST_ID=//p' "$ROOT/core/host-profile.env" | head -1)"
fi

# 템플릿 지문을 다시 계산해 배포본에 싣는다.
#
# 자동 갱신은 이 값으로 판단한다 — 번호가 그대로여도 템플릿 내용이 바뀌었으면
# 지문이 달라지므로 반드시 갱신된다. 번호 올리는 것을 잊어서 생기던 어긋남이
# 여기서 구조적으로 사라진다.
#
# 매니페스트 해싱보다 반드시 먼저 해야 TEMPLATE_DIGEST 자신도 해시 목록에 들어간다.
# 이 파일은 core/template/ 바깥에 있으므로 자기 값에 영향을 주지 않는다.
TEMPLATE_DIGEST=""
if [[ -f "$ROOT/core/scripts/compute-template-digest.sh" ]]; then
  bash "$ROOT/core/scripts/compute-template-digest.sh" \
    --template-dir "$ROOT/core/template" > "$ROOT/core/TEMPLATE_DIGEST"
  TEMPLATE_DIGEST="$(tr -d '[:space:]' < "$ROOT/core/TEMPLATE_DIGEST")"
fi

SUMS_TMP="$(mktemp)"
MANIFEST_TMP="$(mktemp)"
trap 'rm -f "$SUMS_TMP" "$MANIFEST_TMP"' EXIT

(
  cd "$ROOT"
  {
    printf '%s\n' VERSION CORE_API TEMPLATE_VERSION SOURCE_COMMIT SOURCE_DATE SOURCE_INFO
    find core tools \
      \( -type d \( -name node_modules -o -name dist -o -name dist-deck -o -name coverage -o -name .vite -o -name .cache \) -prune \) \
      -o \( -type f -o -type l \) -print
  } | awk '
    /^core\/DeckUI\/src\/deck\/decks\/[^\/]+\/deck\.json$/ &&
      $0 != "core/DeckUI/src/deck/decks/demo-prd/deck.json" &&
      $0 != "core/DeckUI/src/deck/decks/refund/deck.json" { next }
    NF
  ' | LC_ALL=C sort -u
) | while IFS= read -r rel; do
  [[ -e "$ROOT/$rel" || -L "$ROOT/$rel" ]] || continue
  printf '%s  %s\n' "$(hash_file "$ROOT/$rel")" "$rel"
done > "$SUMS_TMP"

{
  echo '{'
  echo '  "schema_version": 1,'
  echo '  "name": "scv-core",'
  printf '  "version": "%s",\n' "$VERSION"
  printf '  "core_api": %s,\n' "$CORE_API"
  printf '  "template_version": "%s",\n' "$TEMPLATE_VERSION"
  printf '  "template_digest": "%s",\n' "$TEMPLATE_DIGEST"
  printf '  "source_repository": "%s",\n' "$SOURCE_REPOSITORY"
  printf '  "source_commit": "%s",\n' "$SOURCE_COMMIT"
  printf '  "profile_id": "%s",\n' "$PROFILE_ID"
  echo '  "files": ['
  first=1
  while read -r hash rel; do
    size="$(wc -c < "$ROOT/$rel" | tr -d '[:space:]')"
    [[ $first -eq 1 ]] || echo ','
    printf '    {"path": "%s", "sha256": "%s", "size": %s}' "$rel" "$hash" "$size"
    first=0
  done < "$SUMS_TMP"
  echo
  echo '  ]'
  echo '}'
} > "$MANIFEST_TMP"

mv "$SUMS_TMP" "$ROOT/SHA256SUMS"
mv "$MANIFEST_TMP" "$ROOT/core-manifest.json"
trap - EXIT
echo "manifest generated: $ROOT/core-manifest.json"
