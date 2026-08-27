#!/usr/bin/env node
// doc.mjs — buildless CLI: markdown → 기획서 문서 HTML (one self-contained file).
//
// Pipeline: transform.mjs (md → deck data; remark) → render.mjs (deck data → HTML;
// zero-dep). No Vite, no React, no bundle. The only install is this folder's slim
// remark stack (see package.json) — a few MB, not the 339MB slide-render deps.
//
// Input can be EITHER:
//   • a single markdown file, OR
//   • an scv slug FOLDER (scv/promote/<slug>/ or scv/archive/<slug>/) — then the
//     PICTURE doc (FEATURE_ARCHITECTURE.md) becomes the 기획서, written next to the
//     markdown as <slug>.deck.html. PLAN.md / TESTS.md still travel as source-panel
//     tabs; --full puts all three back in the body. A folder with no picture doc
//     builds NOTHING (prints DECK_SKIPPED, exits 0) rather than a wall of prose.
//     This is what /scv:promote and /scv:work regenerate so the deck tracks the plan.
//
// Usage: node doc.mjs <input.md|slug-dir> [slug] [--out <path>] [--mermaid cdn|none] [--no-source] [--emit-json] [--full]
// Emits (for deck.sh to parse):
//   DECK_SLUG: <slug>
//   LINT: <n> warning(s)   (+ one "  ⚠ ..." line each)
//   DECK_HTML: <absolute path>
//   DECK_SKIPPED: <reason>   (instead of the three above — no picture doc, nothing built)

import { readFileSync, writeFileSync, mkdirSync, statSync, existsSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { mdToDeck, stripLeadingMeta } from "./transform.mjs";
import { renderHtml } from "./render.mjs";
import { makeT } from "./i18n.mjs";

const normalizeSlug = (s) =>
  s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "deck";

// A slug folder's parts, in reading order. Which of them reach the rendered body is
// decided by selectRenderParts below; every present part always reaches the source
// panel. Labels are resolved to `lang` (English default — see i18n.mjs).
function slugParts(t) {
  return [
    { file: "PLAN.md", label: null },
    { file: "FEATURE_ARCHITECTURE.md", label: t("featureArchitectureLabel") },
    { file: "TESTS.md", label: t("testsLabel") },
  ];
}
// The picture document. A 기획서 is a BIG PICTURE carrying numbered markers with
// the detail hanging off those numbers — that shape lives in FEATURE_ARCHITECTURE.md.
// PLAN.md / TESTS.md are prose by nature, and combining all three is how a deck came
// out twenty sections deep with only two of them a picture. They still travel with
// the deck as source-panel tabs, so nothing is lost — only the BODY narrows.
const PICTURE_PART = "FEATURE_ARCHITECTURE.md";

// ① 읽기 — the only file read on the folder path (pipeline entry; side effect).
function readSlugParts(dir, t) {
  const present = slugParts(t)
    .map((p) => ({ ...p, path: resolve(dir, p.file) }))
    .filter((p) => existsSync(p.path));
  if (!present.length)
    throw new Error(`slug folder has no PLAN.md / FEATURE_ARCHITECTURE.md / TESTS.md: ${dir}`);
  // pristine per-file text — never the stripped/joined version
  return present.map((p) => ({ file: p.file, label: p.label, text: readFileSync(p.path, "utf8").trim() }));
}

// ② 고르기 — pure. Splits "what gets rendered as the body" from "what travels as a
// source tab". Default: the picture doc alone. `full` restores the three-doc combine.
function selectRenderParts(parts, { full = false } = {}) {
  return { body: full ? parts : parts.filter((p) => p.file === PICTURE_PART), sources: parts };
}

// ③ 본문 만들기 — pure. The first body part is the SPINE (its H1 titles the document);
// the rest are appended under a labeled divider with their own leading H1 stripped.
// A lone body part needs neither divider nor label — it IS the document.
function composeBody(bodyParts) {
  return bodyParts
    .map((p, i) =>
      // Spine keeps its frontmatter (parsed at document start) + H1 as the doc title.
      // Non-spine parts get their leading frontmatter/title stripped (parser-based, so
      // a leading `---` rule or a following section heading is preserved).
      i === 0
        ? p.text
        : `\n\n---\n\n## ${p.label || p.file.replace(/\.md$/i, "")}\n\n${stripLeadingMeta(p.text)}`,
    )
    .join("\n");
}

// ---- args ----
// Language resolution mirrors scripts/render-template.sh's SCV_LANG convention
// (settings.json `language` → .env `SCV_LANG` resolve upstream, at the Claude Code/deck.sh
// layer; this CLI only reads the already-resolved env var, English default). --lang
// lets a caller override explicitly without touching the environment.
let INPUT = "";
let SLUG = "";
let OUT = "";
let MERMAID = "cdn";
let SOURCE = true;
let EMIT_JSON = false;
let FULL = false;
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
  else if (a === "--full") FULL = true;
  else if (a === "-h" || a === "--help") {
    console.log(
      "usage: doc.mjs <input.md|slug-dir> [slug] [--out <path>] [--mermaid cdn|none] [--lang english|korean|japanese] [--no-source] [--emit-json] [--full]",
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
// Section-presence lint is judged over EVERY part, not just the rendered body —
// see mdToDeck's `lintRaw`.
let lintRaw;
if (isDir) {
  let parts;
  try {
    parts = readSlugParts(INPUT, t);
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
  const picked = selectRenderParts(parts, { full: FULL });
  if (!picked.body.length) {
    // ⑥ 만들 것 없음. A deck of nothing but prose is the wall of sentences this
    // default exists to remove, and that prose already lives in PLAN.md / TESTS.md.
    // Not an error: callers (/scv:promote, /scv:work) must keep going.
    console.log(`DECK_SKIPPED: ${t("deckSkippedNoPicture")}`);
    process.exit(0);
  }
  raw = composeBody(picked.body);
  // Composed the SAME way as the body, over every part — so the divider labels the
  // combine injects (e.g. "Acceptance Criteria (TESTS)") are present for the lint here
  // exactly as they were when all three docs were the body. With --full the two strings
  // are identical, so the deck comes out byte-for-byte as it did before this default.
  lintRaw = composeBody(parts);
  slug = normalizeSlug(SLUG || basename(INPUT));
  sourceLabel = picked.body.map((p) => p.file).join(" + ");
  sources = picked.sources.map((p) => ({ label: p.file, text: p.text })); // one tab each
  defaultOut = resolve(INPUT, `${slug}.deck.html`); // lives next to the markdown, committed
} else {
  raw = readFileSync(INPUT, "utf8");
  lintRaw = raw;
  slug = normalizeSlug(SLUG || basename(INPUT).replace(/\.md$/i, ""));
  sourceLabel = basename(INPUT);
  sources = [{ label: sourceLabel, text: raw }];
  defaultOut = resolve(process.cwd(), `${slug}-doc.html`);
}

const data = mdToDeck(raw, slug, sourceLabel, LANG, lintRaw);
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
