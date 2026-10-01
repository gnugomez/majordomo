# Agent notes

Majordomo: native macOS (Swift + SwiftUI) menu-bar app; one inbox for
GitHub/GitLab. Details live in CONTRIBUTING.md (layout, adding a provider)
and RELEASING.md.

## Conventions

- **Layout**: `Model` (types; imports nothing UI) → `Providers`
  (ProviderClient + ProviderSpec per provider) → `Store`/`Sync` →
  `App` (AppKit shell) and `UI` (SwiftUI). Don't cross those lines.
- **Provider decoupling**: the core is token-generic — item kind/state/reason
  are opaque strings. ALL presentation (glyphs, colors, capsule labels) and
  the sidebar buckets come from the provider's `ProviderSpec`, registered in
  `providerSpecs`. Buckets are built-in labels plus the rules that fill
  them (`builtinLabels`/`builtinRules`), run by the same `LabelEngine` as
  the user's labels and rules; they list read-only in settings and hide
  from the Inboxes page. `LabelCatalog.current` is the ONE place the full
  set is assembled (built-ins first, then the user's) — read it from
  `AppModel.catalog` or the engine's `catalog()` rather than composing
  unions at a call site. Never interpret provider tokens in core/UI code.
- **Style**: strict Swift 6 concurrency, 2-space indent, one type per file
  where sensible; extract well-named helpers over clever one-liners.
  Provider errors are human-readable strings — they render verbatim.
- **Comments describe the present**: document what the code does now and
  why, never what it used to be. No lineage ("ported from src/…", "the
  Swift side of …", "like the Electron app"), no removed alternatives, no
  "previously/formerly/no longer". Keep the rationale, drop the history —
  "a real NSMenu, not a hand-positioned popover: it dismisses like every
  other menu" earns its place; "rather than the Electron port's popover"
  does not. When a change makes a nearby comment wrong, fix the comment in
  the same commit. Git and CHANGELOG.md are where history lives.
- **Checks**: `make build` (`swift build`) must pass with zero warnings.
  `make bundle` → dist/Majordomo.app (release, ad-hoc signed unless
  `CODESIGN_IDENTITY` is set — it passes through make); `make install`
  installs it. `make help` lists the rest; the targets are thin wrappers
  over SwiftPM and `scripts/`. For visual checks `make demo` is the shortest
  path — fixture data, no accounts, network, or Keychain prompt, main window
  open at launch (`MAJORDOMO_DEMO=1` + `MAJORDOMO_OPEN_MAIN=1`); screenshot
  via `screencapture -l<CGWindowID>`.
- **Commits**: conventional, single-line, no bodies or attribution.
  `feat:`/`fix:` strictly for user-visible changes (they drive the changelog
  and version); `ci:`/`build:` for pipeline work — never `feat:`; `chore:`/
  `docs:`/`refactor:` for the rest. Releases only via release-please — never
  bump version.txt or edit CHANGELOG.md by hand.
- **Principles**: read-only against providers, local-only (no backend, no
  telemetry), tokens AES-GCM encrypted in the JSON store with a single
  Keychain-held key (never per-item keychain entries — see CONTRIBUTING.md).

## Platform quirks (expected, not bugs)

- Ad-hoc signing re-prompts Keychain access once per rebuild, and startup
  BLOCKS on that prompt (the store reads the key during launch). "Always
  Allow" clears it for that binary.
- macOS shows no notification permission prompt for ad-hoc-signed apps;
  delivery needs one manual enable in System Settings → Notifications.
- The time-sensitive notification entitlement is restricted: signed without
  an Apple-issued provisioning profile that grants it, the app is SIGKILLed
  at launch (ad-hoc and self-signed alike). `scripts/bundle.sh` therefore
  applies it only with `MACOS_PROVISION_PROFILE` set — never add it to the
  plain signing path. Unprofiled builds post Urgent banners at the normal
  level, which is a downgrade, not a failure. See RELEASING.md.

## Load-bearing workarounds — do not "clean up"

Each of these fixes a real SwiftUI/AppKit-bridge failure; removing them
reintroduces the bug:

- The detail column's mark-read and open items are always present, merely
  disabled when nothing is selected (MainWindowView): an empty detail
  section sends the list column's toolbar items to the window's far corner
  (a `ToolbarSpacer` instead draws a stray separator stub), and a section
  whose item count changes shifts the date filter a few points relative to
  the search field, because a real item carries a glass background and a
  hidden placeholder does not.
- `NSHostingController.sizingOptions = []` on the main window
  (MainWindowController): otherwise SwiftUI snaps the window back to its
  preferred size after the autosaved frame restores — and autosaves that.
- `shouldCascadeWindows = false` plus the CONTROLLER-level
  `windowFrameAutosaveName` (MainWindowController): window-level
  `setFrameAutosaveName` alone loses the position on every show.
- Empty states in detail panes are wrapped in `ScrollView` +
  `containerRelativeFrame` (PreviewView, MainWindowView): non-scrolling
  content makes the toolbar draw a hard edge line across the pane.
- `orderFrontRegardless()` after `NSApp.activate()` when opening windows:
  cooperative activation can deny the focus steal and the window would open
  buried.
- `pairFilterWithSearch()` (MainWindowController) moves the toolbar's
  trailing flexible space ahead of the date-filter item: SwiftUI lays the
  trailing end out as [items][flexible space][search] and offers no
  placement after the spacer (`.primaryAction`, `ToolbarSpacer`, and
  `DefaultToolbarItem(kind: .search)` all land before it). It re-runs on
  the toolbar's add/remove notifications because selection changes re-diff
  the detail items.
- The inbox list is nudged half a point wider, for one frame, whenever the
  pinned box's shape changes (`InboxListView`): a List row is measured
  once, when it arrives, and keeps that height — and the box arrives, and
  grows a line at a time, as the model answers, so it drew clipped. A width
  change is what makes the table measure again (dragging the column divider
  fixed it by hand); the nudge is that drag, done for the user. Nothing
  else worked: not `fixedSize`, not an explicit row height (the table
  clamps it), not a section header (and it brings a separator besides).
  Keying the list's `id` to the box also worked, but rebuilt every row —
  which is what made opening Recent take a visible moment.
- The inbox list takes the window's first responder through an AppKit
  claim (`claimsInitialKeyboardFocus`, InitialKeyboardFocus): SwiftUI hands
  a NavigationSplitView's keyboard to the sidebar, and neither
  `defaultFocus` on the split view nor a `FocusState` on the content column
  moves it — the arrow keys would walk the sidebar until a row is clicked.
  It fires once per window and never out of a text field.
- The date-filter glyph is an `NSImage` painted via a symbol configuration
  (MainWindowView.filterGlyph): the toolbar draws item images itself as
  templates, so SwiftUI `foregroundStyle`/`tint`/overlays never show; only
  a non-template image keeps its color.
