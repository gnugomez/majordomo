// Shared domain types. Both the main process and the renderer import from
// here; nothing in this file may import from anywhere else in the app.

export type ProviderId = "github" | "gitlab";

export type ItemKind = "issue" | "pull" | "merge";

/**
 * Why an item is in the inbox, normalized across providers: GitHub's
 * notification reasons and GitLab's todo actions name the same events
 * differently ("assign" vs "assigned"), and the app speaks one vocabulary.
 * Providers map their own strings onto this in src/providers/reasons.ts;
 * anything without a common equivalent lands on "activity".
 */
export const ITEM_REASONS = [
  "mentioned",
  "review_requested",
  "assigned",
  "approval_required",
  "author",
  "commented",
  "subscribed",
  "activity",
] as const;

export type ItemReason = typeof ITEM_REASONS[number];

/**
 * Upstream lifecycle state, when the provider can tell. Issues use
 * open/closed; PRs/MRs add merged and draft.
 */
export type ItemState = "open" | "closed" | "merged" | "draft";

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
  /** Why it is in the inbox, in the app's own vocabulary. */
  reason: ItemReason;
  /** True for the "needs you" tier: mentions, direct addresses, review requests. */
  isMention: boolean;
  /** ISO 8601 timestamp of the last activity the provider reported. */
  updatedAt: string;
  /** Absent when the provider couldn't determine it. */
  state?: ItemState;
  /** Login of whoever wrote the issue/PR/MR, when the provider knows it. */
  author?: string;
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
  /** The system accent color as #rrggbb, or null when unavailable. */
  accentColor: string | null;
  launchAtLogin: boolean;
  /** Host OS, so the UI can adapt (login-item support, wording). */
  platform: "darwin" | "win32" | "linux";
  /** Translucent background (Liquid Glass / acrylic / compositor blur). */
  glassEnabled: boolean;
}

// The provider contract (ProviderClient, FetchedItem) lives in
// src/providers/types.ts — the renderer never needs it.
