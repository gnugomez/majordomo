// Dev loop (`pnpm dev`): Vite serves the renderer with hot module
// replacement, while esbuild watches main + preload and relaunches Electron
// whenever they change. Production builds (scripts/build.mjs) stay on plain
// esbuild and are unaffected.
import { spawn } from "node:child_process";
import { cpSync } from "node:fs";
import process from "node:process";
import react from "@vitejs/plugin-react";
import electronPath from "electron";
import { context } from "esbuild";
import { createServer } from "vite";

// The strict production CSP in index.html blocks Vite's dev client (inline
// refresh preamble, injected styles, HMR WebSocket) — relax it in dev only.
const DEV_CSP
  = "default-src 'none'; style-src 'self' 'unsafe-inline'; "
    + "script-src 'self' 'unsafe-inline'; img-src 'self' data:; "
    + "connect-src 'self' ws:";

const vite = await createServer({
  configFile: false,
  root: "src/ui",
  clearScreen: false,
  plugins: [
    react(),
    {
      name: "majordomo-dev-csp",
      transformIndexHtml: (html) =>
        html.replace(/content="default-src[^"]*"/, `content="${DEV_CSP}"`),
    },
  ],
});
await vite.listen();
const devServerUrl = vite.resolvedUrls?.local[0];
if (!devServerUrl)
  throw new Error("Vite did not report a local URL");
vite.printUrls();

// The tray reads its icons from dist/assets at runtime.
cpSync("assets", "dist/assets", { recursive: true });

let electron = null;
let restarting = false;
let quitting = false;

function launch() {
  electron = spawn(electronPath, ["."], {
    stdio: "inherit",
    env: { ...process.env, MAJORDOMO_DEV_SERVER_URL: devServerUrl },
  });
  electron.on("exit", () => {
    if (quitting)
      return;
    if (restarting) {
      restarting = false;
      launch();
    } else {
      // Quit from the tray — wind the dev loop down with it.
      void shutdown();
    }
  });
}

/** (Re)start Electron; the first successful build lands here as the launcher. */
function relaunch() {
  if (electron === null) {
    launch();
    return;
  }
  if (restarting)
    return;
  restarting = true;
  electron.kill();
}

const ctx = await context({
  entryPoints: ["src/electron/index.ts", "src/electron/preload.ts"],
  bundle: true,
  platform: "node",
  format: "cjs",
  external: ["electron", "electron-liquid-glass"],
  outdir: "dist/main",
  plugins: [
    {
      name: "electron-relaunch",
      setup(build) {
        build.onEnd((result) => {
          if (result.errors.length === 0)
            relaunch();
        });
      },
    },
  ],
});
await ctx.watch();

async function shutdown() {
  quitting = true;
  electron?.kill();
  await ctx.dispose();
  await vite.close();
  process.exit(0);
}

process.on("SIGINT", () => void shutdown());
process.on("SIGTERM", () => void shutdown());
