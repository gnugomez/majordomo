# Releasing

Releases are automated with [release-please](https://github.com/googleapis/release-please)
and GitHub Actions, driven entirely by [conventional commits](https://www.conventionalcommits.org)
(`feat:`, `fix:`, `refactor:`, `chore:`, …). No one bumps versions by hand and
there are no release side-files to maintain.

## The flow

1. **Land conventional commits on `main`.** `feat:` bumps the minor version,
   `fix:` the patch, and a `BREAKING CHANGE:` footer (or `!`) the major.
2. **release-please maintains a release PR** that accumulates everything
   unreleased: it bumps `package.json`, updates `CHANGELOG.md`, and rewrites
   itself as more commits land.
3. **Merging that PR cuts the release.** The workflow tags `vX.Y.Z`, creates
   the GitHub release with the changelog notes, and attaches one artifact per
   platform and architecture: `Majordomo-macos-arm64.dmg`,
   `Majordomo-macos-x64.dmg`, `Majordomo-windows-x64-Setup.exe`, and
   `Majordomo-windows-arm64-Setup.exe`. Linux has no prebuilt artifact —
   it's self-build (`pnpm package:linux`).

Release cadence is simply: merge the release PR whenever you want to ship.

## Signing

CI signs every release with the same certificate, imported from repo secrets —
a **stable identity across releases**, so macOS keeps the user's per-app
permissions (notifications, login item) through updates instead of resetting
them the way rotating ad-hoc signatures do.

- `MACOS_SIGN_P12` — base64 of a PKCS#12 bundle holding a code-signing
  certificate named **"Majordomo Dev"** (self-signed is fine).
- `MACOS_SIGN_P12_PASSWORD` — its password.

If the secrets are absent the build falls back to ad-hoc signing. The same
identity can be imported into a local keychain so `pnpm package` produces
identically-signed builds on a dev machine (`scripts/package.mjs` picks up a
"Majordomo Dev" keychain identity automatically, or honors
`CODESIGN_IDENTITY`).

Self-signed still means no notarization: Gatekeeper quarantines downloads
(right-click → Open the first time, or
`xattr -dr com.apple.quarantine /Applications/Majordomo.app`), and macOS
never shows the notification permission prompt — enable Majordomo once under
System Settings → Notifications. Swapping the secret for a real Developer ID
certificate and adding notarization removes both papercuts.

## Installing a released build

Download the DMG from the GitHub release, open it, drag `Majordomo.app` into
`/Applications`, and see the Gatekeeper note above.

## Local/manual release build

```sh
pnpm package
# → release/Majordomo-darwin-arm64/Majordomo.app

pnpm install:app
# same build, then installed on this machine (any platform)
```

This bundles with `@electron/packager` (asar, pruned dev deps,
`LSUIElement`) and re-signs the bundle (stable identity when available,
ad-hoc otherwise). App icons for every platform are committed and come from
`assets/majordomo.icon` (the Icon Composer document) — after changing it,
regenerate them with `pnpm icons:app` (needs macOS 26 + Xcode 26). Packaging
on a macOS 26 host also embeds the layered Assets.car icon; elsewhere the
flat `.icns` fallback ships alone.
