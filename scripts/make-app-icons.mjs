// Exports the app icon to every platform from assets/majordomo.icon — the
// Icon Composer document is the single source of truth:
//   assets/appicon.icns     macOS flat fallback (hosts older than macOS 26;
//                           macOS 26 gets the layered Assets.car the
//                           packager compiles itself — see package.mjs)
//   assets/appicon.ico      Windows app + installer icon
//   assets/appicon-256.png  Linux launcher icon (installed by install.mjs)
// All three are committed, so this only runs when the icon changes. It
// needs macOS 26 with Xcode 26's actool — the same tooling Icon Composer
// itself rides on.
// Run with: node scripts/make-app-icons.mjs   (or: pnpm icons:app)
import { Buffer } from "node:buffer";
import { execFileSync, spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { release, tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";

if (process.platform !== "darwin" || Number(release().split(".")[0]) < 25) {
  console.error("make-app-icons: needs macOS 26+ — actool is what renders .icon documents.");
  process.exit(1);
}
if (spawnSync("xcrun", ["--find", "actool"], { stdio: "ignore" }).status !== 0) {
  console.error("make-app-icons: actool not found — install Xcode 26 or newer.");
  process.exit(1);
}

const tmp = mkdtempSync(join(tmpdir(), "majordomo-icons-"));
try {
  // actool derives the asset name from the document's filename, so compile
  // a copy named the way the packager expects ("Icon").
  const iconDoc = join(tmp, "Icon.icon");
  cpSync("assets/majordomo.icon", iconDoc, { recursive: true });
  const out = join(tmp, "out");
  mkdirSync(out);
  execFileSync("actool", [
    iconDoc,
    "--compile",
    out,
    "--output-format",
    "human-readable-text",
    "--notices",
    "--warnings",
    "--output-partial-info-plist",
    join(out, "partial.plist"),
    "--app-icon",
    "Icon",
    "--include-all-app-icons",
    "--enable-on-demand-resources",
    "NO",
    "--development-region",
    "en",
    "--target-device",
    "mac",
    // A pre-26 deployment target makes actool also emit the derived
    // Icon.icns fallback (26.0 would produce only the Assets.car).
    "--minimum-deployment-target",
    "12.0",
    "--platform",
    "macosx",
  ], { stdio: "ignore" });

  cpSync(join(out, "Icon.icns"), "assets/appicon.icns");
  console.log("wrote assets/appicon.icns");

  // Apple's derived icns carries 16/32/128/256 px renders; unpack them for
  // the other platforms. 256 is also the ICO format's ceiling.
  const iconset = join(tmp, "Icon.iconset");
  execFileSync("iconutil", ["--convert", "iconset", "--output", iconset, join(out, "Icon.icns")]);
  const native = {
    256: join(iconset, "icon_128x128@2x.png"),
    128: join(iconset, "icon_128x128.png"),
    32: join(iconset, "icon_16x16@2x.png"),
    16: join(iconset, "icon_16x16.png"),
  };

  cpSync(native[256], "assets/appicon-256.png");
  console.log("wrote assets/appicon-256.png");

  // Modern ICO: a directory of PNG-compressed entries (supported since
  // Vista). Native actool renders where the iconset has the size, sips
  // downscales of the 256 for the Windows-only 64/48 slots.
  const SIZES = [256, 128, 64, 48, 32, 16];
  const pngs = SIZES.map((size) => {
    let file = native[size];
    if (!file) {
      file = join(tmp, `appicon-${size}.png`);
      execFileSync("sips", ["-z", String(size), String(size), native[256], "--out", file], {
        stdio: "ignore",
      });
    }
    return { size, data: readFileSync(file) };
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
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
