// Small formatting helpers for the renderer views.

/**
 * Compact relative time: "now", "5m", "3h", "2d", then a short date
 * ("Aug 12", with the year appended once it differs from the current one).
 */
export function relativeTime(iso: string, now: number = Date.now()): string {
  const then = Date.parse(iso);
  if (Number.isNaN(then)) {
    return "";
  }
  const seconds = Math.floor(Math.max(0, now - then) / 1000);
  if (seconds < 60) {
    return "now";
  }
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) {
    return `${minutes}m`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `${hours}h`;
  }
  const days = Math.floor(hours / 24);
  if (days < 7) {
    return `${days}d`;
  }
  const date = new Date(then);
  const options: Intl.DateTimeFormatOptions
    = date.getFullYear() === new Date(now).getFullYear()
      ? { month: "short", day: "numeric" }
      : { month: "short", day: "numeric", year: "numeric" };
  return date.toLocaleDateString(undefined, options);
}

/** "review_requested" → "review requested". */
export function humanizeReason(reason: string): string {
  return reason.replace(/_/g, " ");
}

/** Idle sync label for the header; the syncing case is handled by the caller. */
export function syncedLabel(lastSyncAt: string | null, now: number = Date.now()): string {
  if (!lastSyncAt) {
    return "Not synced yet";
  }
  const rel = relativeTime(lastSyncAt, now);
  if (rel === "now") {
    return "Synced just now";
  }
  if (/^\d/.test(rel)) {
    return `Synced ${rel} ago`;
  }
  return `Synced ${rel}`;
}
