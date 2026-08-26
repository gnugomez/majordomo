// Header and inbox views. All user-supplied strings (titles, repos, errors)
// go through textContent; innerHTML is only ever fed the icon constants.

import type { AppState, InboxItem } from "../shared/types";
import { humanizeReason, relativeTime, syncedLabel } from "./format";
import { ICONS, kindIcon, providerIcon } from "./icons";

/** Tiny element factory. */
export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className = "",
  text = ""
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className) {
    node.className = className;
  }
  if (text) {
    node.textContent = text;
  }
  return node;
}

export function iconButton(icon: string, label: string, onClick: () => void): HTMLButtonElement {
  const btn = el("button", "icon-btn");
  btn.type = "button";
  btn.title = label;
  btn.setAttribute("aria-label", label);
  btn.innerHTML = icon;
  btn.addEventListener("click", onClick);
  return btn;
}

export interface HeaderRefs {
  root: HTMLElement;
  syncStatus: HTMLElement;
  refreshBtn: HTMLButtonElement;
  markAllReadBtn: HTMLButtonElement;
  settingsBtn: HTMLButtonElement;
}

export interface HeaderHandlers {
  onRefresh(): void;
  onMarkAllRead(): void;
  onOpenSettings(): void;
}

export function buildHeader(handlers: HeaderHandlers): HeaderRefs {
  const root = el("header", "header");
  const title = el("h1", "panel-title", "Majordomo");
  const syncStatus = el("div", "sync-status");
  syncStatus.setAttribute("aria-live", "polite");
  const refreshBtn = iconButton(ICONS.refresh, "Refresh now", handlers.onRefresh);
  const markAllReadBtn = iconButton(ICONS.markAllRead, "Mark all as read", handlers.onMarkAllRead);
  const settingsBtn = iconButton(ICONS.gear, "Settings", handlers.onOpenSettings);
  root.append(title, syncStatus, refreshBtn, markAllReadBtn, settingsBtn);
  return { root, syncStatus, refreshBtn, markAllReadBtn, settingsBtn };
}

export function updateSyncStatus(target: HTMLElement, state: AppState, now: number): void {
  if (state.syncing) {
    target.innerHTML = ICONS.spinner;
    target.append(el("span", "", "Syncing…"));
  } else {
    target.textContent = syncedLabel(state.lastSyncAt, now);
  }
}

export interface InboxHandlers {
  onOpenItem(id: string): void;
  onOpenSettings(): void;
  /** Fired after a disclosure header toggles; the owner re-renders the pane. */
  onToggleSection(): void;
}

function itemTime(iso: string): number {
  const t = Date.parse(iso);
  return Number.isNaN(t) ? 0 : t;
}

// ---------- Collapse state ----------
// Persisted per section in localStorage so it survives re-renders, state
// pushes, popover dismissal (which only resets the visible pane), and app
// restarts. Absent key = the section's own default.

const COLLAPSE_PREFIX = "collapse:";

function isCollapsed(id: string, defaultCollapsed: boolean): boolean {
  try {
    const stored = localStorage.getItem(COLLAPSE_PREFIX + id);
    if (stored === "1") {
      return true;
    }
    if (stored === "0") {
      return false;
    }
  } catch {
    // Storage unavailable: fall through to the default.
  }
  return defaultCollapsed;
}

function setCollapsed(id: string, collapsed: boolean): void {
  try {
    localStorage.setItem(COLLAPSE_PREFIX + id, collapsed ? "1" : "0");
  } catch {
    // Best-effort: the toggle still works for this render pass.
  }
}

function buildRow(item: InboxItem, now: number, onOpen: (id: string) => void): HTMLElement {
  const row = el("button", item.read ? "row" : "row unread");
  row.type = "button";
  row.dataset.id = item.id;
  row.title = item.title;

  // Circular provider badge, like the device/network circles in the system's
  // own menus: accent-filled while unread, translucent gray once read.
  const badge = el("span", "provider-badge");
  badge.innerHTML = providerIcon(item.provider);

  const content = el("span", "row-content");

  const line1 = el("span", "row-line1");
  const kind = el("span", "kind-icon");
  kind.innerHTML = kindIcon(item.kind);
  line1.append(kind, el("span", "row-title", item.title));

  const line2 = el("span", "row-line2");
  const meta = el("span", "row-meta");
  const time = el("span", "rel-time", relativeTime(item.updatedAt, now));
  time.dataset.ts = item.updatedAt;
  meta.append(el("span", "row-repo", item.repo), el("span", "row-sep", "·"), time);
  const capsule = el(
    "span",
    item.isMention ? "capsule mention" : "capsule",
    humanizeReason(item.reason)
  );
  line2.append(meta, capsule);

  content.append(line1, line2);
  row.append(badge, content);
  row.addEventListener("click", () => onOpen(item.id));
  return row;
}

interface SectionDef {
  /** Stable id, also the localStorage key suffix (e.g. "collapse:overview"). */
  id: string;
  label: string;
  items: InboxItem[];
  defaultCollapsed: boolean;
}

/** Collapsible section: a full-row disclosure header (caption, muted count,
    chevron) over the item rows. Collapsed sections render the header only. */
function buildDisclosureSection(
  def: SectionDef,
  now: number,
  handlers: InboxHandlers
): HTMLElement {
  const collapsed = isCollapsed(def.id, def.defaultCollapsed);
  const section = el("section", "section");

  const header = el("button", "section-header");
  header.type = "button";
  header.setAttribute("aria-expanded", collapsed ? "false" : "true");
  header.setAttribute("aria-controls", `rows-${def.id}`);
  header.append(el("span", "section-label", def.label));
  header.append(el("span", "section-count", String(def.items.length)));
  const chevron = el("span", "disclosure-chevron");
  chevron.innerHTML = ICONS.chevron;
  header.append(chevron);
  header.addEventListener("click", () => {
    setCollapsed(def.id, !collapsed);
    handlers.onToggleSection();
  });
  section.append(header);

  if (!collapsed) {
    const rows = el("div", "rows");
    rows.id = `rows-${def.id}`;
    for (const item of def.items) {
      rows.append(buildRow(item, now, handlers.onOpenItem));
    }
    section.append(rows);
  }
  return section;
}

function buildEmpty(
  icon: string,
  title: string,
  caption: string,
  action?: { label: string; onClick(): void }
): HTMLElement {
  const empty = el("div", "empty");
  const glyph = el("span");
  glyph.innerHTML = icon;
  empty.append(glyph, el("div", "empty-title", title), el("div", "empty-caption", caption));
  if (action) {
    const btn = el("button", "primary-btn", action.label);
    btn.type = "button";
    btn.addEventListener("click", action.onClick);
    empty.append(btn);
  }
  return empty;
}

export function renderInbox(
  container: HTMLElement,
  state: AppState,
  now: number,
  handlers: InboxHandlers
): void {
  container.replaceChildren();

  const anyConnected = state.accounts.some((a) => a.connected);
  if (!anyConnected) {
    container.append(
      buildEmpty(
        ICONS.inbox,
        "No accounts connected",
        "Connect GitHub or a self-hosted GitLab to see your mentions in one place.",
        { label: "Connect an account", onClick: handlers.onOpenSettings }
      )
    );
    return;
  }

  const items = [...state.items].sort((a, b) => itemTime(b.updatedAt) - itemTime(a.updatedAt));
  if (items.length === 0) {
    container.append(
      buildEmpty(
        ICONS.checkCircle,
        "You're all caught up",
        "Nothing needs your attention right now."
      )
    );
    return;
  }

  // "Overview" holds everything, newest first; the categories below re-show
  // the same items grouped. Categories are disjoint: review requests are
  // carved out first (both providers flag reason "review_requested" as a
  // mention, so a plain isMention filter would swallow them all), then
  // mentions, then the remainder splits by kind.
  const reviews = items.filter((i) => i.reason === "review_requested");
  const mentions = items.filter((i) => i.isMention && i.reason !== "review_requested");
  const rest = items.filter((i) => !i.isMention && i.reason !== "review_requested");
  const issues = rest.filter((i) => i.kind === "issue");
  const pulls = rest.filter((i) => i.kind === "pull" || i.kind === "merge");

  const sections: SectionDef[] = [
    { id: "overview", label: "Overview", items, defaultCollapsed: false },
    { id: "mentions", label: "Mentions", items: mentions, defaultCollapsed: true },
    { id: "reviews", label: "Review requests", items: reviews, defaultCollapsed: true },
    { id: "issues", label: "Issues", items: issues, defaultCollapsed: true },
    { id: "pulls", label: "Pull & merge requests", items: pulls, defaultCollapsed: true },
  ];

  for (const def of sections) {
    if (def.items.length > 0) {
      container.append(buildDisclosureSection(def, now, handlers));
    }
  }
}
