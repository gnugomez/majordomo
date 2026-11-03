// The sync engine: owns the store and the provider clients, reconciles
// fetches into the collection, and publishes AppState snapshots to the UI.
// An actor, so every mutation is serialized. Accounts are plural per
// provider — every stored account syncs through its provider's client.

import AppKit
import Foundation

private let syncInterval: Duration = .seconds(60)
/// The timer syncs at .recent depth; a .full pass — every page — runs on
/// manual refresh and at least this often, so items beyond the recent
/// window surface instead of hiding until the window happens to shift.
private let fullSyncInterval: TimeInterval = 60 * 60
/// The shortest gap between suggestion sweeps. Patterns build over days,
/// so asking the model more often than this would spend battery to be
/// told the same thing — and a deep sync's import must not set off a
/// burst of them.
private let suggestionSweepInterval: TimeInterval = 6 * 60 * 60
/// Summaries a sweep writes at most. Each one is a model round trip of a
/// second or two, so a pass takes the rows the user is looking at and
/// leaves the rest to the next one.
private let summaryBudget = 8
/// Verdicts a sweep collects at most, across every intelligence rule. The
/// same bargain as the summaries: the rows in front of the user first, the
/// rest on the next pass.
private let verdictBudget = 8
/// An open target is refreshed again this long after its last refresh; a
/// finished one only when new activity arrives.
private let openTargetRefreshInterval: TimeInterval = 15 * 60
/// New unread items only post a banner while their activity is this fresh.
/// A deep sync can surface months-old backlog in one go — that belongs in
/// the inbox as unread, not in Notification Center as a flood.
private let notifyFreshnessWindow: TimeInterval = 24 * 60 * 60

actor SyncEngine {
  private let store: Store
  /// One client per provider implementation, shared by its accounts.
  private let clients: [ProviderId: any ProviderClient]
  /// Pushes a fresh snapshot to the UI (hops to the main actor).
  private let emit: @Sendable (AppState) -> Void
  /// Posts a user notification for a newly arrived unread item.
  private let notify: @Sendable (InboxItem) -> Void

  /// The on-device model, when one can run here; the null provider
  /// otherwise, which simply says so.
  private var intelligence: any IntelligenceProvider = NoIntelligence(
    reason: "Apple Intelligence isn't set up on this Mac."
  )

  /// Sync/validation errors per account; the rest of an account's state
  /// reads straight from the store.
  private var errors: [AccountId: String] = [:]
  private var lastSyncAt: Date?
  private var lastFullSyncAt: Date?
  private var syncing = false
  /// True while a suggestion sweep is out with the model.
  private var suggesting = false
  /// Whether to look for patterns at all; the user's call, pushed from
  /// settings.
  private var suggestionsEnabled = true
  /// The master switch over every on-device feature.
  private var intelligenceEnabled = true
  /// Whether the model writes the rows' summaries. The app model folds the
  /// row layout into this: with the excerpt line hidden there is nowhere to
  /// show one, and nothing is generated.
  private var summariesEnabled = true
  /// True while a summary sweep is out with the model.
  private var summarizing = false
  /// Items the model wouldn't summarize this run — a guardrail refusal or
  /// a hiccup. Forgotten at relaunch; retrying them every minute would
  /// spend the budget on the same failures.
  private var summaryFailures: Set<String> = []
  /// True while a verdict sweep is out with the model.
  private var judging = false
  /// "item:rule" pairs the model wouldn't answer this run, for the same
  /// reason as the summary failures.
  private var verdictFailures: Set<String> = []
  /// When the last sweep ran, so the next one waits its turn.
  private var lastSuggestionSweepAt: Date?
  /// True while a board refresh is out with the providers.
  private var refreshingTargets = false
  private var inFlight: Task<Void, Never>?
  private var timer: Task<Void, Never>?

  init(
    emit: @escaping @Sendable (AppState) -> Void,
    notify: @escaping @Sendable (InboxItem) -> Void
  ) {
    self.emit = emit
    self.notify = notify
    if isDemo {
      let fixture = DemoData.storeFile()
      store = Store(fixture: fixture, conversations: DemoData.conversations(in: fixture))
    } else {
      store = Store()
    }
    store.builtinLabelIds = LabelCatalog.current(user: [], userRules: []).builtinIds
    // The starter label and rule, once per store (see StarterSetup): the
    // feature arrives configured, and stays deleted if the user deletes it.
    store.seed(labels: StarterSetup.labels, rules: StarterSetup.rules)
    store.seedBoards([GitForgeBoards.myWork])
    clients = Dictionary(uniqueKeysWithValues: providerSpecs.map { ($0.id, $0.makeClient()) })
    for account in store.accounts() where account.config == nil {
      errors[account.id] = "The stored token can't be read — remove and re-add the account."
    }
  }

  func getState() -> AppState {
    // Items ship unordered — every list sorts for display via inboxOrder.
    let items = store.inboxItems()
    let accounts = store.accounts().map { stored in
      AccountState(
        id: stored.id,
        provider: stored.provider,
        username: stored.username,
        name: stored.name,
        avatarUrl: stored.avatarUrl,
        baseUrl: stored.baseUrl,
        error: errors[stored.id]
      )
    }
    return AppState(
      items: items, accounts: accounts, lastSyncAt: lastSyncAt, syncing: syncing,
      labels: store.labels(), rules: store.rules(), sidebar: sidebarLayout(),
      suggestions: store.suggestions().filter { !$0.dismissed },
      boards: store.boards(), targets: store.targets()
    )
  }

  // MARK: Intelligence

  /// Installs the provider the app shell built (the real one needs
  /// FoundationModels, which the engine doesn't import).
  func setIntelligence(_ provider: any IntelligenceProvider) {
    intelligence = provider
  }

  func intelligenceAvailability() -> IntelligenceAvailability {
    intelligence.availability()
  }

  /// A sentence into a rule the app will actually run: the model drafts,
  /// `RuleDraft.validated` checks, and only then does anything reach the
  /// store. Returns the rule and the target it would create, for the user
  /// to confirm — nothing is saved here.
  func composeRule(from text: String) async -> Result<ValidatedRule, IntelligenceError> {
    guard intelligenceEnabled else {
      return .failure(IntelligenceError(message: "Apple Intelligence features are switched off in Settings."))
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .failure(IntelligenceError(message: "Describe the rule you want in a sentence."))
    }
    do {
      let draft = try await intelligence.composeRule(from: trimmed, labels: store.labels())
      switch draft.validated(against: store.labels()) {
      case .success(let validated):
        return .success(validated)
      case .failure(let error):
        return .failure(IntelligenceError(message: error.localizedDescription))
      }
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      return .failure(IntelligenceError(message: message))
    }
  }

  /// Stores a composed or accepted rule: its new target first, so the rule
  /// has something to point at, then a sweep so the inbox reflects it at
  /// once.
  func applyRule(_ validated: ValidatedRule) {
    if let target = validated.newTarget {
      store.setLabels(store.labels() + [target])
    }
    store.setRules(store.rules() + [validated.rule])
    sweepLabels()
    reconcileSidebar()
    emitState()
  }

  /// Looks for patterns worth a label and asks the model about the
  /// strongest few. Mining is deterministic (see Suggestion.swift); the
  /// model only names and judges.
  func sweepSuggestions() async {
    guard intelligenceEnabled, suggestionsEnabled, intelligence.availability().isAvailable, !suggesting else {
      return
    }
    suggesting = true
    lastSuggestionSweepAt = Date()
    defer { suggesting = false }
    let labels = store.labels()
    let candidates = suggestionCandidates(
      in: store.inboxItems(),
      coveredSignatures: coveredSignatures(in: store.rules()),
      dismissed: store.dismissedSignatures()
    ).prefix(suggestionCandidateBudget)
    guard !candidates.isEmpty else {
      return
    }
    var fresh: [Suggestion] = []
    for candidate in candidates {
      guard let draft = try? await intelligence.judge(candidate, labels: labels), !draft.targetName.isEmpty else {
        continue
      }
      // The model names the label; the conditions stay the mined ones, so
      // a suggestion always matches the pattern it came from.
      fresh.append(
        Suggestion(
          id: UUID().uuidString,
          signature: candidate.signature,
          name: draft.name.isEmpty ? draft.targetName : draft.name,
          targetName: draft.targetName,
          targetKind: draft.targetKind.lowercased() == "inbox" ? .inbox : .label,
          targetSymbol: NSSymbolName.known(draft.targetSymbol) ?? "tag",
          targetTint: LabelTint(rawValue: draft.targetTint.lowercased()) ?? .blue,
          rationale: draft.rationale,
          conditions: candidate.conditions,
          matchCount: candidate.count,
          createdAt: Date()
        )
      )
    }
    guard !fresh.isEmpty else {
      return
    }
    store.addSuggestions(fresh)
    emitState()
  }

  /// Writes the missing row summaries, a budgeted handful at a time, and
  /// publishes each one as it lands so rows fill in rather than appearing
  /// all at once. Runs after every sync and whenever the feature is
  /// switched back on.
  func sweepSummaries() async {
    guard intelligenceEnabled, summariesEnabled, intelligence.availability().isAvailable, !summarizing else {
      return
    }
    summarizing = true
    defer { summarizing = false }
    var written: [(itemId: String, summary: String, text: String)] = []
    let queue = store.itemsNeedingSummary(limit: summaryBudget)
      .filter { !summaryFailures.contains($0.id) }
    for item in queue {
      guard let body = item.body else {
        continue
      }
      let request = SummaryRequest(
        title: item.title, repo: item.repo, author: item.author, body: body
      )
      guard let summary = try? await intelligence.summarize(request), !summary.isEmpty else {
        summaryFailures.insert(item.id)
        continue
      }
      written.append((itemId: item.id, summary: summary, text: body))
    }
    // One write and one push for the batch: the store rewrites its whole
    // file per save, and every push re-lays the list out. A sweep that did
    // both per answer paid each cost eight times over, which is what the
    // window going sticky while the model works was made of. Items pruned
    // or parked meanwhile are dropped by the store.
    guard !written.isEmpty else {
      return
    }
    store.setSummaries(written)
    emitState()
  }

  /// Answers what the intelligence rules are asking: a budgeted handful of
  /// item-and-question pairs per pass, newest unread first, each one
  /// published as it lands so a label fills in rather than appearing all at
  /// once. Runs after every sync and whenever the rules change.
  func sweepVerdicts() async {
    guard intelligenceEnabled, intelligence.availability().isAvailable, !judging else {
      return
    }
    let asking = store.rules().filter { $0.enabled && $0.question != nil }
    guard !asking.isEmpty else {
      return
    }
    judging = true
    defer { judging = false }
    var answers: [(itemId: String, rule: String, matched: Bool, question: String)] = []
    // One queue across every rule, so a rule with a long backlog can't
    // starve the others of the budget.
    let queue = asking
      .flatMap { rule -> [(item: StoredItem, rule: LabelRule, question: String)] in
        guard let question = rule.question else {
          return []
        }
        return store.itemsNeedingVerdict(rule: rule.id, question: question, limit: verdictBudget)
          .map { (item: $0, rule: rule, question: question) }
      }
      .filter { !verdictFailures.contains("\($0.item.id):\($0.rule.id)") }
      .sorted { a, b in
        if a.item.read != b.item.read {
          return b.item.read
        }
        return a.item.updatedAt > b.item.updatedAt
      }
      .prefix(verdictBudget)
    for (item, rule, question) in queue {
      let request = VerdictRequest(
        question: question,
        title: item.title,
        repo: item.repo,
        author: item.author,
        body: item.body,
        isMention: item.isMention
      )
      guard let matched = try? await intelligence.evaluate(request) else {
        verdictFailures.insert("\(item.id):\(rule.id)")
        continue
      }
      answers.append((itemId: item.id, rule: rule.id, matched: matched, question: question))
    }
    // The answers only become labels through the rules: store, sweep, then
    // publish — once for the batch, since all three cost the whole
    // collection.
    guard !answers.isEmpty else {
      return
    }
    store.setVerdicts(answers)
    sweepLabels()
    emitState()
  }

  /// Turns the row summaries on or off. Switching them on catches up at
  /// once — the alternative is a minute of rows that say nothing.
  func setSummariesEnabled(_ enabled: Bool) {
    guard enabled != summariesEnabled else {
      return
    }
    summariesEnabled = enabled
    if enabled {
      Task {
        await self.sweepSummaries()
      }
    }
  }

  /// The on-device switches as the user left them, pushed once at launch:
  /// the engine's own defaults are only right for a first run.
  func setIntelligenceSwitches(intelligence: Bool, suggestions: Bool, summaries: Bool) {
    intelligenceEnabled = intelligence
    suggestionsEnabled = suggestions
    summariesEnabled = summaries
  }

  /// Turns a suggestion into a real label and rule.
  func acceptSuggestion(_ id: String) {
    guard let suggestion = store.suggestions().first(where: { $0.id == id }) else {
      return
    }
    let labels = store.labels()
    let existing = labels.first { $0.name.caseInsensitiveCompare(suggestion.targetName) == .orderedSame }
    let target = existing ?? InboxLabel(
      id: UUID().uuidString,
      name: suggestion.targetName,
      symbol: suggestion.targetSymbol,
      tint: suggestion.targetTint,
      notify: .follow,
      order: labels.count,
      kind: suggestion.targetKind
    )
    let rule = LabelRule(
      id: UUID().uuidString, name: suggestion.name, conditions: suggestion.conditions, labelIds: [target.id]
    )
    applyRule(ValidatedRule(rule: rule, newTarget: existing == nil ? target : nil))
    store.removeSuggestion(id)
    emitState()
  }

  func dismissSuggestion(_ id: String) {
    store.dismissSuggestion(id)
    emitState()
  }

  /// Turns pattern-watching on or off. Switching it off stops the sweeps
  /// and hides what is pending, without forgetting the dismissals — on
  /// again and the same patterns stay quiet.
  func setSuggestionsEnabled(_ enabled: Bool) {
    suggestionsEnabled = enabled
    emitState()
  }

  /// Turns every on-device feature off or on. Off, nothing is drafted and
  /// no sweep runs; what was already suggested simply stops being offered,
  /// and the summaries already written stay on their rows.
  func setIntelligenceEnabled(_ enabled: Bool) {
    intelligenceEnabled = enabled
    emitState()
    if enabled {
      Task {
        await self.sweepSummaries()
      }
      Task {
        await self.sweepVerdicts()
      }
    }
  }

  private func emitState() {
    emit(getState())
  }

  private func doSync(depth: FetchDepth) async {
    syncing = true
    emitState()

    // Accounts syncing for the first time seed silently: their entire
    // backlog is standing state, not news. Only accounts that already have
    // items can produce notification-worthy arrivals.
    let seededAccounts = Set(store.getItems().map(\.accountId))
    var newIds: [String] = []

    // Fetches run concurrently; results are applied serially on the actor.
    let results = await withTaskGroup(
      of: (AccountId, ProviderId, Result<FetchResult, Error>)?.self
    ) { group in
      for account in store.accounts() {
        guard let client = clients[account.provider], let config = account.config else {
          continue
        }
        let id = account.id
        let provider = account.provider
        group.addTask {
          do {
            return (id, provider, .success(try await client.fetchItems(config, depth: depth)))
          } catch {
            return (id, provider, .failure(error))
          }
        }
      }
      var collected: [(AccountId, ProviderId, Result<FetchResult, Error>)] = []
      for await result in group {
        if let result {
          collected.append(result)
        }
      }
      return collected
    }

    for (accountId, provider, result) in results {
      // Removed while the fetch was in flight: the account is parked now,
      // and a stale fetch has no business adding to (or bumping) what it
      // parked.
      guard store.getAccount(accountId) != nil else {
        continue
      }
      switch result {
      case let .success(fetch):
        errors[accountId] = nil

        // Reconcile, never replace: the collection is the app's own.
        let added = store.upsertItems(fetch.items, accountId: accountId, provider: provider)
        if seededAccounts.contains(accountId) {
          newIds.append(contentsOf: added)
        }
        // Rules run over the refreshed items right away, so the state pushed
        // at the end of the sync — and any banner — carries their labels.
        sweepLabels(accountId: accountId)

        // Items upstream stopped returning (GitHub's /notifications only
        // lists unread threads, for one) were handled there: mark them read
        // locally. Only a complete fetch proves absence — a capped one
        // can't say whether an item is gone or just beyond the cap.
        if fetch.complete {
          let fetchedIds = Set(fetch.items.map { "\(accountId):\($0.externalId)" })
          let absent = store.getItems()
            .filter { item in
              item.accountId == accountId && !item.read && !fetchedIds.contains(item.id)
            }
            .map(\.id)
          if !absent.isEmpty {
            store.markRead(absent)
          }
        }
      case let .failure(error):
        // Keep this account's items untouched; just surface the error.
        errors[accountId] = errorMessage(error)
      }
    }

    if !newIds.isEmpty {
      let byId = Dictionary(uniqueKeysWithValues: store.inboxItems().map { ($0.id, $0) })
      // Items that arrive already handled upstream don't deserve a ping —
      // nor does old backlog a deep fetch surfaced (it shows up unread in
      // the inbox instead). Which fresh unread ones do is the notification
      // scope setting's call, applied by the app shell.
      let freshCutoff = Date().addingTimeInterval(-notifyFreshnessWindow)
      let fresh = newIds.compactMap { byId[$0] }
        .filter { !$0.read && $0.updatedAt > freshCutoff }
      // One banner per thread: a target arriving as several notifications at
      // once (a GitLab MR mentioning, assigning, and requesting review) pings
      // once. The mention member fronts it so the scope setting sees it.
      for thread in groupIntoThreads(fresh) {
        notify(thread.items.first { $0.isMention } ?? thread.lead)
      }
    }

    store.prune()

    lastSyncAt = Date()
    if depth == .full {
      lastFullSyncAt = lastSyncAt
    }
    syncing = false
    emitState()

    // The boards and the previews' conversations catch up next, on their
    // own requests; the inbox above is already current.
    Task {
      await self.refreshTargets()
    }
    // The model catches up in the background; nothing here waits on it.
    // Summaries go first: they are what the rows are missing right now,
    // while patterns build over days.
    Task {
      await self.sweepSummaries()
    }
    Task {
      await self.sweepVerdicts()
    }
    if suggestionSweepIsDue() {
      Task {
        await self.sweepSuggestions()
      }
    }
  }

  /// True when no sweep has run yet, or the interval has passed.
  private func suggestionSweepIsDue() -> Bool {
    guard let lastSuggestionSweepAt else {
      return true
    }
    return Date().timeIntervalSince(lastSuggestionSweepAt) >= suggestionSweepInterval
  }

  // MARK: Labels

  /// Everything that exists right now: the providers' built-ins plus the
  /// user's, read fresh from the store so a rule or label edit is in it.
  private func catalog() -> LabelCatalog {
    .current(user: store.labels(), userRules: store.rules())
  }

  /// Recomputes the rules' assignments for the live items — one account's,
  /// or every account's — and persists only the sets that changed, in one
  /// save. The providers' built-in rules and labels (the sidebar buckets)
  /// run alongside the user's. Parked accounts' items are not live and
  /// stay as they were.
  private func sweepLabels(accountId: AccountId? = nil) {
    let stored = store.getItems().filter { accountId == nil || $0.accountId == accountId }
    let catalog = catalog()
    // "Hide from everywhere" means every inbox in the sidebar, the
    // catch-all included — that is what makes a moved item disappear from
    // Recent as well.
    let everyInbox = [catchAllInboxId] + catalog.labels.map(\.id)
    let assigned = LabelEngine.assign(
      stored.map { store.inboxItem($0) },
      rules: catalog.rules,
      labels: catalog.labels,
      everyInbox: everyInbox
    )
    let updates = stored.compactMap { item -> (id: String, labels: Set<LabelId>, hiddenFrom: Set<LabelId>)? in
      let result = assigned[item.id] ?? LabelEngine.Assignment()
      if result.labels == item.autoLabels, result.hiddenFrom == item.hiddenFrom {
        return nil
      }
      return (id: item.id, labels: result.labels, hiddenFrom: result.hiddenFrom)
    }
    store.applyAutoLabels(updates)
  }

  /// Replaces the label set and re-sweeps: a deleted label leaves every
  /// item and rule (Store.setLabels), and the rest reassign under the new
  /// set. The sidebar picks up new labels and drops deleted ones.
  func setLabels(_ labels: [InboxLabel]) {
    store.setLabels(labels)
    sweepLabels()
    reconcileSidebar()
    emitState()
  }

  // MARK: Sidebar

  /// The sidebar layout in step with what exists: the stored one (or the
  /// standard one on a store that has none), with new labels added and
  /// vanished ones dropped.
  private func sidebarLayout() -> SidebarLayout {
    let catalog = catalog()
    let builtins = catalog.builtinLabels.map(\.id)
    let inboxes = catalog.userInboxes.map(\.id)
    let labels = catalog.userLabels.map(\.id)
    let stored = store.sidebarLayout()
      ?? .standard(catchAll: catchAllInboxId, builtins: builtins + inboxes, labels: labels)
    return stored.reconciled(catchAll: catchAllInboxId, builtins: builtins, inboxes: inboxes, labels: labels)
  }

  /// Persists the reconciled layout when it differs from the stored one.
  private func reconcileSidebar() {
    store.setSidebarLayout(sidebarLayout())
  }

  /// The user's sidebar edits (Inboxes settings, a label's show-as-inbox
  /// switch): stored as given, reconciled on the way back out.
  func setSidebarLayout(_ layout: SidebarLayout) {
    store.setSidebarLayout(layout)
    emitState()
  }

  /// Replaces the rules and re-sweeps every live item. A rewritten
  /// question drops the answers it was given (Store.setRules), so the
  /// labels it fed empty here and fill again as the model catches up.
  func setRules(_ rules: [LabelRule]) {
    store.setRules(rules)
    verdictFailures = []
    sweepLabels()
    emitState()
    Task {
      await self.sweepVerdicts()
    }
  }

  /// The user's hand on one item's label: forced on, forced off, or (nil)
  /// back to whatever the rules say.
  func setLabelOverride(itemId: String, labelId: LabelId, on: Bool?) {
    store.setLabelOverride(itemId: itemId, labelId: labelId, on: on)
    emitState()
  }

  // MARK: Boards

  func setBoards(_ boards: [Board]) {
    store.setBoards(boards)
    emitState()
  }

  /// Puts a card in a column by hand, noting the state it is in; nil
  /// hands it back to the rules.
  func setPin(board: BoardId, card: String, column: String?, state: String?) {
    store.setPin(board: board, card: card, pin: column.map { BoardPin(column: $0, state: state) })
    emitState()
  }

  /// The user had the card open: what is new on it counts from now.
  func markTargetSeen(_ key: String, provider: ProviderId) {
    store.markTargetSeen(key, provider: provider, at: Date())
    emitState()
  }

  /// Refreshes the targets that are due, most pressing first: those with
  /// activity since their last refresh (or none yet), newest first; then
  /// those whose conversation is missing or behind their last activity —
  /// the backfill, newest first; then open ones gone stale, longest
  /// waiting first. The first two bring their conversations along. What a
  /// round leaves unanswered — a failure, a limit — is first in line the
  /// next time.
  private func refreshTargets() async {
    guard !isDemo, !refreshingTargets else {
      return
    }
    refreshingTargets = true
    defer { refreshingTargets = false }

    let newest = newestItemsByTarget()
    store.pruneTargets(keeping: Set(newest.keys))

    let now = Date()
    let known = store.targets()
    var active: [(key: String, item: InboxItem)] = []
    var behind: [(key: String, item: InboxItem)] = []
    var stale: [(key: String, item: InboxItem, fetchedAt: Date)] = []
    for (key, item) in newest {
      guard let target = known[key], let fetchedAt = target.fetchedAt, fetchedAt >= item.updatedAt else {
        active.append((key, item))
        continue
      }
      if target.wantsConversation {
        behind.append((key, item))
        continue
      }
      let finished = (target.snapshot?.state ?? item.state).map {
        spec(for: item.provider).isFinished(state: $0)
      } ?? false
      if !finished, now.timeIntervalSince(fetchedAt) >= openTargetRefreshInterval {
        stale.append((key, item, fetchedAt))
      }
    }
    active.sort { $0.item.updatedAt > $1.item.updatedAt }
    behind.sort { $0.item.updatedAt > $1.item.updatedAt }
    stale.sort { $0.fetchedAt < $1.fetchedAt }

    let talking = active + behind
    await refresh(talking + stale.map { ($0.key, $0.item) }, conversations: Set(talking.map(\.key)), at: now)
  }

  /// Fetches one target's conversation now, ahead of the rounds — for a
  /// preview opened before they reached it. Returns why it didn't come,
  /// if it didn't; the rounds go on asking either way.
  func refreshConversation(_ key: String) async -> String? {
    guard !isDemo, let item = newestItemsByTarget()[key] else {
      return nil
    }
    let failure = await refresh([(key, item)], conversations: [key], at: Date())
    guard let target = store.targets()[key], target.conversationAt == nil, target.unreadable == nil else {
      return nil
    }
    return failure ?? "The conversation didn't come through just now."
  }

  /// A target's stored conversation, for the preview. One gone from disk
  /// is forgotten, so the rounds fetch it again.
  func conversation(for key: String) -> TargetConversation? {
    if let conversation = store.conversation(for: key) {
      return conversation
    }
    if store.forgetConversation(key) {
      emitState()
    }
    return nil
  }

  /// Each target's newest notification, by key.
  private func newestItemsByTarget() -> [String: InboxItem] {
    var newest: [String: InboxItem] = [:]
    for item in store.inboxItems() {
      guard let key = spec(for: item.provider).boardKey(for: item) else {
        continue
      }
      if let held = newest[key], held.updatedAt >= item.updatedAt {
        continue
      }
      newest[key] = item
    }
    return newest
  }

  /// Asks after `due` in order, each target through the account of its
  /// newest notification and as many as that account's client affords —
  /// the rest wait — with the conversations of those in `conversations`,
  /// and records what came back. Returns why an account's round failed
  /// outright, if one did.
  @discardableResult
  private func refresh(
    _ due: [(key: String, item: InboxItem)], conversations: Set<String>, at date: Date
  ) async -> String? {
    var batches: [AccountId: [String]] = [:]
    var providers: [String: ProviderId] = [:]
    for (key, item) in due {
      guard let client = clients[item.provider],
            batches[item.accountId, default: []].count < client.targetBatchLimit else {
        continue
      }
      batches[item.accountId, default: []].append(key)
      providers[key] = item.provider
    }

    let rounds = await withTaskGroup(of: Result<TargetRound, any Error>.self) { group in
      for (accountId, keys) in batches {
        guard let account = store.getAccount(accountId), let config = account.config,
              let client = clients[account.provider] else {
          continue
        }
        let wanted = conversations.intersection(keys)
        group.addTask {
          do {
            return .success(try await client.fetchTargets(config, keys: keys, conversations: wanted))
          } catch {
            return .failure(error)
          }
        }
      }
      var collected: [Result<TargetRound, any Error>] = []
      for await round in group {
        collected.append(round)
      }
      return collected
    }

    var answer = TargetRound()
    var failure: String?
    for round in rounds {
      switch round {
      case .success(let round):
        answer.refreshed.merge(round.refreshed) { $1 }
        answer.unreadable.merge(round.unreadable) { $1 }
      case .failure(let error):
        failure = failure ?? errorMessage(error)
      }
    }
    store.applyTargetRefresh(answer, providers: providers, at: date)
    if !answer.refreshed.isEmpty || !answer.unreadable.isEmpty {
      emitState()
    }
    return failure
  }

  func syncNow(depth: FetchDepth) async {
    if let inFlight {
      await inFlight.value
      return
    }
    let task = Task {
      await self.doSync(depth: depth)
    }
    inFlight = task
    await task.value
    inFlight = nil
  }

  /// What the timer owes: .full once fullSyncInterval has elapsed (or never
  /// ran), .recent otherwise.
  private func dueDepth() -> FetchDepth {
    guard let lastFullSyncAt else {
      return .full
    }
    return Date().timeIntervalSince(lastFullSyncAt) >= fullSyncInterval ? .full : .recent
  }

  /// Validates and stores an account (any number per provider). Returns
  /// nil on success, or the human-readable failure. The same user on the
  /// same instance is the same account: connecting one already connected
  /// swaps in the new token, and connecting one removed earlier revives its
  /// record — items and read state included — instead of starting a
  /// duplicate.
  func connectAccount(_ provider: ProviderId, config: AccountConfig) async -> String? {
    guard let client = clients[provider] else {
      return "Unknown provider."
    }
    do {
      let profile = try await client.validate(config)
      let identity = AccountIdentity(provider: provider, baseUrl: config.baseUrl, username: profile.username)
      let id = store.findAccount(identity) ?? UUID().uuidString
      store.setAccount(id, provider: provider, config: config, profile: profile)
      store.clearUnreadableTargets()
      errors[id] = nil
      emitState()
      // Deep from the start: a new account seeds its whole backlog (and
      // silently — see doSync's seeding rule); a revived one catches up on
      // whatever arrived while it was away.
      Task {
        await self.syncNow(depth: .full)
      }
      return nil
    } catch {
      return errorMessage(error)
    }
  }

  /// Swaps a connected account's token — the remedy for one that expired
  /// or was revoked. The new token must belong to the same user; the
  /// account's id, items, and read state are untouched. Returns nil on
  /// success, or the human-readable failure.
  func updateToken(_ id: AccountId, token: String) async -> String? {
    guard let account = store.getAccount(id), let client = clients[account.provider] else {
      return "That account is no longer connected."
    }
    let config = AccountConfig(token: token, baseUrl: account.baseUrl)
    do {
      let profile = try await client.validate(config)
      let stored = account.username.map {
        AccountIdentity(provider: account.provider, baseUrl: account.baseUrl, username: $0)
      }
      let offered = AccountIdentity(provider: account.provider, baseUrl: account.baseUrl, username: profile.username)
      if let stored, stored != offered {
        return "That token belongs to @\(profile.username), not @\(account.username ?? "")."
      }
      store.setAccount(id, provider: account.provider, config: config, profile: profile)
      store.clearUnreadableTargets()
      errors[id] = nil
      emitState()
      // A dead token may have kept this account from syncing for days:
      // catch up everywhere, not just the recent pages.
      Task {
        await self.syncNow(depth: .full)
      }
      return nil
    } catch {
      return errorMessage(error)
    }
  }

  /// Removes an account from the app: the token is forgotten now; the
  /// record and its items park in the store (see Store.removeAccount) in
  /// case the same account is added back.
  func disconnectAccount(_ id: AccountId) {
    store.removeAccount(id)
    errors[id] = nil
    emitState()
  }

  /// Opens the item in the browser and marks it read.
  func openItem(id: String) async {
    await openThread(ids: [id])
  }

  /// Opens the first item in the browser and marks the whole set read — a
  /// thread's members are one target, so opening it handles all of them.
  func openThread(ids: [String]) async {
    guard let first = ids.first,
          let item = store.getItems().first(where: { $0.id == first }) else {
      return
    }
    if let url = URL(string: item.url) {
      await MainActor.run {
        _ = NSWorkspaceOpener.open(url)
      }
    }
    store.markRead(ids)
    emitState()
  }

  func markRead(ids: [String]) {
    store.markRead(ids)
    emitState()
  }

  func markAllRead() {
    store.markAllRead()
    emitState()
  }

  /// Kicks off the first sync and the 60s interval.
  func start() {
    guard timer == nil else { return }
    timer = Task {
      // The stored state first — profile refresh and sync both hit the
      // network, and the UI must not sit empty while they run. Rules run
      // over it before it ships, so folders are right from the first frame
      // (and the fixtures never need hand-computed assignments).
      self.sweepLabels()
      self.reconcileSidebar()
      self.emitState()
      // Summarizing is local work on text already in the store, so it runs
      // before the first fetch — and in demo mode, which never fetches.
      Task {
        await self.sweepSummaries()
      }
      Task {
        await self.sweepVerdicts()
      }
      // Demo mode is fixtures only: never touch the network.
      guard !isDemo else { return }
      await self.refreshProfiles()
      // The first sync is always deep (dueDepth: no full pass yet), then
      // hourly deep passes ride the 60s timer.
      await self.syncNow(depth: self.dueDepth())
      while !Task.isCancelled {
        try? await Task.sleep(for: syncInterval)
        await self.syncNow(depth: self.dueDepth())
      }
    }
  }

  /// Re-reads each account's profile once per launch, backfilling names and
  /// avatars for accounts stored before those existed (and keeping them
  /// fresh after). Failures leave the stored profile untouched.
  private func refreshProfiles() async {
    var changed = false
    for account in store.accounts() {
      guard let client = clients[account.provider], let config = account.config,
            let profile = try? await client.validate(config) else {
        continue
      }
      store.updateProfile(account.id, profile: profile)
      changed = true
    }
    if changed {
      emitState()
    }
  }

  // MARK: Images

  /// An image a preview's body shows, fetched through the account the
  /// previewed item came through — its client decides what, if anything,
  /// the account's token may unlock — or anonymously once that account is
  /// gone. `page` is the item's url. nil when the image can't be had; demo
  /// mode serves its fixtures' own and never touches the network.
  func image(_ url: URL, account: AccountId, page: String) async -> Data? {
    if isDemo {
      return DemoData.image(url)
    }
    guard let stored = store.getAccount(account), let config = stored.config,
          let client = clients[stored.provider] else {
      return try? await fetchPublicImage(url)
    }
    return try? await client.fetchImage(config, url: url, page: page)
  }
}

private func errorMessage(_ error: Error) -> String {
  if let provider = error as? ProviderError {
    return provider.message
  }
  return error.localizedDescription
}

// AppKit is only touched here, isolated so the engine stays testable.
@MainActor
private enum NSWorkspaceOpener {
  static func open(_ url: URL) -> Bool {
    NSWorkspace.shared.open(url)
  }
}
