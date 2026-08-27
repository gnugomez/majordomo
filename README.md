# Majordomo 📬

A little macOS menu bar app that puts your GitHub and GitLab stuff — issues,
PRs, MRs, mentions — in one inbox.

- 🔔 Get notified when someone mentions you or asks for a review
- 🗂 One list for everything, with groups per kind
- 🪟 Native look: Liquid Glass, your accent color, light and dark
- 🔑 Sign in by pasting a personal access token — GitHub needs the
  `notifications` scope, GitLab needs `read_api`
- 🔒 Everything stays on your Mac. Read-only, no backend, tokens in the
  keychain

## Install

Grab `Majordomo-darwin-arm64.zip` from the
[latest release](https://github.com/gnugomez/majordomo/releases), unzip, and
drop `Majordomo.app` into `/Applications`. First launch: right-click → Open
(the app isn't notarized), and enable Majordomo under System Settings →
Notifications if you want notifications.

## Build

```sh
npm install
npm start          # run it
npm run package    # build release/Majordomo-darwin-arm64/Majordomo.app
```

Want to help? See [CONTRIBUTING.md](CONTRIBUTING.md). Releases are described
in [RELEASING.md](RELEASING.md). Licensed under [GPL-3.0](LICENSE).
