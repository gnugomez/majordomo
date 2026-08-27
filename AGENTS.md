# Agent notes

Majordomo: cross-platform Electron tray app; one inbox for GitHub/GitLab.
Details live in CONTRIBUTING.md (layout, adding a provider) and RELEASING.md.

## Conventions

- **Layout**: `src/shared` (types + IPC; imports nothing) → `src/providers`
  (ProviderClient impls on official client libs) → `src/electron` (shell) and
  `src/ui` (React). Don't cross those lines.
- **Lean**: no state libs, routers, or new deps without a strong reason.
  esbuild bundles everything; only native modules (`electron-liquid-glass`,
  `@napi-rs/keyring`) ship in node_modules — lazy-require them in try/catch
  with a graceful fallback, list them as esbuild externals.
- **Style**: strict TypeScript, double quotes, 2-space indent, one component
  per file. Provider errors are human-readable strings — they render verbatim.
- **UI**: native-feeling over a transparent glass window — alpha-based color
  tokens from `styles.css`, no opaque page-wide backgrounds (except the
  `opaque` / `no-bridge` modes), light + dark, accent via `--accent`. Verify
  visual changes over a busy wallpaper.
- **Commits**: conventional, single-line, no bodies or attribution.
  `feat:`/`fix:` strictly for user-visible changes (they drive the changelog
  and version); `ci:`/`build:` for pipeline work — never `feat:`; `chore:`/
  `docs:`/`refactor:` for the rest. Releases only via release-please — never
  bump versions or edit CHANGELOG.md by hand.
- **Checks**: `npm run typecheck` and `npm run build` must pass. Run a dev
  copy alongside an installed one with `MAJORDOMO_USERDATA=/tmp/dev npm start`;
  the renderer exposes `window.__debugSetState(state)` for injecting fixture
  data during visual checks.
- **Principles**: read-only against providers, local-only (no backend, no
  telemetry), tokens in the OS keychain.
