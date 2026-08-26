// Generates the macOS template tray icons into assets/.
// No dependencies: PNG chunks are hand-rolled (CRC32 + node:zlib deflate).
// Template images must be pure black with alpha only — macOS recolors them.

import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ASSETS_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "assets");

// ---- PNG encoding (8-bit RGBA, non-interlaced, filter None) ----------------

import { deflateSync } from "node:zlib";

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, "ascii");
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

/** Encodes a size×size RGBA PNG where every pixel is black and `alpha(x, y)` gives opacity. */
function encodePng(size, alpha) {
  const raw = Buffer.alloc(size * (1 + size * 4));
  let o = 0;
  for (let y = 0; y < size; y++) {
    raw[o++] = 0; // filter: None
    for (let x = 0; x < size; x++) {
      raw[o++] = 0;
      raw[o++] = 0;
      raw[o++] = 0;
      raw[o++] = alpha(x, y);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type: RGBA
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  return Buffer.concat([
    signature,
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// ---- Glyph: a chunky inbox tray (side walls, bottom, dipped center notch) --

const GLYPH = [
  "................",
  "................",
  "................",
  "..#..........#..",
  ".##..........##.",
  ".#####....#####.",
  ".#####....#####.",
  ".##.########.##.",
  ".##.########.##.",
  ".##..........##.",
  ".##..........##.",
  ".##############.",
  "..############..",
  "................",
  "................",
  "................",
];

function glyphAlpha(scale) {
  return (x, y) =>
    GLYPH[Math.floor(y / scale)][Math.floor(x / scale)] === "#" ? 255 : 0;
}

/** Adds a filled circle (~4px at 1x, ~8px at 2x) at the top-right corner, clearing the glyph beneath it. */
function withDot(base, scale) {
  const size = 16 * scale;
  const cx = size - 2 * scale;
  const cy = 2 * scale;
  const r = 1.8 * scale;
  const clearX = size - 5 * scale;
  const clearY = 5 * scale;
  return (x, y) => {
    const dx = x + 0.5 - cx;
    const dy = y + 0.5 - cy;
    if (dx * dx + dy * dy <= r * r) return 255;
    if (x >= clearX && y < clearY) return 0; // breathing room around the dot
    return base(x, y);
  };
}

// ---- Write + verify ---------------------------------------------------------

const FILES = [
  ["trayTemplate.png", 16, glyphAlpha(1)],
  ["trayTemplate@2x.png", 32, glyphAlpha(2)],
  ["trayDotTemplate.png", 16, withDot(glyphAlpha(1), 1)],
  ["trayDotTemplate@2x.png", 32, withDot(glyphAlpha(2), 2)],
];

mkdirSync(ASSETS_DIR, { recursive: true });

for (const [name, size, alpha] of FILES) {
  writeFileSync(join(ASSETS_DIR, name), encodePng(size, alpha));
}

let failed = false;
for (const [name, size] of FILES) {
  const file = join(ASSETS_DIR, name);
  try {
    const out = execFileSync("sips", ["-g", "pixelWidth", "-g", "pixelHeight", file], {
      encoding: "utf8",
    });
    const width = Number(/pixelWidth: (\d+)/.exec(out)?.[1]);
    const height = Number(/pixelHeight: (\d+)/.exec(out)?.[1]);
    if (width !== size || height !== size) {
      console.error(`FAIL ${name}: expected ${size}x${size}, sips reported ${width}x${height}`);
      failed = true;
    } else {
      console.log(`ok ${name}: ${width}x${height}`);
    }
  } catch (err) {
    console.error(`FAIL ${name}: sips could not read the file`, err.message ?? err);
    failed = true;
  }
}

if (failed) process.exit(1);
console.log("icons generated into", ASSETS_DIR);
