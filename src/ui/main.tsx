// Renderer entry point: mounts <App/> and installs the two window-level
// affordances that must exist before (and regardless of) React rendering.

import type { AppState } from "../shared/types";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { debugInjector } from "./debug";

// Standalone preview (no preload bridge): there is no vibrancy material
// behind the transparent page, so opt into the plain fallback background.
if (!window.majordomo) {
  document.body.classList.add("no-bridge");
}

// Debug escape hatch for visual checks (e.g. injecting a fabricated inbox
// via CDP). Display-only and renderer-local: it feeds the normal render path
// and cannot reach the main process, so it is harmless if it exists in prod.
interface DebugWindow {
  __debugSetState?: (state: AppState) => void;
}
(window as unknown as DebugWindow).__debugSetState = (state: AppState): void => {
  debugInjector.current?.(state);
};

const rootEl = document.getElementById("root");
if (!rootEl) {
  throw new Error("Renderer shell is missing the #root element");
}
createRoot(rootEl).render(<App />);
