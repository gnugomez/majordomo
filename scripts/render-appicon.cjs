// Run with: electron scripts/render-appicon.cjs
// Renders assets/appicon.svg to build/appicon-1024.png (with alpha) using an
// offscreen window, so icon generation needs no image tooling beyond Electron.
const { Buffer } = require("node:buffer");
const { mkdirSync, readFileSync, writeFileSync } = require("node:fs");
const { join } = require("node:path");
const { app, BrowserWindow } = require("electron");

app.disableHardwareAcceleration();

void app.whenReady().then(async () => {
  const svg = readFileSync(join(__dirname, "../assets/appicon.svg"), "utf8");
  const html = `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:transparent;overflow:hidden}</style>${svg}`;

  const win = new BrowserWindow({
    width: 1024,
    height: 1024,
    show: false,
    frame: false,
    transparent: true,
    webPreferences: { offscreen: true },
  });

  let lastPaint = null;
  win.webContents.on("paint", (_event, _dirty, image) => {
    lastPaint = image;
  });
  win.webContents.setFrameRate(10);

  await win.loadURL(`data:text/html;base64,${Buffer.from(html).toString("base64")}`);
  await new Promise((resolve) => setTimeout(resolve, 800));

  const image = lastPaint ?? (await win.webContents.capturePage());
  const size = image.getSize();
  if (size.width !== 1024 || size.height !== 1024) {
    console.error(`unexpected capture size ${size.width}x${size.height}`);
    app.exit(1);
    return;
  }

  mkdirSync(join(__dirname, "../build"), { recursive: true });
  writeFileSync(join(__dirname, "../build/appicon-1024.png"), image.toPNG());
  console.log("wrote build/appicon-1024.png");
  app.exit(0);
});
