// Debug escape hatch shared between main.tsx (which owns the window global)
// and useAppState (which registers the live React setter). Display-only and
// renderer-local: injected state feeds the normal render path and cannot
// reach the main process, so it is harmless if it exists in prod.

import type { AppState } from "../shared/types";

export const debugInjector: { current: ((state: AppState) => void) | null } = {
  current: null,
};
