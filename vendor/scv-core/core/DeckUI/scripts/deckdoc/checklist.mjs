// checklist.mjs — the composition-checklist lint (core/contracts/composition.md).
//
// A plan's `합성 설계 체크리스트` table answers, with evidence, how its pure steps are
// composed. Three pure steps, composed by the caller:
//
//   checklist_rows      mdast tree → rows [{ num, answer, evidence }] | null (no table)
//   checklist_problems  rows | null → problems [{ kind, nums }]
//   render_warnings     problems, t → lint entries [{ level, message }]
//
// Warn — never block, never fill in. A table is "missing" only when the plan carries no
// checklist heading or no table under it; old plans are warned once, nothing more.

const HEAD_KEYS = ["체크리스트", "checklist", "チェックリスト"];
const COMPOSE_KEYS = ["합성", "composition", "合成"];
const ANSWER_KEYS = ["답", "answer", "答"];
const EVIDENCE_KEYS = ["근거", "증거", "evidence", "根拠"];

const text = (n) =>
  !n ? "" : typeof n.value === "string" ? n.value : Array.isArray(n.children) ? n.children.map(text).join("") : "";

// A cell that was never filled: empty, only dashes / dots / question marks, the template's
// `<TODO …>` placeholder, or the bare word todo / tbd. A file NAMED todo (`todo/store.ts:12`)
// is evidence — only the whole-cell word is a placeholder.
const blank = (s) => {
  const v = String(s || "").trim();
  return v === "" || /^[-–—?.…]+$/.test(v) || /^<\s*todo\b/i.test(v) || /^\(?\s*(todo|tbd)\s*\)?$/i.test(v);
};

// Evidence that says nothing: blank, or a bare "none".
const no_evidence = (s) => blank(s) || /^(없음|n\/?a|none|なし)$/i.test(String(s || "").trim());

// The column whose header IS the key wins over one that merely contains it ("물음과 답" vs "답").
const col = (header, keys) => {
  const h = header.map((x) => x.toLowerCase());
  const exact = h.findIndex((x) => keys.includes(x));
  return exact >= 0 ? exact : h.findIndex((x) => keys.some((k) => x.includes(k)));
};

// A row is named by its number cell; an empty cell or a whole question there names it by position.
const row_name = (cell, at) => (cell && cell.length <= 12 ? cell : `#${at + 1}`);

// The table under ONE checklist heading — null when that heading carries none.
const table_under = (nodes, at) => {
  for (let i = at + 1; i < nodes.length; i++) {
    if (nodes[i].type === "heading") return null;
    if (nodes[i].type === "table") return nodes[i];
  }
  return null;
};

const rows_of = (table) => {
  const [head, ...body] = table.children.map((r) => r.children.map((c) => text(c).trim()));
  const a = col(head || [], ANSWER_KEYS);
  const e = col(head || [], EVIDENCE_KEYS);
  if (a < 0 || e < 0) return null;
  return body.map((cells, at) => ({ num: row_name(cells[0], at), answer: cells[a] || "", evidence: cells[e] || "" }));
};

const rows_under = (nodes, keys) => {
  for (let i = 0; i < nodes.length; i++) {
    const n = nodes[i];
    if (n.type !== "heading" || n.depth < 2) continue;
    const h = text(n).toLowerCase();
    if (!keys.every((group) => group.some((k) => h.includes(k)))) continue;
    const table = table_under(nodes, i);
    const rows = table ? rows_of(table) : null;
    if (rows) return rows;
  }
  return null;
};

// Every part of the plan folder is scanned, so another heading may carry the word (a tests
// checklist, say). A heading that names the COMPOSITION checklist wins; without one, the first
// checklist heading whose table has answer + evidence columns.
export function checklist_rows(tree) {
  const nodes = Array.isArray(tree && tree.children) ? tree.children : [];
  return rows_under(nodes, [HEAD_KEYS, COMPOSE_KEYS]) || rows_under(nodes, [HEAD_KEYS]);
}

// One pass over the rows — a row with no answer is not also asked for its evidence.
export function checklist_problems(rows) {
  // No table, or a table with no rows: nothing was answered.
  if (rows == null || rows.length === 0) return [{ kind: "missing", nums: [] }];
  const noAnswer = [];
  const noEvidence = [];
  for (const r of rows) {
    if (blank(r.answer)) noAnswer.push(r.num);
    else if (no_evidence(r.evidence)) noEvidence.push(r.num);
  }
  return [
    ...(noAnswer.length ? [{ kind: "noAnswer", nums: noAnswer }] : []),
    ...(noEvidence.length ? [{ kind: "noEvidence", nums: noEvidence }] : []),
  ];
}

const KEY = { missing: "lintNoChecklist", noAnswer: "lintChecklistNoAnswer", noEvidence: "lintChecklistNoEvidence" };

export function render_warnings(problems, t) {
  return problems.map((p) => ({ level: "warn", message: t(KEY[p.kind], p.nums.join(", ")) }));
}
