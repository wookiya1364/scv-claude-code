// change-map.mjs — 변경 지도의 순수부 (v0.52.0+).
//
// 왜 있나: 계획서는 이미 "순수함수 · 파이프라인" 절을 의무로 쓴다. 거기에 단계마다 상태
// (추가 · 변경 · 삭제 · 재사용)를 적으면, 읽는 사람이 "이번에 무엇이 새로 생기는가" 를
// 문장이 아니라 그림으로 본다. 이 파일은 그 글을 읽어 그림과 표로 바꾸는 부분만 담는다.
//
// 순수성 계약: 여기의 함수는 문자열·객체만 받아 문자열·객체만 낸다. 파일 읽기, Graft 실행,
// 시각, 난수를 만지지 않는다. 그 셋은 doc.mjs (효과부) 가 한다.
//
// 상태는 다섯 가지다. 넷은 계획서가 적고, 하나는 안 적었을 때 붙는다:
//   added · changed · removed · reused · unspecified

/** 상태 낱말 → 표준 키. 한국어·영어·일본어를 받는다. 모르는 말은 null. */
const STATUS_WORDS = new Map([
  ["추가", "added"], ["신규", "added"], ["added", "added"], ["new", "added"], ["追加", "added"],
  ["변경", "changed"], ["수정", "changed"], ["changed", "changed"], ["modified", "changed"], ["変更", "changed"],
  ["삭제", "removed"], ["제거", "removed"], ["removed", "removed"], ["deleted", "removed"], ["削除", "removed"],
  ["재사용", "reused"], ["기존", "reused"], ["reused", "reused"], ["existing", "reused"], ["再利用", "reused"],
]);

const STATUS_ORDER = ["added", "changed", "removed", "reused", "unspecified"];

// @pure
/** <낱말> → 표준 상태 키 | null. 괄호·공백·대소문자를 무시한다. */
export function normalizeStatus(word) {
  const w = String(word ?? "").replace(/[()（）\s`*]/g, "").toLowerCase();
  if (!w) return null;
  for (const [k, v] of STATUS_WORDS) if (w === k.toLowerCase()) return v;
  for (const [k, v] of STATUS_WORDS) if (w.includes(k.toLowerCase())) return v;
  return null;
}

// @pure
/** <마크다운 표 한 줄> → 칸 배열. 앞뒤 파이프를 버리고, 이스케이프된 파이프는 살린다. */
export function splitRow(line) {
  const out = [];
  let cur = "";
  const s = String(line ?? "").trim().replace(/^\|/, "").replace(/\|$/, "");
  for (let i = 0; i < s.length; i++) {
    if (s[i] === "\\" && s[i + 1] === "|") { cur += "|"; i++; continue; }
    if (s[i] === "|") { out.push(cur.trim()); cur = ""; continue; }
    cur += s[i];
  }
  out.push(cur.trim());
  return out;
}

const isDivider = (cells) => cells.length > 0 && cells.every((c) => /^:?-{2,}:?$/.test(c));
const unwrap = (s) => String(s ?? "").replace(/^[`*_\s]+|[`*_\s]+$/g, "");

// @pure
/**
 * <계획서 본문> → 선언된 단계 목록.
 * `## 순수함수 · 파이프라인` 절(또는 다른 언어의 같은 절) 안의 첫 표를 읽는다.
 * 상태 칸이 없는 옛 서식도 읽히며, 그 경우 상태는 "unspecified" 가 된다.
 * 절이 없거나 표가 없으면 빈 배열 — 오류를 내지 않는다.
 */
export function parsePipelineSection(markdown) {
  const lines = String(markdown ?? "").split(/\r?\n/);
  const HEAD = /^#{2,}\s+.*(순수함수|파이프라인|pure function|pipeline|純粋関数|パイプライン)/i;
  let i = lines.findIndex((l) => HEAD.test(l));
  if (i < 0) return [];
  const depth = (lines[i].match(/^#+/) || ["##"])[0].length;
  i++;

  // 절의 끝 = 같은 깊이 이하의 다음 제목.
  const end = (() => {
    for (let j = i; j < lines.length; j++) {
      const m = lines[j].match(/^(#+)\s/);
      if (m && m[1].length <= depth) return j;
    }
    return lines.length;
  })();

  // 절 안의 첫 표를 찾는다. 표 = 파이프로 시작하는 줄이 둘 이상 이어지고, 둘째 줄이 구분선.
  let header = null, rows = [], inTable = false;
  for (let j = i; j < end; j++) {
    const line = lines[j].trim();
    const looksRow = line.startsWith("|") && line.includes("|", 1);
    if (!looksRow) { if (inTable) break; continue; }
    const cells = splitRow(line);
    if (!inTable) {
      const next = (lines[j + 1] || "").trim();
      if (!next.startsWith("|") || !isDivider(splitRow(next))) continue;
      header = cells; inTable = true; j++; continue;
    }
    if (isDivider(cells)) continue;
    rows.push(cells);
  }
  if (!header) return [];

  const col = (...keys) => header.findIndex((h) => {
    const t = unwrap(h).toLowerCase();
    return keys.some((k) => t.includes(k));
  });
  const iName = col("단계", "step", "ステップ", "함수", "function");
  const iIo = col("→", "->", "받는", "input", "입출력");
  const iPurity = col("순수", "pure", "부수", "純粋");
  const iStatus = col("상태", "status", "状態");

  const steps = [];
  for (const cells of rows) {
    const name = unwrap(cells[iName >= 0 ? iName : 1]);
    if (!name) continue;                       // 이름 없는 행은 버린다 — 번호 없는 그림 조각을 만들지 않는다
    steps.push({
      name,
      io: iIo >= 0 ? unwrap(cells[iIo]) : "",
      purity: iPurity >= 0 ? unwrap(cells[iPurity]) : "",
      status: (iStatus >= 0 ? normalizeStatus(cells[iStatus]) : null) ?? "unspecified",
    });
  }
  return steps;
}

// @pure
/**
 * <화면설계 본문> → 번호-단계 연결 목록.
 * ```screen 블록 안의 functions[] / actions[] 에서 marker 와 step 을 꺼낸다.
 * 깨진 JSON 블록은 조용히 건너뛴다 — 문서 생성을 막지 않는다.
 */
export function parseScreenSteps(markdown) {
  const out = [];
  const re = /```screen\s*\n([\s\S]*?)\n```/g;
  let m;
  while ((m = re.exec(String(markdown ?? ""))) !== null) {
    let spec;
    try { spec = JSON.parse(m[1]); } catch { continue; }
    if (!spec || typeof spec !== "object") continue;
    for (const key of ["functions", "actions"]) {
      const arr = Array.isArray(spec[key]) ? spec[key] : [];
      for (const it of arr) {
        if (!it || typeof it !== "object") continue;
        const step = String(it.step ?? "").trim();
        if (!step) continue;
        out.push({
          marker: String(it.marker ?? "").trim(),
          step,
          title: String(it.title ?? "").trim(),
          screen: String(spec.title ?? "").trim(),
        });
      }
    }
  }
  return out;
}

// @pure
/**
 * <선언된 단계 목록> + <코드 근거> → 대조된 단계 목록.
 * 근거는 { known: Set|Array<이름>, callers: {이름: [곳]} } 모양이며, 비어 있어도 된다.
 * 대조 결과(verdict)는 셋뿐이다:
 *   "no-evidence"  근거가 없다 (Graft 가 없거나 그 이름을 못 봤다)
 *   "match"        선언과 코드가 어긋나지 않는다
 *   "already"      추가라고 했는데 코드에 이미 있다
 * 선언(status)은 어떤 경우에도 바뀌지 않는다.
 */
export function reconcileWithEvidence(steps, evidence) {
  const ev = evidence || {};
  const known = ev.known instanceof Set ? ev.known : new Set(Array.isArray(ev.known) ? ev.known : []);
  const callers = ev.callers && typeof ev.callers === "object" ? ev.callers : {};
  const hasEvidence = known.size > 0;
  return (Array.isArray(steps) ? steps : []).map((s) => {
    let verdict = "no-evidence";
    if (hasEvidence) {
      const seen = known.has(s.name);
      if (s.status === "added") verdict = seen ? "already" : "match";
      else if (s.status === "changed" || s.status === "removed" || s.status === "reused")
        verdict = seen ? "match" : "no-evidence";
      else verdict = seen ? "match" : "no-evidence";
    }
    return { ...s, verdict, callers: Array.isArray(callers[s.name]) ? callers[s.name] : [] };
  });
}

const MERMAID_INIT =
  "%%{init: {'theme':'base', 'themeVariables': {'primaryColor':'#1e1e1e','primaryTextColor':'#fff'," +
  "'primaryBorderColor':'#9096a8','lineColor':'#e7e9f0','secondaryColor':'#2d2d2d'," +
  "'tertiaryColor':'#1e1e1e','background':'#171922','edgeLabelBackground':'#171922'}}}%%";

const nodeId = (i) => `S${i + 1}`;
const esc = (s) => String(s ?? "").replace(/"/g, "'").replace(/[\[\]{}]/g, " ").trim();

// @pure
/**
 * <대조된 단계 목록> + <옵션> → 머메이드 글.
 * 상태를 색으로 나누고, 삭제 단계로 가는 선은 점선으로 둔다.
 * 단계가 `maxNodes`(기본 14)를 넘으면 앞에서부터 자르고 남은 수를 한 노드로 알린다.
 * 단계가 없으면 빈 문자열 — 빈 그림을 만들지 않는다.
 */
export function buildPipelineDiagram(steps, opts = {}) {
  const list = Array.isArray(steps) ? steps.filter((s) => s && s.name) : [];
  if (!list.length) return "";
  const max = Number.isInteger(opts.maxNodes) && opts.maxNodes > 0 ? opts.maxNodes : 14;
  const shown = list.slice(0, max);
  const hidden = list.length - shown.length;

  const lines = [MERMAID_INIT, "flowchart LR"];
  shown.forEach((s, i) => {
    const io = s.io ? `<br/><small>${esc(s.io)}</small>` : "";
    lines.push(`  ${nodeId(i)}["${esc(s.name)}${io}"]`);
  });
  for (let i = 0; i < shown.length - 1; i++) {
    // 삭제로 들어가거나 삭제에서 나가는 선은 점선 — 사라질 길이라는 뜻.
    const dashed = shown[i].status === "removed" || shown[i + 1].status === "removed";
    lines.push(`  ${nodeId(i)} ${dashed ? "-.->" : "-->"} ${nodeId(i + 1)}`);
  }
  if (hidden > 0) {
    lines.push(`  MORE["+${hidden}"]`);
    lines.push(`  ${nodeId(shown.length - 1)} -.-> MORE`);
  }
  lines.push("  classDef added fill:#FFE082,stroke:#F57C00,stroke-width:2px,color:#000");
  lines.push("  classDef changed fill:#90CAF9,stroke:#1565C0,stroke-width:2px,color:#000");
  lines.push("  classDef removed fill:#2d2d2d,stroke:#EF9A9A,stroke-width:2px,stroke-dasharray:4 3,color:#EF9A9A");
  for (const st of ["added", "changed", "removed"]) {
    const ids = shown.map((s, i) => (s.status === st ? nodeId(i) : null)).filter(Boolean);
    if (ids.length) lines.push(`  class ${ids.join(",")} ${st}`);
  }
  return lines.join("\n");
}

// @pure
/**
 * <대조된 단계 목록> + <번호-단계 연결> + <낱말표> → 표 행 목록.
 * 상태별로 묶어 정렬하고, 그 상태의 단계가 하나도 없으면 그 상태의 행을 만들지 않는다.
 * 특히 삭제가 적혀 있지 않으면 삭제 행은 0개다 — 문구를 지어내지 않는다.
 */
export function buildChangeTable(steps, screenSteps = [], words = {}) {
  const list = Array.isArray(steps) ? steps.filter((s) => s && s.name) : [];
  const byStep = new Map();
  for (const l of Array.isArray(screenSteps) ? screenSteps : []) {
    if (!l || !l.step) continue;
    if (!byStep.has(l.step)) byStep.set(l.step, []);
    byStep.get(l.step).push(l.marker ? `${l.marker}. ${l.title || l.step}` : l.title || l.step);
  }
  const w = (k, fallback) => String(words[k] ?? fallback);
  const statusWord = {
    added: w("added", "추가"), changed: w("changed", "변경"), removed: w("removed", "삭제"),
    reused: w("reused", "재사용"), unspecified: w("unspecified", "미지정"),
  };
  const verdictWord = {
    match: w("match", "일치"), already: w("already", "이미 있음"), "no-evidence": w("noEvidence", "근거없음"),
  };
  const rows = [];
  for (const st of STATUS_ORDER) {
    for (const s of list) {
      if (s.status !== st) continue;
      rows.push({
        status: st,
        statusLabel: statusWord[st],
        name: s.name,
        io: s.io || "",
        verdict: s.verdict || "no-evidence",
        verdictLabel: verdictWord[s.verdict] || verdictWord["no-evidence"],
        screens: byStep.get(s.name) || [],
      });
    }
  }
  return rows;
}

// @pure
/** <대조된 단계 목록> → { 상태: 개수 }. 0인 상태는 넣지 않는다. */
export function countByStatus(steps) {
  const out = {};
  for (const s of Array.isArray(steps) ? steps : []) {
    if (!s || !s.name) continue;
    out[s.status] = (out[s.status] || 0) + 1;
  }
  return out;
}

// @pure
/**
 * <그림 글> + <표 행 목록> + <낱말표> → 문서에 끼워 넣을 마크다운.
 * 단계가 하나도 없으면 빈 문자열 — 빈 표를 내보내지 않는다.
 */
export function renderChangeMapMarkdown(diagram, rows, words = {}) {
  const list = Array.isArray(rows) ? rows : [];
  if (!list.length) return "";
  const w = (k, fallback) => String(words[k] ?? fallback);
  const out = [`## ${w("title", "변경 지도")}`, ""];
  if (diagram) out.push("```mermaid", diagram, "```", "");
  out.push(`| ${w("colStatus", "상태")} | ${w("colStep", "단계")} | ${w("colIo", "받는 값 → 돌려주는 값")} | ${w("colVerdict", "코드 대조")} | ${w("colScreen", "화면")} |`);
  out.push("|---|---|---|---|---|");
  for (const r of list) {
    const cell = (v) => String(v ?? "").replace(/\|/g, "\\|") || "—";
    out.push(`| ${cell(r.statusLabel)} | \`${cell(r.name)}\` | ${cell(r.io)} | ${cell(r.verdictLabel)} | ${cell(r.screens.join(", "))} |`);
  }
  out.push("");
  return out.join("\n");
}

export { STATUS_ORDER };
