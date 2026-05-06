import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { COLORS, FONTS, SIZES } from "../design";

export const ScenePromote = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Container fade
  const containerOpacity = interpolate(frame, [0, 12], [0, 1], { extrapolateRight: "clamp" });

  // Flow pulse: a bright dot travels from raw box → PLAN box.
  // Cycle every 1.5 seconds (45 frames), starting at frame 30.
  const FLOW_START = 30;
  const FLOW_CYCLE = fps * 1.5;
  const flowProgress = ((frame - FLOW_START) % FLOW_CYCLE) / FLOW_CYCLE;
  const flowVisible = frame >= FLOW_START;

  // PLAN box "fills in" — content lines appear sequentially after frame 60
  const planLineOpacity = (i: number) =>
    interpolate(frame, [60 + i * 15, 75 + i * 15], [0, 1], {
      extrapolateRight: "clamp",
      extrapolateLeft: "clamp",
    });

  // Bottom caption fades in last
  const captionOpacity = interpolate(frame, [110, 130], [0, 1], { extrapolateRight: "clamp" });

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
        Step 2 — Drop materials, run /scv:promote
      </div>
      <div
        style={{
          opacity: containerOpacity,
          display: "flex",
          gap: 32,
          alignItems: "center",
          fontFamily: FONTS.mono,
          fontSize: SIZES.body,
          position: "relative",
        }}
      >
        {/* Raw box */}
        <div style={{ ...box, color: COLORS.text }}>
          <div style={{ fontSize: SIZES.body, color: COLORS.text }}>scv/raw/</div>
          <div style={{ color: COLORS.textMuted, fontSize: SIZES.caption, marginTop: 12, lineHeight: 1.6 }}>
            meeting notes
            <br />
            spec.pdf
            <br />
            screenshots
          </div>
        </div>

        {/* Flow arrow with traveling pulse */}
        <div style={{ width: 80, height: 40, position: "relative" }}>
          {/* Static line */}
          <div
            style={{
              position: "absolute",
              top: "50%",
              left: 0,
              right: 0,
              height: 2,
              backgroundColor: COLORS.border,
              transform: "translateY(-50%)",
            }}
          />
          {/* Arrow head */}
          <div
            style={{
              position: "absolute",
              top: "50%",
              right: -2,
              transform: "translateY(-50%)",
              fontSize: 28,
              color: COLORS.accent,
              lineHeight: 1,
            }}
          >
            ▶
          </div>
          {/* Traveling pulse */}
          {flowVisible && (
            <div
              style={{
                position: "absolute",
                top: "50%",
                left: `${flowProgress * 100}%`,
                width: 12,
                height: 12,
                borderRadius: 6,
                backgroundColor: COLORS.accent,
                transform: "translate(-50%, -50%)",
                boxShadow: `0 0 16px ${COLORS.accent}`,
              }}
            />
          )}
        </div>

        {/* PLAN box with sequential content fill-in */}
        <div style={{ ...boxAccent, minWidth: 280, textAlign: "left" as const }}>
          <div style={{ fontWeight: 700, fontSize: SIZES.body, marginBottom: 12 }}>
            PLAN.md
          </div>
          <div style={{ opacity: planLineOpacity(0), fontSize: SIZES.caption, lineHeight: 1.7 }}>
            <span style={{ color: COLORS.orange }}>title:</span> Refund button
          </div>
          <div style={{ opacity: planLineOpacity(1), fontSize: SIZES.caption, lineHeight: 1.7 }}>
            <span style={{ color: COLORS.orange }}>refs:</span> [PAY-1234]
          </div>
          <div style={{ opacity: planLineOpacity(2), fontSize: SIZES.caption, lineHeight: 1.7 }}>
            <span style={{ color: COLORS.orange }}>tests:</span> 3 scenarios
          </div>
          <div style={{ opacity: planLineOpacity(3), fontSize: SIZES.caption, lineHeight: 1.7 }}>
            + TESTS.md, diagrams
          </div>
        </div>
      </div>
      <div
        style={{
          opacity: captionOpacity,
          marginTop: 40,
          fontFamily: FONTS.sans,
          fontSize: SIZES.body,
          color: COLORS.textMuted,
        }}
      >
        Claude refines them <em style={{ color: COLORS.text }}>with you</em> — never replaces.
      </div>
    </AbsoluteFill>
  );
};

const box = {
  padding: "32px 40px",
  backgroundColor: COLORS.bgPanel,
  border: `2px solid ${COLORS.border}`,
  borderRadius: 12,
  minWidth: 220,
  textAlign: "center" as const,
};
const boxAccent = {
  ...box,
  backgroundColor: COLORS.accent,
  color: COLORS.accentText,
  border: `2px solid ${COLORS.orange}`,
};
