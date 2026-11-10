// The one sweep over everything a filter reads — the items' labels and
// every board's placement, from one compiled set — and the edits that set
// it off: labels, rules, the sidebar, boards, and pins.

import Foundation

/// What the last sweep worked out: each board's placement, published with
/// the state, and for the verdict pass the cards it built and the
/// questions worth asking.
struct SweepResult {
  /// Each board's placement, by board id.
  var placements: [BoardId: BoardPlacement] = [:]
  /// The cards, by target key — for the questions about them.
  var cards: [String: BoardCard] = [:]
  /// The questions worth asking, by item id and by target key, and each
  /// question's wording by key.
  var openItemQuestions: RuleEngine.OpenQuestions = [:]
  var openTargetQuestions: RuleEngine.OpenQuestions = [:]
  var questionTexts: [String: String] = [:]
}

extension SyncEngine {
  /// Everything that exists right now: the providers' built-ins plus the
  /// user's, read fresh from the store so a rule or label edit is in it.
  func catalog() -> LabelCatalog {
    .current(user: store.labels(), userRules: store.rules())
  }

  /// Runs every rule and every board over what the store holds now, from
  /// one compiled set: the live items' labels first — the providers'
  /// built-in rules alongside the user's, and only the sets that changed
  /// stored — then the cards, built from the items as labeled, and where
  /// each board places them; along the way, the questions worth putting to
  /// the model. Parked accounts' items are not live and stay as they were.
  /// True when any item's labels moved.
  ///
  /// `relabel: false` leaves the labels as the last sweep left them, for a
  /// change no label rule reads (see EngineChange.reactions).
  func sweep(relabel: Bool) -> Bool {
    let catalog = catalog()
    // "Hide from everywhere" means every inbox in the sidebar, the
    // catch-all included — that is what makes a moved item disappear from
    // Recent as well.
    let everyInbox = [catchAllInboxId] + catalog.labels.map(\.id)
    let compiled = RuleEngine.compile(rules: catalog.rules, boards: store.boards(), everyInbox: everyInbox)

    var items = store.inboxItems()
    var moved = false
    if relabel, let labeled = relabeled(items, rules: compiled.rules, existing: catalog.ids) {
      items = labeled
      moved = true
    }
    let now = Date()
    let cards = BoardEngine.cards(
      items: items, targets: store.targets(), logins: accountLogins(), verdicts: store.targetVerdicts(), now: now
    )
    var placements: [BoardId: BoardPlacement] = [:]
    var openTargets: RuleEngine.OpenQuestions = [:]
    for board in compiled.boards {
      let placing = BoardEngine.place(cards, on: board, now: now, isFinished: BoardEngine.isFinished)
      placements[board.board.id] = placing.placement
      openTargets.merge(placing.open) { $0.union($1) }
    }
    swept.placements = placements
    swept.cards = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
    swept.openTargetQuestions = openTargets
    swept.questionTexts = compiled.questions
    return moved
  }

  /// Runs the label rules over the items and stores what changed; hands
  /// back the items as labeled now, or nil when no item's labels moved.
  /// Notes the questions about them worth asking on the way.
  private func relabeled(_ items: [InboxItem], rules: [CompiledRule], existing: Set<LabelId>) -> [InboxItem]? {
    let labeling = RuleEngine.assign(items, rules: rules, existing: existing)
    swept.openItemQuestions = labeling.open
    let updates = store.getItems().compactMap { item -> (id: String, labels: Set<LabelId>, hiddenFrom: Set<LabelId>)? in
      let result = labeling.assignments[item.id] ?? RuleEngine.Assignment()
      if result.labels == item.autoLabels, result.hiddenFrom == item.hiddenFrom {
        return nil
      }
      return (id: item.id, labels: result.labels, hiddenFrom: result.hiddenFrom)
    }
    guard !updates.isEmpty else {
      return nil
    }
    store.applyAutoLabels(updates)
    return store.inboxItems()
  }

  /// Each connected account's login, for `@me` on its cards.
  private func accountLogins() -> [AccountId: String] {
    var logins: [AccountId: String] = [:]
    for account in store.accounts() {
      logins[account.id] = account.username
    }
    return logins
  }

  /// Lets go of the answers to questions no rule or board asks any more,
  /// and of the questions the model refused this run: what is asked has
  /// changed, so they get another chance.
  func forgetAnswers() {
    store.pruneVerdicts(keeping: RuleEngine.questionKeys(rules: store.rules(), boards: store.boards()))
    passes[.verdicts, default: ModelPass()].failures = []
  }

  // MARK: Labels and rules

  /// Replaces the label set: a deleted label leaves every item and rule
  /// (Store.setLabels), and the rest reassign under the new set. The
  /// sidebar picks up new labels and drops deleted ones.
  func setLabels(_ labels: [InboxLabel]) {
    store.setLabels(labels)
    record(.labels)
  }

  /// Replaces the rules; every live item is labeled again under them.
  func setRules(_ rules: [LabelRule]) {
    store.setRules(rules)
    record(.rules)
  }

  // MARK: Sidebar

  /// The sidebar layout in step with what exists: the stored one (or the
  /// standard one on a store that has none), with new labels added and
  /// vanished ones dropped.
  func sidebarLayout() -> SidebarLayout {
    let catalog = catalog()
    let builtins = catalog.builtinLabels.map(\.id)
    let inboxes = catalog.userInboxes.map(\.id)
    let labels = catalog.userLabels.map(\.id)
    let stored = store.sidebarLayout()
      ?? .standard(catchAll: catchAllInboxId, builtins: builtins + inboxes, labels: labels)
    return stored.reconciled(catchAll: catchAllInboxId, builtins: builtins, inboxes: inboxes, labels: labels)
  }

  /// Stores the reconciled layout when it differs from the stored one.
  func reconcileSidebar() {
    store.setSidebarLayout(sidebarLayout())
  }

  /// The user's sidebar edits (Inboxes settings, a label's show-as-inbox
  /// switch): stored as given, reconciled on the way back out.
  func setSidebarLayout(_ layout: SidebarLayout) {
    store.setSidebarLayout(layout)
    record(.sidebar)
  }

  // MARK: Boards

  func setBoards(_ boards: [Board]) {
    store.setBoards(boards)
    record(.boards)
  }

  /// Puts a card in a column by hand, noting the state it is in; nil
  /// hands it back to the filters.
  func setPin(board: BoardId, card: String, column: String?, state: String?) {
    store.setPin(board: board, card: card, pin: column.map { BoardPin(column: $0, state: state) })
    record(.pins)
  }
}
