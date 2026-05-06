import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { COLORS, FONTS, SIZES } from "../design";

const COMMAND = "/scv:help";

export const SceneHelp = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Container fade in
  const containerOpacity = interpolate(frame, [0, 12], [0, 1], { extrapolateRight: "clamp" });

  // Typing: 1 char per 4 frames, starting at frame 18
  const TYPE_START = 18;
  const CHARS_PER_FRAME = 1 / 4;
  const charsRevealed = Math.min(
    COMMAND.length,
    Math.max(0, Math.floor((frame - TYPE_START) * CHARS_PER_FRAME))
  );
  const typed = COMMAND.slice(0, charsRevealed);

  // Cursor blink (every 0.5s)
  const cursorVisible = Math.floor((frame / fps) * 2) % 2 === 0;

  // Subtitle fades in after typing complete
  const subtitleOpacity = interpolate(frame, [80, 100], [0, 1], { extrapolateRight: "clamp" });

  // Box glow pulse (subtle, after typing complete)
  const glowIntensity = interpolate(
    Math.sin(((frame - 80) / fps) * Math.PI) * 0.5 + 0.5,
    [0, 1],
    [0.3, 0.7]
  );

  return (
    <AbsoluteFill
      style={{
        backgroundColor: COLORS.bg,
        justifyContent: "center",
        alignItems: "center",
        flexDirection: "column",
        padding: 80,
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
        Step 1 — The only command you need to remember
      </div>
      <div
        style={{
          opacity: containerOpacity,
          fontFamily: FONTS.mono,
          fontSize: SIZES.title,
          color: COLORS.accent,
          padding: "24px 48px",
          backgroundColor: COLORS.bgPanel,
          border: `2px solid ${COLORS.accent}`,
          borderRadius: 12,
          minWidth: 360,
          textAlign: "center",
          boxShadow: charsRevealed === COMMAND.length
            ? `0 0 ${30 * glowIntensity}px ${COLORS.accent}88`
            : "none",
        }}
      >
        <span>{typed}</span>
        <span
          style={{
            opacity: cursorVisible ? 1 : 0,
            color: COLORS.accent,
            marginLeft: 2,
          }}
        >
          ▍
        </span>
      </div>
      <div
        style={{
          opacity: subtitleOpacity,
          marginTop: 40,
          fontFamily: FONTS.sans,
          fontSize: SIZES.body,
          color: COLORS.textMuted,
          maxWidth: 800,
          textAlign: "center",
          lineHeight: 1.5,
        }}
      >
        Diagnoses your project's state and tells you what to do next.
        <br />
        No flags. No docs to read first.
      </div>
    </AbsoluteFill>
  );
};
