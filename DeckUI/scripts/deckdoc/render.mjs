// render.mjs — ZERO-DEPENDENCY deck data → 기획서 문서 HTML (pure string build).
//
// Renders the SAME deck data that transform.mjs produces into ONE self-contained
// deck HTML — no React/Vite/build, only string ops, no imports. On screen it pages
// one section at a time (‹ 이전 / 다음 ›, dot indicators, numbered jump-nav, arrow
// keys) with the side panel auto-tracking the current page — same navigation model
// the original SlideDeck/SourcePanel had. Print/PDF instead gets one continuous,
// paginated document (every section stacked, table of contents, source appendix) —
// paging is a screen-only convenience, never a barrier to "read this on paper."
// Diagrams use mermaid from CDN with an automatic text fallback (offline / closed
// network → the mermaid source shows as readable code).

import { makeT, normalizeLang } from "./i18n.mjs";

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

function renderBlock(b, mermaid, t) {
  switch (b.type) {
    case "para":
      return `<p>${esc(b.text)}</p>`;
    case "subhead": {
      const tag = (b.depth || 3) >= 4 ? "h4" : "h3";
      return `<${tag} class="subhead">${esc(b.text)}</${tag}>`;
    }
    case "bullets":
      // Prefer the nested tree; fall back to the flat string[] as single-level items.
      return renderList(b.tree || (b.items || []).map((text) => ({ text })), b.ordered);
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
      return `<div class="goals"><div class="goal-col g"><h4>${t("goals")}</h4><ul>${(b.goals || [])
        .map((g) => `<li>${esc(g)}</li>`)
        .join("")}</ul></div><div class="goal-col ng"><h4>${t("nonGoals")}</h4><ul>${(b.nongoals || [])
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
      const CALLOUT_KEY = { info: "calloutInfo", good: "calloutGood", warn: "calloutWarn", danger: "calloutDanger", next: "calloutNext" };
      const title = b.title || t(CALLOUT_KEY[tone] || "calloutInfo");
      return `<div class="callout ${esc(tone)}"><div class="callout-title">${esc(title)}</div><div>${esc(
        b.text,
      )}</div></div>`;
    }
    case "screen":
      return renderScreen(b, t);
    default:
      return "";
  }
}

// ---- screen mockup (wireframe) — PROTOTYPE ----
// A tiny, project-neutral component vocabulary (nav/header/toolbar/tabs/table/
// card/list/form/badge/button/text) rendered as a plain gray-box wireframe — no
// brand colors, no external design system, no build. This is what makes a PLAN's
// screen description actually LOOK like a screen instead of only reading as prose.
const BADGE_TONE = { muted: "wf-badge-muted", info: "wf-badge-info", good: "wf-badge-good", warn: "wf-badge-warn", danger: "wf-badge-danger" };
// Claude authors the screen JSON (commands/promote.md Step 6.4), but a slip is still
// possible — never let a wrong-but-truthy type (string/object instead of array) throw
// and kill the whole doc.mjs process. `arr()` degrades to an empty list instead.
const arr = (x) => (Array.isArray(x) ? x : []);
// Bracket lookup on a plain object walks the prototype chain — a tone/variant value of
// "__proto__"/"constructor"/"toString" would otherwise resolve to a native function and
// leak into an unescaped class attribute. hasOwnProperty confines the lookup to our own keys.
const safeTone = (t) => (Object.prototype.hasOwnProperty.call(BADGE_TONE, t) ? BADGE_TONE[t] : BADGE_TONE.muted);
const MAX_WF_DEPTH = 40; // guards runaway/adversarial card-in-card nesting from overflowing the stack

// ---- project-token override (screen mockup "theme" field) ----
// 1순위(프로젝트 실제 토큰) / 2순위(scv 자체 스킨) 판별: scv 자체 스킨이 기본이고, 사용자가
// "우리 프로젝트엔 디자인 토큰이 있다"고 말한 경우에만(commands/promote.md Step 6.4가
// scv/DESIGN.md §5 를 읽어 판단) Claude 가 screen JSON 에 `theme` 필드로 실제 hex 값만
// 넘긴다. 그 외 파생값(투명 배지 배경, 명암비 안전한 on-primary 텍스트)은 여기서 항상
// 계산한다 — Claude 가 매번 대비를 직접 판단하게 두면 v0.18.0 에서 실제로 터진 WCAG
// 버그가 재발한다. 검증 실패한 값은 조용히 무시하고 scv 기본값을 유지한다(크래시 없음).
const hex6 = (h) => {
  const m = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.exec(String(h || "").trim());
  if (!m) return null;
  const s = m[1];
  return (s.length === 3 ? s.split("").map((c) => c + c).join("") : s).toLowerCase();
};
const rgbOf = (h6) => [0, 2, 4].map((i) => parseInt(h6.slice(i, i + 2), 16));
const relLuminance = ([r, g, b]) => {
  const f = (c) => ((c /= 255), c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
};
const onColorFor = (hex) => {
  const h = hex6(hex);
  return h ? (relLuminance(rgbOf(h)) > 0.5 ? "#12141a" : "#ffffff") : null;
};
const tint = (hex, alpha) => {
  const h = hex6(hex);
  if (!h) return null;
  const [r, g, b] = rgbOf(h);
  return `rgba(${r},${g},${b},${alpha})`;
};
const WF_RADIUS_RE = /^\d+(\.\d+)?(px|rem|em)$/;

// A screen block's optional `theme` (base hex colors only — exactly what a project's
// own scv/DESIGN.md §5 documents) → an inline `style="--wf-*:..."` string that overrides
// the scv-native defaults declared on .wf-screen. Every value is independently
// validated (hex/length regex) before use; anything that fails validation is dropped,
// never inserted — the base CSS default silently takes over for that one property.
function themeStyleOf(theme) {
  if (!theme || typeof theme !== "object") return "";
  const decls = [];
  const put = (name, val) => val != null && decls.push(`--wf-${name}:${val}`);
  put("bg", hex6(theme.bg) && `#${hex6(theme.bg)}`);
  put("fg", hex6(theme.fg) && `#${hex6(theme.fg)}`);
  put("card", hex6(theme.card) && `#${hex6(theme.card)}`);
  put("border", hex6(theme.border) && `#${hex6(theme.border)}`);
  put("muted", hex6(theme.muted) && `#${hex6(theme.muted)}`);
  put("muted-fg", hex6(theme.mutedFg) && `#${hex6(theme.mutedFg)}`);
  if (hex6(theme.primary)) {
    put("primary", `#${hex6(theme.primary)}`);
    put("primary-fg", onColorFor(theme.primary));
  }
  for (const role of ["success", "danger", "warn", "info"]) {
    const v = theme[role];
    if (!hex6(v)) continue;
    put(role, `#${hex6(v)}`);
    put(`${role}-bg`, tint(v, 0.15));
    if (role === "success") put("success-border", tint(v, 0.4));
  }
  if (WF_RADIUS_RE.test(String(theme.radius || ""))) put("radius", theme.radius);
  return decls.length ? ` style="${esc(decls.join(";"))}"` : "";
}

function renderCell(c) {
  if (c == null) return "";
  if (typeof c !== "object") return esc(c);
  if (c.badge !== undefined) return `<span class="wf-badge ${safeTone(c.tone)}">${esc(c.badge)}</span>`;
  if (c.button !== undefined) return `<button class="wf-btn wf-btn-${esc(c.variant || "secondary")}" disabled>${esc(c.button)}</button>`;
  return "";
}

function renderComponent(c, depth, t) {
  depth = depth || 0;
  if (!c || !c.type) return "";
  if (depth > MAX_WF_DEPTH) return `<p class="wf-text">${esc(t("nestedTooDeep"))}</p>`;
  switch (c.type) {
    case "header":
      return `<div class="wf-header"><div class="wf-header-title">${esc(c.title)}</div>${c.subtitle ? `<div class="wf-header-sub">${esc(c.subtitle)}</div>` : ""}</div>`;
    case "toolbar":
      return `<div class="wf-toolbar">${arr(c.items)
        .map((it) =>
          it && it.type === "input"
            ? `<span class="wf-input">${esc(it.placeholder || "")}</span>`
            : `<button class="wf-btn wf-btn-${esc((it && it.variant) || "secondary")}" disabled>${esc(it && it.label)}</button>`,
        )
        .join("")}</div>`;
    case "tabs":
      return `<div class="wf-tabs">${arr(c.items)
        .map((t) => `<span class="wf-tab${t === c.active ? " active" : ""}">${esc(t)}</span>`)
        .join("")}</div>`;
    case "table": {
      const head = `<tr>${arr(c.columns).map((h) => `<th>${esc(h)}</th>`).join("")}</tr>`;
      const body = arr(c.rows)
        .map((r) => `<tr>${arr(r).map((cell) => `<td>${renderCell(cell)}</td>`).join("")}</tr>`)
        .join("");
      return `<table class="wf-table"><thead>${head}</thead><tbody>${body}</tbody></table>`;
    }
    case "card":
      return `<div class="wf-card">${c.title ? `<div class="wf-card-title">${esc(c.title)}</div>` : ""}${arr(c.body)
        .map((x) => renderComponent(x, depth + 1, t))
        .join("")}</div>`;
    case "list":
      return `<ul class="wf-list">${arr(c.items)
        .map((it) => `<li><span>${esc(it && it.label)}</span>${it && it.action ? `<button class="wf-btn wf-btn-secondary" disabled>${esc(it.action)}</button>` : ""}</li>`)
        .join("")}</ul>`;
    case "form":
      return `<div class="wf-form">${arr(c.fields)
        .map((f) => `<label class="wf-field"><span>${esc(f && f.label)}</span><span class="wf-input">${esc((f && f.value) || "")}</span></label>`)
        .join("")}</div>`;
    case "badge":
      return `<span class="wf-badge ${safeTone(c.tone)}">${esc(c.label)}</span>`;
    case "button":
      return `<button class="wf-btn wf-btn-${esc(c.variant || "secondary")}" disabled>${esc(c.label)}</button>`;
    case "text":
      return `<p class="wf-text">${esc(c.value)}</p>`;
    default:
      return "";
  }
}

function renderScreen(b, t) {
  const nav =
    b.nav && typeof b.nav === "object"
      ? `<div class="wf-nav">${arr(b.nav.items)
          .map((it) => `<span class="wf-nav-item${it === b.nav.active ? " active" : ""}">${esc(it)}</span>`)
          .join("")}</div>`
      : "";
  const body = arr(b.body)
    .map((x) => renderComponent(x, 0, t))
    .join("");
  // theme absent (the common case — no project tokens told to us) → identical to before,
  // zero behavior change. theme present → inline style overrides just the validated keys.
  return `<div class="wf-screen"${themeStyleOf(b.theme)}>${b.title ? `<div class="wf-screen-label">${esc(b.title)}</div>` : ""}<div class="wf-frame">${nav}<div class="wf-body">${body}</div></div></div>`;
}

const CSS = `
/* 다크가 기본값(--bg/--panel 등 전부). 라이트는 html[data-theme="light"] 오버라이드 —
   FE 프로젝트의 다크-기본+라이트-오버라이드 관례와 동일한 모양(속성 하나만 바뀌면
   전체가 재테마된다). head 맨 앞 인라인 스크립트가 pre-paint 로 저장된 선택을 적용해
   깜빡임(FOUC)이 없다. */
:root{--fg:#e7e9f0;--muted:#9096a8;--bg:#171922;--panel:#1d2029;--border:#2c3040;--primary:#7c93ff;--warn:#e0ab48;--danger:#ef6b6b;--good:#3ecf8e;--page-bg:#0d0e13;--on-primary:#12163a;--on-warn:#241a06;}
html[data-theme="light"]{--fg:#1a1d24;--muted:#5b6270;--bg:#ffffff;--panel:#f6f7f9;--border:#e3e6ea;--primary:#2f6feb;--warn:#b8860b;--danger:#c0392b;--good:#1e8e5a;--page-bg:#f6f7f9;--on-primary:#ffffff;}
*{box-sizing:border-box}
html,body{height:100%}
html{scroll-behavior:smooth}
body{margin:0;font:16px/1.7 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Noto Sans KR",sans-serif;color:var(--fg);background:var(--page-bg)}
/* 문서 = 스크롤되는 본문(좌) + 상시 원문 마크다운 패널(우, sticky) — 이게 scv:deck 의
   정체성이다: 렌더링과 원문이 늘 같은 화면에 나란히 있어야 서로 어긋나지 않았다는 게
   보장된다. 인쇄 시에는 패널을 접고 본문 뒤에 원문을 부록으로 붙인다(.print-source). */
.shell{display:flex;height:100vh;overflow:hidden}
.scroll-main{flex:1;min-width:0;overflow-y:auto}
.wrap{max-width:840px;margin:0 auto;background:var(--bg);min-height:100%;padding:0 clamp(20px,5vw,56px) 96px;box-shadow:0 0 0 1px var(--border)}
header.doc{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--border);margin:0 calc(clamp(20px,5vw,56px)*-1);padding:18px clamp(20px,5vw,56px);display:flex;align-items:center;gap:14px;justify-content:space-between}
header.doc h1{font-size:22px;margin:0;font-weight:700}
.header-actions{display:flex;align-items:center;gap:8px;flex-shrink:0}
.theme-toggle,.panel-toggle{flex-shrink:0;font:600 12px/1 inherit;color:var(--muted);background:var(--panel);border:1px solid var(--border);border-radius:7px;padding:7px 11px;cursor:pointer}
.theme-toggle:hover,.panel-toggle:hover{background:var(--border);color:var(--fg)}
.panel-toggle .kbd{opacity:.55;margin-left:4px}
.source-panel{position:relative;width:min(440px,38vw);flex-shrink:0;border-left:1px solid var(--border);background:var(--panel);display:flex;flex-direction:column}
.source-panel.closed{display:none}
.panel-resize-handle{position:absolute;left:0;top:0;bottom:0;width:7px;margin-left:-4px;cursor:col-resize;z-index:6}
.panel-resize-handle:hover{background:rgba(127,137,160,.25)}
.panel-head{display:flex;align-items:center;justify-content:space-between;padding:13px 16px;border-bottom:1px solid var(--border);flex-shrink:0}
.panel-title{font-size:12px;color:var(--muted);font-weight:700;letter-spacing:.02em}
.panel-close{border:none;background:none;color:var(--muted);cursor:pointer;font-size:14px;padding:2px 7px;border-radius:5px;line-height:1.4}
.panel-close:hover{background:var(--border);color:var(--fg)}
.panel-tabs{display:flex;gap:2px;padding:9px 12px 0;border-bottom:1px solid var(--border);flex-shrink:0;overflow-x:auto}
.panel-tab{font:600 12px/1 inherit;color:var(--muted);padding:7px 10px;border:none;background:none;border-bottom:2px solid transparent;cursor:pointer;white-space:nowrap}
.panel-tab.active{color:var(--fg);border-bottom-color:var(--primary)}
.panel-body{flex:1;overflow-y:auto;padding:14px}
.panel-body .src-doc{display:none;margin:0}
.panel-body .src-doc.active{display:block}
.print-source{display:none}
/* 목차(nav.toc) 는 인쇄본 전용(펼친 전체 문서엔 목차가 자연스럽다). 화면에서는
   deck-nav(아래) 가 같은 역할을 대신한다 — 페이지 번호 pill + 클릭 이동. */
@media screen{nav.toc{display:none}}
nav.toc{background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:14px 18px;margin:26px 0}
nav.toc h3{margin:0 0 8px;font-size:12px;letter-spacing:.04em;color:var(--muted);text-transform:uppercase}
nav.toc ol{margin:0;padding-left:20px;columns:2;gap:24px}
nav.toc a{color:var(--fg);text-decoration:none}
nav.toc a:hover{color:var(--primary);text-decoration:underline}
section{padding:22px 0;border-top:1px solid var(--border)}
section:first-of-type{border-top:none}
/* 페이지 넘김(화면 전용) — 한 번에 한 섹션만. 인쇄 시엔 전부 펼쳐서 보여준다. */
@media screen{.slide-page{display:none}.slide-page.active{display:block}}
.deck-nav{display:flex;flex-wrap:wrap;gap:6px;margin:20px 0}
.deck-nav-item{font:600 12px/1 inherit;color:var(--muted);background:var(--panel);border:1px solid var(--border);border-radius:7px;padding:7px 11px;cursor:pointer;white-space:nowrap}
.deck-nav-item:hover{color:var(--fg)}
.deck-nav-item.active{background:var(--primary);color:var(--on-primary);border-color:var(--primary)}
.deck-footer{display:flex;align-items:center;justify-content:space-between;gap:14px;margin-top:8px;padding-top:20px;border-top:1px solid var(--border)}
.deck-arrow{font:600 13px/1 inherit;color:var(--fg);background:var(--bg);border:1px solid var(--border);border-radius:8px;padding:9px 16px;cursor:pointer}
.deck-arrow:disabled{opacity:.35;cursor:default}
.deck-arrow:not(:disabled):hover{background:var(--panel)}
.deck-dots{display:flex;align-items:center;gap:6px}
.deck-dot{width:8px;height:8px;border-radius:999px;background:var(--border);border:none;cursor:pointer;padding:0}
.deck-dot.active{background:var(--primary);width:20px;border-radius:5px}
.deck-counter{font-size:12px;color:var(--muted);min-width:52px;text-align:center}
mark.src-hl{background:#ffe58a;color:#3a2f00;border-radius:3px;padding:0 1px}
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
/* mermaid 는 항상 라이트 카드에 그린다(테마 무관, pre.code 가 항상 다크인 것과 대칭) —
   mermaid 렌더 테마를 다크로 다시 그리려면 이미 SVG 로 처리된 노드를 되돌려야 해서
   토글마다 재처리가 필요해진다. 대신 다이어그램 카드 자체를 고정 라이트로 둬서
   토글과 무관하게 항상 선명하게 읽힌다. */
pre.mermaid{background:#f6f7f9;border:1px solid var(--border);border-radius:10px;padding:16px;text-align:center;margin:.8em 0}
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
.lint-count{display:inline-block;background:var(--warn);color:var(--on-warn);border-radius:999px;font-size:12px;padding:1px 9px;vertical-align:middle}
/* 화면목업(와이어프레임) 킷 — scv 자체 기본 스킨(2순위 폴백): DesignSystem 의 실제
   다크 팔레트를 distill(무채색 표면 + 단일 로즈 악센트 + border-only depth + pill
   배지, 글라스 없음 — DesignSystem 본체엔 글라스가 없다). 문서 자체의 라이트/다크
   토글과는 독립적으로 항상 이 다크 스킨을 쓴다(--wf-* 로 스코프해 문서 테마 변수와
   충돌하지 않음) — mermaid 카드를 항상 라이트로 고정하는 것과 같은 이유(재처리 없이
   항상 또렷하게). 프로젝트 실제 토큰(1순위) 자동감지는 아직 없음 — 후속 작업.
   버튼은 항상 disabled(정적 예시 그림이라 실제 인터랙션 없음). */
.wf-screen{
  margin:1em 0;
  --wf-bg:#0a0a0b; --wf-fg:#fafafa; --wf-card:#1c1c1e; --wf-border:rgba(255,255,255,.1);
  --wf-muted:#232326; --wf-muted-fg:#9a9a9f;
  --wf-primary:#a53257; --wf-primary-fg:#fdf1f3;
  --wf-success:#34d399; --wf-success-bg:rgba(16,185,129,.15); --wf-success-border:rgba(16,185,129,.4);
  --wf-danger:#ef6b6b; --wf-danger-bg:rgba(239,107,107,.14);
  --wf-info:#60a5fa; --wf-info-bg:rgba(96,165,250,.15);
  --wf-warn:#e0ab48; --wf-warn-bg:rgba(224,171,72,.15);
  --wf-radius:10px; --wf-radius-pill:999px;
}
.wf-screen-label{font-size:12px;color:var(--muted);margin-bottom:6px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
.wf-frame{border:1px solid var(--wf-border);border-radius:var(--wf-radius);background:var(--wf-bg);color:var(--wf-fg);overflow:hidden}
.wf-nav{display:flex;gap:2px;padding:0 16px;border-bottom:1px solid var(--wf-border);background:var(--wf-bg);flex-wrap:wrap}
.wf-nav-item{font-size:13px;color:var(--wf-muted-fg);padding:12px 11px;border-bottom:2px solid transparent}
.wf-nav-item.active{color:var(--wf-fg);font-weight:600;border-bottom-color:var(--wf-primary)}
.wf-body{padding:20px}
.wf-header{margin-bottom:0}
.wf-header-title{font-size:16px;font-weight:600;color:var(--wf-fg)}
.wf-header-sub{font-size:12.5px;color:var(--wf-muted-fg);margin-top:3px}
.wf-toolbar{display:flex;gap:8px;margin:14px 0;flex-wrap:wrap}
.wf-tabs{display:flex;gap:2px;margin-bottom:12px;border-bottom:1px solid var(--wf-border)}
.wf-tab{font-size:12.5px;color:var(--wf-muted-fg);padding:7px 11px;border-bottom:2px solid transparent}
.wf-tab.active{color:var(--wf-fg);font-weight:600;border-bottom-color:var(--wf-muted-fg)}
.wf-btn{font:500 12.5px/1 inherit;padding:8px 13px;border-radius:8px;border:1px solid transparent;background:var(--wf-muted);color:var(--wf-fg);cursor:default}
.wf-btn-primary{background:var(--wf-primary);color:var(--wf-primary-fg)}
.wf-btn-danger{background:var(--wf-danger-bg);color:var(--wf-danger)}
.wf-input{display:inline-flex;align-items:center;font-size:12.5px;color:var(--wf-muted-fg);padding:8px 12px;border:1px solid var(--wf-border);border-radius:8px;background:var(--wf-card);min-width:120px}
.wf-table{width:100%;border-collapse:collapse;font-size:12.5px;margin-top:4px}
.wf-table th,.wf-table td{border-bottom:1px solid var(--wf-border);padding:9px 10px;text-align:left}
.wf-table th{color:var(--wf-muted-fg);font-weight:500;font-size:11.5px;text-transform:uppercase;letter-spacing:.02em}
.wf-badge{display:inline-flex;align-items:center;height:20px;border-radius:var(--wf-radius-pill);padding:0 9px;font-size:10.5px;font-weight:500;border:1px solid transparent}
.wf-badge-muted{background:var(--wf-muted);color:var(--wf-muted-fg);border-color:var(--wf-border)}
.wf-badge-info{background:var(--wf-info-bg);color:var(--wf-info);border-color:rgba(96,165,250,.35)}
.wf-badge-good{background:var(--wf-success-bg);color:var(--wf-success);border-color:var(--wf-success-border)}
.wf-badge-warn{background:var(--wf-warn-bg);color:var(--wf-warn);border-color:rgba(224,171,72,.35)}
.wf-badge-danger{background:var(--wf-danger-bg);color:var(--wf-danger);border-color:rgba(239,107,107,.35)}
.wf-card{border-radius:var(--wf-radius);border:1px solid var(--wf-border);padding:14px 16px;margin-bottom:10px;background:var(--wf-card)}
.wf-card-title{font-size:13px;font-weight:600;color:var(--wf-fg);margin-bottom:8px}
.wf-list{list-style:none;margin:0;padding:0}
.wf-list li{display:flex;justify-content:space-between;align-items:center;padding:10px 0;border-bottom:1px solid var(--wf-border);font-size:12.5px;color:var(--wf-fg)}
.wf-list li:last-child{border-bottom:none}
.wf-form{display:flex;flex-direction:column;gap:8px}
.wf-field{display:flex;flex-direction:column;gap:3px;font-size:11.5px;color:var(--wf-muted-fg)}
.wf-text{font-size:12.5px;color:var(--wf-fg);margin:.3em 0}
@media (max-width:900px){.source-panel{width:min(360px,44vw)}}
@media (max-width:640px){.goals{grid-template-columns:1fr}nav.toc ol{columns:1}.shell{flex-direction:column;height:auto;overflow:visible}.scroll-main{overflow:visible}.source-panel{width:100%;height:60vh}}
@media print{
  body{background:#fff;display:block;height:auto}
  .shell{display:block;height:auto;overflow:visible}
  .scroll-main{overflow:visible;height:auto}
  .wrap{box-shadow:none;max-width:none;padding:0}
  header.doc{position:static}
  .panel-toggle{display:none}
  .source-panel{display:none}
  .deck-nav{display:none}
  .deck-footer{display:none}
  nav.toc{display:block;break-inside:avoid}
  section{break-inside:avoid}
  .print-source{display:block;break-before:page}
  .print-source h3{margin-top:1.6em;font-size:14px}
}
`;

// Render deck data → self-contained HTML string.
// opts: { mermaid: "cdn" | "none" (default "cdn"), source: boolean (default true),
//         sources: [{label,text}] (default: [data.source] when present) }
//
// scv:deck's defining trait: the raw markdown travels ALONGSIDE the rendering, in an
// always-on side panel (toggle button or the `S` key) — never only a footnote. Multiple
// source files (a slug-folder combine: PLAN.md/FEATURE_ARCHITECTURE.md/TESTS.md) show as
// tabs, matching the original SlideDeck/SourcePanel convention this document path must
// preserve. Print/PDF instead gets a plain paginated appendix (a side-by-side panel
// makes no sense on paper).
export function renderHtml(data, opts = {}) {
  const t = makeT(opts.lang);
  const mermaid = opts.mermaid || "cdn";
  const withSource = opts.source !== false;
  const sources = withSource ? opts.sources || (data.source ? [data.source] : []) : [];
  const slides = data.slides || [];

  // 인쇄용 목차는 anchor 링크 그대로(전체 문서가 한 번에 펼쳐지므로 앵커 이동이 유효).
  const toc = slides
    .map((s, i) => `<li><a href="#${idOf(s.title, i)}">${esc(s.title)}</a></li>`)
    .join("");

  const lint = data.lint || [];
  const pageCount = slides.length + (lint.length ? 1 : 0);

  // 화면 전용 페이지 네비게이션 — 원본 SlideDeck 과 같은 모델(pill 번호 nav + ‹›
  // + dot). anchors[i] 는 그 페이지가 사이드패널에서 하이라이트할 원문 헤딩 텍스트.
  const navLabels = slides.map((s) => s.nav || s.title).concat(lint.length ? [t("qualityReportTitle")] : []);
  const anchors = slides.map((s) => s.anchor || s.title).concat(lint.length ? [null] : []);
  // 단일 페이지 문서엔 "페이지 이동" UI 자체가 의미 없다 — nav/footer 둘 다 같은
  // 기준(pageCount > 1)으로 게이트해 "눌러도 아무 일 없는" 활성 pill 이 남지 않게 한다.
  const deckNav = pageCount > 1
    ? `<nav class="deck-nav">${navLabels
        .map((n, i) => `<button class="deck-nav-item${i === 0 ? " active" : ""}" data-idx="${i}" onclick="scvGoto(${i})">${i + 1}. ${esc(n)}</button>`)
        .join("")}</nav>`
    : "";
  const deckFooter =
    pageCount > 1
      ? `<div class="deck-footer">
      <button class="deck-arrow" id="scvPrev" disabled onclick="scvGoto(scvIdx()-1)">${esc(t("prev"))}</button>
      <div class="deck-dots">${navLabels
        .map((_, i) => `<button class="deck-dot${i === 0 ? " active" : ""}" data-idx="${i}" onclick="scvGoto(${i})" aria-label="${i + 1}"></button>`)
        .join("")}</div>
      <span class="deck-counter" id="scvCounter">1 / ${pageCount}</span>
      <button class="deck-arrow" id="scvNext" onclick="scvGoto(scvIdx()+1)">${esc(t("next"))}</button>
    </div>`
      : "";

  const sections = slides
    .map((s, i) => {
      const kicker = s.kicker && s.kicker !== s.title ? `<div class="kicker">${esc(s.kicker)}</div>` : "";
      const sub = s.sub ? `<p class="sub">${esc(s.sub)}</p>` : "";
      const body = (s.blocks || []).map((b) => renderBlock(b, mermaid, t)).join("\n");
      return `<section id="${idOf(s.title, i)}" class="slide-page${i === 0 ? " active" : ""}" data-idx="${i}">${kicker}<h2>${esc(s.title)}</h2>${sub}${body}</section>`;
    })
    .join("\n");

  const lintSection = lint.length
    ? `<section id="__lint" class="lint slide-page${slides.length === 0 ? " active" : ""}" data-idx="${slides.length}"><h2>${esc(t("qualityReportTitle"))} <span class="lint-count">${lint.length}</span></h2>
     <p class="sub">${esc(t("qualityReportSub"))}</p>
     ${lint.map((l) => `<div class="callout warn"><div>${esc(l.message)}</div></div>`).join("")}</section>`
    : "";

  // Side panel (screen) — always-visible, tabbed if multiple source files.
  const panelToggle = sources.length
    ? `<button class="panel-toggle" onclick="scvTogglePanel()" title="${esc(t("sourcePanelToggleTitle"))}">${esc(t("sourcePanelLabel"))} <span class="kbd">S</span></button>`
    : "";
  const themeToggle = `<button class="theme-toggle" id="scvThemeBtn" onclick="scvToggleTheme()" title="${esc(t("themeToggleTitle"))}"></button>`;
  const headerActions = `<div class="header-actions">${themeToggle}${panelToggle}</div>`;
  const panelTabs =
    sources.length > 1
      ? `<div class="panel-tabs">${sources
          .map(
            (s, i) =>
              `<button class="panel-tab${i === 0 ? " active" : ""}" data-idx="${i}" onclick="scvSelectSource(${i})">${esc(
                s.label || t("documentFallback", i + 1),
              )}</button>`,
          )
          .join("")}</div>`
      : "";
  const panelBodies = sources
    .map((s, i) => `<pre class="code src-doc${i === 0 ? " active" : ""}" data-idx="${i}"><code>${esc(s.text)}</code></pre>`)
    .join("");
  const sourcePanel = sources.length
    ? `<aside class="source-panel" id="scvSourcePanel">
      <div class="panel-resize-handle" id="scvResizeHandle" title="${esc(t("resizeHandleTitle"))}"></div>
      <div class="panel-head"><span class="panel-title">${esc(t("sourcePanelLabel"))}${
        sources.length === 1 ? ` · ${esc(sources[0].label || "source")}` : ""
      }</span><button class="panel-close" onclick="scvTogglePanel()" title="${esc(t("panelCloseTitle"))}">✕</button></div>
      ${panelTabs}
      <div class="panel-body">${panelBodies}</div>
    </aside>`
    : "";

  // Print/PDF appendix — a side panel makes no sense on paper, so this becomes a
  // plain paginated section instead (same source text, one <h3> per file).
  const printSource = sources.length
    ? `<section class="print-source"><h2>${esc(t("sourcePanelLabel"))}</h2>${sources
        .map((s) => `<h3>${esc(s.label || "source")}</h3><pre class="code"><code>${esc(s.text)}</code></pre>`)
        .join("")}</section>`
    : "";

  // Pagination + highlight-sync (screen only) — one script owns both concerns so
  // there is a SINGLE keydown listener. scvGoto(n) flips the visible .slide-page
  // and asks scvHighlight to find that page's anchor heading inside each source's
  // ORIGINAL text (read back via .textContent, so re-marking never compounds),
  // switch the panel to the matching tab, wrap that heading-to-next-heading chunk
  // in <mark>, and scroll it into view — the "이 장이 어느 원문 구간인지" sync.
  const pageScript = pageCount
    ? `<script>
  var SCV_ANCHORS = ${JSON.stringify(anchors)};
  var scvPageIdx = 0;
  function scvIdx(){ return scvPageIdx; }
  function scvEsc(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
  function scvHighlight(anchor){
    var docs = document.querySelectorAll('.src-doc');
    docs.forEach(function(el){
      var code = el.querySelector('code');
      if(code) code.innerHTML = scvEsc(code.textContent);
    });
    if(!anchor) return;
    for (var i=0;i<docs.length;i++){
      var code = docs[i].querySelector('code');
      if(!code) continue;
      var raw = code.textContent;
      var lines = raw.split('\\n');
      var start=-1, end=lines.length;
      for (var j=0;j<lines.length;j++){
        var m = lines[j].match(/^#{1,6}\\s+(.*)$/);
        if (m && m[1].trim() === String(anchor).trim()) { start = j; break; }
      }
      if (start < 0) continue;
      for (var k=start+1;k<lines.length;k++){ if (/^#{1,6}\\s+/.test(lines[k])) { end = k; break; } }
      var before = lines.slice(0,start).join('\\n'), hl = lines.slice(start,end).join('\\n'), after = lines.slice(end).join('\\n');
      code.innerHTML = scvEsc(before) + (before ? '\\n' : '') + '<mark class="src-hl">' + scvEsc(hl) + '</mark>' + (after ? '\\n' + scvEsc(after) : '');
      if (typeof scvSelectSource === 'function') scvSelectSource(i);
      var markEl = docs[i].querySelector('mark.src-hl');
      if (markEl && markEl.scrollIntoView) markEl.scrollIntoView({ block: 'center' });
      return;
    }
  }
  function scvGoto(n){
    var total = ${pageCount};
    n = Math.max(0, Math.min(total - 1, n));
    scvPageIdx = n;
    document.querySelectorAll('.slide-page').forEach(function(p){ p.classList.toggle('active', p.dataset.idx === String(n)); });
    document.querySelectorAll('.deck-nav-item').forEach(function(el){ el.classList.toggle('active', el.dataset.idx === String(n)); });
    document.querySelectorAll('.deck-dot').forEach(function(el){ el.classList.toggle('active', el.dataset.idx === String(n)); });
    if (typeof window.scvRunMermaid === 'function') { try { window.scvRunMermaid(); } catch (e) {} }
    var prevBtn = document.getElementById('scvPrev'), nextBtn = document.getElementById('scvNext'), counter = document.getElementById('scvCounter');
    if (prevBtn) prevBtn.disabled = (n === 0);
    if (nextBtn) nextBtn.disabled = (n === total - 1);
    if (counter) counter.textContent = (n + 1) + ' / ' + total;
    scvHighlight(SCV_ANCHORS[n]);
    var main = document.querySelector('.scroll-main');
    if (main) main.scrollTop = 0;
  }
  ${
    sources.length
      ? `function scvTogglePanel(){ var p=document.getElementById('scvSourcePanel'); if(p) p.classList.toggle('closed'); }
  function scvSelectSource(i){
    document.querySelectorAll('.panel-tab').forEach(function(el){ el.classList.toggle('active', String(i)===el.dataset.idx); });
    document.querySelectorAll('.src-doc').forEach(function(el){ el.classList.toggle('active', String(i)===el.dataset.idx); });
  }
  (function(){
    // 패널 좌측 경계 드래그 리사이즈 — 원본 SourcePanel 과 같은 산식(최소 320px,
    // 본문에 최소 420px 남김).
    var handle = document.getElementById('scvResizeHandle');
    var panel = document.getElementById('scvSourcePanel');
    if (!handle || !panel) return;
    var MOBILE_BP = 640;
    handle.addEventListener('mousedown', function(e){
      e.preventDefault();
      document.body.style.userSelect = 'none';
      document.body.style.cursor = 'col-resize';
      function onMove(ev){
        // 버튼을 놓친 채(창 밖 등) mouseup 을 못 받은 경우 — 버튼이 눌려있지 않으면 즉시 정리.
        if (ev.buttons === 0) { onUp(); return; }
        var raw = window.innerWidth - ev.clientX;
        var max = Math.max(320, window.innerWidth - 420);
        panel.style.width = Math.min(max, Math.max(320, raw)) + 'px';
      }
      function onUp(){
        document.body.style.userSelect = '';
        document.body.style.cursor = '';
        window.removeEventListener('mousemove', onMove);
        window.removeEventListener('mouseup', onUp);
        window.removeEventListener('blur', onUp);
      }
      window.addEventListener('mousemove', onMove);
      window.addEventListener('mouseup', onUp);
      window.addEventListener('blur', onUp);
    });
    // 인라인 width 는 스타일시트의 반응형 브레이크포인트(640px 모바일 전체폭·900px 좁은폭)
    // 보다 항상 우선한다 — 창 크기가 바뀔 때마다 다시 맞춰줘야 브레이크포인트가 살아난다.
    window.addEventListener('resize', function(){
      if (!panel.style.width) return;
      if (window.innerWidth <= MOBILE_BP) { panel.style.width = ''; return; }
      var max = Math.max(320, window.innerWidth - 420);
      if (parseFloat(panel.style.width) > max) panel.style.width = max + 'px';
    });
  })();`
      : ""
  }
  document.addEventListener('keydown', function(e){
    var t = e.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    if (e.key === 'ArrowRight' || e.key === 'PageDown') scvGoto(scvIdx() + 1);
    else if (e.key === 'ArrowLeft' || e.key === 'PageUp') scvGoto(scvIdx() - 1);
    else if (e.key === 'Home') scvGoto(0);
    else if (e.key === 'End') scvGoto(${pageCount} - 1);
    ${sources.length ? `else if (e.key === 's' || e.key === 'S') scvTogglePanel();` : ""}
  });
  scvGoto(0);
</script>`
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
    // Scoped to the ACTIVE page only: mermaid measures text at run-time, so a diagram
    // processed while its .slide-page is display:none comes out zero/tiny-sized — and
    // because mermaid marks nodes data-processed="true" and skips them afterwards, that
    // broken render would stick even after the page becomes visible. Re-run this scoped
    // call every time scvGoto shows a NEW page, so each diagram is first measured exactly
    // when its page is on-screen; revisiting an already-correct page is a harmless no-op.
    window.scvRunMermaid = function () { mermaid.run({ querySelector: ".slide-page.active pre.mermaid" }); };
    await window.scvRunMermaid();
    // Printing bypasses the pager (every .slide-page is visible under @media print), so
    // catch any diagram never visited on screen right before the print dialog opens.
    window.addEventListener("beforeprint", function () { mermaid.run({ querySelector: "pre.mermaid" }); });
  } catch (e) {
    for (const el of document.querySelectorAll("pre.mermaid")) el.classList.add("mermaid-fallback");
  }
</script>`;

  // 다크 기본값 + 라이트 오버라이드. localStorage 에 저장된 선택을 <head> 맨 앞에서
  // (스타일/본문 파싱 전) 적용해 라이트를 골랐던 사용자가 재방문 시 깜빡임 없이 바로
  // 라이트로 뜨게 한다.
  const themeInit = `<script>(function(){try{if(localStorage.getItem('scv-deck-theme')==='light')document.documentElement.setAttribute('data-theme','light');}catch(e){}})();</script>`;
  const THEME_LIGHT_LABEL = JSON.stringify(t("themeLight"));
  const THEME_DARK_LABEL = JSON.stringify(t("themeDark"));
  const themeScript = `<script>
  function scvThemeLabel(){ return document.documentElement.getAttribute('data-theme')==='light' ? ${THEME_LIGHT_LABEL} : ${THEME_DARK_LABEL}; }
  function scvToggleTheme(){
    var html = document.documentElement;
    var next = html.getAttribute('data-theme')==='light' ? 'dark' : 'light';
    if (next === 'light') html.setAttribute('data-theme','light'); else html.removeAttribute('data-theme');
    try { localStorage.setItem('scv-deck-theme', next); } catch(e){}
    var btn = document.getElementById('scvThemeBtn');
    if (btn) btn.textContent = scvThemeLabel();
  }
  document.addEventListener('DOMContentLoaded', function(){
    var btn = document.getElementById('scvThemeBtn');
    if (btn) btn.textContent = scvThemeLabel();
  });
</script>`;

  const HTML_LANG = { english: "en", korean: "ko", japanese: "ja" }[normalizeLang(opts.lang)] || "en";
  const title = esc(data.title || data.slug || t("untitledDeck"));
  return `<!doctype html>
<html lang="${HTML_LANG}">
<head>
${themeInit}
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<style>${CSS}</style>
</head>
<body>
<div class="shell">
<div class="scroll-main">
<div class="wrap">
<header class="doc"><h1>${title}</h1>${headerActions}</header>
${toc ? `<nav class="toc"><h3>${esc(t("toc"))}</h3><ol>${toc}</ol></nav>` : ""}
${deckNav}
${sections}
${lintSection}
${deckFooter}
${printSource}
</div>
</div>
${sourcePanel}
</div>
${mermaidScript}
${pageScript}
${themeScript}
</body>
</html>
`;
}
