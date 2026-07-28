#!/usr/bin/env node
// md-to-deck.mjs — SLIDE-path CLI: markdown → deck.json for the DeckUI Vite build.
//
// The transform itself lives in deckdoc/transform.mjs (the single source of truth
// shared with the buildless document path, deckdoc/doc.mjs) so the slide deck and
// the document HTML can never diverge. This file just resolves the slug, calls the
// shared transform, and writes deck.json where MarkdownDeck.tsx auto-discovers it.
//
// Usage: node scripts/md-to-deck.mjs <input.md> [slug]
// Output: src/deck/decks/<slug>/deck.json

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, basename, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { mdToDeck } from "./deckdoc/transform.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DECKS_DIR = resolve(__dirname, "../src/deck/decks");

const input = process.argv[2];
if (!input) {
  console.error("usage: md-to-deck.mjs <input.md> [slug]");
  process.exit(1);
}
const raw = readFileSync(input, "utf8");
const slug =
  (process.argv[3] || basename(input).replace(/\.md$/i, ""))
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "deck";

// Reads SCV_LANG the same way doc.mjs does — both CLIs must resolve the SAME
// language from the SAME environment, or the byte-identical doc/slide invariant
// breaks whenever a project sets SCV_LANG to anything but the shared default.
const data = mdToDeck(raw, slug, basename(input), process.env.SCV_LANG || "english");

const outDir = resolve(DECKS_DIR, slug);
mkdirSync(outDir, { recursive: true });
writeFileSync(resolve(outDir, "deck.json"), JSON.stringify(data, null, 2) + "\n");

console.log(`DECK_SLUG: ${slug}`);
console.log(`DECK_JSON: ${resolve(outDir, "deck.json")}`);
console.log(`SLIDES: ${data.slides.length}`);
console.log(`LINT: ${data.lint.length} warning(s)`);
data.lint.forEach((l) => console.log(`  ⚠ ${l.message}`));
