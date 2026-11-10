#!/usr/bin/env bash
# test-prompting-guides.sh — 모델별 프롬프팅 가이드가 **실제 실행 위치**에서 찾아지는지 본다.
#
# 왜: help 스킬은 플러그인 최상위의 scripts/help.sh 를 부른다(벤더 코어 사본이 아니라 투영본). 그래서
# 호스트 프로필의 SCV_PROMPTING_GUIDES 는 플러그인 최상위 기준이어야 한다. 0.59.0 은 벤더 코어 기준
# ("../../../prompting")으로 적어 실제 대화에서 GUIDE: none 이 됐다(실측으로 발견). 이 검사가 그 모양을 잠근다.
#
# 확인: (1) prompting/check.sh (색인 · 머리 표기 · 중복 id) (2) 색인의 모델 id 마다 플러그인 최상위 help.sh 가
# GUIDE: load <키> 와 실제로 있는 GUIDE_FILE 을 낸다 (3) 끝의 [..] 표기가 붙은 id 도 같다 (4) 색인에 없는 모델은 공통 원문만(코어 0.88.0+).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0; n=0
err() { echo "✖ $*" >&2; fail=1; }
bash "$ROOT/prompting/check.sh" || err "prompting/check.sh failed"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/scv/journal"
run_help() { (cd "$WORK" && bash "$ROOT/scripts/help.sh" --with-context --model "$1" 2>/dev/null); }
while IFS=$'\t' read -r mid key file url fetched || [[ -n "$mid" ]]; do
  [[ -z "$mid" || "$mid" == \#* || "$mid" == @* || "$mid" == "*" ]] && continue
  n=$((n + 1))
  for id in "$mid" "$mid[1m]"; do
    out="$(run_help "$id")"
    grep -qx "GUIDE: load $key" <<<"$out" || { err "$id → expected 'GUIDE: load $key', got: $(grep '^GUIDE' <<<"$out" | head -1)"; continue; }
    grep -qx "GUIDE_FILE: $ROOT/prompting/$file" <<<"$out" || err "$id → GUIDE_FILE for $file missing"
    while IFS= read -r g; do [[ -f "${g#GUIDE_FILE: }" ]] || err "$id → listed file does not exist: ${g#GUIDE_FILE: }"; done < <(grep '^GUIDE_FILE: ' <<<"$out")
  done
done < "$ROOT/prompting/INDEX.tsv"
# 코어 0.88.0+ — 색인에 없는 모델은 공통(*) 원문만 읽는다(그 발췌본 하나). 공통 행이 없는 색인이면 none.
ckey="$(awk -F'\t' '$1=="*"{print $2; exit}' "$ROOT/prompting/INDEX.tsv")"
uout="$(run_help no-such-model-xyz)"
if [[ -n "$ckey" ]]; then
  grep -qx "GUIDE: load $ckey" <<<"$uout" || err "unknown model should load the common guide ($ckey), got: $(grep '^GUIDE:' <<<"$uout" | head -1)"
  [[ "$(grep -c '^GUIDE_FILE: ' <<<"$uout")" == 1 ]] || err "unknown model should list exactly one file (the common guide)"
  while IFS= read -r g; do [[ -f "${g#GUIDE_FILE: }" ]] || err "unknown model → listed file does not exist: ${g#GUIDE_FILE: }"; done < <(grep '^GUIDE_FILE: ' <<<"$uout")
else
  [[ "$(grep '^GUIDE:' <<<"$uout")" == "GUIDE: none" ]] || err "unknown model should be GUIDE: none"
fi
(( n > 0 )) || err "no model rows in INDEX.tsv"
(( fail )) && exit 1
echo "OK prompting guides resolve from the plugin root: $n model id(s) (+[1m] variants), unknown → common guide"
