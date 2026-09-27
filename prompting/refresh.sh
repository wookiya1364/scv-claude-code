#!/usr/bin/env bash
# refresh.sh — 모델별 공식 프롬프팅 가이드의 오프라인 사본을 원본에서 다시 가져온다.
#
# SCV help 가 지금 답하는 모델의 가이드를 읽고 요청을 그 가이드 기준으로 다시 쓴다
# (scv-core protocols/help/prompt-refine.md). 이 폴더가 그 원문을 들고 있다 — 인터넷 없이 읽히도록.
# 색인 INDEX.tsv 의 각 행(모델 id · 키 · 파일 · 원본 주소 · 가져온 날짜)의 원본 .md 를 받아
# 머리 표기(출처 · 날짜 · 저작권자)만 붙이고 본문은 그대로 쓴 뒤, 그 행의 날짜를 오늘로 바꾼다.
#
# Usage: bash prompting/refresh.sh [--dry-run]
# 맥·리눅스 공통: curl · mktemp · awk 만 쓴다(sed -i 없음). 받기에 실패한 파일은 그대로 두고 알린다.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX="$DIR/INDEX.tsv"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
[[ -f "$INDEX" ]] || { echo "refresh: no INDEX.tsv in $DIR" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "refresh: curl is required" >&2; exit 1; }
TODAY="$(date +%Y-%m-%d)"
HOLDER="$(awk -F'\t' '$1=="@holder"{print $2; exit}' "$INDEX")"; HOLDER="${HOLDER:-the publisher}"

ok=0; bad=0; done_files=" "
while IFS=$'\t' read -r mid key file url fetched || [[ -n "$mid" ]]; do
  [[ -z "$mid" || "$mid" == \#* || "$mid" == @* ]] && continue
  [[ -n "$file" && -n "$url" ]] || continue
  [[ "$done_files" == *" $file "* ]] && continue
  done_files+="$file "
  if (( DRY )); then echo "would fetch: $url -> $file"; continue; fi
  tmp="$(mktemp "$DIR/.refresh.XXXXXX")" || { bad=$((bad + 1)); continue; }
  if curl -fsSL --max-time 60 "$url" -o "$tmp.body" && [[ -s "$tmp.body" ]]; then
    {
      printf '<!--\n'
      printf 'Source: %s\n' "$url"
      printf 'Fetched: %s\n' "$TODAY"
      printf 'Copyright: %s. Verbatim copy of the official documentation, kept offline for SCV help. Do not edit; run prompting/refresh.sh to update.\n' "$HOLDER"
      printf -- '-->\n\n'
      cat "$tmp.body"
    } > "$tmp" && mv -f "$tmp" "$DIR/$file" && ok=$((ok + 1)) && echo "fetched: $file"
  else
    bad=$((bad + 1)); echo "FAILED: $url (kept the old copy of $file)" >&2
  fi
  rm -f "$tmp" "$tmp.body"
done < "$INDEX"
(( DRY )) && exit 0

# 받은 파일의 행만 날짜를 오늘로 — 실패한 행은 옛 날짜를 둬서 help 의 "오래됨" 안내가 계속 뜨게 한다.
ntmp="$(mktemp "$DIR/.index.XXXXXX")" || exit 1
awk -F'\t' -v OFS='\t' -v today="$TODAY" -v dir="$DIR" '
  /^#/ || /^@/ || NF < 5 { print; next }
  { cmd = "head -c 400 \"" dir "/" $3 "\" 2>/dev/null | grep -c \"^Fetched: " today "$\""; cmd | getline n; close(cmd)
    if (n > 0) $5 = today; print }
' "$INDEX" > "$ntmp" && mv -f "$ntmp" "$INDEX"
echo "refresh: $ok fetched, $bad failed"
(( bad == 0 ))
