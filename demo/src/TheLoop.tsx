import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { COLORS, FONTS, SIZES } from "./design";

export const LOOP_FPS = 30;
export const LOOP_DURATION_SECONDS = 12;

// Node positions on a wide virtual canvas. Camera pans across this canvas.
const CANVAS_W = 2400;
const CANVAS_H = 720;
const NODE_W = 280;
const NODE_H = 180;
const NODE_Y = 270;

type NodeId = "raw" | "promote" | "work" | "archive" | "regression";

const NODES: Record<
  NodeId,
  { x: number; title: string; subtitle: string; isKey?: boolean }
> = {
  raw: {
    x: 240,
    title: "scv/raw/",
    subtitle: "meeting notes\nspecs · screenshots",
  },
  promote: {
    x: 720,
    title: "scv/promote/<slug>/",
    subtitle: "PLAN.md + TESTS.md\n+ FEATURE_ARCH",
    isKey: true,
  },
  work: {
    x: 1200,
    title: "implement",
    subtitle: "+ run TESTS",
  },
  archive: {
    x: 1680,
    title: "scv/archive/",
    subtitle: "N plans accumulated",
  },
  regression: {
    x: 2160,
    title: "/scv:regression",
    subtitle: "runs every\narchived TESTS",
    isKey: true,
  },
};

// Each node's appear frame (cumulative timing across 12s @ 30fps = 360 frames).
const APPEAR: Record<NodeId, number> = {
  raw: 30,         // 1.0s
  promote: 75,     // 2.5s
  work: 135,       // 4.5s
  archive: 195,    // 6.5s
  regression: 240, // 8.0s
};

// Edge timing: each edge starts drawing as the destination node appears.
const EDGES: Array<{ from: NodeId; to: NodeId; startFrame: number; label: string }> = [
  { from: "raw", to: "promote", startFrame: 75, label: "/scv:promote" },
  { from: "promote", to: "work", startFrame: 135, label: "/scv:work" },
  { from: "work", to: "archive", startFrame: 195, label: "tests pass\n+ approval" },
  { from: "archive", to: "regression", startFrame: 240, label: "joins suite" },
];

// Camera keyframes: focus moves across the canvas, then zooms out.
// Each keyframe: [frame, focusX, scale]
const CAMERA: Array<[number, number, number]> = [
  [0, 240, 1.0],            // start at Raw
  [60, 240, 1.0],            // hold on Raw
  [105, 720, 1.0],           // pan to Promote
  [165, 1200, 1.0],          // pan to Work
  [225, 1680, 1.0],          // pan to Archive
  [270, 2160, 1.0],          // pan to Regression
  [300, 1200, 0.55],         // zoom out to whole view
  [360, 1200, 0.55],         // hold whole view
];

const interpolateCamera = (frame: number, idx: 1 | 2): number => {
  const frames = CAMERA.map((k) => k[0]);
  const values = CAMERA.map((k) => k[idx]);
  return interpolate(frame, frames, values, {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
};

const Node: React.FC<{
  id: NodeId;
  frame: number;
}> = ({ id, frame }) => {
  const node = NODES[id];
  const appear = APPEAR[id];
  const t = frame - appear;
  const opacity = interpolate(t, [0, 15], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const scale = spring({
    frame: t,
    fps: LOOP_FPS,
    config: { damping: 14, stiffness: 120, mass: 0.6 },
  });
  const finalScale = 0.6 + scale * 0.4;

  // Pulse on key nodes after appearing
  const pulse = node.isKey
    ? 1 + 0.04 * Math.sin((frame - appear) * 0.15)
    : 1;

  const fill = node.isKey ? COLORS.accent : COLORS.bgPanel;
  const stroke = node.isKey ? COLORS.orange : COLORS.border;
  const textColor = node.isKey ? COLORS.accentText : COLORS.text;

  return (
    <div
      style={{
        position: "absolute",
        left: node.x - NODE_W / 2,
        top: NODE_Y,
        width: NODE_W,
        height: NODE_H,
        opacity,
        transform: `scale(${finalScale * pulse})`,
        transformOrigin: "center center",
        backgroundColor: fill,
        border: `3px solid ${stroke}`,
        borderRadius: 14,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: 16,
        boxShadow: node.isKey
          ? `0 0 40px ${COLORS.accent}66`
          : "0 8px 24px rgba(0,0,0,0.5)",
      }}
    >
      <div
        style={{
          fontFamily: FONTS.mono,
          fontSize: 22,
          fontWeight: 700,
          color: textColor,
          textAlign: "center",
          marginBottom: 10,
        }}
      >
        {node.title}
      </div>
      <div
        style={{
          fontFamily: FONTS.sans,
          fontSize: 15,
          color: textColor,
          opacity: 0.85,
          textAlign: "center",
          whiteSpace: "pre-line",
          lineHeight: 1.4,
        }}
      >
        {node.subtitle}
      </div>
    </div>
  );
};

const Edge: React.FC<{
  from: NodeId;
  to: NodeId;
  startFrame: number;
  label: string;
  frame: number;
}> = ({ from, to, startFrame, label, frame }) => {
  const fromNode = NODES[from];
  const toNode = NODES[to];
  const x1 = fromNode.x + NODE_W / 2;
  const x2 = toNode.x - NODE_W / 2;
  const y = NODE_Y + NODE_H / 2;

  const t = frame - startFrame;
  const drawProgress = interpolate(t, [0, 25], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const labelOpacity = interpolate(t, [10, 30], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const currentX2 = x1 + (x2 - x1) * drawProgress;

  // Traveling pulse particle along the edge after it's drawn
  const showPulse = t > 25 && t < 90;
  const pulseProgress = ((t - 25) % 50) / 50;
  const pulseX = x1 + (x2 - x1) * pulseProgress;

  return (
    <>
      <svg
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: CANVAS_W,
          height: CANVAS_H,
          pointerEvents: "none",
        }}
      >
        <defs>
          <marker
            id={`arrow-${from}-${to}`}
            viewBox="0 0 10 10"
            refX="9"
            refY="5"
            markerWidth="8"
            markerHeight="8"
            orient="auto"
          >
            <path d="M 0 0 L 10 5 L 0 10 z" fill={COLORS.text} />
          </marker>
        </defs>
        <line
          x1={x1}
          y1={y}
          x2={currentX2}
          y2={y}
          stroke={COLORS.text}
          strokeWidth={3}
          markerEnd={drawProgress > 0.95 ? `url(#arrow-${from}-${to})` : undefined}
        />
        {showPulse && (
          <circle
            cx={pulseX}
            cy={y}
            r={6}
            fill={COLORS.accent}
            opacity={1 - Math.abs(pulseProgress - 0.5) * 2}
          />
        )}
      </svg>
      {/* Edge label */}
      <div
        style={{
          position: "absolute",
          left: (x1 + x2) / 2 - 90,
          top: y - 50,
          width: 180,
          textAlign: "center",
          fontFamily: FONTS.mono,
          fontSize: 14,
          color: COLORS.text,
          opacity: labelOpacity,
          backgroundColor: COLORS.bgPanel,
          padding: "4px 8px",
          borderRadius: 6,
          whiteSpace: "pre-line",
          lineHeight: 1.3,
        }}
      >
        {label}
      </div>
    </>
  );
};

// The dashed feedback edge: Regression -.->|safety net| Promote
// Curves up and back, only revealed once camera zooms out.
const SafetyNetEdge: React.FC<{ frame: number }> = ({ frame }) => {
  const t = frame - 280;
  const opacity = interpolate(t, [0, 30], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const drawProgress = interpolate(t, [10, 50], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const startX = NODES.regression.x;
  const startY = NODE_Y;
  const endX = NODES.promote.x;
  const endY = NODE_Y;
  const midY = NODE_Y - 220;

  const path = `M ${startX} ${startY} Q ${(startX + endX) / 2} ${midY}, ${endX} ${endY}`;
  const pathLength = 2200;
  const dashOffset = pathLength * (1 - drawProgress);

  return (
    <svg
      style={{
        position: "absolute",
        left: 0,
        top: 0,
        width: CANVAS_W,
        height: CANVAS_H,
        pointerEvents: "none",
        opacity,
      }}
    >
      <defs>
        <marker
          id="safety-arrow"
          viewBox="0 0 10 10"
          refX="9"
          refY="5"
          markerWidth="10"
          markerHeight="10"
          orient="auto"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill={COLORS.accent} />
        </marker>
      </defs>
      <path
        d={path}
        fill="none"
        stroke={COLORS.accent}
        strokeWidth={4}
        strokeDasharray="14 10"
        strokeDashoffset={dashOffset}
        markerEnd={drawProgress > 0.95 ? "url(#safety-arrow)" : undefined}
      />
      <text
        x={(startX + endX) / 2}
        y={midY - 20}
        textAnchor="middle"
        fontFamily={FONTS.mono}
        fontSize={28}
        fill={COLORS.accent}
        fontWeight={700}
      >
        safety net for the next change
      </text>
    </svg>
  );
};

const TitleOverlay: React.FC<{ frame: number }> = ({ frame }) => {
  const introOpacity = interpolate(frame, [0, 15, 45, 60], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const outroOpacity = interpolate(frame, [300, 320, 360], [0, 1, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <>
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          opacity: introOpacity,
          pointerEvents: "none",
        }}
      >
        <div
          style={{
            fontFamily: FONTS.sans,
            fontSize: SIZES.hero,
            fontWeight: 800,
            color: COLORS.text,
            letterSpacing: -1,
          }}
        >
          The Loop
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 60,
          textAlign: "center",
          opacity: outroOpacity,
          pointerEvents: "none",
        }}
      >
        <div
          style={{
            fontFamily: FONTS.sans,
            fontSize: SIZES.subtitle,
            color: COLORS.textMuted,
          }}
        >
          Every archived plan's tests join an{" "}
          <span style={{ color: COLORS.accent, fontWeight: 700 }}>
            accumulating regression suite
          </span>
          .
        </div>
      </div>
    </>
  );
};

export const TheLoop: React.FC = () => {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();

  const focusX = interpolateCamera(frame, 1);
  const scale = interpolateCamera(frame, 2);

  // Translate so that focusX (in canvas coords) lands at the screen center.
  const screenCenterX = width / 2;
  const screenCenterY = height / 2;
  const translateX = screenCenterX - focusX * scale;
  const translateY = screenCenterY - (CANVAS_H / 2) * scale;

  return (
    <AbsoluteFill style={{ backgroundColor: COLORS.bg, overflow: "hidden" }}>
      {/* Camera-transformed canvas */}
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: CANVAS_W,
          height: CANVAS_H,
          transform: `translate(${translateX}px, ${translateY}px) scale(${scale})`,
          transformOrigin: "0 0",
        }}
      >
        {/* Edges first (behind nodes) */}
        {EDGES.map((e) => (
          <Edge
            key={`${e.from}-${e.to}`}
            from={e.from}
            to={e.to}
            startFrame={e.startFrame}
            label={e.label}
            frame={frame}
          />
        ))}
        <SafetyNetEdge frame={frame} />
        {/* Nodes */}
        {(Object.keys(NODES) as NodeId[]).map((id) => (
          <Node key={id} id={id} frame={frame} />
        ))}
      </div>
      {/* Overlays (screen-space, not camera-transformed) */}
      <TitleOverlay frame={frame} />
    </AbsoluteFill>
  );
};
