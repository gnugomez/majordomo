// The UI-facing state: the latest AppState snapshot the engine pushed, plus
// view state both windows share, plus the action methods. Actions need no
// optimistic update — the engine is in-process and pushes immediately.

import AppKit
import Observation
import os
import ServiceManagement

private let log = Logger(subsystem: "dev.majordomo.app", category: "app")

/// Which new unread items post a notification.
enum NotifyScope: String, CaseIterable, Sendable {
  /// The "needs you" tier — mentions and review requests (the default).
  case mentions
  /// Every item that enters the inbox unread.
  case all
  /// No notifications at all.
  case none
}

/// True when running from a real .app bundle. SMAppService and
/// UNUserNotificationCenter require one; a bare `swift run` executable
/// must skip them instead of crashing.
let isBundled = Bundle.main.bundleIdentifier != nil

@MainActor
@Observable
final class AppModel {
  // Engine-pushed state.
  private(set) var items: [InboxItem] = []
  private(set) var accounts: [AccountState] = []
  private(set) var lastSyncAt: Date?
  private(set) var syncing = false

  // Local facts.
  private(set) var launchAtLogin = false
  /// True while an add-account validation runs; its failure lands in
  /// `connectError` for the sheet.
  private(set) var connecting = false
  private(set) var connectError: String?
  /// Ticked every 30s so relative timestamps stay fresh.
  private(set) var now = Date()

  // Shared view state.
  /// Which inbox is showing; remembered across launches like Mail's
  /// selected mailbox.
  var sidebarSelection = AppModel.loadSidebarSelection() {
    didSet {
      UserDefaults.standard.set(sidebarSelection.category, forKey: "sidebarCategory")
      UserDefaults.standard.set(sidebarSelection.account, forKey: "sidebarAccount")
    }
  }
  /// Inboxes the user hid from the sidebar (settings → Inboxes). Persisted;
  /// "recent" is the catch-all and can never be hidden.
  private(set) var hiddenCategories: Set<String> = AppModel.loadHiddenCategories()
  /// Which new items notify, and with what sound (settings → Notifications).
  private(set) var notifyScope: NotifyScope = NotifyScope(
    rawValue: UserDefaults.standard.string(forKey: "notifyScope") ?? ""
  ) ?? .mentions
  /// "default", "none", or a system alert sound name ("Ping").
  private(set) var notificationSound: String =
    UserDefaults.standard.string(forKey: "notificationSound") ?? "default"
  /// Selection is by id, so it survives sync updates.
  var selectedItemIds: Set<String> = []

  @ObservationIgnored var engine: SyncEngine?
  /// Chrome updates after every state push: tray dot, dock badge.
  @ObservationIgnored var onStateApplied: (@MainActor (AppModel) -> Void)?
  @ObservationIgnored var openMainWindow: (@MainActor () -> Void)?
  @ObservationIgnored var openSettings: (@MainActor () -> Void)?

  var anyUnread: Bool { items.contains { !$0.read } }
  var unreadCount: Int { items.count { !$0.read } }
  var unreadMentionDot: Bool { items.contains { $0.isMention && !$0.read } }
  var hasAccounts: Bool { !accounts.isEmpty }

  func apply(_ state: AppState) {
    items = state.items
    accounts = state.accounts
    lastSyncAt = state.lastSyncAt
    syncing = state.syncing
    // A sidebar scope pointing at a removed account would deselect every
    // row and persist the dangling id — snap back to All Inboxes.
    if let account = sidebarSelection.account, !accounts.contains(where: { $0.id == account }) {
      sidebarSelection = SidebarSelection(account: nil, category: sidebarSelection.category)
    }
    onStateApplied?(self)
  }

  func startTicker() {
    Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        now = Date()
      }
    }
  }

  // MARK: Actions

  func refresh() {
    // Show the spinner immediately; the pushed state is authoritative.
    syncing = true
    Task {
      await engine?.syncNow()
    }
  }

  func markAllRead() {
    Task {
      await engine?.markAllRead()
    }
  }

  private static func loadSidebarSelection() -> SidebarSelection {
    let defaults = UserDefaults.standard
    return SidebarSelection(
      account: defaults.string(forKey: "sidebarAccount"),
      category: defaults.string(forKey: "sidebarCategory") ?? recentCategory.id
    )
  }

  private static let hiddenCategoriesKey = "hiddenCategories"

  private static func loadHiddenCategories() -> Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: hiddenCategoriesKey) ?? [])
  }

  func setNotifyScope(_ scope: NotifyScope) {
    notifyScope = scope
    UserDefaults.standard.set(scope.rawValue, forKey: "notifyScope")
  }

  func setNotificationSound(_ sound: String) {
    notificationSound = sound
    UserDefaults.standard.set(sound, forKey: "notificationSound")
  }

  func setCategoryHidden(_ id: String, _ hidden: Bool) {
    guard id != recentCategory.id else {
      return
    }
    if hidden {
      hiddenCategories.insert(id)
    } else {
      hiddenCategories.remove(id)
    }
    UserDefaults.standard.set(hiddenCategories.sorted(), forKey: Self.hiddenCategoriesKey)
  }

  func markRead(_ ids: Set<String>) {
    guard !ids.isEmpty else {
      return
    }
    Task {
      await engine?.markRead(ids: Array(ids))
    }
  }

  /// Opens in the browser and marks read.
  func openItem(_ id: String) {
    Task {
      await engine?.openItem(id: id)
    }
  }

  func connect(_ provider: ProviderId, config: AccountConfig) {
    guard !connecting else {
      return
    }
    connecting = true
    connectError = nil
    Task {
      connectError = await engine?.connectAccount(provider, config: config)
      connecting = false
    }
  }

  func disconnect(_ id: AccountId) {
    Task {
      await engine?.disconnectAccount(id)
    }
  }

  // MARK: Launch at login

  func refreshLaunchAtLogin() {
    guard isBundled else {
      return
    }
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    guard isBundled else {
      log.warning("launch at login needs an app bundle; ignoring")
      return
    }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      log.error("launch-at-login change failed: \(error)")
    }
    refreshLaunchAtLogin()
  }
}
