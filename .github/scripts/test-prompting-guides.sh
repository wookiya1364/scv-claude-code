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
# 코어 0.89.0+ — 권장 effort 요청: 이 호스트의 실제 세션 기록 모양(답 줄의 "perTurnEffort":"<값>")에서 지금 값을 읽어,
# 그 모델의 권장 값과 다르면 싣는다. 프로필의 키 이름이 기록 모양과 어긋나면 여기서 붉다(조용히 꺼지지 않게).
# 코어 0.89.2+ — 줄을 실은 것만으로는 '물었다'가 아니다. 모델이 실제로 물은 턴(선택 창의 질문 글이 코어에 닿은 턴) 뒤에만
# 다시 싣지 않고, 묻지 않았으면 다음 턴에 다시 싣는다. 그래서 두 장면을 본다: 물은 턴 → 1 · 0, 안 물은 턴 → 1 · 1.
neff=0
if [[ -f "$ROOT/prompting/EFFORT.tsv" ]]; then
  MPS="$ROOT/scripts/model-prompting.sh"
  eff_case() {  # <이름> <모델> <기록의 값> <asked|silent> [권장 값] → 매 턴 안내를 두 번 돌려 "첫 번째 요청 수 · 두 번째 요청 수 · 첫 안내 글" 을 낸다
    local d="$WORK/eff-$1" tr o1 o2
    mkdir -p "$d/scv/journal"; (cd "$d" && git init -q . 2>/dev/null)
    printf '{"session":"s1","protocol":1,"turn":1,"diag":"","diag_at":"","nonce":"abcd1234"}\n' > "$d/scv/journal/.help-state"
    tr="$d/tr.jsonl"
    printf '{"type":"user","message":{"content":[{"type":"text","text":"q"}]}}\n{"type":"assistant","effort":"%s","perTurnEffort":"%s","message":{"model":"%s","content":[{"type":"text","text":"a"}]}}\n' "$3" "$3" "$2" > "$tr"
    (cd "$d" && bash "$MPS" human --session s1 >/dev/null 2>&1; bash "$MPS" guide --model "$2" --session s1 >/dev/null 2>&1) || true
    o1="$(cd "$d" && bash "$MPS" prompt --session s1 --transcript "$tr" 2>/dev/null)"
    # 물은 턴: 선택 창 답 훅이 하는 것처럼 그 질문 글을 코어에 넘긴다. 안 물은 턴: 아무것도 넘기지 않는다.
    if [[ "${4:-silent}" == asked ]]; then
      (cd "$d" && printf '%s' "effort 를 ${5:-high} 로 바꾸시겠어요?" | bash "$MPS" effort-seen --session s1 >/dev/null 2>&1) || true
    fi
    o2="$(cd "$d" && bash "$MPS" prompt --session s1 --transcript "$tr" 2>/dev/null)"
    printf '%s %s\n%s' "$(grep -c '^\[SCV effort\]' <<<"$o1")" "$(grep -c '^\[SCV effort\]' <<<"$o2")" "$o1"
  }
  while IFS=$'\t' read -r emid erec econd equote esrc || [[ -n "$emid" ]]; do
    [[ -z "$emid" || "$emid" == \#* ]] && continue
    neff=$((neff + 1))
    other=low; [[ "$erec" == low ]] && other=high
    r="$(eff_case "d$neff" "$emid" "$other" asked "$erec")"
    [[ "$(head -1 <<<"$r")" == "1 0" ]] || err "effort: $emid at $other (recommended $erec) should be carried once, then not again after it was asked — got '$(head -1 <<<"$r")'"
    grep -q "effort 는 $other 인데" <<<"$r" && grep -q "권하는 값은 $erec 이다" <<<"$r" || err "effort: $emid — the line must name $other and $erec"
    grep -qF -- "\"$equote\"" <<<"$r" || err "effort: $emid — the guide's sentence must be carried verbatim"
    [[ "$econd" == "-" ]] || grep -qxF "조건: $econd" <<<"$r" || err "effort: $emid — the condition must be carried"
    r="$(eff_case "n$neff" "$emid" "$other" silent)"
    [[ "$(head -1 <<<"$r")" == "1 1" ]] || err "effort: $emid at $other, not asked → should be carried again on the next turn (core 0.89.2) — got '$(head -1 <<<"$r")'"
    r="$(eff_case "s$neff" "$emid" "$erec" silent)"
    [[ "$(head -1 <<<"$r")" == "0 0" ]] || err "effort: $emid at $erec (the recommended value) should not be asked — got '$(head -1 <<<"$r")'"
  done < "$ROOT/prompting/EFFORT.tsv"
  r="$(eff_case unknown no-such-model-xyz low silent)"
  [[ "$(head -1 <<<"$r")" == "0 0" ]] || err "effort: a model with no row should not be asked"
  (( neff > 0 )) || err "EFFORT.tsv has no rows"
fi
(( n > 0 )) || err "no model rows in INDEX.tsv"
(( fail )) && exit 1
echo "OK prompting guides resolve from the plugin root: $n model id(s) (+[1m] variants), unknown → common guide$( (( neff > 0 )) && echo ", effort: asked → once, not asked → again, for $neff model(s)")"
