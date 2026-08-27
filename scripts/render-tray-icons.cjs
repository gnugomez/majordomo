// Run with: electron scripts/render-tray-icons.cjs  (or: npm run icons)
// Renders the tray icons (base + unread-dot variant, 1x and 2x) as
// anti-aliased vectors via an offscreen window.
// - tray*Template: pure black + alpha; macOS recolors them for light/dark
//   menu bars.
// - tray*Light / tray*Dark: white and black glyphs for Windows/Linux, where
//   template auto-inversion doesn't exist — the app picks the variant from
//   nativeTheme (dark UI → Light files).
const { app, BrowserWindow } = require("electron");
const { writeFileSync } = require("node:fs");
const { join } = require("node:path");

app.disableHardwareAcceleration();
// Windows are destroyed between renders; don't let that quit the app.
app.on("window-all-closed", () => {});

// The same Feather "inbox" glyph the app icon uses, scaled into a 16pt canvas.
const glyphFor = (color) => `
  <g transform="translate(1,1.5) scale(0.5833)" fill="none" stroke="${color}"
     stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">
    <polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/>
    <path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>
  </g>`;

function svgFor(size, withDot, color) {
  const glyph = glyphFor(color);
  const body = withDot
    ? `<mask id="m"><rect width="16" height="16" fill="#fff"/><circle cx="12.8" cy="3.4" r="4.1" fill="#000"/></mask>
       <g mask="url(#m)">${glyph}</g>
       <circle cx="12.8" cy="3.4" r="2.6" fill="${color}"/>`
    : glyph;
  return `<svg width="${size}" height="${size}" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">${body}</svg>`;
}

async function render(size, withDot, color, outName) {
  const html = `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:transparent;overflow:hidden}</style>${svgFor(size, withDot, color)}`;
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
  const variants = [
    ["Template", "#000"], // macOS template (black + alpha)
    ["Dark", "#000"], // win/linux, light theme
    ["Light", "#fff"], // win/linux, dark theme
  ];
  for (const [suffix, color] of variants) {
    await render(16, false, color, `tray${suffix}.png`);
    await render(32, false, color, `tray${suffix}@2x.png`);
    await render(16, true, color, `trayDot${suffix}.png`);
    await render(32, true, color, `trayDot${suffix}@2x.png`);
  }
  app.exit(0);
});
