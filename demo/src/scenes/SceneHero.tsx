import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { COLORS, FONTS, SIZES } from "../design";

export const SceneHero = () => {
  const frame = useCurrentFrame();
  const fadeIn = interpolate(frame, [0, 20], [0, 1], { extrapolateRight: "clamp" });
  const subtitleFadeIn = interpolate(frame, [30, 50], [0, 1], { extrapolateRight: "clamp" });

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
      <div style={{ opacity: fadeIn }}>
        <div
          style={{
            fontFamily: FONTS.sans,
            fontSize: SIZES.hero,
            fontWeight: 800,
            color: COLORS.text,
            letterSpacing: -1,
          }}
        >
          SCV
        </div>
        <div
          style={{
            fontFamily: FONTS.sans,
            fontSize: SIZES.subtitle,
            color: COLORS.accent,
            marginTop: 16,
            letterSpacing: 4,
          }}
        >
          Standard · Cowork · Verify
        </div>
      </div>
      <div
        style={{
          opacity: subtitleFadeIn,
          marginTop: 60,
          maxWidth: 900,
          fontFamily: FONTS.sans,
          fontSize: SIZES.title,
          fontWeight: 600,
          color: COLORS.text,
          lineHeight: 1.3,
        }}
      >
        Every change ships with a plan and tests.
        <br />
        <span style={{ color: COLORS.accent }}>The tests run forever.</span>
      </div>
    </AbsoluteFill>
  );
};
