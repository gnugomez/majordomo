// Packages the built app (dist/) into release/Majordomo-darwin-*/Majordomo.app.
// Run via: npm run package
import { execFileSync } from "node:child_process";
import { packager } from "@electron/packager";

const appPaths = await packager({
  dir: ".",
  name: "Majordomo",
  appBundleId: "dev.majordomo.app",
  appCategoryType: "public.app-category.developer-tools",
  icon: "build/Majordomo.icns",
  out: "release",
  overwrite: true,
  prune: true,
  // Native modules can't load from inside the asar archive.
  asar: { unpack: "**/*.node" },
  // Menu-bar app: never show in the Dock or the Cmd-Tab switcher.
  extendInfo: { LSUIElement: true },
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
    /^\/package-lock\.json$/,
  ],
});

// Packaging modifies the bundle after Electron's own ad-hoc signature was
// sealed, which leaves it invalid — and Apple Silicon refuses to launch an
// invalidly-signed app. Re-sign with CODESIGN_IDENTITY when set, else with a
// "Majordomo Dev" identity if the keychain has one (any stable identity,
// even self-signed, keeps macOS permissions — notifications, login item —
// across updates; ad-hoc resets them on every build), else ad-hoc.
function detectIdentity() {
  if (process.env.CODESIGN_IDENTITY) return process.env.CODESIGN_IDENTITY;
  try {
    const out = execFileSync("security", ["find-identity", "-v", "-p", "codesigning"], {
      encoding: "utf8",
    });
    if (out.includes('"Majordomo Dev"')) return "Majordomo Dev";
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

console.log("packaged:", appPaths.join(", "));
