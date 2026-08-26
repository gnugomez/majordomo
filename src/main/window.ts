import { BrowserWindow } from "electron";
import { join } from "node:path";
import type { Rectangle } from "electron";
import { IPC } from "../shared/ipc";

const POPOVER_WIDTH = 380;
const POPOVER_HEIGHT = 540;
const TRAY_GAP = 4;

// Plain show()/hide(). An always-ordered window driven by opacity (to dodge
// macOS's window-show animation) was tried and rolled back: with the Liquid
// Glass view attached, the compositor sometimes flashed the wrong background
// color on re-show.

/** Creates the popover window that anchors under the tray icon. */
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
    // Transparent window; the Liquid Glass view is attached behind the
    // page in applyGlass() once the renderer has loaded.
    transparent: true,
    webPreferences: {
      preload: join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });
  win.setAlwaysOnTop(true, "floating");
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.on("blur", () => hidePopover(win));
  win.webContents.once("did-finish-load", () => applyGlass(win));
  void win.loadFile(join(__dirname, "../renderer/index.html"));
  return win;
}

export const GLASS_CORNER_RADIUS = 16;

/** Attach the macOS 26 Liquid Glass material (NSGlassEffectView) behind the
 * page; fall back to the older frosted vibrancy where it's unavailable. */
function applyGlass(win: BrowserWindow): void {
  interface LiquidGlassApi {
    addView(handle: Buffer, options: { cornerRadius?: number; tintColor?: string; opaque?: boolean }): number;
  }
  try {
    // Native module, resolved at runtime (esbuild leaves it external).
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const mod = require("electron-liquid-glass") as LiquidGlassApi & { default?: LiquidGlassApi };
    const liquidGlass = mod.default ?? mod;
    liquidGlass.addView(win.getNativeWindowHandle(), {
      cornerRadius: GLASS_CORNER_RADIUS,
    });
  } catch (err) {
    console.error("majordomo: liquid glass unavailable, using vibrancy:", err);
    win.setVibrancy("menu");
  }
}

export function showPopover(win: BrowserWindow, trayBounds: Rectangle): void {
  const x = Math.round(trayBounds.x + trayBounds.width / 2 - POPOVER_WIDTH / 2);
  const y = Math.round(trayBounds.y + trayBounds.height + TRAY_GAP);
  win.setPosition(x, y, false);
  win.show();
  win.focus();
  win.webContents.send(IPC.popoverVisibility, true);
}

export function hidePopover(win: BrowserWindow): void {
  if (!win.isVisible()) return;
  win.hide();
  // The window is already invisible, so the renderer can reset to the inbox
  // without the pane switch ever being seen.
  win.webContents.send(IPC.popoverVisibility, false);
}

export function togglePopover(win: BrowserWindow, trayBounds: Rectangle): void {
  if (win.isVisible()) {
    hidePopover(win);
  } else {
    showPopover(win, trayBounds);
  }
}
