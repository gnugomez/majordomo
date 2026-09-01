import { cpSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { build } from "esbuild";

mkdirSync("dist/renderer", { recursive: true });

await Promise.all([
  build({
    entryPoints: ["src/electron/index.ts"],
    bundle: true,
    platform: "node",
    format: "cjs",
    external: ["electron", "electron-liquid-glass"],
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

// The source HTML points at main.tsx for the Vite dev server (pnpm dev);
// the shipped page loads the esbuild bundle instead.
const html = readFileSync("src/ui/index.html", "utf8");
const shipped = html.replace(
  "<script type=\"module\" src=\"./main.tsx\"></script>",
  "<script src=\"./index.js\"></script>",
);
if (shipped === html)
  throw new Error("index.html: renderer script tag not found");
writeFileSync("dist/renderer/index.html", shipped);
cpSync("src/ui/styles.css", "dist/renderer/styles.css");
cpSync("assets", "dist/assets", { recursive: true });
console.log("build ok");
