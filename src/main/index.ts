import { app, ipcMain } from "electron";
import { IPC } from "../shared/ipc";
import type { AccountConfig, AppState, ProviderId } from "../shared/types";
import { createStore } from "./store";
import { createSyncEngine } from "./sync";
import { createTray } from "./tray";
import { createPopover, showPopover, togglePopover } from "./window";

// Keep one identity (userData dir, safeStorage keychain entry) between
// `electron .` in development and the packaged Majordomo.app.
app.setName("Majordomo");

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

    app.on("second-instance", () => showPopover(win, tray.bounds()));

    engine.start();
  });
}
