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
  asar: true,
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
// invalidly-signed app. Re-sign ad-hoc.
for (const appPath of appPaths) {
  execFileSync("codesign", ["--force", "--deep", "-s", "-", `${appPath}/Majordomo.app`]);
}

console.log("packaged:", appPaths.join(", "));
