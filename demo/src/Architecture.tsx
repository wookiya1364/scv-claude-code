import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { COLORS, FONTS, SIZES } from "./design";

export const ARCH_FPS = 30;
export const ARCH_DURATION_SECONDS = 14;
export const ARCH_WIDTH = 1600;
export const ARCH_HEIGHT = 720;

// Static layout — today's structure. No camera, no zoom.
const NODE_W = 180;
const NODE_H = 80;

type NodeKind = "rect" | "cylinder";
type NodeDef = {
  cx: number;
  cy: number;
  title: string;
  subtitle?: string;
  isKey?: boolean;
  shape?: NodeKind;
  fill?: string;
  // Optional explicit size overrides.
  w?: number;
  h?: number;
  // Invisible anchor: an arrow target on a container's border, not a box.
  hidden?: boolean;
};

const NODES: Record<string, NodeDef> = {
  // Core
  Core:   { cx: 390,  cy: 150, title: "SCV Core", subtitle: "protocols · scripts · hooks · actions list", isKey: true, w: 420, h: 96 },
  // Release channels
  Dev:    { cx: 920,  cy: 120, title: "dev",   subtitle: "channel/dev branch",   w: 200, h: 64 },
  Stage:  { cx: 1150, cy: 120, title: "stage", subtitle: "channel/stage branch", w: 200, h: 64 },
  Prod:   { cx: 1380, cy: 120, title: "prod",  subtitle: "latest release",       w: 200, h: 64 },
  Swap:   { cx: 1150, cy: 222, title: "/scv:channel", subtitle: "swaps the installed copy", w: 260, h: 52, fill: COLORS.bgPanelLight },
  // Wrappers ("Wrappers" anchor = the top edge of the wrappers container)
  Wrappers: { cx: 690, cy: 310, title: "", w: 0, h: 0, hidden: true },
  Codex:  { cx: 220,  cy: 400, title: "Codex plugin",       subtitle: "scv-codex",       w: 240 },
  Claude: { cx: 560,  cy: 400, title: "Claude Code plugin", subtitle: "scv-claude-code", w: 240 },
  // Mods
  Dash:   { cx: 990,  cy: 400, title: "scv-dashboard", subtitle: "an SCV pane in the desktop app", w: 260, isKey: true },
  Mods:   { cx: 1410, cy: 400, title: "scv-mods", subtitle: "mods marketplace", shape: "cylinder", fill: COLORS.bgPanelLight, w: 180 },
  // Outputs
  PR:     { cx: 390,  cy: 598, title: "PR with evidence", subtitle: "/scv:work",   w: 240, fill: COLORS.bgPanelLight },
  Notify: { cx: 900,  cy: 598, title: "Slack / Discord",  subtitle: "/scv:report", w: 240, fill: COLORS.bgPanelLight },
};

type SubgraphDef = {
  id: string;
  label: string;
  // Optional label center (relative to the container) when the top-left corner is crossed by an arrow.
  labelCenterX?: number;
  x: number;
  y: number;
  w: number;
  h: number;
  fill: string;
  stroke: string;
};

const SUBGRAPHS: SubgraphDef[] = [
  { id: "core",     label: "SCV Core — the shared engine",                  x:  60, y:  40, w:  680, h: 230, fill: COLORS.scvFill,      stroke: "#4a8fbf" },
  { id: "channels", label: "Release channels",                              x: 780, y:  40, w:  760, h: 230, fill: COLORS.externalFill, stroke: "#5fa85f" },
  { id: "wrappers", label: "Wrappers", labelCenterX: 325,                   x:  60, y: 310, w:  680, h: 170, fill: COLORS.scvFill,      stroke: "#4a8fbf" },
  { id: "mods",     label: "Mods — a separate marketplace (Claude Code)",   x: 780, y: 310, w:  760, h: 170, fill: COLORS.externalFill, stroke: "#5fa85f" },
  { id: "output",   label: "Outputs",                                       x:  60, y: 515, w: 1480, h: 150, fill: COLORS.outputFill,   stroke: "#a85faa" },
];

type EdgeDef = {
  from: keyof typeof NODES;
  to: keyof typeof NODES;
  startFrame: number;
  label?: string;
  dashed?: boolean;
  color?: string;
  // Where on the path the label sits (0 = start, 1 = end). Default 0.5.
  labelT?: number;
};

const EDGES: EdgeDef[] = [
  // Phase 1: Core vendored into both wrappers
  { from: "Core", to: "Codex",  startFrame: 30, label: "vendored", color: COLORS.accent },
  { from: "Core", to: "Claude", startFrame: 40, label: "vendored", color: COLORS.accent },
  // Phase 2: channels → /scv:channel → installed copy
  { from: "Dev",   to: "Swap", startFrame: 110, dashed: true, color: COLORS.green },
  { from: "Stage", to: "Swap", startFrame: 118, dashed: true, color: COLORS.green },
  { from: "Prod",  to: "Swap", startFrame: 126, dashed: true, color: COLORS.green },
  { from: "Swap", to: "Wrappers", startFrame: 140, color: COLORS.green, label: "installed copy" },
  // Phase 3: mods marketplace → scv-dashboard → Claude Code desktop app
  { from: "Mods", to: "Dash",   startFrame: 200, label: "/scv:mods-install", color: COLORS.blue },
  { from: "Dash", to: "Claude", startFrame: 215, label: "pane", color: COLORS.blue },
  // Phase 4: outputs
  { from: "Codex",  to: "PR",     startFrame: 280, color: COLORS.accent },
  { from: "Claude", to: "PR",     startFrame: 288, color: COLORS.accent },
  { from: "Codex",  to: "Notify", startFrame: 296, color: COLORS.blue },
  { from: "Claude", to: "Notify", startFrame: 304, color: COLORS.blue },
];

// All nodes/subgraphs appear together at the start.
const NODES_FADEIN_END = 25;

// Compute boundary intersection: where a line from cx,cy in direction (ux,uy)
// exits a rectangle of half-size (halfW, halfH).
const exitPoint = (cx: number, cy: number, ux: number, uy: number, halfW: number, halfH: number) => {
  const eps = 1e-6;
  const tx = Math.abs(ux) > eps ? halfW / Math.abs(ux) : Infinity;
  const ty = Math.abs(uy) > eps ? halfH / Math.abs(uy) : Infinity;
  const t = Math.min(tx, ty);
  return { x: cx + ux * t, y: cy + uy * t };
};

const Subgraph: React.FC<{ cfg: SubgraphDef; frame: number }> = ({ cfg, frame }) => {
  const opacity = interpolate(frame, [0, NODES_FADEIN_END], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <div
      style={{
        position: "absolute",
        left: cfg.x,
        top: cfg.y,
        width: cfg.w,
        height: cfg.h,
        backgroundColor: cfg.fill,
        border: `2px solid ${cfg.stroke}55`,
        borderRadius: 12,
        opacity,
      }}
    >
      <div
        style={{
          position: "absolute",
          left: cfg.labelCenterX ?? 18,
          transform: cfg.labelCenterX ? "translateX(-50%)" : undefined,
          top: 10,
          fontFamily: FONTS.sans,
          fontSize: 16,
          fontWeight: 600,
          color: cfg.stroke,
          letterSpacing: 0.3,
        }}
      >
        {cfg.label}
      </div>
    </div>
  );
};

const Node: React.FC<{ id: keyof typeof NODES; frame: number }> = ({ id, frame }) => {
  const node = NODES[id];
  if (node.hidden) return null;
  const opacity = interpolate(frame, [0, NODES_FADEIN_END], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const w = node.w ?? NODE_W;
  const h = node.h ?? NODE_H;
  const fill = node.isKey ? COLORS.accent : node.fill || COLORS.bgPanel;
  const stroke = node.isKey ? COLORS.orange : COLORS.border;
  const textColor = node.isKey ? COLORS.accentText : COLORS.text;

  if (node.shape === "cylinder") {
    return (
      <div
        style={{
          position: "absolute",
          left: node.cx - w / 2,
          top: node.cy - h / 2,
          width: w,
          height: h,
          opacity,
          backgroundColor: fill,
          border: `2px solid ${stroke}`,
          borderRadius: "50% / 22%",
          display: "flex",
            alignItems: "center",
          justifyContent: "center",
          boxShadow: "0 4px 14px rgba(0,0,0,0.4)",
        }}
      >
        <div style={{ textAlign: "center" }}>
          <div style={{ fontFamily: FONTS.mono, fontSize: 16, fontWeight: 700, color: textColor }}>
            {node.title}
          </div>
          {node.subtitle && (
            <div style={{ fontFamily: FONTS.sans, fontSize: 12, color: textColor, opacity: 0.85, marginTop: 4 }}>
              {node.subtitle}
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <div
      style={{
        position: "absolute",
        left: node.cx - w / 2,
        top: node.cy - h / 2,
        width: w,
        height: h,
        opacity,
        backgroundColor: fill,
        border: `2px solid ${stroke}`,
        borderRadius: 8,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: 8,
        boxShadow: node.isKey ? `0 0 22px ${COLORS.accent}55` : "0 4px 14px rgba(0,0,0,0.4)",
      }}
    >
      <div
        style={{
          fontFamily: FONTS.mono,
          fontSize: node.isKey && (node.h ?? NODE_H) > NODE_H ? 26 : node.title.length > 18 ? 13 : 16,
          fontWeight: 700,
          color: textColor,
          textAlign: "center",
          lineHeight: 1.2,
        }}
      >
        {node.title}
      </div>
      {node.subtitle && (
        <div
          style={{
            fontFamily: FONTS.sans,
            fontSize: (node.h ?? NODE_H) > NODE_H ? 16 : 12,
            color: textColor,
            opacity: 0.85,
            marginTop: 4,
            textAlign: "center",
          }}
        >
          {node.subtitle}
        </div>
      )}
    </div>
  );
};

const Edge: React.FC<{ edge: EdgeDef; frame: number }> = ({ edge, frame }) => {
  const fromN = NODES[edge.from];
  const toN = NODES[edge.to];

  const dx = toN.cx - fromN.cx;
  const dy = toN.cy - fromN.cy;
  const len = Math.hypot(dx, dy);
  if (len === 0) return null;
  const ux = dx / len;
  const uy = dy / len;

  const fromHalfW = (fromN.w ?? NODE_W) / 2;
  const fromHalfH = (fromN.h ?? NODE_H) / 2;
  const toHalfW = (toN.w ?? NODE_W) / 2;
  const toHalfH = (toN.h ?? NODE_H) / 2;

  const start = exitPoint(fromN.cx, fromN.cy, ux, uy, fromHalfW, fromHalfH);
  const end = exitPoint(toN.cx, toN.cy, -ux, -uy, toHalfW, toHalfH);

  const sx = start.x;
  const sy = start.y;
  const ex = end.x;
  const ey = end.y;
  const segLen = Math.hypot(ex - sx, ey - sy);

  const t = frame - edge.startFrame;
  if (t < 0) return null;

  // Phase 1: fade in (12 frames), line gets drawn for solid edges.
  const opacity = interpolate(t, [0, 12], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Line draw progress (solid only). Dashed uses dash flow from the start.
  const drawProgress = interpolate(t, [0, 22], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const color = edge.color || COLORS.text;
  const markerId = `mk-${String(edge.from)}-${String(edge.to)}`.replace(/[^a-z0-9]/gi, "");

  // Dashed flow: dashoffset moves negatively → dashes travel from start to end.
  const dashFlowOffset = -(t * 0.7);

  // Solid-line traveling particle — appears after the line is drawn,
  // loops every 50 frames along the segment.
  const particleAfter = 22;
  const showParticle = !edge.dashed && t > particleAfter;
  const particleT = (t - particleAfter) % 50;
  const particleProgress = particleT / 50;
  const px = sx + (ex - sx) * particleProgress;
  const py = sy + (ey - sy) * particleProgress;
  const particleAlpha = Math.sin(particleProgress * Math.PI); // fade in then out

  // Label position (parametric along the line)
  const labelTRatio = edge.labelT ?? 0.5;
  const labelX = sx + (ex - sx) * labelTRatio;
  const labelY = sy + (ey - sy) * labelTRatio;
  const labelOpacity = interpolate(t, [10, 28], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <>
      <svg
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: ARCH_WIDTH,
          height: ARCH_HEIGHT,
          pointerEvents: "none",
        }}
      >
        <defs>
          <marker
            id={markerId}
            viewBox="0 0 10 10"
            refX="9"
            refY="5"
            markerWidth="7"
            markerHeight="7"
            orient="auto"
          >
            <path d="M 0 0 L 10 5 L 0 10 z" fill={color} />
          </marker>
        </defs>
        {edge.dashed ? (
          // Dashed line with continuous dash-flow animation.
          <line
            x1={sx}
            y1={sy}
            x2={ex}
            y2={ey}
            stroke={color}
            strokeWidth={2.5}
            strokeDasharray="9 7"
            strokeDashoffset={dashFlowOffset}
            opacity={opacity}
            markerEnd={opacity > 0.9 ? `url(#${markerId})` : undefined}
          />
        ) : (
          // Solid line — gets drawn over 22 frames, then particle travels along it.
          <line
            x1={sx}
            y1={sy}
            x2={ex}
            y2={ey}
            stroke={color}
            strokeWidth={3}
            strokeDasharray={`${segLen} ${segLen}`}
            strokeDashoffset={segLen * (1 - drawProgress)}
            opacity={opacity}
            markerEnd={drawProgress > 0.95 ? `url(#${markerId})` : undefined}
          />
        )}
        {showParticle && (
          <circle cx={px} cy={py} r={5} fill={color} opacity={particleAlpha} />
        )}
      </svg>
      {edge.label && (
        <div
          style={{
            position: "absolute",
            left: labelX,
            top: labelY,
            transform: "translate(-50%, -50%)",
            fontFamily: FONTS.mono,
            fontSize: 12,
            color,
            opacity: labelOpacity,
            backgroundColor: COLORS.bg,
            padding: "3px 8px",
            borderRadius: 4,
            whiteSpace: "pre-line",
            lineHeight: 1.3,
            border: `1px solid ${color}66`,
            textAlign: "center",
          }}
        >
          {edge.label}
        </div>
      )}
    </>
  );
};

const PhaseLabel: React.FC<{ frame: number }> = ({ frame }) => {
  // Show what's flowing right now.
  const phases: Array<{ from: number; to: number; text: string }> = [
    { from: 30, to: 110, text: "1.  SCV Core  →  vendored into the two wrappers you install" },
    { from: 110, to: 200, text: "2.  /scv:channel  —  dev · stage · prod swap the installed copy" },
    { from: 200, to: 280, text: "3.  scv-dashboard  —  a mod from a separate marketplace" },
    { from: 280, to: 420, text: "4.  Outputs  —  a PR with evidence · Slack / Discord" },
  ];
  const active = phases.find((p) => frame >= p.from && frame < p.to);
  if (!active) return null;
  // Fade in/out at edges of the phase.
  const opacity = interpolate(
    frame,
    [active.from, active.from + 10, active.to - 10, active.to],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        bottom: 6,
        textAlign: "center",
        opacity,
        pointerEvents: "none",
      }}
    >
      <div
        style={{
          display: "inline-block",
          fontFamily: FONTS.mono,
          fontSize: 16,
          fontWeight: 600,
          color: COLORS.text,
          backgroundColor: `${COLORS.bgPanel}ee`,
          padding: "8px 18px",
          borderRadius: 22,
          border: `1px solid ${COLORS.border}`,
          letterSpacing: 0.3,
        }}
      >
        {active.text}
      </div>
    </div>
  );
};

export const Architecture: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ backgroundColor: COLORS.bg }}>
      {/* Subgraphs (background containers) */}
      {SUBGRAPHS.map((s) => (
        <Subgraph key={s.id} cfg={s} frame={frame} />
      ))}
      {/* Edges (behind nodes so node fills sit on top of incoming arrows) */}
      {EDGES.map((e, i) => (
        <Edge key={i} edge={e} frame={frame} />
      ))}
      {/* Nodes */}
      {(Object.keys(NODES) as Array<keyof typeof NODES>).map((id) => (
        <Node key={id} id={id} frame={frame} />
      ))}
      {/* Phase label ribbon */}
      <PhaseLabel frame={frame} />
    </AbsoluteFill>
  );
};
