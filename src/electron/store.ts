import { app, safeStorage } from "electron";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import type { AccountConfig, ProviderId } from "../shared/types";
import type { FetchedItem } from "../providers/types";

// JSON persistence for account metadata, the app's own persistent item
// collection (upstream disappearance is a read signal, never a delete — see
// sync.ts), and preferences. Tokens live in the OS keychain
// (@napi-rs/keyring); where no keyring backend exists (e.g. Linux without a
// Secret Service) they stay in the JSON, safeStorage-encrypted when available.

const KEYRING_SERVICE = "Majordomo";

/** Read items vanish this long after upstream last mentioned them. */
const RETAIN_READ_MS = 30 * 24 * 60 * 60 * 1000;
/** Hard cap on the collection; oldest (read first) beyond it are dropped. */
const ITEMS_CAP = 500;

/** A FetchedItem the app has adopted into its own collection. The transient
 * upstreamRead signal is consumed at upsert and never persisted. */
export interface StoredItem extends Omit<FetchedItem, "upstreamRead"> {
  read: boolean;
  /** ISO 8601 — when this item first entered the collection. */
  firstSeenAt: string;
  /** ISO 8601 — the last sync in which upstream still returned the item. */
  lastSeenUpstreamAt: string;
}

interface StoredAccount {
  /** Base64 of the safeStorage-encrypted token, or the plaintext token.
   * Absent when the token lives in the OS keychain instead. */
  token?: string;
  tokenEncrypted?: boolean;
  baseUrl?: string;
  username?: string;
}

interface StoreFile {
  accounts: Partial<Record<ProviderId, StoredAccount>>;
  items: Record<string, StoredItem>;
  /** Translucent background preference; absent → platform default. */
  glassEnabled?: boolean;
}

/** Pre-collection format, folded into `items` on first load. */
interface LegacyStoreFile {
  readIds?: string[];
  seenIds?: string[];
  cachedItems?: FetchedItem[];
}

export interface StoredAccountInfo {
  config: AccountConfig;
  username?: string;
}

export interface Store {
  getAccount(provider: ProviderId): StoredAccountInfo | undefined;
  setAccount(provider: ProviderId, config: AccountConfig, username: string): void;
  deleteAccount(provider: ProviderId): void;
  getItems(): StoredItem[];
  /** Adopts new items (unread) and refreshes known ones (fields updated,
   * lastSeenUpstreamAt bumped, local read preserved). Returns the ids that
   * were new to the collection. */
  upsertItems(items: FetchedItem[]): string[];
  markRead(ids: string[]): void;
  markAllRead(): void;
  /** Removes a disconnected provider's items immediately. */
  deleteProviderItems(provider: ProviderId): void;
  /** Retention: drops read items unseen upstream for 30 days, then enforces
   * the 500-item cap (oldest by updatedAt go first, read before unread). */
  prune(): void;
  /** undefined when the user never toggled it — use the platform default. */
  getGlassEnabled(): boolean | undefined;
  setGlassEnabled(enabled: boolean): void;
}

// --- OS keychain access ------------------------------------------------
// @napi-rs/keyring is a native module, resolved at runtime (esbuild leaves it
// external — same pattern as electron-liquid-glass in window.ts). Every call
// is wrapped: if there is no usable keyring backend, callers fall back to the
// safeStorage-in-JSON path.
//
// The keyring is only used on Windows/Linux. On macOS, keychain item ACLs
// pin "Always Allow" to the exact build (its code hash) for apps without an
// Apple-issued certificate, so every rebuild re-prompts — safeStorage
// (Chromium Safe Storage, still Keychain-derived encryption) is prompt-free
// across rebuilds and is what macOS uses instead.
const USE_KEYRING = process.platform !== "darwin";

interface KeyringEntry {
  setPassword(password: string): void;
  getPassword(): string | null;
  deletePassword(): boolean;
}
type KeyringEntryCtor = new (service: string, username: string) => KeyringEntry;

let entryCtor: KeyringEntryCtor | null | undefined;

function keyringEntry(provider: ProviderId): KeyringEntry | null {
  if (entryCtor === undefined) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      entryCtor = (require("@napi-rs/keyring") as { Entry: KeyringEntryCtor }).Entry;
    } catch (err) {
      console.error("majordomo: OS keyring unavailable, tokens stay in the JSON store:", err);
      entryCtor = null;
    }
  }
  if (!entryCtor) return null;
  try {
    return new entryCtor(KEYRING_SERVICE, `${provider}-token`);
  } catch {
    return null;
  }
}

function keyringRead(provider: ProviderId): string | undefined {
  try {
    return keyringEntry(provider)?.getPassword() ?? undefined;
  } catch {
    // NoEntry, locked keyring, no backend — treat all as "not there".
    return undefined;
  }
}

/** Writes the token and confirms it by reading it back. */
function keyringWrite(provider: ProviderId, token: string): boolean {
  try {
    const entry = keyringEntry(provider);
    if (!entry) return false;
    entry.setPassword(token);
    return entry.getPassword() === token;
  } catch {
    return false;
  }
}

function keyringDelete(provider: ProviderId): void {
  try {
    keyringEntry(provider)?.deletePassword();
  } catch {
    // Nothing stored, or no keyring — either way there is nothing to delete.
  }
}

export function createStore(): Store {
  const file = join(app.getPath("userData"), "majordomo.json");

  let data: StoreFile = { accounts: {}, items: {} };
  let migrated = false;
  try {
    const parsed = JSON.parse(readFileSync(file, "utf8")) as Partial<StoreFile> & LegacyStoreFile;
    let items: Record<string, StoredItem> = {};
    if (parsed.items && typeof parsed.items === "object") {
      items = parsed.items;
    } else if (Array.isArray(parsed.cachedItems)) {
      // Legacy format: fold cachedItems + readIds into the collection.
      // seenIds is dropped — "new to the collection" replaces it.
      const readIds = new Set(Array.isArray(parsed.readIds) ? parsed.readIds : []);
      const now = new Date().toISOString();
      for (const item of parsed.cachedItems) {
        items[item.id] = { ...item, read: readIds.has(item.id), firstSeenAt: now, lastSeenUpstreamAt: now };
      }
      migrated = true;
      console.log(`majordomo: migrated ${parsed.cachedItems.length} cached items to the collection`);
    }
    data = {
      accounts: parsed.accounts && typeof parsed.accounts === "object" ? parsed.accounts : {},
      items,
      glassEnabled: typeof parsed.glassEnabled === "boolean" ? parsed.glassEnabled : undefined,
    };
  } catch {
    // Missing or corrupt file — start fresh.
  }

  function save(): void {
    try {
      mkdirSync(dirname(file), { recursive: true });
      // data holds only the current shape, so legacy keys (readIds, seenIds,
      // cachedItems) are dropped from the JSON by this write.
      writeFileSync(file, JSON.stringify(data));
    } catch (err) {
      console.error("majordomo: failed to save store:", err);
    }
  }

  function decodeToken(stored: StoredAccount): string | undefined {
    if (stored.token === undefined) return undefined;
    if (!stored.tokenEncrypted) return stored.token;
    try {
      return safeStorage.decryptString(Buffer.from(stored.token, "base64"));
    } catch {
      return undefined;
    }
  }

  function encodeToken(stored: StoredAccount, token: string): void {
    const encrypt = safeStorage.isEncryptionAvailable();
    stored.token = encrypt ? safeStorage.encryptString(token).toString("base64") : token;
    stored.tokenEncrypted = encrypt;
  }

  if (USE_KEYRING) {
    // Migrate JSON-stored tokens into the OS keyring. The token is stripped
    // from the JSON only after the write was confirmed by a read-back; on
    // any failure it stays where it is, so a token is never lost.
    for (const [provider, stored] of Object.entries(data.accounts) as [
      ProviderId,
      StoredAccount,
    ][]) {
      if (stored.token === undefined) continue;
      const token = decodeToken(stored);
      if (token === undefined) continue;
      if (keyringWrite(provider, token)) {
        delete stored.token;
        delete stored.tokenEncrypted;
        migrated = true;
        console.log(`majordomo: migrated ${provider} token to the OS keychain`);
      }
    }
  } else {
    // macOS: tokens that a previous version put in the keychain move back
    // into safeStorage-encrypted JSON (one final access prompt, then never
    // again). The keychain entry is removed only after the JSON write.
    for (const [provider, stored] of Object.entries(data.accounts) as [
      ProviderId,
      StoredAccount,
    ][]) {
      if (stored.token !== undefined) continue;
      const token = keyringRead(provider);
      if (token === undefined) continue;
      encodeToken(stored, token);
      keyringDelete(provider);
      migrated = true;
      console.log(`majordomo: moved the ${provider} token back to encrypted storage`);
    }
  }
  if (migrated) save();

  // Tokens are resolved from the keychain at most once per run: every
  // keychain access can pop a macOS permission prompt (until the user picks
  // "Always Allow"), and the sync loop asks for the account every minute —
  // uncached, that turns one grudging "Allow" into a dialog per sync.
  const tokenCache = new Map<ProviderId, string>();

  return {
    getAccount(provider) {
      const stored = data.accounts[provider];
      if (!stored) return undefined;
      let token = tokenCache.get(provider);
      if (token === undefined) {
        token = (USE_KEYRING ? keyringRead(provider) : undefined) ?? decodeToken(stored);
        if (token === undefined) return undefined;
        tokenCache.set(provider, token);
      }
      return { config: { token, baseUrl: stored.baseUrl }, username: stored.username };
    },

    setAccount(provider, config, username) {
      const account: StoredAccount = { baseUrl: config.baseUrl, username };
      if (!USE_KEYRING || !keyringWrite(provider, config.token)) {
        encodeToken(account, config.token);
      }
      tokenCache.set(provider, config.token);
      data.accounts[provider] = account;
      save();
    },

    deleteAccount(provider) {
      if (USE_KEYRING) keyringDelete(provider);
      tokenCache.delete(provider);
      delete data.accounts[provider];
      save();
    },

    getItems() {
      return Object.values(data.items);
    },

    upsertItems(items) {
      if (items.length === 0) return [];
      const now = new Date().toISOString();
      const newIds: string[] = [];
      for (const { upstreamRead, ...item } of items) {
        // Local read state only ever moves toward read: the user reading it
        // here or upstream both count, and nothing un-reads an item.
        const existing = data.items[item.id];
        if (existing) {
          data.items[item.id] = {
            ...item,
            // Enriched fields can be absent on rounds where the provider
            // skipped the lookup — never forget what a prior sync learned.
            state: item.state ?? existing.state,
            author: item.author ?? existing.author,
            read: existing.read || upstreamRead === true,
            firstSeenAt: existing.firstSeenAt,
            lastSeenUpstreamAt: now,
          };
        } else {
          newIds.push(item.id);
          data.items[item.id] = {
            ...item,
            read: upstreamRead === true,
            firstSeenAt: now,
            lastSeenUpstreamAt: now,
          };
        }
      }
      save();
      return newIds;
    },

    markRead(ids) {
      let changed = false;
      for (const id of ids) {
        const item = data.items[id];
        if (item && !item.read) {
          item.read = true;
          changed = true;
        }
      }
      if (changed) save();
    },

    markAllRead() {
      let changed = false;
      for (const item of Object.values(data.items)) {
        if (!item.read) {
          item.read = true;
          changed = true;
        }
      }
      if (changed) save();
    },

    deleteProviderItems(provider) {
      let changed = false;
      for (const [id, item] of Object.entries(data.items)) {
        if (item.provider === provider) {
          delete data.items[id];
          changed = true;
        }
      }
      if (changed) save();
    },

    prune() {
      let changed = false;
      const cutoff = Date.now() - RETAIN_READ_MS;
      for (const [id, item] of Object.entries(data.items)) {
        if (item.read && Date.parse(item.lastSeenUpstreamAt) < cutoff) {
          delete data.items[id];
          changed = true;
        }
      }
      const all = Object.values(data.items);
      const excess = all.length - ITEMS_CAP;
      if (excess > 0) {
        all.sort((a, b) => {
          if (a.read !== b.read) return a.read ? -1 : 1;
          return a.updatedAt < b.updatedAt ? -1 : a.updatedAt > b.updatedAt ? 1 : 0;
        });
        for (const victim of all.slice(0, excess)) delete data.items[victim.id];
        changed = true;
      }
      if (changed) save();
    },

    getGlassEnabled() {
      return data.glassEnabled;
    },

    setGlassEnabled(enabled) {
      data.glassEnabled = enabled;
      save();
    },
  };
}
