import { useCallback, useEffect, useRef, useState, type ComponentType } from "react";
import { cn } from "@/lib/utils";
import { SourcePanel } from "@/deck/SourcePanel";

// 사이드 패널이 보여줄 기획서 원문 한 건(레이블 + 전문).
export interface DeckSource {
  label: string; // 파일 경로 등 표시용 레이블
  text: string; // 마크다운/YAML 원문 전문
}

// 원문에서 형광펜으로 칠할 구간. anchor(부분 문자열, 보통 헤딩)부터
// until(부분 문자열)까지, until 없으면 다음 헤딩 직전까지.
export interface SourceHighlight {
  anchor: string;
  until?: string;
}

// 한 슬라이드가 연결하는 원문 한 건 + 형광펜 구간들. 여러 건이면 패널에 탭으로 표시.
export interface SlideSourceDoc {
  doc: DeckSource;
  highlights?: SourceHighlight[];
}

export interface Slide {
  id: string;
  nav: string; // 상단 목차용 짧은 이름
  Comp: ComponentType;
  sources?: SlideSourceDoc[]; // 옆 패널에 띄울 기획서 원문(형광펜 연결). 없으면 패널 비움.
}

export const SlideDeck = ({ slides, deckTitle }: { slides: Slide[]; deckTitle: string }) => {
  const [i, setI] = useState(0);
  const total = slides.length;
  // 이 덱에 연결된 원문이 하나라도 있으면 패널을 기본으로 연다.
  const [panelOpen, setPanelOpen] = useState(() =>
    slides.some((s) => s.sources && s.sources.length > 0),
  );
  // 사이드 패널 너비(px). 좌측 경계를 드래그해 조절한다. 본문은 flex-1로 자동 반응.
  const [panelWidth, setPanelWidth] = useState(640);
  const draggingRef = useRef(false);

  const clamp = useCallback((n: number) => Math.max(0, Math.min(total - 1, n)), [total]);
  const go = useCallback((n: number) => setI(() => clamp(n)), [clamp]);

  // 패널 좌측 경계 드래그 리사이즈. 최소 320px, 본문에 최소 420px 남긴다.
  const startResize = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    draggingRef.current = true;
    document.body.style.userSelect = "none";
    document.body.style.cursor = "col-resize";
    const onMove = (ev: MouseEvent) => {
      if (!draggingRef.current) return;
      const raw = window.innerWidth - ev.clientX;
      const max = Math.max(320, window.innerWidth - 420);
      setPanelWidth(Math.min(max, Math.max(320, raw)));
    };
    const onUp = () => {
      draggingRef.current = false;
      document.body.style.userSelect = "";
      document.body.style.cursor = "";
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
  }, []);

  // 함수형 업데이트로 최신 index 기준 이동 (stale closure 방지)
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      // 프로토타입 등 폼 입력 중에는 슬라이드 이동/토글 단축키를 가로채지 않는다.
      const t = e.target as HTMLElement | null;
      if (
        t &&
        (t.tagName === "INPUT" ||
          t.tagName === "TEXTAREA" ||
          t.tagName === "SELECT" ||
          t.isContentEditable)
      )
        return;
      if (e.key === "ArrowRight" || e.key === "PageDown") setI((c) => clamp(c + 1));
      else if (e.key === "ArrowLeft" || e.key === "PageUp") setI((c) => clamp(c - 1));
      else if (e.key === "Home") setI(0);
      else if (e.key === "End") setI(total - 1);
      else if (e.key === "s" || e.key === "S") setPanelOpen((p) => !p);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [clamp, total]);

  const Current = slides[i].Comp;

  return (
    <div className="dark flex h-svh flex-col bg-background text-foreground">
      {/* 상단: 덱 제목 + 목차 */}
      <header className="flex shrink-0 items-center gap-4 border-b px-6 py-3">
        <div className="text-sm font-semibold">{deckTitle}</div>
        <nav className="flex flex-1 flex-wrap items-center gap-1 overflow-x-auto">
          {slides.map((s, idx) => (
            <button
              key={s.id}
              onClick={() => go(idx)}
              className={cn(
                "rounded px-2 py-1 text-xs transition-colors whitespace-nowrap",
                idx === i
                  ? "bg-primary text-primary-foreground"
                  : "text-muted-foreground hover:bg-muted",
              )}
            >
              {idx + 1}. {s.nav}
            </button>
          ))}
        </nav>
        <button
          onClick={() => setPanelOpen((p) => !p)}
          className={cn(
            "shrink-0 rounded-md border px-2.5 py-1 text-xs font-medium transition-colors",
            panelOpen ? "bg-muted" : "hover:bg-muted",
          )}
          title="기획서 원문 패널 토글 (S)"
        >
          {panelOpen ? "기획서 숨기기" : "기획서 보기"} <span className="text-muted-foreground">(S)</span>
        </button>
      </header>

      {/* 본문: 왼쪽 슬라이드 + (열면) 오른쪽 기획서 원문 패널 */}
      <main className="min-h-0 flex-1 overflow-hidden">
        <div className="flex h-full min-h-0">
          <div
            className={cn(
              "min-h-0 overflow-hidden px-10 py-8",
              panelOpen ? "flex-1" : "w-full",
            )}
          >
            <div className="mx-auto flex h-full min-h-0 w-full max-w-[1200px] flex-col">
              <Current />
            </div>
          </div>
          {panelOpen && (
            <aside
              style={{ width: panelWidth }}
              className="relative flex shrink-0 flex-col border-l bg-card/30"
            >
              {/* 좌측 경계 드래그 핸들 */}
              <div
                onMouseDown={startResize}
                title="드래그해서 패널 크기 조절"
                className="absolute left-0 top-0 z-20 h-full w-2 -translate-x-1/2 cursor-col-resize hover:bg-primary/40"
              />
              <div className="flex shrink-0 items-center justify-between border-b px-3 py-2">
                <span className="text-xs font-semibold text-muted-foreground">
                  기획서 원문 · 형광펜 = 이 슬라이드의 근거
                </span>
                <button
                  onClick={() => setPanelOpen(false)}
                  className="rounded px-2 py-0.5 text-xs text-muted-foreground hover:bg-muted"
                >
                  닫기 ✕
                </button>
              </div>
              <div className="min-h-0 flex-1">
                <SourcePanel key={slides[i].id} sources={slides[i].sources} />
              </div>
            </aside>
          )}
        </div>
      </main>

      {/* 하단: 진행·이동 */}
      <footer className="flex shrink-0 items-center justify-between gap-4 border-t px-6 py-3">
        <div className="flex items-center gap-1.5">
          {slides.map((s, idx) => (
            <button
              key={s.id}
              onClick={() => go(idx)}
              aria-label={s.nav}
              className={cn(
                "h-2 rounded-full transition-all",
                idx === i ? "w-6 bg-primary" : "w-2 bg-muted hover:bg-muted-foreground/40",
              )}
            />
          ))}
        </div>
        <div className="flex items-center gap-3">
          <span className="text-sm text-muted-foreground">
            {i + 1} / {total}
          </span>
          <button
            onClick={() => go(i - 1)}
            disabled={i === 0}
            className="rounded-md border px-3 py-1.5 text-sm font-medium disabled:opacity-40 hover:bg-muted"
          >
            ‹ 이전
          </button>
          <button
            onClick={() => go(i + 1)}
            disabled={i === total - 1}
            className="rounded-md border px-3 py-1.5 text-sm font-medium disabled:opacity-40 hover:bg-muted"
          >
            다음 ›
          </button>
        </div>
      </footer>
    </div>
  );
};
