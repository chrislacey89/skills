import { useState } from "react";

export function useWorkflowState() {
  const [expanded, setExpanded] = useState(null);
  const toggle = (idx) => setExpanded((prev) => (prev === idx ? null : idx));
  return { expanded, toggle, setExpanded };
}
