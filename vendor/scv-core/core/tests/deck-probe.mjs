#!/usr/bin/env node
// Read COMPUTED styles and real geometry out of a built deck, in a real browser.
//
// Why this exists: the deck's tests pin CSS as literal substrings. That is how a
// stylesheet full of `font:600 12px/1 inherit` — a shorthand the parser discards
// whole — passed 151 assertions while every control rendered in
// 13.333px/400/Arial. A string being present in a file says nothing about what
// the reader sees.
//
// How: the measuring code is injected into a COPY of the deck, it writes its
// findings into a <script type="application/json"> node, and the page is dumped
// with --dump-dom. No DevTools protocol driver, no dependency, and the original
// file is never touched.
//
// Usage:  node core/tests/deck-probe.mjs <deck.html> [--width=1440] [--json]
// Env:    SCV_CHROME — browser binary (the same variable static-mermaid.mjs uses)
// Exit:   0 measured or skipped · 2 bad invocation

import { spawnSync, execSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith("--"));
const width = Number((args.find((a) => a.startsWith("--width=")) || "--width=1440").split("=")[1]);
const asJson = args.includes("--json");

if (!file || !existsSync(file)) {
  console.error("deck-probe: need a built deck html");
  process.exit(2);
}

function findChrome() {
  if (process.env.SCV_CHROME && existsSync(process.env.SCV_CHROME)) return process.env.SCV_CHROME;
  for (const c of ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome"]) {
    try {
      return execSync("command -v " + c, { stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    } catch { /* keep looking */ }
  }
  // Most dev machines already carry a Playwright browser; reporting "no browser"
  // on a machine that plainly has one just turns the check into a silent skip.
  try {
    const hit = execSync(
      "ls -d \"$HOME\"/.cache/ms-playwright/chromium*/chrome-linux64/chrome 2>/dev/null | tail -1",
      { shell: "/bin/bash", stdio: ["ignore", "pipe", "ignore"] },
    ).toString().trim();
    if (hit && existsSync(hit)) return hit;
  } catch { /* fall through */ }
  return null;
}

const chrome = findChrome();
if (!chrome) {
  console.log("deck-probe: SKIP — no browser found (set SCV_CHROME)");
  process.exit(0);
}

const PROBE = String.raw`
<script id="scv-probe">
(function(){
  function px(v){ return Math.round(parseFloat(v)*100)/100; }
  function lin(c){ return c<=0.03928 ? c/12.92 : Math.pow((c+0.055)/1.055,2.4); }
  function parse(s){
    var m=String(s).match(/rgba?\(([^)]+)\)/); if(!m) return null;
    var p=m[1].split(",").map(parseFloat);
    return {r:p[0],g:p[1],b:p[2],a:p.length>3?p[3]:1};
  }
  function lum(c){ return 0.2126*lin(c.r/255)+0.7152*lin(c.g/255)+0.0722*lin(c.b/255); }
  function over(f,b){ return f.a>=1?f:{r:f.r*f.a+b.r*(1-f.a),g:f.g*f.a+b.g*(1-f.a),b:f.b*f.a+b.b*(1-f.a),a:1}; }
  function ratio(fs,bs){
    var f=parse(fs), b=parse(bs); if(!f||!b) return null;
    var lf=lum(over(f,b)), lb=lum(b), hi=Math.max(lf,lb), lo=Math.min(lf,lb);
    return Math.round(((hi+0.05)/(lo+0.05))*100)/100;
  }
  // The nearest ancestor that actually paints — contrast has to be measured
  // against the pixel behind the ink, not against a transparent parent.
  function ground(el){
    var n=el;
    while(n && n!==document.documentElement){
      var p=parse(getComputedStyle(n).backgroundColor);
      if(p && p.a>0.95) return getComputedStyle(n).backgroundColor;
      n=n.parentElement;
    }
    return getComputedStyle(document.documentElement).backgroundColor||"rgb(255, 255, 255)";
  }

  var out={width:innerWidth,controls:[],badFont:[],diagram:null,chrome:null,nav:null,undeclared:[],titleDupes:null};

  var docFamily=getComputedStyle(document.body).fontFamily.split(",")[0].replace(/["']/g,"");
  document.querySelectorAll("button,input,select,textarea").forEach(function(el){
    var cs=getComputedStyle(el);
    var fam=cs.fontFamily.split(",")[0].replace(/["']/g,"");
    var rec={sel:(el.className||el.tagName).toString().split(" ")[0],size:px(cs.fontSize),weight:cs.fontWeight,family:fam};
    out.controls.push(rec);
    // 13.333px/400 in a family the document never asked for is the UA default
    // leaking through — the exact fingerprint of a discarded declaration.
    if(rec.size===13.33||rec.size===13.333||(fam!==docFamily&&rec.weight==="400"&&rec.size>13&&rec.size<13.5)) out.badFont.push(rec);
  });

  // Chrome is measured on the FIRST page, before any paging below. Measuring it
  // after a scvGoto reads a scrolled position and reports 0px.
  var first=document.querySelector(".slide-page:not([hidden]) h2")||document.querySelector(".wrap h2")||document.querySelector(".wrap p");
  if(first) out.chrome={beforeContentPx:px(first.getBoundingClientRect().top)};
  var navEl=document.querySelector(".deck-nav")||document.querySelector("nav");
  if(navEl) out.nav={heightPx:px(navEl.getBoundingClientRect().height),flexWrap:getComputedStyle(navEl).flexWrap};

  // The deck is a pager: only one section is visible, and a diagram on page 11
  // measures 0px wide from page 1. Go to whichever page holds it first —
  // measuring a hidden element is how a scaled-down diagram stays invisible to
  // a test that thinks it is checking the diagram.
  var svg=document.querySelector("pre.mermaid svg, .mermaid svg, svg.flowchart");
  if(svg && typeof scvGoto==="function"){
    var page=svg.closest(".slide-page");
    if(page && page.dataset && page.dataset.idx){ try{ scvGoto(Number(page.dataset.idx)); }catch(e){} }
  }
  if(svg){
    var vb=(svg.getAttribute("viewBox")||"").split(/\s+/);
    var natural=vb.length===4?parseFloat(vb[2]):null;
    var r=svg.getBoundingClientRect();
    var label=svg.querySelector(".nodeLabel")||svg.querySelector(".label");
    var edge=svg.querySelector("path.flowchart-link")||svg.querySelector(".edgePath path")||svg.querySelector("path");
    var node=svg.querySelector("g.node rect")||svg.querySelector(".node rect")||svg.querySelector("rect");
    var scale=natural?Math.round((r.width/natural)*1000)/1000:null;
    var surface=ground(svg);
    var lf=label?px(getComputedStyle(label).fontSize):null;
    out.diagram={
      natural:natural, rendered:px(r.width), scale:scale,
      labelPx:lf, effectiveLabelPx:(lf&&scale)?Math.round(lf*scale*100)/100:null,
      surface:surface,
      edgeStroke:edge?getComputedStyle(edge).stroke:null,
      edgeContrast:edge?ratio(getComputedStyle(edge).stroke,surface):null,
      nodeFill:node?getComputedStyle(node).fill:null,
      nodeStroke:node?getComputedStyle(node).stroke:null,
      nodeStrokeContrast:node?ratio(getComputedStyle(node).stroke,surface):null,
      labelColor:label?getComputedStyle(label).color:null,
      labelContrast:(label&&node)?ratio(getComputedStyle(label).color,getComputedStyle(node).fill):null,
      inlineColourAttrs:svg.querySelectorAll('[style*="fill:"],[style*="stroke:"]').length,
      // A label whose text is wider than its box is clipped mid-word. Mermaid
      // sizes edge boxes for two wrapped lines, so this only fires when
      // something stopped the wrap — <pre>'s white-space:pre did, silently.
      clippedLabels:(function(){
        var n=0;
        svg.querySelectorAll("foreignObject p").forEach(function(el){
          if(el.scrollWidth>el.clientWidth+1) n++;
        });
        return n;
      })(),
      labelCount:svg.querySelectorAll("foreignObject p").length,
      idScopedRules:(function(){
        var s=svg.querySelector("style"); if(!s) return 0;
        return (s.textContent.match(/#mermaid-\d+/g)||[]).length;
      })()
    };
  }

  var declared={};
  // Walk nested rules too. A custom property declared inside @supports or @media
  // is still declared; a flat scan reported --bleed as undeclared and would have
  // trained the reader to ignore this line.
  function collect(rules){
    for(var j=0;j<rules.length;j++){
      var r=rules[j];
      if(r.style) for(var k=0;k<r.style.length;k++) if(r.style[k].indexOf("--")===0) declared[r.style[k]]=1;
      if(r.cssRules) collect(r.cssRules);
    }
  }
  for(var i=0;i<document.styleSheets.length;i++){
    try{ collect(document.styleSheets[i].cssRules); }catch(e){ continue; }
  }
  var css=Array.prototype.map.call(document.querySelectorAll("style"),function(s){return s.textContent;}).join("\n");
  var seen={}, m, re=/var\((--[a-z0-9-]+)/g;
  while((m=re.exec(css))) seen[m[1]]=1;
  var rootCs=getComputedStyle(document.documentElement);
  out.undeclared=Object.keys(seen).filter(function(u){ return !declared[u] && !rootCs.getPropertyValue(u).trim(); });

  var t=document.querySelector(".doc-title,header h1");
  if(t){
    var txt=t.textContent.trim();
    var page=document.querySelector(".slide-page:not([hidden])");
    out.titleDupes=page?(page.textContent.split(txt).length-1):null;
  }

  var box=document.createElement("script");
  box.type="application/json"; box.id="scv-probe-result";
  box.textContent=JSON.stringify(out);
  document.body.appendChild(box);
})();
</script>
`;

const html = readFileSync(file, "utf8");
const injected = html.includes("</body>")
  ? html.replace("</body>", PROBE + "</body>")
  : html + PROBE;

const dir = mkdtempSync(join(tmpdir(), "scv-deck-probe-"));
const copy = join(dir, "probe.html");
writeFileSync(copy, injected);

// No --user-data-dir. Measured on Chrome 149: passing one makes --dump-dom emit
// nothing at all (0 bytes, exit 0), which reads as "page did not render" and
// turns every check into a silent skip. static-mermaid.mjs does pass a profile,
// but it drives the browser differently and is not affected.
const res = spawnSync(chrome, [
  "--headless=new", "--disable-gpu", "--no-sandbox",
  "--window-size=" + width + ",900",
  "--virtual-time-budget=8000",
  "--dump-dom", "file://" + resolve(copy),
], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024, timeout: 90000 });

const dom = res.stdout || "";
rmSync(dir, { recursive: true, force: true });

const m = dom.match(/<script type="application\/json" id="scv-probe-result">([\s\S]*?)<\/script>/);
if (!m) {
  console.log("deck-probe: SKIP — the page did not run the probe");
  process.exit(0);
}
const out = JSON.parse(m[1]);

if (asJson) { console.log(JSON.stringify(out, null, 2)); process.exit(0); }

const f = (v) => (v === null || v === undefined ? "—" : v);
console.log("  viewport " + out.width + "px");
if (out.diagram) {
  const d = out.diagram;
  console.log("  diagram   natural " + f(d.natural) + "px → rendered " + f(d.rendered) + "px  (scale " + f(d.scale) + ")");
  console.log("            label " + f(d.labelPx) + "px → effective " + f(d.effectiveLabelPx) + "px");
  console.log("            edge " + f(d.edgeStroke) + "  contrast " + f(d.edgeContrast) + ":1");
  console.log("            node stroke contrast " + f(d.nodeStrokeContrast) + ":1  label/fill " + f(d.labelContrast) + ":1");
  console.log("            inline colour attrs " + f(d.inlineColourAttrs) + "  id-scoped rules " + f(d.idScopedRules));
  console.log("            labels " + f(d.labelCount) + ", clipped " + f(d.clippedLabels));
}
if (out.chrome) console.log("  chrome    before content " + f(out.chrome.beforeContentPx) + "px");
if (out.nav) console.log("  nav       height " + f(out.nav.heightPx) + "px  flex-wrap " + f(out.nav.flexWrap));
console.log("  controls  " + out.controls.length + " total, " + out.badFont.length + " in a UA fallback font");
for (const b of out.badFont.slice(0, 6)) console.log("            ✗ " + b.sel + " " + b.size + "px/" + b.weight + " " + b.family);
if (out.undeclared.length) console.log("  tokens    undeclared: " + out.undeclared.join(" "));
if (out.titleDupes !== null) console.log("  title     appears " + f(out.titleDupes) + "× on the active page");
