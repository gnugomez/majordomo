import type { AccountConfig, AccountState, AppState, ProviderId } from "./types";

// IPC channel names. The preload script maps these onto the typed
// `window.majordomo` API below; the renderer never touches channels directly.
export const IPC = {
  /** invoke → AppState */
  getState: "state:get",
  /** main → renderer push, payload AppState */
  stateUpdated: "state:updated",
  /** invoke (provider: ProviderId, config: AccountConfig) → AccountState */
  connectAccount: "account:connect",
  /** invoke (provider: ProviderId) → void */
  disconnectAccount: "account:disconnect",
  /** invoke (id: string) → void — opens in browser and marks read */
  openItem: "item:open",
  /** invoke → void */
  markAllRead: "items:mark-all-read",
  /** invoke → void — triggers an immediate sync */
  refresh: "sync:refresh",
  /** invoke (enabled: boolean) → void — register/unregister as a login item */
  setLaunchAtLogin: "app:set-launch-at-login",
  /** invoke (enabled: boolean) → void — toggle the translucent background */
  setGlassEnabled: "app:set-glass-enabled",
  /**
   * invoke (px: number) → void — the renderer's content height; the window
   * resizes to hug it, like native menu extras (clamped to a max)
   */
  setPopoverHeight: "popover:set-content-height",
  /** main → renderer push, payload boolean — false when the popover is dismissed */
  popoverVisibility: "popover:visibility",
} as const;

/** Exposed by the preload script as `window.majordomo`. */
export interface MajordomoApi {
  getState: () => Promise<AppState>;
  connectAccount: (provider: ProviderId, config: AccountConfig) => Promise<AccountState>;
  disconnectAccount: (provider: ProviderId) => Promise<void>;
  openItem: (id: string) => Promise<void>;
  markAllRead: () => Promise<void>;
  refresh: () => Promise<void>;
  setLaunchAtLogin: (enabled: boolean) => Promise<void>;
  setGlassEnabled: (enabled: boolean) => Promise<void>;
  setPopoverHeight: (px: number) => Promise<void>;
  /** Returns an unsubscribe function. */
  onStateUpdated: (cb: (state: AppState) => void) => () => void;
  /** Returns an unsubscribe function. cb receives false when the popover is dismissed. */
  onPopoverVisibility: (cb: (visible: boolean) => void) => () => void;
}

declare global {
  interface Window {
    majordomo: MajordomoApi;
  }
}
