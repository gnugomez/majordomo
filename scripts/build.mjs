import { build } from "esbuild";
import { cpSync, mkdirSync } from "node:fs";

mkdirSync("dist/renderer", { recursive: true });

await Promise.all([
  build({
    entryPoints: ["src/main/index.ts"],
    bundle: true,
    platform: "node",
    format: "cjs",
    external: ["electron"],
    outfile: "dist/main/index.js",
  }),
  build({
    entryPoints: ["src/main/preload.ts"],
    bundle: true,
    platform: "node",
    format: "cjs",
    external: ["electron"],
    outfile: "dist/main/preload.js",
  }),
  build({
    entryPoints: ["src/renderer/index.ts"],
    bundle: true,
    platform: "browser",
    format: "iife",
    outfile: "dist/renderer/index.js",
  }),
]);

cpSync("src/renderer/index.html", "dist/renderer/index.html");
cpSync("src/renderer/styles.css", "dist/renderer/styles.css");
cpSync("assets", "dist/assets", { recursive: true });
console.log("build ok");
