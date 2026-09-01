import type { Rectangle } from "electron";
import type { Buffer } from "node:buffer";
import { release } from "node:os";
import { join } from "node:path";
import process from "node:process";
import { BrowserWindow, screen } from "electron";
import { IPC } from "../shared/ipc";

const POPOVER_WIDTH = 380;
const POPOVER_HEIGHT = 540;
const MIN_POPOVER_HEIGHT = 140;
const TRAY_GAP = 4;

// Whether the popover was last anchored above the tray (bottom taskbar):
// resizes must then keep the bottom edge fixed instead of the top.
let anchoredAbove = false;

// Plain show()/hide(). An always-ordered window driven by opacity (to dodge
// macOS's window-show animation) was tried and rolled back: with the Liquid
// Glass view attached, the compositor sometimes flashed the wrong background
// color on re-show.

/** Windows build number (e.g. 22631 for 11 23H2), 0 elsewhere. */
function windowsBuild(): number {
  if (process.platform !== "win32")
    return 0;
  return Number(release().split(".")[2]) || 0;
}

/** Acrylic needs Windows 11 (build 22000+). */
function acrylicSupported(): boolean {
  return process.platform === "win32" && windowsBuild() >= 22000;
}

/**
 * Whether the translucent background should start enabled on this machine.
 * The toggle itself is renderer-side paint — main only persists the flag.
 */
export function defaultGlassEnabled(): boolean {
  switch (process.platform) {
    case "darwin":
      return true;
    case "win32":
      return acrylicSupported();
    default:
      // Linux: transparency is compositor roulette — opaque by default.
      return false;
  }
}

/** Creates the popover window that anchors to the tray icon. */
export function createPopover(): BrowserWindow {
  const acrylic = acrylicSupported();
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
    // darwin: transparent window; the Liquid Glass view is attached behind
    // the page in applyGlass() once the renderer has loaded.
    // win32: backgroundMaterial wants a non-transparent frameless window;
    // on builds < 22000 there is no material and the renderer paints opaque.
    // linux: transparent best-effort — compositors like KDE can blur it.
    transparent: process.platform !== "win32",
    ...(acrylic ? { backgroundMaterial: "acrylic" as const } : {}),
    webPreferences: {
      preload: join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      // The preload is a single esbuild bundle that only touches the
      // ipcRenderer/contextBridge subset a sandboxed preload gets.
      sandbox: true,
    },
  });
  win.setAlwaysOnTop(true, "floating");
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  win.on("blur", () => hidePopover(win));
  if (process.platform === "darwin") {
    win.webContents.once("did-finish-load", () => applyGlass(win));
  }
  // pnpm dev serves the renderer from Vite for HMR; otherwise load the
  // built page from disk.
  const devServerUrl = process.env.MAJORDOMO_DEV_SERVER_URL;
  if (devServerUrl) {
    void win.loadURL(devServerUrl);
  } else {
    void win.loadFile(join(__dirname, "../renderer/index.html"));
  }
  return win;
}

export const GLASS_CORNER_RADIUS = 16;

/**
 * Attach the macOS 26 Liquid Glass material (NSGlassEffectView) behind the
 * page; fall back to the older frosted vibrancy where it's unavailable.
 */
function applyGlass(win: BrowserWindow): void {
  interface LiquidGlassApi {
    addView: (handle: Buffer, options: { cornerRadius?: number; tintColor?: string; opaque?: boolean }) => number;
  }
  try {
    // Native module, resolved at runtime (esbuild leaves it external).
    // eslint-disable-next-line ts/no-require-imports
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

/**
 * Where to place the popover for the given tray bounds: under a top tray
 * (macOS menu bar), above a bottom tray (Windows taskbar), near the cursor
 * when the DE reports no tray bounds at all (some Linux AppIndicator hosts) —
 * always clamped inside the work area of the display it lands on.
 */
function popoverPosition(trayBounds: Rectangle, height: number): { x: number; y: number } {
  const hasTrayBounds = trayBounds.width > 0 || trayBounds.height > 0;
  const anchor = hasTrayBounds
    ? {
        x: Math.round(trayBounds.x + trayBounds.width / 2),
        y: Math.round(trayBounds.y + trayBounds.height / 2),
      }
    : screen.getCursorScreenPoint();
  const area = screen.getDisplayNearestPoint(anchor).workArea;

  let x = Math.round(anchor.x - POPOVER_WIDTH / 2);
  let y: number;
  anchoredAbove = false;
  if (!hasTrayBounds) {
    y = anchor.y + TRAY_GAP;
  } else if (anchor.y <= area.y + area.height / 2) {
    // Tray in the top half (menu bar, top taskbar): open below it.
    y = Math.round(trayBounds.y + trayBounds.height + TRAY_GAP);
  } else {
    // Tray in the bottom half (Windows taskbar): open above it.
    y = Math.round(trayBounds.y - TRAY_GAP - height);
    anchoredAbove = true;
  }

  x = Math.min(Math.max(x, area.x), area.x + area.width - POPOVER_WIDTH);
  y = Math.min(Math.max(y, area.y), area.y + area.height - height);
  return { x, y };
}

export function showPopover(win: BrowserWindow, trayBounds: Rectangle): void {
  const { x, y } = popoverPosition(trayBounds, win.getBounds().height);
  win.setPosition(x, y, false);
  win.show();
  win.focus();
  win.webContents.send(IPC.popoverVisibility, true);
}

/**
 * Resizes the popover to hug the renderer's content, like native menu
 * extras: clamped, keeping the tray-adjacent edge fixed, animated while
 * visible (macOS ignores the flag elsewhere).
 */
export function resizePopover(win: BrowserWindow, contentHeight: number): void {
  const height = Math.round(
    Math.min(POPOVER_HEIGHT, Math.max(MIN_POPOVER_HEIGHT, contentHeight)),
  );
  const bounds = win.getBounds();
  if (bounds.height === height)
    return;
  const y = anchoredAbove ? bounds.y + bounds.height - height : bounds.y;
  win.setBounds({ x: bounds.x, y, width: bounds.width, height }, win.isVisible());
}

export function hidePopover(win: BrowserWindow): void {
  if (!win.isVisible())
    return;
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
