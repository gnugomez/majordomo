// Builds build/Majordomo.icns from assets/appicon.svg via Electron
// (offscreen render), sips, and iconutil — all present on a stock macOS
// dev machine.
import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";

const electron = "./node_modules/.bin/electron";
execFileSync(electron, ["scripts/render-appicon.cjs"], { stdio: "inherit" });

const iconset = "build/Majordomo.iconset";
rmSync(iconset, { recursive: true, force: true });
mkdirSync(iconset, { recursive: true });

const master = "build/appicon-1024.png";
const entries = [
  ["icon_16x16.png", 16],
  ["icon_16x16@2x.png", 32],
  ["icon_32x32.png", 32],
  ["icon_32x32@2x.png", 64],
  ["icon_128x128.png", 128],
  ["icon_128x128@2x.png", 256],
  ["icon_256x256.png", 256],
  ["icon_256x256@2x.png", 512],
  ["icon_512x512.png", 512],
  ["icon_512x512@2x.png", 1024],
];
for (const [name, size] of entries) {
  execFileSync("sips", ["-z", String(size), String(size), master, "--out", `${iconset}/${name}`], {
    stdio: "ignore",
  });
}

execFileSync("iconutil", ["-c", "icns", iconset, "-o", "build/Majordomo.icns"], {
  stdio: "inherit",
});
console.log("wrote build/Majordomo.icns");
