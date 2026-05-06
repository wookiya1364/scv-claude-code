import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { COLORS, FONTS, SIZES } from "../design";

export const ScenePR = () => {
  const frame = useCurrentFrame();
  const containerOpacity = interpolate(frame, [0, 12], [0, 1], { extrapolateRight: "clamp" });

  // Sequential attachment list reveals
  const itemOpacity = (i: number) =>
    interpolate(frame, [30 + i * 20, 50 + i * 20], [0, 1], {
      extrapolateRight: "clamp",
      extrapolateLeft: "clamp",
    });
  const itemSlide = (i: number) =>
    interpolate(frame, [30 + i * 20, 50 + i * 20], [12, 0], {
      extrapolateRight: "clamp",
      extrapolateLeft: "clamp",
    });

  // Final OK line
  const okOpacity = interpolate(frame, [150, 170], [0, 1], { extrapolateRight: "clamp" });

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
          marginBottom: 32,
        }}
      >
        Step 4 — Auto PR with everything attached
      </div>

      {/* GitHub PR card mockup */}
      <div
        style={{
          opacity: containerOpacity,
          fontFamily: FONTS.sans,
          backgroundColor: COLORS.bgPanel,
          padding: 0,
          borderRadius: 12,
          border: `1px solid ${COLORS.border}`,
          minWidth: 760,
          color: COLORS.text,
          overflow: "hidden",
        }}
      >
        {/* PR Header bar */}
        <div
          style={{
            backgroundColor: COLORS.bgPanelLight,
            padding: "16px 24px",
            borderBottom: `1px solid ${COLORS.border}`,
            display: "flex",
            alignItems: "center",
            gap: 12,
          }}
        >
          {/* Status pill */}
          <div
            style={{
              backgroundColor: "#238636",
              color: "#ffffff",
              fontSize: SIZES.caption,
              fontWeight: 600,
              padding: "4px 12px",
              borderRadius: 999,
            }}
          >
            ● Open
          </div>
          {/* Title */}
          <div style={{ fontSize: SIZES.body, fontWeight: 600, flex: 1 }}>
            Add refund button to checkout
          </div>
          {/* PR number */}
          <div style={{ fontSize: SIZES.body, color: COLORS.textMuted }}>#142</div>
        </div>

        {/* PR sub-header (branch info) */}
        <div
          style={{
            padding: "10px 24px",
            borderBottom: `1px solid ${COLORS.border}`,
            display: "flex",
            alignItems: "center",
            gap: 8,
            fontFamily: FONTS.mono,
            fontSize: SIZES.caption,
            color: COLORS.textMuted,
          }}
        >
          <span style={{ color: COLORS.text, fontWeight: 600 }}>wookiya1364</span>
          <span>wants to merge into</span>
          <span
            style={{
              backgroundColor: COLORS.bg,
              padding: "2px 8px",
              borderRadius: 4,
              color: COLORS.blue,
            }}
          >
            main
          </span>
          <span>from</span>
          <span
            style={{
              backgroundColor: COLORS.bg,
              padding: "2px 8px",
              borderRadius: 4,
              color: COLORS.blue,
            }}
          >
            checkout-refund
          </span>
        </div>

        {/* PR body — attachment list */}
        <div style={{ padding: "24px 32px", fontFamily: FONTS.mono, fontSize: SIZES.code, lineHeight: 2 }}>
          <div style={{ color: COLORS.textMuted, fontSize: SIZES.caption, marginBottom: 12 }}>
            Auto-attached by /scv:work:
          </div>
          {ATTACHMENTS.map((att, i) => (
            <div
              key={i}
              style={{
                opacity: itemOpacity(i),
                transform: `translateY(${itemSlide(i)}px)`,
                color: COLORS.text,
              }}
            >
              <span style={{ color: COLORS.accent, marginRight: 12 }}>{att.icon}</span>
              {att.label}
            </div>
          ))}
          <div
            style={{
              opacity: okOpacity,
              marginTop: 16,
              color: COLORS.green,
              fontFamily: FONTS.sans,
              fontSize: SIZES.body,
            }}
          >
            ✓ Reviewer sees the feature working in 5 sec.
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const ATTACHMENTS = [
  { icon: "▶", label: "GIF preview (5-second test recording)" },
  { icon: "▶", label: "Mermaid architecture diagrams" },
  { icon: "▶", label: "Linked Jira ticket: PAY-1234" },
  { icon: "▶", label: ".webm video link (audio + native player)" },
];
