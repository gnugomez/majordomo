// Run with: electron scripts/render-tray-icons.cjs  (or: npm run icons)
// Renders the menu-bar template icons (base + unread-dot variant, 1x and 2x)
// as anti-aliased vectors via an offscreen window. Template images are pure
// black + alpha; macOS recolors them for light/dark menu bars.
const { app, BrowserWindow } = require("electron");
const { writeFileSync } = require("node:fs");
const { join } = require("node:path");

app.disableHardwareAcceleration();
// Windows are destroyed between renders; don't let that quit the app.
app.on("window-all-closed", () => {});

// The same Feather "inbox" glyph the app icon uses, scaled into a 16pt canvas.
const GLYPH = `
  <g transform="translate(1,1.5) scale(0.5833)" fill="none" stroke="#000"
     stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">
    <polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/>
    <path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>
  </g>`;

function svgFor(size, withDot) {
  const body = withDot
    ? `<mask id="m"><rect width="16" height="16" fill="#fff"/><circle cx="12.8" cy="3.4" r="4.1" fill="#000"/></mask>
       <g mask="url(#m)">${GLYPH}</g>
       <circle cx="12.8" cy="3.4" r="2.6" fill="#000"/>`
    : GLYPH;
  return `<svg width="${size}" height="${size}" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">${body}</svg>`;
}

async function render(size, withDot, outName) {
  const html = `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:transparent;overflow:hidden}</style>${svgFor(size, withDot)}`;
  const win = new BrowserWindow({
    width: size,
    height: size,
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

  await win.loadURL("data:text/html;base64," + Buffer.from(html).toString("base64"));
  await new Promise((resolve) => setTimeout(resolve, 400));

  const image = lastPaint ?? (await win.webContents.capturePage());
  const out = join(__dirname, "../assets", outName);
  writeFileSync(out, image.resize({ width: size, height: size }).toPNG());
  win.destroy();
  console.log(`wrote assets/${outName} (${size}x${size})`);
}

void app.whenReady().then(async () => {
  await render(16, false, "trayTemplate.png");
  await render(32, false, "trayTemplate@2x.png");
  await render(16, true, "trayDotTemplate.png");
  await render(32, true, "trayDotTemplate@2x.png");
  app.exit(0);
});
