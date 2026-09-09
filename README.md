# Majordomo 🛎️

A native macOS menu bar app that puts your GitHub and GitLab stuff — issues,
PRs, MRs, mentions — in one inbox. Swift + SwiftUI, no dependencies beyond
the SDK.

<table>
  <tr>
    <td align="center">
      <img src=".github/screenshot-window.png" width="760" alt="The Majordomo window: sidebar with per-account sections, inbox list, and item preview" />
    </td>
    <td align="center">
      <img src=".github/screenshot-tray.png" width="340" alt="The Majordomo menu bar inbox" />
    </td>
  </tr>
</table>

- 🔔 Get notified when someone mentions you or asks for a review
- 🗂 One list for everything, with per-account sections and configurable
  inboxes — connect as many GitHub or GitLab accounts as you like
- 🔒 Everything stays on your machine — read-only, no backend, tokens
  encrypted at rest

## Install

With Homebrew (requires macOS 26, Apple silicon):

```sh
brew tap gnugomez/tap && brew trust gnugomez/tap
brew install majordomo
xattr -dr com.apple.quarantine /Applications/Majordomo.app
```

`brew trust` because Homebrew only loads third-party taps it has been told
to trust. The `xattr` line clears Gatekeeper's quarantine — the app is not
notarized; skip it if you prefer approving the app once under
System Settings → Privacy & Security instead.

Or build from source (requires Xcode 26):

```sh
make install   # release build → /Applications/Majordomo.app
```

`make help` lists the rest of the shortcuts — `build`, `bundle`, `run`,
`demo`, `clean`. They're thin wrappers over `swift build` and `scripts/`.

Two one-time papercuts of an unsigned build:

- **Keychain**: the token-encryption key lives in your Keychain; because the
  app is ad-hoc signed, a rebuilt binary re-prompts for access once per
  build — click **Always Allow**.
- **Notifications**: macOS shows no permission prompt for ad-hoc-signed
  apps — enable Majordomo once under System Settings → Notifications.

## Roadmap
The whole objective of this project is to consolidate all the notifications you
are used to receive from other places in a single place and at the same time
receive desktop notifications for your awareness.

Right now it's only supporting github and gitlab notifications, but the objective would
be to implement as many providers as people find useful, people may have systems like
Jira or any other alternative, this project is a good place to keep notifications in a 
single place, secure and easy to reach.

## Tokens

Add accounts from Settings (⌘,) by pasting a personal access token:

| Provider | Scope |
| --- | --- |
| GitHub | `notifications` (classic token) |
| GitLab (self-hosted) | `read_api` |

Tokens are stored AES-GCM encrypted in the app's data file; the key is a
single Keychain item.

Want to help? See [CONTRIBUTING.md](CONTRIBUTING.md). Releases are described
in [RELEASING.md](RELEASING.md). Licensed under [GPL-3.0](LICENSE).
