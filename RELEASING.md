# Releasing

Releases are automated with [release-please](https://github.com/googleapis/release-please)
and GitHub Actions, driven entirely by [conventional commits](https://www.conventionalcommits.org)
(`feat:`, `fix:`, `refactor:`, `chore:`, …). No one bumps versions by hand.

## The flow

1. **Land conventional commits on `main`.** `feat:` bumps the minor version,
   `fix:` the patch, and a `BREAKING CHANGE:` footer (or `!`) the major.
2. **release-please maintains a release PR** that accumulates everything
   unreleased: it bumps `version.txt`, updates `CHANGELOG.md`, and rewrites
   itself as more commits land.
3. **Merging that PR cuts the release.** The workflow tags `vX.Y.Z`, creates
   the GitHub release with the changelog notes, and attaches
   `Majordomo-macos-arm64.dmg` (Apple silicon only for now — the SPM build
   targets the runner's architecture).

Release cadence is simply: merge the release PR whenever you want to ship.

## Signing

CI signs the release with a certificate imported from repo secrets — a
**stable identity across releases**, so macOS keeps the user's per-app
permissions (Keychain access, notifications, login item) through updates
instead of resetting them the way rotating ad-hoc signatures do.

- `MACOS_SIGN_P12` — base64 of a PKCS#12 bundle holding a code-signing
  certificate named **"Majordomo Dev"** (self-signed is fine).
- `MACOS_SIGN_P12_PASSWORD` — its password.

If the secrets are absent the build falls back to ad-hoc signing. Locally,
`CODESIGN_IDENTITY="Majordomo Dev" ./scripts/bundle.sh` signs the same way.

Self-signed still means no notarization: Gatekeeper quarantines downloads
(right-click → Open the first time, or
`xattr -dr com.apple.quarantine /Applications/Majordomo.app`), and macOS
never shows the notification permission prompt — enable Majordomo once under
System Settings → Notifications.

## Local build

```sh
./scripts/bundle.sh    # → dist/Majordomo.app
./scripts/install.sh   # same build, installed to /Applications
```

The app icon comes from `assets/majordomo.icon` (the Icon Composer source);
`assets/appicon.icns` is the committed export the bundle ships.
