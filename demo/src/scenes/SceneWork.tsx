import { AbsoluteFill, interpolate, useCurrentFrame, spring, useVideoConfig } from "remotion";
import { COLORS, FONTS, SIZES } from "../design";

// Sequential check-in animation: 4 rows appear one by one.
// Last row is the "next step" pulse (slow fade in/out).
const ROWS = [
  { check: "✓", text: "Implementation: 6 files changed", color: COLORS.green },
  { check: "✓", text: "Playwright e2e: 3 passed", color: COLORS.green, accent: COLORS.accent },
  { check: "✓", text: ".webm captured (4.2 MB)", color: COLORS.green },
  { check: "→", text: "Archiving · Opening PR", color: COLORS.accent, isPulse: true },
];

export const SceneWork = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const containerOpacity = interpolate(frame, [0, 12], [0, 1], { extrapolateRight: "clamp" });

  return (
    <AbsoluteFill
      style={{
        backgroundColor: COLORS.bg,
        justifyContent: "center",
        alignItems: "center",
        padding: 80,
        flexDirection: "column",
      }}
    >
      <div
        style={{
          opacity: containerOpacity,
          fontFamily: FONTS.sans,
          fontSize: SIZES.subtitle,
          color: COLORS.textMuted,
          marginBottom: 40,
        }}
      >
        Step 3 — /scv:work implements + tests
      </div>
      <div
        style={{
          opacity: containerOpacity,
          fontFamily: FONTS.mono,
          fontSize: SIZES.code,
          backgroundColor: COLORS.bgPanel,
          padding: "32px 40px",
          borderRadius: 12,
          border: `1px solid ${COLORS.border}`,
          minWidth: 600,
          color: COLORS.text,
          lineHeight: 2.0,
        }}
      >
        {ROWS.map((row, i) => {
          // Each row enters at frame (15 + i * 25). Pulse rows also breathe.
          const enterFrom = 15 + i * 25;
          const rowOpacity = interpolate(
            frame,
            [enterFrom, enterFrom + 12],
            [0, 1],
            { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
          );
          const rowSlide = interpolate(
            frame,
            [enterFrom, enterFrom + 12],
            [10, 0],
            { extrapolateRight: "clamp", extrapolateLeft: "clamp" }
          );
          const pulse = row.isPulse
            ? interpolate(
                Math.sin(((frame - enterFrom) / fps) * Math.PI * 2) * 0.5 + 0.5,
                [0, 1],
                [0.65, 1]
              )
            : 1;

          return (
            <div
              key={i}
              style={{
                opacity: rowOpacity * pulse,
                transform: `translateY(${rowSlide}px)`,
                color: row.color,
                marginTop: i === ROWS.length - 1 ? 16 : 0,
              }}
            >
              <span style={{ marginRight: 12 }}>{row.check}</span>
              <span style={{ color: row.accent ?? COLORS.text }}>{row.text}</span>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
