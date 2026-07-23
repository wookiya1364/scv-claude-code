#!/usr/bin/env bash
# test-deck-doc.sh — regression tests for the buildless /scv:deck DOCUMENT path.
#
# Body/structural assertions target a --no-source render (NS) so a grep can NEVER
# accidentally match the embedded raw-markdown <details> dump (that mistake let
# several fixes pass even when reverted). Covers:
#   1. document (default) is a scrollable HTML, NOT the React slide SPA
#   2. every deck block type renders (para/bullets/goals/kpi/table/mermaid/code/callout/subhead)
#   2b. structure fidelity: nested lists → real nested <ul>/<ol> (no fusing, correct numbering),
#       H3 kept, KPI anchored-but-suffix-tolerant
#   2c. M1: ordered list with sub-bullets keeps correct <ol> numbering (sub-list nested in <li>)
#   2d. transform edge cases: loose multi-paragraph item space-joined; empty H2 kept / empty H1 dropped
#   3. mermaid = CDN with an automatic text fallback (offline / closed network)
#   4. --mermaid none renders mermaid as source text (no CDN script)
#   5. --no-source drops the raw-markdown section; unknown flags are rejected
#   6. the quality/gap lint surfaces and the source is escaped (no HTML injection)
#   7. INVARIANT: doc transform == slide transform (byte-identical); slide-path stdout contract
#   8. the renderer is zero-dependency (no bare-specifier imports)
#   9. slug-folder input combines PLAN + FEATURE_ARCHITECTURE + TESTS into one <slug>.deck.html
#      (missing files handled; a non-spine file's frontmatter/H1 does NOT leak as a section)
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$HERE/.."
DECKDOC="$ROOT/DeckUI/scripts/deckdoc"
MD2DECK="$ROOT/DeckUI/scripts/md-to-deck.mjs"
FIX="$HERE/fixtures/deck-sample.md"
SLUG="decktest-tmp"   # already-normalized temp slug; md-to-deck writes into the deck registry — cleaned on exit

pass=0; fail=0
has()  { grep -qF -- "$2" "$1" && { pass=$((pass+1)); } || { echo "  ✗ $3 — missing: $2"; fail=$((fail+1)); }; }
hasnt(){ grep -qF -- "$2" "$1" && { echo "  ✗ $3 — should be absent: $2"; fail=$((fail+1)); } || { pass=$((pass+1)); }; }
ck()   { if [[ "$2" == "$3" ]]; then pass=$((pass+1)); else echo "  ✗ $1 — expected [$2] got [$3]"; fail=$((fail+1)); fi; }

# deck is a Node+pnpm-only feature — skip cleanly if the toolchain is absent.
command -v node >/dev/null 2>&1 || { echo "SKIP test-deck-doc: node not found"; exit 0; }
command -v pnpm >/dev/null 2>&1 || { echo "SKIP test-deck-doc: pnpm not found"; exit 0; }
if [[ ! -d "$DECKDOC/node_modules" ]]; then
  ( cd "$DECKDOC" && pnpm install ) >/dev/null 2>&1 || { echo "SKIP test-deck-doc: deckdoc install failed"; exit 0; }
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -rf "$ROOT/DeckUI/src/deck/decks/$SLUG"' EXIT

# ---- renders: default (with source) + --no-source (structural asserts target NS) ----
node "$DECKDOC/doc.mjs" "$FIX" "$SLUG" --out "$TMP/doc.html" --emit-json > "$TMP/out.txt" 2>&1
node "$DECKDOC/doc.mjs" "$FIX" "$SLUG" --out "$TMP/ns.html" --no-source >/dev/null 2>&1
DOC="$TMP/doc.html"   # includes the raw-source <details>
NS="$TMP/ns.html"     # NO source dump — body/structural greps target THIS
has "$TMP/out.txt" "DECK_HTML:" "emits DECK_HTML"
has "$TMP/out.txt" "LINT: 1 warning" "lint = 1 (acceptance criteria missing)"
has "$TMP/out.txt" "인수기준" "lint names the missing acceptance section"

# 1. document shape (not slides) + source travels by default
has   "$NS" 'class="wrap"'    "document wrapper present"
hasnt "$NS" 'id="root"'       "no React slide root (#root)"
has   "$NS" 'nav class="toc"' "table of contents present"
has   "$DOC" '기획서 원문'    "raw markdown travels with the doc by default"
hasnt "$NS"  '기획서 원문'    "--no-source drops the source section"

# 2. every block type (rendered body only)
has "$NS" '<p>'                  "paragraph block"
has "$NS" 'class="callout warn"' "callout (WARNING→warn)"
has "$NS" 'class="goals"'        "goals/non-goals split"
has "$NS" 'class="kpi"'          "metric table → KPI tiles"
has "$NS" 'class="tw"'           "regular table"
has "$NS" 'pre class="mermaid"'  "mermaid diagram block"
has "$NS" 'pre class="code"'     "code block"

# 2b. structure fidelity — nested lists render as REAL nested <ul> (tree), not fused/marked
has   "$NS" '<li>다른 상위 항목</li>' "plain top-level bullet rendered"
has   "$NS" '<li>상위 항목<ul>'       "nested bullets → nested <ul> inside the parent <li>"
has   "$NS" '<li>하위 A</li>'         "sub-bullet rendered cleanly"
hasnt "$NS" '상위 항목하위'            "nested bullets NOT fused into a run-on string"
hasnt "$NS" '· 하위 A'                "document uses real nesting, not the flat '· ' marker"
has   "$NS" 'class="subhead">리스크'  "H3 subsection kept as a sub-heading"
has   "$NS" '지표관리자'              "KPI anchor: normal-table header kept (not KPI-dropped)"

# 2c. M1 — ordered list with sub-bullets: sub-list nests inside the <li> (no <ol> mis-count)
has "$NS" '<li>초안 작성<ul>' "ordered item's sub-bullets nest inside its <li>"
OL=$(grep -oF '<ol>' "$NS" | wc -l | tr -d ' ')
if [[ "$OL" -ge 2 ]]; then pass=$((pass+1)); else echo "  ✗ ordered list → <ol> (toc+content, got $OL)"; fail=$((fail+1)); fi

# 2d. transform edge cases (inline)
printf '# T\n\n## S\n\n- 첫 문단\n\n  같은 항목 둘째 문단\n' > "$TMP/loose.md"
node "$DECKDOC/doc.mjs" "$TMP/loose.md" --out "$TMP/loose.html" --no-source >/dev/null 2>&1
has   "$TMP/loose.html" '첫 문단 같은 항목 둘째 문단' "loose list item paragraphs space-joined"
hasnt "$TMP/loose.html" '첫 문단같은'                 "loose list item NOT fused"
printf '# 제목\n\n## 배경\n\n내용\n\n## 리스크\n\n## 다음\n\n끝\n' > "$TMP/empty.md"
node "$DECKDOC/doc.mjs" "$TMP/empty.md" --out "$TMP/empty.html" --no-source >/dev/null 2>&1
has "$TMP/empty.html" '<h2>리스크</h2>' "empty H2 section kept (placeholder still shows)"
EH1=$(grep -oF '<h2>제목</h2>' "$TMP/empty.html" | wc -l | tr -d ' ')
ck "empty H1 not duplicated as a section" "0" "$EH1"

# 3. mermaid CDN + automatic text fallback wiring
has "$NS" 'mermaid.run'      "mermaid CDN run script"
has "$NS" 'mermaid-fallback' "offline text-fallback styling"

# 6. quality lint section + HTML escaping (body, not source dump)
has   "$NS" '품질 리포트' "quality report section rendered"
has   "$NS" '&lt;script&gt;alert(1)&lt;/script&gt;' "source content HTML-escaped in the body"
hasnt "$NS" '<script>alert(1)</script>' "raw <script> never emitted"

# 4. --mermaid none → source text, no CDN
node "$DECKDOC/doc.mjs" "$FIX" "$SLUG" --out "$TMP/none.html" --mermaid none >/dev/null 2>&1
has   "$TMP/none.html" 'mermaid-src' "--mermaid none → mermaid as source code"
hasnt "$TMP/none.html" 'cdn.jsdelivr' "--mermaid none → no CDN script"

# 5. unknown/typo flag is rejected (not swallowed as the slug)
if node "$DECKDOC/doc.mjs" "$FIX" "$SLUG" --out "$TMP/x.html" --mermeid none >/dev/null 2>&1; then
  echo "  ✗ unknown flag --mermeid should exit nonzero"; fail=$((fail+1))
else pass=$((pass+1)); fi

# 7. INVARIANT: doc transform == slide transform (byte-identical) + slide-path stdout contract
node "$MD2DECK" "$FIX" "$SLUG" > "$TMP/slide.out.txt" 2>&1
has "$TMP/slide.out.txt" "DECK_SLUG:" "slide path prints DECK_SLUG"
has "$TMP/slide.out.txt" "DECK_JSON:" "slide path prints DECK_JSON"
has "$TMP/slide.out.txt" "SLIDES:"    "slide path prints SLIDES"
has "$TMP/slide.out.txt" "LINT:"      "slide path prints LINT"
SLIDE_JSON="$ROOT/DeckUI/src/deck/decks/$SLUG/deck.json"
DOC_JSON="$TMP/$SLUG.deck.json"
if [[ -f "$SLIDE_JSON" && -f "$DOC_JSON" ]] && diff -q "$SLIDE_JSON" "$DOC_JSON" >/dev/null; then
  pass=$((pass+1))
else
  echo "  ✗ doc/slide transform diverged (deck.json differs)"; fail=$((fail+1))
fi

# 8. renderer is zero-dependency (no bare-specifier imports)
BARE=$(grep -E '^import .* from "[^.]' "$DECKDOC/render.mjs" 2>/dev/null | wc -l | tr -d ' ')
ck "render.mjs has no external imports" "0" "$BARE"

# 9. slug-FOLDER combine → one <slug>.deck.html in the folder; non-spine frontmatter/H1 not leaked.
SLUGDIR="$TMP/20260101-tester-combine"
mkdir -p "$SLUGDIR"
printf '# 결합 기획\n\n## 배경\n\n본문\n' > "$SLUGDIR/PLAN.md"
# FEATURE_ARCHITECTURE.md STARTS with frontmatter (like the promote Step 6.3 template).
printf -- '---\ntitle: 위치\nstatus: planned\n---\n\n# 아키텍처 위치\n\n```mermaid\nflowchart LR\n  A-->B\n```\n' > "$SLUGDIR/FEATURE_ARCHITECTURE.md"
printf '# TESTS\n\n## 인수기준\n\n| ID | 기대 |\n| --- | --- |\n| T1 | ok |\n' > "$SLUGDIR/TESTS.md"
node "$DECKDOC/doc.mjs" "$SLUGDIR" >/dev/null 2>&1                              # default (committed, with source)
node "$DECKDOC/doc.mjs" "$SLUGDIR" --out "$TMP/combine-ns.html" --no-source >/dev/null 2>&1
COMBINED="$SLUGDIR/20260101-tester-combine.deck.html"
CNS="$TMP/combine-ns.html"
if [[ -f "$COMBINED" ]]; then pass=$((pass+1)); else echo "  ✗ slug combine: <slug>.deck.html not written into the folder"; fail=$((fail+1)); fi
has   "$CNS" '<h1>결합 기획'               "slug combine: PLAN H1 becomes the doc title"
has   "$CNS" '구조 · FEATURE_ARCHITECTURE' "slug combine: FEATURE_ARCHITECTURE section merged"
has   "$CNS" '테스트 · 인수기준'           "slug combine: TESTS section merged"
has   "$CNS" 'pre class="mermaid"'         "slug combine: FEATURE_ARCHITECTURE mermaid rendered"
hasnt "$CNS" 'status: planned'             "non-spine frontmatter NOT leaked into the body"
hasnt "$CNS" '아키텍처 위치'               "non-spine H1 stripped (already under the divider)"

# 9b. non-spine stripping is PARSER-based (not regex): a leading `---` thematic rule
#     is NOT mistaken for frontmatter, and a section heading after the file's own
#     title is preserved (guards the two fix-induced data-loss bugs the reverify found).
SLUGDIR3="$TMP/20260101-tester-rule"
mkdir -p "$SLUGDIR3"
printf '# 계획\n\n## 배경\n\n스파인\n' > "$SLUGDIR3/PLAN.md"
printf -- '---\n\n## 인수기준 A\n\nSENTINEL_A\n\n---\n\n## 인수기준 B\n\nSENTINEL_B\n' > "$SLUGDIR3/TESTS.md"
node "$DECKDOC/doc.mjs" "$SLUGDIR3" --out "$TMP/rule.html" --no-source >/dev/null 2>&1
has "$TMP/rule.html" 'SENTINEL_A' "leading '---' rule not mistaken for frontmatter (content kept)"
has "$TMP/rule.html" '인수기준 A'  "section before a later '---' divider preserved"
has "$TMP/rule.html" 'SENTINEL_B'  "content after the divider preserved"
SLUGDIR4="$TMP/20260101-tester-setext"
mkdir -p "$SLUGDIR4"
printf '# 계획\n\n## 배경\n\n스파인\n' > "$SLUGDIR4/PLAN.md"
printf '# TESTS 파일 제목\n\n실제 섹션 SETEXT\n=================\n\nSENTINEL_SETEXT\n' > "$SLUGDIR4/TESTS.md"
node "$DECKDOC/doc.mjs" "$SLUGDIR4" --out "$TMP/setext.html" --no-source >/dev/null 2>&1
has   "$TMP/setext.html" '실제 섹션 SETEXT' "setext section heading after the file's title preserved"
hasnt "$TMP/setext.html" 'TESTS 파일 제목'  "the non-spine file's own leading H1 title stripped"
# missing files handled gracefully: a PLAN-only slug still builds, no TESTS divider
SLUGDIR2="$TMP/20260101-tester-planonly"
mkdir -p "$SLUGDIR2"
printf '# 계획만\n\n## 배경\n\n본문\n' > "$SLUGDIR2/PLAN.md"
node "$DECKDOC/doc.mjs" "$SLUGDIR2" >/dev/null 2>&1
PLANONLY="$SLUGDIR2/20260101-tester-planonly.deck.html"
if [[ -f "$PLANONLY" ]]; then pass=$((pass+1)); else echo "  ✗ slug combine: PLAN-only slug failed to build"; fail=$((fail+1)); fi
hasnt "$PLANONLY" '테스트 · 인수기준' "slug combine: no TESTS divider when TESTS.md absent"

echo ""
echo "test-deck-doc: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
