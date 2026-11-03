# Contributing to Majordomo

Thanks for your interest! Majordomo is a native macOS menu-bar app that
unifies GitHub and self-hosted GitLab notifications into one inbox.
Contributions of all sizes are welcome.

## Getting set up

You need macOS 26 and Xcode 26 (Swift 6.3+). There are no package
dependencies — SwiftPM with the SDK only.

```sh
make build      # compile (debug); must stay warning-free
make test       # the Swift Testing suite in Tests/MajordomoTests
make bundle     # release build → dist/Majordomo.app (ad-hoc signed)
make install    # same, then installed to /Applications
make demo       # run on fixture data — no accounts, network, or Keychain
```

(`make help` lists everything; the targets are thin wrappers over
`swift build`, `swift test`, and `scripts/`.)

A bare `swift run` works for quick iteration, but launch-at-login and
notifications need a real bundle, so those are disabled outside
`Majordomo.app` (a warning is logged). For visual checks,
`MAJORDOMO_OPEN_MAIN=1` opens the main window at launch — no trip through
the tray menu needed — and `MAJORDOMO_OPEN_SETTINGS=Labels` (any tab
label) opens the settings window on that tab; `MAJORDOMO_DEMO=1` is what
`make demo` sets.

## How the code is laid out

Layers, lower never importing higher:

- `Sources/Majordomo/Model/` — domain types. Imports Foundation only;
  knows nothing about providers' vocabularies or the UI.
- `Sources/Majordomo/Providers/` — one `ProviderClient` (API → items) and
  one `ProviderSpec` (presentation) per provider, registered in
  `providerSpecs`.
- `Sources/Majordomo/Store/` — the JSON persistence and token encryption,
  and the targets' conversations, a file each beside the store.
- `Sources/Majordomo/Sync/` — the sync engine (an actor): fetch, reconcile,
  sweep the rules and boards, publish state.
- `Sources/Majordomo/App/` — the AppKit shell: status item and tray menu,
  windows, notifications, main menu.
- `Sources/Majordomo/UI/` — the SwiftUI views.

`Tests/MajordomoTests/` holds the Swift Testing suite, which reaches the
app target through `@testable import Majordomo`.

## The provider contract

The core is a generic notification manager: an item's `kind`, `state`, and
`reason` are **opaque tokens** the core never interprets. Everything about
how a provider's items look and read — glyphs, colors, capsule labels,
sidebar buckets and their wording — comes from the provider's `ProviderSpec`
implementation (in code, not from the API). The buckets are built-in labels
(`builtinLabels`) and the rules that fill them (`builtinRules`), evaluated
by the same `RuleEngine` as the user's own labels and rules: they show as
folders, list read-only in the Labels and Rules settings, and can be hidden
from the Inboxes page.

The providers' set and the user's are joined in exactly one place,
`LabelCatalog.current` (`Providers/ProviderSpec.swift`), which hands back a
`LabelCatalog` (`Model/LabelCatalog.swift`) carrying the full label and rule
lists, the built-in/user splits, and id lookup. The sync engine, the app
model, and the settings pages all read it instead of concatenating their
own, so the built-ins-first ordering is decided once.

Adding a provider means:

1. a `ProviderClient` that speaks the API and normalizes to `FetchedItem`
   tokens, and refreshes the targets boards and previews are built from
   (`fetchTargets`, at most `targetBatchLimit` per round: state,
   assignees, reviewers, review, checks, and merge tokens, the latest
   commenter, and for the keys it is asked to, the description and latest
   comments as Markdown). The engine asks after new activity first, then fills in
   the conversations it lacks; a target the provider won't show comes
   back unreadable with the reason, and keys left out of the answer are
   asked again next round. Errors are human-readable `ProviderError`
   strings, which render verbatim in the UI, a missing token scope named
   as such;
2. a `ProviderSpec` with the presentation for those tokens and its built-in
   labels and rules (`GitForgeBuckets` builds the git-forge set), plus a
   `previewScopeNote` when previews need a scope beyond the token hint's,
   and the board hooks: which target an item is about (`boardKey`), the
   comment it points at (`triggerCommentId`), which states are finished,
   the review, checks, and merge badges (marked `needsAction` when they
   say something must be done — what a cramped inbox row keeps), and the
   token vocabulary the board editor offers. The badges draw on board
   cards and, through `TargetBadges`, on inbox rows, whose glyph and
   capsule read the target's current state once it has been refreshed;
3. one registration line in `providerSpecs`.

Label rules, a board's scope, and each board column all hold one kind of
filter (`RuleFilter`, `Model/RuleFilter.swift`): groups of conditions, each
group holding when all or any of its conditions do, joined by the filter's
own all or any. A condition can be an Apple Intelligence check — a question
in the user's words (`RuleField.question`) whose answer the on-device model
gives once per subject and the store keeps under the question's key, so the
same question asked by a rule and by a column shares its answers. One
editor (`FilterEditor`) edits them all, on the Rules page and in the board
editor.

Boards (`Model/Board.swift`) place cards — one per target, built by
`BoardEngine` from the notifications pointing at it and the target's stored
snapshot — into the first column whose filter holds. Filters are compiled
by `RuleEngine` (`Sync/RuleEngine.swift`) and tested against a notification
or a card alike through `RuleSubject`; the fields only a target has
(assignee, review, checks…) are offered to boards alone. The sync engine
runs one sweep over everything a filter reads, whenever any of it changes:
the items' labels and every board's placement from one compiled set,
published with the state, plus the questions whose answers could still move
something — the only ones the model is asked, a budgeted few per pass. The
views only narrow a placement by the search and the pills.

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
- **Read state is local and precious**: nothing is ever marked read
  upstream, so the store is the only record of what was read. Removing an
  account parks its record and items for 90 days (the token goes at once)
  instead of deleting them, and connecting the same user on the same
  instance — a new token, or the account added back — lands on the
  existing record.
- **Tokens at rest** are AES-GCM encrypted in the JSON store; the key is a
  single Keychain item — never per-item keychain entries (their ACLs pin the
  exact build hash for unsigned apps and re-prompt on every rebuild).
