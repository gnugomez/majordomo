import { Menu, Tray } from "electron";
import { join } from "node:path";
import type { Rectangle } from "electron";

export interface TrayHandle {
  bounds(): Rectangle;
  /** Shows the dot variant iff there are unread mentions. */
  setDot(dot: boolean): void;
}

export function createTray(opts: {
  onToggle(bounds: Rectangle): void;
  onOpen(bounds: Rectangle): void;
  onRefresh(): void;
  onQuit(): void;
}): TrayHandle {
  const baseIcon = join(__dirname, "../assets/trayTemplate.png");
  const dotIcon = join(__dirname, "../assets/trayDotTemplate.png");

  const tray = new Tray(baseIcon);
  tray.setToolTip("Majordomo");

  const menu = Menu.buildFromTemplate([
    { label: "Open Inbox", click: () => opts.onOpen(tray.getBounds()) },
    { label: "Refresh now", click: () => opts.onRefresh() },
    { type: "separator" },
    { label: "Quit Majordomo", click: () => opts.onQuit() },
  ]);

  tray.on("click", () => opts.onToggle(tray.getBounds()));
  tray.on("right-click", () => tray.popUpContextMenu(menu));

  let dotShown = false;
  return {
    bounds: () => tray.getBounds(),
    setDot(dot: boolean) {
      if (dot === dotShown) return;
      dotShown = dot;
      tray.setImage(dot ? dotIcon : baseIcon);
    },
  };
}
