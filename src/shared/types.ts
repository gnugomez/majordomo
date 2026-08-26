// Shared domain types. Both the main process and the renderer import from
// here; nothing in this file may import from anywhere else in the app.

export type ProviderId = "github" | "gitlab";

export type ItemKind = "issue" | "pull" | "merge";

/** One row in the unified inbox. */
export interface InboxItem {
  /** Globally unique: `${provider}:${externalId}`. */
  id: string;
  provider: ProviderId;
  kind: ItemKind;
  title: string;
  /** e.g. "eclipse/jetty" — the project/repo the item belongs to. */
  repo: string;
  /** Web URL opened in the browser when the row is clicked. */
  url: string;
  /** Provider-native reason, e.g. "mention", "review_requested", "assigned". */
  reason: string;
  /** True for the "needs you" tier: mentions, direct addresses, review requests. */
  isMention: boolean;
  /** ISO 8601 timestamp of the last activity the provider reported. */
  updatedAt: string;
  read: boolean;
}

/** What the user supplies to connect a provider. */
export interface AccountConfig {
  token: string;
  /** Required for GitLab (self-hosted instance origin, e.g. "https://gitlab.example.com"). Unused for GitHub. */
  baseUrl?: string;
}

/** Connection status shown in the Accounts pane. */
export interface AccountState {
  provider: ProviderId;
  connected: boolean;
  username?: string;
  baseUrl?: string;
  /** Human-readable error from the last validation or sync attempt. */
  error?: string;
}

/** The full app state pushed to the renderer. */
export interface AppState {
  items: InboxItem[];
  accounts: AccountState[];
  /** ISO 8601, or null if no sync has completed yet. */
  lastSyncAt: string | null;
  syncing: boolean;
}

/** A fetched item is an InboxItem before local read-state is applied. */
export type FetchedItem = Omit<InboxItem, "read">;

/** Implemented once per provider, consumed by the main-process sync loop. */
export interface ProviderClient {
  id: ProviderId;
  /** Throws with a human-readable message on bad token/URL; returns the username on success. */
  validate(config: AccountConfig): Promise<{ username: string }>;
  /** Returns the current inbox for this provider. Throws with a human-readable message on failure. */
  fetchItems(config: AccountConfig): Promise<FetchedItem[]>;
}
