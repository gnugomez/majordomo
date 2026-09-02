// How the inbox splits into named buckets. The popover renders them as
// collapsible sections, the main window as sidebar sources — same buckets,
// same labels, one definition.

import type { InboxItem } from "../../shared/types";

export type CategoryId = "recent" | "assigned" | "mentions" | "reviews" | "issues" | "pulls";

export interface Category {
  id: CategoryId;
  label: string;
  items: InboxItem[];
}

/** Reasons that get their own category, and so never fall through to a kind. */
const CLAIMED_REASONS = new Set<InboxItem["reason"]>([
  "assigned",
  "mentioned",
  "review_requested",
]);

/**
 * "Recent" holds everything, newest first; the categories below re-show the
 * same items grouped. They are disjoint, and the reason-named ones claim
 * their items first — so "Issues" and "Pull & merge requests" hold whatever
 * reached the inbox for some other reason (authored, commented, subscribed),
 * split by kind.
 */
export function categorize(items: InboxItem[]): Category[] {
  const byReason = (reason: InboxItem["reason"]): InboxItem[] =>
    items.filter((i) => i.reason === reason);
  const rest = items.filter(
    (i) => !CLAIMED_REASONS.has(i.reason),
  );
  return [
    { id: "recent", label: "Recent", items },
    { id: "assigned", label: "Assigned", items: byReason("assigned") },
    { id: "mentions", label: "Mentions", items: byReason("mentioned") },
    { id: "reviews", label: "Review requests", items: byReason("review_requested") },
    { id: "issues", label: "Issues", items: rest.filter((i) => i.kind === "issue") },
    {
      id: "pulls",
      label: "Pulls",
      items: rest.filter((i) => i.kind === "pull" || i.kind === "merge"),
    },
  ];
}

/** Newest activity first — the order every list in the app shows items in. */
export function byNewest(items: InboxItem[]): InboxItem[] {
  const time = (iso: string): number => {
    const t = Date.parse(iso);
    return Number.isNaN(t) ? 0 : t;
  };
  return [...items].sort((a, b) => time(b.updatedAt) - time(a.updatedAt));
}
