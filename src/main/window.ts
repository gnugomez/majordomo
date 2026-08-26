import { BrowserWindow } from "electron";
import { join } from "node:path";
import type { Rectangle } from "electron";

const POPOVER_WIDTH = 380;
const POPOVER_HEIGHT = 540;
const TRAY_GAP = 4;

/** Creates the hidden popover window that anchors under the tray icon. */
export function createPopover(): BrowserWindow {
  const win = new BrowserWindow({
    width: POPOVER_WIDTH,
    height: POPOVER_HEIGHT,
    show: false,
    frame: false,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    webPreferences: {
      preload: join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });
  win.setAlwaysOnTop(true, "floating");
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.on("blur", () => win.hide());
  void win.loadFile(join(__dirname, "../renderer/index.html"));
  return win;
}

export function showPopover(win: BrowserWindow, trayBounds: Rectangle): void {
  const x = Math.round(trayBounds.x + trayBounds.width / 2 - POPOVER_WIDTH / 2);
  const y = Math.round(trayBounds.y + trayBounds.height + TRAY_GAP);
  win.setPosition(x, y, false);
  win.show();
  win.focus();
}

export function togglePopover(win: BrowserWindow, trayBounds: Rectangle): void {
  if (win.isVisible()) {
    win.hide();
  } else {
    showPopover(win, trayBounds);
  }
}
