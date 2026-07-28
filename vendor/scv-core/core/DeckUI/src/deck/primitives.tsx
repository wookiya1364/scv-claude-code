import { Fragment, type ReactNode } from "react";
import { cn } from "@/lib/utils";

// PPTX 기획서 슬라이드용 공용 프리미티브 — shadcn 테마 토큰 기반, dark

export const Kicker = ({ children }: { children: ReactNode }) => (
  <div className="text-sm font-semibold tracking-wide text-primary">{children}</div>
);

export const SlideTitle = ({ children, sub }: { children: ReactNode; sub?: ReactNode }) => (
  <div>
    <h1 className="text-4xl font-bold leading-tight tracking-tight text-foreground">{children}</h1>
    {sub && <p className="mt-2 max-w-3xl text-lg text-muted-foreground">{sub}</p>}
  </div>
);

// ── 태그(칩): FR / 스토리 / 역할 ──────────────────────────────
type TagTone = "muted" | "fr" | "story" | "role";
const TAG_TONE: Record<TagTone, string> = {
  muted: "bg-muted text-muted-foreground border-border",
  fr: "bg-sky-500/15 text-sky-300 border-sky-500/30",
  story: "bg-violet-500/15 text-violet-300 border-violet-500/30",
  role: "bg-amber-500/15 text-amber-300 border-amber-500/30",
};
export const Tag = ({ children, tone = "muted" }: { children: ReactNode; tone?: TagTone }) => (
  <span
    className={cn(
      "inline-flex items-center rounded-md border px-2 py-0.5 font-mono text-xs",
      TAG_TONE[tone],
    )}
  >
    {children}
  </span>
);
export const TagRow = ({ children }: { children: ReactNode }) => (
  <div className="flex flex-wrap items-center gap-1.5">{children}</div>
);

// ── 라벨 섹션 ────────────────────────────────────────────────
export const Section = ({
  label,
  children,
  className,
}: {
  label: string;
  children: ReactNode;
  className?: string;
}) => (
  <section className={className}>
    <div className="mb-2 text-xs font-semibold tracking-wider text-muted-foreground">{label}</div>
    <div className="text-[15px] leading-relaxed text-foreground/90">{children}</div>
  </section>
);

// ── 불릿 목록 ────────────────────────────────────────────────
export const Bullets = ({ items, className }: { items: ReactNode[]; className?: string }) => (
  <ul className={cn("flex flex-col gap-2", className)}>
    {items.map((it, i) => (
      <li key={i} className="flex gap-2.5">
        <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-primary/70" />
        <span className="text-[15px] leading-relaxed text-foreground/90">{it}</span>
      </li>
    ))}
  </ul>
);

// ── 강조 박스 ────────────────────────────────────────────────
type Tone = "info" | "good" | "warn" | "danger" | "next";
const CALLOUT_TONE: Record<Tone, string> = {
  info: "border-sky-500/30 bg-sky-500/10",
  good: "border-emerald-500/30 bg-emerald-500/10",
  warn: "border-amber-500/30 bg-amber-500/10",
  danger: "border-red-500/30 bg-red-500/10",
  next: "border-dashed border-border bg-muted/30",
};
export const Callout = ({
  tone = "info",
  title,
  children,
}: {
  tone?: Tone;
  title?: ReactNode;
  children: ReactNode;
}) => (
  <div className={cn("rounded-lg border p-4", CALLOUT_TONE[tone])}>
    {title && <div className="mb-1 font-semibold text-foreground">{title}</div>}
    <div className="text-sm leading-relaxed text-foreground/85">{children}</div>
  </div>
);

// ── 키-값 스펙 표 ────────────────────────────────────────────
export const SpecTable = ({ rows }: { rows: [ReactNode, ReactNode][] }) => (
  <div className="overflow-hidden rounded-lg border">
    {rows.map(([k, v], i) => (
      <div
        key={i}
        className={cn("flex gap-4 px-4 py-2.5 text-sm", i % 2 === 1 && "bg-muted/30")}
      >
        <div className="w-32 shrink-0 font-medium text-muted-foreground">{k}</div>
        <div className="flex-1 text-foreground/90">{v}</div>
      </div>
    ))}
  </div>
);

// ── 브라우저 창(화면 미리보기 프레임) ────────────────────────
export const ScreenFrame = ({ label, children }: { label: string; children: ReactNode }) => (
  <div className="flex h-full min-h-0 flex-col overflow-hidden rounded-xl border bg-background shadow-2xl">
    <div className="flex shrink-0 items-center gap-2 border-b bg-card px-4 py-2.5">
      <span className="h-3 w-3 rounded-full bg-red-500/70" />
      <span className="h-3 w-3 rounded-full bg-amber-500/70" />
      <span className="h-3 w-3 rounded-full bg-emerald-500/70" />
      <span className="ml-3 truncate rounded bg-muted px-2 py-0.5 font-mono text-xs text-muted-foreground">
        {label}
      </span>
      <span className="ml-auto text-xs text-muted-foreground">실제 화면 미리보기</span>
    </div>
    <div className="flex-1 overflow-auto p-6">{children}</div>
  </div>
);

// ── 흐름도 ───────────────────────────────────────────────────
export interface FlowStep {
  step?: string;
  label: ReactNode;
  sub?: ReactNode;
  tone?: "active" | "next";
}
export const Flow = ({ steps }: { steps: FlowStep[] }) => (
  <div className="flex flex-wrap items-stretch gap-2">
    {steps.map((s, i) => (
      <Fragment key={i}>
        <div
          className={cn(
            "flex min-w-[128px] flex-1 flex-col gap-1 rounded-lg border p-3",
            s.tone === "next" ? "border-dashed opacity-60" : "bg-card",
          )}
        >
          {s.step && <div className="text-xs text-muted-foreground">{s.step}</div>}
          <div className="font-semibold text-foreground">{s.label}</div>
          {s.sub && <div className="text-xs text-muted-foreground">{s.sub}</div>}
        </div>
        {i < steps.length - 1 && (
          <div className="flex items-center text-xl text-muted-foreground">→</div>
        )}
      </Fragment>
    ))}
  </div>
);

// ── 상태 범례 ────────────────────────────────────────────────
// Generic status legend — DeckUI is domain-agnostic; callers pass their own
// items (label + swatch className). (Decoupled from ai_tm_center @/domain.)
export const StatusLegend = ({
  items,
}: {
  items: { label: ReactNode; className?: string }[];
}) => (
  <div className="flex flex-wrap gap-4">
    {items.map((it, idx) => (
      <span key={idx} className="flex items-center gap-1.5 text-sm text-muted-foreground">
        <span className={cn("h-3 w-3 rounded-full border", it.className)} />
        {it.label}
      </span>
    ))}
  </div>
);

// ── 슬라이드 공통 셸 (헤더 + 스크롤 본문) ────────────────────
export const SlideShell = ({
  kicker,
  title,
  sub,
  children,
}: {
  kicker: string;
  title: ReactNode;
  sub?: ReactNode;
  children: ReactNode;
}) => (
  <div className="flex h-full min-h-0 flex-col gap-6">
    <div>
      <Kicker>{kicker}</Kicker>
      <SlideTitle sub={sub}>{title}</SlideTitle>
    </div>
    <div className="min-h-0 flex-1 overflow-auto pr-1">{children}</div>
  </div>
);

// ── 코드/구조 블록 ───────────────────────────────────────────
export const CodeBlock = ({ children }: { children: ReactNode }) => (
  <pre className="overflow-auto rounded-lg border bg-muted/40 p-4 font-mono text-xs leading-relaxed text-foreground/90">
    {children}
  </pre>
);

// ── DB 스키마 표 ─────────────────────────────────────────────
type ColBadge = "PK" | "FK" | "IDX" | "NN" | "UQ";
const COL_BADGE: Record<ColBadge, string> = {
  PK: "bg-amber-500/20 text-amber-300",
  FK: "bg-sky-500/20 text-sky-300",
  IDX: "bg-violet-500/20 text-violet-300",
  NN: "bg-emerald-500/20 text-emerald-300",
  UQ: "bg-pink-500/20 text-pink-300",
};
export interface SchemaColumn {
  name: string;
  type: string;
  note?: string;
  badge?: ColBadge;
}
export const SchemaTable = ({
  table,
  sub,
  columns,
}: {
  table: string;
  sub?: string;
  columns: SchemaColumn[];
}) => (
  <div className="overflow-hidden rounded-lg border bg-card">
    <div className="flex items-baseline gap-2 border-b bg-muted/40 px-3 py-2">
      <span className="font-mono text-sm font-semibold text-foreground">{table}</span>
      {sub && <span className="text-xs text-muted-foreground">{sub}</span>}
    </div>
    <div className="divide-y divide-border/50">
      {columns.map((c) => (
        <div key={c.name} className="flex items-center gap-2 px-3 py-1.5 text-xs">
          {c.badge && (
            <span
              className={cn(
                "rounded px-1 py-0.5 font-mono text-[10px] font-bold",
                COL_BADGE[c.badge],
              )}
            >
              {c.badge}
            </span>
          )}
          <span className="font-mono text-foreground/90">{c.name}</span>
          <span className="font-mono text-muted-foreground">{c.type}</span>
          {c.note && <span className="ml-auto truncate pl-2 text-muted-foreground">{c.note}</span>}
        </div>
      ))}
    </div>
  </div>
);

// ── 상태 전이 목록 ───────────────────────────────────────────
export interface Transition {
  from: ReactNode;
  cond?: ReactNode;
  to: ReactNode;
  tone?: Tone;
}
export const TransitionList = ({ rows }: { rows: Transition[] }) => (
  <div className="flex flex-col gap-2.5">
    {rows.map((r, i) => (
      <div key={i} className="flex items-center gap-2 text-sm">
        <span className="rounded-md border bg-card px-2.5 py-1 text-foreground/90">{r.from}</span>
        <span className="flex flex-col items-center px-1 text-muted-foreground">
          {r.cond && <span className="text-[11px] leading-tight">{r.cond}</span>}
          <span className="text-base leading-none">→</span>
        </span>
        <span
          className={cn(
            "rounded-md border px-2.5 py-1",
            r.tone ? CALLOUT_TONE[r.tone] : "bg-card text-foreground/90",
          )}
        >
          {r.to}
        </span>
      </div>
    ))}
  </div>
);
