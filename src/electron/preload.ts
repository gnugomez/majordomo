import type { IpcRendererEvent } from "electron";
import type { MajordomoApi } from "../shared/ipc";
import type { AccountConfig, AppState, ProviderId } from "../shared/types";
import { contextBridge, ipcRenderer } from "electron";
import { IPC } from "../shared/ipc";

const api: MajordomoApi = {
  getState: () => ipcRenderer.invoke(IPC.getState),
  connectAccount: (provider: ProviderId, config: AccountConfig) =>
    ipcRenderer.invoke(IPC.connectAccount, provider, config),
  disconnectAccount: (provider: ProviderId) => ipcRenderer.invoke(IPC.disconnectAccount, provider),
  openItem: (id: string) => ipcRenderer.invoke(IPC.openItem, id),
  markAllRead: () => ipcRenderer.invoke(IPC.markAllRead),
  refresh: () => ipcRenderer.invoke(IPC.refresh),
  setLaunchAtLogin: (enabled) => ipcRenderer.invoke(IPC.setLaunchAtLogin, enabled),
  setGlassEnabled: (enabled) => ipcRenderer.invoke(IPC.setGlassEnabled, enabled),
  setPopoverHeight: (px) => ipcRenderer.invoke(IPC.setPopoverHeight, px),
  openMainWindow: () => ipcRenderer.invoke(IPC.openMainWindow),
  onStateUpdated: (cb: (state: AppState) => void) => {
    const listener = (_event: IpcRendererEvent, state: AppState) => cb(state);
    ipcRenderer.on(IPC.stateUpdated, listener);
    return () => ipcRenderer.removeListener(IPC.stateUpdated, listener);
  },
  onPopoverVisibility: (cb: (visible: boolean) => void) => {
    const listener = (_event: IpcRendererEvent, visible: boolean) => cb(visible);
    ipcRenderer.on(IPC.popoverVisibility, listener);
    return () => ipcRenderer.removeListener(IPC.popoverVisibility, listener);
  },
};

contextBridge.exposeInMainWorld("majordomo", api);
