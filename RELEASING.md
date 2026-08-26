# Releasing

Releases are automated with [changesets](https://github.com/changesets/changesets)
and GitHub Actions. No one bumps versions by hand.

## The flow

1. **Every user-visible PR carries a changeset** (`npx changeset`): a small
   markdown file under `.changeset/` naming the bump level (patch/minor/major)
   and describing the change.
2. **When changesets land on `main`**, the Release workflow opens (or updates)
   a PR called **"chore: version release"**. It applies all pending
   changesets: bumps `package.json`, writes `CHANGELOG.md`, and deletes the
   consumed changeset files.
3. **Merging that PR cuts the release.** The workflow tags `vX.Y.Z`, creates
   the GitHub release with the changelog notes, packages `Majordomo.app` on a
   macOS runner, and attaches `Majordomo-darwin-arm64.zip` to the release.

So the release cadence is simply: merge the version PR whenever you want to
ship what has accumulated.

## Installing a released build

Download the zip from the GitHub release, unzip, drag `Majordomo.app` into
`/Applications`. Builds are ad-hoc signed, not notarized, so Gatekeeper will
quarantine the download: either right-click → Open the first time, or run

```sh
xattr -dr com.apple.quarantine /Applications/Majordomo.app
```

Ad-hoc signing also means macOS never shows the notification permission
prompt — the first delivery attempt is silently denied. The app still appears
under **System Settings → Notifications**, and enabling it there makes
new-mention notifications work normally. Worse, ad-hoc signatures carry no
stable identity, so macOS forgets that enablement (and other per-app
permissions) every time a differently-built copy replaces the app.

Both papercuts disappear with a stable signing identity. `npm run package`
honors `CODESIGN_IDENTITY`, and with no env var set it automatically uses a
keychain identity named **"Majordomo Dev"** when one exists — create one once
(a self-signed code-signing certificate via Keychain Access's Certificate
Assistant, or openssl + `security import`) and every local build signs
consistently, so permissions persist across updates. Proper Developer ID
signing + notarization in CI is the long-term fix — it needs an Apple
Developer account and signing secrets in the repo.

## Local/manual release build

```sh
npm run package
# → release/Majordomo-darwin-arm64/Majordomo.app
```

This renders the app icon from `assets/appicon.svg`, bundles with
`@electron/packager` (asar, pruned dev deps, `LSUIElement`), and ad-hoc
re-signs the bundle so Apple Silicon will launch it.
