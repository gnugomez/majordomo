import { app, safeStorage } from "electron";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import type { AccountConfig, ProviderId } from "../shared/types";
import type { FetchedItem } from "../providers/types";

// JSON persistence for account configs (token encrypted via safeStorage when
// available), read/seen item ids, and the cached inbox items.

const SEEN_IDS_CAP = 2000;

interface StoredAccount {
  /** Base64 of the safeStorage-encrypted token, or the plaintext token. */
  token: string;
  tokenEncrypted: boolean;
  baseUrl?: string;
  username?: string;
}

interface StoreFile {
  accounts: Partial<Record<ProviderId, StoredAccount>>;
  readIds: string[];
  /** Ordered oldest → newest, capped at SEEN_IDS_CAP. */
  seenIds: string[];
  cachedItems: FetchedItem[];
}

export interface StoredAccountInfo {
  config: AccountConfig;
  username?: string;
}

export interface Store {
  getAccount(provider: ProviderId): StoredAccountInfo | undefined;
  setAccount(provider: ProviderId, config: AccountConfig, username: string): void;
  deleteAccount(provider: ProviderId): void;
  getReadIds(): ReadonlySet<string>;
  addReadIds(ids: string[]): void;
  getSeenIds(): ReadonlySet<string>;
  addSeenIds(ids: string[]): void;
  getCachedItems(): FetchedItem[];
  setCachedItems(items: FetchedItem[]): void;
}

export function createStore(): Store {
  const file = join(app.getPath("userData"), "majordomo.json");

  let data: StoreFile = { accounts: {}, readIds: [], seenIds: [], cachedItems: [] };
  try {
    const parsed = JSON.parse(readFileSync(file, "utf8")) as Partial<StoreFile>;
    data = {
      accounts: parsed.accounts && typeof parsed.accounts === "object" ? parsed.accounts : {},
      readIds: Array.isArray(parsed.readIds) ? parsed.readIds : [],
      seenIds: Array.isArray(parsed.seenIds) ? parsed.seenIds : [],
      cachedItems: Array.isArray(parsed.cachedItems) ? parsed.cachedItems : [],
    };
  } catch {
    // Missing or corrupt file — start fresh.
  }

  const readIds = new Set(data.readIds);
  const seenIds = new Set(data.seenIds);
  data.seenIds = [...seenIds];

  function save(): void {
    data.readIds = [...readIds];
    try {
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, JSON.stringify(data));
    } catch (err) {
      console.error("majordomo: failed to save store:", err);
    }
  }

  function decodeToken(stored: StoredAccount): string | undefined {
    if (!stored.tokenEncrypted) return stored.token;
    try {
      return safeStorage.decryptString(Buffer.from(stored.token, "base64"));
    } catch {
      return undefined;
    }
  }

  return {
    getAccount(provider) {
      const stored = data.accounts[provider];
      if (!stored) return undefined;
      const token = decodeToken(stored);
      if (token === undefined) return undefined;
      return { config: { token, baseUrl: stored.baseUrl }, username: stored.username };
    },

    setAccount(provider, config, username) {
      const encrypt = safeStorage.isEncryptionAvailable();
      data.accounts[provider] = {
        token: encrypt ? safeStorage.encryptString(config.token).toString("base64") : config.token,
        tokenEncrypted: encrypt,
        baseUrl: config.baseUrl,
        username,
      };
      save();
    },

    deleteAccount(provider) {
      delete data.accounts[provider];
      save();
    },

    getReadIds() {
      return readIds;
    },

    addReadIds(ids) {
      for (const id of ids) readIds.add(id);
      save();
    },

    getSeenIds() {
      return seenIds;
    },

    addSeenIds(ids) {
      for (const id of ids) {
        if (!seenIds.has(id)) {
          seenIds.add(id);
          data.seenIds.push(id);
        }
      }
      const excess = data.seenIds.length - SEEN_IDS_CAP;
      if (excess > 0) {
        for (const dropped of data.seenIds.splice(0, excess)) seenIds.delete(dropped);
      }
      save();
    },

    getCachedItems() {
      return data.cachedItems;
    },

    setCachedItems(items) {
      data.cachedItems = items;
      save();
    },
  };
}
