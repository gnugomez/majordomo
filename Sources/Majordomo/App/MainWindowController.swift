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
  init(model: AppModel) {
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

  // Back to a pure menu-bar presence.
  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}
