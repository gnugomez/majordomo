import { app, ipcMain, systemPreferences } from "electron";
import { IPC } from "../shared/ipc";
import type { AccountConfig, AppState, ProviderId } from "../shared/types";
import { createStore } from "./store";
import { createSyncEngine } from "./sync";
import { createTray } from "./tray";
import { createPopover, showPopover, togglePopover } from "./window";

// Keep one identity (userData dir, safeStorage keychain entry) between
// `electron .` in development and the packaged Majordomo.app.
app.setName("Majordomo");

// Point at a scratch profile (own store, own single-instance lock) so a dev
// build can run alongside the installed app.
if (process.env.MAJORDOMO_USERDATA) {
  app.setPath("userData", process.env.MAJORDOMO_USERDATA);
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  // Menu-bar app: stay alive when every window is closed or hidden.
  app.on("window-all-closed", () => {});

  void app.whenReady().then(() => {
    app.dock?.hide();

    const store = createStore();
    const win = createPopover();
    const tray = createTray({
      onToggle: (bounds) => togglePopover(win, bounds),
      onOpen: (bounds) => showPopover(win, bounds),
      onRefresh: () => void engine.syncNow(),
      onQuit: () => app.quit(),
    });
    const engine = createSyncEngine(store, (state: AppState) => {
      tray.setDot(state.items.some((item) => item.isMention && !item.read));
      if (!win.isDestroyed()) win.webContents.send(IPC.stateUpdated, state);
    });

    ipcMain.handle(IPC.getState, () => engine.getState());
    ipcMain.handle(IPC.connectAccount, (_event, provider: ProviderId, config: AccountConfig) =>
      engine.connectAccount(provider, config),
    );
    ipcMain.handle(IPC.disconnectAccount, (_event, provider: ProviderId) =>
      engine.disconnectAccount(provider),
    );
    ipcMain.handle(IPC.openItem, (_event, id: string) => engine.openItem(id));
    ipcMain.handle(IPC.markAllRead, () => engine.markAllRead());
    ipcMain.handle(IPC.refresh, () => engine.syncNow());
    ipcMain.handle(IPC.setLaunchAtLogin, (_event, enabled: boolean) => {
      app.setLoginItemSettings({ openAtLogin: enabled });
      engine.updateChrome({ launchAtLogin: app.getLoginItemSettings().openAtLogin });
    });

    // getAccentColor returns "rrggbbaa"; "multicolor" accent returns "".
    const readAccent = (): string | null => {
      try {
        const raw = systemPreferences.getAccentColor();
        return raw.length >= 6 ? `#${raw.slice(0, 6)}` : null;
      } catch {
        return null;
      }
    };
    engine.updateChrome({
      accentColor: readAccent(),
      launchAtLogin: app.getLoginItemSettings().openAtLogin,
    });
    systemPreferences.subscribeNotification("AppleColorPreferencesChangedNotification", () =>
      engine.updateChrome({ accentColor: readAccent() }),
    );

    app.on("second-instance", () => showPopover(win, tray.bounds()));

    engine.start();
  });
}
