import { Notification, shell } from "electron";
import { createProviders } from "../providers";
import type {
  AccountConfig,
  AccountState,
  AppState,
  InboxItem,
  ProviderId,
} from "../shared/types";
import type { FetchedItem } from "../providers/types";
import type { Store } from "./store";

const SYNC_INTERVAL_MS = 60_000;

export interface SyncEngine {
  getState(): AppState;
  syncNow(): Promise<void>;
  connectAccount(provider: ProviderId, config: AccountConfig): Promise<AccountState>;
  disconnectAccount(provider: ProviderId): void;
  openItem(id: string): void;
  markAllRead(): void;
  /** Merge window-chrome facts (accent color, login item) into the state and push it. */
  updateChrome(chrome: Partial<AppChrome>): void;
  /** Kicks off the first sync and the 60s interval. */
  start(): void;
}

export interface AppChrome {
  accentColor: string | null;
  launchAtLogin: boolean;
  glassEnabled: boolean;
}

function errorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

export function createSyncEngine(store: Store, emit: (state: AppState) => void): SyncEngine {
  const providers = createProviders();
  const providerIds = Object.keys(providers) as ProviderId[];

  const accounts = new Map<ProviderId, AccountState>();
  for (const id of providerIds) {
    const stored = store.getAccount(id);
    accounts.set(
      id,
      stored
        ? { provider: id, connected: true, username: stored.username, baseUrl: stored.config.baseUrl }
        : { provider: id, connected: false },
    );
  }

  // Seed from the cache so the inbox isn't empty on relaunch before first sync.
  const itemsByProvider = new Map<ProviderId, FetchedItem[]>();
  for (const item of store.getCachedItems()) {
    const list = itemsByProvider.get(item.provider) ?? [];
    list.push(item);
    itemsByProvider.set(item.provider, list);
  }

  let lastSyncAt: string | null = null;
  let syncing = false;
  let inFlight: Promise<void> | null = null;
  const chrome: AppChrome = { accentColor: null, launchAtLogin: false, glassEnabled: false };

  function allFetchedItems(): FetchedItem[] {
    const all: FetchedItem[] = [];
    for (const list of itemsByProvider.values()) all.push(...list);
    return all;
  }

  function getState(): AppState {
    const readIds = store.getReadIds();
    const items: InboxItem[] = allFetchedItems().map((it) => ({
      ...it,
      read: readIds.has(it.id),
    }));
    items.sort((a, b) => {
      if (a.isMention !== b.isMention) return a.isMention ? -1 : 1;
      return a.updatedAt < b.updatedAt ? 1 : a.updatedAt > b.updatedAt ? -1 : 0;
    });
    return {
      items,
      accounts: providerIds.map((id) => ({ ...accounts.get(id)! })),
      lastSyncAt,
      syncing,
      accentColor: chrome.accentColor,
      launchAtLogin: chrome.launchAtLogin,
      platform: process.platform as AppState["platform"],
      glassEnabled: chrome.glassEnabled,
    };
  }

  function updateChrome(partial: Partial<AppChrome>): void {
    Object.assign(chrome, partial);
    emitState();
  }

  function emitState(): void {
    emit(getState());
  }

  function notify(item: FetchedItem): void {
    if (!Notification.isSupported()) return;
    const notification = new Notification({ title: item.repo, body: item.title });
    notification.on("click", () => {
      void shell.openExternal(item.url);
      store.addReadIds([item.id]);
      emitState();
    });
    notification.show();
  }

  async function doSync(): Promise<void> {
    syncing = true;
    emitState();

    // Very first sync ever: seed seenIds without notifying.
    const firstRun = store.getSeenIds().size === 0;
    const fetchedNow: FetchedItem[] = [];

    await Promise.all(
      providerIds.map(async (id) => {
        const stored = store.getAccount(id);
        if (!stored) return;
        const account = accounts.get(id)!;
        try {
          const items = await providers[id].fetchItems(stored.config);
          itemsByProvider.set(id, items);
          fetchedNow.push(...items);
          delete account.error;
        } catch (err) {
          // Keep this provider's previous items; just surface the error.
          account.error = errorMessage(err);
        }
      }),
    );

    if (!firstRun) {
      const seenIds = store.getSeenIds();
      for (const item of fetchedNow) {
        if (item.isMention && !seenIds.has(item.id)) notify(item);
      }
    }
    store.addSeenIds(fetchedNow.map((item) => item.id));
    store.setCachedItems(allFetchedItems());

    lastSyncAt = new Date().toISOString();
    syncing = false;
    emitState();
  }

  function syncNow(): Promise<void> {
    if (!inFlight) {
      inFlight = doSync()
        .catch((err) => {
          console.error("majordomo: sync failed:", err);
        })
        .finally(() => {
          inFlight = null;
        });
    }
    return inFlight;
  }

  return {
    getState,
    syncNow,
    updateChrome,

    async connectAccount(provider, config) {
      try {
        const { username } = await providers[provider].validate(config);
        store.setAccount(provider, config, username);
        const state: AccountState = { provider, connected: true, username, baseUrl: config.baseUrl };
        accounts.set(provider, state);
        emitState();
        void syncNow();
        return { ...state };
      } catch (err) {
        return { provider, connected: false, baseUrl: config.baseUrl, error: errorMessage(err) };
      }
    },

    disconnectAccount(provider) {
      store.deleteAccount(provider);
      itemsByProvider.delete(provider);
      store.setCachedItems(allFetchedItems());
      accounts.set(provider, { provider, connected: false });
      emitState();
    },

    openItem(id) {
      const item = allFetchedItems().find((it) => it.id === id);
      if (item) void shell.openExternal(item.url);
      store.addReadIds([id]);
      emitState();
    },

    markAllRead() {
      store.addReadIds(allFetchedItems().map((item) => item.id));
      emitState();
    },

    start() {
      setInterval(() => {
        void syncNow();
      }, SYNC_INTERVAL_MS);
      void syncNow();
    },
  };
}
