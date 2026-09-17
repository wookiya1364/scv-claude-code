#!/usr/bin/env bash
# test-graft-adapter.sh — "Graft 어댑터" 검사 (v0.51.0+).
#
# 왜 있나: Graft 는 선택 제공자다 — 없으면 아무것도 달라지지 않고(GRAFT_STATUS: absent 한 줄), 있으면 회귀 앞단에
# 정적 영향 범위(blast), 계획·구현 헤더에 관련 코드 후보(ask)가 자체 그래프 블록 아래에 덧붙는다. 이 저장소는
# bash 라 실제 graft 로 실증할 수 없으므로 가짜 graft(PATH 앞)로 계약을 검증한다.
#
# Covers TESTS.md T1~T9 of 20260917-wookiya1364-graft-adapter (T10 = 전체 검사).
# Run: bash core/tests/test-graft-adapter.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-graft-adapter: payload not found from $HERE" >&2; exit 1; }
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
US=$'\x1f'
LIB="$CORE/scripts/lib/graft.sh"; GRAFT="$CORE/scripts/graft.sh"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
[[ -f "$LIB" ]] || { echo "  ✖ FAIL: lib missing: $LIB"; echo; echo "test-graft-adapter: pass=0 fail=1"; exit 1; }
source "$LIB"
now_ms() { local n; n="$(date +%s%3N 2>/dev/null || true)"; [[ "$n" =~ ^[0-9]+$ ]] || n="$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || true)"; [[ "$n" =~ ^[0-9]+$ ]] || n=$(( $(date +%s) * 1000 )); printf '%s' "$n"; }

echo "── [T1] 상태 판정 (순수) ──"
[[ "$(scv_graft_status 0 0 auto)" == "absent" && "$(scv_graft_status 0 1 auto)" == "absent" ]] && ok "bin 없음 → absent" || fail "absent"
[[ "$(scv_graft_status 1 0 auto)" == "no-graph" ]] && ok "bin 있음·graph 없음 → no-graph" || fail "no-graph"
[[ "$(scv_graft_status 1 1 auto)" == "ready" && "$(scv_graft_status 1 1 '')" == "ready" ]] && ok "둘 다 → ready (스위치 빈값 = auto)" || fail "ready"
[[ "$(scv_graft_status 1 1 off)" == "off" && "$(scv_graft_status 0 0 off)" == "off" && "$(scv_graft_status 1 1 OFF)" == "off" ]] && ok "switch=off → off (대소문자 무관)" || fail "off"

echo "── [T2] blast 요약 (결정적) ──"
BJ='{"files":[{"path":"a.ts","symbols":["f1","f2","f3","f4"]},{"path":"b.ts","symbols":["g1","g2"]},{"path":"c.ts","symbols":["h1"]}]}'
[[ "$(scv_graft_blast_summary "$BJ")" == "3${US}7${US}a.ts:4 b.ts:2 c.ts:1" ]] && ok "파일 3·심볼 7·상위 파일(심볼 수 내림차순)" || fail "blast: $(scv_graft_blast_summary "$BJ" | tr "$US" '|')"
BJ2='{"impacted":[{"file":"x.py","symbol":"a"},{"file":"x.py","symbol":"b"},{"file":"y.py","symbol":"c"}]}'
[[ "$(scv_graft_blast_summary "$BJ2")" == "2${US}3${US}x.py:2 y.py:1" ]] && ok "impacted[] 모양도 읽는다" || fail "blast2: $(scv_graft_blast_summary "$BJ2" | tr "$US" '|')"
v="$(scv_graft_blast_summary '{"weird":1}')"; [[ "$v" == "?${US}?${US}"* && "$v" == *"11B"* ]] && ok "모르는 모양 → ?/? + 원문 크기" || fail "blast weird: $(printf '%s' "$v" | tr "$US" '|')"
[[ "$(scv_graft_blast_summary '{}')" == "0${US}0${US}" ]] && ok "빈 객체 → 0/0" || fail "blast empty: $(scv_graft_blast_summary '{}' | tr "$US" '|')"

echo "── [T3] ask 요약 (결정적) ──"
AJ="$(jq -cn '{results: [range(0;12) | {path: ("src/f" + tostring + ".ts"), line: (10 + .), label: ("sym" + tostring), score: ((. * 7) % 12 / 12)}]}')"
v="$(scv_graft_ask_summary "$AJ" 10)"; n="$(printf '%s\n' "$v" | grep -c .)"
top="$(jq -r '.results | sort_by(-.score) | .[0] | "\(.path):\(.line)"' <<<"$AJ")"
[[ "$n" == "10" && "$(printf '%s\n' "$v" | head -1 | cut -d"$US" -f1)" == "$top" ]] && ok "점수 내림차순 상위 10, path:line" || fail "ask: n=$n first=$(printf '%s\n' "$v" | head -1 | tr "$US" '|') top=$top"
[[ -z "$(scv_graft_ask_summary '{"results":[]}' 10)" ]] && ok "후보 0 → 빈 출력" || fail "ask empty"
AJ2='{"nodes":[{"file":"a.py","line":3,"name":"n1","score":0.2},{"file":"b.py","line":4,"name":"n2","score":0.9}]}'
[[ "$(scv_graft_ask_summary "$AJ2" 10 | head -1)" == "b.py:4${US}n2" ]] && ok "nodes[]/file/name 모양도 읽는다" || fail "ask2: $(scv_graft_ask_summary "$AJ2" 10 | tr "$US" '|' | tr '\n' ' ')"

# ---- 픽스처 프로젝트 + 가짜 graft ----
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-graft.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
mkfake() {  # <dir> <mode: ok|broken|slow>
  mkdir -p "$1"; cat > "$1/graft" <<EOF2
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WORK/calls.log"
case "$2" in
  broken) echo '{not json'; exit 0 ;;
  slow) sleep 30; echo '{}' ;;
  *) if [[ "\$1" == "blast" ]]; then echo '$BJ'; elif [[ "\$1" == "ask" ]]; then echo '$AJ2'; else echo '{}'; fi ;;
esac
EOF2
  chmod +x "$1/graft"
}
mkproj() { local p="$WORK/$1"; mkdir -p "$p/scv/raw" "$p/scv/promote/20260917-u-delta" "$p/scv/archive/20260901-u-alpha"; printf 'x\n' > "$p/a.ts"
  printf -- '---\ntitle: "델타 기능"\nslug: 20260917-u-delta\nstatus: planned\nkind: feature\nscope:\n  - "a.ts"\n---\n# 델타\n' > "$p/scv/promote/20260917-u-delta/PLAN.md"; printf '# T\n## How to run\n```bash\ntrue\n```\n' > "$p/scv/promote/20260917-u-delta/TESTS.md"
  printf -- '---\ntitle: "알파"\nslug: 20260901-u-alpha\nstatus: testing\nkind: feature\nscope:\n  - "a.ts"\n---\n# 알파\n' > "$p/scv/archive/20260901-u-alpha/PLAN.md"; printf '# T\n## How to run\n```bash\ntrue\n```\n' > "$p/scv/archive/20260901-u-alpha/TESTS.md"
  ( cd "$p" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm init ) 2>/dev/null; echo "$p"; }
CLEANPATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'graft' | tr '\n' ':')"
run_in() { local p="$1" fake="$2"; shift 2; ( cd "$p" && PATH="${fake:+$fake:}$CLEANPATH" "$@" 2>/dev/null ); }
WS="$CORE/scripts/work.sh"; PH="$CORE/scripts/promote-helper.sh"; RG="$CORE/scripts/regression.sh"; ID="$CORE/scripts/install-deps.sh"

echo "── [T4] graft 없음 ──"
P=$(mkproj p4); rm -f "$WORK/calls.log"
[[ "$(run_in "$P" "" bash "$GRAFT" status)" == "GRAFT_STATUS: absent" ]] && ok "status → absent" || fail "status: $(run_in "$P" "" bash "$GRAFT" status)"
[[ -z "$(run_in "$P" "" bash "$GRAFT" blast)" && -z "$(run_in "$P" "" bash "$GRAFT" ask x)" ]] && ( run_in "$P" "" bash "$GRAFT" blast; run_in "$P" "" bash "$GRAFT" ask x ) && ok "blast/ask 빈 출력, exit 0" || fail "blast/ask absent"
o="$(run_in "$P" "" bash "$WS" 20260917-u-delta)"; [[ "$(grep -c '^GRAFT_STATUS: absent' <<<"$o")" == "1" ]] && ! grep -q 'code candidates' <<<"$o" && ok "work.sh: GRAFT_STATUS: absent 한 줄, 후보 블록 없음" || fail "work absent: $(grep -n 'GRAFT\|candidates' <<<"$o" | head -3)"
o="$(run_in "$P" "" bash "$PH" --dry-run)"; grep -q '^GRAFT_STATUS: absent' <<<"$o" && ! grep -q 'code candidates' <<<"$o" && ok "promote-helper: absent 한 줄" || fail "promote absent"
o="$(run_in "$P" "" bash "$RG" --dry --changed a.ts)"; ! grep -q 'graft' <<<"$o" && ok "regression: graft 블록 없음" || fail "regression absent: $(grep -n 'graft' <<<"$o" | head -2)"

echo "── [T5] graft 있음, 그래프 없음 ──"
P=$(mkproj p5); F="$WORK/fake-ok"; mkfake "$F" ok; rm -f "$WORK/calls.log"
[[ "$(run_in "$P" "$F" bash "$GRAFT" status)" == "GRAFT_STATUS: no-graph" ]] && ok "status → no-graph" || fail "status: $(run_in "$P" "$F" bash "$GRAFT" status)"
[[ -z "$(run_in "$P" "$F" bash "$GRAFT" blast)" && ! -e "$WORK/calls.log" ]] && ok "blast 빈 출력, graft 호출 없음" || fail "no-graph 에서 호출됨: $(cat "$WORK/calls.log" 2>/dev/null)"

echo "── [T6] ready — blast 블록 ──"
P=$(mkproj p6); mkdir -p "$P/graft"; rm -f "$WORK/calls.log"
o="$(run_in "$P" "$F" bash "$RG" --dry --changed a.ts)"
own="$(grep -n '=== impact (scv graph) ===' <<<"$o" | cut -d: -f1)"; gr="$(grep -n '=== impact (graft blast) ===' <<<"$o" | cut -d: -f1)"
[[ -n "$own" && -n "$gr" && "$gr" -gt "$own" ]] && ok "자체 그래프 블록 아래에 graft 블록" || fail "블록 순서: own=$own graft=$gr"
grep -q 'a.ts' <<<"$o" && grep -qE '3|파일 3|files 3' <<<"$o" && grep -qE '7|심볼 7|symbols 7' <<<"$o" && ok "파일 수·심볼 수·상위 파일" || fail "blast 내용: $(sed -n "${gr:-1},$((${gr:-1}+4))p" <<<"$o")"
grep -q 'blast --base HEAD --depth all --format json' "$WORK/calls.log" && ok "호출 인자 (origin/main 없음 → HEAD)" || fail "호출: $(cat "$WORK/calls.log")"

echo "── [T7] ready — ask 후보 블록 ──"
rm -f "$WORK/calls.log"
o="$(run_in "$P" "$F" bash "$WS" 20260917-u-delta)"; grep -q '^GRAFT_STATUS: ready' <<<"$o" && grep -q '=== code candidates (graft ask) ===' <<<"$o" && grep -q 'b.py:4' <<<"$o" && ok "work.sh: ready + 후보 블록" || fail "work ready: $(grep -n 'GRAFT\|candidates\|b.py' <<<"$o" | head -4)"
grep -q 'ask 델타 기능 --json' "$WORK/calls.log" && ok "ask 인자 = 계획 제목" || fail "ask 호출: $(cat "$WORK/calls.log")"
o="$(run_in "$P" "$F" bash "$PH" --dry-run)"; grep -q '^GRAFT_STATUS: ready' <<<"$o" && ok "promote-helper: ready" || fail "promote ready"

echo "── [T8] 실패 처리 ──"
FB="$WORK/fake-broken"; mkfake "$FB" broken; FS="$WORK/fake-slow"; mkfake "$FS" slow
[[ -z "$(run_in "$P" "$FB" bash "$GRAFT" blast)" ]] && ( run_in "$P" "$FB" bash "$GRAFT" blast ) && ok "깨진 JSON → 빈 출력, exit 0" || fail "broken"
t0=$(now_ms); v="$( cd "$P" && PATH="$FS:$CLEANPATH" SCV_GRAFT_TIMEOUT=2 bash "$GRAFT" ask x 2>/dev/null )"; rc=$?; t1=$(now_ms)
[[ -z "$v" && "$rc" == "0" ]] && ok "타임아웃(2s) → 빈 출력, exit 0, $((t1 - t0))ms" || fail "slow: rc=$rc out=[$v] $((t1 - t0))ms"
# coreutils timeout 이 없는 환경(macOS)의 bash 감시자 경로 — 필요한 도구만 담은 PATH 로 강제한다
NOTO="$WORK/no-timeout"; mkdir -p "$NOTO"; for b in bash sh jq sleep kill mktemp cat rm git sed awk grep head tail tr cut sort date printf env dirname basename; do bp="$(command -v $b 2>/dev/null)"; [[ -n "$bp" ]] && ln -sf "$bp" "$NOTO/$b"; done; ln -sf "$FS/graft" "$NOTO/graft"
t0=$(now_ms); v="$( cd "$P" && PATH="$NOTO" SCV_GRAFT_TIMEOUT=2 bash "$GRAFT" ask x 2>/dev/null )"; rc=$?; t1=$(now_ms)
[[ -z "$v" && "$rc" == "0" ]] && ok "timeout 없는 환경의 감시자 → 빈 출력, exit 0, $((t1 - t0))ms" || fail "slow (no timeout bin): rc=$rc out=[$v] $((t1 - t0))ms"

echo "── [T9] 스위치·안내 ──"
printf '{"SCV_GRAFT":"off"}\n' > "$P/scv/scv_settings.json"; rm -f "$WORK/calls.log"
[[ "$(run_in "$P" "$F" bash "$GRAFT" status)" == "GRAFT_STATUS: off" && ! -e "$WORK/calls.log" ]] && ok "SCV_GRAFT=off → off, 호출 없음" || fail "off"
rm -f "$P/scv/scv_settings.json"
pr="$(bash "$ID" --print 2>/dev/null)"; grep -q 'graft' <<<"$pr" && grep -q -- '--no-hooks --no-statusline' <<<"$pr" && grep -q 'telemetry disable' <<<"$pr" && ok "--print 에 graft 안내 한 줄" || fail "install-deps print"
c1="$(bash "$ID" --check >/dev/null 2>&1; echo $?)"; c2="$(PATH="$F:$PATH" bash "$ID" --check >/dev/null 2>&1; echo $?)"; [[ "$c1" == "$c2" ]] && ! bash "$ID" --check 2>&1 | grep -q '\[.\] graft' && ok "--check 는 graft 를 세지 않는다" || fail "check counts graft: $c1 vs $c2"
jq -e '._doc.SCV_GRAFT and .SCV_GRAFT=="auto"' "$CORE/template/scv/scv_settings.example.json" >/dev/null && ok "설정 예시 SCV_GRAFT" || fail "settings example"
if [[ -f "$CORE/scripts/check-purity.sh" ]]; then
  OUT="$(bash "$CORE/scripts/check-purity.sh" "$LIB" 2>&1)"; grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성: $(head -2 <<<"$OUT")"
fi

echo; echo "test-graft-adapter: pass=$PASS fail=$FAIL"
(( FAIL == 0 ))
