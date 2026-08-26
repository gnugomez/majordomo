// Renderer entry point. Owns the app state received from the main process,
// a little local UI state (which pane is open, which connects are in flight),
// and funnels everything through a single render(state) pass.

import type { AccountConfig, AccountState, AppState, ProviderId } from "../shared/types";
import type { MajordomoApi } from "../shared/ipc";
import { SettingsPane } from "./settings";
import { relativeTime } from "./format";
import { ICONS } from "./icons";
import { buildHeader, el, renderInbox, updateSyncStatus } from "./views";

// The preload script installs this; guard so a standalone preview of the raw
// HTML degrades to the empty state instead of throwing.
const api: MajordomoApi | undefined = window.majordomo;

type Pane = "inbox" | "settings";

interface UiState {
  pane: Pane;
  connecting: Record<ProviderId, boolean>;
}

let appState: AppState = {
  items: [],
  accounts: [],
  lastSyncAt: null,
  syncing: false,
  accentColor: null,
  launchAtLogin: false,
};
const uiState: UiState = {
  pane: "inbox",
  connecting: { github: false, gitlab: false },
};

const PROVIDER_NAMES: Record<ProviderId, string> = { github: "GitHub", gitlab: "GitLab" };

// ---------- Static shell (built once; render() only mutates content) ----------

const appRoot: HTMLElement = (() => {
  const node = document.getElementById("app");
  if (!node) {
    throw new Error("Renderer shell is missing the #app element");
  }
  return node;
})();

const header = buildHeader({
  onRefresh: handleRefresh,
  onMarkAllRead: handleMarkAllRead,
  // The gear toggles: pressing it again closes the settings pane.
  onOpenSettings: () => setPane(uiState.pane === "settings" ? "inbox" : "settings"),
});

const banner = el("div");
banner.id = "banner";
banner.hidden = true;
banner.innerHTML = ICONS.warning;
const bannerText = el("span", "banner-text");
banner.append(bannerText);

const content = el("div", "content");
const inboxPane = el("div", "pane");
inboxPane.id = "inbox";

const settingsPane = new SettingsPane({
  onConnect: (provider, config) => void handleConnect(provider, config),
  onDisconnect: (provider) => void handleDisconnect(provider),
  onToggleLaunchAtLogin: handleToggleLaunchAtLogin,
});

content.append(inboxPane, settingsPane.root);
appRoot.append(header.root, banner, content);

// ---------- Actions ----------

function setPane(pane: Pane): void {
  uiState.pane = pane;
  render();
}

function handleRefresh(): void {
  if (!appState.syncing) {
    // Show the spinner immediately; the pushed state is authoritative.
    appState = { ...appState, syncing: true };
    render();
  }
  void api?.refresh();
}

function handleMarkAllRead(): void {
  appState = {
    ...appState,
    items: appState.items.map((i) => (i.read ? i : { ...i, read: true })),
  };
  render();
  void api?.markAllRead();
}

function handleOpenItem(id: string): void {
  // Optimistically mark read; the main process does the same and pushes.
  appState = {
    ...appState,
    items: appState.items.map((i) => (i.id === id && !i.read ? { ...i, read: true } : i)),
  };
  render();
  void api?.openItem(id);
}

function mergeAccount(next: AccountState): void {
  const rest = appState.accounts.filter((a) => a.provider !== next.provider);
  appState = { ...appState, accounts: [...rest, next] };
}

async function handleConnect(provider: ProviderId, config: AccountConfig): Promise<void> {
  if (!api || uiState.connecting[provider]) {
    return;
  }
  uiState.connecting[provider] = true;
  render();
  try {
    const result = await api.connectAccount(provider, config);
    mergeAccount(result);
    if (result.connected) {
      settingsPane.clearToken(provider);
    }
  } catch (err) {
    mergeAccount({
      provider,
      connected: false,
      error: err instanceof Error ? err.message : String(err),
    });
  } finally {
    uiState.connecting[provider] = false;
    render();
  }
}

async function handleDisconnect(provider: ProviderId): Promise<void> {
  // Optimistic; the pushed state is authoritative.
  mergeAccount({ provider, connected: false });
  render();
  try {
    await api?.disconnectAccount(provider);
  } catch {
    // A state push will correct us if the disconnect didn't take.
  }
}

function handleToggleLaunchAtLogin(next: boolean): void {
  // Optimistic flip; the pushed state is authoritative.
  appState = { ...appState, launchAtLogin: next };
  render();
  void api?.setLaunchAtLogin(next);
}

// ---------- Rendering ----------

function updateBanner(): void {
  const errors = appState.accounts
    .filter((a) => a.connected && a.error)
    .map((a) => `${PROVIDER_NAMES[a.provider]}: ${a.error ?? ""}`);
  const show = errors.length > 0 && uiState.pane === "inbox";
  banner.hidden = !show;
  if (show) {
    const text = errors.join(" · ");
    bannerText.textContent = text;
    banner.title = text;
  }
}

function render(): void {
  const now = Date.now();

  // Follow the macOS system accent; the stylesheet's per-theme blues are the
  // fallback when the main process couldn't read it.
  if (appState.accentColor) {
    document.documentElement.style.setProperty("--accent", appState.accentColor);
  } else {
    document.documentElement.style.removeProperty("--accent");
  }

  updateSyncStatus(header.syncStatus, appState, now);
  header.refreshBtn.disabled = appState.syncing;
  header.markAllReadBtn.disabled = !appState.items.some((i) => !i.read);

  updateBanner();

  renderInbox(inboxPane, appState, now, {
    onOpenItem: handleOpenItem,
    onOpenSettings: () => setPane("settings"),
    // Collapse state lives in localStorage (written by the view); a plain
    // re-render picks it up.
    onToggleSection: render,
  });

  settingsPane.update(appState, uiState.connecting);

  const settingsOpen = uiState.pane === "settings";
  appRoot.classList.toggle("settings-open", settingsOpen);
  header.settingsBtn.classList.toggle("active", settingsOpen);
  settingsPane.root.setAttribute("aria-hidden", settingsOpen ? "false" : "true");
}

// Keep relative timestamps fresh without rebuilding the DOM (a full rebuild
// every 30s would drop hover states mid-pointing).
window.setInterval(() => {
  const now = Date.now();
  for (const node of document.querySelectorAll<HTMLElement>(".rel-time[data-ts]")) {
    node.textContent = relativeTime(node.dataset.ts ?? "", now);
  }
  updateSyncStatus(header.syncStatus, appState, now);
}, 30_000);

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && uiState.pane === "settings") {
    setPane("inbox");
  }
});

// The popover must always reopen on the inbox. The window is never actually
// hidden (it fades to opacity 0 so macOS can't play its window-show
// animation), so dismissal arrives as an explicit push from the main process.
// Resetting on dismiss (rather than on show) avoids any visible pane flash;
// form input values are left alone — only the pane switches.
window.majordomo?.onPopoverVisibility((visible) => {
  if (!visible && uiState.pane !== "inbox") {
    setPane("inbox");
  }
});

// Debug escape hatch for visual checks (e.g. injecting a fabricated inbox via
// CDP). Display-only and renderer-local: it feeds the normal render path and
// cannot reach the main process, so it is harmless if it exists in prod.
interface DebugWindow {
  __debugSetState?: (state: AppState) => void;
}
(window as unknown as DebugWindow).__debugSetState = (state: AppState): void => {
  appState = state;
  render();
};

// ---------- Boot ----------

async function init(): Promise<void> {
  if (!api) {
    // Standalone preview: no vibrancy material behind the transparent page,
    // so opt into the plain fallback background.
    document.body.classList.add("no-bridge");
    console.error("window.majordomo is not available; rendering empty state");
    render();
    return;
  }
  // Subscribe first so a push racing the initial getState() can't be lost;
  // if a push lands before getState() resolves, the push wins.
  let receivedPush = false;
  api.onStateUpdated((state) => {
    receivedPush = true;
    appState = state;
    render();
  });
  try {
    const initial = await api.getState();
    if (!receivedPush) {
      appState = initial;
    }
  } catch (err) {
    console.error("getState failed", err);
  }
  render();
}

// The main process focuses the window on every popover open, which lands
// keyboard focus on the first header button and paints a focus ring. Native
// menus open focus-clean; drop the ring unless focus is in a text field.
window.addEventListener("focus", () => {
  const active = document.activeElement;
  if (active instanceof HTMLElement && !(active instanceof HTMLInputElement)) {
    active.blur();
  }
});

void init();
