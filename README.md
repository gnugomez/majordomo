# Majordomo

A macOS menu-bar app that unifies GitHub and self-hosted GitLab issues, pull
requests, and merge requests into a single mentions-first inbox.

- **Menubar popover** — click the tray icon to see the unified inbox; mentions
  and review requests are pinned to the top, everything else sorts by recency.
- **Tray dot** — the menu-bar icon grows a dot whenever unread mentions are
  waiting.
- **Native notifications** — new mentions notify; clicking a notification opens
  the item in your browser. macOS doesn't show the permission prompt for
  un-notarized builds, so enable Majordomo once under System Settings →
  Notifications.
- **Liquid Glass popover** — the window is backed by the native
  `NSGlassEffectView` material on macOS 26+ (via `electron-liquid-glass`),
  falling back to the older frosted vibrancy on earlier systems.
- **PAT auth** — paste a personal access token per provider. Tokens are
  encrypted with the macOS keychain (Electron `safeStorage`) and never leave
  the machine.
- **Read-only and local-only** — no writes back to the providers, no backend.

## Development

```sh
npm install
npm start        # build with esbuild, launch Electron
npm run typecheck
```

## Install

```sh
npm run package  # builds release/Majordomo-darwin-arm64/Majordomo.app
cp -R release/Majordomo-darwin-arm64/Majordomo.app /Applications/
```

Packaging renders the app icon from `assets/appicon.svg` (via an offscreen
Electron window, sips, and iconutil — no extra image tooling), marks the app
`LSUIElement` so it never appears in the Dock, and ad-hoc re-signs the bundle
so Apple Silicon will launch it.

The app polls GitHub's notifications API and GitLab's todos API every 60
seconds. GitHub needs a classic PAT with just the `notifications` scope (or a
fine-grained PAT with the account-level "Notifications" read permission);
GitLab needs a PAT with `read_api`.

## Layout

- `src/shared/` — domain types and the IPC contract; imported by everything, imports nothing.
- `src/providers/` — one client per provider behind the `ProviderClient` contract
  (`providers/types.ts`); GitHub on `@octokit/rest`, GitLab on `@gitbeaker/rest`.
- `src/electron/` — the Electron shell: tray, Liquid Glass popover window, sync
  loop, encrypted token store, notifications, preload bridge.
- `src/ui/` — the popover UI in React, one component per file
  (`inbox/`, `settings/`, `components/`, `hooks/`).
