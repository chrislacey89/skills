import { useState } from "react";
import { STEPS, PHASES, getPhaseSteps } from "../data/workflow-data";

const PHASE_LABELS = { plan: "PLAN", execute: "EXECUTE", learn: "LEARN" };

const DEBT_STATUS = {
  github: "STATUS: ZERO DEBT — LIVES IN GITHUB",
  temporary: "STATUS: TEMPORARY — DELETE AFTER SHIP",
  compound: "STATUS: COMPOUNDS — FUTURE WORK CONSULTS THIS",
  none: null,
};

export default function V6Brutalist() {
  const [expanded, setExpanded] = useState(null);
  const toggle = (idx) => setExpanded((prev) => (prev === idx ? null : idx));

  let globalIdx = 0;

  return (
    <div style={{
      fontFamily: "Georgia, 'Times New Roman', serif",
      background: "#FFFFFF",
      color: "#000000",
      minHeight: "100vh",
    }}>
      <style>{`
        @media (max-width: 768px) {
          .brutalist-grid { grid-template-columns: 1fr !important; }
          .brutalist-phase-title { font-size: 48px !important; }
        }
      `}</style>

      {/* Header */}
      <header style={{
        padding: "48px 20px 40px",
        borderBottom: "8px solid #000",
      }}>
        <h1 style={{
          fontFamily: "'Arial Black', 'Impact', 'Helvetica Neue', sans-serif",
          fontSize: 64,
          fontWeight: 900,
          textTransform: "uppercase",
          letterSpacing: "-0.03em",
          lineHeight: 0.9,
          margin: 0,
        }}>
          The Hybrid<br />Workflow
        </h1>
        <p style={{
          fontSize: 14,
          marginTop: 16,
          maxWidth: 500,
          lineHeight: 1.5,
          color: "#666",
        }}>
          Composable pipeline. GSD research. Compound Engineering. Nine steps. Three phases. No waste.
        </p>
      </header>

      {/* Phases */}
      {PHASES.map((phase) => {
        const steps = getPhaseSteps(phase);

        return (
          <section key={phase} style={{
            borderTop: "8px solid #000",
          }}>
            {/* Phase Title — massive, clipped */}
            <div style={{
              height: 72,
              overflow: "hidden",
              padding: "0 20px",
              position: "relative",
            }}>
              <div
                className="brutalist-phase-title"
                style={{
                  fontFamily: "'Arial Black', 'Impact', 'Helvetica Neue', sans-serif",
                  fontSize: 96,
                  fontWeight: 900,
                  textTransform: "uppercase",
                  letterSpacing: "-0.04em",
                  lineHeight: 0.85,
                  color: "#000",
                  position: "absolute",
                  bottom: -8,
                  left: 20,
                }}
              >
                {PHASE_LABELS[phase]}
              </div>
            </div>

            {/* Steps Grid */}
            <div
              className="brutalist-grid"
              style={{
                display: "grid",
                gridTemplateColumns: "1fr 1fr",
                borderTop: "2px solid #000",
              }}
            >
              {steps.map((s) => {
                const stepNum = globalIdx++;
                const idx = STEPS.indexOf(s);
                const isOpen = expanded === idx;
                const debt = DEBT_STATUS[s.debtType];

                return (
                  <div
                    key={s.id}
                    onClick={() => toggle(idx)}
                    role="button"
                    tabIndex={0}
                    style={{
                      borderRight: "2px solid #000",
                      borderBottom: "2px solid #000",
                      padding: "32px 24px",
                      cursor: "pointer",
                      position: "relative",
                      overflow: "hidden",
                      borderLeft: isOpen ? "4px solid #FF0000" : "none",
                      background: isOpen ? "#FAFAFA" : "#FFFFFF",
                      minHeight: 120,
                    }}
                  >
                    {/* Watermark number */}
                    <div style={{
                      position: "absolute",
                      top: -10,
                      right: -5,
                      fontSize: 140,
                      fontFamily: "'Arial Black', sans-serif",
                      fontWeight: 900,
                      color: isOpen ? "#FFE5E5" : "#F0F0F0",
                      lineHeight: 1,
                      transform: "rotate(-5deg)",
                      pointerEvents: "none",
                      userSelect: "none",
                      zIndex: 0,
                    }}>
                      {stepNum + 1}
                    </div>

                    {/* Content */}
                    <div style={{ position: "relative", zIndex: 1 }}>
                      {/* Label + mode */}
                      <div style={{
                        display: "flex",
                        justifyContent: "space-between",
                        alignItems: "flex-start",
                        marginBottom: 8,
                      }}>
                        <h3 style={{
                          fontFamily: "'Arial', 'Helvetica', sans-serif",
                          fontSize: 20,
                          fontWeight: 700,
                          textTransform: "uppercase",
                          margin: 0,
                          letterSpacing: "-0.01em",
                          color: isOpen ? "#FF0000" : "#000",
                        }}>
                          {s.label}
                        </h3>
                        <span style={{
                          fontFamily: "'Courier New', monospace",
                          fontSize: 10,
                          fontWeight: 700,
                          textTransform: "uppercase",
                          letterSpacing: "0.1em",
                          color: "#666",
                          flexShrink: 0,
                        }}>
                          {s.mode === "afk" ? "AFK" : "HITL"} / {s.time}
                        </span>
                      </div>

                      {/* Summary */}
                      <p style={{
                        fontSize: 14,
                        lineHeight: 1.5,
                        color: "#333",
                        margin: 0,
                        fontWeight: 700,
                      }}>
                        {s.summary}
                      </p>

                      {/* Expanded — instant, no animation */}
                      {isOpen && (
                        <div style={{ marginTop: 20 }}>
                          {/* Source */}
                          <p style={{
                            fontFamily: "'Courier New', monospace",
                            fontSize: 10,
                            textTransform: "uppercase",
                            letterSpacing: "0.1em",
                            color: "#999",
                            marginBottom: 12,
                          }}>
                            SOURCE: {s.source}
                          </p>

                          {/* Detail */}
                          <p style={{
                            fontSize: 14,
                            lineHeight: 1.65,
                            color: "#444",
                            marginBottom: 20,
                          }}>
                            {s.detail}
                          </p>

                          {/* Consumes / Produces table */}
                          <table style={{
                            width: "100%",
                            borderCollapse: "collapse",
                            marginBottom: 16,
                            fontFamily: "'Courier New', monospace",
                            fontSize: 11,
                          }}>
                            <tbody>
                              {s.consumes && (
                                <tr>
                                  <td style={{
                                    borderTop: "1px solid #000",
                                    borderBottom: "1px solid #000",
                                    padding: "8px 12px 8px 0",
                                    fontWeight: 700,
                                    textTransform: "uppercase",
                                    letterSpacing: "0.08em",
                                    verticalAlign: "top",
                                    whiteSpace: "nowrap",
                                    width: 90,
                                    color: "#000",
                                  }}>
                                    CONSUMES
                                  </td>
                                  <td style={{
                                    borderTop: "1px solid #000",
                                    borderBottom: "1px solid #000",
                                    padding: "8px 0",
                                    color: "#444",
                                    fontFamily: "Georgia, serif",
                                    fontSize: 12,
                                    lineHeight: 1.5,
                                  }}>
                                    {s.consumes}
                                  </td>
                                </tr>
                              )}
                              {s.produces && (
                                <tr>
                                  <td style={{
                                    borderBottom: "1px solid #000",
                                    padding: "8px 12px 8px 0",
                                    fontWeight: 700,
                                    textTransform: "uppercase",
                                    letterSpacing: "0.08em",
                                    verticalAlign: "top",
                                    whiteSpace: "nowrap",
                                    width: 90,
                                    color: "#000",
                                  }}>
                                    PRODUCES
                                  </td>
                                  <td style={{
                                    borderBottom: "1px solid #000",
                                    padding: "8px 0",
                                    color: "#444",
                                    fontFamily: "Georgia, serif",
                                    fontSize: 12,
                                    lineHeight: 1.5,
                                  }}>
                                    {s.produces}
                                  </td>
                                </tr>
                              )}
                            </tbody>
                          </table>

                          {/* Debt status */}
                          {debt && (
                            <div style={{
                              borderTop: "2px solid #000",
                              paddingTop: 8,
                            }}>
                              <p style={{
                                fontFamily: "'Courier New', monospace",
                                fontSize: 11,
                                fontWeight: 700,
                                textTransform: "uppercase",
                                letterSpacing: "0.06em",
                                color: "#000",
                                margin: 0,
                              }}>
                                [{debt}]
                              </p>
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </section>
        );
      })}

      {/* Footer */}
      <footer style={{
        borderTop: "8px solid #000",
        padding: "32px 20px",
        display: "flex",
        justifyContent: "space-between",
        flexWrap: "wrap",
        gap: 16,
      }}>
        {[
          "GITHUB = TRUTH",
          "DOCS/SOLUTIONS/ = COMPOUNDS",
          "RESEARCH.MD = TEMPORARY",
          "NO .GSD/",
        ].map((text) => (
          <span key={text} style={{
            fontFamily: "'Courier New', monospace",
            fontSize: 10,
            fontWeight: 700,
            letterSpacing: "0.12em",
            color: "#000",
          }}>
            {text}
          </span>
        ))}
      </footer>

      {/* Feedback loop */}
      <div style={{
        borderTop: "2px solid #000",
        padding: "24px 20px",
        textAlign: "center",
      }}>
        <p style={{
          fontFamily: "'Arial', sans-serif",
          fontSize: 12,
          textTransform: "uppercase",
          letterSpacing: "0.2em",
          color: "#999",
        }}>
          EACH CYCLE MAKES THE NEXT ONE EASIER
        </p>
      </div>
    </div>
  );
}
