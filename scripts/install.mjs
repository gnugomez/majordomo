// Builds, packages, and installs Majordomo on the machine it runs on.
// Usage: node scripts/install.mjs [--no-launch]   (or: pnpm install:app)
//
// - darwin: /Applications/Majordomo.app (~/Applications when /Applications
//   isn't writable; MAJORDOMO_INSTALL_DIR overrides the directory — running
//   copies are then left alone, for side-by-side installs).
// - win32: hands off to the Squirrel installer, which installs per-user
//   (%LOCALAPPDATA%\Majordomo), creates shortcuts, and relaunches the app
//   itself — --no-launch has no effect there.
// - linux: ~/.local/opt/majordomo, a ~/.local/bin/majordomo symlink, and a
//   .desktop entry + scalable icon so launchers pick it up.
import { execFileSync, spawn, spawnSync } from "node:child_process";
import {
  accessSync,
  constants,
  cpSync,
  existsSync,
  mkdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import process from "node:process";

const { platform, arch } = process;
const launch = !process.argv.includes("--no-launch");

if (!["darwin", "win32", "linux"].includes(platform)) {
  console.error(`unsupported platform: ${platform} (darwin|win32|linux)`);
  process.exit(1);
}
if (!["arm64", "x64"].includes(arch)) {
  console.error(`unsupported arch: ${arch} (arm64|x64)`);
  process.exit(1);
}

const packaged = join("release", `Majordomo-${platform}-${arch}`);

function run(cmd, args) {
  execFileSync(cmd, args, { stdio: "inherit" });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function appIsRunning() {
  return spawnSync("pgrep", ["-x", "Majordomo"], { stdio: "ignore" }).status === 0;
}

/** Quits a running copy and waits until it is gone: the replacement can
 * only take over the single-instance lock once the old process has exited —
 * otherwise the fresh launch quits immediately and the (deleted) old build
 * keeps running. Escalates to SIGKILL if a graceful quit stalls. */
async function stopRunningApp() {
  if (platform === "win32") {
    try {
      execFileSync("taskkill", ["/IM", "Majordomo.exe", "/F"], { stdio: "ignore" });
    } catch {
      // Not running (or no taskkill) — nothing to stop.
    }
    return;
  }
  for (const signal of ["-TERM", "-KILL"]) {
    try {
      execFileSync("pkill", [signal, "-x", "Majordomo"], { stdio: "ignore" });
    } catch {
      return; // pkill exits non-zero when nothing matched — already gone.
    }
    for (let waited = 0; waited < 3000 && appIsRunning(); waited += 100) {
      await sleep(100);
    }
    if (!appIsRunning()) {
      return;
    }
  }
}

async function installDarwin() {
  const override = process.env.MAJORDOMO_INSTALL_DIR;
  // Replace the copy the user already has, wherever it lives; a fresh
  // install prefers /Applications, falling back to the per-user dir when
  // /Applications isn't writable (it needs admin membership).
  let appsDir = override
    ?? ["/Applications", join(homedir(), "Applications")]
      .find((dir) => existsSync(join(dir, "Majordomo.app")));
  if (!appsDir) {
    appsDir = "/Applications";
    try {
      accessSync(appsDir, constants.W_OK);
    } catch {
      appsDir = join(homedir(), "Applications");
    }
  }
  mkdirSync(appsDir, { recursive: true });
  const dest = join(appsDir, "Majordomo.app");
  if (!override) {
    await stopRunningApp();
  }
  rmSync(dest, { recursive: true, force: true });
  // ditto preserves what cp -R can drop (extended attributes, resource
  // forks) — the code signature depends on them.
  run("ditto", [join(packaged, "Majordomo.app"), dest]);
  console.log(`installed: ${dest}`);
  // codesign reports "Signature=adhoc" (on stderr) for ad-hoc bundles.
  const signature = spawnSync("codesign", ["--display", "--verbose=2", dest], { encoding: "utf8" });
  if (`${signature.stderr}`.includes("Signature=adhoc")) {
    console.log(
      "Ad-hoc-signed builds get no notification prompt on macOS — enable "
      + "Majordomo once under System Settings → Notifications.",
    );
  }
  if (launch) {
    run("open", [dest]);
  }
}

async function installWin32() {
  run("node", ["scripts/make-windows-installer.mjs", `--arch=${arch}`]);
  await stopRunningApp();
  // Squirrel installs per-user and starts the app when it finishes.
  run(join("release", "installer", `Majordomo-windows-${arch}-Setup.exe`), ["--silent"]);
  console.log("installed: %LOCALAPPDATA%\\Majordomo (Squirrel, per-user)");
}

async function installLinux() {
  const home = homedir();
  const optDir = join(home, ".local", "opt", "majordomo");
  const binDir = join(home, ".local", "bin");
  const appsDir = join(home, ".local", "share", "applications");
  const iconDir = join(home, ".local", "share", "icons", "hicolor", "256x256", "apps");
  const executable = join(optDir, "Majordomo");

  await stopRunningApp();
  rmSync(optDir, { recursive: true, force: true });
  mkdirSync(join(home, ".local", "opt"), { recursive: true });
  cpSync(packaged, optDir, { recursive: true });

  mkdirSync(binDir, { recursive: true });
  const link = join(binDir, "majordomo");
  rmSync(link, { force: true });
  symlinkSync(executable, link);

  mkdirSync(iconDir, { recursive: true });
  cpSync("assets/appicon-256.png", join(iconDir, "majordomo.png"));

  mkdirSync(appsDir, { recursive: true });
  writeFileSync(join(appsDir, "majordomo.desktop"), `[Desktop Entry]
Type=Application
Name=Majordomo
Comment=Tray inbox for GitHub and self-hosted GitLab
Exec="${executable}"
Icon=majordomo
Terminal=false
Categories=Development;Utility;
StartupWMClass=Majordomo
`);

  // Refresh launcher caches where the tools exist; desktops that lack them
  // re-scan on their own.
  for (const [cmd, args] of [
    ["update-desktop-database", [appsDir]],
    ["gtk-update-icon-cache", ["-t", join(home, ".local", "share", "icons", "hicolor")]],
  ]) {
    try {
      execFileSync(cmd, args, { stdio: "ignore" });
    } catch {
      // Best-effort only.
    }
  }

  console.log(`installed: ${optDir}`);
  console.log(`desktop entry: ${join(appsDir, "majordomo.desktop")}`);
  if (launch) {
    spawn(executable, { detached: true, stdio: "ignore" }).unref();
  }
}

// --- build → package → install, always for the host ----------------------
run("node", ["scripts/build.mjs"]);
run("node", ["scripts/package.mjs", `--platform=${platform}`, `--arch=${arch}`]);

if (platform === "darwin") {
  await installDarwin();
} else if (platform === "win32") {
  await installWin32();
} else {
  await installLinux();
}
