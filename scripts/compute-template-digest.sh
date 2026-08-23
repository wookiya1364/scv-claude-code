#!/usr/bin/env bash
# compute-template-digest.sh — 템플릿 트리의 지문을 계산해 한 줄로 낸다.
#
# 왜 필요한가: 자동 갱신이 번호가 아니라 내용으로 판단하게 하려면, 배포본이 자기
# 템플릿의 지문을 들고 있어야 한다. 번호를 올리는 걸 잊어도 내용이 바뀌었으면
# 지문이 달라지므로 반드시 갱신된다.
#
# 무엇을 해싱하나: 템플릿 디렉터리 아래의 모든 파일. 경로는 템플릿 디렉터리 기준
# 상대 경로다 — 절대 경로가 섞이면 기계마다 지문이 달라진다. 수정 시각·권한·소유자는
# 애초에 입력에 넣지 않는다.
#
# 순수부는 lib/template-digest.sh 의 scv_digest_fold 가 맡는다. 이 스크립트는
# 파일을 읽어 그 함수에 넘기는 바깥층이다.
#
# Usage:
#   compute-template-digest.sh [--template-dir DIR]
#   compute-template-digest.sh --check FILE   # FILE 의 값과 비교, 다르면 exit 1
#
# Output: 64자리 16진수 한 줄.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/template-digest.sh
source "$SCRIPT_DIR/lib/template-digest.sh"

TEMPLATE_DIR="$SCRIPT_DIR/../template"
CHECK_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template-dir)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "✖ --template-dir requires DIR" >&2; exit 2; }
      TEMPLATE_DIR="$2"; shift 2 ;;
    --check)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "✖ --check requires FILE" >&2; exit 2; }
      CHECK_FILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "✖ unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$TEMPLATE_DIR" ]] || { echo "✖ template dir not found: $TEMPLATE_DIR" >&2; exit 1; }
TEMPLATE_DIR="$( cd "$TEMPLATE_DIR" && pwd )"

hash_one() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# 템플릿 디렉터리 기준 상대 경로 + 파일 내용 해시. 심볼릭 링크는 따라가지 않고
# 링크가 가리키는 문자열 자체를 내용으로 본다 (링크 대상은 우리 소유가 아니다).
DIGEST="$(
  cd "$TEMPLATE_DIR" || exit 1
  find . \( -type f -o -type l \) -print \
  | LC_ALL=C sort \
  | while IFS= read -r rel; do
      if [[ -L "$rel" ]]; then
        printf '%s  %s\n' "$(printf 'symlink:%s' "$(readlink "$rel")" | hash_one /dev/stdin)" "$rel"
      else
        printf '%s  %s\n' "$(hash_one "$rel")" "$rel"
      fi
    done \
  | scv_digest_fold
)"

if [[ -z "$DIGEST" || ! "$DIGEST" =~ ^[0-9a-f]{64}$ ]]; then
  echo "✖ digest computation failed (got: ${DIGEST:-empty})" >&2
  exit 1
fi

if [[ -n "$CHECK_FILE" ]]; then
  STORED=""
  [[ -f "$CHECK_FILE" ]] && STORED="$(tr -d '[:space:]' < "$CHECK_FILE")"
  if [[ "$STORED" == "$DIGEST" ]]; then
    echo "OK  template digest matches: $DIGEST"
    exit 0
  fi
  echo "✖ template digest is STALE" >&2
  echo "    stored:   ${STORED:-(none)}" >&2
  echo "    computed: $DIGEST" >&2
  echo "    fix: bash core/scripts/compute-template-digest.sh > core/TEMPLATE_DIGEST" >&2
  exit 1
fi

printf '%s\n' "$DIGEST"
