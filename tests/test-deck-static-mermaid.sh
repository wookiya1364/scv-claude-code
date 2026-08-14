#!/usr/bin/env bash
# test-deck-static-mermaid.sh — regression for the offline static-SVG embed step
# (deckdoc/static-mermaid.mjs + render.mjs's ?scv-static build mode).
#
# The feature is BEST-EFFORT by contract: without node/pnpm, a local Chrome, or
# network to the mermaid CDN it must skip cleanly (exit 3, input untouched) —
# this test mirrors that: hard-asserts only what must hold in every environment,
# and skips the embed assertions when the environment can't render.
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$HERE/.."
DECKDOC="$ROOT/DeckUI/scripts/deckdoc"

pass=0; fail=0
has()  { grep -qF -- "$2" "$1" && { pass=$((pass+1)); } || { echo "  ✗ $3 — missing: $2"; fail=$((fail+1)); }; }
hasnt(){ grep -qF -- "$2" "$1" && { echo "  ✗ $3 — should be absent: $2"; fail=$((fail+1)); } || { pass=$((pass+1)); }; }

command -v node >/dev/null 2>&1 || { echo "SKIP test-deck-static-mermaid: node not found"; exit 0; }
command -v pnpm >/dev/null 2>&1 || { echo "SKIP test-deck-static-mermaid: pnpm not found"; exit 0; }
if [[ ! -d "$DECKDOC/node_modules" ]]; then
  ( cd "$DECKDOC" && pnpm install ) >/dev/null 2>&1 || { echo "SKIP test-deck-static-mermaid: deckdoc install failed"; exit 0; }
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/sample.md" <<'EOF'
# Static Mermaid

## Approach Overview

```mermaid
%%{init: {'theme':'base', 'themeVariables': {'primaryColor':'#1e1e1e','primaryTextColor':'#fff','primaryBorderColor':'#9096a8','lineColor':'#e7e9f0','secondaryColor':'#2d2d2d','tertiaryColor':'#1e1e1e','background':'#171922','edgeLabelBackground':'#171922'}}}%%
flowchart LR
  A["node A"] -->|edge| B["node B"]
```

## Steps

1. one
EOF

node "$DECKDOC/doc.mjs" "$TMP/sample.md" --out "$TMP/deck.html" --no-source >/dev/null 2>&1 \
  || { echo "  ✗ doc build failed"; exit 1; }

# ---- environment-independent invariants of the CDN build ----
has "$TMP/deck.html" 'id="scv-mermaid-loader"'   "loader script carries its strip-marker id"
has "$TMP/deck.html" 'scv-static'                "loader supports the ?scv-static build mode"
has "$TMP/deck.html" 'scv-static-reveal'         "static mode reveals hidden pages before render"
has "$TMP/deck.html" 'id="scv-mermaid-contrast"' "contrast overrides present"

# no-loader input → clean skip (exit 3), file untouched
printf '<html><head></head><body>no mermaid</body></html>' > "$TMP/plain.html"
cp "$TMP/plain.html" "$TMP/plain.orig"
node "$DECKDOC/static-mermaid.mjs" "$TMP/plain.html" >/dev/null 2>&1
rc=$?
if [[ $rc -eq 3 ]] && cmp -s "$TMP/plain.html" "$TMP/plain.orig"; then pass=$((pass+1)); else
  echo "  ✗ no-mermaid input must skip with exit 3 and stay untouched (rc=$rc)"; fail=$((fail+1)); fi

# ---- the embed itself (needs local Chrome + network to the mermaid CDN) ----
cp "$TMP/deck.html" "$TMP/deck.orig"
if node "$DECKDOC/static-mermaid.mjs" "$TMP/deck.html" > "$TMP/embed.out" 2> "$TMP/embed.err"; then
  has   "$TMP/embed.out"  'STATIC_MERMAID: embedded diagrams=1' "reports one embedded diagram"
  has   "$TMP/deck.html" 'data-scv-static-mermaid="true"'      "static marker on the diagram"
  has   "$TMP/deck.html" '<svg'                                 "inline SVG baked in"
  hasnt "$TMP/deck.html" 'id="scv-mermaid-loader"'              "CDN loader stripped (offline-ready)"
  hasnt "$TMP/deck.html" 'id="scv-static-reveal"'               "build-only reveal style stripped"
  hasnt "$TMP/deck.html" 'data-scv-mermaid-static-done'         "completion marker stripped"
  has   "$TMP/deck.html" 'id="scv-mermaid-contrast"'            "contrast overrides survive the embed"
  # Mermaid bakes its palette three ways and each defeats ordinary CSS. If any
  # comes back, the diagram freezes to whatever the author pasted into the fence
  # and the deck can no longer theme what it renders.
  has   "$TMP/deck.html" 'class="scv-mmd"'                      "the svg is normalized for restyling"
  has   "$TMP/deck.html" 'id="scv-mmd-1"'                       "the svg id is deterministic (rebuilds stay byte-identical)"
  if grep -qE '#mermaid-[0-9]' "$TMP/deck.html"; then
    echo "  ✗ id-scoped mermaid rules survived — author CSS cannot win"; fail=$((fail+1))
  else pass=$((pass+1)); fi
  # Look inside the SVG only. The page's own stylesheet carries a comment that
  # quotes the very attribute this checks for, and a whole-file grep reported the
  # explanation of the fix as the bug.
  if sed -n '/<svg/,/<\/svg>/p' "$TMP/deck.html" | grep -qE 'style="[^"]*(fill|stroke):'; then
    echo "  ✗ inline colour attributes survived — classDef nodes stay frozen"; fail=$((fail+1))
  else pass=$((pass+1)); fi
  head -c 15 "$TMP/deck.html" | grep -qi '<!doctype' \
    && pass=$((pass+1)) || { echo "  ✗ doctype preserved/prepended"; fail=$((fail+1)); }
else
  rc=$?
  if [[ $rc -eq 3 ]] && cmp -s "$TMP/deck.html" "$TMP/deck.orig"; then
    echo "  (embed skipped in this environment — $(tail -1 "$TMP/embed.err" 2>/dev/null); fail-open verified)"
    pass=$((pass+1))
  else
    echo "  ✗ embed failed with rc=$rc but input was modified or wrong exit code"; fail=$((fail+1))
  fi
fi

echo ""

echo "── test-deck-static-mermaid: $pass passed, $fail failed ──"
exit $(( fail > 0 ? 1 : 0 ))
