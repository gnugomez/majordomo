// Presentation rules an item's kind and state map to, shared by the popover
// row and the main window's list/preview so both speak the same language.

import type { InboxItem, ItemState } from "../../shared/types";

/**
 * A merged/closed/draft PR or MR shows its STATE in the capsule — the stored
 * reason ("review requested" on a merged PR) would be stale. Open or unknown
 * state keeps the reason capsule; issues always keep it (their state shows
 * via the icon alone).
 */
export function stateCapsule(item: InboxItem): ItemState | null {
  const isPullLike = item.kind === "pull" || item.kind === "merge";
  return isPullLike && item.state && item.state !== "open" ? item.state : null;
}

/**
 * State color class for the kind glyph; no state keeps the muted look.
 * GitHub renders completed issues purple, not red — only closed PRs/MRs
 * are red.
 */
export function kindIconClass(item: InboxItem): string {
  if (!item.state) {
    return "kind-icon";
  }
  return item.state === "closed" && item.kind === "issue"
    ? "kind-icon state-closed-issue"
    : `kind-icon state-${item.state}`;
}
