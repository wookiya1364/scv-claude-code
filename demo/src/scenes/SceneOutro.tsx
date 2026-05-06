import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { COLORS, FONTS, SIZES } from "../design";

export const SceneOutro = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 20], [0, 1], { extrapolateRight: "clamp" });

  return (
    <AbsoluteFill
      style={{
        backgroundColor: COLORS.bg,
        justifyContent: "center",
        alignItems: "center",
        textAlign: "center",
        padding: 80,
      }}
    >
      <div
        style={{
          opacity,
          fontFamily: FONTS.sans,
          fontSize: SIZES.title,
          fontWeight: 700,
          color: COLORS.text,
          lineHeight: 1.4,
        }}
      >
        The longer your team works,
        <br />
        the <span style={{ color: COLORS.accent }}>thicker</span> your safety net grows.
      </div>
      <div
        style={{
          opacity,
          marginTop: 60,
          fontFamily: FONTS.mono,
          fontSize: SIZES.body,
          color: COLORS.textMuted,
        }}
      >
        github.com/wookiya1364/scv-claude-code
      </div>
    </AbsoluteFill>
  );
};
