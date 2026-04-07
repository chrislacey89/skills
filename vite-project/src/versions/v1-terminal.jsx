import { STEPS, PHASE_META, MODE_COLORS, SOURCE_DOT, DEBT_CALLOUT } from "../data/workflow-data";
import { useWorkflowState } from "../hooks/useWorkflowState";

export default function V1Terminal() {
  const { expanded, toggle } = useWorkflowState();

  return (
    <div style={{
      fontFamily: "'SF Mono', 'JetBrains Mono', 'Fira Code', monospace",
      background: "#0a0f1a",
      color: "#c9d1d9",
      minHeight: "100vh",
      maxWidth: 600,
      margin: "0 auto",
    }}>
      <div style={{ padding: "24px 20px 16px" }}>
        <h1 style={{ fontSize: 16, fontWeight: 700, color: "#e2e8f0", margin: 0, letterSpacing: "-0.02em" }}>
          The Hybrid Workflow
        </h1>
        <p style={{ fontSize: 11, color: "#64748b", margin: "4px 0 0", lineHeight: 1.4, fontFamily: "system-ui, sans-serif" }}>
          Matt's pipeline + GSD research + Compound Engineering
        </p>
      </div>

      <div style={{ display: "flex", flexWrap: "wrap", gap: 10, padding: "0 20px 16px", fontSize: 10 }}>
        {Object.entries(SOURCE_DOT).map(([name, color]) => (
          <span key={name} style={{ display: "flex", alignItems: "center", gap: 4 }}>
            <span style={{ width: 7, height: 7, borderRadius: "50%", background: color }} />
            <span style={{ color: "#94a3b8" }}>{name}</span>
          </span>
        ))}
      </div>

      <div style={{ padding: "0 20px 24px" }}>
        {["plan", "execute", "learn"].map((phase, phaseIdx) => {
          const meta = PHASE_META[phase];
          const phaseSteps = STEPS.filter((s) => s.phase === phase);
          return (
            <div key={phase} style={{ marginBottom: 20 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 10 }}>
                <span style={{ fontSize: 9, fontWeight: 700, letterSpacing: "0.12em", color: meta.color }}>
                  {meta.label}
                </span>
                <span style={{ flex: 1, height: 1, background: meta.color + "33" }} />
              </div>

              {phaseSteps.map((s, i) => {
                const idx = STEPS.indexOf(s);
                const isOpen = expanded === idx;
                const isDec = s.mode === "decision";
                const mode = MODE_COLORS[s.mode];
                const srcColor = SOURCE_DOT[s.source] || "#64748b";
                const debt = DEBT_CALLOUT[s.debtType];

                return (
                  <div key={s.id}>
                    <div
                      onClick={() => toggle(idx)}
                      role="button"
                      tabIndex={0}
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 10,
                        padding: isDec ? "8px 12px" : "12px 14px",
                        background: isOpen ? (meta.color + "12") : "#0f1629",
                        border: isOpen ? ("1px solid " + meta.color + "44") : "1px solid #1e293b",
                        borderRadius: isDec ? 20 : 10,
                        cursor: "pointer",
                        marginBottom: isOpen ? 0 : 4,
                        borderBottomLeftRadius: isOpen ? 0 : (isDec ? 20 : 10),
                        borderBottomRightRadius: isOpen ? 0 : (isDec ? 20 : 10),
                      }}
                    >
                      {!isDec && (
                        <span style={{ width: 7, height: 7, borderRadius: "50%", background: srcColor, flexShrink: 0 }} />
                      )}
                      <span style={{ flex: 1, minWidth: 0 }}>
                        <span style={{
                          display: "block",
                          fontSize: isDec ? 11 : 13,
                          fontWeight: isDec ? 400 : 600,
                          color: isDec ? "#94a3b8" : "#e2e8f0",
                          fontStyle: isDec ? "italic" : "normal",
                        }}>
                          {s.label}
                        </span>
                        {!isDec && (
                          <span style={{
                            display: "block", fontSize: 10, color: "#64748b", marginTop: 2,
                            fontFamily: "system-ui, sans-serif",
                          }}>
                            {s.summary}
                          </span>
                        )}
                      </span>
                      <span style={{ display: "flex", alignItems: "center", gap: 6, flexShrink: 0 }}>
                        {!isDec && (
                          <span style={{
                            fontSize: 8, fontWeight: 700, letterSpacing: "0.06em",
                            padding: "2px 5px", borderRadius: 4, color: mode.color, background: mode.bg,
                          }}>
                            {mode.label}
                          </span>
                        )}
                        {s.time && (
                          <span style={{ fontSize: 9, color: "#475569", whiteSpace: "nowrap" }}>{s.time}</span>
                        )}
                      </span>
                      <svg width="12" height="12" viewBox="0 0 12 12"
                        style={{ transform: isOpen ? "rotate(180deg)" : "rotate(0deg)", transition: "transform 0.15s ease", flexShrink: 0 }}>
                        <path d="M3 4.5L6 7.5L9 4.5" stroke="#475569" strokeWidth="1.5" fill="none" strokeLinecap="round" />
                      </svg>
                    </div>

                    {isOpen && (
                      <div style={{
                        padding: "14px 14px 16px",
                        background: meta.color + "08",
                        border: "1px solid " + meta.color + "44",
                        borderTop: "none",
                        borderRadius: "0 0 10px 10px",
                        marginBottom: 4,
                      }}>
                        {s.source && (
                          <span style={{
                            display: "inline-block", fontSize: 9, padding: "2px 7px", borderRadius: 4,
                            background: srcColor + "18", color: srcColor, border: "1px solid " + srcColor + "33",
                            marginBottom: 10,
                          }}>
                            {s.source}
                          </span>
                        )}
                        <p style={{
                          fontSize: 12, color: "#94a3b8", margin: "0 0 14px", lineHeight: 1.65,
                          fontFamily: "system-ui, sans-serif",
                        }}>
                          {s.detail}
                        </p>

                        {s.consumes && (
                          <div style={{
                            padding: "8px 10px", borderRadius: 6, background: "#0a0f1a",
                            border: "1px solid #1e293b", marginBottom: 6,
                          }}>
                            <div style={{ fontSize: 8, fontWeight: 700, letterSpacing: "0.1em", color: "#6366f1", marginBottom: 4 }}>
                              CONSUMES
                            </div>
                            <div style={{ fontSize: 11, color: "#94a3b8", lineHeight: 1.5, fontFamily: "system-ui, sans-serif" }}>
                              {s.consumes}
                            </div>
                          </div>
                        )}
                        {s.produces && (
                          <div style={{
                            padding: "8px 10px", borderRadius: 6, background: "#0a0f1a",
                            border: "1px solid #1e293b", marginBottom: 6,
                          }}>
                            <div style={{ fontSize: 8, fontWeight: 700, letterSpacing: "0.1em", color: "#22c55e", marginBottom: 4 }}>
                              PRODUCES
                            </div>
                            <div style={{ fontSize: 11, color: "#94a3b8", lineHeight: 1.5, fontFamily: "system-ui, sans-serif" }}>
                              {s.produces}
                            </div>
                          </div>
                        )}

                        {debt && (
                          <div style={{
                            marginTop: 8, padding: "8px 10px", borderRadius: 6,
                            background: debt.bg, border: "1px solid " + debt.border,
                            fontSize: 10, color: debt.color, lineHeight: 1.5,
                            fontFamily: "system-ui, sans-serif",
                          }}>
                            {debt.icon} {debt.text}
                          </div>
                        )}
                      </div>
                    )}

                    {i < phaseSteps.length - 1 && !isOpen && (
                      <div style={{ display: "flex", justifyContent: "center", height: 6 }}>
                        <div style={{ width: 1, height: "100%", background: "#1e293b" }} />
                      </div>
                    )}
                  </div>
                );
              })}

              {phaseIdx < 2 && (
                <div style={{ display: "flex", justifyContent: "center", padding: "8px 0" }}>
                  <svg width="12" height="14" viewBox="0 0 12 14">
                    <path d="M6 0L6 10M2 7L6 11.5L10 7" stroke="#334155" strokeWidth="1.5" fill="none" />
                  </svg>
                </div>
              )}
            </div>
          );
        })}

        <div style={{
          marginTop: 12, padding: "12px 14px", borderRadius: 10,
          border: "1px dashed #334155", fontSize: 11, color: "#64748b",
          lineHeight: 1.7, textAlign: "center", fontFamily: "system-ui, sans-serif",
        }}>
          <span style={{ color: "#34d399" }}>docs/solutions/</span> feeds back into{" "}
          <span style={{ color: "#f59e0b" }}>/research</span> and{" "}
          <span style={{ color: "#818cf8" }}>/write-a-prd</span>
          <br />
          <span style={{ fontStyle: "italic", fontSize: 10 }}>Each cycle makes the next one easier</span>
        </div>
      </div>

      <div style={{
        padding: "14px 20px", borderTop: "1px solid #1e293b",
        display: "flex", flexWrap: "wrap", gap: 8, fontSize: 9, color: "#475569",
      }}>
        <span><span style={{ color: "#3b82f6" }}>●</span> GitHub = truth</span>
        <span><span style={{ color: "#22c55e" }}>●</span> docs/solutions/ = compounds</span>
        <span><span style={{ color: "#f59e0b" }}>●</span> research.md = temporary</span>
        <span><span style={{ color: "#ef4444" }}>●</span> No .gsd/ · No 36K plugin</span>
      </div>
    </div>
  );
}
