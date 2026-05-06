import { AbsoluteFill, Sequence, useCurrentFrame } from "remotion";
import { SceneHero } from "./scenes/SceneHero";
import { SceneHelp } from "./scenes/SceneHelp";
import { ScenePromote } from "./scenes/ScenePromote";
import { SceneWork } from "./scenes/SceneWork";
import { ScenePR } from "./scenes/ScenePR";
import { SceneOutro } from "./scenes/SceneOutro";

export const FPS = 30;
export const DURATION_SECONDS = 30;

// Each scene's frame range (cumulative). 30 fps × seconds.
export const SCENES = {
  hero: { from: 0, durationInFrames: FPS * 4 },        // 0–4s
  help: { from: FPS * 4, durationInFrames: FPS * 5 },  // 4–9s
  promote: { from: FPS * 9, durationInFrames: FPS * 6 }, // 9–15s
  work: { from: FPS * 15, durationInFrames: FPS * 5 },   // 15–20s
  pr: { from: FPS * 20, durationInFrames: FPS * 7 },     // 20–27s
  outro: { from: FPS * 27, durationInFrames: FPS * 3 },  // 27–30s
};

export const ScvDemo = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#0d1117" }}>
      <Sequence from={SCENES.hero.from} durationInFrames={SCENES.hero.durationInFrames}>
        <SceneHero />
      </Sequence>
      <Sequence from={SCENES.help.from} durationInFrames={SCENES.help.durationInFrames}>
        <SceneHelp />
      </Sequence>
      <Sequence from={SCENES.promote.from} durationInFrames={SCENES.promote.durationInFrames}>
        <ScenePromote />
      </Sequence>
      <Sequence from={SCENES.work.from} durationInFrames={SCENES.work.durationInFrames}>
        <SceneWork />
      </Sequence>
      <Sequence from={SCENES.pr.from} durationInFrames={SCENES.pr.durationInFrames}>
        <ScenePR />
      </Sequence>
      <Sequence from={SCENES.outro.from} durationInFrames={SCENES.outro.durationInFrames}>
        <SceneOutro />
      </Sequence>
    </AbsoluteFill>
  );
};
