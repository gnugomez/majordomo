# Contributing to Majordomo

Thanks for your interest! Majordomo is a macOS menu-bar app that unifies
GitHub and self-hosted GitLab issues, PRs, and MRs into one mentions-first
inbox. Contributions of all sizes are welcome.

## Getting set up

You need macOS (the app is macOS-only) and Node.js 22+.

```sh
npm install
npm start          # build with esbuild, launch Electron
npm run typecheck  # strict TypeScript, no emit
npm run package    # produce release/Majordomo-darwin-arm64/Majordomo.app
```

If you have a packaged copy of Majordomo installed and running, point your dev
build at a scratch profile so both can run side by side:

```sh
MAJORDOMO_USERDATA=/tmp/majordomo-dev npm start
```

## How the code is laid out

- `src/shared/` — domain types and the IPC contract. Imported by everything,
  imports nothing. If you change an interface here, everything downstream
  must follow.
- `src/providers/` — one client per provider behind the `ProviderClient`
  contract documented in `providers/types.ts`. GitHub uses `@octokit/rest`
  (notifications API), GitLab uses `@gitbeaker/rest` (todos API); both load
  lazily and normalize to `FetchedItem`. To add a provider, implement
  `ProviderClient` and register it in `createProviders()`. Friendly error
  strings live in `providers/errors.ts` — they surface verbatim in the UI.
- `src/electron/` — the Electron shell: tray, Liquid Glass popover window,
  sync loop, encrypted token store, notifications, preload bridge.
- `src/ui/` — the popover UI in React: `App.tsx` + `hooks/` own state,
  `inbox/` and `settings/` hold the feature components, `components/` the
  shared bits (icons are typed JSX SVGs). Bundled by esbuild — no vite, no
  CSS-in-JS; the design tokens live in `styles.css`.

## Design principles

- **Lean.** React for the UI and official API clients for the providers, but
  no state libraries, routers, or speculative abstraction. The only runtime
  dependency in the shipped bundle's node_modules is `electron-liquid-glass`;
  everything else is inlined by esbuild.
- **Native-feeling.** The popover should read as a macOS menu, not a web
  page: system font, glass material, alpha-based colors that work over any
  wallpaper, light and dark.
- **Read-only.** The app never writes back to GitHub or GitLab. Read state
  is local.
- **Local-only.** No backend, no telemetry. Tokens are encrypted with the
  macOS keychain via Electron's `safeStorage`.

## Pull requests

1. Keep the change focused; match the style of the surrounding code
   (strict TypeScript, double quotes, 2-space indent).
2. `npm run typecheck` and `npm run build` must pass — CI enforces both.
3. If your change is user-visible (feature, fix, behavior change), add a
   changeset: `npx changeset`, pick a bump level, and write one sentence a
   user would understand. Internal-only changes (docs, CI, refactors) don't
   need one.
4. For UI changes, include a screenshot over a busy wallpaper — glass
   surfaces can hide contrast problems on plain backgrounds.

Releases are cut from `main` via changesets; see [RELEASING.md](RELEASING.md).
