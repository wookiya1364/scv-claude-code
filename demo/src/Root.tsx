import { Composition } from "remotion";
import { ScvDemo, FPS, DURATION_SECONDS } from "./ScvDemo";

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
    </>
  );
};
