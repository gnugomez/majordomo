// The resizable "main app" window: a singleton browser-style inbox opened
// from the popover. Same renderer bundle as the popover — the `?window=main`
// query selects the main-window component tree — and the same background
// story: transparent + Liquid Glass on macOS, acrylic on Windows 11,
// best-effort transparency on Linux (the renderer's `opaque` class covers
// the rest).

import { join } from "node:path";
import process from "node:process";
import { app, BrowserWindow } from "electron";
import { acrylicSupported, applyGlass } from "./window";

const DEFAULT_WIDTH = 980;
const DEFAULT_HEIGHT = 640;
// The three columns' minimum widths plus their dividers (see MainApp): the
// window can never be dragged small enough to squeeze the preview.
const MIN_WIDTH = 800;
const MIN_HEIGHT = 420;

// The macOS 26 large window radius, much rounder than the popover's 16.
export const MAIN_GLASS_CORNER_RADIUS = 26;

// Traffic lights sit lower than the hiddenInset default so they (and the
// header content, which centers on them) clear the rounder corner. The
// renderer's .main-header height matches: lights are 12pt tall, so a 52pt
// header centers them at y = 20.
const TRAFFIC_LIGHTS = { x: 20, y: 20 };

let mainWindow: BrowserWindow | null = null;

/** Opens the main window, or focuses the live one; recreated after close. */
export function openMainWindow(): void {
  if (mainWindow !== null && !mainWindow.isDestroyed()) {
    if (mainWindow.isMinimized()) {
      mainWindow.restore();
    }
    mainWindow.show();
    mainWindow.focus();
    return;
  }

  // Unlike the popover, the main window is a real citizen: give the app a
  // Dock icon (and thus an app-switcher entry) for as long as it is open.
  if (process.platform === "darwin") {
    void app.dock?.show();
  }

  const win = new BrowserWindow({
    width: DEFAULT_WIDTH,
    height: DEFAULT_HEIGHT,
    minWidth: MIN_WIDTH,
    minHeight: MIN_HEIGHT,
    show: false,
    title: "Majordomo",
    // Standard frame, but on macOS the title bar collapses into the page —
    // the renderer's header centers itself on the repositioned lights.
    ...(process.platform === "darwin"
      ? { titleBarStyle: "hidden" as const, trafficLightPosition: TRAFFIC_LIGHTS }
      : {}),
    // Background approach mirrors createPopover(): see the notes there.
    transparent: process.platform !== "win32",
    ...(acrylicSupported() ? { backgroundMaterial: "acrylic" as const } : {}),
    webPreferences: {
      preload: join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  mainWindow = win;
  win.on("closed", () => {
    if (mainWindow === win) {
      mainWindow = null;
      // Back to a pure menu-bar presence.
      if (process.platform === "darwin") {
        app.dock?.hide();
      }
    }
  });

  if (process.platform === "darwin") {
    win.webContents.once("did-finish-load", () => applyGlass(win, MAIN_GLASS_CORNER_RADIUS));
  }
  win.once("ready-to-show", () => {
    win.show();
    win.focus();
  });

  const devServerUrl = process.env.MAJORDOMO_DEV_SERVER_URL;
  if (devServerUrl) {
    const url = new URL(devServerUrl);
    url.searchParams.set("window", "main");
    void win.loadURL(url.toString());
  } else {
    void win.loadFile(join(__dirname, "../renderer/index.html"), {
      query: { window: "main" },
    });
  }
}
