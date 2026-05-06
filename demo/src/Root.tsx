import { Composition } from "remotion";
import { ScvDemo, FPS, DURATION_SECONDS } from "./ScvDemo";
import { TheLoop, LOOP_FPS, LOOP_DURATION_SECONDS } from "./TheLoop";
import {
  Architecture,
  ARCH_FPS,
  ARCH_DURATION_SECONDS,
  ARCH_WIDTH,
  ARCH_HEIGHT,
} from "./Architecture";

export const Root = () => {
  return (
    <>
      <Composition
        id="ScvDemo"
        component={ScvDemo}
        durationInFrames={FPS * DURATION_SECONDS}
        fps={FPS}
        width={1280}
        height={720}
      />
      <Composition
        id="TheLoop"
        component={TheLoop}
        durationInFrames={LOOP_FPS * LOOP_DURATION_SECONDS}
        fps={LOOP_FPS}
        width={1280}
        height={720}
      />
      <Composition
        id="Architecture"
        component={Architecture}
        durationInFrames={ARCH_FPS * ARCH_DURATION_SECONDS}
        fps={ARCH_FPS}
        width={ARCH_WIDTH}
        height={ARCH_HEIGHT}
      />
    </>
  );
};
