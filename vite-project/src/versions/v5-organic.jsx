import { useState } from "react";
import { STEPS, PHASES, PHASE_META, getPhaseSteps } from "../data/workflow-data";

// --- Organic / Earth / River palette ---
const PALETTE = {
  bg: "#F5EFE0",
  text: "#3D3229",
  textSecondary: "#8C7B6B",
  cardBg: "#FFFDF7",
  river: "#7BA7C2",
  phase: {
    plan: "#4A7C59",
    execute: "#C17C3A",
    learn: "#5B7FA5",
  },
};

const DEBT_DISPLAY = {
  github: { icon: "●", text: "Lives in GitHub — zero debt", color: PALETTE.phase.plan },
  temporary: { icon: "●", text: "Temporary — delete after ship", color: "#C17C3A" },
  compound: { icon: "🌿", text: "Compounds — future work consults this", color: PALETTE.phase.plan },
  none: null,
};

const PHASE_LABELS = {
  plan: "Planning",
  execute: "Executing",
  learn: "Learning",
};

// --- River path generation ---
// Each step occupies ~140px vertical space. The river gently S-curves down the center.
const STEP_HEIGHT = 140;
const RIVER_CENTER = 400; // center of 800px container
const RIVER_SWAY = 40; // how far left/right the river meanders

function buildRiverPath(stepCount) {
  const totalHeight = stepCount * STEP_HEIGHT + 120; // extra padding top/bottom
  const points = [];
  const startY = 30;

  points.push(`M ${RIVER_CENTER} ${startY}`);

  for (let i = 0; i < stepCount; i++) {
    const y1 = startY + i * STEP_HEIGHT + STEP_HEIGHT * 0.33;
    const y2 = startY + i * STEP_HEIGHT + STEP_HEIGHT * 0.66;
    const yEnd = startY + (i + 1) * STEP_HEIGHT;
    // Alternate sway direction
    const sway = i % 2 === 0 ? RIVER_SWAY : -RIVER_SWAY;
    points.push(`C ${RIVER_CENTER + sway} ${y1}, ${RIVER_CENTER - sway} ${y2}, ${RIVER_CENTER} ${yEnd}`);
  }

  return { d: points.join(" "), totalHeight };
}

// Find which steps are at phase boundaries
function getPhaseTransitions() {
  const transitions = [];
  for (let i = 1; i < STEPS.length; i++) {
    if (STEPS[i].phase !== STEPS[i - 1].phase) {
      transitions.push({ index: i, phase: STEPS[i].phase });
    }
  }
  return transitions;
}

// Compute the Y position on the river for a given step index
function getStepY(index) {
  return 30 + index * STEP_HEIGHT + STEP_HEIGHT / 2;
}

// --- Components ---

function PhaseTransitionPill({ phase, y }) {
  const color = PALETTE.phase[phase];
  return (
    <g>
      {/* Wider river section */}
      <ellipse
        cx={RIVER_CENTER}
        cy={y - 10}
        rx={18}
        ry={22}
        fill={PALETTE.river}
        opacity={0.18}
      />
      {/* Pill background */}
      <foreignObject x={RIVER_CENTER - 50} y={y - 26} width={100} height={32}>
        <div
          style={{
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            height: "100%",
          }}
        >
          <span
            style={{
              display: "inline-block",
              background: "#FFFDF7",
              border: `2px solid ${color}`,
              color: color,
              borderRadius: 20,
              padding: "4px 16px",
              fontSize: 12,
              fontFamily: "Georgia, 'Times New Roman', serif",
              fontStyle: "italic",
              fontWeight: 600,
              letterSpacing: "0.04em",
              whiteSpace: "nowrap",
            }}
          >
            {PHASE_LABELS[phase]}
          </span>
        </div>
      </foreignObject>
    </g>
  );
}

function TributaryLine({ stepIndex, side }) {
  const y = getStepY(stepIndex);
  // Tributary connects from card edge toward the river center
  if (side === "left") {
    // Card is on the left, tributary goes from right edge of card area to river
    const x1 = RIVER_CENTER - 30 - 320 + 320; // right edge of left card area ≈ center - 30
    const x2 = RIVER_CENTER;
    return (
      <line
        x1={x1 - 4}
        y1={y}
        x2={x2}
        y2={y}
        stroke={PALETTE.river}
        strokeWidth={2}
        strokeDasharray="4 3"
        opacity={0.5}
      />
    );
  } else {
    const x1 = RIVER_CENTER;
    const x2 = RIVER_CENTER + 30 + 4;
    return (
      <line
        x1={x1}
        y1={y}
        x2={x2}
        y2={y}
        stroke={PALETTE.river}
        strokeWidth={2}
        strokeDasharray="4 3"
        opacity={0.5}
      />
    );
  }
}

function StepCard({ step, index, isOpen, onToggle }) {
  const phaseColor = PALETTE.phase[step.phase];
  const isLeft = index % 2 === 0;
  const debt = DEBT_DISPLAY[step.debtType];

  return (
    <div
      style={{
        display: "flex",
        justifyContent: isLeft ? "flex-start" : "flex-end",
        width: "100%",
        paddingLeft: isLeft ? 0 : 0,
        paddingRight: isLeft ? 0 : 0,
        boxSizing: "border-box",
      }}
    >
      <div
        onClick={onToggle}
        style={{
          width: 320,
          background: PALETTE.cardBg,
          borderRadius: 14,
          borderLeft: `4px solid ${phaseColor}`,
          boxShadow: "0 2px 12px rgba(61, 50, 41, 0.08)",
          padding: 20,
          cursor: "pointer",
          marginLeft: isLeft ? 0 : 30,
          marginRight: isLeft ? 30 : 0,
          transition: "box-shadow 0.2s ease, transform 0.2s ease",
          position: "relative",
        }}
        onMouseEnter={(e) => {
          e.currentTarget.style.boxShadow = "0 4px 20px rgba(61, 50, 41, 0.14)";
          e.currentTarget.style.transform = "translateY(-1px)";
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.boxShadow = "0 2px 12px rgba(61, 50, 41, 0.08)";
          e.currentTarget.style.transform = "translateY(0)";
        }}
      >
        {/* Header row */}
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 6 }}>
          <span
            style={{
              fontFamily: "Georgia, 'Times New Roman', serif",
              fontWeight: 700,
              fontSize: 18,
              color: PALETTE.text,
            }}
          >
            {step.label}
          </span>
          <span
            style={{
              display: "inline-block",
              background: phaseColor,
              color: "#fff",
              borderRadius: 10,
              padding: "2px 10px",
              fontSize: 11,
              fontFamily: "system-ui, -apple-system, sans-serif",
              fontWeight: 600,
              letterSpacing: "0.06em",
            }}
          >
            {step.mode === "hitl" ? "HITL" : "AFK"}
          </span>
        </div>

        {/* Time */}
        <div
          style={{
            fontFamily: "system-ui, -apple-system, sans-serif",
            fontSize: 12,
            color: PALETTE.textSecondary,
            marginBottom: 8,
          }}
        >
          {step.time}
        </div>

        {/* Summary */}
        <div
          style={{
            fontFamily: "system-ui, -apple-system, sans-serif",
            fontSize: 14,
            lineHeight: 1.7,
            color: PALETTE.text,
          }}
        >
          {step.summary}
        </div>

        {/* Expanded content — bloom effect */}
        <div
          style={{
            maxHeight: isOpen ? 500 : 0,
            opacity: isOpen ? 1 : 0,
            overflow: "hidden",
            transition: "max-height 300ms ease, opacity 300ms ease",
          }}
        >
          <div style={{ paddingTop: 14, borderTop: `1px solid ${phaseColor}22`, marginTop: 14 }}>
            {/* Source attribution */}
            <div
              style={{
                fontFamily: "Georgia, 'Times New Roman', serif",
                fontStyle: "italic",
                fontSize: 12,
                color: PALETTE.textSecondary,
                marginBottom: 10,
              }}
            >
              Source: {step.source}
            </div>

            {/* Detail */}
            <div
              style={{
                fontFamily: "system-ui, -apple-system, sans-serif",
                fontSize: 14,
                lineHeight: 1.7,
                color: PALETTE.text,
                marginBottom: 14,
              }}
            >
              {step.detail}
            </div>

            {/* Consumes */}
            {step.consumes && (
              <div style={{ marginBottom: 10 }}>
                <div
                  style={{
                    fontFamily: "system-ui, -apple-system, sans-serif",
                    fontSize: 11,
                    textTransform: "uppercase",
                    letterSpacing: "0.12em",
                    color: PALETTE.textSecondary,
                    marginBottom: 4,
                  }}
                >
                  <span style={{ marginRight: 6 }}>↑</span>Receives from upstream
                </div>
                <div
                  style={{
                    fontFamily: "system-ui, -apple-system, sans-serif",
                    fontSize: 13,
                    lineHeight: 1.6,
                    color: PALETTE.text,
                    paddingLeft: 18,
                  }}
                >
                  {step.consumes}
                </div>
              </div>
            )}

            {/* Produces */}
            {step.produces && (
              <div style={{ marginBottom: 10 }}>
                <div
                  style={{
                    fontFamily: "system-ui, -apple-system, sans-serif",
                    fontSize: 11,
                    textTransform: "uppercase",
                    letterSpacing: "0.12em",
                    color: PALETTE.textSecondary,
                    marginBottom: 4,
                  }}
                >
                  <span style={{ marginRight: 6 }}>↓</span>Sends downstream
                </div>
                <div
                  style={{
                    fontFamily: "system-ui, -apple-system, sans-serif",
                    fontSize: 13,
                    lineHeight: 1.6,
                    color: PALETTE.text,
                    paddingLeft: 18,
                  }}
                >
                  {step.produces}
                </div>
              </div>
            )}

            {/* State location */}
            <div style={{ marginBottom: 10 }}>
              <div
                style={{
                  fontFamily: "system-ui, -apple-system, sans-serif",
                  fontSize: 11,
                  textTransform: "uppercase",
                  letterSpacing: "0.12em",
                  color: PALETTE.textSecondary,
                  marginBottom: 4,
                }}
              >
                State lives in
              </div>
              <div
                style={{
                  fontFamily: "system-ui, -apple-system, sans-serif",
                  fontSize: 13,
                  lineHeight: 1.6,
                  color: PALETTE.text,
                  paddingLeft: 18,
                }}
              >
                {step.stateLocation}
              </div>
            </div>

            {/* Debt callout */}
            {debt && (
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  marginTop: 12,
                  padding: "8px 12px",
                  background: `${phaseColor}08`,
                  borderRadius: 8,
                  border: `1px solid ${phaseColor}18`,
                }}
              >
                <span style={{ fontSize: 14 }}>{debt.icon}</span>
                <span
                  style={{
                    fontFamily: "system-ui, -apple-system, sans-serif",
                    fontSize: 12,
                    color: PALETTE.textSecondary,
                    fontStyle: "italic",
                  }}
                >
                  {debt.text}
                </span>
              </div>
            )}
          </div>
        </div>

        {/* Expand indicator */}
        <div
          style={{
            textAlign: "center",
            marginTop: 8,
            fontSize: 10,
            color: PALETTE.textSecondary,
            opacity: 0.6,
          }}
        >
          {isOpen ? "collapse" : "tap to bloom"}
        </div>
      </div>
    </div>
  );
}

// --- Main component ---

export default function V5Organic() {
  const [expanded, setExpanded] = useState(null);

  const toggle = (idx) => setExpanded((prev) => (prev === idx ? null : idx));

  const { d: riverPath, totalHeight } = buildRiverPath(STEPS.length);
  const phaseTransitions = getPhaseTransitions();

  return (
    <div
      style={{
        background: PALETTE.bg,
        minHeight: "100vh",
        fontFamily: "system-ui, -apple-system, sans-serif",
      }}
    >
      <div
        style={{
          maxWidth: 800,
          margin: "0 auto",
          padding: "40px 20px",
          position: "relative",
        }}
      >
        {/* --- Header --- */}
        <div style={{ textAlign: "center", marginBottom: 50, position: "relative", zIndex: 2 }}>
          <h1
            style={{
              fontFamily: "Georgia, 'Times New Roman', serif",
              fontSize: 36,
              fontWeight: 400,
              color: PALETTE.text,
              margin: 0,
              letterSpacing: "-0.01em",
            }}
          >
            The Hybrid Workflow
          </h1>
          <p
            style={{
              fontFamily: "Georgia, 'Times New Roman', serif",
              fontStyle: "italic",
              fontSize: 16,
              color: PALETTE.textSecondary,
              margin: "8px 0 0",
              lineHeight: 1.6,
            }}
          >
            A river of decisions flowing from idea to shipped feature
          </p>

          {/* Phase legend */}
          <div
            style={{
              display: "flex",
              justifyContent: "center",
              gap: 24,
              marginTop: 20,
            }}
          >
            {PHASES.map((phase) => (
              <div key={phase} style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <span
                  style={{
                    width: 10,
                    height: 10,
                    borderRadius: "50%",
                    background: PALETTE.phase[phase],
                    display: "inline-block",
                  }}
                />
                <span
                  style={{
                    fontFamily: "system-ui, -apple-system, sans-serif",
                    fontSize: 12,
                    color: PALETTE.textSecondary,
                    textTransform: "uppercase",
                    letterSpacing: "0.1em",
                  }}
                >
                  {phase}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* --- River + Steps container --- */}
        <div
          style={{
            position: "relative",
            minHeight: totalHeight,
          }}
        >
          {/* SVG River */}
          <svg
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              height: totalHeight,
              pointerEvents: "none",
              zIndex: 0,
            }}
            viewBox={`0 0 800 ${totalHeight}`}
            preserveAspectRatio="xMidYMin meet"
          >
            <defs>
              <filter id="river-glow">
                <feGaussianBlur stdDeviation="3" result="blur" />
                <feMerge>
                  <feMergeNode in="blur" />
                  <feMergeNode in="SourceGraphic" />
                </feMerge>
              </filter>
            </defs>

            {/* River shadow */}
            <path
              d={riverPath}
              fill="none"
              stroke={PALETTE.river}
              strokeWidth={10}
              strokeLinecap="round"
              opacity={0.12}
            />

            {/* River main stroke */}
            <path
              d={riverPath}
              fill="none"
              stroke={PALETTE.river}
              strokeWidth={6}
              strokeLinecap="round"
              filter="url(#river-glow)"
              opacity={0.6}
            />

            {/* River highlight (thin bright center line) */}
            <path
              d={riverPath}
              fill="none"
              stroke={PALETTE.river}
              strokeWidth={2}
              strokeLinecap="round"
              opacity={0.9}
            />

            {/* Tributary lines from each step to the river */}
            {STEPS.map((step, i) => (
              <TributaryLine
                key={step.id}
                stepIndex={i}
                side={i % 2 === 0 ? "left" : "right"}
              />
            ))}

            {/* Phase transition markers */}
            {phaseTransitions.map((t) => (
              <PhaseTransitionPill
                key={t.phase}
                phase={t.phase}
                y={30 + t.index * STEP_HEIGHT - 10}
              />
            ))}

            {/* Feedback loop — dashed arc from bottom back to top */}
            <path
              d={`M ${RIVER_CENTER + 60} ${totalHeight - 80} C ${RIVER_CENTER + 200} ${totalHeight - 200}, ${RIVER_CENTER + 200} 200, ${RIVER_CENTER + 60} 80`}
              fill="none"
              stroke={PALETTE.phase.learn}
              strokeWidth={2}
              strokeDasharray="8 5"
              opacity={0.4}
              strokeLinecap="round"
            />
            {/* Arrow at top of feedback arc */}
            <polygon
              points={`${RIVER_CENTER + 55} 74, ${RIVER_CENTER + 60} 80, ${RIVER_CENTER + 66} 76`}
              fill={PALETTE.phase.learn}
              opacity={0.5}
            />
            {/* Feedback label */}
            <foreignObject x={RIVER_CENTER + 100} y={totalHeight / 2 - 40} width={120} height={80}>
              <div
                style={{
                  fontFamily: "Georgia, 'Times New Roman', serif",
                  fontStyle: "italic",
                  fontSize: 12,
                  color: PALETTE.phase.learn,
                  textAlign: "center",
                  lineHeight: 1.5,
                  opacity: 0.7,
                }}
              >
                Each cycle enriches the next
              </div>
            </foreignObject>
          </svg>

          {/* Step cards */}
          <div
            style={{
              position: "relative",
              zIndex: 1,
              display: "flex",
              flexDirection: "column",
              gap: 0,
            }}
          >
            {/* Initial phase pill for "plan" */}
            <div
              style={{
                display: "flex",
                justifyContent: "center",
                marginBottom: 16,
                height: 10,
              }}
            >
              {/* Handled in SVG; this spacer aligns the first card */}
            </div>

            {STEPS.map((step, i) => {
              // Insert phase separator before the step if phase changes
              const showPhaseSeparator =
                i > 0 && STEPS[i].phase !== STEPS[i - 1].phase;

              return (
                <div key={step.id}>
                  {showPhaseSeparator && (
                    <div style={{ height: STEP_HEIGHT * 0.15 }} />
                  )}
                  <div
                    style={{
                      height: STEP_HEIGHT,
                      display: "flex",
                      alignItems: "center",
                    }}
                  >
                    <StepCard
                      step={step}
                      index={i}
                      isOpen={expanded === i}
                      onToggle={() => toggle(i)}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* --- Footer --- */}
        <div
          style={{
            textAlign: "center",
            marginTop: 60,
            paddingTop: 30,
            borderTop: `1px solid ${PALETTE.textSecondary}22`,
            position: "relative",
            zIndex: 2,
          }}
        >
          <p
            style={{
              fontFamily: "Georgia, 'Times New Roman', serif",
              fontStyle: "italic",
              fontSize: 16,
              color: PALETTE.textSecondary,
              lineHeight: 1.8,
              margin: 0,
            }}
          >
            Knowledge flows downstream. Lessons flow upstream.
          </p>
        </div>
      </div>
    </div>
  );
}
