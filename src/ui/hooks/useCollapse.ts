// Per-section collapse state, persisted in localStorage ("collapse:<id>")
// so it survives re-renders, state pushes, popover dismissal (which only
// resets the visible pane), and app restarts. Absent key = the section's
// own default.

import { useState } from "react";

const COLLAPSE_PREFIX = "collapse:";

function readCollapsed(id: string, defaultCollapsed: boolean): boolean {
  try {
    const stored = localStorage.getItem(COLLAPSE_PREFIX + id);
    if (stored === "1") {
      return true;
    }
    if (stored === "0") {
      return false;
    }
  } catch {
    // Storage unavailable: fall through to the default.
  }
  return defaultCollapsed;
}

function writeCollapsed(id: string, collapsed: boolean): void {
  try {
    localStorage.setItem(COLLAPSE_PREFIX + id, collapsed ? "1" : "0");
  } catch {
    // Best-effort: the toggle still works for this session.
  }
}

export function useCollapse(id: string, defaultCollapsed: boolean): [boolean, () => void] {
  const [collapsed, setCollapsed] = useState(() => readCollapsed(id, defaultCollapsed));
  const toggle = (): void => {
    const next = !collapsed;
    setCollapsed(next);
    writeCollapsed(id, next);
  };
  return [collapsed, toggle];
}
