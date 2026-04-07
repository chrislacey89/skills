import { useState, useEffect, useRef } from "react";

const VERSION_NAMES = [
  "Terminal",
  "Editorial",
  "CRT",
  "Blueprint",
  "Organic",
  "Brutalist",
];

export default function VersionSwitcher({ active, onChange, total = 6 }) {
  const [isOpen, setIsOpen] = useState(false);
  const ref = useRef(null);

  useEffect(() => {
    const handleKey = (e) => {
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") return;
      const num = parseInt(e.key);
      if (num >= 1 && num <= total) {
        onChange(num - 1);
        setIsOpen(false);
        return;
      }
      if (e.key === "ArrowRight") {
        onChange((active + 1) % total);
      } else if (e.key === "ArrowLeft") {
        onChange((active - 1 + total) % total);
      } else if (e.key === "Escape") {
        setIsOpen(false);
      }
    };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [active, onChange, total]);

  useEffect(() => {
    const handleClick = (e) => {
      if (ref.current && !ref.current.contains(e.target)) {
        setIsOpen(false);
      }
    };
    if (isOpen) {
      document.addEventListener("mousedown", handleClick);
      return () => document.removeEventListener("mousedown", handleClick);
    }
  }, [isOpen]);

  return (
    <div
      ref={ref}
      style={{
        position: "fixed",
        bottom: 20,
        right: 20,
        zIndex: 9999,
        fontFamily: "'SF Mono', 'JetBrains Mono', 'Fira Code', ui-monospace, monospace",
      }}
    >
      {!isOpen ? (
        <button
          onClick={() => setIsOpen(true)}
          style={{
            width: 44,
            height: 44,
            borderRadius: "50%",
            background: "rgba(0, 0, 0, 0.75)",
            backdropFilter: "blur(12px)",
            WebkitBackdropFilter: "blur(12px)",
            border: "1px solid rgba(255, 255, 255, 0.15)",
            color: "#fff",
            fontSize: 16,
            fontWeight: 700,
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            boxShadow: "0 4px 24px rgba(0, 0, 0, 0.4)",
            transition: "transform 0.15s ease",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.transform = "scale(1.1)")}
          onMouseLeave={(e) => (e.currentTarget.style.transform = "scale(1)")}
          title={`Version ${active + 1}: ${VERSION_NAMES[active]} — Click or press 1-6`}
        >
          {active + 1}
        </button>
      ) : (
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 0,
            background: "rgba(0, 0, 0, 0.8)",
            backdropFilter: "blur(16px)",
            WebkitBackdropFilter: "blur(16px)",
            border: "1px solid rgba(255, 255, 255, 0.12)",
            borderRadius: 28,
            padding: "6px 8px",
            boxShadow: "0 8px 32px rgba(0, 0, 0, 0.5)",
          }}
        >
          {Array.from({ length: total }, (_, i) => {
            const isActive = i === active;
            return (
              <button
                key={i}
                onClick={() => {
                  onChange(i);
                  setIsOpen(false);
                }}
                style={{
                  width: 36,
                  height: 36,
                  borderRadius: "50%",
                  background: isActive ? "#fff" : "transparent",
                  border: isActive ? "none" : "1px solid rgba(255, 255, 255, 0.25)",
                  color: isActive ? "#000" : "rgba(255, 255, 255, 0.7)",
                  fontSize: 13,
                  fontWeight: isActive ? 700 : 400,
                  cursor: "pointer",
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  justifyContent: "center",
                  transition: "all 0.12s ease",
                  margin: "0 2px",
                  padding: 0,
                  lineHeight: 1,
                }}
                title={`${VERSION_NAMES[i]} (${i + 1})`}
              >
                <span style={{ fontSize: 13 }}>{i + 1}</span>
                <span
                  style={{
                    fontSize: 6,
                    letterSpacing: "0.02em",
                    marginTop: 1,
                    opacity: isActive ? 0.7 : 0.4,
                    textTransform: "uppercase",
                    fontFamily: "system-ui, sans-serif",
                    fontWeight: 500,
                  }}
                >
                  {VERSION_NAMES[i].slice(0, 4)}
                </span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
