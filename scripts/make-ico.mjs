// Builds assets/appicon.ico (the Windows app icon) from assets/appicon.svg
// via Electron (offscreen render) and sips — macOS-only tooling, which is
// fine: the .ico is committed, so CI never needs to regenerate it.
// Run with: node scripts/make-ico.mjs
import { Buffer } from "node:buffer";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

const electron = "./node_modules/.bin/electron";
execFileSync(electron, ["scripts/render-appicon.cjs"], { stdio: "inherit" });

const master = "build/appicon-1024.png";
const workDir = "build/ico";
rmSync(workDir, { recursive: true, force: true });
mkdirSync(workDir, { recursive: true });

// Modern ICO: a directory of PNG-compressed entries (supported since Vista).
const SIZES = [256, 128, 64, 48, 32, 16];
const pngs = SIZES.map((size) => {
  const out = `${workDir}/appicon-${size}.png`;
  execFileSync("sips", ["-z", String(size), String(size), master, "--out", out], {
    stdio: "ignore",
  });
  return { size, data: readFileSync(out) };
});

// ICONDIR (6 bytes) + one ICONDIRENTRY (16 bytes) per image + PNG blobs.
const header = Buffer.alloc(6);
header.writeUInt16LE(0, 0); // reserved
header.writeUInt16LE(1, 2); // type: icon
header.writeUInt16LE(pngs.length, 4);

const entries = [];
let offset = 6 + 16 * pngs.length;
for (const { size, data } of pngs) {
  const entry = Buffer.alloc(16);
  entry.writeUInt8(size === 256 ? 0 : size, 0); // width (0 = 256)
  entry.writeUInt8(size === 256 ? 0 : size, 1); // height (0 = 256)
  entry.writeUInt8(0, 2); // palette colors
  entry.writeUInt8(0, 3); // reserved
  entry.writeUInt16LE(1, 4); // color planes
  entry.writeUInt16LE(32, 6); // bits per pixel
  entry.writeUInt32LE(data.length, 8);
  entry.writeUInt32LE(offset, 12);
  entries.push(entry);
  offset += data.length;
}

writeFileSync("assets/appicon.ico", Buffer.concat([header, ...entries, ...pngs.map((p) => p.data)]));
console.log(`wrote assets/appicon.ico (${SIZES.join(", ")} px PNG entries)`);
