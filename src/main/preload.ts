import { contextBridge, ipcRenderer } from "electron";
import type { IpcRendererEvent } from "electron";
import { IPC } from "../shared/ipc";
import type { MajordomoApi } from "../shared/ipc";
import type { AccountConfig, AppState, ProviderId } from "../shared/types";

const api: MajordomoApi = {
  getState: () => ipcRenderer.invoke(IPC.getState),
  connectAccount: (provider: ProviderId, config: AccountConfig) =>
    ipcRenderer.invoke(IPC.connectAccount, provider, config),
  disconnectAccount: (provider: ProviderId) => ipcRenderer.invoke(IPC.disconnectAccount, provider),
  openItem: (id: string) => ipcRenderer.invoke(IPC.openItem, id),
  markAllRead: () => ipcRenderer.invoke(IPC.markAllRead),
  refresh: () => ipcRenderer.invoke(IPC.refresh),
  onStateUpdated: (cb: (state: AppState) => void) => {
    const listener = (_event: IpcRendererEvent, state: AppState) => cb(state);
    ipcRenderer.on(IPC.stateUpdated, listener);
    return () => ipcRenderer.removeListener(IPC.stateUpdated, listener);
  },
};

contextBridge.exposeInMainWorld("majordomo", api);
