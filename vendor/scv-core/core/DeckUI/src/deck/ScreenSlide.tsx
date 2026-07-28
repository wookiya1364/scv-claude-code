import type { ComponentType, ReactNode } from "react";
import {
  Bullets,
  Callout,
  Kicker,
  ScreenFrame,
  Section,
  SlideTitle,
  SpecTable,
  Tag,
  TagRow,
} from "./primitives";

export interface ScreenSlideData {
  kicker: string;
  title: ReactNode;
  sub?: ReactNode;
  frameLabel: string;
  Screen: ComponentType;
  frDone?: string[]; // 담당 요구사항
  stories?: string[]; // 관련 작업 단위
  roles?: string[]; // 담당 역할
  intent: ReactNode; // 기획 의도
  callFlow: ReactNode[]; // 호출·데이터 흐름
  data?: [ReactNode, ReactNode][]; // 다루는/보이는 데이터
  rules: ReactNode[]; // 규칙·불변식
  notScope?: ReactNode; // 이번엔 안 하는 것
}

// 화면 슬라이드: 좌측 실제 화면 미리보기 + 우측 기획 주석
export const ScreenSlide = (d: ScreenSlideData) => {
  const { Screen } = d;
  return (
    <div className="flex h-full min-h-0 flex-col gap-5">
      {/* 헤더 */}
      <div className="flex items-end justify-between gap-4">
        <div>
          <Kicker>{d.kicker}</Kicker>
          <SlideTitle sub={d.sub}>{d.title}</SlideTitle>
        </div>
        <TagRow>
          {d.roles?.map((r) => (
            <Tag key={r} tone="role">
              {r}
            </Tag>
          ))}
          {d.frDone?.map((f) => (
            <Tag key={f} tone="fr">
              {f}
            </Tag>
          ))}
          {d.stories?.map((s) => (
            <Tag key={s} tone="story">
              {s}
            </Tag>
          ))}
        </TagRow>
      </div>

      {/* 본문: 좌 화면 / 우 주석 */}
      <div className="grid min-h-0 flex-1 grid-cols-5 gap-6">
        {/* 좌: 화면 미리보기 */}
        <div className="col-span-3 min-h-0">
          <ScreenFrame label={d.frameLabel}>
            <Screen />
          </ScreenFrame>
        </div>

        {/* 우: 기획 주석 (스크롤) */}
        <div className="col-span-2 flex min-h-0 flex-col gap-5 overflow-auto pr-1">
          <Section label="기획 의도 · 왜 이 화면인가">{d.intent}</Section>

          <Section label="호출 · 데이터 흐름">
            <Bullets items={d.callFlow} />
          </Section>

          {d.data && (
            <Section label="다루는 데이터">
              <SpecTable rows={d.data} />
            </Section>
          )}

          <Section label="규칙 · 지켜야 할 선">
            <Bullets items={d.rules} />
          </Section>

          {d.notScope && (
            <Callout tone="warn" title="이번엔 안 하는 것">
              {d.notScope}
            </Callout>
          )}
        </div>
      </div>
    </div>
  );
};
