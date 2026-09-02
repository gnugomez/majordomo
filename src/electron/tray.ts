import type { Rectangle } from "electron";
import { join } from "node:path";
import process from "node:process";
import { Menu, nativeTheme, Tray } from "electron";

export interface TrayHandle {
  bounds: () => Rectangle;
  /** Shows the dot variant iff there are unread mentions. */
  setDot: (dot: boolean) => void;
}

/**
 * macOS gets Template images (pure black + alpha, recolored by the system).
 * Windows/Linux have no template auto-inversion, so pick the white or black
 * glyph from the current theme: dark UI → white glyph (`Light` files).
 */
function iconPath(dot: boolean): string {
  if (process.platform === "darwin") {
    return join(__dirname, "../assets", dot ? "trayDotTemplate.png" : "trayTemplate.png");
  }
  const shade = nativeTheme.shouldUseDarkColors ? "Light" : "Dark";
  return join(__dirname, "../assets", dot ? `trayDot${shade}.png` : `tray${shade}.png`);
}

export function createTray(opts: {
  onToggle: (bounds: Rectangle) => void;
  onOpen: (bounds: Rectangle) => void;
  onOpenMain: () => void;
  onRefresh: () => void;
  onQuit: () => void;
}): TrayHandle {
  let dotShown = false;

  const tray = new Tray(iconPath(false));
  tray.setToolTip("Majordomo");

  const menu = Menu.buildFromTemplate([
    { label: "Open Inbox", click: () => opts.onOpen(tray.getBounds()) },
    { label: "Open Majordomo Window", click: () => opts.onOpenMain() },
    { label: "Refresh now", click: () => opts.onRefresh() },
    { type: "separator" },
    { label: "Quit Majordomo", click: () => opts.onQuit() },
  ]);

  // Linux AppIndicator hosts often deliver no click events at all —
  // registering the context menu is the one thing every DE honors, and
  // "Open Inbox" is its first item.
  if (process.platform === "linux") {
    tray.setContextMenu(menu);
  }
  tray.on("click", () => opts.onToggle(tray.getBounds()));
  tray.on("right-click", () => tray.popUpContextMenu(menu));

  // The non-template icons don't follow theme flips on their own.
  if (process.platform !== "darwin") {
    nativeTheme.on("updated", () => tray.setImage(iconPath(dotShown)));
  }

  return {
    bounds: () => tray.getBounds(),
    setDot(dot: boolean) {
      if (dot === dotShown)
        return;
      dotShown = dot;
      tray.setImage(iconPath(dot));
    },
  };
}
