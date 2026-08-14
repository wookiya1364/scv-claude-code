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
// Claude Code authors the screen JSON (commands/promote.md Step 6.4), but a slip is still
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
// "우리 프로젝트엔 디자인 토큰이 있다"고 말한 경우에만(commands/promote.md Step 6.4의
// 사용자 확인으로 판단) Claude Code 가 screen JSON 에 `theme` 필드로 실제 hex 값만
// 넘긴다. 그 외 파생값(투명 배지 배경, 명암비 안전한 on-primary 텍스트)은 여기서 항상
// 계산한다 — Claude Code 가 매번 대비를 직접 판단하게 두면 v0.18.0 에서 실제로 터진 WCAG
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

// A screen block's optional `theme` (base hex colors only — exactly what the
// user's own token source documents) → an inline `style="--wf-*:..."` string that overrides
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
  // The title becomes browser chrome inside the frame rather than a caption above
  // it — the reference's ScreenFrame. The label already exists in the authored
  // JSON, so this is the one reference primitive that ports whole.
  const chrome = b.title
    ? `<div class="wf-chrome"><span class="wf-dot wf-dot-r"></span><span class="wf-dot wf-dot-y"></span><span class="wf-dot wf-dot-g"></span><span class="wf-url">${esc(b.title)}</span></div>`
    : "";
  return `<div class="wf-screen"${themeStyleOf(b.theme)}><div class="wf-frame">${chrome}${nav}<div class="wf-body">${body}</div></div></div>`;
}

const CSS = `
/* Dark only — the light token set and its toggle were removed:
   FE 프로젝트의 다크-기본+라이트-오버라이드 관례와 동일한 모양(속성 하나만 바뀌면
   전체가 재테마된다). head 맨 앞 인라인 스크립트가 pre-paint 로 저장된 선택을 적용해
   깜빡임(FOUC)이 없다. */
/* Dark only. Ported from the owner's DesignSystem .dark block (shadcn oklch ->
   sRGB, every neutral at chroma 0). The blue-cast greys this replaces
   (#171922 / #1d2029 / #2c3040 / #9096a8) were the single loudest reason the
   two decks read as different systems.

   Contrast figures are WCAG 2.x, measured against the surface named. */
:root{
  /* surfaces */
  --bg:#0a0a0a;                  /* the one ground */
  --panel:#171717;               /* cards, aside, code */
  --surface-2:#121212;           /* zebra rows, quiet fills */
  --surface-3:#151515;           /* table head, code block */

  /* text */
  --fg:#fafafa;                  /* 18.97:1 on --bg */
  --fg-body:#e2e2e2;             /* 15.28:1 on --bg  · body copy */
  --fg-soft:#d6d6d6;             /* 13.62:1 on --bg  · text inside a tinted card */
  --muted-foreground:#a1a1a1;    /*  7.66:1 on --bg  · 6.94:1 on --panel */

  /* lines — alpha so ONE value composites correctly over bg and panel alike */
  --border:rgba(255,255,255,.10);
  --border-strong:#707070;       /* load-bearing rules. Measured where it actually
                                    sits, not on --bg: 3.62:1 on --panel (node
                                    fill), 3.69:1 on --surface-3 (figure ground),
                                    5.87:1 on --bg. #4d4d4d cleared 3:1 against
                                    --bg alone and failed at 2.12:1 on a node. */
  --ring:#737373;                /*  4.18:1 on --bg */

  /* brand — the owner's rose, kept for a public product on their say-so.
     TWO values, because one cannot do both jobs: oklch(.455 .188 13.697)
     = #a50036 measures 2.50:1 as text on --bg and is unreadable. The text
     value is the same hue lifted in lightness only. */
  --primary:#a50036;             /* fill · white on it 7.58:1 */
  --primary-text:#fc7184;        /* text · 7.39:1 on --bg · 6.69:1 on --panel */
  --on-primary:#fafafa;          /* 7.58:1 on the --primary plate */

  /* status */
  --good:#4bd39a;                /*  9.53:1 on --bg */
  --warn:#e3b153;                /*  9.18:1 on --bg */
  --danger:#f4837f;              /*  7.22:1 on --bg */
  --on-warn:#241a06;             /*  8.72:1 on the --warn plate */
}
*{box-sizing:border-box}
html,body{height:100%}
html{scroll-behavior:smooth}
body{margin:0;font:16px/1.7 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Noto Sans KR",sans-serif;color:var(--fg);background:var(--bg)}
/* Controls do not inherit the document font — a UA default applies unless asked.
   Six controls below set font-size alone or an invalid \`font:\` shorthand, and
   all of them rendered in 13.333px/400/Arial. This one line is what makes the
   per-control rules that follow actually reach the element. */
button,input,select,textarea{font:inherit;color:inherit}
/* 문서 = 스크롤되는 본문(좌) + 상시 원문 마크다운 패널(우, sticky) — 이게 scv:deck 의
   정체성이다: 렌더링과 원문이 늘 같은 화면에 나란히 있어야 서로 어긋나지 않았다는 게
   보장된다. 인쇄 시에는 패널을 접고 본문 뒤에 원문을 부록으로 붙인다(.print-source). */
/* Three rows over the viewport: header, content, footer. The header and the
   footer are chrome and must not scroll away with the text — before this they
   lived inside .wrap and pushed 268px of nav in front of the first sentence. */
.shell{display:grid;grid-template-rows:auto 1fr auto;height:100svh;overflow:hidden}
.shell-mid{display:flex;min-height:0;overflow:hidden}
/* A container so a figure can measure the READING area and break out of the
   840px text column. 100vw would count the source panel too and push the
   diagram under it. */
.scroll-main{flex:1;min-width:0;overflow-y:auto;container-type:inline-size}
.wrap{--doc-pad:clamp(20px,5vw,56px);max-width:840px;margin:0 auto;min-height:100%;padding:0 var(--doc-pad) 96px}
header.doc{display:flex;align-items:center;gap:16px;min-width:0;background:var(--bg);border-bottom:1px solid var(--border);padding:11px 20px}
header.doc h1{font-size:15px;font-weight:600;margin:0;flex-shrink:0;max-width:34ch;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--fg)}
.header-actions{display:flex;align-items:center;gap:8px;flex-shrink:0}
.panel-toggle{flex-shrink:0;font-weight:600;font-size:12px;line-height:1;color:var(--muted-foreground);background:var(--panel);border:1px solid var(--border);border-radius:7px;padding:7px 11px;cursor:pointer}
.panel-toggle:hover{background:var(--border);color:var(--fg)}
.panel-toggle .kbd{opacity:.55;margin-left:4px}
.source-panel{position:relative;width:min(440px,38vw);flex-shrink:0;border-left:1px solid var(--border);background:var(--panel);display:flex;flex-direction:column}
.source-panel.closed{display:none}
.panel-resize-handle{position:absolute;left:0;top:0;bottom:0;width:7px;margin-left:-4px;cursor:col-resize;z-index:6}
.panel-resize-handle:hover{background:rgba(127,137,160,.25)}
.panel-head{display:flex;align-items:center;justify-content:space-between;padding:13px 16px;border-bottom:1px solid var(--border);flex-shrink:0}
.panel-title{font-size:12px;color:var(--muted-foreground);font-weight:700;letter-spacing:.02em}
.panel-close{border:none;background:none;color:var(--muted-foreground);cursor:pointer;font-size:14px;padding:2px 7px;border-radius:5px;line-height:1.4}
.panel-close:hover{background:var(--border);color:var(--fg)}
.panel-tabs{display:flex;gap:2px;padding:9px 12px 0;border-bottom:1px solid var(--border);flex-shrink:0;overflow-x:auto}
.panel-tab{font-weight:600;font-size:12px;line-height:1;color:var(--muted-foreground);padding:7px 10px;border:none;background:none;border-bottom:2px solid transparent;cursor:pointer;white-space:nowrap}
.panel-tab.active{color:var(--fg);border-bottom-color:var(--primary)}
.panel-body{flex:1;overflow-y:auto;padding:14px}
.panel-body .src-doc{display:none;margin:0}
.panel-body .src-doc.active{display:block}
.print-source{display:none}
/* 목차(nav.toc) 는 인쇄본 전용(펼친 전체 문서엔 목차가 자연스럽다). 화면에서는
   deck-nav(아래) 가 같은 역할을 대신한다 — 페이지 번호 pill + 클릭 이동. */
@media screen{nav.toc{display:none}}
nav.toc{background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:14px 18px;margin:26px 0}
nav.toc h3{margin:0 0 8px;font-size:12px;letter-spacing:.04em;color:var(--muted-foreground);text-transform:uppercase}
nav.toc ol{margin:0;padding-left:20px;columns:2;gap:24px}
nav.toc a{color:var(--fg);text-decoration:none}
nav.toc a:hover{color:var(--primary);text-decoration:underline}
section{padding:22px 0;border-top:1px solid var(--border)}
section:first-of-type{border-top:none}
/* 페이지 넘김(화면 전용) — 한 번에 한 섹션만. 인쇄 시엔 전부 펼쳐서 보여준다. */
@media screen{.slide-page{display:none}.slide-page.active{display:block}}
/* One scrolling row, never wrapped. The reference sets flex-wrap AND
   overflow-x-auto together; flex-wrap wins, and fed 19 labels its own header
   grows to three rows. nowrap is the one place this deliberately differs. */
.deck-nav{display:flex;flex-wrap:nowrap;gap:4px;margin:0;flex:1;min-width:0;overflow-x:auto;scrollbar-width:thin}
.deck-nav::-webkit-scrollbar{height:6px}
.deck-nav::-webkit-scrollbar-thumb{background:var(--border);border-radius:3px}
.deck-nav-item{font-weight:400;font-size:12px;line-height:16px;color:var(--muted-foreground);background:none;border:none;border-radius:4px;padding:4px 8px;cursor:pointer;white-space:nowrap}
.deck-nav-item:hover{color:var(--fg)}
.deck-nav-item.active{background:var(--primary-text);color:var(--bg);font-weight:500}
.deck-footer{display:flex;align-items:center;justify-content:space-between;gap:14px;margin:0;padding:11px 20px;border-top:1px solid var(--border);background:var(--bg)}
.deck-arrow{font-weight:600;font-size:13px;line-height:1;color:var(--fg);background:var(--bg);border:1px solid var(--border);border-radius:8px;padding:9px 16px;cursor:pointer}
.deck-arrow:disabled{opacity:.35;cursor:default}
.deck-arrow:not(:disabled):hover{background:var(--panel)}
.deck-dots{display:flex;align-items:center;gap:6px}
.deck-dot{width:8px;height:8px;border-radius:999px;background:var(--border);border:none;cursor:pointer;padding:0}
.deck-dot.active{background:var(--primary);width:20px;border-radius:5px}
.deck-counter{font-size:12px;color:var(--muted-foreground);min-width:52px;text-align:center}
mark.src-hl{background:color-mix(in srgb,var(--warn) 20%,transparent);color:var(--fg);border-left:2px solid var(--warn);border-radius:0;padding:0 2px}
h2{font-size:32px;line-height:1.15;letter-spacing:-.02em;margin:.1em 0 .5em;font-weight:700;color:var(--fg)}
h4{margin:1.1em 0 .35em;font-size:17px;font-weight:600;color:var(--fg)}
.subhead{font-size:20px;font-weight:600;margin:1.4em 0 .4em;color:var(--fg)}
.kicker{font-size:14px;font-weight:600;letter-spacing:.02em;color:var(--primary-text);margin-bottom:6px}
.sub{font-size:18px;line-height:1.55;color:var(--muted-foreground);margin:-.1em 0 1.3em;max-width:62ch}
p{margin:.65em 0;font-size:15px;line-height:1.625;color:var(--fg-body)}
ul{margin:.6em 0;padding-left:0;list-style:none}
ol{margin:.6em 0;padding-left:22px}
li{margin:0;font-size:15px;line-height:1.625;color:var(--fg-body)}
ul>li{position:relative;padding-left:18px;margin:8px 0}
ul>li::before{content:"";position:absolute;left:0;top:.62em;width:6px;height:6px;border-radius:50%;background:color-mix(in srgb,var(--primary-text) 70%,transparent)}
ol>li{margin:8px 0}
.tw{overflow-x:auto;margin:.8em 0}
table{border-collapse:collapse;width:100%;font-size:14px;border:1px solid var(--border);border-radius:10px;overflow:hidden}
th,td{border:none;border-bottom:1px solid var(--border);padding:10px 14px;text-align:left;vertical-align:top;color:var(--fg-body)}
tbody tr:last-child td{border-bottom:none}
thead th{background:var(--surface-3);font-weight:600;font-size:12px;letter-spacing:.02em;color:var(--muted-foreground)}
table.kv th{background:none;width:30%;white-space:nowrap;font-weight:500;color:var(--muted-foreground)}
.kpi{display:flex;flex-wrap:wrap;gap:12px;margin:.8em 0}
.kpi-card{flex:1 1 160px;border:1px solid var(--border);border-radius:10px;padding:12px 14px;background:var(--panel)}
.kpi-label{font-size:13px;color:var(--muted-foreground);margin-bottom:6px}
.kpi-nums{display:flex;align-items:center;gap:8px;font-weight:700}
.kpi-nums .base{color:var(--muted-foreground)}
.kpi-nums .arrow{color:var(--primary)}
.kpi-nums .target{color:var(--good)}
.goals{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:.8em 0}
.goal-col{border:1px solid var(--border);border-radius:10px;padding:10px 14px}
.goal-col.g{border-left:4px solid var(--good)}
.goal-col.ng{border-left:4px solid var(--danger)}
pre.code{background:var(--surface-3);color:var(--fg-body);border-radius:10px;padding:14px 16px;overflow-x:auto;font:13px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace;margin:.8em 0}
/* mermaid 는 항상 라이트 카드에 그린다(테마 무관, pre.code 가 항상 다크인 것과 대칭) —
   mermaid 렌더 테마를 다크로 다시 그리려면 이미 SVG 로 처리된 노드를 되돌려야 해서
   토글마다 재처리가 필요해진다. 대신 다이어그램 카드 자체를 고정 라이트로 둬서
   토글과 무관하게 항상 선명하게 읽힌다. */
/* A figure, not a paragraph. The SVG now carries its natural width, so the
   frame scrolls instead of shrinking it — a 1437px graph squeezed into an
   840px column rendered its 16px labels at 7.7px, which was the single worst
   readability defect in the deck. */
/* Full bleed: the figure uses the whole reading area, not the 840px measure the
   prose wants. A 1388px graph inside an 840px column left ~215px of dead gutter
   on each side AND a scrollbar — the worst of both. */
pre.mermaid{background:var(--surface-3);border:1px solid var(--border-strong);border-radius:10px;padding:14px;margin:1.1em 0;overflow-x:auto;text-align:left}
@supports (width:100cqw){
  pre.mermaid{
    /* A 16px gutter, not the prose gutter. Text wants a comfortable measure; a
       figure wants the glass. With the source panel open — which is the deck's
       whole point and stays open — every pixel of the reading area counts. */
    --bleed:calc(100cqw - 32px);
    width:var(--bleed);
    max-width:var(--bleed);
    margin-inline:calc((100% - var(--bleed)) / 2);
  }
}
/* Fit the frame when there is room; below 900px stop shrinking and scroll
   instead. Scaling all the way down is what made 16px labels render at 7.7px,
   and a scrollbar is better than text nobody can read. */
pre.mermaid svg{max-width:100%;min-width:900px;height:auto}
/* The diagram lives in a <pre>, whose UA default is white-space:pre, and that
   inherits into every label. Mermaid sizes an edge label's box for TWO wrapped
   lines (200x48.75) and the text then refused to wrap, so anything past 200px
   was clipped mid-word — "BASE_REF, HEAD_REF, PR_TITLE" measured 230px of text
   in a 200px box. Labels are prose, not preformatted text. */
pre.mermaid foreignObject,pre.mermaid foreignObject *{white-space:normal}
/* On a narrow window there is nothing to floor — let it fit rather than force
   a scrollbar the reader cannot escape. */
@media (max-width:900px){pre.mermaid svg{min-width:0}}
pre.mermaid.mermaid-fallback{text-align:left;white-space:pre;overflow-x:auto;background:#0f1320;color:#e6e9f0;font:13px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace;padding:30px 16px 14px;position:relative}
pre.mermaid.mermaid-fallback::before{content:"\\29c9 \\b2e4\\c774\\c5b4\\adf8\\b7a8 \\c6d0\\bcf8 (\\c624\\d504\\b77c\\c778 \\b610\\b294 CDN \\bbf8\\b85c\\b4dc)";position:absolute;top:8px;left:16px;font:600 11px/1 -apple-system,sans-serif;color:var(--muted-foreground)}
/* A tinted card, not a left rule — the reference's Callout. color-mix keeps one
   hue per tone instead of a second hand-picked hex for the fill. */
.callout{border:1px solid var(--border);border-radius:10px;padding:14px 16px;margin:1em 0;background:var(--panel)}
.callout-title{font-weight:600;font-size:16px;margin-bottom:4px;color:var(--fg)}
.callout p,.callout li{font-size:14px;color:var(--fg-soft)}
.callout.info{border-color:color-mix(in srgb,var(--primary-text) 30%,transparent);background:color-mix(in srgb,var(--primary-text) 10%,var(--bg))}
.callout.good{border-color:color-mix(in srgb,var(--good) 30%,transparent);background:color-mix(in srgb,var(--good) 10%,var(--bg))}
.callout.warn{border-color:color-mix(in srgb,var(--warn) 30%,transparent);background:color-mix(in srgb,var(--warn) 10%,var(--bg))}
.callout.danger{border-color:color-mix(in srgb,var(--danger) 30%,transparent);background:color-mix(in srgb,var(--danger) 10%,var(--bg))}
.callout.next{border-style:dashed;border-color:var(--border-strong);background:var(--surface-2)}
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
.wf-chrome{display:flex;align-items:center;gap:7px;padding:9px 12px;border-bottom:1px solid var(--wf-border);background:var(--wf-card)}
.wf-dot{width:12px;height:12px;border-radius:50%;flex-shrink:0;opacity:.7}
.wf-dot-r{background:#fb2c36}.wf-dot-y{background:#fe9a00}.wf-dot-g{background:#00bc7d}
.wf-url{margin-left:6px;padding:2px 8px;border-radius:5px;background:var(--wf-muted);color:var(--wf-muted-fg,var(--muted-foreground));font:12px/1.4 ui-monospace,SFMono-Regular,Menlo,monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.wf-frame{border:1px solid var(--wf-border);border-radius:calc(var(--wf-radius) + 4px);background:var(--wf-bg);color:var(--wf-fg);overflow:hidden}
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
.wf-btn{font-weight:500;font-size:12.5px;line-height:1;padding:8px 13px;border-radius:8px;border:1px solid transparent;background:var(--wf-muted);color:var(--wf-fg);cursor:default}
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
/* Paper is the one place the light values live. This is not a second theme the
   reader can choose — @media print is unreachable on screen, persists nothing,
   and shows no control. The screen deck stays dark only.
   It has to redeclare the TOKENS, not just body: the old block set
   background:#fff on body while every surface below it kept painting from
   --bg, so the PDF was 20 pages of dark slabs on a white sheet. */
@media print{
  :root{
    --bg:#ffffff; --panel:#f6f7f8; --surface-2:#fafafa; --surface-3:#f4f4f5;
    --fg:#111418;                /* 17.74:1 on white */
    --fg-body:#1c1f24;           /* 15.42:1 */
    --fg-soft:#33373d;           /* 10.87:1 */
    --muted-foreground:#565d6b;  /*  6.45:1 */
    --border:rgba(0,0,0,.14); --border-strong:#8a8f98; --ring:#8a8f98;
    --primary:#a50036;           /* the brand fill survives; white on it 7.58:1 */
    --primary-text:#8f0030;      /*  8.75:1 on white — the light form of the rose */
    --on-primary:#ffffff;
    --good:#0f7a4d;              /*  5.24:1 */
    --warn:#8a6100;              /*  5.40:1 */
    --danger:#b32d1f;            /*  6.18:1 */
    --on-warn:#fdf6e6;
    --wf-bg:#ffffff; --wf-fg:#111418; --wf-card:#f6f6f7;
    --wf-border:rgba(0,0,0,.16); --wf-muted:#f0f0f1; --wf-muted-fg:#565d6b;
  }
  @page{size:A4;margin:14mm 12mm}
  body{background:#fff;display:block;height:auto}
  .shell{display:block;height:auto;overflow:visible}
  .shell-mid{display:block;overflow:visible}
  .scroll-main{overflow:visible;height:auto}
  .wrap{box-shadow:none;max-width:none;padding:0}
  header.doc{position:static;border-bottom:1px solid var(--border);padding:0 0 8px}
  .panel-toggle,.source-panel,.deck-nav,.deck-footer{display:none}
  nav.toc{display:block;break-inside:avoid}
  /* break-inside:avoid on a 3000px section dumps most of a page. Keep headings
     with what follows and protect only the things that must not split. */
  h2,h3,h4,.subhead{break-after:avoid}
  figure,table,pre.code,.callout,.wf-screen{break-inside:avoid}
  /* Paper cannot scroll, so a wide graph gets its own landscape sheet. */
  @page dg{size:A4 landscape;margin:12mm}
  pre.mermaid{page:dg;overflow:visible;break-inside:avoid;max-height:180mm}
  pre.mermaid svg{max-width:100%;height:auto}
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
  const headerActions = `<div class="header-actions">${panelToggle}</div>`;
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
    document.querySelectorAll('.deck-nav-item').forEach(function(el){
      var on = el.dataset.idx === String(n);
      el.classList.toggle('active', on);
      // The nav is one scrolling row now, so the active pill can sit past the
      // right edge. Scroll the STRIP, not the page — scrollIntoView on the
      // element would also scroll .scroll-main and lose the reader's place.
      if (on && el.parentElement) {
        var strip = el.parentElement;
        var left = el.offsetLeft - (strip.clientWidth - el.offsetWidth) / 2;
        strip.scrollTo({ left: Math.max(0, left), behavior: 'smooth' });
      }
    });
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
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable)) return;
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
      : `<script type="module" id="scv-mermaid-loader">
  try {
    const { default: mermaid } = await import("https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs");
    // The page's own stack, verbatim. "inherit" is not a font NAME: mermaid could
    // not measure with it, fell back to a default width of 200px per label, and
    // every label longer than that was clipped inside its foreignObject.
    const SCV_FONT_STACK = '-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Noto Sans KR",sans-serif';
    mermaid.initialize({ startOnLoad: false, theme: "base", themeVariables: { fontFamily: SCV_FONT_STACK, fontSize: "16px" }, flowchart: { useMaxWidth: false, htmlLabels: true }, securityLevel: "strict" });
    // Scoped to the ACTIVE page only: mermaid measures text at run-time, so a diagram
    // processed while its .slide-page is display:none comes out zero/tiny-sized — and
    // because mermaid marks nodes data-processed="true" and skips them afterwards, that
    // broken render would stick even after the page becomes visible. Re-run this scoped
    // call every time scvGoto shows a NEW page, so each diagram is first measured exactly
    // when its page is on-screen; revisiting an already-correct page is a harmless no-op.
    window.scvRunMermaid = function () { mermaid.run({ querySelector: ".slide-page.active pre.mermaid" }); };
    if (new URLSearchParams(location.search).has("scv-static")) {
      // Static-build mode (?scv-static=1 — driven by static-mermaid.mjs, never by a
      // reader): reveal every page so each diagram measures at its real size, render
      // ALL of them, mark them, and signal completion. The build harness dumps the
      // resulting DOM, strips this loader, and ships offline-ready inline SVGs.
      const st = document.createElement("style");
      st.id = "scv-static-reveal";
      st.textContent = ".slide-page{display:block!important}";
      document.head.appendChild(st);
      await mermaid.run({ querySelector: "pre.mermaid" });
      for (const el of document.querySelectorAll("pre.mermaid")) el.setAttribute("data-scv-static-mermaid", "true");
      document.documentElement.setAttribute("data-scv-mermaid-static-done", "1");
    } else {
      await window.scvRunMermaid();
    }
    // Printing bypasses the pager (every .slide-page is visible under @media print), so
    // catch any diagram never visited on screen right before the print dialog opens.
    window.addEventListener("beforeprint", function () { mermaid.run({ querySelector: "pre.mermaid" }); });
  } catch (e) {
    for (const el of document.querySelectorAll("pre.mermaid")) el.classList.add("mermaid-fallback");
  }
</script>`;


  const HTML_LANG = { english: "en", korean: "ko", japanese: "ja" }[normalizeLang(opts.lang)] || "en";
  const title = esc(data.title || data.slug || t("untitledDeck"));
  return `<!doctype html>
<html lang="${HTML_LANG}">
<head>

<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<style>${CSS}</style>
<style id="scv-mermaid-contrast">
/* Diagram palette. static-mermaid.mjs strips the id-scoped rules, the
   !important flags and the inline colour attributes first, so plain specificity
   is enough here — before that, an author rule at (1,3,1) with !important still
   lost to style="fill:#FFE082 !important" on a classDef node. */
pre.mermaid .flowchart-link,pre.mermaid .edgePath .path,pre.mermaid path.flowchart-link{stroke:var(--fg-body);stroke-width:1.6px;fill:none}
pre.mermaid .marker,pre.mermaid marker path,pre.mermaid .arrowMarkerPath{fill:var(--fg-body);stroke:var(--fg-body)}
pre.mermaid .node rect,pre.mermaid .node circle,pre.mermaid .node polygon,pre.mermaid .node path{fill:var(--panel);stroke:var(--border-strong);stroke-width:1.2px}
pre.mermaid .nodeLabel,pre.mermaid .nodeLabel p,pre.mermaid .label,pre.mermaid text{fill:var(--fg);color:var(--fg)}
pre.mermaid .edgeLabel,pre.mermaid .edgeLabel p{background-color:var(--surface-3);color:var(--fg-body)}
pre.mermaid .edgeLabel rect,pre.mermaid .labelBkg{fill:var(--surface-3);opacity:1}
pre.mermaid .cluster rect{fill:var(--surface-2);stroke:var(--border-strong)}
pre.mermaid .cluster text,pre.mermaid .cluster .nodeLabel{fill:var(--muted-foreground);color:var(--muted-foreground)}
/* The two semantic highlights the protocol sanctions. Any other per-node colour
   is stripped, so these are the only ones that survive — deck.md says so. */
pre.mermaid .node.new rect,pre.mermaid g.new rect{fill:#5a4415;stroke:var(--warn);stroke-width:1.8px}
pre.mermaid .node.new .nodeLabel,pre.mermaid g.new .nodeLabel{fill:#f6e8c8;color:#f6e8c8}
pre.mermaid .node.changed rect,pre.mermaid g.changed rect{fill:#16324f;stroke:#6fb4f2;stroke-width:1.8px}
pre.mermaid .node.changed .nodeLabel,pre.mermaid g.changed .nodeLabel{fill:#d9ecff;color:#d9ecff}
</style>
</head>
<body>
<div class="shell">
<header class="doc"><h1>${title}</h1>${deckNav}${headerActions}</header>
<div class="shell-mid">
<div class="scroll-main">
<div class="wrap">
${toc ? `<nav class="toc"><h3>${esc(t("toc"))}</h3><ol>${toc}</ol></nav>` : ""}
${sections}
${lintSection}
${printSource}
</div>
</div>
${sourcePanel}
</div>
${deckFooter}
</div>
${mermaidScript}
${pageScript}

</body>
</html>
`;
}
