import { build } from "esbuild";
import { cpSync, mkdirSync } from "node:fs";

mkdirSync("dist/renderer", { recursive: true });

await Promise.all([
  build({
    entryPoints: ["src/electron/index.ts"],
    bundle: true,
    platform: "node",
    format: "cjs",
    external: ["electron", "electron-liquid-glass", "@napi-rs/keyring"],
    outfile: "dist/main/index.js",
  }),
  build({
    entryPoints: ["src/electron/preload.ts"],
    bundle: true,
    platform: "node",
    format: "cjs",
    external: ["electron"],
    outfile: "dist/main/preload.js",
  }),
  build({
    entryPoints: ["src/ui/main.tsx"],
    bundle: true,
    platform: "browser",
    format: "iife",
    jsx: "automatic",
    outfile: "dist/renderer/index.js",
  }),
]);

cpSync("src/ui/index.html", "dist/renderer/index.html");
cpSync("src/ui/styles.css", "dist/renderer/styles.css");
cpSync("assets", "dist/assets", { recursive: true });
console.log("build ok");
