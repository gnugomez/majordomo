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
  accountsBtn: HTMLButtonElement;
}

export interface HeaderHandlers {
  onRefresh(): void;
  onMarkAllRead(): void;
  onToggleAccounts(): void;
}

export function buildHeader(handlers: HeaderHandlers): HeaderRefs {
  const root = el("header", "header");
  const title = el("h1", "app-title", "Majordomo");
  const syncStatus = el("div", "sync-status");
  syncStatus.setAttribute("aria-live", "polite");
  const refreshBtn = iconButton(ICONS.refresh, "Refresh now", handlers.onRefresh);
  const markAllReadBtn = iconButton(ICONS.markAllRead, "Mark all as read", handlers.onMarkAllRead);
  const accountsBtn = iconButton(ICONS.gear, "Accounts", handlers.onToggleAccounts);
  root.append(title, syncStatus, refreshBtn, markAllReadBtn, accountsBtn);
  return { root, syncStatus, refreshBtn, markAllReadBtn, accountsBtn };
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
  onOpenAccounts(): void;
}

function itemTime(iso: string): number {
  const t = Date.parse(iso);
  return Number.isNaN(t) ? 0 : t;
}

function buildRow(item: InboxItem, now: number, onOpen: (id: string) => void): HTMLElement {
  const row = el("button", item.read ? "row" : "row unread");
  row.type = "button";
  row.dataset.id = item.id;
  row.title = item.title;

  const dot = el("span", "unread-dot");

  const mark = el("span", "provider-mark");
  mark.innerHTML = providerIcon(item.provider);

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
  row.append(dot, mark, content);
  row.addEventListener("click", () => onOpen(item.id));
  return row;
}

function buildSection(
  label: string,
  items: InboxItem[],
  now: number,
  onOpen: (id: string) => void,
  emptyNote: string
): HTMLElement {
  const section = el("section", "section");
  section.append(el("h2", "section-title", label));
  if (items.length === 0) {
    section.append(el("p", "section-empty", emptyNote));
    return section;
  }
  const rows = el("div", "rows");
  for (const item of items) {
    rows.append(buildRow(item, now, onOpen));
  }
  section.append(rows);
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
        { label: "Connect an account", onClick: handlers.onOpenAccounts }
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

  const mentions = items.filter((i) => i.isMention);
  const rest = items.filter((i) => !i.isMention);

  container.append(
    buildSection("Mentions", mentions, now, handlers.onOpenItem, "No mentions right now.")
  );
  if (rest.length > 0) {
    container.append(buildSection("Everything else", rest, now, handlers.onOpenItem, ""));
  }
}
