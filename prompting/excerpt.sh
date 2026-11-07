#!/usr/bin/env bash
# excerpt.sh — 가이드 원문에서 요구 항목 인용이 든 구역만 원문 그대로 뽑은 발췌본을 만든다.
#
# SCV help 는 원문 옆에 excerpt-<원문> 이 있으면 원문 대신 그것을 읽는다(core 0.83.0+). 압축 · 세션 시작마다
# 다시 읽는 양을 줄이려는 것 — 원문 사본은 그대로 두고 검사의 기준으로 남는다.
# 목록 excerpt-<이름>.sections 한 줄에 원문의 '## ' 또는 '### ' 제목 하나. 그 제목부터 다음 '##' · '###' 제목 전까지를
# 원문 순서대로 옮기고, 원문의 머리 표기(Source · Fetched · Copyright)에 Excerpt 한 줄을 더한다.
#
# Usage: bash prompting/excerpt.sh            목록마다 발췌본을 다시 쓴다
#        bash prompting/excerpt.sh --check    발췌본이 지금 원문 · 목록으로 다시 뽑은 것과 같은지만 본다(다르면 exit 1)
# 맥·리눅스 공통: awk(정규식 반복 {n,m} 없이) · cmp · mktemp 만 쓴다.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK=0; [[ "${1:-}" == "--check" ]] && CHECK=1

# @pure
# 역할: 원문과 구역 목록으로 발췌본 본문을 낸다
# 종류: 변환
# 예: 원문(머리 표기 + '### A' · '### B') + 목록('### B') → 머리 표기 + Excerpt 줄 + '### B' 구역
_excerpt() {
  awk -v listf="$2" '
    BEGIN { while ((getline l < listf) > 0) if (l ~ /^###? /) want[l] = 1 }
    NR == 1 && $0 == "<!--" { head = 1 }
    head { if ($0 == "-->") { print "Excerpt: only the sections named in the excerpt list, each copied verbatim from this source."; head = 0 } print; next }
    /^###? / { on = ($0 in want) }
    on { print }
  ' "$1"
}

n=0; bad=0
for list in "$DIR"/excerpt-*.sections; do
  [[ -f "$list" ]] || continue
  stem="$(basename "$list" .sections)"; stem="${stem#excerpt-}"
  src="$DIR/$stem.md"; out="$DIR/excerpt-$stem.md"
  [[ -f "$src" ]] || { echo "✖ excerpt: no source $stem.md for $(basename "$list")" >&2; bad=1; continue; }
  tmp="$(mktemp "$DIR/.excerpt.XXXXXX")" || exit 1
  _excerpt "$src" "$list" > "$tmp"
  # 목록의 제목마다 원문에 그 제목 줄이 있어야 한다 — 오타로 구역이 조용히 빠지지 않게
  while IFS= read -r h || [[ -n "$h" ]]; do
    [[ "$h" == "## "* || "$h" == "### "* ]] || continue
    grep -qxF -- "$h" "$src" || { echo "✖ excerpt: heading not in $stem.md: $h" >&2; bad=1; }
  done < "$list"
  if (( CHECK )); then
    cmp -s "$tmp" "$out" || { echo "✖ excerpt-$stem.md differs from what excerpt.sh makes now (run prompting/excerpt.sh)" >&2; bad=1; }
    rm -f "$tmp"
  else
    mv -f "$tmp" "$out" && echo "excerpt: excerpt-$stem.md ($(wc -c < "$out" | tr -d ' ') bytes, source $(wc -c < "$src" | tr -d ' '))"
  fi
  n=$((n + 1))
done
(( bad )) && exit 1
(( CHECK )) && echo "OK excerpts: $n"
exit 0
