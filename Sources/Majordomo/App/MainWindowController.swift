// The resizable "main app" window: a singleton browser-style inbox opened
// from the tray menu. An AppKit-managed window (not a SwiftUI Window scene)
// because scene windows can't be opened from an NSStatusItem — SwiftUI's
// openWindow action only exists inside an installed view's environment. The
// content is SwiftUI throughout; sceneBridgingOptions hands SwiftUI the
// toolbar.

import AppKit
import SwiftUI

private let defaultSize = NSSize(width: 980, height: 640)
private let minSize = NSSize(width: 800, height: 420)

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
  private let model: AppModel

  init(model: AppModel) {
    self.model = model
    let host = NSHostingController(rootView: MainWindowView(model: model))
    // SwiftUI installs the window's NSToolbar and title from the view's
    // .toolbar / .navigationTitle modifiers.
    host.sceneBridgingOptions = [.toolbars, .title]
    // …and enforces only the content's MINIMUM size. Never include
    // .preferredContentSize here: the hosting controller then snaps the
    // frame back to the preferred size after the autosaved frame restores —
    // and autosaves that, clobbering the user's size on every launch. And
    // with no option at all, the window can be squeezed to a sliver (the
    // hosting view discards the manually set contentMinSize on attach).
    host.sizingOptions = [.minSize]
    let window = NSWindow(contentViewController: host)
    // fullSizeContentView + unified toolbar let the split view's sidebar run
    // the window's full height, with the toolbar split at the sidebar edge —
    // without them AppKit stacks a full-width title bar above the content.
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.toolbarStyle = .unified
    window.title = "Majordomo"
    window.contentMinSize = minSize
    window.setContentSize(defaultSize)
    // Remember the frame the way a native window does — and only center a
    // window that has never been placed (centering after the restore would
    // wipe the remembered position on every launch).
    if !window.setFrameUsingName("MainWindow") {
      window.center()
    }
    window.setFrameAutosaveName("MainWindow")
    window.isReleasedWhenClosed = false
    super.init(window: window)
    // Cascading (the default) re-places the window on every showWindow,
    // silently discarding the restored position while keeping the size —
    // and placement is governed by the controller's own autosave name, not
    // the window-level one.
    shouldCascadeWindows = false
    windowFrameAutosaveName = "MainWindow"
    window.delegate = self
    // The toolbar is SwiftUI's; keep its trailing pair in order whenever
    // SwiftUI re-diffs the items (selection changes swap the detail items).
    for name in [NSToolbar.didRemoveItemNotification, NSToolbar.willAddItemNotification] {
      // The toolbar doesn't exist yet (SwiftUI installs it on show), so
      // the sender is checked per notification rather than at registration.
      NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] notification in
        let sender = notification.object.map { ObjectIdentifier($0 as AnyObject) }
        MainActor.assumeIsolated {
          guard let self, let toolbar = self.window?.toolbar, sender == ObjectIdentifier(toolbar) else {
            return
          }
          self.scheduleFilterPairing()
        }
      }
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("not used")
  }

  /// Opens the window, or focuses the live one. The main window is a real
  /// citizen: the app gets a Dock icon (and an app-switcher entry) for as
  /// long as it is open.
  func open() {
    // Leaving .accessory takes effect asynchronously in the window server;
    // ordering the window front in the same runloop pass loses the first
    // click, so the actual ordering waits one turn after the switch.
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
      DispatchQueue.main.async { [weak self] in
        self?.orderFront()
      }
    } else {
      orderFront()
    }
  }

  private func orderFront() {
    if window?.isMiniaturized == true {
      window?.deminiaturize(nil)
    }
    showWindow(nil)
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
    // Cooperative activation may deny a fresh accessory→regular app the
    // focus steal — the window must still not open buried under others.
    window?.orderFrontRegardless()
    // The views exist once shown; hand the split view to AppKit's autosave.
    DispatchQueue.main.async { [weak self] in
      self?.adoptColumnAutosave()
      self?.pairFilterWithSearch()
    }
  }

  /// NavigationSplitView doesn't expose column-width persistence, but the
  /// NSSplitView it bridges to autosaves divider positions once named.
  private func adoptColumnAutosave() {
    guard let root = window?.contentView else {
      return
    }
    for splitView in Self.splitViews(in: root) where splitView.autosaveName?.isEmpty != false {
      splitView.autosaveName = "MainWindowColumns"
    }
  }

  private var filterPairingScheduled = false

  /// Coalesces the pairing behind the current runloop turn: SwiftUI adds
  /// and removes several items per diff, and the layout is only settled
  /// once they are all in.
  private func scheduleFilterPairing() {
    guard !filterPairingScheduled else {
      return
    }
    filterPairingScheduled = true
    DispatchQueue.main.async { [weak self] in
      self?.filterPairingScheduled = false
      self?.pairFilterWithSearch()
    }
  }

  /// SwiftUI lays the toolbar's trailing end out as
  /// [detail items…][flexible space][search field], with no placement
  /// that lands an item after the spacer. The filter (the last detail
  /// item) belongs flush against the search field, the way Music
  /// pairs its filter with search — so the spacer moves ahead of it.
  /// Idempotent: once paired, the item before the search field is no
  /// longer the spacer and nothing happens.
  private func pairFilterWithSearch() {
    guard let toolbar = window?.toolbar else {
      return
    }
    let items = toolbar.items
    guard let searchIndex = items.lastIndex(where: { $0 is NSSearchToolbarItem }),
          searchIndex >= 2,
          items[searchIndex - 1].itemIdentifier == .flexibleSpace,
          items[searchIndex - 2].itemIdentifier != .flexibleSpace,
          !(items[searchIndex - 2] is NSTrackingSeparatorToolbarItem) else {
      return
    }
    toolbar.removeItem(at: searchIndex - 1)
    toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: searchIndex - 2)
  }

  private static func splitViews(in view: NSView) -> [NSSplitView] {
    var found: [NSSplitView] = []
    for subview in view.subviews {
      if let split = subview as? NSSplitView {
        found.append(split)
      }
      found.append(contentsOf: splitViews(in: subview))
    }
    return found
  }

  // Back to a pure menu-bar presence. The next open is a fresh look, so
  // the unread filter lets go of the rows it held read.
  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    model.releaseKeptReads()
  }
}
