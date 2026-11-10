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
  them (`builtinLabels`/`builtinRules`), run by the same `RuleEngine` as
  the user's labels and rules; they list read-only in settings and hide
  from the Inboxes page. `LabelCatalog.current` is the ONE place the full
  set is assembled (built-ins first, then the user's) — read it from
  `AppModel.catalog` or the engine's `catalog()` rather than composing
  unions at a call site. Never interpret provider tokens in core/UI code.
- **One sidebar for every account**: buckets sharing an id merge into one
  inbox, and every inbox holds every account's items — the selection
  (`SidebarSelection`) names an inbox or a board, never an account. One
  provider's items are the toolbar filter's Provider pick; an account in
  trouble (`AccountState.error`) shows at the sidebar's foot, opening
  Settings on Accounts, for as long as it is.
- **One filter model, one sweep**: label rules, board scopes, and board
  columns all hold a `RuleFilter` (groups of conditions, all/any at both
  levels; an Apple Intelligence check is a `.question` condition), edited
  by the one `FilterEditor`. The sync engine's `sweep()` compiles them once
  and works out the labels AND every board's placement off the main actor;
  `AppModel` only narrows a published placement by the search and the
  toolbar's filter, and only while the filter is on (`narrowing`). Model
  answers are keyed by question (`RuleEngine.questionKey`), per item and
  per target.
- **Changes, reactions, one push**: an engine mutation does its own work
  and records what it touched (`record(.rules)`) — it never calls a sweep,
  a model pass, or a publish itself. `EngineChange.reactions` is the one
  table of what follows what (relabel or only re-place, reconcile the
  sidebar, forget answers, which background passes start), and `settle`
  runs the turn's changes through it once, publishing only the slices
  they moved as one push. A new follow-up is an entry in that table; a
  new reaction to what happened subscribes to `events()` (a
  `DomainEvent`) instead of being wired into the engine. State reaches
  the main actor as an `AsyncStream` (`states()`, latest wins), and the
  store writes a moment after a change, off the actor, and on quit.
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
- **Checks**: `make build` (`swift build`) must pass with zero warnings,
  and `make test` (`swift test`, Swift Testing in `Tests/MajordomoTests`,
  `@testable import Majordomo`) must stay green — the filters, placement,
  every stored shape's decoding, the engine's reactions and events, the
  store's saves, and how the model takes in a push are covered there.
  `make bundle` → dist/Majordomo.app (release, ad-hoc signed unless
  `CODESIGN_IDENTITY` is set — it passes through make); `make install`
  installs it. `make help` lists the rest; the targets are thin wrappers
  over SwiftPM and `scripts/`. For visual checks `make demo` is the shortest
  path — fixture data, no accounts, network, or Keychain prompt, main window
  open at launch (`MAJORDOMO_DEMO=1` + `MAJORDOMO_OPEN_MAIN=1`); screenshot
  via `screencapture -l<CGWindowID>`.
- **Commits**: conventional, single-line, no bodies or attribution.
  `feat:`/`fix:` strictly for user-visible changes against the last release
  (they drive the changelog and version) — a fix or follow-up to a feature
  not yet released is `chore:`, so the changelog shows the feature once;
  `ci:`/`build:` for pipeline work — never `feat:`; `refactor:` lists in the
  changelog, `chore:`/`docs:` don't. Releases only via release-please —
  never bump version.txt or edit CHANGELOG.md by hand.
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

- `NSHostingController.sizingOptions = [.minSize]` on the main window
  (MainWindowController), never `.preferredContentSize`: that snaps the
  window back to its preferred size after the autosaved frame restores —
  and autosaves that. Without `.minSize`, a window narrower than the split
  needs takes AppKit's layout down.
- `shouldCascadeWindows = false` plus the CONTROLLER-level
  `windowFrameAutosaveName` (MainWindowController): window-level
  `setFrameAutosaveName` alone loses the position on every show.
- Empty states in detail panes are wrapped in `ScrollView` +
  `containerRelativeFrame` (PreviewView, MainWindowView): non-scrolling
  content makes the toolbar draw a hard edge line across the pane.
- `orderFrontRegardless()` after `NSApp.activate()` when opening windows:
  cooperative activation can deny the focus steal and the window would open
  buried.
- The pinned spotlight is a list row keyed by its own shape
  (`spotlightKey`, InboxListView): a List row is measured once, when it
  arrives, and keeps that height — and the box arrives, grows (a summary is
  a line) and shrinks (a read notification leaves) long after the list was
  built, so a row with a stable identity drew clipped, or left a gap where
  it had shrunk, until something forced another pass. The key spells out
  everything that decides the box's height, so any change REPLACES the row
  and the table measures the new one. The row is always in the list,
  resting at a hairline when there is nothing to spotlight — hence the
  lowered `defaultMinListRowHeight`, which would otherwise hold that row
  open as a band of blank space over the first notification. A box arriving
  is then a replacement too, and a replacement is the one case the table
  measures right: a plain insertion draws as a header strip with the rows
  cut off. Nothing else held: `fixedSize`, an explicit row height (the
  table clamps it), a section header (and it draws a separator), keying the
  list's id (correct, but rebuilds every row — opening Recent took a
  visible moment), keying the row's id, a half-point width nudge, and
  AppKit's own `noteHeightOfRows(withIndexesChanged:)`, which SwiftUI
  answers out of its own cache. The rotation and the light are held by the
  list rather than the box, because a replaced row starts its own state
  over. The lowered floor is also the table's row height, which the table
  copies into its scroll view's wheel line on every tile — one notch would
  move a point — so `wheelScrollsByRow()` (WheelLineScroll) holds the line at
  24 pt, the table's own value without the floor, through KVO on
  `verticalLineScroll`. Trackpads scroll by exact distances and never
  read it.
- The inbox list and a board take the window's first responder through
  an AppKit claim (`KeyboardClaim`, InitialKeyboardFocus): SwiftUI hands
  a NavigationSplitView's keyboard to the sidebar, and neither
  `defaultFocus` on the split view nor a `FocusState` on the content column
  moves it — the arrow keys would walk the sidebar until a row is clicked.
  The list claims for its table (`claimsInitialKeyboardFocus`), a board
  for its own key view (BoardKeyboard), an AppKit view behind the grid
  that reads the arrows, Space, Return, and Escape. The claim fires once
  per window — again only when nobody holds the keyboard, as after the
  pane holding it is swapped for the other — and never out of a text
  field, so the sidebar keeps its arrows while it has them.
- A board's key view is `accessibilityHidden`: in SwiftUI's tree it is
  the pane's size and answers VoiceOver's hit test over every card. As
  first responder it still reports itself as the board, and each card the
  arrows pick is announced. The arrows scroll without animation — a
  scroll still animating when the next key lands leaves the selection off
  the pane — to a clear frame around the card (`RevealFrame`), so it
  rests clear of the header band and the scrollers; a card in a lane the
  LazyVStack hasn't built is reached by scrolling to the lane and then to
  the card in the lane's `onAppear`, since `scrollTo` finds nothing in an
  unbuilt lane. The slots are lazy too (`cell`): without lanes the one
  row holds every card, and SwiftUI's ScrollView re-renders every card
  built on each scroll step and hit-tests every one on each wheel event,
  in view or not — a board of two hundred cards scrolled at half the
  display's rate. A card its slot hasn't built is approached through the
  clip view (`approach`, `BoardScroll.nudge`), by the cards between it and
  the slot's built ones at a typical card's height, each batch built
  bringing the next step (`BoardFocus.cardAppeared`), and is scrolled to
  in its own `onAppear`; the steps give up after a dozen or half a
  second, so they never fight a wheel.
- The filter glyph, the filter control's label, is an `NSImage` painted
  via a symbol configuration (FilterToolbarControl.glyph): the toolbar
  draws item images itself as templates, so SwiftUI
  `foregroundStyle`/`tint`/overlays never show; only a non-template image
  keeps its color.
- The filter is a toolbar item (FilterToolbarControl, MainWindowView),
  not a row under the toolbar: whenever the preview slides in, and often
  when it is open as the window opens, AppKit gives the content's stretch
  of the toolbar a backdrop of its own that ends at the toolbar's foot and
  stays after the preview closes again. Anything laid out beneath it — an
  overlay or a `safeAreaBar` alike — then floats over the content
  scrolling past, under a hard line. Nothing we can set reaches that
  backdrop: not `toolbarBackgroundVisibility` on the column or the split,
  the scroll edge style, the clear layer's place, or an unanimated
  toggle. The control is a `Menu` with a primary action that keeps its
  menu indicator, which the toolbar draws as one capsule split into the
  glyph and a chevron. It is Equatable over whether the filter narrows
  and its summary — never over what its menu offers, which the menu asks
  for as it is built (`offeredValues`) — so no push redraws it (see the
  fade entry), and its tooltip holds still. In a narrow window the system
  moves it, with the preview toggle, into the toolbar's overflow menu,
  which lists the menu but not the glyph's click; the menu's Unread Only
  and Clear Filters do what the click does, there and for VoiceOver,
  which names no chevron. The control is keyed by its summary
  (`.id(summary)`): the toolbar builds an item's menu once and keeps it,
  so without the key a reopened menu shows the ticks and submenu titles
  it was built with, whatever has been picked since — keying its content
  instead changes nothing. A pick rebuilds the item, once per pick.
- A board's column headers ride a `safeAreaBar` on its one two-axis
  ScrollView (BoardView), drawn as an overlay on a clear band rather than
  laid out directly: a row as wide as the grid would widen the bar, and
  with it the pane. A header row outside the scroll view instead clips the
  cards at its foot, and a vertical ScrollView nested in a horizontal one
  hides its scroller past the grid's far end. The board's top edge effect
  is `.hard`: once the toolbar has its own backdrop (see the filter), a
  soft edge leaves the cards legible under the band, the labels
  floating over them, where a hard one covers the band either way. The
  room above the grid's first row is padding inside the scroll view, not
  room in the bar, so it scrolls away under the band with the cards.
- The board's menu is in the toolbar over a board only (MainWindowView),
  and over the inbox it is dropped rather than hidden: a hidden toolbar
  item still draws its empty glass capsule. It comes before the filter,
  so the filter and the preview toggle keep their places from one to the
  other. Opening and marking read are the preview's (SelectionActions),
  not toolbar items. Switching
  between the two runs with animations disabled — SwiftUI rebuilds the
  toolbar's items either way, and animated they fade and morph. The
  board's menu is a view that reads its own state
  (BoardToolbarControls), with a fixed label and tooltip: content that
  changes with a click or a selection makes SwiftUI rebuild the items,
  and the cluster blinks.
- Toolbar items redraw with a fade whenever the view that builds them
  updates, so each toolbar control is a small view given only what
  decides how it looks (`RefreshButton` watches `syncing`, the board's
  menu the board, `PreviewToggle` whether a card is selected and where
  the board's preview stands,
  `FilterToolbarControl` whether the filter narrows and by what), and
  `AppModel.apply` assigns only the slices whose revision moved
  (`StateRevisions`) — selecting a card pushes several times (the
  selection, marking it seen), and every reader woken by each push
  flickers every item in the bar. Assigning an Equatable property an
  equal value wakes no one (Observation compares first, at the price of
  a comparison), but an in-place mutation (`boards[i].pins[…] = …`) or a
  non-Equatable value wakes every reader, equal or not; the revision
  check spares both the wake-ups and the comparisons.
- The preview is an inspector in the detail column (MainWindowView). On
  the NavigationSplitView itself, as Apple's Landmarks sample has it,
  SwiftUI counts it twice in the window's minimum width (as a column, and
  again as the room it covers over the content), and AppKit's layout
  fails whenever it opens in a window narrower than that. In the detail
  column the column's views sit under a clear layer that never changes
  (`ZStack { … Color.clear }`, out of hit testing): with nothing in the
  column holding still, every swap of one view for another — the list for
  a board, the list's empty state for its rows — shrinks the inspector to
  its narrowest, and the sidebar arriving in a narrow window takes the
  layout down. The layer goes on top: beneath the views, it is what the
  toolbar finds at the top of the pane, and with the inspector open the
  toolbar draws a hard line under itself rather than fading the content
  out beneath it. On top it holds only until the toolbar takes a backdrop
  of its own as the inspector slides in (see the filter). The
  sidebar's and the inspector's slide, the content scrolling on beneath
  both, and the toolbar's sections are all the system's.
- A board's preview can stand under the board instead
  (`boardPreviewPlacement`, picked from the preview toggle's menu), in a
  pane of our own (BottomPreviewSplit), since an inspector only stands at
  the trailing edge. The pane is an overlay over the board's foot, not a
  stack beside it: the window's minimum size follows the content's
  (`.minSize`), and a pane laid out under the board as a
  `.frame(height:)` moved that minimum on every step of a drag — dragging
  it took the app down, AppKit throwing on its update-constraints passes
  as the hosting view invalidated its size constraints mid-layout. An
  overlay never reaches the board's size; the board runs on beneath it,
  as under the sidebar, its scroll content and scrollers ending at the
  pane's edge through `contentMargins`, carried by an animatable modifier
  (`PaneMargin`): a margin set in one step lands at once, and the
  scrollers would jump to where the pane will be while it is still
  sliding up. The pane stands on the sidebar's
  own glass (`SidebarGlass`): an `NSGlassEffectView` in the private
  variant the split view gives its sidebar, set only where the glass view
  answers to it. The inspector binding's setter only writes the card
  preview's state while the preview stands beside the board: moving it
  under the board closes the inspector, which writes `false` back and
  would hide the pane it moved to. The toggle's menu is keyed by the
  placement (`.id`), as the filter's is by its summary, so a reopened
  menu ticks the current one.
- The sidebar toggle is our own (`SidebarToggle`, MainWindowView), behind
  a flexible spacer in the sidebar's stretch of the toolbar, and SwiftUI's
  is removed (`.toolbar(removing: .sidebarToggle)`): SwiftUI's comes and
  goes with how the window was set up. The toggle and View ▸ Toggle
  Sidebar (⌃⌘S, AppDelegate) both go through `AppModel.sidebarShown`, so
  the menu and SwiftUI's split never disagree.
- The column widths persist through the defaults (`remembersWidth`,
  MainWindowView): NavigationSplitView keeps no widths across launches,
  so each column notes its width straight into the defaults — not into
  state, which would redraw the toolbar on every step of a drag — and
  opens at it, as its ideal, the next time. The width modifiers sit
  outside that `onGeometryChange`: wrapped in it, the split no longer
  finds them and falls back to its own widths.
- The inbox list draws `rowPage` threads and offers the rest behind a row
  (InboxListView): a List measures every row it is handed, and a long
  history took seconds to show on opening and on every inbox switch.
