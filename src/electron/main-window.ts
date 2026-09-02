// The resizable "main app" window: a singleton browser-style inbox opened
// from the popover. Same renderer bundle as the popover — the `?window=main`
// query selects the main-window component tree — but a different background:
// this is a document window, so it takes the classic NSVisualEffectView
// "sidebar" material on an ordinary macOS frame, with the system's own corner
// radius and shadow, rather than the popover's Liquid Glass, which belongs to
// the menu bar. Windows 11 gets acrylic, Linux best-effort transparency; the
// renderer's `opaque` class covers the rest.

import type { Store, WindowBounds } from "./store";
import { join } from "node:path";
import process from "node:process";
import { app, BrowserWindow, screen } from "electron";
import { acrylicSupported } from "./window";

const DEFAULT_WIDTH = 980;
const DEFAULT_HEIGHT = 640;
// The three columns' minimum widths plus their dividers (see MainApp): the
// window can never be dragged small enough to squeeze the preview.
const MIN_WIDTH = 800;
const MIN_HEIGHT = 420;

// Traffic lights sit lower than the hiddenInset default, centered in the
// renderer's 52pt .main-header: the lights are 12pt tall, so y = 20.
const TRAFFIC_LIGHTS = { x: 20, y: 20 };

let mainWindow: BrowserWindow | null = null;
let store: Store | null = null;

/** Gives the window module the store it remembers its frame in. */
export function setMainWindowStore(next: Store): void {
  store = next;
}

/**
 * The remembered frame, if it still lands on a display that exists — a window
 * saved on a monitor that has since been unplugged would otherwise open
 * offscreen. Undefined means "use the default size, centred".
 */
function restoredBounds(): WindowBounds | undefined {
  const saved = store?.getMainWindowBounds();
  if (!saved) {
    return undefined;
  }
  const area = screen.getDisplayMatching(saved).workArea;
  const visible
    = saved.x < area.x + area.width
      && saved.x + saved.width > area.x
      && saved.y < area.y + area.height
      && saved.y + saved.height > area.y;
  return visible
    ? {
        ...saved,
        width: Math.max(MIN_WIDTH, saved.width),
        height: Math.max(MIN_HEIGHT, saved.height),
      }
    : undefined;
}

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

  const saved = restoredBounds();
  const win = new BrowserWindow({
    width: saved?.width ?? DEFAULT_WIDTH,
    height: saved?.height ?? DEFAULT_HEIGHT,
    ...(saved ? { x: saved.x, y: saved.y } : {}),
    minWidth: MIN_WIDTH,
    minHeight: MIN_HEIGHT,
    show: false,
    title: "Majordomo",
    // Standard frame, but on macOS the title bar collapses into the page —
    // the renderer's header centers itself on the repositioned lights. The
    // window stays opaque there: the vibrancy view supplies the translucency,
    // and an ordinary frame brings the system corner radius and shadow with
    // it (a transparent window would have to fake both).
    ...(process.platform === "darwin"
      ? {
          titleBarStyle: "hidden" as const,
          trafficLightPosition: TRAFFIC_LIGHTS,
          // The material native source lists use; the renderer leaves the
          // sidebar unpainted so it shows, and paints over it everywhere else.
          vibrancy: "sidebar" as const,
          visualEffectState: "followWindow" as const,
        }
      : {}),
    transparent: process.platform === "linux",
    ...(acrylicSupported() ? { backgroundMaterial: "acrylic" as const } : {}),
    webPreferences: {
      preload: join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  mainWindow = win;

  // Remember the frame the way a native window does: the normal (unmaximized,
  // unfullscreened) bounds, written after the user stops dragging.
  let saveTimer: NodeJS.Timeout | undefined;
  const rememberBounds = (): void => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      if (!win.isDestroyed() && !win.isMinimized()) {
        store?.setMainWindowBounds(win.getNormalBounds());
      }
    }, 400);
  };
  win.on("resize", rememberBounds);
  win.on("move", rememberBounds);
  win.on("close", () => {
    clearTimeout(saveTimer);
    if (!win.isMinimized()) {
      store?.setMainWindowBounds(win.getNormalBounds());
    }
  });

  win.on("closed", () => {
    if (mainWindow === win) {
      mainWindow = null;
      // Back to a pure menu-bar presence.
      if (process.platform === "darwin") {
        app.dock?.hide();
      }
    }
  });

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
