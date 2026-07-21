import { type Slide } from "@/deck/SlideDeck";
import { SlideShell } from "@/deck/primitives";
import raw from "./sample-prd.md?raw";

// The raw markdown shown verbatim in the right-hand SourcePanel (the transform
// never mutates it — panel is the ground truth).
const src = { doc: { label: "sample-prd.md", text: raw } };

const Cover = () => (
  <SlideShell
    kicker="DeckUI · sample"
    title="샘플 기획서 덱"
    sub="DeckUI 추출·빌드 검증용 최소 덱"
  >
    <div className="space-y-3 text-foreground">
      <p>이 덱은 DeckUI 추출이 실제로 빌드·렌더되는지 검증하는 최소 샘플입니다.</p>
      <p className="text-muted-foreground">
        우측 "기획서 원문" 패널에 아래 markdown이 그대로 표시됩니다 (S 키로 토글).
      </p>
    </div>
  </SlideShell>
);

const Next = () => (
  <SlideShell kicker="다음" title="결정론적 md → 덱 변환" sub="P1 다음 단계">
    <ul className="list-disc space-y-2 pl-6 text-foreground">
      <li>remark로 markdown 파싱 → 섹션/표/mermaid를 DeckUI 프리미티브에 매핑</li>
      <li>SourcePanel 하이라이트를 섹션 위치에서 자동 연결</li>
      <li>빠진 섹션은 린트로 경고 (내용을 지어내지 않음)</li>
    </ul>
  </SlideShell>
);

export const sampleDeck = {
  title: "DeckUI 샘플",
  slides: [
    { id: "cover", nav: "표지", Comp: Cover, sources: [{ ...src, highlights: [{ anchor: "샘플 기획서" }] }] },
    { id: "next", nav: "다음", Comp: Next, sources: [src] },
  ] as Slide[],
};
