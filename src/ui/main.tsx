// Renderer entry point: mounts the window's component tree and installs the
// two window-level affordances that must exist before (and regardless of)
// React rendering. One bundle serves both windows — the popover by default,
// the resizable main window when loaded with `?window=main`.

import type { AppState } from "../shared/types";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { debugInjector } from "./debug";
import { MainApp } from "./main-window/MainApp";

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
const isMainWindow = new URLSearchParams(window.location.search).get("window") === "main";
createRoot(rootEl).render(isMainWindow ? <MainApp /> : <App />);
