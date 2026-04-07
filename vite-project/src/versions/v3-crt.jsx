import { useState, useEffect } from "react";
import { STEPS, PHASES, PHASE_META, getPhaseSteps } from "../data/workflow-data";

const PHOSPHOR = "#33FF33";
const PHOSPHOR_DIM = "#1A8C1A";
const PHOSPHOR_BRIGHT = "#66FF66";
const CRT_BLACK = "#0A0A0A";

const GLOW = `0 0 5px ${PHOSPHOR}, 0 0 10px ${PHOSPHOR}66`;
const GLOW_BRIGHT = `0 0 8px ${PHOSPHOR}, 0 0 20px ${PHOSPHOR}88, 0 0 40px ${PHOSPHOR}44`;

const FONT = "'Courier New', 'Courier', monospace";

const PHASE_NUMBER = { plan: 1, execute: 2, learn: 3 };

const DEBT_STATUS = {
  github: "ZERO DEBT \u2014 LIVES IN GITHUB",
  temporary: "TEMPORARY \u2014 DELETE AFTER SHIP",
  compound: "COMPOUNDS \u2014 FUTURE WORK CONSULTS THIS",
  none: null,
};

function boxLine(content, width) {
  const padded = content + " ".repeat(Math.max(0, width - content.length));
  return `  \u2502 ${padded} \u2502`;
}

function buildDetailBox(step, revealedChars) {
  const width = 47;
  const top = `  \u250C${ "\u2500".repeat(width + 2) }\u2510`;
  const bottom = `  \u2514${ "\u2500".repeat(width + 2) }\u2518`;
  const empty = boxLine("", width);

  const lines = [];
  lines.push(top);

  // Detail text, wrapped
  const detailWords = step.detail.split(" ");
  let currentLine = "";
  const detailLines = [];
  for (const word of detailWords) {
    if (currentLine.length + word.length + 1 > width) {
      detailLines.push(currentLine);
      currentLine = word;
    } else {
      currentLine = currentLine ? currentLine + " " + word : word;
    }
  }
  if (currentLine) detailLines.push(currentLine);
  detailLines.forEach((l) => lines.push(boxLine(l, width)));

  lines.push(empty);

  // Input/Output
  const inputText = `>> INPUT:  ${step.consumes}`;
  const inputWords = inputText.split(" ");
  let inputLine = "";
  const inputLines = [];
  for (const word of inputWords) {
    if (inputLine.length + word.length + 1 > width) {
      inputLines.push(inputLine);
      inputLine = "           " + word;
    } else {
      inputLine = inputLine ? inputLine + " " + word : word;
    }
  }
  if (inputLine) inputLines.push(inputLine);
  inputLines.forEach((l) => lines.push(boxLine(l, width)));

  const outputText = `<< OUTPUT: ${step.produces}`;
  const outputWords = outputText.split(" ");
  let outputLine = "";
  const outputLines = [];
  for (const word of outputWords) {
    if (outputLine.length + word.length + 1 > width) {
      outputLines.push(outputLine);
      outputLine = "           " + word;
    } else {
      outputLine = outputLine ? outputLine + " " + word : word;
    }
  }
  if (outputLine) outputLines.push(outputLine);
  outputLines.forEach((l) => lines.push(boxLine(l, width)));

  lines.push(empty);

  // Status
  const status = DEBT_STATUS[step.debtType];
  if (status) {
    lines.push(boxLine(`[STATUS: ${status}]`, width));
  } else {
    lines.push(boxLine("[STATUS: NO ARTIFACT]", width));
  }

  lines.push(bottom);

  const fullText = lines.join("\n");
  return fullText.slice(0, revealedChars);
}

function phaseHeader(phase) {
  const num = PHASE_NUMBER[phase];
  const label = PHASE_META[phase].label;
  const title = `  PHASE ${num} : ${label}`;
  const innerWidth = 38;
  const padded = title + " ".repeat(Math.max(0, innerWidth - title.length));
  return [
    `\u2554${ "\u2550".repeat(innerWidth) }\u2557`,
    `\u2551${padded}\u2551`,
    `\u255A${ "\u2550".repeat(innerWidth) }\u255D`,
  ].join("\n");
}

function dotSeparator() {
  return ". ".repeat(20).trim();
}

export default function V3CRT() {
  const [expanded, setExpanded] = useState(null);
  const [revealedChars, setRevealedChars] = useState(0);
  const [hoveredStep, setHoveredStep] = useState(null);

  const fullDetailText = expanded !== null
    ? buildDetailBox(STEPS[expanded], Infinity)
    : "";

  useEffect(() => {
    if (expanded === null) return;
    setRevealedChars(0);
    const fullText = buildDetailBox(STEPS[expanded], Infinity);
    const len = fullText.length;
    let count = 0;
    const interval = setInterval(() => {
      count += 3;
      if (count >= len) {
        setRevealedChars(len);
        clearInterval(interval);
      } else {
        setRevealedChars(count);
      }
    }, 15);
    return () => clearInterval(interval);
  }, [expanded]);

  const toggleStep = (idx) => {
    if (expanded === idx) {
      setExpanded(null);
    } else {
      setExpanded(idx);
    }
  };

  const keyframesCSS = `
    @keyframes scanline-drift {
      0% { transform: translateY(0px); }
      100% { transform: translateY(3px); }
    }
    @keyframes cursor-blink {
      0%, 49% { opacity: 1; }
      50%, 100% { opacity: 0; }
    }
    @keyframes screen-flicker {
      0% { opacity: 1; }
      50% { opacity: 0.97; }
      100% { opacity: 1; }
    }
    @keyframes boot-glow {
      0% { opacity: 0; transform: scaleY(0.01); }
      30% { opacity: 1; transform: scaleY(0.01); }
      50% { opacity: 1; transform: scaleY(1); }
      100% { opacity: 1; transform: scaleY(1); }
    }
  `;

  return (
    <div style={{
      background: CRT_BLACK,
      minHeight: "100vh",
      display: "flex",
      justifyContent: "center",
      padding: "40px 20px",
      fontFamily: FONT,
      fontSize: 14,
      lineHeight: 1.6,
      color: PHOSPHOR,
    }}>
      <style>{keyframesCSS}</style>

      {/* Scanline overlay */}
      <div style={{
        position: "fixed",
        inset: 0,
        pointerEvents: "none",
        zIndex: 9998,
        background: "repeating-linear-gradient(0deg, rgba(0,0,0,0.15) 0px, rgba(0,0,0,0.15) 1px, transparent 1px, transparent 3px)",
        animation: "scanline-drift 60s linear infinite",
      }} />

      {/* CRT screen container */}
      <div style={{
        position: "relative",
        overflow: "hidden",
        maxWidth: 700,
        width: "100%",
        padding: 30,
        borderRadius: 20,
        boxShadow: `inset 0 0 80px rgba(0,0,0,0.6), inset 0 0 160px rgba(0,0,0,0.3), 0 0 40px rgba(51,255,51,0.1)`,
        animation: "screen-flicker 8s ease-in-out infinite",
      }}>

        {/* Boot header */}
        <div style={{
          textTransform: "uppercase",
          textShadow: GLOW,
          marginBottom: 8,
          letterSpacing: 2,
          fontSize: 12,
          color: PHOSPHOR_DIM,
        }}>
          {">>> PIPELINE CONTROL SYSTEM v3.0.1"}
        </div>
        <div style={{
          textShadow: GLOW,
          marginBottom: 4,
          fontSize: 12,
          color: PHOSPHOR_DIM,
        }}>
          {">>> INITIALIZING MODULES..."}
        </div>
        <div style={{
          textShadow: GLOW,
          marginBottom: 4,
          fontSize: 12,
          color: PHOSPHOR,
        }}>
          {">>> BOOT COMPLETE. ALL SYSTEMS NOMINAL."}
        </div>
        <div style={{
          textShadow: GLOW,
          marginBottom: 24,
          fontSize: 12,
          color: PHOSPHOR_DIM,
        }}>
          {">>> " + STEPS.length + " MODULES LOADED. AWAITING INPUT."}
        </div>

        {/* Horizontal rule */}
        <div style={{
          textShadow: GLOW,
          color: PHOSPHOR_DIM,
          marginBottom: 24,
          fontSize: 14,
          letterSpacing: 1,
        }}>
          {"\u2500".repeat(50)}
        </div>

        {/* Phase groups */}
        {PHASES.map((phase) => {
          const steps = getPhaseSteps(phase);
          const header = phaseHeader(phase);

          return (
            <div key={phase} style={{ marginBottom: 32 }}>
              {/* Phase header box */}
              <pre style={{
                margin: 0,
                marginBottom: 16,
                fontFamily: FONT,
                fontSize: 14,
                lineHeight: 1.4,
                color: PHOSPHOR,
                textShadow: GLOW,
                textTransform: "uppercase",
              }}>
                {header}
              </pre>

              {/* Steps in this phase */}
              {steps.map((step) => {
                const idx = STEPS.indexOf(step);
                const isExpanded = expanded === idx;
                const isHovered = hoveredStep === idx;
                const isLast = idx === STEPS.length - 1;

                return (
                  <div key={step.id}>
                    {/* Step line */}
                    <div
                      onClick={() => toggleStep(idx)}
                      onMouseEnter={() => setHoveredStep(idx)}
                      onMouseLeave={() => setHoveredStep(null)}
                      style={{
                        cursor: "pointer",
                        padding: "4px 0",
                        userSelect: "none",
                        textShadow: isHovered || isExpanded ? GLOW_BRIGHT : GLOW,
                        transition: "text-shadow 0.15s ease",
                      }}
                    >
                      <span style={{
                        color: isHovered || isExpanded ? PHOSPHOR_BRIGHT : PHOSPHOR,
                        fontWeight: isExpanded ? "bold" : "normal",
                      }}>
                        {">"} {step.label}
                      </span>
                      <span style={{ color: PHOSPHOR_DIM }}>
                        {" "}{". ".repeat(Math.max(1, Math.floor((40 - step.label.length) / 2))).trim()}{" "}
                      </span>
                      <span style={{
                        color: isHovered || isExpanded ? PHOSPHOR : PHOSPHOR_DIM,
                      }}>
                        {step.summary}
                      </span>
                      {/* Blinking cursor on hovered step */}
                      {isHovered && !isExpanded && (
                        <span style={{
                          color: PHOSPHOR_BRIGHT,
                          textShadow: GLOW_BRIGHT,
                          animation: "cursor-blink 1s step-end infinite",
                          marginLeft: 4,
                        }}>
                          {"\u2588"}
                        </span>
                      )}
                    </div>

                    {/* Expanded detail */}
                    {isExpanded && (
                      <pre style={{
                        margin: 0,
                        padding: "8px 0 4px 0",
                        fontFamily: FONT,
                        fontSize: 13,
                        lineHeight: 1.5,
                        color: PHOSPHOR,
                        textShadow: GLOW,
                        whiteSpace: "pre-wrap",
                        wordBreak: "break-word",
                      }}>
                        {buildDetailBox(step, revealedChars)}
                        <span style={{
                          color: PHOSPHOR_BRIGHT,
                          textShadow: GLOW_BRIGHT,
                          animation: "cursor-blink 1s step-end infinite",
                        }}>
                          {revealedChars < fullDetailText.length ? "\u2588" : ""}
                        </span>
                      </pre>
                    )}

                    {/* Dot separator between steps */}
                    {!isLast && (
                      <div style={{
                        color: `${PHOSPHOR_DIM}44`,
                        textShadow: `0 0 3px ${PHOSPHOR}22`,
                        padding: "2px 0",
                        fontSize: 12,
                        letterSpacing: 2,
                      }}>
                        {dotSeparator()}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          );
        })}

        {/* Footer status bar */}
        <div style={{
          textShadow: GLOW,
          color: PHOSPHOR_DIM,
          marginTop: 16,
          fontSize: 12,
          letterSpacing: 1,
        }}>
          {"\u2500".repeat(50)}
        </div>
        <div style={{
          textShadow: GLOW,
          color: PHOSPHOR,
          marginTop: 12,
          fontSize: 12,
          textTransform: "uppercase",
          letterSpacing: 2,
        }}>
          {"\u2500\u2500\u2500 SYSTEM ONLINE \u2500\u2500\u2500 " + STEPS.length + " MODULES LOADED \u2500\u2500\u2500 GITHUB = TRUTH \u2500\u2500\u2500"}
        </div>

      </div>
    </div>
  );
}
