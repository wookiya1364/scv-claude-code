// static-mermaid.mjs — post-build step: bake deck mermaid diagrams into the HTML
// as inline SVG so the 기획서 opens fully rendered OFFLINE (no CDN at view time).
//
// How: serve the built deck HTML on a loopback http server (file:// blocks ESM
// imports), load it in a locally installed headless Chrome/Chromium with
// ?scv-static=1 (render.mjs's loader then reveals every page, renders ALL
// diagrams, and marks completion), dump the resulting DOM, strip the loader and
// the reveal style, and write the result back. The raw mermaid source still
// travels in the deck's source panel, untouched.
//
// Zero new dependencies: node stdlib + whatever Chrome the machine already has.
// Best-effort by design — no Chrome, no network to the mermaid CDN, or a render
// failure exits 3 WITHOUT touching the input, and the deck keeps today's
// CDN-at-view + text-fallback behavior. deck.sh treats that as a skip, not an
// error.
//
// Usage: node static-mermaid.mjs <deck.html> [--out <path>]   (default: in place)
// Env:   SCV_CHROME — explicit browser binary (checked first)
// Exit:  0 embedded · 1 usage/IO error · 3 skipped (reason on stderr)

import { readFileSync, writeFileSync, existsSync, mkdtempSync, rmSync } from "node:fs";
import { createServer } from "node:http";
import { spawn, spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";

const args = process.argv.slice(2);
let input = "";
let out = "";
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--out") out = args[++i] || "";
  else if (args[i].startsWith("--out=")) out = args[i].slice(6);
  else if (!input) input = args[i];
}
if (!input) {
  console.error("usage: static-mermaid.mjs <deck.html> [--out <path>]");
  process.exit(1);
}
if (!existsSync(input)) {
  console.error(`static-mermaid: input not found: ${input}`);
  process.exit(1);
}
out = out || input;

const html = readFileSync(input, "utf8");
if (!html.includes('id="scv-mermaid-loader"')) {
  console.error("static-mermaid: no mermaid loader in this deck (no diagrams or --mermaid none) — skipping");
  process.exit(3);
}

// ---- find a headless-capable browser ----
const which = (cmd) => {
  const r = spawnSync("which", [cmd], { encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : null;
};
function findChrome() {
  if (process.env.SCV_CHROME && existsSync(process.env.SCV_CHROME)) return process.env.SCV_CHROME;
  for (const c of ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome"]) {
    const p = which(c);
    if (p) return p;
  }
  for (const p of [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
  ]) {
    if (existsSync(p)) return p;
  }
  return null;
}
const chrome = findChrome();
if (!chrome) {
  console.error("static-mermaid: no Chrome/Chromium found (set SCV_CHROME to override) — skipping");
  process.exit(3);
}

// ---- serve the deck on loopback, render headless, dump the DOM ----
const server = createServer((req, res) => {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.end(html);
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;
const url = `http://127.0.0.1:${port}/deck.html?scv-static=1`;

const looksRendered = (dom) =>
  typeof dom === "string" &&
  dom.includes('data-scv-mermaid-static-done="1"') &&
  dom.includes("<svg") &&
  !dom.includes("mermaid mermaid-fallback");

// MUST be async (spawn, not spawnSync): the page is served by THIS process's
// http server, so a blocked event loop would deadlock Chrome's page load until
// its timeout — the classic self-serve pitfall.
function renderOnce(extraArgs, useProfile = false) {
  const profile = mkdtempSync(join(tmpdir(), "scv-deck-chrome-"));
  return new Promise((resolve) => {
    const child = spawn(
      chrome,
      [
        ...extraArgs,
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-first-run",
        "--disable-extensions",
        // A --user-data-dir makes --dump-dom emit nothing at all on Chrome 149
        // (0 bytes, exit 0), so every attempt in the ladder below failed and the
        // deck silently shipped the CDN loader instead of a baked SVG.
        // --incognito gives the same clean-state isolation the profile was there
        // for. The profile form stays reachable for hosts without incognito.
        ...(useProfile ? [`--user-data-dir=${profile}`] : ["--incognito"]),
        "--virtual-time-budget=30000",
        "--dump-dom",
        url,
      ],
      { stdio: ["ignore", "pipe", "ignore"] },
    );
    let dom = "";
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      rmSync(profile, { recursive: true, force: true });
      resolve(dom);
    };
    const killer = setTimeout(() => {
      child.kill("SIGKILL");
    }, 90000);
    child.stdout.on("data", (chunk) => {
      dom += chunk;
    });
    child.on("close", () => {
      clearTimeout(killer);
      finish();
    });
    child.on("error", () => {
      clearTimeout(killer);
      finish();
    });
  });
}

let dom = "";
// New headless first; some sandboxed/CI environments need --no-sandbox; very old
// Chrome only knows the legacy --headless flag.
// Two independent things silence --dump-dom on this browser: a --user-data-dir,
// and the absence of --no-sandbox. The old ladder varied only the second, so on
// a machine that needs both it never produced a single byte and the skip looked
// like "offline? CDN blocked?" rather than a browser-flag problem.
for (const attempt of [
  ["--headless=new", "--no-sandbox"],
  ["--headless=new"],
  ["--headless", "--no-sandbox"],
]) {
  dom = await renderOnce(attempt);
  if (dom && dom.includes("</html>")) break;
  dom = await renderOnce(attempt, true);
  if (looksRendered(dom)) break;
}
server.close();

if (!looksRendered(dom)) {
  console.error(
    "static-mermaid: headless render did not complete (offline? CDN blocked? diagram error?) — keeping the CDN version",
  );
  process.exit(3);
}

// ---- strip build-only artifacts from the dumped DOM ----
dom = dom
  .replace(/<script type="module" id="scv-mermaid-loader">[\s\S]*?<\/script>/, "")
  .replace(/<style id="scv-static-reveal">[\s\S]*?<\/style>/, "")
  .replace(/ data-scv-mermaid-static-done="1"/, "");
// ---- make the frozen SVG restylable ------------------------------------
// Mermaid bakes its palette three ways, and each defeats ordinary CSS:
//   - an internal <style> scoped to #mermaid-<timestamp>, specificity (1,1,0)
//   - !important on many of those rules
//   - inline style="fill:… !important" on classDef nodes, which nothing beats
// Strip all three so the page's own tokens can paint the diagram. Without this
// the palette an author pasted into the fence is frozen for the life of the
// file, and the deck cannot theme what it renders.
//
// Fails OPEN: a markup change in a future mermaid degrades to today's baked
// colours rather than failing the build.
function normalizeMermaidSvg(input) {
  // One document holds several diagrams, and every one of them carries a whole
  // family of ids: the svg itself, arrowhead markers, drop-shadow filters, the
  // gradient. Give two diagrams the same id and every url(#…) in the document
  // resolves to whichever element the parser met first — so diagram three drew
  // diagram one's arrowheads. Uniqueness is not cosmetic here.
  const usedIds = new Map();
  try {
    return input.replace(/<svg\b[^>]*\bid="mermaid-\d+"[\s\S]*?<\/svg>/g, (svg) => {
      let s = svg;
      const idm = s.match(/id="(mermaid-\d+)"/);
      if (!idm) return svg;
      const id = idm[1];

      // ID-scoped -> class-scoped, so author rules at (0,1,0) can win.
      s = s.split("#" + id).join(".scv-mmd");
      s = s.replace(/\s*!important/g, "");

      // The inline attribute is the only carrier no stylesheet can out-rank.
      s = s.replace(/style="([^"]*)"/g, (m, decls) => {
        const kept = decls
          .split(";")
          .filter((d) => d.trim() && !/^\s*(fill|stroke|color|background(-color)?)\s*:/i.test(d));
        return kept.length ? 'style="' + kept.join(";") + '"' : "";
      });

      // A build-timestamp id makes every rebuild a different file; this artifact
      // is committed on every promote. So the id must be stable — but a single
      // fixed value bought that stability by making every diagram identical,
      // which is the collision described above.
      //
      // Deriving it from the drawing itself satisfies both: the same picture
      // always yields the same id, a different picture a different one, and the
      // value does not depend on where the diagram sits in the document — insert
      // one at the top and the others' bytes do not move. The hash is taken with
      // the old id neutralised so it describes the picture, not the render order.
      const canonical = s.split(id).join("@SCV_MMD_ID@");
      const digest = createHash("sha256").update(canonical).digest("hex").slice(0, 10);
      // Two byte-identical diagrams in one document would land on the same
      // digest, which is the very thing being fixed — number the repeats.
      const seen = (usedIds.get(digest) || 0) + 1;
      usedIds.set(digest, seen);
      s = s.split(id).join(seen === 1 ? "scv-mmd-" + digest : "scv-mmd-" + digest + "-" + seen);
      s = s.replace(/<svg\b/, '<svg class="scv-mmd"');

      // Natural size, not 100% of a 694px column. The viewBox is the only place
      // the real dimensions survive; width="100%" plus max-width scaled a
      // 1437px graph to 0.483 and rendered 16px labels at 7.7px.
      const vb = s.match(/viewBox="([^"]+)"/);
      if (vb) {
        const p = vb[1].trim().split(/\s+/).map(Number);
        if (p.length === 4 && p[2] > 0 && p[3] > 0) {
          s = s.replace(/\swidth="[^"]*"/, "").replace(/\sheight="[^"]*"/, "");
          s = s.replace(/style="[^"]*max-width:[^"]*"/g, "");
          s = s.replace(/<svg\b/, '<svg width="' + p[2] + '" height="' + p[3] + '"');
        }
      }
      return s;
    });
  } catch (err) {
    console.error("static-mermaid: normalization skipped (" + err.message + ")");
    return input;
  }
}
dom = normalizeMermaidSvg(dom);

if (!/^\s*<!doctype/i.test(dom)) dom = "<!DOCTYPE html>\n" + dom;
if (!dom.endsWith("\n")) dom += "\n";

const count = (dom.match(/data-scv-static-mermaid="true"/g) || []).length;
writeFileSync(out, dom);
console.log(`STATIC_MERMAID: embedded diagrams=${count} → ${out}`);
