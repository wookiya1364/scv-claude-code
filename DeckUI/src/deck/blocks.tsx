import { useEffect, useRef, useState } from "react";
import mermaid from "mermaid";

// New DeckUI primitives beyond the base set: a real N-column DataTable and a
// client-rendered Mermaid diagram. Kept separate from primitives.tsx so the
// mermaid dependency is isolated to the blocks that need it.

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

export const DataTable = ({
  headers,
  rows,
}: {
  headers: string[];
  rows: string[][];
}) => (
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
                {c}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);
