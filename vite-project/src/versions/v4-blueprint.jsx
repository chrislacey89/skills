import { useState, useEffect } from "react";
import { STEPS, PHASES, PHASE_META, getPhaseSteps } from "../data/workflow-data";

// ── Color Palette ──────────────────────────────────────────────
const C = {
  bg: "#1B2F5E",
  line: "#E8E4D8",
  secondary: "#8B9DC3",
  grid: "#253D72",
  plan: "#FFD166",
  execute: "#FF8C42",
  learn: "#6BCB77",
};

const PHASE_COLORS = { plan: C.plan, execute: C.execute, learn: C.learn };

// ── Grid background via layered repeating-linear-gradient ──────
const gridBg = [
  // minor vertical
  `repeating-linear-gradient(90deg, ${C.grid}66 0px, ${C.grid}66 1px, transparent 1px, transparent 20px)`,
  // minor horizontal
  `repeating-linear-gradient(0deg, ${C.grid}66 0px, ${C.grid}66 1px, transparent 1px, transparent 20px)`,
  // major vertical
  `repeating-linear-gradient(90deg, ${C.grid}cc 0px, ${C.grid}cc 1px, transparent 1px, transparent 100px)`,
  // major horizontal
  `repeating-linear-gradient(0deg, ${C.grid}cc 0px, ${C.grid}cc 1px, transparent 1px, transparent 100px)`,
].join(", ");

// ── Shared text styles ──────────────────────────────────────────
const mono = "'Courier New', monospace";
const caps = { textTransform: "uppercase", letterSpacing: "0.15em" };

// ── Arrowhead SVG connector ─────────────────────────────────────
function Connector({ color, isMobile }) {
  if (isMobile) {
    return (
      <svg width="2" height="28" style={{ display: "block", margin: "0 auto" }}>
        <line x1="1" y1="0" x2="1" y2="20" stroke={color} strokeWidth="1" />
        <polygon points="1,28 -3,20 5,20" fill={color} />
      </svg>
    );
  }
  return (
    <svg width="32" height="2" style={{ display: "block", flexShrink: 0 }}>
      <line x1="0" y1="1" x2="24" y2="1" stroke={color} strokeWidth="1" />
      <polygon points="32,1 24,-3 24,5" fill={color} />
    </svg>
  );
}

// ── Dimension annotation (architectural measurement) ────────────
function DimensionAnnotation({ time, color }) {
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 4, marginTop: 6 }}>
      <svg width="6" height="12" style={{ flexShrink: 0 }}>
        <line x1="3" y1="0" x2="3" y2="12" stroke={color} strokeWidth="1" />
        <line x1="0" y1="1" x2="6" y2="1" stroke={color} strokeWidth="1" />
        <line x1="0" y1="11" x2="6" y2="11" stroke={color} strokeWidth="1" />
      </svg>
      <span style={{ fontFamily: mono, fontSize: 10, color, ...caps }}>
        {time}
      </span>
      <svg width="6" height="12" style={{ flexShrink: 0 }}>
        <line x1="3" y1="0" x2="3" y2="12" stroke={color} strokeWidth="1" />
        <line x1="0" y1="1" x2="6" y2="1" stroke={color} strokeWidth="1" />
        <line x1="0" y1="11" x2="6" y2="11" stroke={color} strokeWidth="1" />
      </svg>
    </div>
  );
}

// ── Leader Line Callout ─────────────────────────────────────────
function Callout({ step, phaseColor }) {
  return (
    <div style={{ position: "relative", width: 300, margin: "0 auto" }}>
      {/* Leader line */}
      <svg width="300" height="24" style={{ display: "block" }}>
        <line x1="150" y1="0" x2="40" y2="24" stroke={C.secondary} strokeWidth="1" strokeDasharray="4 3" />
      </svg>
      {/* Callout panel */}
      <div style={{
        border: `1px solid ${C.line}`,
        padding: "12px 14px",
        fontFamily: mono,
        fontSize: 12,
        color: C.line,
        background: "transparent",
      }}>
        {/* Source */}
        <div style={{ color: C.secondary, fontSize: 10, marginBottom: 8, ...caps }}>
          Source: {step.source}
        </div>
        {/* Detail */}
        <p style={{ margin: "0 0 10px", lineHeight: 1.55, color: C.line, fontSize: 12 }}>
          {step.detail}
        </p>
        {/* Consumes */}
        <div style={{ display: "flex", alignItems: "flex-start", gap: 6, marginBottom: 8 }}>
          <svg width="14" height="14" viewBox="0 0 14 14" style={{ flexShrink: 0, marginTop: 1 }}>
            <line x1="12" y1="7" x2="2" y2="7" stroke={phaseColor} strokeWidth="1.5" />
            <polyline points="6,3 2,7 6,11" fill="none" stroke={phaseColor} strokeWidth="1.5" />
          </svg>
          <div>
            <span style={{ fontSize: 10, color: C.secondary, ...caps }}>Consumes: </span>
            <span style={{ color: C.line, fontSize: 11 }}>{step.consumes}</span>
          </div>
        </div>
        {/* Produces */}
        <div style={{ display: "flex", alignItems: "flex-start", gap: 6, marginBottom: 8 }}>
          <svg width="14" height="14" viewBox="0 0 14 14" style={{ flexShrink: 0, marginTop: 1 }}>
            <line x1="2" y1="7" x2="12" y2="7" stroke={phaseColor} strokeWidth="1.5" />
            <polyline points="8,3 12,7 8,11" fill="none" stroke={phaseColor} strokeWidth="1.5" />
          </svg>
          <div>
            <span style={{ fontSize: 10, color: C.secondary, ...caps }}>Produces: </span>
            <span style={{ color: C.line, fontSize: 11 }}>{step.produces}</span>
          </div>
        </div>
        {/* Debt type annotation */}
        {step.debtType !== "none" && (
          <div style={{ fontSize: 10, color: C.secondary, fontStyle: "italic", marginTop: 4 }}>
            [{step.debtType === "github" ? "STATE: GITHUB" : step.debtType === "temporary" ? "STATE: TEMPORARY" : step.debtType === "compound" ? "STATE: COMPOUND" : step.debtType.toUpperCase()}]
          </div>
        )}
      </div>
    </div>
  );
}

// ── Step Box ────────────────────────────────────────────────────
function StepBox({ step, index, expanded, toggle, phaseColor, isMobile }) {
  const isExpanded = expanded === index;
  const globalIndex = STEPS.findIndex((s) => s.id === step.id);

  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
      {/* The box */}
      <div
        onClick={() => toggle(globalIndex)}
        style={{
          width: isMobile ? "100%" : 180,
          minHeight: 80,
          border: isExpanded ? `2px solid ${phaseColor}` : `1px solid ${C.line}`,
          boxShadow: isExpanded ? `0 0 12px ${phaseColor}44, inset 0 0 8px ${phaseColor}11` : "none",
          background: "transparent",
          padding: "10px 12px",
          fontFamily: mono,
          cursor: "pointer",
          position: "relative",
          boxSizing: "border-box",
          transition: "border-color 0.2s, box-shadow 0.2s",
        }}
      >
        {/* Mode badge */}
        <span style={{
          position: "absolute",
          top: 4,
          right: 6,
          fontSize: 9,
          color: C.secondary,
          ...caps,
        }}>
          {step.mode.toUpperCase()}
        </span>

        {/* Step label */}
        <div style={{
          fontSize: 15,
          fontWeight: 700,
          color: C.line,
          ...caps,
          marginBottom: 6,
          paddingRight: 32,
        }}>
          {step.label}
        </div>

        {/* Summary */}
        <div style={{ fontSize: 12, color: C.secondary, lineHeight: 1.4 }}>
          {step.summary}
        </div>
      </div>

      {/* Dimension annotation below box */}
      <DimensionAnnotation time={step.time} color={C.secondary} />

      {/* Expanded callout */}
      {isExpanded && (
        <div style={{ marginTop: 8, width: isMobile ? "100%" : "auto" }}>
          <Callout step={step} phaseColor={phaseColor} />
        </div>
      )}
    </div>
  );
}

// ── Swim Lane ───────────────────────────────────────────────────
function SwimLane({ phase, expanded, toggle, isMobile, isLast }) {
  const steps = getPhaseSteps(phase);
  const phaseColor = PHASE_COLORS[phase];
  const phaseLabel = PHASE_META[phase].label;

  return (
    <div>
      <div style={{
        display: "flex",
        position: "relative",
        minHeight: isMobile ? "auto" : 160,
        paddingLeft: isMobile ? 0 : 52,
        paddingTop: 16,
        paddingBottom: 24,
      }}>
        {/* Rotated phase label on left edge (desktop) */}
        {!isMobile && (
          <div style={{
            position: "absolute",
            left: 0,
            top: 0,
            bottom: 0,
            width: 40,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}>
            <span style={{
              writingMode: "vertical-rl",
              transform: "rotate(180deg)",
              fontFamily: mono,
              fontSize: 18,
              fontWeight: 700,
              color: phaseColor,
              ...caps,
              letterSpacing: "0.25em",
            }}>
              {phaseLabel}
            </span>
          </div>
        )}

        {/* Phase header (mobile) */}
        {isMobile && (
          <div style={{
            fontFamily: mono,
            fontSize: 18,
            fontWeight: 700,
            color: phaseColor,
            ...caps,
            letterSpacing: "0.25em",
            marginBottom: 16,
            paddingLeft: 4,
            borderLeft: `3px solid ${phaseColor}`,
            paddingTop: 2,
            paddingBottom: 2,
            width: "100%",
          }}>
            {phaseLabel}
          </div>
        )}

        {/* Steps row / column */}
        {!isMobile && (
          <div style={{
            display: "flex",
            alignItems: "flex-start",
            gap: 0,
            flexWrap: "nowrap",
          }}>
            {steps.map((step, i) => {
              const globalIndex = STEPS.findIndex((s) => s.id === step.id);
              return (
                <div key={step.id} style={{ display: "flex", alignItems: "flex-start" }}>
                  <StepBox
                    step={step}
                    index={globalIndex}
                    expanded={expanded}
                    toggle={toggle}
                    phaseColor={phaseColor}
                    isMobile={false}
                  />
                  {i < steps.length - 1 && (
                    <div style={{ display: "flex", alignItems: "center", height: 80, paddingTop: 10 }}>
                      <Connector color={phaseColor} isMobile={false} />
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Mobile steps column */}
      {isMobile && (
        <div style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 0,
          padding: "0 8px",
        }}>
          {steps.map((step, i) => {
            const globalIndex = STEPS.findIndex((s) => s.id === step.id);
            return (
              <div key={step.id} style={{ width: "100%" }}>
                <StepBox
                  step={step}
                  index={globalIndex}
                  expanded={expanded}
                  toggle={toggle}
                  phaseColor={phaseColor}
                  isMobile={true}
                />
                {i < steps.length - 1 && (
                  <div style={{ display: "flex", justifyContent: "center", padding: "4px 0" }}>
                    <Connector color={phaseColor} isMobile={true} />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Dashed lane separator */}
      {!isLast && (
        <div style={{
          borderBottom: `1px dashed ${C.secondary}44`,
          margin: isMobile ? "20px 0" : "0",
        }} />
      )}
    </div>
  );
}

// ── Title Block ─────────────────────────────────────────────────
function TitleBlock() {
  return (
    <div style={{
      display: "flex",
      justifyContent: "flex-end",
      padding: "32px 0 12px",
    }}>
      <div style={{
        border: `1px solid ${C.line}`,
        outline: `1px solid ${C.line}`,
        outlineOffset: "3px",
        padding: "10px 16px",
        fontFamily: mono,
        fontSize: 10,
        color: C.line,
        lineHeight: 1.8,
        ...caps,
        whiteSpace: "pre",
      }}>
{`Project:  The Hybrid Workflow
Drawn:    Claude
Date:     2026-04-06
Scale:    NTS
Sheet:    1 of 1
Rev:      1.0`}
      </div>
    </div>
  );
}

// ── Main Component ──────────────────────────────────────────────
export default function V4Blueprint() {
  const [expanded, setExpanded] = useState(null);
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const check = () => setIsMobile(window.innerWidth < 768);
    check();
    window.addEventListener("resize", check);
    return () => window.removeEventListener("resize", check);
  }, []);

  const toggle = (idx) => setExpanded((prev) => (prev === idx ? null : idx));

  return (
    <div style={{
      background: C.bg,
      backgroundImage: gridBg,
      minHeight: "100vh",
      fontFamily: mono,
      color: C.line,
    }}>
      <div style={{
        maxWidth: 960,
        margin: "0 auto",
        padding: isMobile ? "24px 12px 40px" : "40px 32px 48px",
        minHeight: "100vh",
        position: "relative",
      }}>
        {/* Drawing title (top-left, like a real blueprint annotation) */}
        <div style={{ marginBottom: 32 }}>
          <div style={{
            fontSize: 10,
            color: C.secondary,
            ...caps,
            marginBottom: 4,
          }}>
            Workflow Architecture / Feature Delivery Pipeline
          </div>
          <h1 style={{
            fontFamily: mono,
            fontSize: isMobile ? 20 : 26,
            fontWeight: 700,
            color: C.line,
            ...caps,
            margin: 0,
            letterSpacing: "0.2em",
          }}>
            The Hybrid Workflow
          </h1>
          <div style={{
            width: 120,
            height: 1,
            background: C.line,
            marginTop: 8,
            opacity: 0.5,
          }} />
        </div>

        {/* Legend */}
        <div style={{
          display: "flex",
          flexWrap: "wrap",
          gap: isMobile ? 12 : 24,
          marginBottom: 28,
          fontSize: 10,
          ...caps,
        }}>
          {PHASES.map((phase) => (
            <span key={phase} style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <span style={{
                width: 20,
                height: 2,
                background: PHASE_COLORS[phase],
                display: "inline-block",
              }} />
              <span style={{ color: PHASE_COLORS[phase] }}>{PHASE_META[phase].label}</span>
            </span>
          ))}
          <span style={{ display: "flex", alignItems: "center", gap: 6, color: C.secondary }}>
            <span style={{
              width: 12,
              height: 12,
              border: `1px solid ${C.line}`,
              display: "inline-block",
            }} />
            <span>HITL / AFK Step</span>
          </span>
        </div>

        {/* Swim lanes */}
        {PHASES.map((phase, i) => (
          <SwimLane
            key={phase}
            phase={phase}
            expanded={expanded}
            toggle={toggle}
            isMobile={isMobile}
            isLast={i === PHASES.length - 1}
          />
        ))}

        {/* Title block */}
        <TitleBlock />

        {/* Footer */}
        <div style={{
          textAlign: "center",
          fontFamily: mono,
          fontSize: 10,
          color: C.secondary,
          ...caps,
          marginTop: 24,
          paddingTop: 16,
          borderTop: `1px solid ${C.secondary}33`,
        }}>
          ── All Dimensions in Minutes ── Do Not Scale from Drawing ──
        </div>
      </div>
    </div>
  );
}
