// transform.mjs — DETERMINISTIC markdown → deck data (pure, no fs/argv).
//
// Single source of truth for BOTH the slide deck (md-to-deck.mjs writes this to
// deck.json for the Vite build) and the lightweight document HTML (deckdoc/doc.mjs
// renders it directly). Keeping one transform means the slide and the doc can
// never diverge. No content is invented: every value comes from the source md.
//
// Only dependency is the remark/unified stack (pure JS, no build/native) — see
// deckdoc/package.json. This is what lets the doc path run without the 339MB
// React/Vite render deps.

import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import remarkFrontmatter from "remark-frontmatter";
import { makeT } from "./i18n.mjs";

// mdast node → plain text (MVP: inline formatting flattened, faithful to words).
const txt = (n) =>
  !n
    ? ""
    : n.type === "text" || n.type === "inlineCode"
      ? n.value
      : Array.isArray(n.children)
        ? n.children.map(txt).join("")
        : n.value || "";

// Flatten a list into display lines. Each item's OWN text = its non-list block
// children joined with a space (so words never fuse — txt()'s ""-join is only
// safe for inline nodes). A nested sub-list is indented one level and marked
// with "· " so hierarchy survives while keeping the flat string[] the block
// model (and the slide renderer) expects.
function listLines(listNode, depth) {
  const lines = [];
  for (const li of listNode.children || []) {
    const own = [];
    const subs = [];
    for (const child of li.children || []) {
      if (child.type === "list") subs.push(child);
      else own.push(txt(child).trim());
    }
    const text = own.filter(Boolean).join(" ");
    if (text) lines.push((depth > 0 ? "  ".repeat(depth) + "· " : "") + text);
    for (const sub of subs) lines.push(...listLines(sub, depth + 1));
  }
  return lines;
}

// A proper NESTED tree of a list, so the document renderer can emit real nested
// <ol>/<ul> with correct per-level numbering (the flat listLines() above stays for
// the slide renderer, which takes a string[]). Each item: { text, children? }
// where children = { ordered, items: Item[] } carries the sub-list's own ordering.
function listItemsTree(listNode) {
  return (listNode.children || []).map((li) => {
    const own = [];
    let child = null;
    for (const c of li.children || []) {
      if (c.type === "list") child = { ordered: !!c.ordered, items: listItemsTree(c) };
      else own.push(txt(c).trim());
    }
    const item = { text: own.filter(Boolean).join(" ") };
    if (child && child.items.length) item.children = child;
    return item;
  });
}

const CALLOUT = { NOTE: "info", TIP: "good", IMPORTANT: "info", WARNING: "warn", CAUTION: "danger" };

function blockOf(node, t) {
  switch (node.type) {
    case "paragraph":
      return { type: "para", text: txt(node) };
    case "list":
      // items = flat marked lines (slide renderer); tree = nested (document renderer).
      // ordered carried so the renderer emits <ol> with correct per-level numbering.
      return { type: "bullets", ordered: !!node.ordered, items: listLines(node, 0), tree: listItemsTree(node) };
    case "code":
      if (node.lang === "mermaid") return { type: "mermaid", code: node.value };
      if (node.lang === "screen") {
        // Claude authors a screen mockup as a JSON object inside a ```screen fence
        // (see commands/promote.md for the schema) — parsed here, deterministically,
        // never fixed up. A malformed block never crashes the whole deck: it becomes a
        // visible error callout, and the raw fence is always inspectable in the side
        // panel (the rendering and the source travel together by design).
        try {
          // The literal type must win over anything the fence body itself contains —
          // spread FIRST, then pin type, so a stray "type" key inside the JSON can't
          // repurpose this block as something else (bypassing the faithfulness rules).
          return { ...JSON.parse(node.value), type: "screen" };
        } catch (e) {
          return {
            type: "callout",
            tone: "danger",
            title: t("screenParseErrorTitle"),
            text: t("screenParseErrorText", e.message),
          };
        }
      }
      return { type: "code", lang: node.lang || "", text: node.value };
    case "table": {
      const rows = node.children.map((tr) => tr.children.map((td) => txt(td).trim()));
      const [headers, ...body] = rows;
      const H = (headers || []).map((h) => h.toLowerCase().trim());
      // Anchored so a normal table whose header merely CONTAINS 지표/현재/목표
      // (e.g. "지표관리자", "현재상태", "목표일자") is NOT mis-read as KPI tiles —
      // but allow the natural metric suffixes 값/치/수치 (현재 값 · 목표치 · 목표 수치).
      const iL = H.findIndex((h) => /^(지표|metric|kpi)$/.test(h));
      const iB = H.findIndex((h) => /^(현재|baseline|as-?is)(\s*(값|치|수치))?$/.test(h));
      const iT = H.findIndex((h) => /^(목표|target|to-?be)(\s*(값|치|수치))?$/.test(h));
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
      // Headings deep enough to reach here are H3+ (H1/H2 start sections upstream)
      // → keep them as sub-headings so subsection structure isn't lost.
      return node.type === "heading"
        ? { type: "subhead", depth: node.depth, text: txt(node).trim() }
        : { type: "para", text: txt(node) };
  }
}

// Strip a leading YAML frontmatter block and/or the FIRST H1 title from a
// markdown string — used to embed a NON-spine slug file under its own divider
// without leaking its frontmatter/title. Uses the REAL remark parser (not a
// regex) so a leading `---` thematic break is NOT mistaken for frontmatter and
// only the file's own leading title (yaml + first depth-1 heading) is removed;
// a following setext/ATX section heading and all body content are preserved.
// A leading `---…---` block parses as a `yaml` node when the file is read standalone
// (frontmatter is only doc-start), but a `---` THEMATIC BREAK followed by markdown and
// a later `---` also captures as `yaml`. So confirm the captured content is actually a
// YAML mapping (key: value / list lines) — otherwise it's a horizontal rule + content
// and must be kept verbatim (a bare regex strip here silently deleted a whole section).
function looksLikeYaml(v) {
  const lines = String(v).split(/\r?\n/).filter((l) => l.trim());
  if (!lines.length) return false;
  return lines.every(
    (l) => /^\s*[A-Za-z_][\w.-]*\s*:/.test(l) || /^\s*-\s/.test(l) || /^\s{2,}\S/.test(l),
  );
}

export function stripLeadingMeta(md) {
  const tree = unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkFrontmatter, ["yaml"])
    .parse(md);
  const kids = tree.children || [];
  let cut = 0;
  let i = 0;
  if (kids[i] && kids[i].type === "yaml" && kids[i].position && looksLikeYaml(kids[i].value)) {
    cut = kids[i].position.end.offset;
    i++;
  }
  if (kids[i] && kids[i].type === "heading" && kids[i].depth === 1 && kids[i].position) {
    cut = kids[i].position.end.offset;
  }
  return cut > 0 ? md.slice(cut).replace(/^\s+/, "") : md;
}

// Parse a markdown planning doc into typed deck data. `slug`/`sourceLabel` are
// already resolved by the caller (CLI). `lang` selects the UI-chrome/lint-message
// language (English default — see i18n.mjs; the SOURCE content itself is never
// translated, only strings this transform generates). Returns
// { title, slug, source, slides, lint }.
export function mdToDeck(raw, slug, sourceLabel, lang) {
  const t = makeT(lang);
  const tree = unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkFrontmatter, ["yaml"])
    .parse(raw);

  // Doc title: first H1 (frontmatter title parsing is out of MVP scope).
  const h1 = tree.children.find((n) => n.type === "heading" && n.depth === 1);
  const docTitle = h1 ? txt(h1).trim() : slug;

  // One slide per heading (depth 1|2). Content before the first heading → cover.
  const slides = [];
  let cur = null;
  const pushCur = () => {
    // Keep an empty section only when it's an explicit H2+ placeholder (that still
    // signals the section exists). Drop an empty pre-heading cover AND an empty H1
    // section — the H1 is already the document title, so an empty one is a dup.
    if (cur && (cur.blocks.length > 0 || (cur.id !== "cover" && (cur.depth || 0) >= 2)))
      slides.push(cur);
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
        depth: node.depth,
        blocks: [],
      };
    } else {
      if (!cur)
        cur = { id: "cover", nav: t("cover"), kicker: "DeckUI", title: docTitle, anchor: docTitle, depth: 0, blocks: [] };
      const b = blockOf(node, t);
      if (b) cur.blocks.push(b);
    }
  }
  pushCur();

  // Post-process: a slide that COMBINES prefixed 목표:/비목표: bullets → a
  // Goals/Non-goals split. Guards (avoid the "비목표 contains 목표" inversion and
  // stripping a word like "목표수립…"): the prefix needs a mandatory delimiter,
  // BOTH buckets must be non-empty, and there must be no stray unprefixed bullet.
  for (const s of slides) {
    const bi = s.blocks.findIndex((b) => b.type === "bullets");
    if (bi < 0) continue;
    const goals = [];
    const nongoals = [];
    const plain = [];
    for (const it of s.blocks[bi].items) {
      if (/^\s*(비목표|non-?goals?|out of scope)\s*[:：·\-]/i.test(it)) {
        nongoals.push(it.replace(/^\s*(비목표|non-?goals?|out of scope)\s*[:：·\-]\s*/i, ""));
      } else if (/^\s*(목표|goals?)\s*[:：·\-]/i.test(it)) {
        goals.push(it.replace(/^\s*(목표|goals?)\s*[:：·\-]\s*/i, ""));
      } else {
        plain.push(it);
      }
    }
    if (goals.length > 0 && nongoals.length > 0 && plain.length === 0) {
      s.blocks[bi] = { type: "goals", goals, nongoals };
    }
  }

  // Lint: canonical planning-doc sections (KO/EN aliases). Warn — never fill in.
  const headingTexts = tree.children.filter((n) => n.type === "heading").map((n) => txt(n).toLowerCase());
  const has = (...keys) => headingTexts.some((h) => keys.some((k) => h.includes(k)));
  const lint = [];
  if (!has("non-goal", "비목표", "out of scope", "범위 밖", "하지 않"))
    lint.push({ level: "warn", message: t("lintNonGoals") });
  if (!has("metric", "지표", "성공 지표", "kpi"))
    lint.push({ level: "warn", message: t("lintMetrics") });
  if (!has("acceptance", "인수", "given/when", "완료 조건"))
    lint.push({ level: "warn", message: t("lintAcceptance") });
  if (!has("edge", "예외", "error", "오류"))
    lint.push({ level: "warn", message: t("lintEdgeCases") });

  return { title: docTitle, slug, source: { label: sourceLabel || `${slug}.md`, text: raw }, slides, lint };
}
