#!/usr/bin/env node
// md-to-deck.mjs — DETERMINISTIC markdown → deck.json transform (DeckUI).
//
// Parses a markdown planning doc into a typed deck data structure that
// MarkdownDeck.tsx renders with DeckUI primitives. No content is invented:
// every rendered value comes from the source. The raw markdown is carried
// verbatim as the SourcePanel source. A lint pass warns about missing
// canonical planning-doc sections (it never fills them in).
//
// Usage: node scripts/md-to-deck.mjs <input.md> [slug]
// Output: src/deck/decks/<slug>/deck.json  (auto-discovered by MarkdownDeck)

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, basename, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import remarkFrontmatter from "remark-frontmatter";

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

const tree = unified()
  .use(remarkParse)
  .use(remarkGfm)
  .use(remarkFrontmatter, ["yaml"])
  .parse(raw);

// mdast node → plain text (MVP: inline formatting flattened, faithful to words).
const txt = (n) =>
  !n
    ? ""
    : n.type === "text" || n.type === "inlineCode"
      ? n.value
      : Array.isArray(n.children)
        ? n.children.map(txt).join("")
        : n.value || "";

const CALLOUT = { NOTE: "info", TIP: "good", IMPORTANT: "info", WARNING: "warn", CAUTION: "danger" };

function blockOf(node) {
  switch (node.type) {
    case "paragraph":
      return { type: "para", text: txt(node) };
    case "list":
      return {
        type: "bullets",
        items: node.children.map((li) => txt(li).trim()).filter(Boolean),
      };
    case "code":
      return node.lang === "mermaid"
        ? { type: "mermaid", code: node.value }
        : { type: "code", lang: node.lang || "", text: node.value };
    case "table": {
      const rows = node.children.map((tr) => tr.children.map((td) => txt(td).trim()));
      const [headers, ...body] = rows;
      const H = (headers || []).map((h) => h.toLowerCase());
      const iL = H.findIndex((h) => /지표|metric|kpi/.test(h));
      const iB = H.findIndex((h) => /현재|baseline|as-?is/.test(h));
      const iT = H.findIndex((h) => /목표|target|to-?be/.test(h));
      if (iL >= 0 && iB >= 0 && iT >= 0) {
        // metric table → KPI tiles (baseline → target)
        return {
          type: "kpi",
          items: body.map((r) => ({ label: r[iL] || "", baseline: r[iB] || "", target: r[iT] || "" })),
        };
      }
      return { type: "table", headers: headers || [], rows: body };
    }
    case "blockquote": {
      let t = txt(node).trim();
      const m = t.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*/i);
      let tone = "info";
      if (m) {
        tone = CALLOUT[m[1].toUpperCase()] || "info";
        t = t.slice(m[0].length).trim();
      }
      return { type: "callout", tone, text: t };
    }
    case "thematicBreak":
      return null;
    default:
      return node.type === "heading" ? null : { type: "para", text: txt(node) };
  }
}

// Doc title: first H1 (frontmatter title parsing is out of MVP scope).
const h1 = tree.children.find((n) => n.type === "heading" && n.depth === 1);
const docTitle = h1 ? txt(h1).trim() : slug;

// One slide per heading (depth 1|2). Content before the first heading → cover.
const slides = [];
let cur = null;
const pushCur = () => {
  if (cur && (cur.blocks.length > 0 || cur.id === "cover")) slides.push(cur);
};
for (const node of tree.children) {
  if (node.type === "yaml") continue;
  if (node.type === "heading" && node.depth <= 2) {
    pushCur();
    const title = txt(node).trim();
    cur = {
      id: `s${slides.length}`,
      nav: title.slice(0, 18) || `s${slides.length}`,
      kicker: docTitle,
      title,
      anchor: title,
      blocks: [],
    };
  } else {
    if (!cur)
      cur = { id: "cover", nav: "표지", kicker: "DeckUI", title: docTitle, anchor: docTitle, blocks: [] };
    const b = blockOf(node);
    if (b) cur.blocks.push(b);
  }
}
pushCur();

// Post-process: a "목표 / 비목표" slide whose bullets are prefixed (목표: / 비목표:)
// → a Goals/Non-goals split block. Faithful — only reorganizes the author's own
// bullets, adds nothing.
for (const s of slides) {
  if (!/목표|goal/i.test(s.title) || !/비목표|non-?goal|out.?of.?scope|범위 밖/i.test(s.title)) continue;
  const bi = s.blocks.findIndex((b) => b.type === "bullets");
  if (bi < 0) continue;
  const goals = [];
  const nongoals = [];
  for (const it of s.blocks[bi].items) {
    if (/^\s*(비목표|non-?goals?|out of scope)/i.test(it)) {
      nongoals.push(it.replace(/^\s*(비목표|non-?goals?|out of scope)\s*[:：·\-]?\s*/i, ""));
    } else {
      goals.push(it.replace(/^\s*(목표|goals?)\s*[:：·\-]?\s*/i, ""));
    }
  }
  if (goals.length || nongoals.length) s.blocks[bi] = { type: "goals", goals, nongoals };
}

// Lint: canonical planning-doc sections (KO/EN aliases). Warn — never fill in.
const headingTexts = tree.children.filter((n) => n.type === "heading").map((n) => txt(n).toLowerCase());
const has = (...keys) => headingTexts.some((h) => keys.some((k) => h.includes(k)));
const lint = [];
if (!has("non-goal", "비목표", "out of scope", "범위 밖", "하지 않"))
  lint.push({ level: "warn", message: "비목표(Non-goals / Out-of-scope) 섹션이 없습니다 — 범위 경계가 모호해질 수 있습니다." });
if (!has("metric", "지표", "성공 지표", "kpi"))
  lint.push({ level: "warn", message: "성공지표(Metrics) 섹션이 없습니다 — baseline→target 지표를 권장합니다." });
if (!has("acceptance", "인수", "given/when", "완료 조건"))
  lint.push({ level: "warn", message: "인수기준(Acceptance criteria) 섹션이 없습니다." });
if (!has("edge", "예외", "error", "오류"))
  lint.push({ level: "warn", message: "예외처리(Edge cases) 섹션이 없습니다." });

const data = { title: docTitle, slug, source: { label: basename(input), text: raw }, slides, lint };
const outDir = resolve(DECKS_DIR, slug);
mkdirSync(outDir, { recursive: true });
writeFileSync(resolve(outDir, "deck.json"), JSON.stringify(data, null, 2) + "\n");

console.log(`DECK_SLUG: ${slug}`);
console.log(`DECK_JSON: ${resolve(outDir, "deck.json")}`);
console.log(`SLIDES: ${slides.length}`);
console.log(`LINT: ${lint.length} warning(s)`);
lint.forEach((l) => console.log(`  ⚠ ${l.message}`));
