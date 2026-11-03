// The UI-facing state: the latest AppState the engine pushed, plus view
// state both windows share, plus the action methods. The composition root
// of the app's main-actor side: the user's lasting choices live in
// Preferences and the preview's conversations in ConversationCache, both
// read through here, so views see one model. Actions mostly need no
// optimistic update — the engine is in-process and pushes immediately; the
// edits a keystroke or a drag must answer at once apply here first, and
// the push echoes them.

import AppKit
import Observation
import os
import ServiceManagement

private let log = Logger(subsystem: "dev.majordomo.app", category: "app")

/// True when running from a real .app bundle. SMAppService and
/// UNUserNotificationCenter require one; a bare `swift run` executable
/// must skip them instead of crashing.
let isBundled = Bundle.main.bundleIdentifier != nil

@MainActor
@Observable
final class AppModel {
  // Engine-pushed state.
  private(set) var items: [InboxItem] = [] {
    didSet {
      sidebarSections = [:]
    }
  }
  private(set) var accounts: [AccountState] = []
  /// The user's labels (folder order) and rules (evaluation order). Edits
  /// apply here at once — the settings editors bind text fields to them,
  /// and a round trip through the engine would lag the keystrokes — then
  /// push to the engine, whose next state echoes the same values.
  private(set) var labels: [InboxLabel] = [] {
    didSet {
      sidebarSections = [:]
    }
  }
  private(set) var rules: [LabelRule] = [] {
    didSet {
      sidebarSections = [:]
    }
  }
  /// The sidebar's tree of inboxes and folders; edited through
  /// `updateSidebar`, which applies here at once and pushes to the engine.
  private(set) var sidebarLayout = SidebarLayout() {
    didSet {
      sidebarSections = [:]
    }
  }
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
  /// The suggestions the engine holds, whether or not they are on offer.
  private var pendingSuggestions: [Suggestion] = []
  /// Whether the on-device model can run here; read once the engine has
  /// installed its provider.
  private(set) var intelligence: IntelligenceAvailability = .unavailable("Checking…")
  private(set) var lastSyncAt: Date?
  private(set) var syncing = false
  /// The revisions of the slices this model holds (see apply).
  @ObservationIgnored private var appliedRevisions = StateRevisions()

  // Worked out once per push rather than on every read.
  /// Whether any item is unread.
  private(set) var anyUnread = false
  /// Unread THREADS — the number of rows needing attention, matching the
  /// sidebar badges and the dock badge to what the list actually shows.
  private(set) var unreadCount = 0
  /// Whether an unread mention waits: the tray's dot.
  private(set) var unreadMentionDot = false

  // Local facts.
  private(set) var launchAtLogin = false
  /// True while an add-account validation runs; its failure lands in
  /// `connectError` for the sheet.
  private(set) var connecting = false
  private(set) var connectError: String?
  /// Ticked every 30s so relative timestamps stay fresh.
  private(set) var now = Date()

  // Shared view state.
  /// The user's choices that outlive a launch.
  @ObservationIgnored let preferences: Preferences
  /// The conversations the preview has read.
  @ObservationIgnored let conversations = ConversationCache()
  /// What the pills under the toolbar narrow the inbox to, one value per
  /// facet. Kept for the session only: a pick names one author or
  /// repository, which a later launch may no longer have.
  private(set) var facetPicks: [Facet: String] = [:]
  /// Items read while the unread filter was on. Their threads stay in the
  /// filtered list, drawn as read, until the user moves on — another
  /// inbox, the filter switched, the window closed — so reading a row
  /// never pulls it out from under the pointer.
  private(set) var keptReadIds: Set<String> = []
  /// Selection is by thread id, so it survives sync updates.
  var selectedThreadIds: Set<String> = []
  /// The card selected on the board, by card id; a board shows one at a
  /// time.
  var selectedCardId: String?
  /// Whether the selected card's preview stands beside the board. Picking
  /// a card shows it; the user can put it away for the whole board and
  /// keep the card selected.
  var cardPreviewShown = false
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

  typealias ConversationLoad = ConversationCache.Load

  @ObservationIgnored var engine: SyncEngine?
  @ObservationIgnored var openMainWindow: (@MainActor () -> Void)?
  @ObservationIgnored var openSettings: (@MainActor () -> Void)?

  init(preferences: Preferences = Preferences()) {
    self.preferences = preferences
  }

  var hasAccounts: Bool { !accounts.isEmpty }

  // MARK: Preferences

  /// Which inbox is showing; remembered across launches.
  var sidebarSelection: SidebarSelection {
    get {
      preferences.sidebarSelection
    }
    set {
      let changed = newValue != preferences.sidebarSelection
      preferences.sidebarSelection = newValue
      // Another inbox is a fresh look: the unread filter starts over.
      if changed {
        releaseKeptReads()
      }
    }
  }

  /// Whether the main window's sidebar shows; remembered across launches.
  var sidebarShown: Bool {
    get { preferences.sidebarShown }
    set { preferences.sidebarShown = newValue }
  }

  /// Whether the inbox's preview stands beside the list. It stays as the
  /// user leaves it, across launches.
  var inboxPreviewShown: Bool {
    get { preferences.inboxPreviewShown }
    set { preferences.inboxPreviewShown = newValue }
  }

  /// The toolbar's date filter, remembered across launches; nil is any time.
  var activityWindow: ActivityWindow? { preferences.activityWindow }
  /// The toolbar's unread filter, remembered across launches.
  var unreadOnly: Bool { preferences.unreadOnly }
  /// Which new items notify, and with what sound (settings → Notifications).
  var notifyScope: NotifyScope { preferences.notifyScope }
  /// "default", "none", or a system alert sound name ("Ping").
  var notificationSound: String { preferences.notificationSound }
  /// What the inbox rows show, and in what order (settings → General).
  var rowLayout: RowLayout { preferences.rowLayout }
  /// Whether the model watches for patterns worth a label at all; only
  /// consulted while `intelligenceEnabled` is on.
  var suggestionsEnabled: Bool { preferences.suggestionsEnabled }
  /// Whether the model writes the one-line summaries the rows show in
  /// place of raw excerpt text; only consulted while `intelligenceEnabled`
  /// is on.
  var summariesEnabled: Bool { preferences.summariesEnabled }
  /// The master switch over every on-device feature — the rule composer,
  /// the suggestions, and the summaries. Off means nothing is generated at
  /// all.
  var intelligenceEnabled: Bool { preferences.intelligenceEnabled }

  // MARK: Pushes

  /// Takes in a push: only the slices whose revision moved are assigned,
  /// so a push that changed one board costs the integers it compares, not
  /// a pass over every item. (Assigning an Equatable property its own
  /// value notifies no one, but finding that out compares the whole
  /// value.)
  func apply(_ state: AppState) {
    let moved = state.revisions.moved(since: appliedRevisions)
    appliedRevisions = state.revisions
    if moved.contains(.items) {
      if unreadOnly {
        keepNewlyRead(state.items)
      }
      items = state.items
      noteUnread()
    }
    if moved.contains(.accounts) {
      accounts = state.accounts
    }
    if moved.contains(.status) {
      lastSyncAt = state.lastSyncAt
      syncing = state.syncing
    }
    if moved.contains(.labels) {
      labels = state.labels
    }
    if moved.contains(.rules) {
      rules = state.rules
    }
    if moved.contains(.sidebar) {
      sidebarLayout = state.sidebar
    }
    if moved.contains(.suggestions) {
      pendingSuggestions = state.suggestions
    }
    if moved.contains(.boards) {
      boards = state.boards
    }
    if moved.contains(.targets) {
      targets = state.targets
    }
    if moved.contains(.placements) {
      placements = state.placements
    }
    // A sidebar scope pointing at a removed account would deselect every
    // row and persist the dangling id — snap back to All Inboxes.
    if let account = sidebarSelection.account, !accounts.contains(where: { $0.id == account }) {
      sidebarSelection = SidebarSelection(account: nil, category: sidebarSelection.category)
    }
    // Likewise a deleted board: back to the inbox it was opened over.
    if let board = sidebarSelection.board, !boards.contains(where: { $0.id == board }) {
      sidebarSelection.board = nil
    }
  }

  /// The unread figures the chrome and the window read, from the items as
  /// they now stand.
  private func noteUnread() {
    anyUnread = items.contains { !$0.read }
    unreadCount = groupIntoThreads(items).count { !$0.read }
    unreadMentionDot = items.contains { $0.isMention && !$0.read }
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

  func setActivityWindow(_ window: ActivityWindow?) {
    preferences.activityWindow = window
  }

  func setUnreadOnly(_ on: Bool) {
    preferences.unreadOnly = on
    releaseKeptReads()
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
    preferences.notifyScope = scope
  }

  func setNotificationSound(_ sound: String) {
    preferences.notificationSound = sound
  }

  func setRowLayout(_ layout: RowLayout) {
    let summarized = summariesWanted
    preferences.rowLayout = layout
    // Hiding the excerpt leaves a summary nowhere to go; showing it again
    // asks for the ones that were never written.
    if summariesWanted != summarized {
      pushSummariesWanted()
    }
  }

  // MARK: Labels

  /// Everything that exists: the providers' built-ins plus the user's,
  /// assembled the one way (see LabelCatalog). The views read their label
  /// lists from here rather than composing unions of their own.
  var catalog: LabelCatalog {
    .current(user: labels, userRules: rules)
  }

  /// Every label the sidebar can show: the providers' built-ins as "All
  /// Inboxes" merges them, then the user's.
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

  /// Labels and rules the on-device model suggests, waiting on the user —
  /// none while `suggestionsActive` is off.
  var suggestions: [Suggestion] {
    suggestionsActive ? pendingSuggestions : []
  }

  /// Turns every on-device feature off or on at once.
  func setIntelligenceEnabled(_ enabled: Bool) {
    preferences.intelligenceEnabled = enabled
    Task {
      await engine?.setIntelligenceEnabled(enabled)
    }
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
    preferences.summariesEnabled = enabled
    pushSummariesWanted()
  }

  /// The on-device switches as the user left them, for the launch push —
  /// the engine's own defaults only suit a first run.
  var intelligenceSwitches: (intelligence: Bool, suggestions: Bool, summaries: Bool) {
    (intelligenceEnabled, suggestionsEnabled, summariesWanted)
  }

  func setSuggestionsEnabled(_ enabled: Bool) {
    preferences.suggestionsEnabled = enabled
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

  // MARK: Sidebar

  /// One sidebar section as it draws: its rows, and the unread threads of
  /// each inbox and folder in it, by row id.
  private struct SidebarSection {
    let rows: [SidebarRow]
    let unread: [String: Int]
  }

  /// Sections worked out since what they read last changed, by account
  /// id ("" for All Inboxes). The sidebar redraws on a selection, a sync
  /// starting, a board's badge; the sections only change with the items,
  /// the labels, and the layout.
  @ObservationIgnored private var sidebarSections: [String: SidebarSection] = [:]

  /// A section's rows — All Inboxes (nil) or one account's — drawn from
  /// the layout: inboxes and folders in the user's order, hidden ones
  /// skipped.
  func sidebarRows(for account: AccountState?) -> [SidebarRow] {
    sidebarSection(for: account).rows
  }

  /// Unread threads, not items, in an inbox or folder of a section — the
  /// badge matches the rows the list will show, and an item in two of a
  /// folder's inboxes counts once.
  func unreadThreads(in rowId: String, account: AccountState?) -> Int {
    sidebarSection(for: account).unread[rowId] ?? 0
  }

  private func sidebarSection(for account: AccountState?) -> SidebarSection {
    // Read on every call, a held section too: the views asking observe
    // what they read, and one that stopped reading would never hear of a
    // change.
    let items = items
    let labels = catalog.sectionLabels(for: account?.provider)
    let layout = sidebarLayout
    let key = account?.id ?? ""
    if let held = sidebarSections[key] {
      return held
    }
    let scoped = account.map { scope in items.filter { $0.accountId == scope.id } } ?? items
    let rows = Majordomo.sidebarRows(layout: layout, categories: categorize(scoped, into: categories(for: labels)))
    var unread: [String: Int] = [:]
    func count(_ rows: [SidebarRow]) {
      for row in rows {
        switch row {
        case .inbox(let category):
          unread[category.id] = groupIntoThreads(category.items).count { !$0.read }
        case .folder(let folder, let inside):
          unread[folder.id] = unreadThreadCount(in: inside)
          count(inside)
        }
      }
    }
    count(rows)
    let section = SidebarSection(rows: rows, unread: unread)
    sidebarSections[key] = section
    return section
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
    return conversations.load(key, target: targets[key])
  }

  /// What the preview's load of a conversation follows: a change to it
  /// starts the load again.
  func conversationVersion(for item: InboxItem) -> String {
    let target = spec(for: item.provider).boardKey(for: item).flatMap { targets[$0] }
    let at = target?.conversationAt?.timeIntervalSinceReferenceDate ?? 0
    return "\(item.id)@\(at)\(target?.unreadable == nil ? "" : "!")"
  }

  /// Reads the target's stored conversation, or, when the background
  /// refresh hasn't brought it yet, asks for it ahead of the rounds.
  func loadConversation(for item: InboxItem) async {
    guard let key = spec(for: item.provider).boardKey(for: item), let engine else {
      return
    }
    await conversations.fetch(key, target: targets[key], from: engine)
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
