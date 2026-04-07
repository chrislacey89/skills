import { useState } from "react";
import { STEPS, PHASES, PHASE_META, getPhaseSteps } from "../data/workflow-data";

const PHASE_COLORS = {
  plan: "#1A3A5C",
  execute: "#B8532E",
  learn: "#2E6B4F",
};

const ROMAN = { plan: "I", execute: "II", learn: "III" };
const PHASE_TITLES = { plan: "Plan", execute: "Execute", learn: "Learn" };

const DEBT_TEXT = {
  github: "This artifact lives in GitHub — zero cognitive debt.",
  temporary: "This is temporary — delete after the feature ships.",
  compound: "This compounds — future work consults it.",
  none: null,
};

export default function V2Editorial() {
  const [expanded, setExpanded] = useState(null);
  const toggle = (idx) => setExpanded((prev) => (prev === idx ? null : idx));

  return (
    <div style={{
      fontFamily: "'Palatino', 'Book Antiqua', 'Palatino Linotype', Georgia, serif",
      background: "#FEFBF4",
      color: "#2D2A26",
      minHeight: "100vh",
    }}>
      <style>{`
        @keyframes fadeIn {
          from { opacity: 0; transform: translateY(8px); }
          to { opacity: 1; transform: translateY(0); }
        }
      `}</style>

      {/* Header */}
      <header style={{
        maxWidth: 720,
        margin: "0 auto",
        padding: "80px 32px 40px",
        borderBottom: "1px solid #D4CFC5",
      }}>
        <div style={{
          fontSize: 11,
          letterSpacing: "0.2em",
          textTransform: "uppercase",
          color: "#8A8279",
          marginBottom: 16,
          fontFamily: "system-ui, -apple-system, sans-serif",
          fontWeight: 500,
        }}>
          A Development Pipeline
        </div>
        <h1 style={{
          fontFamily: "Georgia, 'Times New Roman', serif",
          fontSize: 52,
          fontWeight: 400,
          letterSpacing: "-0.03em",
          lineHeight: 1.05,
          margin: 0,
          color: "#2D2A26",
        }}>
          The Hybrid Workflow
        </h1>
        <p style={{
          fontSize: 20,
          lineHeight: 1.5,
          color: "#8A8279",
          marginTop: 16,
          maxWidth: 520,
          fontStyle: "italic",
        }}>
          Composable skills, GSD research discipline, and Compound Engineering's knowledge capture — unified into one pipeline.
        </p>
      </header>

      {/* Body */}
      <main style={{
        maxWidth: 720,
        margin: "0 auto",
        padding: "0 32px 80px",
      }}>
        {PHASES.map((phase, phaseIdx) => {
          const phaseColor = PHASE_COLORS[phase];
          const steps = getPhaseSteps(phase);

          return (
            <div key={phase}>
              {/* Phase divider */}
              {phaseIdx > 0 && (
                <div style={{
                  textAlign: "center",
                  padding: "56px 0",
                  color: "#D4CFC5",
                  fontSize: 24,
                  letterSpacing: "0.5em",
                  userSelect: "none",
                }}>
                  * &nbsp; * &nbsp; *
                </div>
              )}

              {/* Phase header */}
              <div style={{
                display: "flex",
                alignItems: "baseline",
                gap: 16,
                marginBottom: 40,
                marginTop: phaseIdx === 0 ? 48 : 0,
              }}>
                <span style={{
                  fontFamily: "Georgia, 'Times New Roman', serif",
                  fontSize: 14,
                  color: phaseColor,
                  fontStyle: "italic",
                  opacity: 0.6,
                  minWidth: 24,
                }}>
                  {ROMAN[phase]}
                </span>
                <h2 style={{
                  fontFamily: "Georgia, 'Times New Roman', serif",
                  fontSize: 36,
                  fontWeight: 400,
                  letterSpacing: "-0.02em",
                  margin: 0,
                  color: phaseColor,
                }}>
                  {PHASE_TITLES[phase]}
                </h2>
                <div style={{
                  flex: 1,
                  height: 1,
                  background: phaseColor,
                  opacity: 0.15,
                  marginLeft: 8,
                }} />
              </div>

              {/* Steps */}
              {steps.map((s) => {
                const idx = STEPS.indexOf(s);
                const isOpen = expanded === idx;
                const debt = DEBT_TEXT[s.debtType];

                return (
                  <article
                    key={s.id}
                    onClick={() => toggle(idx)}
                    style={{
                      cursor: "pointer",
                      marginBottom: 48,
                      position: "relative",
                    }}
                  >
                    {/* Step label */}
                    <div style={{
                      display: "flex",
                      alignItems: "baseline",
                      gap: 12,
                      marginBottom: 12,
                    }}>
                      <h3 style={{
                        fontFamily: "Georgia, 'Times New Roman', serif",
                        fontSize: 22,
                        fontWeight: 700,
                        margin: 0,
                        color: "#2D2A26",
                        letterSpacing: "-0.01em",
                      }}>
                        {s.label}
                      </h3>
                      <span style={{
                        fontFamily: "system-ui, sans-serif",
                        fontSize: 11,
                        color: "#8A8279",
                        textTransform: "uppercase",
                        letterSpacing: "0.08em",
                        fontWeight: 500,
                      }}>
                        {s.mode === "afk" ? "AFK" : "Interactive"} · {s.time}
                      </span>
                    </div>

                    {/* Pull quote — summary */}
                    <blockquote style={{
                      margin: 0,
                      padding: "16px 0 16px 24px",
                      borderLeft: `3px solid ${phaseColor}`,
                      background: `linear-gradient(90deg, #F0E6D2 0%, transparent 100%)`,
                      marginLeft: 0,
                      marginRight: 0,
                    }}>
                      <p style={{
                        fontFamily: "Georgia, 'Times New Roman', serif",
                        fontSize: 20,
                        fontStyle: "italic",
                        lineHeight: 1.45,
                        color: "#2D2A26",
                        margin: 0,
                      }}>
                        {s.summary}
                      </p>
                    </blockquote>

                    {/* Expanded detail */}
                    {isOpen && (
                      <div style={{
                        marginTop: 20,
                        animation: "fadeIn 0.3s ease",
                      }}>
                        {/* Source */}
                        <p style={{
                          fontSize: 12,
                          color: phaseColor,
                          fontStyle: "italic",
                          marginBottom: 12,
                          fontFamily: "system-ui, sans-serif",
                        }}>
                          Origin: {s.source}
                        </p>

                        {/* Detail prose */}
                        <p style={{
                          fontSize: 16,
                          lineHeight: 1.75,
                          color: "#4A453F",
                          marginBottom: 24,
                        }}>
                          {s.detail}
                        </p>

                        {/* Consumes */}
                        {s.consumes && (
                          <div style={{ marginBottom: 16 }}>
                            <div style={{
                              fontFamily: "system-ui, sans-serif",
                              fontSize: 11,
                              fontVariant: "small-caps",
                              letterSpacing: "0.15em",
                              color: phaseColor,
                              marginBottom: 6,
                              fontWeight: 600,
                            }}>
                              Consumes
                            </div>
                            <p style={{
                              fontSize: 14,
                              lineHeight: 1.6,
                              color: "#6B655D",
                              paddingLeft: 16,
                              margin: 0,
                              borderLeft: "1px solid #D4CFC5",
                            }}>
                              {s.consumes}
                            </p>
                          </div>
                        )}

                        {/* Produces */}
                        {s.produces && (
                          <div style={{ marginBottom: 16 }}>
                            <div style={{
                              fontFamily: "system-ui, sans-serif",
                              fontSize: 11,
                              fontVariant: "small-caps",
                              letterSpacing: "0.15em",
                              color: phaseColor,
                              marginBottom: 6,
                              fontWeight: 600,
                            }}>
                              Produces
                            </div>
                            <p style={{
                              fontSize: 14,
                              lineHeight: 1.6,
                              color: "#6B655D",
                              paddingLeft: 16,
                              margin: 0,
                              borderLeft: "1px solid #D4CFC5",
                            }}>
                              {s.produces}
                            </p>
                          </div>
                        )}

                        {/* State location */}
                        <p style={{
                          fontSize: 12,
                          color: "#8A8279",
                          fontStyle: "italic",
                          margin: "8px 0 0",
                        }}>
                          State: {s.stateLocation}
                        </p>

                        {/* Debt footnote */}
                        {debt && (
                          <p style={{
                            fontSize: 13,
                            fontStyle: "italic",
                            color: "#8A8279",
                            marginTop: 16,
                            paddingTop: 12,
                            borderTop: "1px solid #E8E3D9",
                          }}>
                            {debt}
                          </p>
                        )}
                      </div>
                    )}

                    {/* Click hint */}
                    {!isOpen && (
                      <p style={{
                        fontSize: 11,
                        color: "#C4BDB3",
                        marginTop: 10,
                        fontFamily: "system-ui, sans-serif",
                        fontStyle: "italic",
                      }}>
                        Click to read more
                      </p>
                    )}
                  </article>
                );
              })}
            </div>
          );
        })}

        {/* Feedback loop */}
        <div style={{
          textAlign: "center",
          padding: "48px 0 0",
          borderTop: "1px solid #D4CFC5",
        }}>
          <p style={{
            fontSize: 18,
            fontStyle: "italic",
            color: "#8A8279",
            lineHeight: 1.6,
          }}>
            <span style={{ color: "#2E6B4F" }}>docs/solutions/</span>{" "}
            feeds back into{" "}
            <span style={{ color: "#B8532E" }}>/research</span>{" "}
            and{" "}
            <span style={{ color: "#1A3A5C" }}>/write-a-prd</span>
          </p>
          <p style={{
            fontSize: 14,
            color: "#C4BDB3",
            fontStyle: "italic",
            marginTop: 8,
          }}>
            Each cycle makes the next one easier.
          </p>
        </div>
      </main>

      {/* Footer */}
      <footer style={{
        maxWidth: 720,
        margin: "0 auto",
        padding: "24px 32px 48px",
        borderTop: "1px solid #E8E3D9",
        display: "flex",
        justifyContent: "center",
        gap: 32,
        flexWrap: "wrap",
      }}>
        {[
          ["GitHub = truth", "#1A3A5C"],
          ["docs/solutions/ = compounds", "#2E6B4F"],
          ["research.md = temporary", "#B8532E"],
        ].map(([text, color]) => (
          <span key={text} style={{
            fontSize: 11,
            color,
            fontFamily: "system-ui, sans-serif",
            letterSpacing: "0.05em",
            textTransform: "uppercase",
            fontWeight: 500,
          }}>
            {text}
          </span>
        ))}
      </footer>
    </div>
  );
}
