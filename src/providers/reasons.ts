// Provider vocabularies → the app's ItemReason. Each provider names the same
// events its own way (GitHub "assign", GitLab "assigned"), so the mapping
// lives here rather than leaking raw strings into the store and the UI.
// Anything a provider can report but the other has no equivalent for maps to
// "activity"; so does anything new either API starts sending.

import type { ItemReason, ProviderId } from "../shared/types";
import { ITEM_REASONS } from "../shared/types";

/** GitHub notification `reason` values. */
const GITHUB_REASONS: Record<string, ItemReason> = {
  mention: "mentioned",
  team_mention: "mentioned",
  review_requested: "review_requested",
  approval_requested: "approval_required",
  assign: "assigned",
  author: "author",
  comment: "commented",
  subscribed: "subscribed",
  manual: "subscribed",
};

/** GitLab todo `action_name` values. */
const GITLAB_REASONS: Record<string, ItemReason> = {
  mentioned: "mentioned",
  directly_addressed: "mentioned",
  review_requested: "review_requested",
  approval_required: "approval_required",
  assigned: "assigned",
  marked: "subscribed",
};

export function githubReason(raw: string): ItemReason {
  return GITHUB_REASONS[raw] ?? "activity";
}

export function gitlabReason(raw: string): ItemReason {
  return GITLAB_REASONS[raw] ?? "activity";
}

const KNOWN: ReadonlySet<string> = new Set(ITEM_REASONS);

/**
 * Maps a stored item's reason forward, for items written before a provider's
 * vocabulary was normalized. Values that are already ItemReasons pass through
 * untouched, so this is safe to run on every load.
 */
export function normalizeReason(provider: ProviderId, raw: string): ItemReason {
  if (KNOWN.has(raw)) {
    return raw as ItemReason;
  }
  return provider === "github" ? githubReason(raw) : gitlabReason(raw);
}

/**
 * The "needs you" tier — someone put this in front of you personally. Drives
 * the tray dot and the notification wording, so it deliberately excludes
 * "assigned": an assignment is a task, not an interruption.
 */
export function isMentionReason(reason: ItemReason): boolean {
  return reason === "mentioned" || reason === "review_requested";
}
