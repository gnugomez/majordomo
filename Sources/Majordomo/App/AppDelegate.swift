// App shell: the status item and its tray menu, the main menu (⌘, and the
// edit shortcuts), and the wiring between the sync engine and the chrome
// (tray dot, dock badge). The inbox opens as a real NSMenu, not a
// hand-positioned popover: instant, and it dismisses like every other menu.

import AppKit
import SwiftUI
import UserNotifications

/// Rows shown in the tray menu before "Open Majordomo" takes over.
private let menuMentionCap = 8
private let menuRecentCap = 12

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  let model = AppModel()
  private var engine: SyncEngine!
  private var notifier: Notifier!
  private var statusItem: NSStatusItem!
  private var mainWindow: MainWindowController?
  private var settingsWindow: SettingsWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let model = model
    engine = SyncEngine(
      emit: { state in
        Task { @MainActor in
          model.apply(state)
        }
      },
      notify: { item in
        Task { @MainActor in
          guard let delegate = AppDelegateBox.shared else {
            return
          }
          // The engine reports every new unread item. Its labels speak
          // first: an urgent or always label pings whatever the scope, a
          // never label silences it; unlabeled items (and follow-policy
          // labels) leave it to the notification scope setting.
          let model = delegate.model
          let policy = LabelNotifyPolicy.effective(item.labels.compactMap { model.label($0)?.notify })
          let wanted: Bool
          var level: UNNotificationInterruptionLevel = .active
          switch policy {
          case .never:
            wanted = false
          case .always:
            wanted = true
          case .urgent:
            wanted = true
            level = .timeSensitive
          case .follow:
            wanted = switch model.notifyScope {
            case .mentions: item.isMention
            case .all: true
            case .none: false
            }
          }
          if wanted {
            delegate.notifier.post(item, sound: model.notificationSound, interruptionLevel: level)
          }
        }
      }
    )
    AppDelegateBox.shared = self
    notifier = Notifier(openItem: { [engine] id in
      await engine?.openItem(id: id)
    })
    model.engine = engine
    model.onStateApplied = { [weak self] model in
      self?.applyChrome(model)
    }
    model.openMainWindow = { [weak self] in
      self?.openMainWindow()
    }
    model.openSettings = { [weak self] in
      self?.openSettings()
    }
    model.startTicker()
    model.refreshLaunchAtLogin()

    setupMainMenu()
    setupStatusItem()

    // Dev harness: open the main window straight away so a visual check
    // (or a screenshot script) doesn't need a trip through the tray menu.
    if ProcessInfo.processInfo.environment["MAJORDOMO_OPEN_MAIN"] != nil {
      openMainWindow()
    }
    // Likewise MAJORDOMO_OPEN_SETTINGS=<tab label> opens settings on that
    // tab, for a screenshot of one page.
    if let tab = ProcessInfo.processInfo.environment["MAJORDOMO_OPEN_SETTINGS"] {
      openSettings()
      settingsWindow?.select(tab: tab)
    }

    let engine = engine!
    Task {
      // The on-device model touches no network, so a demo run uses it
      // too — the composer is the point of the Rules page and has to be
      // usable there. Demo fixtures still ship their own suggestions.
      await engine.setIntelligence(AppleIntelligence())
      let switches = await MainActor.run {
        model.refreshIntelligence()
        return model.intelligenceSwitches
      }
      await engine.setIntelligenceSwitches(
        intelligence: switches.intelligence,
        suggestions: switches.suggestions,
        summaries: switches.summaries
      )
      await engine.start()
    }
  }

  // macOS keeps the process alive with no windows; Dock-icon clicks (only
  // possible while the main window exists) refocus it.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    openMainWindow()
    return false
  }

  // MARK: Chrome

  /// Tray dot iff there are unread mentions; Dock badge counts all unread
  /// (visible only while the main window keeps the Dock icon alive).
  private func applyChrome(_ model: AppModel) {
    statusItem?.button?.image = model.unreadMentionDot ? TrayIcon.dot : TrayIcon.normal
    NSApp.dockTile.badgeLabel = model.unreadCount > 0 ? String(model.unreadCount) : nil
  }

  // MARK: Main menu

  /// Invisible for an accessory app, but key equivalents still route through
  /// it: ⌘, opens settings anywhere, ⌘F focuses the inbox search, and the
  /// Edit items give the settings window's token fields their paste/copy
  /// shortcuts.
  private func setupMainMenu() {
    let mainMenu = NSMenu()

    let appItem = NSMenuItem()
    mainMenu.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(
      withTitle: "About Majordomo",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    appMenu.addItem(.separator())
    let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
    settings.target = self
    appMenu.addItem(settings)
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Hide Majordomo",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    let hideOthers = NSMenuItem(
      title: "Hide Others",
      action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h"
    )
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(hideOthers)
    appMenu.addItem(
      withTitle: "Show All",
      action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: ""
    )
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Quit Majordomo",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )

    // File menu: ⌘W closes whichever window is key.
    let fileItem = NSMenuItem()
    mainMenu.addItem(fileItem)
    let fileMenu = NSMenu(title: "File")
    fileItem.submenu = fileMenu
    fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    let editItem = NSMenuItem()
    mainMenu.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editItem.submenu = editMenu
    editMenu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenu.addItem(.separator())
    let find = NSMenuItem(title: "Find", action: #selector(focusSearch), keyEquivalent: "f")
    find.target = self
    editMenu.addItem(find)

    // The Window menu: the standard trio, plus the open-windows list and
    // "Bring All to Front" that AppKit maintains once it owns the menu.
    // A menu-bar app only shows a menu bar while a window is open (the
    // activation policy turns regular then), and that is exactly when
    // these are wanted.
    let windowItem = NSMenuItem()
    mainMenu.addItem(windowItem)
    let windowMenu = NSMenu(title: "Window")
    windowItem.submenu = windowMenu
    windowMenu.addItem(
      withTitle: "Minimize",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    windowMenu.addItem(.separator())
    windowMenu.addItem(
      withTitle: "Bring All to Front",
      action: #selector(NSApplication.arrangeInFront(_:)),
      keyEquivalent: ""
    )
    NSApp.windowsMenu = windowMenu

    NSApp.mainMenu = mainMenu
  }

  // MARK: Status item + tray menu

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = TrayIcon.normal
    statusItem.button?.toolTip = "Majordomo"
    // A permanently attached menu opens on any click, instantly, and
    // dismisses like every other menu-bar menu; the delegate rebuilds its
    // contents each time it opens.
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = self
    statusItem.menu = menu
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    addAccountAlerts(to: menu)
    addInboxRows(to: menu)
    addActions(to: menu)
  }

  /// Account problems lead — one row per broken account, opening settings.
  private func addAccountAlerts(to menu: NSMenu) {
    let broken = model.accounts.filter { $0.error != nil }
    for account in broken {
      let name = account.username.map { "@\($0)" } ?? account.provider.displayName
      let item = NSMenuItem(title: "\(name) needs attention…", action: #selector(openSettingsAction), keyEquivalent: "")
      item.target = self
      item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
      menu.addItem(item)
    }
    if !broken.isEmpty {
      menu.addItem(.separator())
    }
  }

  /// The inbox rows: unread mentions first, then the recent tail, capped.
  private func addInboxRows(to menu: NSMenu) {
    let threads = groupIntoThreads(inboxOrder(model.items))
    guard !threads.isEmpty else {
      let empty = NSMenuItem(
        title: model.hasAccounts ? "You're all caught up" : "No accounts connected",
        action: nil,
        keyEquivalent: ""
      )
      empty.isEnabled = false
      menu.addItem(empty)
      return
    }
    let mentions = threads.filter { thread in
      thread.items.contains { $0.isMention && !$0.read }
    }.prefix(menuMentionCap)
    let mentionIds = Set(mentions.map(\.id))
    let recent = threads.filter { !mentionIds.contains($0.id) }.prefix(menuRecentCap)
    if !mentions.isEmpty {
      menu.addItem(.sectionHeader(title: "Mentions"))
      for thread in mentions {
        menu.addItem(trayRow(for: thread))
      }
    }
    if !recent.isEmpty {
      menu.addItem(.sectionHeader(title: "Recent"))
      for thread in recent {
        menu.addItem(trayRow(for: thread))
      }
    }
  }

  /// Mark-all / refresh, then the windows, then quit.
  private func addActions(to menu: NSMenu) {
    menu.addItem(.separator())
    let markAll = NSMenuItem(title: "Mark All as Read", action: #selector(trayMarkAllRead), keyEquivalent: "")
    markAll.target = self
    markAll.isEnabled = model.anyUnread
    menu.addItem(markAll)
    let refresh = NSMenuItem(
      title: model.syncing ? "Syncing…" : "Refresh Now",
      action: #selector(trayRefresh),
      keyEquivalent: ""
    )
    refresh.target = self
    refresh.isEnabled = !model.syncing
    menu.addItem(refresh)
    menu.addItem(.separator())
    let openMain = NSMenuItem(title: "Open Majordomo", action: #selector(trayOpenMain), keyEquivalent: "")
    openMain.target = self
    menu.addItem(openMain)
    let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Majordomo",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
  }

  /// One inbox row: provider mark, two-line attributed title (title over the
  /// repo/author/time meta), and an accent dot in the state column when the
  /// thread has anything unread. Clicking opens in the browser and marks the
  /// whole thread read, like everywhere.
  private func trayRow(for thread: InboxThread) -> NSMenuItem {
    let item = thread.lead
    let row = NSMenuItem(title: item.title, action: #selector(trayRowClicked(_:)), keyEquivalent: "")
    row.target = self
    row.representedObject = thread.itemIds

    let text = NSMutableAttributedString(
      string: truncated(item.title, max: 58),
      attributes: [
        .font: NSFont.menuFont(ofSize: 13),
        .foregroundColor: NSColor.labelColor,
      ]
    )
    text.append(NSAttributedString(
      string: "\n" + truncated(metaLine(for: item, now: model.now), max: 64),
      attributes: [
        .font: NSFont.menuFont(ofSize: 11),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
    ))
    row.attributedTitle = text
    row.image = Self.providerMenuImage(item.provider)
    if !thread.read {
      row.state = .on
      row.onStateImage = Self.unreadDot
    }
    return row
  }

  private func truncated(_ string: String, max: Int) -> String {
    string.count > max ? String(string.prefix(max - 1)) + "…" : string
  }

  /// The provider marks as template images, rendered once from the shared
  /// SwiftUI paths so the menu rows still show whose item each is.
  private static var providerImages: [ProviderId: NSImage] = [:]

  private static func providerMenuImage(_ provider: ProviderId) -> NSImage? {
    if let cached = providerImages[provider] {
      return cached
    }
    let renderer = ImageRenderer(
      content: ProviderMark(provider: provider)
        .foregroundStyle(.black)
        .frame(width: 16, height: 16)
    )
    renderer.scale = 2
    guard let image = renderer.nsImage else {
      return nil
    }
    image.isTemplate = true
    image.size = NSSize(width: 16, height: 16)
    providerImages[provider] = image
    return image
  }

  /// Accent-colored unread dot for the menu's state column; drawn on demand
  /// so it follows the system accent and appearance.
  private static let unreadDot = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
    NSColor.controlAccentColor.setFill()
    NSBezierPath(ovalIn: rect).fill()
    return true
  }

  @objc private func trayRowClicked(_ sender: NSMenuItem) {
    guard let ids = sender.representedObject as? [String] else {
      return
    }
    model.openThread(ids)
  }

  @objc private func trayMarkAllRead() {
    model.markAllRead()
  }

  @objc private func trayRefresh() {
    model.refresh()
  }

  @objc private func trayOpenMain() {
    openMainWindow()
  }

  /// ⌘F: the main window comes up with the toolbar search field focused.
  @objc private func focusSearch() {
    openMainWindow()
    model.searchPresented = true
  }

  // MARK: Windows

  private func openMainWindow() {
    if mainWindow == nil {
      mainWindow = MainWindowController(model: model)
    }
    mainWindow?.open()
  }

  @objc private func openSettingsAction() {
    openSettings()
  }

  private func openSettings() {
    if settingsWindow == nil {
      settingsWindow = SettingsWindowController(model: model)
    }
    settingsWindow?.open()
  }
}

/// Weak global hook so the engine's @Sendable notify closure can reach the
/// delegate without capturing main-actor state at init time.
@MainActor
enum AppDelegateBox {
  weak static var shared: AppDelegate?
}
