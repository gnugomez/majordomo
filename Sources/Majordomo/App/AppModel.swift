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
  /// The user's labels (folder order) and rules (evaluation order). Edits
  /// apply here at once — the settings editors bind text fields to them,
  /// and a round trip through the engine would lag the keystrokes — then
  /// push to the engine, whose next state echoes the same values.
  private(set) var labels: [InboxLabel] = []
  private(set) var rules: [LabelRule] = []
  /// The sidebar's tree of inboxes and folders; edited through
  /// `updateSidebar`, which applies here at once and pushes to the engine.
  private(set) var sidebarLayout = SidebarLayout()
  /// Labels and rules the on-device model suggests, waiting on the user —
  /// empty while `suggestionsEnabled` is off.
  private(set) var suggestions: [Suggestion] = []
  /// Whether the model watches for patterns worth a label at all; only
  /// consulted while `intelligenceEnabled` is on.
  private(set) var suggestionsEnabled: Bool = AppModel.loadSuggestionsEnabled()
  /// The master switch over every on-device feature — the rule composer
  /// and the suggestions both. Off means nothing is generated at all.
  private(set) var intelligenceEnabled: Bool = AppModel.loadIntelligenceEnabled()
  /// Whether the on-device model can run here; read once the engine has
  /// installed its provider.
  private(set) var intelligence: IntelligenceAvailability = .unavailable("Checking…")
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
  /// Which inbox is showing; remembered across launches.
  var sidebarSelection = AppModel.loadSidebarSelection() {
    didSet {
      UserDefaults.standard.set(sidebarSelection.category, forKey: "sidebarCategory")
      UserDefaults.standard.set(sidebarSelection.account, forKey: "sidebarAccount")
    }
  }
  /// The toolbar's date filter, remembered across launches; nil is any time.
  private(set) var activityWindow: ActivityWindow? = AppModel.loadActivityWindow()
  /// Which new items notify, and with what sound (settings → Notifications).
  private(set) var notifyScope: NotifyScope = NotifyScope(
    rawValue: UserDefaults.standard.string(forKey: "notifyScope") ?? ""
  ) ?? .mentions
  /// "default", "none", or a system alert sound name ("Ping").
  private(set) var notificationSound: String =
    UserDefaults.standard.string(forKey: "notificationSound") ?? "default"
  /// Selection is by thread id, so it survives sync updates.
  var selectedThreadIds: Set<String> = []
  /// A message picked inside the previewed thread: the toolbar actions
  /// narrow to it while set. Ignored whenever it doesn't belong to the
  /// previewed thread.
  var selectedMemberId: String?
  /// Live filter over the inbox list; empty shows everything.
  var searchText = ""
  /// True while the toolbar search field is active; set it to move focus
  /// there (⌘F does).
  var searchPresented = false

  @ObservationIgnored var engine: SyncEngine?
  /// Chrome updates after every state push: tray dot, dock badge.
  @ObservationIgnored var onStateApplied: (@MainActor (AppModel) -> Void)?
  @ObservationIgnored var openMainWindow: (@MainActor () -> Void)?
  @ObservationIgnored var openSettings: (@MainActor () -> Void)?

  var anyUnread: Bool { items.contains { !$0.read } }
  /// Unread THREADS — the number of rows needing attention, matching the
  /// sidebar badges and the dock badge to what the list actually shows.
  var unreadCount: Int { groupIntoThreads(items).count { !$0.read } }
  var unreadMentionDot: Bool { items.contains { $0.isMention && !$0.read } }
  var hasAccounts: Bool { !accounts.isEmpty }

  func apply(_ state: AppState) {
    items = state.items
    accounts = state.accounts
    labels = state.labels
    rules = state.rules
    sidebarLayout = state.sidebar
    suggestions = suggestionsActive ? state.suggestions : []
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

  /// Manual refresh digs through every page — the user asked, so look
  /// everywhere.
  func refresh() {
    // Show the spinner immediately; the pushed state is authoritative.
    syncing = true
    Task {
      await engine?.syncNow(depth: .full)
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

  private static func loadActivityWindow() -> ActivityWindow? {
    UserDefaults.standard.string(forKey: "activityWindow").flatMap(ActivityWindow.init(rawValue:))
  }

  func setActivityWindow(_ window: ActivityWindow?) {
    activityWindow = window
    UserDefaults.standard.set(window?.rawValue, forKey: "activityWindow")
  }

  func setNotifyScope(_ scope: NotifyScope) {
    notifyScope = scope
    UserDefaults.standard.set(scope.rawValue, forKey: "notifyScope")
  }

  func setNotificationSound(_ sound: String) {
    notificationSound = sound
    UserDefaults.standard.set(sound, forKey: "notificationSound")
  }

  // MARK: Labels

  /// Every label the sidebar can show: the providers' built-ins as "All
  /// Inboxes" merges them, then the user's.
  /// Everything that exists: the providers' built-ins plus the user's,
  /// assembled the one way (see LabelCatalog). The views read their label
  /// lists from here rather than composing unions of their own.
  var catalog: LabelCatalog {
    .current(user: labels, userRules: rules)
  }

  var allLabels: [InboxLabel] {
    catalog.labels
  }

  /// The user's tags: pills on rows, applied by hand, the Labels page.
  var userLabels: [InboxLabel] {
    catalog.userLabels
  }

  /// The user's own inboxes: rule-fed buckets seen only in the sidebar,
  /// made and edited on the Inboxes page.
  var userInboxes: [InboxLabel] {
    catalog.userInboxes
  }

  /// Built-in or the user's own.
  func label(_ id: LabelId) -> InboxLabel? {
    catalog.label(id)
  }

  func setLabels(_ labels: [InboxLabel]) {
    self.labels = labels
    Task {
      await engine?.setLabels(labels)
    }
  }

  func setRules(_ rules: [LabelRule]) {
    self.rules = rules
    Task {
      await engine?.setRules(rules)
    }
  }

  // MARK: Intelligence

  /// True when the model can run here AND the user has left it on: what
  /// every on-device feature checks before offering itself.
  var intelligenceActive: Bool {
    intelligenceEnabled && intelligence.isAvailable
  }

  /// True when pattern-watching should run and its results should show.
  var suggestionsActive: Bool {
    intelligenceActive && suggestionsEnabled
  }

  private static func loadIntelligenceEnabled() -> Bool {
    UserDefaults.standard.object(forKey: "intelligenceEnabled") as? Bool ?? true
  }

  /// Turns every on-device feature off or on at once.
  func setIntelligenceEnabled(_ enabled: Bool) {
    intelligenceEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: "intelligenceEnabled")
    if !enabled {
      suggestions = []
    }
    Task {
      await engine?.setIntelligenceEnabled(enabled)
    }
  }

  private static func loadSuggestionsEnabled() -> Bool {
    UserDefaults.standard.object(forKey: "suggestionsEnabled") as? Bool ?? true
  }

  func setSuggestionsEnabled(_ enabled: Bool) {
    suggestionsEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: "suggestionsEnabled")
    if !enabled {
      suggestions = []
    }
    Task {
      await engine?.setSuggestionsEnabled(enabled)
    }
  }

  /// Reads the provider's availability once the engine has one.
  func refreshIntelligence() {
    Task {
      if let availability = await engine?.intelligenceAvailability() {
        intelligence = availability
      }
    }
  }

  /// A sentence into a rule to confirm; nothing is saved until
  /// `applyRule`. The message on failure is fit to show verbatim.
  func composeRule(_ text: String) async -> Result<ValidatedRule, IntelligenceError> {
    guard let engine else {
      return .failure(IntelligenceError(message: "The sync engine isn't running."))
    }
    return await engine.composeRule(from: text)
  }

  /// Saves a composed rule (and the label or inbox it needs).
  func applyRule(_ validated: ValidatedRule) {
    Task {
      await engine?.applyRule(validated)
    }
  }

  func acceptSuggestion(_ id: String) {
    Task {
      await engine?.acceptSuggestion(id)
    }
  }

  func dismissSuggestion(_ id: String) {
    Task {
      await engine?.dismissSuggestion(id)
    }
  }

  /// Edits the sidebar layout in place (move, hide, add or dissolve a
  /// folder, rename) and pushes the result to the engine.
  func updateSidebar(_ change: (inout SidebarLayout) -> Void) {
    var layout = sidebarLayout
    change(&layout)
    guard layout != sidebarLayout else {
      return
    }
    sidebarLayout = layout
    Task {
      await engine?.setSidebarLayout(layout)
    }
  }

  /// Forces a label on (`true`) or off (`false`) for one item, or hands it
  /// back to the rules (nil).
  func setItemLabel(_ itemId: String, _ labelId: LabelId, on: Bool?) {
    Task {
      await engine?.setLabelOverride(itemId: itemId, labelId: labelId, on: on)
    }
  }

  func markRead(_ ids: Set<String>) {
    guard !ids.isEmpty else {
      return
    }
    Task {
      await engine?.markRead(ids: Array(ids))
    }
  }

  /// Opens the thread's lead item in the browser and marks every member read.
  func openThread(_ ids: [String]) {
    Task {
      await engine?.openThread(ids: ids)
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

  /// Replaces a connected account's token; the sheet reads the outcome
  /// through the same `connecting`/`connectError` pair as connect.
  func updateToken(_ id: AccountId, token: String) {
    guard !connecting else {
      return
    }
    connecting = true
    connectError = nil
    Task {
      connectError = await engine?.updateToken(id, token: token)
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
