// The UI-facing state: the latest AppState snapshot the engine pushed, plus
// view state both windows share, plus the action methods. Actions mostly
// need no optimistic update — the engine is in-process and pushes
// immediately; the edits a keystroke or a drag must answer at once apply
// here first, and the push echoes them.

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

/// Conversations the preview keeps read at most; looking back at a recent
/// one is instant, and nothing builds up over a long session.
private let conversationCacheLimit = 40

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
  /// The user's boards, in sidebar order; edited through `setBoards`,
  /// which applies here at once and pushes to the engine.
  private(set) var boards: [Board] = []
  /// What the boards' cards know about their targets, by key.
  private(set) var targets: [String: TrackedTarget] = [:]
  /// Where each board's cards go, by board id, as the engine's sweep
  /// placed them; the views narrow it by the search and the pills
  /// (`placement(of:)`).
  private(set) var placements: [BoardId: BoardPlacement] = [:] {
    didSet {
      narrowedPlacements = [:]
    }
  }
  /// Labels and rules the on-device model suggests, waiting on the user —
  /// empty while `suggestionsEnabled` is off.
  private(set) var suggestions: [Suggestion] = []
  /// Whether the model watches for patterns worth a label at all; only
  /// consulted while `intelligenceEnabled` is on.
  private(set) var suggestionsEnabled: Bool = AppModel.loadSuggestionsEnabled()
  /// Whether the model writes the one-line summaries the rows show in
  /// place of raw excerpt text; only consulted while `intelligenceEnabled`
  /// is on.
  private(set) var summariesEnabled: Bool = AppModel.loadSummariesEnabled()
  /// The master switch over every on-device feature — the rule composer,
  /// the suggestions, and the summaries. Off means nothing is generated at
  /// all.
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
      UserDefaults.standard.set(sidebarSelection.board, forKey: "sidebarBoard")
      // Another inbox is a fresh look: the unread filter starts over.
      if sidebarSelection != oldValue {
        releaseKeptReads()
      }
    }
  }
  /// The toolbar's date filter, remembered across launches; nil is any time.
  private(set) var activityWindow: ActivityWindow? = AppModel.loadActivityWindow()
  /// The toolbar's unread filter, remembered across launches.
  private(set) var unreadOnly = UserDefaults.standard.bool(forKey: "unreadOnly")
  /// What the pills under the toolbar narrow the inbox to, one value per
  /// facet. Kept for the session only: a pick names one author or
  /// repository, which a later launch may no longer have.
  private(set) var facetPicks: [Facet: String] = [:]
  /// Items read while the unread filter was on. Their threads stay in the
  /// filtered list, drawn as read, until the user moves on — another
  /// inbox, the filter switched, the window closed — so reading a row
  /// never pulls it out from under the pointer.
  private(set) var keptReadIds: Set<String> = []
  /// Which new items notify, and with what sound (settings → Notifications).
  private(set) var notifyScope: NotifyScope = NotifyScope(
    rawValue: UserDefaults.standard.string(forKey: "notifyScope") ?? ""
  ) ?? .mentions
  /// "default", "none", or a system alert sound name ("Ping").
  private(set) var notificationSound: String =
    UserDefaults.standard.string(forKey: "notificationSound") ?? "default"
  /// What the inbox rows show, and in what order (settings → General).
  private(set) var rowLayout: RowLayout = AppModel.loadRowLayout()
  /// Selection is by thread id, so it survives sync updates.
  var selectedThreadIds: Set<String> = []
  /// The card selected on the board, by card id; a board shows one at a
  /// time.
  var selectedCardId: String?
  /// Whether the selected card's preview stands beside the board. Picking
  /// a card shows it; the user can put it away for the whole board and
  /// keep the card selected.
  var cardPreviewShown = false
  /// Whether the main window's sidebar shows; remembered across launches.
  var sidebarShown = !UserDefaults.standard.bool(forKey: "sidebarHidden") {
    didSet {
      UserDefaults.standard.set(!sidebarShown, forKey: "sidebarHidden")
    }
  }
  /// Whether the inbox's preview stands beside the list. It stays as the
  /// user leaves it, across launches.
  var inboxPreviewShown = !UserDefaults.standard.bool(forKey: "previewHidden") {
    didSet {
      UserDefaults.standard.set(!inboxPreviewShown, forKey: "previewHidden")
    }
  }
  /// The board in the editor sheet — an existing one, or a new one not
  /// saved until the sheet is.
  var editingBoard: Board?
  /// A message picked inside the previewed thread: the toolbar actions
  /// narrow to it while set. Ignored whenever it doesn't belong to the
  /// previewed thread.
  var selectedMemberId: String?
  /// Live filter over the inbox list; empty shows everything.
  var searchText = ""
  /// True while the toolbar search field is active; set it to move focus
  /// there (⌘F does).
  var searchPresented = false

  /// Where an item's target's conversation stands, as the preview shows it.
  enum ConversationLoad: Sendable {
    /// Not in yet: the background refresh hasn't reached it, and the
    /// preview asked for it ahead of the rounds.
    case fetching
    case loaded(TargetConversation)
    /// The provider won't show the target; why, fit to show verbatim.
    case unreadable(String)
    /// The ask ahead of the rounds came back empty; why, fit to show. The
    /// rounds go on asking.
    case waiting(String)
  }

  /// A stored conversation the preview has read, and the activity it is
  /// current as of.
  private struct HeldConversation {
    let at: Date
    let conversation: TargetConversation
  }

  /// Conversations read for the preview, by target key — the most recent
  /// `conversationCacheLimit` of them.
  private var conversations: [String: HeldConversation] = [:]
  @ObservationIgnored private var conversationOrder: [String] = []
  /// Why an ask ahead of the rounds came back empty, by target key.
  private var conversationFailures: [String: String] = [:]
  /// Targets an ask ahead of the rounds is out for.
  @ObservationIgnored private var fetchingConversations: Set<String> = []

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
    if unreadOnly {
      keepNewlyRead(state.items)
    }
    // Only what changed is assigned: every assignment wakes every view
    // that reads the property, equal value or not, and a push repeats
    // most of the state unchanged. Toolbar items redraw with a fade, so a
    // push that touched only one card would flicker the whole toolbar.
    assignIfChanged(\.items, state.items)
    assignIfChanged(\.accounts, state.accounts)
    assignIfChanged(\.labels, state.labels)
    assignIfChanged(\.rules, state.rules)
    assignIfChanged(\.sidebarLayout, state.sidebar)
    assignIfChanged(\.boards, state.boards)
    assignIfChanged(\.targets, state.targets)
    assignIfChanged(\.placements, state.placements)
    assignIfChanged(\.suggestions, suggestionsActive ? state.suggestions : [])
    assignIfChanged(\.lastSyncAt, state.lastSyncAt)
    assignIfChanged(\.syncing, state.syncing)
    // A sidebar scope pointing at a removed account would deselect every
    // row and persist the dangling id — snap back to All Inboxes.
    if let account = sidebarSelection.account, !accounts.contains(where: { $0.id == account }) {
      sidebarSelection = SidebarSelection(account: nil, category: sidebarSelection.category)
    }
    // Likewise a deleted board: back to the inbox it was opened over.
    if let board = sidebarSelection.board, !boards.contains(where: { $0.id == board }) {
      sidebarSelection.board = nil
    }
    onStateApplied?(self)
  }

  private func assignIfChanged<Value: Equatable>(_ property: ReferenceWritableKeyPath<AppModel, Value>, _ value: Value) {
    if self[keyPath: property] != value {
      self[keyPath: property] = value
    }
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
      category: defaults.string(forKey: "sidebarCategory") ?? recentCategory.id,
      board: defaults.string(forKey: "sidebarBoard")
    )
  }

  private static func loadActivityWindow() -> ActivityWindow? {
    UserDefaults.standard.string(forKey: "activityWindow").flatMap(ActivityWindow.init(rawValue:))
  }

  func setActivityWindow(_ window: ActivityWindow?) {
    activityWindow = window
    UserDefaults.standard.set(window?.rawValue, forKey: "activityWindow")
  }

  func setUnreadOnly(_ on: Bool) {
    unreadOnly = on
    releaseKeptReads()
    UserDefaults.standard.set(on, forKey: "unreadOnly")
  }

  /// Narrows the inbox to one value of a facet; nil lets it show any.
  func setFacet(_ facet: Facet, to value: String?) {
    facetPicks[facet] = value
  }

  /// Lets the unread filter drop the rows it has been holding read.
  func releaseKeptReads() {
    if !keptReadIds.isEmpty {
      keptReadIds = []
    }
  }

  /// Notes the items a push turns read, so the unread filter keeps their
  /// rows. Every read lands here, wherever it was made — the inbox, the
  /// tray, a banner, or the provider's own site.
  private func keepNewlyRead(_ incoming: [InboxItem]) {
    let unread = Set(items.lazy.filter { !$0.read }.map(\.id))
    let newlyRead = incoming.filter { $0.read && unread.contains($0.id) }.map(\.id)
    if !newlyRead.isEmpty {
      keptReadIds.formUnion(newlyRead)
    }
  }

  func setNotifyScope(_ scope: NotifyScope) {
    notifyScope = scope
    UserDefaults.standard.set(scope.rawValue, forKey: "notifyScope")
  }

  func setNotificationSound(_ sound: String) {
    notificationSound = sound
    UserDefaults.standard.set(sound, forKey: "notificationSound")
  }

  private static func loadRowLayout() -> RowLayout {
    guard let raw = UserDefaults.standard.data(forKey: "rowLayout"),
          let stored = try? JSONDecoder().decode(RowLayout.self, from: raw) else {
      return .default
    }
    return stored
  }

  func setRowLayout(_ layout: RowLayout) {
    let summarized = summariesWanted
    rowLayout = layout
    // Hiding the excerpt leaves a summary nowhere to go; showing it again
    // asks for the ones that were never written.
    if summariesWanted != summarized {
      pushSummariesWanted()
    }
    guard let raw = try? JSONEncoder().encode(layout) else {
      log.error("failed to encode the row layout")
      return
    }
    UserDefaults.standard.set(raw, forKey: "rowLayout")
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

  /// True when the model is writing row summaries right now.
  var summariesActive: Bool {
    intelligenceActive && summariesWanted
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

  private static func loadSummariesEnabled() -> Bool {
    UserDefaults.standard.object(forKey: "summariesEnabled") as? Bool ?? true
  }

  /// What the engine is told: the user's switch, plus the fact that a row
  /// with its excerpt hidden has nowhere to show a summary.
  private var summariesWanted: Bool {
    summariesEnabled && rowLayout.shows(.excerpt)
  }

  private func pushSummariesWanted() {
    let wanted = summariesWanted
    Task {
      await engine?.setSummariesEnabled(wanted)
    }
  }

  func setSummariesEnabled(_ enabled: Bool) {
    summariesEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: "summariesEnabled")
    pushSummariesWanted()
  }

  /// The on-device switches as the user left them, for the launch push —
  /// the engine's own defaults only suit a first run.
  var intelligenceSwitches: (intelligence: Bool, suggestions: Bool, summaries: Bool) {
    (intelligenceEnabled, suggestionsEnabled, summariesWanted)
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

  // MARK: Boards

  /// The board the sidebar has open, if it has one open.
  var selectedBoard: Board? {
    sidebarSelection.board.flatMap { id in boards.first { $0.id == id } }
  }

  /// What a narrowed placement is remembered by.
  private struct NarrowingKey: Hashable {
    let board: BoardId
    let search: String
    let picks: [Facet: String]
  }

  /// Placements already narrowed for the current ones. The board, each
  /// pill's menu, and the window's subtitle all ask on every redraw, and a
  /// selection or a hover is a redraw.
  @ObservationIgnored private var narrowedPlacements: [NarrowingKey: BoardPlacement] = [:]

  /// A board's cards as the engine placed them, narrowed by the search
  /// and by the pills — all of them but `except`'s, for that pill's own
  /// menu. Narrowing never moves a card: each is placed on its own, so
  /// leaving some out changes nothing for the rest.
  func placement(
    of board: Board, search: String = "", picks: [Facet: String] = [:], except: Facet? = nil
  ) -> BoardPlacement {
    // Read on every call, a narrowed placement too: the views asking
    // observe what they read, and one that stopped reading the placements
    // would never hear that they changed.
    let placed = placements[board.id] ?? BoardPlacement()
    let narrowing = picks.filter { $0.key != except }
    guard !narrowing.isEmpty || !search.trimmingCharacters(in: .whitespaces).isEmpty else {
      return placed
    }
    let key = NarrowingKey(board: board.id, search: search, picks: narrowing)
    if let held = narrowedPlacements[key] {
      return held
    }
    let kept = matchingFacets(matchingSearch(placed.allCards, search), narrowing)
    let narrowed = placed.narrowed(to: Set(kept.map(\.id)))
    // Every search keystroke is a new key; a handful is all one screen
    // ever needs at once.
    if narrowedPlacements.count >= 24 {
      narrowedPlacements = [:]
    }
    narrowedPlacements[key] = narrowed
    return narrowed
  }

  func setBoards(_ boards: [Board]) {
    self.boards = boards
    Task {
      await engine?.setBoards(boards)
    }
  }

  /// Edits one board in place and pushes the result.
  func updateBoard(_ id: BoardId, _ change: (inout Board) -> Void) {
    guard let index = boards.firstIndex(where: { $0.id == id }) else {
      return
    }
    var updated = boards
    change(&updated[index])
    setBoards(updated)
  }

  /// Saves a board from the editor: replaced where it stands, or added at
  /// the end and opened.
  func saveBoard(_ board: Board) {
    var updated = boards
    if let index = updated.firstIndex(where: { $0.id == board.id }) {
      updated[index] = board
    } else {
      updated.append(board)
      sidebarSelection = SidebarSelection(account: nil, category: recentCategory.id, board: board.id)
    }
    setBoards(updated)
  }

  func deleteBoard(_ id: BoardId) {
    setBoards(boards.filter { $0.id != id })
    if sidebarSelection.board == id {
      sidebarSelection.board = nil
    }
  }

  /// A board to start editing: the starter board's columns under fresh
  /// ids, since a project board usually wants the same who-moves-next
  /// split, narrowed by a scope.
  func newBoard() -> Board {
    var board = GitForgeBoards.myWork
    board.id = UUID().uuidString
    board.name = "New Board"
    board.columns = board.columns.map { column in
      var copy = column
      copy.id = UUID().uuidString
      return copy
    }
    return board
  }

  /// Puts a card in a column of the board by hand, or (nil) hands it back
  /// to the board's filters. A card put somewhere lands there at once; the
  /// engine's sweep, a moment later, confirms it.
  func pin(_ card: BoardCard, to column: String?, on board: BoardId) {
    if let index = boards.firstIndex(where: { $0.id == board }) {
      boards[index].pins[card.id] = column.map { BoardPin(column: $0, state: card.state) }
    }
    if let column, let placed = placements[board] {
      placements[board] = placed.pinning(card, to: column)
    }
    Task {
      await engine?.setPin(board: board, card: card.id, column: column, state: card.state)
    }
  }

  /// The user has the card open: its new comments count from now on.
  func markSeen(_ card: BoardCard) {
    let countable = card.snapshot?.commentCount != nil
    guard card.target?.seenAt == nil || card.newComments != nil || (countable && card.target?.seenComments == nil) else {
      return
    }
    Task {
      await engine?.markTargetSeen(card.id, provider: card.lead.provider)
    }
  }

  // MARK: Targets

  /// Where a thread's target stands, as its row draws it: the snapshot's
  /// tokens, and whether it waits on a review from the account the thread
  /// came through. nil when the thread points at nothing tracked, or no
  /// refresh has described it yet.
  func targetStatus(for thread: InboxThread) -> TargetStatus? {
    let lead = thread.lead
    guard let key = spec(for: lead.provider).boardKey(for: lead), let snapshot = targets[key]?.snapshot else {
      return nil
    }
    let login = accounts.first { $0.id == lead.accountId }?.username
    return TargetStatus(provider: lead.provider, snapshot: snapshot, ownLogins: login.map { [$0] } ?? [])
  }

  // MARK: Previews

  /// The conversation of the item's target, as the preview shows it; nil
  /// when the item points at nothing a conversation is kept for, or while
  /// a stored one is on its way from disk.
  func conversation(for item: InboxItem) -> ConversationLoad? {
    guard let key = spec(for: item.provider).boardKey(for: item) else {
      return nil
    }
    let target = targets[key]
    if let at = target?.conversationAt {
      guard let held = conversations[key], held.at == at else {
        return nil
      }
      return .loaded(held.conversation)
    }
    if let reason = target?.unreadable {
      return .unreadable(reason)
    }
    if let failure = conversationFailures[key] {
      return .waiting(failure)
    }
    return .fetching
  }

  /// What the preview's load of a conversation follows: a change to it
  /// starts the load again.
  func conversationVersion(for item: InboxItem) -> String {
    let target = spec(for: item.provider).boardKey(for: item).flatMap { targets[$0] }
    let at = target?.conversationAt?.timeIntervalSinceReferenceDate ?? 0
    return "\(item.id)@\(at)\(target?.unreadable == nil ? "" : "!")"
  }

  /// Reads the target's stored conversation, or, when the background
  /// refresh hasn't brought it yet, asks for it ahead of the rounds. An
  /// ask cancelled because the selection moved on leaves nothing behind.
  func loadConversation(for item: InboxItem) async {
    guard let key = spec(for: item.provider).boardKey(for: item), let engine else {
      return
    }
    let target = targets[key]
    if let at = target?.conversationAt {
      guard conversations[key]?.at != at else {
        return
      }
      if let conversation = await engine.conversation(for: key) {
        hold(key, HeldConversation(at: at, conversation: conversation))
      }
      return
    }
    guard target?.unreadable == nil, !fetchingConversations.contains(key) else {
      return
    }
    fetchingConversations.insert(key)
    defer { fetchingConversations.remove(key) }
    if conversationFailures[key] != nil {
      conversationFailures[key] = nil
    }
    let failure = await engine.refreshConversation(key)
    if let failure, !Task.isCancelled {
      conversationFailures[key] = failure
    }
  }

  /// Keeps a conversation read, letting go of the oldest beyond the cache
  /// limit.
  private func hold(_ key: String, _ held: HeldConversation) {
    conversations[key] = held
    conversationOrder.removeAll { $0 == key }
    conversationOrder.append(key)
    while conversationOrder.count > conversationCacheLimit {
      conversations[conversationOrder.removeFirst()] = nil
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

  // MARK: Images

  /// Where a preview of `item` gets the images its bodies show: sources
  /// resolved by the item's provider against its target, pictures fetched
  /// through the account the item came through.
  func bodyImages(for item: InboxItem) -> BodyImageSource {
    let providerSpec = spec(for: item.provider)
    let engine = engine
    let account = item.accountId
    let page = item.url
    return BodyImageSource(
      key: "\(account) \(page)",
      resolve: { providerSpec.bodyURL($0, for: item) },
      fetch: { url in await engine?.image(url, account: account, page: page) }
    )
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
