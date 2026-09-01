import { execFileSync } from "node:child_process";
// Packages the built app (dist/) into release/Majordomo-<platform>-<arch>/.
// Usage: node scripts/package.mjs [--platform=darwin|win32|linux] [--arch=arm64|x64]
// Defaults to the host platform/arch. Run via: pnpm package (macOS flow).
import process from "node:process";
import { packager } from "@electron/packager";

const args = new Map(
  process.argv
    .slice(2)
    .filter((arg) => arg.startsWith("--") && arg.includes("="))
    .map((arg) => arg.slice(2).split(/=(.*)/s, 2)),
);
const platform = args.get("platform") ?? process.platform;
const arch = args.get("arch") ?? process.arch;
if (!["darwin", "win32", "linux"].includes(platform)) {
  console.error(`unsupported --platform=${platform} (darwin|win32|linux)`);
  process.exit(1);
}
if (!["arm64", "x64"].includes(arch)) {
  console.error(`unsupported --arch=${arch} (arm64|x64)`);
  process.exit(1);
}

// darwin: .icns rendered by scripts/make-icns.mjs. win32: the committed
// assets/appicon.ico (scripts/make-ico.mjs regenerates it). linux: the
// packager takes no icon — the .desktop file of whoever installs it does.
const icon
  = platform === "darwin" ? "build/Majordomo.icns" : platform === "win32" ? "assets/appicon.ico" : undefined;

const appPaths = await packager({
  dir: ".",
  name: "Majordomo",
  platform,
  arch,
  icon,
  out: "release",
  overwrite: true,
  prune: true,
  // Native modules can't load from inside the asar archive.
  asar: { unpack: "**/*.node" },
  ...(platform === "darwin"
    ? {
        appBundleId: "dev.majordomo.app",
        appCategoryType: "public.app-category.developer-tools",
        // Menu-bar app: never show in the Dock or the Cmd-Tab switcher.
        extendInfo: { LSUIElement: true },
      }
    : {}),
  ...(platform === "win32"
    ? {
        win32metadata: {
          CompanyName: "Majordomo contributors",
          ProductName: "Majordomo",
        },
      }
    : {}),
  ignore: [
    /^\/src($|\/)/,
    /^\/scripts($|\/)/,
    /^\/assets($|\/)/,
    /^\/build($|\/)/,
    /^\/release($|\/)/,
    /^\/\.claude($|\/)/,
    /^\/\.github($|\/)/,
    /^\/\.gitignore$/,
    /^\/tsconfig\.json$/,
    /^\/README\.md$/,
    /^\/LICENSE$/,
    /^\/pnpm-lock\.yaml$/,
    /^\/pnpm-workspace\.yaml$/,
    // pnpm's bookkeeping inside node_modules — the pruner leaves it behind
    // because none of it is a module.
    /^\/node_modules\/\.(modules\.yaml|package-map\.json|pnpm|pnpm-workspace-state-v1\.json)($|\/)/,
  ],
});

if (platform === "darwin") {
  // Packaging modifies the bundle after Electron's own ad-hoc signature was
  // sealed, which leaves it invalid — and Apple Silicon refuses to launch an
  // invalidly-signed app. Re-sign with CODESIGN_IDENTITY when set, else with a
  // "Majordomo Dev" identity if the keychain has one (any stable identity,
  // even self-signed, keeps macOS permissions — notifications, login item —
  // across updates; ad-hoc resets them on every build), else ad-hoc.
  function detectIdentity() {
    if (process.env.CODESIGN_IDENTITY)
      return process.env.CODESIGN_IDENTITY;
    try {
      const out = execFileSync("security", ["find-identity", "-v", "-p", "codesigning"], {
        encoding: "utf8",
      });
      if (out.includes("\"Majordomo Dev\""))
        return "Majordomo Dev";
    } catch {
      // security not available or no keychain access — fall through to ad-hoc.
    }
    return "-";
  }
  const identity = detectIdentity();
  console.log(identity === "-" ? "signing: ad-hoc" : `signing: ${identity}`);
  for (const appPath of appPaths) {
    execFileSync("codesign", ["--force", "--deep", "-s", identity, `${appPath}/Majordomo.app`]);
  }
}

console.log("packaged:", appPaths.join(", "));
