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
  # The id must be BOTH stable across rebuilds and unique within the document.
  # A single fixed value bought the first at the cost of the second, and the
  # cost was not cosmetic: every arrowhead marker, filter and gradient is keyed
  # off this id, so identical ids made three diagrams share the first one's
  # markers. It is now derived from the drawing itself.
  if grep -qE 'id="scv-mmd-[0-9a-f]{10}(-[0-9]+)?"' "$TMP/deck.html"; then pass=$((pass+1)); else
    echo "  ✗ the svg id is not derived from the diagram's content"; fail=$((fail+1)); fi
  if grep -q 'id="scv-mmd-1"' "$TMP/deck.html"; then
    echo "  ✗ the old single fixed id is back — diagrams would share markers"; fail=$((fail+1))
  else pass=$((pass+1)); fi
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

# ---- several diagrams in ONE document ---------------------------------------
# The single-diagram fixture above cannot see this class of bug at all. With two
# or more, mermaid's clock-derived ids collided inside the same millisecond: the
# loser resolved its id to the winner's element and came out as an empty <svg>
# with no viewBox — which is how a wireframe diagram rendered blank while the
# ones before it were fine.
cat > "$TMP/multi.md" <<'EOF'
# Multi

## One

```mermaid
flowchart LR
  A["첫째"] -->|간다| B["둘째"]
```

## Two

```mermaid
flowchart TB
  C["셋째"] --> D["넷째"]
  D --> E["다섯째"]
```

## Three

```mermaid
flowchart LR
  F["여섯째"] --> G["일곱째"]
```
EOF

if node "$DECKDOC/doc.mjs" "$TMP/multi.md" --out "$TMP/multi.html" --no-source >/dev/null 2>&1 \
   && node "$DECKDOC/static-mermaid.mjs" "$TMP/multi.html" > "$TMP/multi.out" 2>/dev/null; then
  ids="$(grep -oE '<svg [^>]*class="scv-mmd" id="[^"]+"' "$TMP/multi.html" | sed 's/.*id="//; s/"$//')"
  [[ -z "$ids" ]] && ids="$(grep -oE 'id="scv-mmd-[0-9a-f]{10}(-[0-9]+)?"' "$TMP/multi.html" | sort -u | sed 's/id="//; s/"$//')"
  n_total=$(printf '%s\n' "$ids" | grep -c . || true)
  n_uniq=$(printf '%s\n' "$ids" | sort -u | grep -c . || true)
  if [[ "$n_total" -ge 3 && "$n_total" -eq "$n_uniq" ]]; then pass=$((pass+1)); else
    echo "  ✗ diagram ids are not unique within one document ($n_total found, $n_uniq distinct)"; fail=$((fail+1)); fi

  # An empty graphic is the collision's other face — assert it directly.
  if grep -q '<g></g></svg>' "$TMP/multi.html"; then
    echo "  ✗ a diagram rendered empty — id collision is back"; fail=$((fail+1))
  else pass=$((pass+1)); fi

  # No viewBox means no size, and the svg keeps width="100%" and collapses.
  if grep -qE '<svg[^>]*class="scv-mmd"[^>]*width="100%"' "$TMP/multi.html"; then
    echo "  ✗ a diagram carries no size (width stayed 100%)"; fail=$((fail+1))
  else pass=$((pass+1)); fi

  # Markers are keyed off the diagram id; duplicates make every diagram borrow
  # the first one's arrowheads.
  mk_total=$(grep -oE 'id="scv-mmd-[0-9a-f]{10}(-[0-9]+)?_flowchart-v2-pointEnd"' "$TMP/multi.html" | grep -c . || true)
  mk_uniq=$(grep -oE 'id="scv-mmd-[0-9a-f]{10}(-[0-9]+)?_flowchart-v2-pointEnd"' "$TMP/multi.html" | sort -u | grep -c . || true)
  if [[ "$mk_total" -eq "$mk_uniq" ]]; then pass=$((pass+1)); else
    echo "  ✗ arrowhead marker ids collide ($mk_total found, $mk_uniq distinct)"; fail=$((fail+1)); fi

  # Byte stability is the contract this artifact is committed under.
  h1=$(sha256sum "$TMP/multi.html" | cut -d' ' -f1)
  node "$DECKDOC/doc.mjs" "$TMP/multi.md" --out "$TMP/multi2.html" --no-source >/dev/null 2>&1
  node "$DECKDOC/static-mermaid.mjs" "$TMP/multi2.html" >/dev/null 2>&1
  h2=$(sha256sum "$TMP/multi2.html" | cut -d' ' -f1)
  if [[ "$h1" == "$h2" ]]; then pass=$((pass+1)); else
    echo "  ✗ two builds of the same input differ — the committed artifact would churn"; fail=$((fail+1)); fi

  # Inserting a diagram must not move the others' bytes. That is the whole
  # reason the id comes from the content and not from a sequence number.
  { printf '# Multi\n\n## Zero\n\n```mermaid\nflowchart LR\n  Z1["끼움"] --> Z2["시험"]\n```\n\n'; tail -n +2 "$TMP/multi.md"; } > "$TMP/multi3.md"
  if node "$DECKDOC/doc.mjs" "$TMP/multi3.md" --out "$TMP/multi3.html" --no-source >/dev/null 2>&1 \
     && node "$DECKDOC/static-mermaid.mjs" "$TMP/multi3.html" >/dev/null 2>&1; then
    kept=0
    for one in $ids; do grep -q "id=\"$one\"" "$TMP/multi3.html" && kept=$((kept+1)); done
    if [[ "$kept" -eq "$n_total" ]]; then pass=$((pass+1)); else
      echo "  ✗ inserting a diagram changed the others' ids ($kept/$n_total kept)"; fail=$((fail+1)); fi
  fi
else
  echo "  (multi-diagram checks skipped in this environment)"
fi

echo ""

echo "── test-deck-static-mermaid: $pass passed, $fail failed ──"
exit $(( fail > 0 ? 1 : 0 ))
