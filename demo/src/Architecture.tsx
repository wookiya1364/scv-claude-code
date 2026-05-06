import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { COLORS, FONTS, SIZES } from "./design";

export const ARCH_FPS = 30;
export const ARCH_DURATION_SECONDS = 12;
export const ARCH_WIDTH = 1600;
export const ARCH_HEIGHT = 600;

// Static layout — matches the README Mermaid screenshot. No camera, no zoom.
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
  // Optional explicit width override (e.g., for long titles like FEATURE_ARCHITECTURE.md).
  w?: number;
};

const NODES: Record<string, NodeDef> = {
  // SCV row
  PLAN:    { cx: 300,  cy: 240, title: "PLAN.md",                  subtitle: "(plan + refs)",            isKey: true },
  Archive: { cx: 1080, cy: 100, title: "scv/archive/",             subtitle: "(accumulated regression)", isKey: true },
  TESTS:   { cx: 1080, cy: 240, title: "TESTS.md",                 subtitle: "(executable gate)" },
  FA:      { cx: 1380, cy: 240, title: "FEATURE_ARCHITECTURE.md",  subtitle: "(2 Mermaid diagrams)",     w: 240 },
  // External (cylinders)
  Jira:       { cx: 130,  cy: 500, title: "Jira",                shape: "cylinder", fill: COLORS.bgPanelLight },
  Linear:     { cx: 290,  cy: 500, title: "Linear",              shape: "cylinder", fill: COLORS.bgPanelLight },
  Confluence: { cx: 470,  cy: 500, title: "Confluence",          shape: "cylinder", fill: COLORS.bgPanelLight },
  Doc:        { cx: 670,  cy: 500, title: "Google Doc / Notion", shape: "cylinder", fill: COLORS.bgPanelLight },
  // Output
  GH:      { cx: 890,  cy: 500, title: "GitHub PR", fill: COLORS.bgPanelLight },
  GL:      { cx: 1080, cy: 500, title: "GitLab MR", fill: COLORS.bgPanelLight },
  Slack:   { cx: 1260, cy: 500, title: "Slack",     fill: COLORS.bgPanelLight },
  Discord: { cx: 1450, cy: 500, title: "Discord",   fill: COLORS.bgPanelLight },
};

const SUBGRAPHS = [
  { id: "scv",      label: "SCV (in your repo)",         x:  60, y:  40, w: 1500, h: 320, fill: COLORS.scvFill,      stroke: "#4a8fbf" },
  { id: "external", label: "External (linked via refs:)", x:  60, y: 410, w:  720, h: 170, fill: COLORS.externalFill, stroke: "#5fa85f" },
  { id: "output",   label: "Output channels",            x: 820, y: 410, w:  740, h: 170, fill: COLORS.outputFill,   stroke: "#a85faa" },
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
  // Phase label that lights up while this edge is active.
  phase?: string;
};

const EDGES: EdgeDef[] = [
  // refs (dashed, green) — Phase 1: PLAN → External
  { from: "PLAN", to: "Jira",       startFrame: 30,  label: "refs:", dashed: true, color: COLORS.green, phase: "refs" },
  { from: "PLAN", to: "Linear",     startFrame: 40,  label: "refs:", dashed: true, color: COLORS.green, phase: "refs" },
  { from: "PLAN", to: "Confluence", startFrame: 50,  label: "refs:", dashed: true, color: COLORS.green, phase: "refs" },
  { from: "PLAN", to: "Doc",        startFrame: 60,  label: "refs:", dashed: true, color: COLORS.green, phase: "refs" },
  // work (solid, accent) — Phase 2: PLAN → Output
  { from: "PLAN", to: "GH", startFrame: 130, label: "/scv:work Step 9d\n(.webm + .gif inline)", color: COLORS.accent, labelT: 0.35, phase: "work" },
  { from: "PLAN", to: "GL", startFrame: 145, label: "/scv:work Step 9d", color: COLORS.accent, labelT: 0.55, phase: "work" },
  // regression (solid, accent) — Phase 3: Archive → TESTS
  { from: "Archive", to: "TESTS", startFrame: 200, label: "/scv:regression\n(auto-runs every TESTS)", color: COLORS.accent, phase: "regression" },
  // report (solid, blue) — Phase 4: TESTS → Slack/Discord
  { from: "TESTS", to: "Slack",   startFrame: 270, label: "/scv:report", color: COLORS.blue, phase: "report" },
  { from: "TESTS", to: "Discord", startFrame: 285, label: "/scv:report", color: COLORS.blue, phase: "report" },
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

const Subgraph: React.FC<{ cfg: typeof SUBGRAPHS[number]; frame: number }> = ({ cfg, frame }) => {
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
          left: 18,
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
  const opacity = interpolate(frame, [0, NODES_FADEIN_END], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const w = node.w ?? NODE_W;
  const fill = node.isKey ? COLORS.accent : node.fill || COLORS.bgPanel;
  const stroke = node.isKey ? COLORS.orange : COLORS.border;
  const textColor = node.isKey ? COLORS.accentText : COLORS.text;

  if (node.shape === "cylinder") {
    return (
      <div
        style={{
          position: "absolute",
          left: node.cx - w / 2,
          top: node.cy - NODE_H / 2,
          width: w,
          height: NODE_H,
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
        <div style={{ fontFamily: FONTS.mono, fontSize: 16, fontWeight: 700, color: textColor }}>
          {node.title}
        </div>
      </div>
    );
  }

  return (
    <div
      style={{
        position: "absolute",
        left: node.cx - w / 2,
        top: node.cy - NODE_H / 2,
        width: w,
        height: NODE_H,
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
          fontSize: node.title.length > 18 ? 13 : 16,
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
            fontSize: 12,
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
  const fromHalfH = NODE_H / 2;
  const toHalfW = (toN.w ?? NODE_W) / 2;
  const toHalfH = NODE_H / 2;

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
    { from: 30, to: 130, text: "1.  PLAN.md  →  External  (linked via refs:)" },
    { from: 130, to: 200, text: "2.  PLAN.md  →  Output  (/scv:work Step 9d)" },
    { from: 200, to: 270, text: "3.  Archive  →  TESTS  (/scv:regression — auto-runs every TESTS)" },
    { from: 270, to: 360, text: "4.  TESTS  →  Slack / Discord  (/scv:report)" },
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
        bottom: 22,
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
