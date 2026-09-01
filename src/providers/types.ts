// The provider contract. A provider turns one account's remote inbox into
// the app's uniform item shape; the sync engine consumes nothing else.
// Implementations live in this directory and are registered in index.ts.

import type { AccountConfig, InboxItem } from "../shared/types";

/** What a provider fetches: an InboxItem before local read-state is applied. */
export type FetchedItem = Omit<InboxItem, "read"> & {
  /**
   * True when the provider reports the user already handled this upstream
   * (read notification thread, done todo). Consumed at upsert time to mark
   * the local item read; never stored. Absent means "unknown/unread".
   */
  upstreamRead?: boolean;
};

/**
 * Implemented once per provider.
 *
 * Rules every implementation must follow:
 * - `validate` and `fetchItems` throw `Error`s with human-readable messages —
 *   the strings surface verbatim in the UI's Accounts pane.
 * - One malformed remote entry must never fail the whole fetch: skip it.
 * - No sorting — ordering is the sync engine's concern.
 * - `id` is globally unique as `${provider}:${externalId}` and stable across
 *   fetches (it is the dedup and read-state key).
 */
export interface ProviderClient {
  id: InboxItem["provider"];
  /** Checks the credentials; returns the account's username on success. */
  validate: (config: AccountConfig) => Promise<{ username: string }>;
  /** Returns the account's current inbox. */
  fetchItems: (config: AccountConfig) => Promise<FetchResult>;
}

/** What fetchItems returns. */
export interface FetchResult {
  items: FetchedItem[];
  /**
   * True when no page cap truncated the authoritative list — an item's
   * absence from a complete fetch proves the user handled it upstream, so
   * the sync engine marks it read. A capped fetch proves nothing.
   */
  complete: boolean;
}
