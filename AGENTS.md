# Agent notes

Majordomo: native macOS (Swift + SwiftUI) menu-bar app; one inbox for
GitHub/GitLab. Details live in CONTRIBUTING.md (layout, adding a provider)
and RELEASING.md.

## Conventions

- **Layout**: `Model` (types; imports nothing UI) → `Providers`
  (ProviderClient + ProviderSpec per provider) → `Store`/`Sync` →
  `App` (AppKit shell) and `UI` (SwiftUI). Don't cross those lines.
- **Provider decoupling**: the core is token-generic — item kind/state/reason
  are opaque strings. ALL presentation (glyphs, colors, labels, sidebar
  buckets) comes from the provider's `ProviderSpec`, registered in
  `providerSpecs`. Never interpret provider tokens in core/UI code.
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
- **Checks**: `swift build` must pass with zero warnings.
  `./scripts/bundle.sh` → dist/Majordomo.app (release, ad-hoc signed unless
  `CODESIGN_IDENTITY` is set); `./scripts/install.sh` installs it. For
  visual checks launch with `MAJORDOMO_OPEN_MAIN=1` (opens the main window
  immediately) and screenshot via `screencapture -l<CGWindowID>`.
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

## Load-bearing workarounds — do not "clean up"

Each of these fixes a real SwiftUI/AppKit-bridge failure; removing them
reintroduces the bug:

- The detail column's toolbar holds an invisible `Color.clear` item with
  `.sharedBackgroundVisibility(.hidden)` (MainWindowView): without a
  detail-section item the list column's toolbar items drift to the window's
  far corner; a `ToolbarSpacer` instead draws a stray separator stub.
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
