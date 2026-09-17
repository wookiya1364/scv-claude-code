#!/usr/bin/env bash
# test-graph.sh — "SCV 자체 그래프" 검사 (v0.51.0+).
#
# 왜 있나: 옛 그래프 스킬을 걷어내고 SCV 가 가진 재료(문서 링크 · 보관 계획→파일 · 결정 참조 · 동시변경)만으로
# 그래프를 만든다는 약속은, 순수부가 문자열만으로 같은 답을 내고, 빌드가 결정적이며, 소비처 넷이 새 그래프를
# 읽고, 옛 스킬 참조가 0 일 때만 믿을 수 있다.
#
# Covers TESTS.md T1~T11 of 20260917-wookiya1364-scv-own-graph (T12 = run-dry + 코어 검사 + deck).
# Run: bash core/tests/test-graph.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-graph: payload not found from $HERE" >&2; exit 1; }
REPO="$(cd "$CORE/.." && pwd)"
# 이 검사가 scv-core 저장소 자체에서 도는지(보관 계획·루트 gitignore·docs 가 있는 곳), 래퍼에 벤더링된 사본에서 도는지.
# 저장소 전용 항목(T6 의 알려진 동시변경 쌍 · T10 의 docs/README · T11 의 루트 gitignore)은 사본에서는 건너뛴다.
IS_CORE_REPO=0; [[ -f "$REPO/VERSION" && -f "$REPO/core/TEMPLATE_DIGEST" && -d "$REPO/scv/archive" ]] && IS_CORE_REPO=1
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
US=$'\x1f'
LIB="$CORE/scripts/lib/graph.sh"; GRAPH="$CORE/scripts/graph.sh"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
[[ -f "$LIB" ]] || { echo "  ✖ FAIL: lib missing: $LIB"; echo; echo "test-graph: pass=0 fail=1"; exit 1; }
source "$LIB"
now_ms() { local n; n="$(date +%s%3N 2>/dev/null || true)"; [[ "$n" =~ ^[0-9]+$ ]] || n="$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || true)"; [[ "$n" =~ ^[0-9]+$ ]] || n=$(( $(date +%s) * 1000 )); printf '%s' "$n"; }

echo "── [T1] 문서 링크 추출 (순수) ──"
MD=$'# A\n[arch](architecture.md) and [guard](../core/contracts/guard.md) and [sec](#절) and [web](https://x.y/z.md) ![img](x.png) [same](architecture.md#top)\n'
v="$(scv_graph_doc_links docs/index.md "$MD" | sort -u)"
[[ "$v" == $'docs/index.md'"$US"$'core/contracts/guard.md\ndocs/index.md'"$US"$'docs/architecture.md' ]] && ok "상대 md 링크 2개, 앵커·URL·이미지 제외, 경로 정규화" || fail "doc links: $(printf '%s' "$v" | tr "$US" '|')"
[[ -z "$(scv_graph_doc_links docs/a.md $'no links here\n')" ]] && ok "링크 없음 → 빈 출력" || fail "빈 입력"

echo "── [T2] 계획→파일 추출 (순수) ──"
PLAN=$'---\ntitle: "T"\nslug: 20260917-x-plan\nepic: 20260917-e\nscope:\n  - "core/x.sh (설명)"\n  - "core/tests/test-a.sh · core/tests/test-b.sh"\n  - "CHANGELOG.md"\n---\n# T\n본문 `core/y.sh` 와 `SCV_LANG` 과 `0.49.1` 과 `https://a/b.md` 와 `./core/z.md` 그리고 `core/y.sh` 다시.\n'
v="$(scv_graph_plan_touches 20260917-x-plan "$PLAN")"
IFS="$US" read -r slug epic title files <<<"$v"
[[ "$slug" == "20260917-x-plan" && "$epic" == "20260917-e" && "$title" == "T" ]] && ok "슬러그·epic·제목" || fail "meta: $slug|$epic|$title"
[[ "$files" == "core/x.sh core/tests/test-a.sh core/tests/test-b.sh CHANGELOG.md core/y.sh core/z.md" ]] && ok "scope 첫 토큰·구분자 분리·백틱 경로·./ 제거·중복 제거 (설정 키·버전·URL 제외; 정렬은 jq)" || fail "files: $files"

echo "── [T3] 동시변경 (순수) ──"
T=$'A'"$US"$'x y z\nB'"$US"$'x y\nC'"$US"$'y'
v="$(scv_graph_cochange "$T")"
[[ "$v" == $'x'"$US"$'y'"$US"$'2'"$US"$'A B\nx'"$US"$'z'"$US"$'1'"$US"$'A\ny'"$US"$'z'"$US"$'1'"$US"$'A' ]] && ok "쌍·가중치·근거 (사전순, 자기 쌍 없음)" || fail "cochange: $(printf '%s' "$v" | tr "$US" '|')"

echo "── [T4] 군집·핵심 노드 (순수) ──"
[[ "$(scv_graph_community file core/scripts/a.sh)" == "core/scripts" && "$(scv_graph_community file core/scripts/lib/b.sh)" == "core/scripts" && "$(scv_graph_community doc docs/c.md)" == "docs" ]] && ok "파일·문서 군집 = 상위 두 폴더" || fail "community file"
[[ "$(scv_graph_community plan P 20260917-e)" == "20260917-e" && "$(scv_graph_community plan 20260917-q-slug '')" == "2026-09" ]] && ok "계획 군집 = epic 또는 연월" || fail "community plan: $(scv_graph_community plan 20260917-q-slug '')"
G='{"nodes":[{"id":"a"},{"id":"b"},{"id":"c"},{"id":"d"}],"links":[{"source":"a","target":"b"},{"source":"a","target":"c"},{"source":"b","target":"c"},{"source":"d","target":"a"}]}'
[[ "$(scv_graph_god_nodes "$G" 3 | tr '\n' ' ')" == "a b c " && "$(scv_graph_god_nodes "$G" 3)" == "$(scv_graph_god_nodes "$G" 3)" ]] && ok "핵심 노드 = 차수 내림차순·동률 id 순·상한" || fail "god: $(scv_graph_god_nodes "$G" 3 | tr '\n' ' ')"

echo "── [T5] 픽스처 프로젝트 빌드 ──"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-graph.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
P="$WORK/p"; mkdir -p "$P/docs" "$P/core/contracts" "$P/core" "$P/scv/archive/20260901-u-alpha" "$P/scv/archive/20260902-u-beta" "$P/scv/archive/20260903-u-gamma" "$P/scv/promote/20260917-u-delta" "$P/scv/raw"
printf '# Arch\nSee [guard](../core/contracts/guard.md) and [ops](ops.md).\n' > "$P/docs/architecture.md"
printf '# Ops\nBack to [arch](architecture.md).\n' > "$P/docs/ops.md"
printf '# Guard\n' > "$P/core/contracts/guard.md"
printf 'x\n' > "$P/core/x.sh"; printf 'y\n' > "$P/core/y.sh"; printf 'z\n' > "$P/core/z.sh"
mkplan() { printf -- '---\ntitle: "%s"\nslug: %s\nstatus: testing\nkind: feature\n%sscope:\n%s---\n# %s\n본문.\n' "$2" "$1" "$3" "$4" "$2" > "$5/PLAN.md"; printf '# T\n' > "$5/TESTS.md"; }
mkplan 20260901-u-alpha "알파" $'epic: 20260901-ep\n' $'  - "core/x.sh"\n  - "core/y.sh (설명)"\n  - "core/z.sh"\n' "$P/scv/archive/20260901-u-alpha"
mkplan 20260902-u-beta "베타" $'epic: 20260901-ep\n' $'  - "core/x.sh"\n  - "core/y.sh"\n' "$P/scv/archive/20260902-u-beta"
mkplan 20260903-u-gamma "감마" "" $'  - "core/y.sh"\n  - "core/gone.sh"\n' "$P/scv/archive/20260903-u-gamma"
mkplan 20260917-u-delta "델타" "" $'  - "core/x.sh"\n' "$P/scv/promote/20260917-u-delta"
printf '# Decisions\n\n## [2026-09-01 10:00] u — 알파 채택\n\n- verdict: adopted\n- why: w\n- refs: scv/archive/20260901-u-alpha/PLAN.md\n\n## [2026-09-03 10:00] u — 감마 보관\n\n- verdict: archived\n- why: w\n- refs: scv/archive/20260903-u-gamma/PLAN.md, scv/archive/20260902-u-beta/PLAN.md\n' > "$P/scv/DECISIONS.md"
gs() { ( cd "$P" && bash "$GRAPH" "$@" 2>&1 ); }
out="$(gs build)"; [[ -f "$P/scv/.graph/graph.json" && -f "$P/scv/.graph/GRAPH_REPORT.md" ]] && ok "build → graph.json + GRAPH_REPORT.md" || fail "build 산출물 없음: $out"
J="$P/scv/.graph/graph.json"
jq -e '.version==1 and (.built_at|type)=="string" and (.nodes|all(.kind as $k | ["doc","file","plan","decision"]|index($k))) and (.links|all(.kind as $k | ["link","touches","refers","cochange"]|index($k))) and (.links|all(has("weight") and has("evidence"))) and (.god_nodes|type)=="array" and (.communities|type)=="object" and (.sources|has("docs") and has("plans") and has("decisions"))' "$J" >/dev/null && ok "graph.json 스키마" || fail "스키마: $(head -c 300 "$J")"
jq -e '[.nodes[]|select(.kind=="doc")]|length==3' "$J" >/dev/null && ok "문서 노드 3 (docs 2 + contracts 1)" || fail "doc nodes: $(jq -c '[.nodes[]|select(.kind=="doc")|.id]' "$J")"
jq -e '[.links[]|select(.kind=="link")]|length==3' "$J" >/dev/null && ok "문서 링크 3" || fail "links: $(jq -c '[.links[]|select(.kind=="link")|[.source,.target]]' "$J")"
jq -e '(.nodes|map(select(.kind=="plan"))|length)==4 and (.nodes|map(select(.kind=="plan" and .active==true))|length)==1' "$J" >/dev/null && ok "계획 노드 4 (promote 1 은 active)" || fail "plan nodes: $(jq -c '[.nodes[]|select(.kind=="plan")|{id,active}]' "$J")"
jq -e '(.links[]|select(.kind=="cochange" and .source=="core/x.sh" and .target=="core/y.sh")|.weight==2 and (.evidence|sort)==["20260901-u-alpha","20260902-u-beta"])' "$J" >/dev/null && ok "동시변경 x–y weight 2 근거 2" || fail "cochange x-y: $(jq -c '[.links[]|select(.kind=="cochange")]' "$J")"
jq -e '[.links[]|select(.kind=="refers")]|length==3' "$J" >/dev/null && ok "결정→계획 참조 3" || fail "refers: $(jq -c '[.links[]|select(.kind=="refers")]' "$J")"
jq -e '(.nodes[]|select(.id=="core/gone.sh")|.missing==true) and ((.nodes[]|select(.id=="core/x.sh")|.missing)!=true)' "$J" >/dev/null && ok "없는 경로는 missing: true" || fail "missing flag"
jq -e '.communities["core"]|index("core/x.sh")' "$J" >/dev/null && jq -e '.communities["20260901-ep"]|index("20260901-u-alpha")' "$J" >/dev/null && ok "군집: 폴더·epic" || fail "communities: $(jq -c '.communities|keys' "$J")"
for s in '## Communities' '## God Nodes' '## Co-change pairs' '## Sources'; do grep -q "^$s" "$P/scv/.graph/GRAPH_REPORT.md" && ok "보고 절 $s" || fail "보고 절 없음: $s"; done
cp "$J" "$WORK/g1.json"; sleep 1; gs build >/dev/null; [[ "$(jq -S 'del(.built_at)' "$WORK/g1.json")" == "$(jq -S 'del(.built_at)' "$J")" ]] && ok "두 번 빌드 → built_at 제외 동일" || fail "비결정적"

echo "── [T6] 이 저장소 빌드 ──"
if (( IS_CORE_REPO )); then
  t0=$(now_ms); ( cd "$REPO" && bash "$GRAPH" build >/dev/null 2>&1 ); t1=$(now_ms); RJ="$REPO/scv/.graph/graph.json"
  # 벽시계 단언은 두지 않는다. 밀리초를 재면 기계가 바쁠 때 코드와 무관하게 무너지고,
  # 그 검사를 공유하는 계획들이 한꺼번에 붉는다. 걸린 시간은 사람이 보게 적기만 한다.
  ok "빌드 완료 ($((t1 - t0))ms)"
  [[ -f "$RJ" ]] && jq -e '(.nodes|length)>50' "$RJ" >/dev/null && ok "노드 > 50" || fail "노드 수"
  jq -e '.links[]|select(.kind=="cochange" and ((.source=="core/template/hooks/on-stop.sh" and .target=="core/scripts/lib/help-state.sh") or (.source=="core/scripts/lib/help-state.sh" and .target=="core/template/hooks/on-stop.sh")))|.evidence|index("20260916-wookiya1364-answer-lint-turn-race")' "$RJ" >/dev/null && ok "on-stop.sh–lib/help-state.sh 동시변경, 근거에 answer-lint-turn-race" || fail "알려진 동시변경 쌍 없음"
else
  echo "  – SKIP: 벤더링된 사본(보관 계획 없음) — 저장소 전용 항목은 scv-core 에서만 본다"
fi

echo "── [T7] 신선도 ──"
P2="$WORK/p2"; cp -r "$P" "$P2"; rm -rf "$P2/scv/.graph"; gs2() { ( cd "$P2" && bash "$GRAPH" "$@" 2>&1 ); }
[[ "$(gs2 status)" == "GRAPH_STATUS: missing" ]] && ok "빌드 전 missing" || fail "status0: $(gs2 status)"
gs2 build >/dev/null; [[ "$(gs2 status)" == "GRAPH_STATUS: built" ]] && ok "빌드 후 built" || fail "status1: $(gs2 status)"
m1="$(stat -c %Y "$P2/scv/.graph/graph.json" 2>/dev/null || stat -f %m "$P2/scv/.graph/graph.json")"
sleep 1; touch "$P2/scv/archive/20260901-u-alpha/PLAN.md"; [[ "$(gs2 status)" == "GRAPH_STATUS: stale" ]] && ok "PLAN 바뀌면 stale" || fail "status2: $(gs2 status)"
[[ "$(gs2 ensure)" == "GRAPH_STATUS: built" ]] && ok "ensure → built" || fail "ensure: $(gs2 ensure)"
m2="$(stat -c %Y "$P2/scv/.graph/graph.json" 2>/dev/null || stat -f %m "$P2/scv/.graph/graph.json")"; (( m2 > m1 )) && ok "stale 이면 다시 빌드" || fail "재빌드 안 됨"
sleep 1; gs2 ensure >/dev/null; m3="$(stat -c %Y "$P2/scv/.graph/graph.json" 2>/dev/null || stat -f %m "$P2/scv/.graph/graph.json")"; (( m3 == m2 )) && ok "built 이면 파일 그대로" || fail "불필요한 재빌드"

echo "── [T8] 영향 조회 ──"
out="$(gs impact core/x.sh)"
grep -q 'core/y.sh' <<<"$out" && grep -q 'weight=2\|×2\|2회' <<<"$out" && grep -q '20260901-u-alpha' <<<"$out" && ok "함께 바뀌는 파일 + 가중치 + 근거" || fail "impact 이웃: $out"
grep -q '20260902-u-beta' <<<"$out" && grep -q '감마 보관\|알파 채택' <<<"$out" && ok "건드린 계획 + 얽힌 결정" || fail "impact 계획·결정: $out"
grep -q '근거 없음' <<<"$(gs impact core/nope.sh)" && ( cd "$P" && bash "$GRAPH" impact core/nope.sh >/dev/null 2>&1 ) && ok "없는 경로 → 근거 없음, 종료 0" || fail "없는 경로 처리"
gs impact --json core/x.sh | jq -e '.[0].path=="core/x.sh" and (.[0].cochange|length)>=2 and (.[0].plans|length)>=2 and (.[0].decisions|length)>=1' >/dev/null && ok "--json" || fail "impact json: $(gs impact --json core/x.sh | head -c 300)"
out="$(gs impact docs/architecture.md)"; grep -q 'docs/ops.md' <<<"$out" && ok "문서는 링크한 문서를 낸다" || fail "impact doc: $out"

echo "── [T9] 소비처 넷 + 회귀 앞단 ──"
PH="$CORE/scripts/promote-helper.sh"; WS="$CORE/scripts/work.sh"; SS="$CORE/scripts/status.sh"; DC="$CORE/scripts/deck-context.sh"; RG="$CORE/scripts/regression.sh"
o="$( cd "$P" && bash "$PH" --dry-run 2>/dev/null )"; grep -q '^GRAPH_STATUS: built' <<<"$o" && grep -q '^GRAPH_DIR: scv/.graph' <<<"$o" && ! grep -q 'GRAPH''IFY_SKILL' <<<"$o" && ok "promote-helper: GRAPH_STATUS built · GRAPH_DIR · 옛 스킬 줄 없음" || fail "promote-helper: $(grep -E 'GRAPH' <<<"$o" | tr '\n' ' ')"
o="$( cd "$P" && bash "$WS" 20260917-u-delta 2>/dev/null )"; grep -q '=== impact (scv graph) ===' <<<"$o" && grep -q 'core/y.sh' <<<"$o" && ! grep -q 'GRAPH''IFY_SKILL' <<<"$o" && ok "work.sh: IMPACT 블록(계획 scope 의 이웃)" || fail "work.sh: $(grep -n -A3 'impact' <<<"$o" | head -6)"
o="$( cd "$P" && bash "$SS" 2>/dev/null )"; grep -q '\[docs graph (scv graph)\]' <<<"$o" && grep -qE 'status: (built|stale|missing)' <<<"$o" && ok "status.sh: scv graph 절" || fail "status.sh: $(grep -n 'graph' <<<"$o" | head -3)"
o="$( cd "$P" && bash "$DC" 2>/dev/null )"; grep -q '^SCV_GRAPH: present' <<<"$o" && ! grep -q 'GRAPH''IFY' <<<"$o" && ok "deck-context: SCV_GRAPH present" || fail "deck-context: $(grep -n 'GRAPH' <<<"$o")"
o="$( cd "$P" && bash "$RG" --dry --changed core/x.sh,core/z.sh 2>/dev/null )"; grep -q '=== impact (scv graph) ===' <<<"$o" && grep -q 'core/y.sh' <<<"$o" && grep -q 'TOTAL_SLUGS' <<<"$o" && ok "regression --dry: 영향 목록 + 실행 계획(실행 없음)" || fail "regression: $(head -12 <<<"$o")"

echo "── [T10] 옛 그래프 스킬 참조 0 ──"
W="graph""ify"
# 코어 페이로드(scripts·protocols·template·contracts·tests)는 어디서 돌든 본다; docs·README·루트 tests 는 scv-core 에서만.
n="$( cd "$CORE" && grep -ril "$W" scripts protocols template contracts tests 2>/dev/null | grep -v '^tests/fixtures/' | wc -l )"; (( n == 0 )) && ok "코어 페이로드에 옛 스킬 이름 없음" || fail "옛 스킬 이름 남음(코어): $( cd "$CORE" && grep -ril "$W" scripts protocols template contracts tests | head -5 | tr '\n' ' ')"
if (( IS_CORE_REPO )); then
  n="$( cd "$REPO" && grep -ril "$W" docs README.md tests 2>/dev/null | wc -l )"; (( n == 0 )) && ok "docs·README·루트 tests 에 옛 스킬 이름 없음" || fail "옛 스킬 이름 남음(저장소): $( cd "$REPO" && grep -ril "$W" docs README.md tests | head -5 | tr '\n' ' ')"
fi
! grep -q 'scv_graph_skill_available' "$CORE/scripts/lib/host-profile.sh" && ok "감지 함수 제거" || fail "scv_graph_skill_available 남음"
! bash "$CORE/scripts/install-deps.sh" --check 2>&1 | grep -qi "$W" && ! bash "$CORE/scripts/install-deps.sh" --print 2>&1 | grep -qi "$W" && ok "install-deps 출력에 옛 스킬 이름 없음" || fail "install-deps 옛 스킬 이름"
! ( cd "$P" && bash "$CORE/scripts/help.sh" 2>&1 | grep -qi "$W" ) && ok "help.sh 의존성 표에 옛 스킬 이름 없음" || fail "help.sh 옛 스킬 이름"

echo "── [T11] gitignore · 설정 ──"
grep -q '^scv/\.graph/' "$CORE/template/.gitignore.fragment" && ! grep -qi "$W" "$CORE/template/.gitignore.fragment" && ok "템플릿 fragment: scv/.graph/, 옛 항목 없음" || fail "fragment"
! grep -qi "$W" "$CORE/.gitignore" && ok "core gitignore 에 옛 항목 없음" || fail "core gitignore"
if (( IS_CORE_REPO )); then grep -q '^scv/\.graph/' "$REPO/.gitignore" && ! grep -qi "$W" "$REPO/.gitignore" && ok "루트 gitignore: scv/.graph/" || fail "루트 gitignore"; fi
jq -e '._doc.SCV_GRAPH and ._doc.SCV_GRAPH_DOCS and .SCV_GRAPH=="on" and (.SCV_GRAPH_DOCS|type)=="string"' "$CORE/template/scv/scv_settings.example.json" >/dev/null && ok "설정 예시: SCV_GRAPH · SCV_GRAPH_DOCS" || fail "설정 예시"
P3="$WORK/p3"; cp -r "$P" "$P3"; rm -rf "$P3/scv/.graph"; printf '{"SCV_GRAPH":"off"}\n' > "$P3/scv/scv_settings.json"
o="$( cd "$P3" && bash "$GRAPH" ensure 2>&1 )"; [[ "$o" == "GRAPH_STATUS: off" && ! -e "$P3/scv/.graph" ]] && ok "SCV_GRAPH=off → off, 아무것도 안 만듦" || fail "off: $o"
P4="$WORK/p4"; cp -r "$P" "$P4"; rm -rf "$P4/scv/.graph"; printf '# R\n[a](docs/architecture.md)\n' > "$P4/README.md"; printf '{"SCV_GRAPH_DOCS":"docs"}\n' > "$P4/scv/scv_settings.json"
( cd "$P4" && bash "$GRAPH" build >/dev/null 2>&1 ); jq -e '(.sources.docs=="docs") and ([.nodes[]|select(.id=="README.md")]|length==0) and ([.nodes[]|select(.id=="docs/ops.md")]|length==1)' "$P4/scv/.graph/graph.json" >/dev/null && ok "SCV_GRAPH_DOCS=docs → README 는 재료가 아니다" || fail "docs 범위 설정: $(jq -c '[.sources.docs, [.nodes[]|select(.kind=="doc")|.id]]' "$P4/scv/.graph/graph.json")"

echo; echo "test-graph: pass=$PASS fail=$FAIL"
(( FAIL == 0 ))
