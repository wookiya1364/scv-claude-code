#!/usr/bin/env bash
# check.sh — 모델별 프롬프팅 가이드 폴더가 온전한지 본다 (SCV help 가 읽는 오프라인 사본).
#
#   bash prompting/check.sh            오프라인: 색인 행마다 파일이 있고, 머리 표기(Source · Fetched · Copyright)가
#                                      색인과 맞고, 모델 id 가 겹치지 않는지
#   bash prompting/check.sh --online   위 + 각 원문 본문이 원본(.md)과 바이트 단위로 같은지 (가져온 날 기준)
# 맥·리눅스 공통. 통과하면 "OK prompting guides: <n> model id(s), <m> file(s)" 를 찍고 exit 0.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX="$DIR/INDEX.tsv"; ONLINE=0; [[ "${1:-}" == "--online" ]] && ONLINE=1
fail=0; ids=" "; files=" "; nid=0; nfile=0
err() { echo "✖ $*" >&2; fail=1; }
[[ -f "$INDEX" ]] || { err "no INDEX.tsv"; exit 1; }
HOLDER="$(awk -F'\t' '$1=="@holder"{print $2; exit}' "$INDEX")"
[[ -n "$HOLDER" ]] || err "INDEX.tsv has no @holder row"
REFRESH="$(awk -F'\t' '$1=="@refresh"{print $2; exit}' "$INDEX")"
[[ -n "$REFRESH" && -f "$DIR/$REFRESH" ]] || err "INDEX.tsv @refresh missing or points at no file"
while IFS=$'\t' read -r mid key file url fetched || [[ -n "$mid" ]]; do
  [[ -z "$mid" || "$mid" == \#* || "$mid" == @* ]] && continue
  [[ -n "$key" && -n "$file" && -n "$url" && "$fetched" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { err "bad row: $mid"; continue; }
  if [[ "$mid" != "*" ]]; then
    [[ "$ids" == *" $mid "* ]] && err "duplicate model id: $mid"
    ids+="$mid "; nid=$((nid + 1))
  fi
  [[ "$file" == */* || "$file" == .* ]] && { err "file must be a plain name in this folder: $file"; continue; }
  [[ -f "$DIR/$file" ]] || { err "missing file: $file"; continue; }
  [[ "$files" == *" $file "* ]] && continue
  files+="$file "; nfile=$((nfile + 1))
  head -n 6 "$DIR/$file" | grep -qxF "Source: $url" || err "$file: Source line does not match the index"
  head -n 6 "$DIR/$file" | grep -qxF "Fetched: $fetched" || err "$file: Fetched line does not match the index ($fetched)"
  head -n 6 "$DIR/$file" | grep -q "^Copyright: $HOLDER\. Verbatim copy" || err "$file: Copyright line missing"
  if (( ONLINE )); then
    start="$(grep -n '^-->$' "$DIR/$file" | head -1 | cut -d: -f1)"
    tmpl="$(mktemp)"; tmpr="$(mktemp)"
    tail -n +$((start + 2)) "$DIR/$file" > "$tmpl"
    if curl -fsSL --max-time 60 "$url" -o "$tmpr"; then
      cmp -s "$tmpl" "$tmpr" || err "$file: body differs from the source today (run $REFRESH)"
    else
      err "$file: could not fetch $url"
    fi
    rm -f "$tmpl" "$tmpr"
  fi
done < "$INDEX"
# v0.62.0+ (core) — 요구 항목 목록: 색인의 키마다 checklist-<키>.tsv 가 있고, 첫 줄 출처가 그 키의 원문이며,
# 항목마다 id · label · 인용이 있고, 인용이 그 원문에 글자 그대로 있는지(매 턴 1:1 비교의 기준이 원문에서 왔다는 증거).
nitem=0; seenkeys=" "
while IFS=$'\t' read -r mid key file url fetched || [[ -n "$mid" ]]; do
  [[ -z "$mid" || "$mid" == \#* || "$mid" == @* || -z "$key" || -z "$file" ]] && continue
  [[ "$seenkeys" == *" $key "* ]] && continue; seenkeys+="$key "
  cl="$DIR/checklist-$key.tsv"
  [[ -f "$cl" ]] || { err "missing checklist: checklist-$key.tsv"; continue; }
  head -1 "$cl" | grep -qxF "# source: $file" || err "checklist-$key.tsv: first line must be '# source: $file'"
  while IFS=$'\t' read -r cid clabel cquote extra || [[ -n "$cid" ]]; do
    [[ -z "$cid" || "$cid" == \#* ]] && continue
    [[ "$cid" =~ ^[a-z0-9-]+$ && -n "$clabel" && -n "$cquote" && -z "${extra:-}" ]] || { err "checklist-$key.tsv: bad line: $cid"; continue; }
    grep -qF -- "$cquote" "$DIR/$file" || err "checklist-$key.tsv: $cid quote is not verbatim in $file"
    nitem=$((nitem + 1))
  done < "$cl"
done < "$INDEX"
(( fail )) && exit 1
echo "OK prompting guides: $nid model id(s), $nfile file(s), $nitem checklist item(s)$( (( ONLINE )) && echo ', bodies match the source')"
