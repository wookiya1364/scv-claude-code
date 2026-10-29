import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { COLORS, FONTS } from "./design";

// How to mirror the SCV pane (scv-dashboard mod) onto a second computer.
// Source of truth: scv-mods/README.md, the paragraph starting "A Remote Control viewer".
export const MIRROR_FPS = 30;
export const MIRROR_DURATION_SECONDS = 19;

const RED = "#f47067";

type Side = {
  cmd?: string; // what the person types in that session
  reply?: string; // what happens (described, not a copy of the real output)
  tone?: "ok" | "bad";
};

type Step = {
  start: number;
  end: number;
  label: string;
  caption: string;
  a: Side;
  b: Side;
  note?: string; // a line under the computers
  bOpen: boolean; // B has a session open in its own desktop app
  mirror: "off" | "on" | "on-then-off";
};

// Each step holds 2–3.5 s so a viewer can read it.
const STEPS: Step[] = [
  {
    start: 45,
    end: 135,
    label: "1",
    caption: "Computer A, the working session: get its address",
    a: { cmd: "/scv-dashboard", reply: "prints this session's address\n(its Remote Control id while Remote Control is on)" },
    b: {},
    bOpen: false,
    mirror: "off",
  },
  {
    start: 135,
    end: 240,
    label: "2",
    caption: "Computer B: open a session in B's own desktop app, then mirror A",
    a: {},
    b: { cmd: "/scv-mirror <address>" },
    note: "Not a Remote Control viewer — claude.ai, the phone or a remote view cannot draw the pane.",
    bOpen: true,
    mirror: "off",
  },
  {
    start: 240,
    end: 315,
    label: "3",
    caption: "B's SCV pane now shows A's state",
    a: {},
    b: { cmd: "/scv-mirror <address>", reply: "sent between the two sessions —\nnever read by either model", tone: "ok" },
    bOpen: true,
    mirror: "on",
  },
  {
    start: 315,
    end: 375,
    label: "4",
    caption: "Check what B mirrors",
    a: {},
    b: { cmd: "/scv-mirror", reply: "says what it mirrors", tone: "ok" },
    bOpen: true,
    mirror: "on",
  },
  {
    start: 375,
    end: 435,
    label: "5",
    caption: "End the mirror",
    a: {},
    b: { cmd: "/scv-mirror stop", reply: "ends it" },
    bOpen: true,
    mirror: "on-then-off",
  },
  {
    start: 435,
    end: 570,
    label: "!",
    caption: "Pitfall: /scv-mirror in the working session itself",
    a: { cmd: "/scv-mirror <address>", reply: "refused — it is itself,\nthere is nowhere to send", tone: "bad" },
    b: {},
    bOpen: true,
    mirror: "off",
  },
];

const TYPE_START = 6;
const TYPE_END = 26;
const REPLY_AT = 30;

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const activeStep = (frame: number): Step | undefined =>
  STEPS.find((s) => frame >= s.start && frame < s.end);

const typed = (text: string, t: number): string =>
  text.slice(0, Math.round(interpolate(t, [TYPE_START, TYPE_END], [0, text.length], clamp)));

const mirrorOpacity = (step: Step | undefined, t: number): number => {
  if (!step) return 0;
  if (step.mirror === "on") return step.start === 240 ? interpolate(t, [REPLY_AT - 10, REPLY_AT + 5], [0, 1], clamp) : 1;
  if (step.mirror === "on-then-off") return interpolate(t, [REPLY_AT - 4, REPLY_AT + 8], [1, 0], clamp);
  return 0;
};

// Skeleton lines stand in for the pane's content — the point is whose state it is.
const PaneSkeleton: React.FC<{ color: string; opacity: number }> = ({ color, opacity }) => (
  <div style={{ opacity }}>
    {[0.9, 0.65, 0.8, 0.5].map((w, i) => (
      <div
        key={i}
        style={{
          height: 12,
          width: `${w * 100}%`,
          backgroundColor: color,
          opacity: i === 0 ? 0.9 : 0.45,
          borderRadius: 6,
          marginBottom: 12,
        }}
      />
    ))}
  </div>
);

const Computer: React.FC<{
  name: string;
  sub: string;
  side: Side;
  t: number;
  open: boolean;
  paneLabel: string;
  paneOpacity: number;
  highlight: boolean;
}> = ({ name, sub, side, t, open, paneLabel, paneOpacity, highlight }) => {
  const replyOpacity = interpolate(t, [REPLY_AT, REPLY_AT + 10], [0, 1], clamp);
  const replyColor = side.tone === "bad" ? RED : side.tone === "ok" ? COLORS.green : COLORS.textMuted;
  return (
    <div
      style={{
        width: 560,
        height: 430,
        backgroundColor: COLORS.bgPanel,
        border: `2px solid ${highlight ? COLORS.accent : COLORS.border}`,
        borderRadius: 14,
        boxShadow: highlight ? `0 0 30px ${COLORS.accent}44` : "0 8px 24px rgba(0,0,0,0.5)",
        display: "flex",
        flexDirection: "column",
        overflow: "hidden",
        opacity: open ? 1 : 0.45,
      }}
    >
      <div
        style={{
          padding: "12px 18px",
          backgroundColor: COLORS.bgPanelLight,
          fontFamily: FONTS.sans,
          display: "flex",
          justifyContent: "space-between",
          alignItems: "baseline",
        }}
      >
        <span style={{ fontSize: 22, fontWeight: 800, color: COLORS.text }}>{name}</span>
        <span style={{ fontSize: 15, color: COLORS.textMuted }}>{sub}</span>
      </div>
      <div style={{ display: "flex", flex: 1 }}>
        {/* Chat side */}
        <div style={{ flex: 1, padding: 18, display: "flex", flexDirection: "column", justifyContent: "flex-end" }}>
          {side.reply && (
            <div
              style={{
                fontFamily: FONTS.sans,
                fontSize: 16,
                lineHeight: 1.4,
                color: replyColor,
                whiteSpace: "pre-line",
                marginBottom: 14,
                opacity: replyOpacity,
              }}
            >
              {side.tone === "bad" ? "✕ " : "→ "}
              {side.reply}
            </div>
          )}
          <div
            style={{
              fontFamily: FONTS.mono,
              fontSize: 18,
              color: COLORS.text,
              backgroundColor: COLORS.bg,
              border: `1px solid ${COLORS.border}`,
              borderRadius: 8,
              padding: "10px 12px",
              minHeight: 24,
            }}
          >
            <span style={{ color: COLORS.accent }}>{side.cmd ? typed(side.cmd, t) : ""}</span>
            <span style={{ opacity: Math.floor(t / 15) % 2 === 0 && open ? 1 : 0 }}>▏</span>
          </div>
        </div>
        {/* SCV pane */}
        <div
          style={{
            width: 190,
            borderLeft: `1px solid ${COLORS.border}`,
            padding: 16,
            backgroundColor: COLORS.scvFill,
          }}
        >
          <div style={{ fontFamily: FONTS.sans, fontSize: 14, fontWeight: 700, color: "#4a8fbf", marginBottom: 6 }}>
            SCV pane
          </div>
          <div style={{ fontFamily: FONTS.sans, fontSize: 12, color: COLORS.textMuted, marginBottom: 16, minHeight: 32 }}>
            {paneLabel}
          </div>
          <PaneSkeleton color={COLORS.accent} opacity={paneOpacity} />
        </div>
      </div>
    </div>
  );
};

export const Mirror: React.FC = () => {
  const frame = useCurrentFrame();
  const step = activeStep(frame);
  const t = step ? frame - step.start : 0;
  const mOpacity = mirrorOpacity(step, t);
  const bOpen = step?.bOpen ?? false;

  const titleOpacity = interpolate(frame, [0, 10, 35, 45], [0, 1, 1, 0], clamp);
  const captionOpacity = step ? interpolate(t, [0, 8], [0, 1], clamp) : 0;
  const footOpacity = interpolate(frame, [435, 450], [0, 1], clamp);

  // Dotted link A → B while the mirror is on; dots travel A → B.
  const linkDash = -(frame * 1.2);

  return (
    <AbsoluteFill style={{ backgroundColor: COLORS.bg }}>
      {/* Title */}
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: titleOpacity, zIndex: 2 }}>
        <div style={{ fontFamily: FONTS.sans, fontSize: 56, fontWeight: 800, color: COLORS.text, textAlign: "center" }}>
          See the SCV pane on another computer
        </div>
        <div style={{ fontFamily: FONTS.mono, fontSize: 22, color: COLORS.accent, marginTop: 14 }}>
          scv-dashboard · /scv-mirror
        </div>
      </AbsoluteFill>

      {/* Step caption */}
      {step && (
        <div
          style={{
            position: "absolute",
            top: 40,
            left: 0,
            right: 0,
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            gap: 16,
            opacity: captionOpacity,
          }}
        >
          <div
            style={{
              width: 44,
              height: 44,
              borderRadius: 22,
              backgroundColor: step.label === "!" ? RED : COLORS.accent,
              color: COLORS.accentText,
              fontFamily: FONTS.mono,
              fontSize: 24,
              fontWeight: 800,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            {step.label}
          </div>
          <div style={{ fontFamily: FONTS.sans, fontSize: 30, fontWeight: 700, color: COLORS.text }}>{step.caption}</div>
        </div>
      )}

      {/* Two computers */}
      {step && (
        <div
          style={{
            position: "absolute",
            top: 130,
            left: 60,
            right: 60,
            display: "flex",
            justifyContent: "space-between",
          }}
        >
          <Computer
            name="Computer A"
            sub="the working session"
            side={step.a}
            t={t}
            open
            paneLabel="this session's state"
            paneOpacity={1}
            highlight={Boolean(step.a.cmd)}
          />
          <Computer
            name="Computer B"
            sub={bOpen ? "a session in B's own desktop app" : "—"}
            side={step.b}
            t={t}
            open={bOpen}
            paneLabel={mOpacity > 0.5 ? "showing A's state" : bOpen ? "not mirroring" : ""}
            paneOpacity={mOpacity}
            highlight={Boolean(step.b.cmd)}
          />
        </div>
      )}

      {/* Mirror link between the panes */}
      {mOpacity > 0 && (
        <svg style={{ position: "absolute", left: 0, top: 0, width: 1280, height: 720, opacity: mOpacity }}>
          <line
            x1={622}
            y1={360}
            x2={646}
            y2={360}
            stroke={COLORS.green}
            strokeWidth={4}
            strokeDasharray="8 8"
            strokeDashoffset={linkDash}
          />
          <path d="M 646 351 L 659 360 L 646 369 z" fill={COLORS.green} />
        </svg>
      )}

      {/* Step note */}
      {step?.note && (
        <div
          style={{
            position: "absolute",
            bottom: 70,
            left: 0,
            right: 0,
            textAlign: "center",
            fontFamily: FONTS.sans,
            fontSize: 22,
            color: COLORS.textMuted,
            opacity: interpolate(t, [REPLY_AT, REPLY_AT + 10], [0, 1], clamp),
          }}
        >
          {step.note}
        </div>
      )}

      {/* Requirement line */}
      <div
        style={{
          position: "absolute",
          bottom: 50,
          left: 0,
          right: 0,
          textAlign: "center",
          fontFamily: FONTS.sans,
          fontSize: 22,
          color: COLORS.textMuted,
          opacity: footOpacity,
        }}
      >
        Both computers need{" "}
        <span style={{ color: COLORS.accent, fontWeight: 700 }}>scv-dashboard 0.2.0 or later</span>.
      </div>
    </AbsoluteFill>
  );
};
