import { SlideDeck, type Slide } from "@/deck/SlideDeck";
import { SlideShell, Bullets, Callout, SpecTable } from "@/deck/primitives";
import { DataTable, Mermaid } from "@/deck/blocks";

// Data-driven deck: md-to-deck.mjs (deterministic transform) emits a deck.json
// matching this shape; this component maps typed blocks → DeckUI primitives.
// No TSX is generated — the transform output is plain data (diffable/testable).

export type Block =
  | { type: "para"; text: string }
  | { type: "bullets"; items: string[] }
  | { type: "table"; headers: string[]; rows: string[][] }
  | { type: "kv"; rows: [string, string][] }
  | { type: "mermaid"; code: string }
  | { type: "code"; lang?: string; text: string }
  | { type: "callout"; tone: "info" | "good" | "warn" | "danger" | "next"; title?: string; text: string };

export interface DeckSlideData {
  id: string;
  nav: string;
  kicker: string;
  title: string;
  sub?: string;
  anchor: string;
  blocks: Block[];
}

export interface DeckData {
  title: string;
  slug: string;
  source: { label: string; text: string };
  slides: DeckSlideData[];
  lint?: { level: string; message: string }[];
}

function BlockView({ b }: { b: Block }) {
  switch (b.type) {
    case "para":
      return <p className="text-[15px] leading-relaxed text-foreground/90">{b.text}</p>;
    case "bullets":
      return <Bullets items={b.items} />;
    case "table":
      return <DataTable headers={b.headers} rows={b.rows} />;
    case "kv":
      return <SpecTable rows={b.rows} />;
    case "mermaid":
      return <Mermaid code={b.code} />;
    case "code":
      return (
        <pre className="overflow-auto rounded-lg border bg-card/40 p-3 font-mono text-xs leading-relaxed text-foreground/90">
          {b.text}
        </pre>
      );
    case "callout":
      return (
        <Callout tone={b.tone} title={b.title}>
          {b.text}
        </Callout>
      );
    default:
      return null;
  }
}

export function MarkdownDeck({ data }: { data: DeckData }) {
  const slides: Slide[] = data.slides.map((s) => ({
    id: s.id,
    nav: s.nav,
    Comp: () => (
      <SlideShell kicker={s.kicker} title={s.title} sub={s.sub}>
        <div className="flex flex-col gap-4">
          {s.blocks.map((b, i) => (
            <BlockView key={i} b={b} />
          ))}
        </div>
      </SlideShell>
    ),
    sources: [{ doc: data.source, highlights: s.anchor ? [{ anchor: s.anchor }] : [] }],
  }));

  // Quality/gap report as a final slide — warnings only, never fabricated content.
  if (data.lint && data.lint.length > 0) {
    const lint = data.lint;
    slides.push({
      id: "__lint",
      nav: "품질",
      Comp: () => (
        <SlideShell
          kicker="품질 리포트"
          title="빠졌거나 확인이 필요한 항목"
          sub="원문에 없는 내용은 채우지 않음 — 경고만 표시"
        >
          <div className="flex flex-col gap-3">
            {lint.map((l, i) => (
              <Callout key={i} tone="warn" title={`경고 ${i + 1}`}>
                {l.message}
              </Callout>
            ))}
          </div>
        </SlideShell>
      ),
      sources: [{ doc: data.source }],
    });
  }

  return <SlideDeck slides={slides} deckTitle={data.title} />;
}

// Build-time discovery of generated decks (decks/<slug>/deck.json).
const GENERATED = import.meta.glob("./decks/*/deck.json", { eager: true }) as Record<
  string,
  { default: DeckData }
>;

export function loadGeneratedDeck(slug?: string): DeckData | null {
  if (!slug) return null;
  for (const [path, mod] of Object.entries(GENERATED)) {
    if (path.includes(`/decks/${slug}/`)) return mod.default;
  }
  return null;
}
