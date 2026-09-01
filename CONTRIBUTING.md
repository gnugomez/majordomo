# Contributing to Majordomo

Thanks for your interest! Majordomo is a menu-bar/tray app for macOS,
Windows, and Linux that unifies GitHub and self-hosted GitLab issues, PRs,
and MRs into one inbox. Contributions of all sizes are welcome.

## Getting set up

You need Node.js 22+ (any OS; the glass material and DMG packaging are
macOS-specific, everything else is cross-platform). Dependencies are managed
with pnpm — `corepack enable pnpm` gives you the version pinned in
`package.json`.

```sh
pnpm install
pnpm start         # build with esbuild, launch Electron
pnpm typecheck     # strict TypeScript, no emit
pnpm lint          # ESLint (antfu config); pnpm lint:fix autofixes
pnpm package       # produce release/Majordomo-darwin-arm64/Majordomo.app
pnpm install:app   # build, package, and install on this machine
```

`pnpm-workspace.yaml` sets `nodeLinker: hoisted`: `@electron/packager` copies
`node_modules` into the app bundle and prunes it by walking the tree, which a
symlinked layout would break. It also lists the two packages allowed to run
install scripts.

A note on the TypeScript packages: `pnpm typecheck` runs the native
TypeScript 7 `tsc` (installed as `@typescript/native`), while the
`typescript` name resolves to Microsoft's `@typescript/typescript6`
compatibility package — typescript-eslint needs the TS 6 JS API, and this is
the side-by-side setup the TypeScript 7 announcement documents.

If you have a packaged copy of Majordomo installed and running, point your dev
build at a scratch profile so both can run side by side:

```sh
MAJORDOMO_USERDATA=/tmp/majordomo-dev pnpm start
```

## How the code is laid out

- `src/shared/` — domain types and the IPC contract. Imported by everything,
  imports nothing. If you change an interface here, everything downstream
  must follow.
- `src/providers/` — one client per provider behind the `ProviderClient`
  contract documented in `providers/types.ts`. GitHub uses `@octokit/rest`
  (notifications API), GitLab uses `@gitbeaker/rest` (todos API); both load
  lazily and normalize to `FetchedItem`. Friendly error strings live in
  `providers/errors.ts` — they surface verbatim in the UI.
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
- **Native-feeling.** The popover should read as a system menu, not a web
  page: system font, glass/acrylic material where the OS offers one,
  alpha-based colors that work over any wallpaper, light and dark.
- **Read-only.** The app never writes back to the providers. Read state is
  local.
- **Local-only.** No backend, no telemetry. Tokens are stored encrypted via
  Electron's `safeStorage` (key derived from the macOS Keychain, Windows
  DPAPI, or the Linux Secret Service). Don't move them into per-item OS
  keychain entries: on macOS those re-prompt for access on every rebuild of
  a non-Developer-ID-signed app.

## Adding a provider

Everything downstream of a provider only sees `FetchedItem`s, so a new
provider (Gitea, Bitbucket, Jira, …) is a contained change:

1. **Implement `ProviderClient`** (`src/providers/types.ts` documents the
   rules) in a new `src/providers/<name>.ts`: `validate(config)` checks the
   token and returns the username; `fetchItems(config)` returns the
   account's current inbox as a `FetchResult` — the `FetchedItem`s plus a
   `complete` flag (set it `false` whenever a page cap may have truncated
   the list, so the sync engine never mistakes a capped-out item for a
   handled one). Use the provider's official
   client library if a maintained one exists, load it lazily (see
   `github.ts`), and map failures to human-readable strings — they render
   verbatim in the Accounts pane (reuse `providers/errors.ts`).
   Key mapping decisions: `id` must be stable across fetches
   (`"<name>:<externalId>"` — it's the dedup and read-state key), and
   `isMention` marks what deserves a notification and the Mentions group
   (mentions, direct addresses, review requests).
2. **Register it**: add the id to the `ProviderId` union in
   `src/shared/types.ts` and the instance to `createProviders()` in
   `src/providers/index.ts`.
3. **Teach the UI about it**: a small monochrome glyph in
   `src/ui/components/Icons.tsx`, the display name in
   `src/ui/components/Banner.tsx`, and an entry in the `PROVIDERS` list in
   `src/ui/settings/SettingsPane.tsx` (set `needsBaseUrl: true` for
   self-hosted services so the URL field shows).

The typechecker walks you through the rest — extending `ProviderId` flags
every switch that needs the new case.

## Pull requests

1. Keep the change focused; match the style of the surrounding code
   (strict TypeScript, double quotes, 2-space indent).
2. `pnpm typecheck`, `pnpm lint`, and `pnpm build` must pass — CI
   enforces all three.
3. Use [conventional commits](https://www.conventionalcommits.org) —
   releases and the changelog are generated from them by release-please.
   `feat:` for user-visible features, `fix:` for bug fixes, `refactor:`/
   `chore:`/`docs:` for the rest; add a `BREAKING CHANGE:` footer when
   behavior breaks. If a PR is squash-merged, its title becomes the commit
   message, so title PRs conventionally too.
4. For UI changes, include a screenshot over a busy wallpaper — glass
   surfaces can hide contrast problems on plain backgrounds.

Releases are cut from `main` by release-please; see [RELEASING.md](RELEASING.md).
