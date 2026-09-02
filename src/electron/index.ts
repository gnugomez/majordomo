import type { AccountConfig, AppState, ProviderId } from "../shared/types";
import type { SyncEngine } from "./sync";
import process from "node:process";
import { app, BrowserWindow, ipcMain, systemPreferences } from "electron";
import squirrelStartup from "electron-squirrel-startup";
import { IPC } from "../shared/ipc";
import { openMainWindow, setMainWindowStore } from "./main-window";
import { createStore } from "./store";
import { createSyncEngine } from "./sync";
import { createTray } from "./tray";
import {
  createPopover,
  defaultGlassEnabled,
  hidePopover,
  resizePopover,
  showPopover,
  togglePopover,
} from "./window";

// Squirrel.Windows install/update/uninstall events relaunch the app with a
// --squirrel-* flag; the module creates/removes shortcuts and we must exit
// immediately without showing anything. No-op outside Windows.
if (squirrelStartup) {
  app.quit();
}

// Keep one identity (userData dir, safeStorage keychain entry) between
// `electron .` in development and the packaged Majordomo.app.
app.setName("Majordomo");

// Windows ties notifications (and taskbar grouping) to the AppUserModelID.
if (process.platform === "win32") {
  app.setAppUserModelId("dev.majordomo.app");
}

// Point at a scratch profile (own store, own single-instance lock) so a dev
// build can run alongside the installed app.
if (process.env.MAJORDOMO_USERDATA) {
  app.setPath("userData", process.env.MAJORDOMO_USERDATA);
}

// On Linux, setLoginItemSettings is a no-op and getLoginItemSettings can
// claim whatever it likes — report "not a login item" and change nothing.
const loginItemSupported = process.platform !== "linux";

/** The accent color as #rrggbb, or null when the OS doesn't expose one. */
function setupAccent(engine: SyncEngine): (source?: "boot" | "live") => void {
  if (process.platform === "darwin") {
    // getAccentColor is exact but frozen at its boot-time value (AppKit
    // caches controlAccentColor per process), while the AppleAccentColor
    // user default stays fresh. So boot reads the former, and every later
    // refresh maps the default through this palette (sampled from
    // getAccentColor itself, one process boot per value, on macOS 26).
    const ACCENT_HEX: Record<string, string> = {
      "-1": "#989898", // graphite
      "0": "#e0383e", // red
      "1": "#f7821b", // orange
      "2": "#ffc726", // yellow
      "3": "#62ba46", // green
      "4": "#007aff", // blue
      "5": "#953d96", // purple
      "6": "#f74f9e", // pink
    };
    const readAccentBoot = (): string | null => {
      try {
        const raw = systemPreferences.getAccentColor();
        return raw.length >= 6 ? `#${raw.slice(0, 6)}` : null;
      } catch {
        return null;
      }
    };
    // Absent key ("multicolour" or never set) → null → the renderer's
    // per-theme blue fallback.
    const readAccentDefault = (): string | null => {
      try {
        const raw = String(systemPreferences.getUserDefault("AppleAccentColor", "string"));
        return ACCENT_HEX[raw] ?? null;
      } catch {
        return null;
      }
    };
    let lastAccent: string | null = null;
    const refreshAccent = (source: "boot" | "live" = "live"): void => {
      const accent = source === "boot" ? readAccentBoot() : readAccentDefault();
      if (accent !== lastAccent) {
        lastAccent = accent;
        engine.updateChrome({ accentColor: accent });
      }
    };
    // Different macOS versions broadcast different names for an accent
    // change, and AppKit's cached controlAccentColor can lag the
    // notification — so listen broadly and re-read twice, and re-read on
    // every popover open (the only moment the accent is visible anyway).
    for (const name of [
      "AppleColorPreferencesChangedNotification",
      "AppleAquaColorVariantChanged",
      "AppleInterfaceThemeChangedNotification",
    ]) {
      systemPreferences.subscribeNotification(name, () => {
        setTimeout(refreshAccent, 150);
        setTimeout(refreshAccent, 1000);
      });
    }
    return refreshAccent;
  }

  if (process.platform === "win32") {
    // Windows exposes the accent directly (RGBA hex) and emits an event.
    const readAccent = (): string | null => {
      try {
        const raw = systemPreferences.getAccentColor();
        return raw.length >= 6 ? `#${raw.slice(0, 6)}` : null;
      } catch {
        return null;
      }
    };
    let lastAccent: string | null = null;
    const refreshAccent = (): void => {
      const accent = readAccent();
      if (accent !== lastAccent) {
        lastAccent = accent;
        engine.updateChrome({ accentColor: accent });
      }
    };
    systemPreferences.on("accent-color-changed", () => refreshAccent());
    return refreshAccent;
  }

  // Linux: no portable accent API — null keeps the renderer's fallback.
  return () => {};
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  // Menu-bar app: stay alive when every window is closed or hidden.
  app.on("window-all-closed", () => {});

  void app.whenReady().then(() => {
    app.dock?.hide();

    const store = createStore();
    setMainWindowStore(store);
    const win = createPopover();
    // The tray menu drives the engine (refresh) and the engine drives the
    // tray (unread dot) — a cycle, so both land in `let` bindings that the
    // callbacks close over and the assignments below fill in.
    let engine: SyncEngine;
    let refreshAccent: (source?: "boot" | "live") => void;
    const tray = createTray({
      onToggle: (bounds) => {
        refreshAccent();
        togglePopover(win, bounds);
      },
      onOpen: (bounds) => {
        refreshAccent();
        showPopover(win, bounds);
      },
      onRefresh: () => void engine.syncNow(),
      onQuit: () => app.quit(),
    });
    engine = createSyncEngine(store, (state: AppState) => {
      tray.setDot(state.items.some((item) => item.isMention && !item.read));
      // Every live window renders the same pushed state (popover + main).
      for (const target of BrowserWindow.getAllWindows()) {
        if (!target.isDestroyed() && !target.webContents.isDestroyed())
          target.webContents.send(IPC.stateUpdated, state);
      }
    });

    ipcMain.handle(IPC.getState, () => engine.getState());
    ipcMain.handle(IPC.connectAccount, (_event, provider: ProviderId, config: AccountConfig) =>
      engine.connectAccount(provider, config));
    ipcMain.handle(IPC.disconnectAccount, (_event, provider: ProviderId) =>
      engine.disconnectAccount(provider));
    ipcMain.handle(IPC.openItem, (_event, id: string) => engine.openItem(id));
    ipcMain.handle(IPC.markAllRead, () => engine.markAllRead());
    ipcMain.handle(IPC.refresh, () => engine.syncNow());
    ipcMain.handle(IPC.setLaunchAtLogin, (_event, enabled: boolean) => {
      if (!loginItemSupported)
        return;
      app.setLoginItemSettings({ openAtLogin: enabled });
      engine.updateChrome({ launchAtLogin: app.getLoginItemSettings().openAtLogin });
    });
    ipcMain.handle(IPC.setGlassEnabled, (_event, enabled: boolean) => {
      store.setGlassEnabled(enabled);
      engine.updateChrome({ glassEnabled: enabled });
    });
    ipcMain.handle(IPC.setPopoverHeight, (_event, px: number) => {
      if (Number.isFinite(px))
        resizePopover(win, px);
    });
    ipcMain.handle(IPC.openMainWindow, () => {
      // Opening a window steals focus (which would blur-hide the popover
      // anyway), but hide explicitly so dismissal never depends on timing.
      hidePopover(win);
      openMainWindow();
    });

    refreshAccent = setupAccent(engine);
    engine.updateChrome({
      launchAtLogin: loginItemSupported && app.getLoginItemSettings().openAtLogin,
      glassEnabled: store.getGlassEnabled() ?? defaultGlassEnabled(),
    });
    refreshAccent("boot");

    app.on("second-instance", () => showPopover(win, tray.bounds()));
    // macOS only: the Dock icon exists exactly while the main window is
    // open, so activation (Dock click, app switcher) refocuses it.
    app.on("activate", () => openMainWindow());

    engine.start();
  });
}
