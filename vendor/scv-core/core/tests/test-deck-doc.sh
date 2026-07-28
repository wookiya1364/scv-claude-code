#!/usr/bin/env bash
# test-deck-doc.sh — regression tests for the buildless /scv:deck DOCUMENT path.
#
# Body/structural assertions target a --no-source render (NS) so a grep can NEVER
# accidentally match the raw-markdown side panel / print appendix (that mistake let
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
#  10. scv:deck's defining trait — the raw markdown is an ALWAYS-ON side panel (not a
#      footnote): single source = no tabs, multi-source (slug combine) = one tab per
#      file with the pristine (unstripped) text; toggle button + print-only appendix.
#  11. screen-by-screen paging (‹›  arrows, dots, jump-nav, arrow keys) with the side
#      panel auto-tracking the current page (tab switch + <mark> highlight); mermaid
#      is scoped to the active page only (a hidden-page render sizes to zero and mermaid
#      never retries it) with a beforeprint pass so print/PDF still gets every diagram.
#  12. dark-default theme with a header toggle (pre-paint init from localStorage, no
#      flash-of-light) + a draggable side-panel resize handle (same bounds as the
#      original SourcePanel: 320px floor, main content keeps ≥420px).
#  13. ```screen fenced JSON → wireframe mockup (Claude Code-authored, per commands/promote.md
#      Step 6.4): valid JSON renders the dark scv-native wf-* skin; malformed JSON never
#      crashes the build — it becomes a visible error callout instead.
#  14. v0.18.0 pre-release fixes (adversarial review): array-type-confusion crash guards,
#      card recursion depth cap, BADGE_TONE prototype-chain guard, screen-fence type-key
#      override guard, WCAG contrast fix (on-primary/on-warn), resize breakpoint fix,
#      single-page pagination-UI gating.
#  15. i18n — English is the DEFAULT UI-chrome language (buttons/headings/lint text; the
#      user's own PLAN.md/TESTS.md/screen-mockup CONTENT is never translated); --lang /
#      SCV_LANG select korean/japanese, same SCV_LANG convention as
#      scripts/render-template.sh (anything unrecognized falls back to English); the
#      doc/slide byte-identical invariant holds under a non-default SCV_LANG too (both
#      CLIs read the same env var).
#  16. screen-mockup theme override (project-token priority): absent by default (scv
#      skin), a valid `theme` field emits validated inline --wf-* vars with COMPUTED
#      on-primary/tint derivatives, and invalid/malicious values are dropped silently
#      (never reach the HTML in any form — no CSS/attribute injection).
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
DOC="$TMP/doc.html"   # includes the side panel + print appendix
NS="$TMP/ns.html"     # NO source panel — body/structural greps target THIS
has "$TMP/out.txt" "DECK_HTML:" "emits DECK_HTML"
has "$TMP/out.txt" "LINT: 1 warning" "lint = 1 (acceptance criteria missing)"
has "$TMP/out.txt" "Acceptance" "lint names the missing acceptance section (English default)"

# 1. document shape (not slides) + source travels by default
has   "$NS" 'class="wrap"'    "document wrapper present"
hasnt "$NS" 'id="root"'       "no React slide root (#root)"
has   "$NS" 'nav class="toc"' "table of contents present"
has   "$DOC" 'Source'         "raw markdown travels with the doc by default (English default label)"
hasnt "$NS"  'class="panel-toggle"' "--no-source drops the source panel/toggle entirely"

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
has   "$NS" 'Quality Report' "quality report section rendered (English default)"
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
has   "$CNS" 'Structure · FEATURE_ARCHITECTURE'         "slug combine: FEATURE_ARCHITECTURE section merged (English default)"
has   "$CNS" 'Tests · Acceptance Criteria'              "slug combine: TESTS section merged (English default)"
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
hasnt "$PLANONLY" 'Tests · Acceptance Criteria' "slug combine: no TESTS divider when TESTS.md absent (English default)"

# 10. side panel — single source (no tabs) vs slug-combine (tabs, pristine per-file text)
has   "$DOC" 'id="scvSourcePanel"'      "side panel present by default"
has   "$DOC" 'panel-toggle'             "header toggle button present"
hasnt "$DOC" '<div class="panel-tabs">' "single source: no tabs (only one document)"
has   "$DOC" 'scvSourcePanel'           "panel toggle/select script wired"

node "$DECKDOC/doc.mjs" "$SLUGDIR" --out "$TMP/combine-panel.html" >/dev/null 2>&1
CPANEL="$TMP/combine-panel.html"
has "$CPANEL" '<div class="panel-tabs">'                                  "slug combine: tabs render (3 files)"
has "$CPANEL" '>PLAN.md<'                                                 "slug combine: PLAN.md tab labeled"
has "$CPANEL" '>FEATURE_ARCHITECTURE.md<'                                 "slug combine: FEATURE_ARCHITECTURE.md tab labeled"
has "$CPANEL" '>TESTS.md<'                                                "slug combine: TESTS.md tab labeled"
has "$CPANEL" 'status: planned'                                           "panel shows the PRISTINE (unstripped) file — frontmatter visible here, unlike the rendered body"
has "$CPANEL" '<h3>PLAN.md</h3>'                                          "print appendix: one heading per source file"
has "$CPANEL" '<h3>FEATURE_ARCHITECTURE.md</h3>'                          "print appendix: FEATURE_ARCHITECTURE.md heading"
has "$CPANEL" 'class="print-source"'                                     "print-only appendix present (hidden on screen, shown at print via CSS)"

# 11. pagination + highlight-sync (screen-only paging; print always shows everything)
has   "$NS" 'class="slide-page active"'    "first page starts active"
has   "$NS" 'class="deck-nav"'             "page jump-nav (pill buttons) present"
has   "$NS" 'id="scvPrev"'                 "footer prev/next controls present"
has   "$NS" 'class="deck-dots"'            "dot indicators present"
has   "$NS" 'function scvGoto'             "pagination controller present"
has   "$NS" 'function scvHighlight'        "source-panel highlight-sync present"
has   "$NS" "SCV_ANCHORS"                  "per-page anchor list embedded for highlight lookup"
has   "$NS" "'ArrowRight'"                 "arrow-key navigation wired"
has   "$NS" "'ArrowLeft'"                  "arrow-key navigation wired (left)"
# nav.toc is print-only now (deck-nav replaced it as the on-screen jump mechanism)
has   "$NS" '@media screen{nav.toc{display:none}}' "table of contents hidden on screen (deck-nav replaces it)"
# regression guard for the real bug the reverify caught: mermaid measured while its
# page was display:none comes out zero-sized AND gets marked processed (never fixed by
# a later broad re-run) — the initial/on-navigate run MUST be scoped to the active page.
has "$DOC" '".slide-page.active pre.mermaid"' "mermaid run is scoped to the ACTIVE page only (not run on documentwide-hidden pages)"
has "$DOC" 'beforeprint'                      "printing forces a full (unscoped) mermaid pass so unvisited pages still render"

# 12. dark-default theme (toggle button, pre-paint init, no FOUC) + draggable panel resize
has   "$NS" ":root{--fg:#e7e9f0"            "dark palette is the :root default"
has   "$NS" 'html[data-theme="light"]'      "light palette is an explicit override, not the default"
has   "$NS" 'id="scvThemeBtn"'              "theme toggle button present in the header"
has   "$NS" 'function scvToggleTheme'       "theme toggle handler present"
has   "$NS" "localStorage.getItem('scv-deck-theme'"  "theme choice is read back from localStorage"
has   "$DOC" "localStorage.getItem('scv-deck-theme')==='light')document.documentElement.setAttribute" "pre-paint theme init runs before <style>/<body> (no flash of the wrong theme)"
has   "$DOC" 'id="scvResizeHandle"'          "panel resize handle present (needs a source panel — checked on DOC, not NS)"
has   "$DOC" "addEventListener('mousedown'"  "resize drag handler wired"
has   "$DOC" 'Math.max(320, window.innerWidth - 420)' "resize clamps to the original SourcePanel bounds (min 320px, main keeps ≥420px)"

# 13. ```screen fenced JSON → wireframe mockup; malformed JSON never crashes the build
has   "$NS" 'class="wf-frame"'          "valid screen block renders the wireframe frame"
has   "$NS" 'class="wf-nav-item active"' "screen mockup nav renders with the active item marked"
has   "$NS" 'class="wf-badge wf-badge-muted"' "screen mockup table cell renders as a badge"
has   "$NS" '전화번호부 관리'            "screen mockup content is faithful to the fixture JSON (no invented text)"
has   "$NS" 'Screen Mockup Parse Error'  "malformed screen JSON renders a visible error callout (English default)"
has   "$NS" 'class="callout danger"'    "the parse-error callout uses the danger tone"
hasnt "$NS" 'class="wf-frame"><div class="wf-screen-label">/campaigns' "malformed block does not silently fall back to a (wrong) wireframe"
# dark scv-native skin, scoped independently of the document's own light/dark toggle
has   "$DOC" '--wf-bg:#0a0a0b'          "screen mockup skin is dark by default (DesignSystem-distilled, not the document's own theme)"
has   "$DOC" '.wf-screen{'              "wireframe CSS variables are scoped to .wf-screen (isolated from --bg/--fg used by the document chrome)"

# 14. v0.18.0 pre-release fixes (adversarial review) — each locked so it can't silently regress.

# 14a. wrong-but-truthy types in the screen DSL degrade gracefully instead of crashing
#      doc.mjs (a malformed "rows"/"body"/"items" as a string/object, not null/undefined,
#      used to throw past the `x || []` guards and produce ZERO output for the whole doc).
printf '# T\n\n## S\n\n```screen\n{"body":[{"type":"table","columns":["A"],"rows":"not-an-array"},{"type":"toolbar","items":{"not":"an array either"}}]}\n```\n' > "$TMP/badtypes.md"
if node "$DECKDOC/doc.mjs" "$TMP/badtypes.md" --out "$TMP/badtypes.html" --no-source >/dev/null 2>&1; then
  pass=$((pass+1))
else
  echo "  ✗ wrong-typed screen-DSL fields (string/object instead of array) crash doc.mjs"; fail=$((fail+1))
fi
has "$TMP/badtypes.html" 'class="wf-table"' "malformed rows/items degrade to an empty render, not a crash"

# 14b. runaway card-in-card nesting is capped, not a stack overflow
node -e '
  const N = 500;
  let inner = { type: "text", value: "bottom" };
  for (let i = 0; i < N; i++) inner = { type: "card", body: [inner] };
  const fs = require("node:fs");
  fs.writeFileSync(process.argv[1], "# T\n\n## S\n\n```screen\n" + JSON.stringify({ body: [inner] }) + "\n```\n");
' "$TMP/deepnest.md"
if node "$DECKDOC/doc.mjs" "$TMP/deepnest.md" --out "$TMP/deepnest.html" --no-source >/dev/null 2>&1; then
  pass=$((pass+1))
else
  echo "  ✗ deep card-in-card nesting (500 levels) crashes doc.mjs"; fail=$((fail+1))
fi
has "$TMP/deepnest.html" 'nesting too deep' "nesting past the depth cap renders a truncation notice instead of overflowing (English default)"

# 14c. BADGE_TONE lookup is hasOwnProperty-guarded — a tone of "__proto__"/"constructor"
#      must NOT resolve through the prototype chain into a native function/[object Object].
printf '# T\n\n## S\n\n```screen\n{"body":[{"type":"badge","label":"x","tone":"__proto__"}]}\n```\n' > "$TMP/prototone.md"
node "$DECKDOC/doc.mjs" "$TMP/prototone.md" --out "$TMP/prototone.html" --no-source >/dev/null 2>&1
has   "$TMP/prototone.html" 'wf-badge-muted'    "tone:\"__proto__\" falls back to the muted class, not a prototype-chain hit"
hasnt "$TMP/prototone.html" '[object Object]'   "the unguarded lookup's actual leak shape (Object.prototype stringified) never appears"

# 14d. a `type` key inside the fence body cannot hijack the block away from "screen"
#      (spread-then-pin: the literal type is applied AFTER the JSON spread).
printf '# T\n\n## S\n\n```screen\n{"type":"table","body":[{"type":"text","value":"still a screen"}]}\n```\n' > "$TMP/typehijack.md"
node "$DECKDOC/doc.mjs" "$TMP/typehijack.md" --out "$TMP/typehijack.html" --no-source >/dev/null 2>&1
has "$TMP/typehijack.html" 'class="wf-frame"' "a \"type\":\"table\" key inside the fence cannot hijack the block away from the wireframe renderer"

# 14e. WCAG contrast fixes — the two previously-hardcoded white-on-accent rules now use
#      theme-aware on-* variables (dark-default primary #7c93ff read 2.81:1 with white).
has "$NS" '--on-primary:#12163a' "dark theme defines a readable on-primary text color (not hardcoded white)"
has "$NS" '--on-primary:#ffffff' "light theme's on-primary override is declared explicitly"
has "$NS" '--on-warn'            "on-warn text color variable defined (lint-count badge)"
has "$NS" 'color:var(--on-primary)' "active nav pill uses the theme-aware on-primary color"
has "$NS" 'color:var(--on-warn)'    "lint-count badge uses the theme-aware on-warn color"
hasnt "$NS" '.deck-nav-item.active{background:var(--primary);color:#fff' "active nav pill no longer hardcodes white text"
hasnt "$NS" '.lint-count{display:inline-block;background:var(--warn);color:#fff' "lint-count badge no longer hardcodes white text"

# 14f. resize no longer permanently defeats the mobile/narrow breakpoints — a window
#      resize listener clears/reclamps the inline width so CSS can reassert control.
has "$DOC" "addEventListener('resize'" "a window resize listener exists to reconcile the drag-set inline width"
has "$DOC" "panel.style.width = ''"    "dropping below the mobile breakpoint clears the inline width entirely"
has "$DOC" 'ev.buttons === 0'          "a lost mouseup (button released outside the window) is detected and cleaned up"

# 14g. single-page docs hide the pagination UI entirely (previously deckNav showed an
#      always-active, functionally-inert pill while deckFooter stayed hidden). Built by
#      calling renderHtml directly with lint:[] so the page count is exactly 1 — going
#      through the md pipeline would always add a 2nd (lint) page for an unlabeled doc.
node -e '
  import("'"$DECKDOC"'/render.mjs").then(({ renderHtml }) => {
    const data = { title: "Single", slug: "single", slides: [
      { id: "s0", nav: "One", title: "One", anchor: "One", blocks: [{ type: "para", text: "hi" }] },
    ], lint: [] };
    require("node:fs").writeFileSync(process.argv[1], renderHtml(data, { source: false }));
  });
' "$TMP/onepage.html"
hasnt "$TMP/onepage.html" 'class="deck-nav"'    "single-page doc: no jump-nav (nothing to jump to)"
hasnt "$TMP/onepage.html" 'class="deck-footer"' "single-page doc: no ‹›/dots footer either (gate now matches deck-nav)"

# 15. i18n — English default, --lang/SCV_LANG select korean/japanese, unrecognized
#     falls back to English (render-template.sh's SCV_LANG rule), content never
#     translated, and the doc/slide invariant survives a non-default SCV_LANG.
node "$DECKDOC/doc.mjs" "$FIX" "$SLUG" --out "$TMP/lang-en.html" --no-source >/dev/null 2>&1
has   "$TMP/lang-en.html" '<html lang="en">' "default language is English (no --lang, no SCV_LANG)"
has   "$TMP/lang-en.html" '‹ Prev'            "English default: footer prev button"
has   "$TMP/lang-en.html" 'Next ›'            "English default: footer next button"
has   "$TMP/lang-en.html" 'Table of Contents' "English default: table-of-contents heading (print-only, but always emitted)"

node "$DECKDOC/doc.mjs" "$FIX" "$SLUG" --out "$TMP/lang-ko.html" --lang korean >/dev/null 2>&1
has "$TMP/lang-ko.html" '<html lang="ko">' "--lang korean sets the html lang attribute"
has "$TMP/lang-ko.html" '기획서 원문'       "--lang korean: panel/toggle label in Korean (needs the source panel — no --no-source here)"
has "$TMP/lang-ko.html" '품질 리포트'       "--lang korean: quality-report heading in Korean"
has "$TMP/lang-ko.html" '리스크'            "--lang korean: fixture CONTENT (H3 heading text) unaffected by the UI-chrome language"

node "$DECKDOC/doc.mjs" "$FIX" "$SLUG" --out "$TMP/lang-ja.html" --no-source --lang japanese >/dev/null 2>&1
has "$TMP/lang-ja.html" '<html lang="ja">' "--lang japanese sets the html lang attribute"
has "$TMP/lang-ja.html" '品質レポート'      "--lang japanese: quality-report heading in Japanese"

node "$DECKDOC/doc.mjs" "$FIX" "$SLUG" --out "$TMP/lang-bogus.html" --no-source --lang klingon >/dev/null 2>&1
has "$TMP/lang-bogus.html" '<html lang="en">' "an unrecognized --lang value falls back to English, not a crash"

SCV_LANG=korean node "$DECKDOC/doc.mjs" "$FIX" "$SLUG" --out "$TMP/lang-env.html" --no-source >/dev/null 2>&1
has "$TMP/lang-env.html" '<html lang="ko">' "SCV_LANG env var is respected when --lang is not passed"

# slug-combine dividers are ALSO localized (doc.mjs's own SLUG_PARTS labels, not just render.mjs)
node "$DECKDOC/doc.mjs" "$SLUGDIR" --out "$TMP/combine-ko.html" --no-source --lang korean >/dev/null 2>&1
has "$TMP/combine-ko.html" '구조 · FEATURE_ARCHITECTURE' "slug combine divider labels localize too (Korean)"

# byte-identical invariant must survive a non-default SCV_LANG (both CLIs read the same var)
SCV_LANG=korean node "$MD2DECK" "$FIX" "$SLUG" >/dev/null 2>&1
SCV_LANG=korean node "$DECKDOC/doc.mjs" "$FIX" "$SLUG" --out "$TMP/lang-inv.html" --emit-json >/dev/null 2>&1
if diff -q "$ROOT/DeckUI/src/deck/decks/$SLUG/deck.json" "$TMP/$SLUG.deck.json" >/dev/null 2>&1; then
  pass=$((pass+1))
else
  echo "  ✗ doc/slide transform diverge under SCV_LANG=korean (lint messages must match between the two CLIs)"; fail=$((fail+1))
fi

# 16. screen-mockup "theme" override — scv-native skin is the default (1순위=project
#     tokens only when told, 2순위=scv skin otherwise); Claude Code supplies base hex only,
#     render.mjs derives readable on-primary text + translucent badge tints itself
#     (never repeat the WCAG hardcoded-white bug for a project-supplied color either).
printf '# T\n\n## S\n\n```screen\n{"theme":{"primary":"#5a6cff","success":"#22c55e"},"body":[{"type":"button","label":"x","variant":"primary"},{"type":"badge","label":"y","tone":"good"}]}\n```\n' > "$TMP/theme-ok.md"
node "$DECKDOC/doc.mjs" "$TMP/theme-ok.md" --out "$TMP/theme-ok.html" --no-source >/dev/null 2>&1
has "$TMP/theme-ok.html" 'style="--wf-primary:#5a6cff' "valid theme.primary emits an inline --wf-primary override"
has "$TMP/theme-ok.html" '--wf-primary-fg:#ffffff'     "on-primary text is COMPUTED (luminance), not left at the scv-native default"
has "$TMP/theme-ok.html" '--wf-success-bg:rgba(34,197,94,0.15)' "translucent badge background is derived from the base hex, not authored by hand"

printf '# T\n\n## S\n\n```screen\n{"body":[{"type":"text","value":"no theme field at all"}]}\n```\n' > "$TMP/theme-absent.md"
node "$DECKDOC/doc.mjs" "$TMP/theme-absent.md" --out "$TMP/theme-absent.html" --no-source >/dev/null 2>&1
hasnt "$TMP/theme-absent.html" 'style="--wf-' "no theme field → no inline style at all (scv-native skin, unchanged from before this feature)"

# malicious/invalid values (CSS/attribute-injection attempt + garbage) are dropped
# silently, never reach the emitted HTML in ANY form.
printf '# T\n\n## S\n\n```screen\n{"theme":{"primary":"javascript:alert(1)","bg":"not-a-color","radius":"10px; }</style><script>alert(1)</script>"},"body":[{"type":"text","value":"x"}]}\n```\n' > "$TMP/theme-bad.md"
node "$DECKDOC/doc.mjs" "$TMP/theme-bad.md" --out "$TMP/theme-bad.html" --no-source >/dev/null 2>&1
hasnt "$TMP/theme-bad.html" 'javascript:'  "an invalid/malicious primary value never reaches the output"
hasnt "$TMP/theme-bad.html" '10px; }'      "the attribute-breakout PAYLOAD (not the document's own, always-present, unrelated </style> tag) never reaches the output"
hasnt "$TMP/theme-bad.html" '<script>alert(1)</script>' "no raw <script> ever gets injected via a theme field"

echo ""
echo "test-deck-doc: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
