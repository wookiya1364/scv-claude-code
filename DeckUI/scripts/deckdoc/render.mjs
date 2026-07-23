// render.mjs — ZERO-DEPENDENCY deck data → 기획서 문서 HTML (pure string build).
//
// Renders the SAME deck data that transform.mjs produces into ONE self-contained,
// scrollable planning-document HTML — no slides, no React/Vite/build. Reads
// top-to-bottom like a real 기획서 and prints to PDF cleanly. Only string ops;
// no imports. Diagrams use mermaid from CDN with an automatic text fallback
// (offline / closed network → the mermaid source shows as readable code).

// html-escape (every source value passes through this).
const esc = (s) =>
  String(s == null ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

// A stable id for a heading anchor (keeps unicode word chars).
const idOf = (s, i) =>
  "s-" +
  i +
  "-" +
  String(s || "")
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/[^\p{L}\p{N}-]/gu, "")
    .slice(0, 40);

const CALLOUT_LABEL = { info: "참고", good: "좋음", warn: "주의", danger: "위험", next: "다음" };

// Recursively render a bullets tree → nested <ol>/<ul> with correct per-level
// numbering (each level carries its own `ordered`). Falls back to a flat list
// when only the string[] `items` form is present (older deck data).
function renderList(items, ordered) {
  const tag = ordered ? "ol" : "ul";
  const lis = (items || [])
    .map((it) => `<li>${esc(it.text)}${it.children ? renderList(it.children.items, it.children.ordered) : ""}</li>`)
    .join("");
  return `<${tag}>${lis}</${tag}>`;
}

function renderBlock(b, mermaid) {
  switch (b.type) {
    case "para":
      return `<p>${esc(b.text)}</p>`;
    case "subhead": {
      const tag = (b.depth || 3) >= 4 ? "h4" : "h3";
      return `<${tag} class="subhead">${esc(b.text)}</${tag}>`;
    }
    case "bullets":
      // Prefer the nested tree; fall back to the flat string[] as single-level items.
      return renderList(b.tree || (b.items || []).map((t) => ({ text: t })), b.ordered);
    case "table": {
      const head = `<tr>${(b.headers || []).map((h) => `<th>${esc(h)}</th>`).join("")}</tr>`;
      const body = (b.rows || [])
        .map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join("")}</tr>`)
        .join("");
      return `<div class="tw"><table>${b.headers ? `<thead>${head}</thead>` : ""}<tbody>${body}</tbody></table></div>`;
    }
    case "kv": {
      const body = (b.rows || [])
        .map((r) => `<tr><th>${esc(r[0])}</th><td>${esc(r[1])}</td></tr>`)
        .join("");
      return `<div class="tw"><table class="kv"><tbody>${body}</tbody></table></div>`;
    }
    case "kpi":
      return `<div class="kpi">${(b.items || [])
        .map(
          (it) =>
            `<div class="kpi-card"><div class="kpi-label">${esc(it.label)}</div><div class="kpi-nums"><span class="base">${esc(
              it.baseline || "",
            )}</span><span class="arrow">→</span><span class="target">${esc(it.target || "")}</span></div></div>`,
        )
        .join("")}</div>`;
    case "goals":
      return `<div class="goals"><div class="goal-col g"><h4>목표</h4><ul>${(b.goals || [])
        .map((g) => `<li>${esc(g)}</li>`)
        .join("")}</ul></div><div class="goal-col ng"><h4>비목표</h4><ul>${(b.nongoals || [])
        .map((g) => `<li>${esc(g)}</li>`)
        .join("")}</ul></div></div>`;
    case "code":
      return `<pre class="code"><code>${esc(b.text)}</code></pre>`;
    case "mermaid":
      return mermaid === "none"
        ? `<pre class="code mermaid-src"><code>${esc(b.code)}</code></pre>`
        : `<pre class="mermaid">${esc(b.code)}</pre>`;
    case "callout": {
      const tone = b.tone || "info";
      const title = b.title || CALLOUT_LABEL[tone] || "참고";
      return `<div class="callout ${esc(tone)}"><div class="callout-title">${esc(title)}</div><div>${esc(
        b.text,
      )}</div></div>`;
    }
    default:
      return "";
  }
}

const CSS = `
:root{--fg:#1a1d24;--muted:#5b6270;--bg:#ffffff;--panel:#f6f7f9;--border:#e3e6ea;--primary:#2f6feb;--warn:#b8860b;--danger:#c0392b;--good:#1e8e5a;}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;font:16px/1.7 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Noto Sans KR",sans-serif;color:var(--fg);background:var(--panel)}
.wrap{max-width:840px;margin:0 auto;background:var(--bg);min-height:100vh;padding:0 clamp(20px,5vw,56px) 96px;box-shadow:0 0 0 1px var(--border)}
header.doc{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--border);margin:0 calc(clamp(20px,5vw,56px)*-1);padding:18px clamp(20px,5vw,56px);}
header.doc h1{font-size:22px;margin:0;font-weight:700}
nav.toc{background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:14px 18px;margin:26px 0}
nav.toc h3{margin:0 0 8px;font-size:12px;letter-spacing:.04em;color:var(--muted);text-transform:uppercase}
nav.toc ol{margin:0;padding-left:20px;columns:2;gap:24px}
nav.toc a{color:var(--fg);text-decoration:none}
nav.toc a:hover{color:var(--primary);text-decoration:underline}
section{padding:22px 0;border-top:1px solid var(--border)}
section:first-of-type{border-top:none}
h2{font-size:19px;margin:.2em 0 .6em;font-weight:700}
h4{margin:.2em 0 .4em;font-size:14px}
.subhead{font-size:15px;font-weight:600;margin:1.1em 0 .3em;color:var(--fg)}
.kicker{font-size:12px;color:var(--muted);letter-spacing:.03em;margin-bottom:2px}
.sub{color:var(--muted);margin:-.2em 0 1em}
p{margin:.5em 0}
ul,ol{margin:.4em 0;padding-left:22px}
li{margin:.25em 0}
.tw{overflow-x:auto;margin:.8em 0}
table{border-collapse:collapse;width:100%;font-size:14.5px}
th,td{border:1px solid var(--border);padding:8px 11px;text-align:left;vertical-align:top}
thead th{background:var(--panel);font-weight:600}
table.kv th{background:var(--panel);width:30%;white-space:nowrap}
.kpi{display:flex;flex-wrap:wrap;gap:12px;margin:.8em 0}
.kpi-card{flex:1 1 160px;border:1px solid var(--border);border-radius:10px;padding:12px 14px;background:var(--panel)}
.kpi-label{font-size:13px;color:var(--muted);margin-bottom:6px}
.kpi-nums{display:flex;align-items:center;gap:8px;font-weight:700}
.kpi-nums .base{color:var(--muted)}
.kpi-nums .arrow{color:var(--primary)}
.kpi-nums .target{color:var(--good)}
.goals{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:.8em 0}
.goal-col{border:1px solid var(--border);border-radius:10px;padding:10px 14px}
.goal-col.g{border-left:4px solid var(--good)}
.goal-col.ng{border-left:4px solid var(--danger)}
pre.code{background:#0f1320;color:#e6e9f0;border-radius:10px;padding:14px 16px;overflow-x:auto;font:13px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace;margin:.8em 0}
pre.mermaid{background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:16px;text-align:center;margin:.8em 0}
pre.mermaid.mermaid-fallback{text-align:left;white-space:pre;overflow-x:auto;background:#0f1320;color:#e6e9f0;font:13px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace;padding:30px 16px 14px;position:relative}
pre.mermaid.mermaid-fallback::before{content:"\\29c9 \\b2e4\\c774\\c5b4\\adf8\\b7a8 \\c6d0\\bcf8 (\\c624\\d504\\b77c\\c778 \\b610\\b294 CDN \\bbf8\\b85c\\b4dc)";position:absolute;top:8px;left:16px;font:600 11px/1 -apple-system,sans-serif;color:#9aa4b2}
.callout{border:1px solid var(--border);border-left-width:4px;border-radius:8px;padding:11px 14px;margin:.8em 0;background:var(--panel)}
.callout-title{font-weight:700;font-size:13px;margin-bottom:3px}
.callout.info{border-left-color:var(--primary)}
.callout.good{border-left-color:var(--good)}
.callout.warn{border-left-color:var(--warn)}
.callout.danger{border-left-color:var(--danger)}
.callout.next{border-left-color:var(--primary)}
.lint h2{color:var(--warn)}
.lint-count{display:inline-block;background:var(--warn);color:#fff;border-radius:999px;font-size:12px;padding:1px 9px;vertical-align:middle}
details.source{margin-top:32px;border:1px solid var(--border);border-radius:10px;padding:6px 14px}
details.source summary{cursor:pointer;font-size:13px;color:var(--muted);padding:6px 0}
@media (max-width:640px){.goals{grid-template-columns:1fr}nav.toc ol{columns:1}}
@media print{
  body{background:#fff}
  .wrap{box-shadow:none;max-width:none;padding:0}
  header.doc{position:static}
  nav.toc{break-inside:avoid}
  section{break-inside:avoid}
  details.source[open]{break-before:page}
  details.source summary{list-style:none}
}
`;

// Render deck data → self-contained HTML string.
// opts: { mermaid: "cdn" | "none" (default "cdn"), source: boolean (default true) }
export function renderHtml(data, opts = {}) {
  const mermaid = opts.mermaid || "cdn";
  const withSource = opts.source !== false;
  const slides = data.slides || [];

  const toc = slides
    .map((s, i) => `<li><a href="#${idOf(s.title, i)}">${esc(s.title)}</a></li>`)
    .join("");

  const sections = slides
    .map((s, i) => {
      const kicker = s.kicker && s.kicker !== s.title ? `<div class="kicker">${esc(s.kicker)}</div>` : "";
      const sub = s.sub ? `<p class="sub">${esc(s.sub)}</p>` : "";
      const body = (s.blocks || []).map((b) => renderBlock(b, mermaid)).join("\n");
      return `<section id="${idOf(s.title, i)}">${kicker}<h2>${esc(s.title)}</h2>${sub}${body}</section>`;
    })
    .join("\n");

  const lint = data.lint || [];
  const lintSection = lint.length
    ? `<section id="__lint" class="lint"><h2>품질 리포트 <span class="lint-count">${lint.length}</span></h2>
     <p class="sub">원문에 없는 내용은 채우지 않음 — 전문 기획서가 보통 갖추는데 이 문서엔 빠진 항목입니다.</p>
     ${lint.map((l) => `<div class="callout warn"><div>${esc(l.message)}</div></div>`).join("")}</section>`
    : "";

  const sourceSection =
    withSource && data.source && data.source.text
      ? `<details class="source"><summary>기획서 원문 (${esc(
          data.source.label || "source",
        )})</summary><pre class="code"><code>${esc(data.source.text)}</code></pre></details>`
      : "";

  const hasMermaid = slides.some((s) => (s.blocks || []).some((b) => b.type === "mermaid"));
  // CDN 기본 + 자동 텍스트 폴백: CDN 로드가 실패(오프라인·폐쇄망)하면 <pre class="mermaid">에
  // 담긴 mermaid 원본 코드를 그대로 읽히도록 .mermaid-fallback 로 표시한다.
  const mermaidScript =
    mermaid === "none" || !hasMermaid
      ? ""
      : `<script type="module">
  try {
    const { default: mermaid } = await import("https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs");
    mermaid.initialize({ startOnLoad: false, theme: "default", securityLevel: "strict" });
    await mermaid.run({ querySelector: "pre.mermaid" });
  } catch (e) {
    for (const el of document.querySelectorAll("pre.mermaid")) el.classList.add("mermaid-fallback");
  }
</script>`;

  const title = esc(data.title || data.slug || "기획서");
  return `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<style>${CSS}</style>
</head>
<body>
<div class="wrap">
<header class="doc"><h1>${title}</h1></header>
${toc ? `<nav class="toc"><h3>목차</h3><ol>${toc}</ol></nav>` : ""}
${sections}
${lintSection}
${sourceSection}
</div>
${mermaidScript}
</body>
</html>
`;
}
