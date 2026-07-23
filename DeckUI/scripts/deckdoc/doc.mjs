#!/usr/bin/env node
// doc.mjs — buildless CLI: markdown → 기획서 문서 HTML (one self-contained file).
//
// Pipeline: transform.mjs (md → deck data; remark) → render.mjs (deck data → HTML;
// zero-dep). No Vite, no React, no bundle. The only install is this folder's slim
// remark stack (see package.json) — a few MB, not the 339MB slide-render deps.
//
// Input can be EITHER:
//   • a single markdown file, OR
//   • an scv slug FOLDER (scv/promote/<slug>/ or scv/archive/<slug>/) — then PLAN.md
//     + FEATURE_ARCHITECTURE.md + TESTS.md are combined into ONE 기획서, written next
//     to the markdown as <slug>.deck.html. This is what /scv:promote and /scv:work
//     regenerate so the deck always tracks the plan.
//
// Usage: node doc.mjs <input.md|slug-dir> [slug] [--out <path>] [--mermaid cdn|none] [--no-source] [--emit-json]
// Emits (for deck.sh to parse):
//   DECK_SLUG: <slug>
//   LINT: <n> warning(s)   (+ one "  ⚠ ..." line each)
//   DECK_HTML: <absolute path>

import { readFileSync, writeFileSync, mkdirSync, statSync, existsSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { mdToDeck, stripLeadingMeta } from "./transform.mjs";
import { renderHtml } from "./render.mjs";
import { makeT } from "./i18n.mjs";

const normalizeSlug = (s) =>
  s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "deck";

// A slug folder's parts, in reading order. The first present file is the SPINE
// (its H1 becomes the document title); the rest are appended under a labeled
// divider with their own leading H1 stripped (the spine already titled the doc).
// Labels are resolved to `lang` (English default — see i18n.mjs).
function slugParts(t) {
  return [
    { file: "PLAN.md", label: null },
    { file: "FEATURE_ARCHITECTURE.md", label: t("featureArchitectureLabel") },
    { file: "TESTS.md", label: t("testsLabel") },
  ];
}
function buildSlugDoc(dir, t) {
  const present = slugParts(t)
    .map((p) => ({ ...p, path: resolve(dir, p.file) }))
    .filter((p) => existsSync(p.path));
  if (!present.length)
    throw new Error(`slug folder has no PLAN.md / FEATURE_ARCHITECTURE.md / TESTS.md: ${dir}`);
  const parts = [];
  const sources = []; // pristine per-file text for the side panel — never the stripped/joined version
  present.forEach((p, i) => {
    const text = readFileSync(p.path, "utf8").trim();
    sources.push({ label: p.file, text });
    // Spine keeps its frontmatter (parsed at document start) + H1 as the doc title.
    // Non-spine parts get their leading frontmatter/title stripped (parser-based, so
    // a leading `---` rule or a following section heading is preserved).
    if (i === 0) parts.push(text);
    else parts.push(`\n\n---\n\n## ${p.label || p.file.replace(/\.md$/i, "")}\n\n${stripLeadingMeta(text)}`);
  });
  return { raw: parts.join("\n"), label: present.map((p) => p.file).join(" + "), sources };
}

// ---- args ----
// Language resolution mirrors scripts/render-template.sh's SCV_LANG convention
// (settings.json `language` → .env `SCV_LANG` resolve upstream, at the Claude/deck.sh
// layer; this CLI only reads the already-resolved env var, English default). --lang
// lets a caller override explicitly without touching the environment.
let INPUT = "";
let SLUG = "";
let OUT = "";
let MERMAID = "cdn";
let SOURCE = true;
let EMIT_JSON = false;
let LANG = process.env.SCV_LANG || "english";
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--out") OUT = argv[++i] || "";
  else if (a.startsWith("--out=")) OUT = a.slice(6);
  else if (a === "--mermaid") MERMAID = argv[++i] || "cdn";
  else if (a.startsWith("--mermaid=")) MERMAID = a.slice(10);
  else if (a === "--lang") LANG = argv[++i] || "english";
  else if (a.startsWith("--lang=")) LANG = a.slice(7);
  else if (a === "--no-source") SOURCE = false;
  else if (a === "--emit-json") EMIT_JSON = true;
  else if (a === "-h" || a === "--help") {
    console.log(
      "usage: doc.mjs <input.md|slug-dir> [slug] [--out <path>] [--mermaid cdn|none] [--lang english|korean|japanese] [--no-source] [--emit-json]",
    );
    process.exit(0);
  } else if (a.startsWith("-")) {
    console.error(`unknown flag: ${a}`);
    process.exit(1);
  } else if (!INPUT) INPUT = a;
  else if (!SLUG) SLUG = a;
}
const t = makeT(LANG);
if (!INPUT) {
  console.error("usage: doc.mjs <input.md|slug-dir> [slug] [--out <path>]");
  process.exit(1);
}
INPUT = resolve(INPUT);
if (!existsSync(INPUT)) {
  console.error(`input not found: ${INPUT}`);
  process.exit(1);
}

// ---- resolve input → (raw markdown, slug, source label, default output) ----
const isDir = statSync(INPUT).isDirectory();
let raw, slug, sourceLabel, defaultOut, sources;
if (isDir) {
  let combined;
  try {
    combined = buildSlugDoc(INPUT, t);
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
  raw = combined.raw;
  slug = normalizeSlug(SLUG || basename(INPUT));
  sourceLabel = combined.label;
  sources = combined.sources; // pristine PLAN.md/FEATURE_ARCHITECTURE.md/TESTS.md — one tab each
  defaultOut = resolve(INPUT, `${slug}.deck.html`); // lives next to the markdown, committed
} else {
  raw = readFileSync(INPUT, "utf8");
  slug = normalizeSlug(SLUG || basename(INPUT).replace(/\.md$/i, ""));
  sourceLabel = basename(INPUT);
  sources = [{ label: sourceLabel, text: raw }];
  defaultOut = resolve(process.cwd(), `${slug}-doc.html`);
}

const data = mdToDeck(raw, slug, sourceLabel, LANG);
// render.mjs already guards the known crash vectors (wrong-typed screen-DSL fields,
// runaway nesting); this catch is defense-in-depth for anything still unforeseen —
// a clear error + nonzero exit beats a raw Node stack trace and zero bytes written.
let html;
try {
  html = renderHtml(data, { mermaid: MERMAID, source: SOURCE, sources, lang: LANG });
} catch (e) {
  console.error(`render failed: ${e.message}`);
  process.exit(1);
}

if (!OUT) OUT = defaultOut;
OUT = resolve(OUT);
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, html);

if (EMIT_JSON) {
  const jsonPath = resolve(dirname(OUT), `${slug}.deck.json`);
  writeFileSync(jsonPath, JSON.stringify(data, null, 2) + "\n");
  console.log(`DECK_JSON: ${jsonPath}`);
}

console.log(`DECK_SLUG: ${slug}`);
console.log(`LINT: ${data.lint.length} warning(s)`);
data.lint.forEach((l) => console.log(`  ⚠ ${l.message}`));
console.log(`DECK_HTML: ${OUT}`);
