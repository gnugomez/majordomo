// Main-window pane widths, persisted in localStorage ("width:<id>") so a
// window the user has resized comes back the way they left it. Absent or
// unusable key = the pane's own default.

import { useRef, useState } from "react";

const WIDTH_PREFIX = "width:";

function readWidth(id: string, fallback: number): number {
  try {
    const stored = Number(localStorage.getItem(WIDTH_PREFIX + id));
    if (Number.isFinite(stored) && stored > 0) {
      return stored;
    }
  } catch {
    // Storage unavailable: fall through to the default.
  }
  return fallback;
}

export interface PaneWidth {
  width: number;
  /** During a drag: updates the layout without touching storage. */
  set: (next: number) => void;
  /** At the end of a drag: remembers where it was left. */
  commit: () => void;
}

export function usePaneWidth(id: string, fallback: number): PaneWidth {
  const [width, setWidth] = useState(() => readWidth(id, fallback));
  // A drag holds on to the object it started with, so commit() has to read
  // the live width through a stable ref rather than that render's closure.
  const latestRef = useRef(width);
  latestRef.current = width;
  return {
    width,
    set: (next) => {
      latestRef.current = next;
      setWidth(next);
    },
    commit: () => {
      try {
        localStorage.setItem(WIDTH_PREFIX + id, String(Math.round(latestRef.current)));
      } catch {
        // Best-effort: the drag still applied for this session.
      }
    },
  };
}
