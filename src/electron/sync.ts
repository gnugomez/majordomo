import { Notification, shell } from "electron";
import { createProviders } from "../providers";
import type {
  AccountConfig,
  AccountState,
  AppState,
  InboxItem,
  ProviderId,
} from "../shared/types";
import type { FetchedItem, ProviderClient } from "../providers/types";
import type { Store, StoredItem } from "./store";

const SYNC_INTERVAL_MS = 60_000;

/** Notification-title fallback for items without a repo (a GitLab todo may
 * carry no project). Mirrors the display names in src/ui/components/Banner.tsx
 * — the renderer never sees this copy. */
const PROVIDER_NAMES: Record<ProviderId, string> = { github: "GitHub", gitlab: "GitLab" };

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

export function createSyncEngine(
  store: Store,
  emit: (state: AppState) => void,
  // Injectable for tests; the app uses the real registry.
  providers: Record<ProviderId, ProviderClient> = createProviders(),
): SyncEngine {
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

  let lastSyncAt: string | null = null;
  let syncing = false;
  let inFlight: Promise<void> | null = null;
  const chrome: AppChrome = { accentColor: null, launchAtLogin: false, glassEnabled: false };

  function toInboxItem(stored: StoredItem): InboxItem {
    const { firstSeenAt: _first, lastSeenUpstreamAt: _last, ...item } = stored;
    return item;
  }

  function getState(): AppState {
    const items = store.getItems().map(toInboxItem);
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

  // Strong references to shown notifications: Electron only delivers the
  // "click" event while the Notification object is alive, and a local that
  // goes out of scope gets garbage-collected — silently dropping clicks.
  const liveNotifications = new Set<Notification>();

  function notify(item: FetchedItem): void {
    if (!Notification.isSupported()) return;
    const notification = new Notification({
      title: item.repo || PROVIDER_NAMES[item.provider],
      body: item.title,
    });
    const release = () => liveNotifications.delete(notification);
    notification.on("click", () => {
      void shell.openExternal(item.url);
      store.markRead([item.id]);
      emitState();
      release();
    });
    notification.on("close", release);
    liveNotifications.add(notification);
    notification.show();
  }

  async function doSync(): Promise<void> {
    syncing = true;
    emitState();

    // Very first sync ever (empty collection): seed without notifying.
    const firstRun = store.getItems().length === 0;
    const newIds: string[] = [];

    await Promise.all(
      providerIds.map(async (id) => {
        const stored = store.getAccount(id);
        if (!stored) return;
        const account = accounts.get(id)!;
        try {
          const { items: fetched, complete } = await providers[id].fetchItems(stored.config);
          // Disconnected while the fetch was in flight: upserting now would
          // resurrect the items deleteProviderItems just removed — as
          // unread orphans nothing would ever prune.
          if (!store.getAccount(id)) return;
          delete account.error;

          // Reconcile, never replace: the collection is the app's own.
          newIds.push(...store.upsertItems(fetched));

          // Items upstream stopped returning (GitHub's /notifications only
          // lists unread threads, for one) were handled there: mark them
          // read locally. Only a complete fetch proves absence — a capped
          // one can't say whether an item is gone or just beyond the cap.
          if (complete) {
            const fetchedIds = new Set(fetched.map((item) => item.id));
            const absent = store
              .getItems()
              .filter((item) => item.provider === id && !item.read && !fetchedIds.has(item.id))
              .map((item) => item.id);
            if (absent.length > 0) store.markRead(absent);
          }
        } catch (err) {
          // Keep this provider's items untouched; just surface the error —
          // unless the account was disconnected mid-fetch.
          if (!store.getAccount(id)) return;
          account.error = errorMessage(err);
        }
      }),
    );

    if (!firstRun && newIds.length > 0) {
      const byId = new Map(store.getItems().map((item) => [item.id, item]));
      for (const id of newIds) {
        const item = byId.get(id);
        // Items that arrive already handled upstream don't deserve a ping.
        if (item?.isMention && !item.read) notify(item);
      }
    }

    store.prune();

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
        const state: AccountState = {
          provider,
          connected: false,
          baseUrl: config.baseUrl,
          error: errorMessage(err),
        };
        // Recorded, not just returned: state pushes rebuild the accounts
        // list from this map, and one lands within a minute (the sync
        // interval) — an unrecorded error would vanish mid-read. It clears
        // on the next attempt or disconnect.
        accounts.set(provider, state);
        return { ...state };
      }
    },

    disconnectAccount(provider) {
      store.deleteAccount(provider);
      store.deleteProviderItems(provider);
      accounts.set(provider, { provider, connected: false });
      emitState();
    },

    openItem(id) {
      const item = store.getItems().find((it) => it.id === id);
      if (!item) return;
      void shell.openExternal(item.url);
      store.markRead([id]);
      emitState();
    },

    markAllRead() {
      store.markAllRead();
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
