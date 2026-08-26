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
} as const;

/** Exposed by the preload script as `window.majordomo`. */
export interface MajordomoApi {
  getState(): Promise<AppState>;
  connectAccount(provider: ProviderId, config: AccountConfig): Promise<AccountState>;
  disconnectAccount(provider: ProviderId): Promise<void>;
  openItem(id: string): Promise<void>;
  markAllRead(): Promise<void>;
  refresh(): Promise<void>;
  /** Returns an unsubscribe function. */
  onStateUpdated(cb: (state: AppState) => void): () => void;
}

declare global {
  interface Window {
    majordomo: MajordomoApi;
  }
}
