import { app, safeStorage } from "electron";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import type { AccountConfig, ProviderId } from "../shared/types";
import type { FetchedItem } from "../providers/types";

// JSON persistence for account metadata, read/seen item ids, the cached inbox
// items, and preferences. Tokens live in the OS keychain (@napi-rs/keyring);
// where no keyring backend exists (e.g. Linux without a Secret Service) they
// stay in the JSON, safeStorage-encrypted when available.

const SEEN_IDS_CAP = 2000;

const KEYRING_SERVICE = "Majordomo";

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
  readIds: string[];
  /** Ordered oldest → newest, capped at SEEN_IDS_CAP. */
  seenIds: string[];
  cachedItems: FetchedItem[];
  /** Translucent background preference; absent → platform default. */
  glassEnabled?: boolean;
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
  /** undefined when the user never toggled it — use the platform default. */
  getGlassEnabled(): boolean | undefined;
  setGlassEnabled(enabled: boolean): void;
}

// --- OS keychain access ------------------------------------------------
// @napi-rs/keyring is a native module, resolved at runtime (esbuild leaves it
// external — same pattern as electron-liquid-glass in window.ts). Every call
// is wrapped: if there is no usable keyring backend, callers fall back to the
// safeStorage-in-JSON path.

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

  let data: StoreFile = { accounts: {}, readIds: [], seenIds: [], cachedItems: [] };
  try {
    const parsed = JSON.parse(readFileSync(file, "utf8")) as Partial<StoreFile>;
    data = {
      accounts: parsed.accounts && typeof parsed.accounts === "object" ? parsed.accounts : {},
      readIds: Array.isArray(parsed.readIds) ? parsed.readIds : [],
      seenIds: Array.isArray(parsed.seenIds) ? parsed.seenIds : [],
      cachedItems: Array.isArray(parsed.cachedItems) ? parsed.cachedItems : [],
      glassEnabled: typeof parsed.glassEnabled === "boolean" ? parsed.glassEnabled : undefined,
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
    if (stored.token === undefined) return undefined;
    if (!stored.tokenEncrypted) return stored.token;
    try {
      return safeStorage.decryptString(Buffer.from(stored.token, "base64"));
    } catch {
      return undefined;
    }
  }

  // Migrate JSON-stored tokens into the OS keychain. The token is stripped
  // from the JSON only after the keyring write was confirmed by a read-back;
  // on any failure it stays where it is, so a token is never lost.
  let migrated = false;
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
  if (migrated) save();

  return {
    getAccount(provider) {
      const stored = data.accounts[provider];
      if (!stored) return undefined;
      const token = keyringRead(provider) ?? decodeToken(stored);
      if (token === undefined) return undefined;
      return { config: { token, baseUrl: stored.baseUrl }, username: stored.username };
    },

    setAccount(provider, config, username) {
      const account: StoredAccount = { baseUrl: config.baseUrl, username };
      if (!keyringWrite(provider, config.token)) {
        const encrypt = safeStorage.isEncryptionAvailable();
        account.token = encrypt
          ? safeStorage.encryptString(config.token).toString("base64")
          : config.token;
        account.tokenEncrypted = encrypt;
      }
      data.accounts[provider] = account;
      save();
    },

    deleteAccount(provider) {
      keyringDelete(provider);
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

    getGlassEnabled() {
      return data.glassEnabled;
    },

    setGlassEnabled(enabled) {
      data.glassEnabled = enabled;
      save();
    },
  };
}
