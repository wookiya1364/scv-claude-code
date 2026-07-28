import { useEffect, useRef, useState } from "react";
import mermaid from "mermaid";
import { cn } from "@/lib/utils";

// DeckUI primitives beyond the base set: Mermaid diagram, a real N-column
// DataTable (with priority-badge cells), KPI tiles, and a Goals/Non-goals split.
// Kept separate from primitives.tsx so the mermaid dependency stays isolated.

mermaid.initialize({
  startOnLoad: false,
  theme: "dark",
  securityLevel: "loose",
  fontFamily: "inherit",
});
let _mid = 0;

export const Mermaid = ({ code }: { code: string }) => {
  const ref = useRef<HTMLDivElement>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    const id = `mmd-${++_mid}`;
    mermaid
      .render(id, code)
      .then(({ svg }) => {
        if (alive && ref.current) ref.current.innerHTML = svg;
      })
      .catch((e) => {
        if (alive) setErr(String(e?.message ?? e));
      });
    return () => {
      alive = false;
    };
  }, [code]);
  if (err)
    return (
      <pre className="overflow-auto rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-xs whitespace-pre-wrap text-red-300">
        mermaid 렌더 오류: {err}
        {"\n\n"}
        {code}
      </pre>
    );
  return (
    <div
      ref={ref}
      className="flex justify-center overflow-auto rounded-lg border bg-card/40 p-4 [&_svg]:max-w-full"
    />
  );
};

// Priority / MoSCoW chip tones — applied to cells in a priority column.
const PRIORITY_TONE: Record<string, string> = {
  p0: "border-red-500/30 bg-red-500/15 text-red-300",
  p1: "border-amber-500/30 bg-amber-500/15 text-amber-300",
  p2: "border-sky-500/30 bg-sky-500/15 text-sky-300",
  must: "border-red-500/30 bg-red-500/15 text-red-300",
  should: "border-amber-500/30 bg-amber-500/15 text-amber-300",
  could: "border-sky-500/30 bg-sky-500/15 text-sky-300",
};

export const DataTable = ({ headers, rows }: { headers: string[]; rows: string[][] }) => {
  const prioCol = headers.findIndex((h) => /우선\s*순위|priority|중요도/i.test(h));
  const renderCell = (c: string, ci: number) => {
    const tone = ci === prioCol ? PRIORITY_TONE[c.trim().toLowerCase()] : undefined;
    if (!tone) return c;
    return (
      <span
        className={cn(
          "inline-flex items-center rounded-md border px-2 py-0.5 font-mono text-xs",
          tone,
        )}
      >
        {c}
      </span>
    );
  };
  return (
    <div className="overflow-auto rounded-lg border">
      <table className="w-full border-collapse text-sm">
        {headers.length > 0 && (
          <thead className="bg-muted/50">
            <tr>
              {headers.map((h, i) => (
                <th
                  key={i}
                  className="border-b px-3 py-2 text-left font-semibold whitespace-nowrap text-foreground"
                >
                  {h}
                </th>
              ))}
            </tr>
          </thead>
        )}
        <tbody>
          {rows.map((r, ri) => (
            <tr key={ri} className={ri % 2 ? "bg-muted/20" : ""}>
              {r.map((c, ci) => (
                <td key={ci} className="border-b px-3 py-2 align-top text-foreground/90">
                  {renderCell(c, ci)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

// KPI tiles — a metric with baseline → target. Falsifiable metrics read better
// as tiles than a plain table.
export const KpiPanel = ({
  items,
}: {
  items: { label: string; baseline?: string; target?: string }[];
}) => (
  <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
    {items.map((k, i) => (
      <div key={i} className="rounded-lg border bg-card/40 p-4">
        <div className="text-xs text-muted-foreground">{k.label}</div>
        <div className="mt-1.5 flex items-baseline gap-2">
          {k.baseline && (
            <span className="text-sm text-muted-foreground line-through">{k.baseline}</span>
          )}
          {k.target && <span className="text-2xl font-bold text-foreground">{k.target}</span>}
        </div>
        {k.baseline && k.target && <div className="mt-0.5 text-xs text-emerald-400">→ 목표</div>}
      </div>
    ))}
  </div>
);

// Goals vs Non-goals — the scope boundary side by side, non-goals emphasized.
export const GoalsNonGoals = ({
  goals,
  nongoals,
}: {
  goals: string[];
  nongoals: string[];
}) => (
  <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
    <div className="rounded-lg border border-emerald-500/30 bg-emerald-500/5 p-4">
      <div className="mb-2 text-sm font-semibold text-emerald-300">목표 · In-scope</div>
      <ul className="flex flex-col gap-1.5 text-sm text-foreground/90">
        {goals.map((g, i) => (
          <li key={i} className="flex gap-2">
            <span className="text-emerald-400">✓</span>
            {g}
          </li>
        ))}
      </ul>
    </div>
    <div className="rounded-lg border border-border bg-muted/20 p-4">
      <div className="mb-2 text-sm font-semibold text-muted-foreground">비목표 · Out-of-scope</div>
      <ul className="flex flex-col gap-1.5 text-sm text-muted-foreground">
        {nongoals.map((g, i) => (
          <li key={i} className="flex gap-2">
            <span>✕</span>
            {g}
          </li>
        ))}
      </ul>
    </div>
  </div>
);
