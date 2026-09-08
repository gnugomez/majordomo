// The settings window, Mail-style: toolbar tabs (NSTabViewController's
// .toolbar style — the canonical preferences window, which also animates the
// resize between tabs), one tab per category. Opened from ⌘, (main menu),
// the tray menu, and the sidebar's account row; a singleton that refocuses.
// Every page is fixed-size (adding an account happens in a sheet), so tab
// switches are the only resizes.

import AppKit
import SwiftUI

/// Keeps the window title in step with the selected tab, the way every
/// toolbar-tabbed settings window titles itself.
private final class SettingsTabsController: NSTabViewController {
  override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    if let label = tabViewItem?.label {
      view.window?.title = label
    }
  }

  // The initial selection lands before the window exists (didSelect finds
  // view.window == nil and the window would open "Untitled") — re-assert
  // once attached.
  override func viewDidAppear() {
    super.viewDidAppear()
    if selectedTabViewItemIndex >= 0 {
      view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }
  }
}

@MainActor
final class SettingsWindowController: NSWindowController {
  init(model: AppModel) {
    let tabs = SettingsTabsController()
    tabs.tabStyle = .toolbar

    func page(_ content: some View) -> NSHostingController<some View> {
      let host = NSHostingController(rootView: content.frame(width: 440))
      host.sizingOptions = .preferredContentSize
      return host
    }

    let general = NSTabViewItem(viewController: page(GeneralSettingsView(model: model)))
    general.label = "General"
    general.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")
    tabs.addTabViewItem(general)

    let accounts = NSTabViewItem(viewController: page(AccountsSettingsView(model: model)))
    accounts.label = "Accounts"
    accounts.image = NSImage(systemSymbolName: "at", accessibilityDescription: "Accounts")
    tabs.addTabViewItem(accounts)

    let inboxes = NSTabViewItem(viewController: page(InboxesSettingsView(model: model)))
    inboxes.label = "Inboxes"
    inboxes.image = NSImage(systemSymbolName: "tray.2", accessibilityDescription: "Inboxes")
    tabs.addTabViewItem(inboxes)

    let notifications = NSTabViewItem(viewController: page(NotificationsSettingsView(model: model)))
    notifications.label = "Notifications"
    notifications.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Notifications")
    tabs.addTabViewItem(notifications)

    // Accounts is where everything happens in this app — start there.
    tabs.selectedTabViewItemIndex = 1

    let window = NSWindow(contentViewController: tabs)
    window.styleMask = [.titled, .closable]
    window.title = "Accounts"
    window.isReleasedWhenClosed = false
    if !window.setFrameUsingName("SettingsWindow") {
      window.center()
    }
    window.setFrameAutosaveName("SettingsWindow")
    super.init(window: window)
    // Same as the main window: cascading would discard the restored
    // position, and placement is governed by the CONTROLLER's autosave name
    // — the window-level one alone saves but never restores the position.
    shouldCascadeWindows = false
    windowFrameAutosaveName = "SettingsWindow"
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("not used")
  }

  func open() {
    NSApp.activate()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    // Same guard as the main window: never open buried when cooperative
    // activation denies the focus steal.
    window?.orderFrontRegardless()
  }
}
