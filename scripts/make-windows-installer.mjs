// Builds release/installer/Majordomo-Setup.exe from the packaged win32 app
// (release/Majordomo-win32-x64, produced by package.mjs --platform=win32).
// Squirrel.Windows tooling only runs on Windows — CI's windows runner does.
// Run with: node scripts/make-windows-installer.mjs
import { createWindowsInstaller } from "electron-winstaller";

if (process.platform !== "win32") {
  console.error("make-windows-installer: Squirrel.Windows tooling requires Windows.");
  process.exit(1);
}

await createWindowsInstaller({
  appDirectory: "release/Majordomo-win32-x64",
  outputDirectory: "release/installer",
  exe: "Majordomo.exe",
  setupExe: "Majordomo-Setup.exe",
  setupIcon: "assets/appicon.ico",
  authors: "Majordomo contributors",
  noMsi: true,
});
console.log("wrote release/installer/Majordomo-Setup.exe");
