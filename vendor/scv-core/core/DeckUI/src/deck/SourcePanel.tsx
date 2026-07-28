import { useEffect, useMemo, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { cn } from "@/lib/utils";
import type { SlideSourceDoc, SourceHighlight } from "@/deck/SlideDeck";

// 마크다운 헤딩 레벨(선행 # 개수). 헤딩이 아니면 0.
function headingLevel(line: string): number {
  const m = /^(#{1,6})\s/.exec(line);
  return m ? m[1].length : 0;
}

// 원문에서 형광펜으로 칠할 줄 번호 집합. anchor(부분 문자열)부터 until까지,
// until이 없고 anchor가 헤딩이면 같은 레벨 이상 헤딩 직전까지(하위 ### 포함), 아니면 다음 헤딩 직전까지.
function computeHighlight(lines: string[], highlights?: SourceHighlight[]) {
  const set = new Set<number>();
  for (const h of highlights ?? []) {
    const start = lines.findIndex((l) => l.includes(h.anchor));
    if (start < 0) continue;
    let end: number;
    if (h.until) {
      const u = lines.findIndex((l, idx) => idx > start && l.includes(h.until as string));
      end = u < 0 ? lines.length - 1 : u;
    } else {
      const anchorLevel = headingLevel(lines[start]);
      let stop = -1;
      for (let idx = start + 1; idx < lines.length; idx++) {
        const lvl = headingLevel(lines[idx]);
        if (lvl > 0 && (anchorLevel === 0 || lvl <= anchorLevel)) {
          stop = idx;
          break;
        }
      }
      end = stop < 0 ? lines.length - 1 : stop - 1;
    }
    for (let k = start; k <= end; k++) set.add(k);
  }
  return set;
}

// 마크다운을 헤딩 기준으로 섹션 분할(코드펜스 내부의 # 는 무시).
function splitSections(lines: string[]): { start: number; end: number }[] {
  const heads: number[] = [];
  let fence = false;
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*(```|~~~)/.test(lines[i])) fence = !fence;
    else if (!fence && /^#{1,6}\s/.test(lines[i])) heads.push(i);
  }
  if (heads.length === 0) return [{ start: 0, end: lines.length - 1 }];
  const secs: { start: number; end: number }[] = [];
  if (heads[0] > 0) secs.push({ start: 0, end: heads[0] - 1 });
  for (let k = 0; k < heads.length; k++) {
    secs.push({ start: heads[k], end: k + 1 < heads.length ? heads[k + 1] - 1 : lines.length - 1 });
  }
  return secs;
}

// 맨 앞 YAML frontmatter(--- ... ---) 제거 — 프리뷰에서 표처럼 깨져 보이는 것 방지.
function stripFrontmatter(text: string): string {
  if (!text.startsWith("---\n")) return text;
  const close = text.indexOf("\n---", 4);
  if (close < 0) return text;
  const nl = text.indexOf("\n", close + 1);
  return nl < 0 ? "" : text.slice(nl + 1);
}

const isMarkdown = (label: string) => /\.md$/i.test(label);

export function SourcePanel({ sources }: { sources?: SlideSourceDoc[] }) {
  const [tab, setTab] = useState(0);

  if (!sources || sources.length === 0) {
    return (
      <div className="flex h-full items-center justify-center p-6 text-center text-sm text-muted-foreground">
        이 슬라이드에 연결된 기획서 문서가 없습니다.
      </div>
    );
  }

  const idx = Math.min(tab, sources.length - 1);
  const active = sources[idx];
  return (
    <div className="flex h-full min-h-0 flex-col">
      {sources.length > 1 && (
        <div className="flex shrink-0 flex-wrap items-center gap-1 border-b px-3 py-2">
          {sources.map((s, i) => (
            <button
              key={s.doc.label + i}
              onClick={() => setTab(i)}
              className={cn(
                "rounded px-2 py-1 font-mono text-[11px] transition-colors",
                i === idx
                  ? "bg-primary text-primary-foreground"
                  : "text-muted-foreground hover:bg-muted",
              )}
            >
              {s.doc.label.replace(/^docs\//, "")}
            </button>
          ))}
        </div>
      )}
      <SourceBody key={active.doc.label} active={active} single={sources.length === 1} />
    </div>
  );
}

interface Sec {
  text: string;
  on: boolean;
}

function SourceBody({ active, single }: { active: SlideSourceDoc; single: boolean }) {
  const md = isMarkdown(active.doc.label);
  const firstRef = useRef<HTMLDivElement | null>(null);

  const model = useMemo(() => {
    const text = md ? stripFrontmatter(active.doc.text) : active.doc.text;
    const lines = text.split("\n");
    const set = computeHighlight(lines, active.highlights);
    const firstIdx = set.size ? Math.min(...set) : -1;
    const sections: Sec[] = md
      ? splitSections(lines).map((s) => {
          let on = false;
          for (let n = s.start; n <= s.end; n++) if (set.has(n)) on = true;
          return { text: lines.slice(s.start, s.end + 1).join("\n"), on };
        })
      : [];
    return { lines, set, firstIdx, sections, firstSec: sections.findIndex((s) => s.on) };
  }, [active, md]);

  useEffect(() => {
    firstRef.current?.scrollIntoView({ block: "center" });
  }, [active]);

  return (
    <div className="flex h-full min-h-0 flex-col">
      {single && (
        <div className="shrink-0 border-b px-4 py-1.5 font-mono text-[11px] text-muted-foreground">
          {active.doc.label}
        </div>
      )}
      <div className="min-h-0 flex-1 overflow-auto bg-muted/10">
        {md ? (
          <div className="py-2">
            {model.sections.map((s, i) => (
              <div
                key={i}
                ref={i === model.firstSec ? firstRef : undefined}
                className={cn(
                  "prose prose-invert prose-sm max-w-none border-l-2 border-transparent px-4 py-1",
                  // 코드/표는 특히 잘 보이게 키운다(사용자 요청).
                  "prose-p:text-[13.5px] prose-li:text-[13.5px] prose-headings:scroll-mt-4",
                  "prose-pre:my-2 prose-pre:bg-black/40 prose-pre:text-[13.5px] prose-pre:leading-relaxed",
                  "prose-code:text-[13.5px] prose-table:my-2 prose-td:text-[13px] prose-th:text-[13px]",
                  s.on && "border-amber-400 bg-amber-300/15",
                )}
              >
                <ReactMarkdown remarkPlugins={[remarkGfm]}>{s.text}</ReactMarkdown>
              </div>
            ))}
          </div>
        ) : (
          <div className="w-max min-w-full py-2 font-mono text-[13.5px] leading-relaxed">
            {model.lines.map((ln, i) => {
              const on = model.set.has(i);
              return (
                <div
                  key={i}
                  ref={i === model.firstIdx ? firstRef : undefined}
                  className={cn(
                    "flex border-l-2 border-transparent px-4",
                    on && "border-amber-400 bg-amber-300/20",
                  )}
                >
                  <span className="mr-3 w-9 shrink-0 select-none text-right text-muted-foreground/40">
                    {i + 1}
                  </span>
                  <span className={cn("whitespace-pre", on ? "text-amber-100" : "text-foreground/75")}>
                    {ln || " "}
                  </span>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
