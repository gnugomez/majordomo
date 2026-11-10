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
- `Sources/Majordomo/Store/` — the JSON persistence and token encryption
  (`Store`, written off the engine's actor by `StoreWriter` a moment after
  a change), the targets' conversations, a file each beside the store,
  and the images previews have shown, kept within a size under the user's
  Caches.
- `Sources/Majordomo/Sync/` — the sync engine, one actor split by concern:
  `SyncEngine.swift` (the change log, `settle`, publishing, the streams,
  start and stop), `EngineChange.swift` (the reaction table), and the
  `SyncEngine+…` extensions — `Accounts`, `Fetch` (syncing and arrivals),
  `Sweep` (labels, rules, boards, sidebar), `Inbox` (read state, label
  overrides), `Intelligence` (the model's passes, with `ModelPass` holding
  what they share), `Composer`, `Targets`, `Images`. Beside it the pure
  engines it runs — `RuleEngine`, `BoardEngine` — and the on-device model's
  protocol.
- `Sources/Majordomo/App/` — the AppKit shell: status item and tray menu,
  windows, notifications, main menu, and `AppModel`, the main actor's
  mirror of the engine's state and the views' one model; it composes
  `Preferences` (everything kept in UserDefaults, through one
  `PreferenceKey` mechanism) and `ConversationCache` (the conversations
  the preview reads).
- `Sources/Majordomo/UI/` — the SwiftUI views. The app's own colors live
  in `Palette.swift` and its text sizes in `Typography.swift`
  (`.font(.app(.caption))`); reach for those rather than a literal.

`Tests/MajordomoTests/` holds the Swift Testing suite, which reaches the
app target through `@testable import Majordomo`.

## How state flows

The sync engine is the one writer. Everything it knows changes inside the
actor, in three steps:

1. **A change.** A mutation — a fetch applied, a rule saved, a card
   pinned, the model's answers filed — does its own work on the store and
   records what it touched: `record(.rules)`, `record([.accounts,
   .itemContent])`. It calls nothing else.
2. **Reactions.** Once per actor turn, however many mutations it gathered,
   `settle` looks the changes up in the reaction table
   (`EngineChange.reactions`, `Sync/EngineChange.swift`) and does what
   they call for, in a fixed order: forget stale answers, sweep (relabel
   for what label rules read, or only re-place the boards), reconcile the
   sidebar, announce arrivals, prune; then start the background work — a
   target refresh round, the model's summary, verdict, and suggestion
   passes. The table is the whole of "what depends on what": a rules
   change relabels and asks the model again; a pin only re-places; a read
   only re-places and republishes the items.
3. **One push.** `settle` rebuilds only the slices of `AppState` the
   changes could move (`EngineChange.slices`), moves the revision
   (`StateRevisions`) of each that did, and pushes the state once.
   `AppModel.apply` compares revisions — integers — and assigns only the
   slices that moved, so a push about one card costs the views nothing
   else. Slices the app model edits ahead of the engine (labels, rules,
   the sidebar, boards, a pin) always move their revision when the engine
   takes the edit (`EngineChange.echoes`), so the model ends on the
   engine's version.

Two streams leave the engine, one per subscriber: `states()` (latest
wins — a slow reader skips to the newest) and `events()` (every
`DomainEvent`, in order: fresh threads worth a banner, an account failing,
a token rejected, an account working again). `AppDelegate` runs one
main-actor loop over each — the states into `AppModel`, the events into
banners and the log — and keeps the tray dot and dock badge in step with
the model through `Observations`.

The store notes each change and writes a moment later (`flushSoon`), in
one write however many changes followed, encoded and written off the
actor; quitting (`applicationWillTerminate` → `SyncEngine.stop`) writes
what is pending before the app exits.

**Adding a feature.** Something the engine should do *after* a kind of
change is an entry in the reaction table — a new `Reactions` member, or a
new `EngineChange` its mutation records — never a call added to every
mutation that might need it. Something the app should do *when* a thing
happens subscribes: add a `DomainEvent` case if the engine doesn't tell
it yet, `emit` it where it happens, and consume `engine.events()` where
the feature lives. Something the views should show is a slice of
`AppState` (or derived from one in `AppModel`, worked out once per push).

## The provider contract

The core is a generic notification manager: an item's `kind`, `state`, and
`reason` are **opaque tokens** the core never interprets. Everything about
how a provider's items look and read — glyphs, colors, capsule labels,
sidebar buckets and their wording — comes from the provider's `ProviderSpec`
implementation (in code, not from the API). The buckets are built-in labels
(`builtinLabels`) and the rules that fill them (`builtinRules`), evaluated
by the same `RuleEngine` as the user's own labels and rules: they show as
inboxes in the sidebar, list read-only in the Labels and Rules settings,
and can be hidden from the Inboxes page. Buckets sharing an id merge into
one inbox holding every provider's items, named in the first
registration's wording.

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
   assignees, reviewers, review, checks, and merge tokens, a work item's
   status under its stage token (`WorkStatus`), the latest commenter,
   and for the keys it is asked to, the conversation: who
   opened the target and when, its description and latest comments as
   Markdown, each with its author's picture, and events worth a place
   among them — a review's verdict — as entries carrying an event token,
   words optional (`TargetConversation`, `DetailComment`; every field a
   refresh may not fill is optional, so stored files from before it still
   read). The engine asks after new activity first, then fills in the
   conversations it lacks; a target the provider won't show comes back
   unreadable with the reason, and keys left out of the answer are asked
   again next round. Errors are human-readable `ProviderError` strings,
   which render verbatim in the UI, a missing token scope named as such.
   The images a body shows come through the client too (`fetchImage`,
   anonymous by default): the account's token goes only to the provider's
   own API origin over https — never to an image host — and
   `RedirectGuard` strips it from any redirect off that origin;
2. a `ProviderSpec` with the presentation for those tokens and its built-in
   labels and rules (`GitForgeBuckets` builds the git-forge set), plus a
   `previewScopeNote` when previews need a scope beyond the token hint's,
   and the board hooks: which target an item is about (`boardKey`), the
   comment it points at (`triggerCommentId`), which states are finished,
   the review, checks, merge, and status badges (marked `needsAction`
   when they say something must be done — what a cramped inbox row
   keeps), and the token vocabulary the board editor offers. The badges
   draw on board cards and, through `TargetBadges`, on inbox rows, whose
   glyph and capsule read the target's current state once it has been
   refreshed.
   For previews: the mark an event token wears in the conversation
   (`eventBadge`) and where a link or image a body writes points
   (`bodyURL` — GitLab's uploads are relative to the project);
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
views only narrow a placement by the search and the toolbar's filter.

Any number of accounts per provider can be connected; accounts are keyed by
`AccountId`, never by provider. The sidebar keeps no section per account:
every inbox holds every account's items, the toolbar's Provider filter
narrows to one provider's, and an account whose sync fails shows at the
sidebar's foot, opening Settings on Accounts, until it works again.

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
