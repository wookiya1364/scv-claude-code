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
function renderOnce(extraArgs) {
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
        `--user-data-dir=${profile}`,
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
for (const attempt of [["--headless=new"], ["--headless=new", "--no-sandbox"], ["--headless", "--no-sandbox"]]) {
  dom = await renderOnce(attempt);
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
if (!/^\s*<!doctype/i.test(dom)) dom = "<!DOCTYPE html>\n" + dom;
if (!dom.endsWith("\n")) dom += "\n";

const count = (dom.match(/data-scv-static-mermaid="true"/g) || []).length;
writeFileSync(out, dom);
console.log(`STATIC_MERMAID: embedded diagrams=${count} → ${out}`);
