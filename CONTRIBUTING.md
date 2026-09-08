# Contributing to Majordomo

Thanks for your interest! Majordomo is a native macOS menu-bar app that
unifies GitHub and self-hosted GitLab notifications into one inbox.
Contributions of all sizes are welcome.

## Getting set up

You need macOS 26 and Xcode 26 (Swift 6.3+). There are no package
dependencies — SwiftPM with the SDK only.

```sh
swift build              # compile (debug); must stay warning-free
./scripts/bundle.sh      # release build → dist/Majordomo.app (ad-hoc signed)
./scripts/install.sh     # same, then installed to /Applications
```

A bare `swift run` works for quick iteration, but launch-at-login and
notifications need a real bundle, so those are disabled outside
`Majordomo.app` (a warning is logged). For visual checks,
`MAJORDOMO_OPEN_MAIN=1` opens the main window at launch — no trip through
the tray menu needed.

## How the code is laid out

Layers, lower never importing higher:

- `Sources/Majordomo/Model/` — domain types. Imports Foundation only;
  knows nothing about providers' vocabularies or the UI.
- `Sources/Majordomo/Providers/` — one `ProviderClient` (API → items) and
  one `ProviderSpec` (presentation) per provider, registered in
  `providerSpecs`.
- `Sources/Majordomo/Store/` — the JSON persistence and token encryption.
- `Sources/Majordomo/Sync/` — the sync engine (an actor): fetch, reconcile,
  publish state.
- `Sources/Majordomo/App/` — the AppKit shell: status item and tray menu,
  windows, notifications, main menu.
- `Sources/Majordomo/UI/` — the SwiftUI views.

## The provider contract

The core is a generic notification manager: an item's `kind`, `state`, and
`reason` are **opaque tokens** the core never interprets. Everything about
how a provider's items look and read — glyphs, colors, capsule labels,
sidebar buckets and their wording — comes from the provider's `ProviderSpec`
implementation (in code, not from the API). Adding a provider means:

1. a `ProviderClient` that speaks the API and normalizes to `FetchedItem`
   tokens (errors as human-readable `ProviderError` strings — they render
   verbatim in the UI);
2. a `ProviderSpec` with the presentation for those tokens;
3. one registration line in `providerSpecs`.

Any number of accounts per provider can be connected; accounts are keyed by
`AccountId`, never by provider.

## Style

- Strict Swift 6 concurrency: actors for shared mutable state, `Sendable`
  values across boundaries, `@MainActor` for AppKit/SwiftUI.
- 2-space indent, one type per file where sensible. Prefer extracting a
  well-named helper over a clever one-liner — readability wins, even for
  single-use code.
- `swift build` must pass with zero warnings.

## Design principles

- **Read-only** against providers: fetch and display, never mutate upstream.
- **Local-only**: no backend, no telemetry.
- **Tokens at rest** are AES-GCM encrypted in the JSON store; the key is a
  single Keychain item — never per-item keychain entries (their ACLs pin the
  exact build hash for unsigned apps and re-prompt on every rebuild).
