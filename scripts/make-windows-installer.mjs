// Builds release/installer/Majordomo-windows-<arch>-Setup.exe from the
// packaged win32 app (release/Majordomo-win32-<arch>, produced by
// package.mjs --platform=win32 --arch=<arch>).
// Squirrel.Windows tooling only runs on Windows — CI's windows runner does.
// Run with: node scripts/make-windows-installer.mjs [--arch=x64|arm64]
import { createWindowsInstaller } from "electron-winstaller";

if (process.platform !== "win32") {
  console.error("make-windows-installer: Squirrel.Windows tooling requires Windows.");
  process.exit(1);
}

const args = new Map(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, "").split("=");
    return [k, v];
  }),
);
const arch = args.get("arch") ?? process.arch;
if (!["arm64", "x64"].includes(arch)) {
  console.error(`unsupported --arch=${arch} (arm64|x64)`);
  process.exit(1);
}

const setupExe = `Majordomo-windows-${arch}-Setup.exe`;
await createWindowsInstaller({
  appDirectory: `release/Majordomo-win32-${arch}`,
  outputDirectory: "release/installer",
  exe: "Majordomo.exe",
  setupExe,
  setupIcon: "assets/appicon.ico",
  authors: "Majordomo contributors",
  noMsi: true,
});
console.log(`wrote release/installer/${setupExe}`);
