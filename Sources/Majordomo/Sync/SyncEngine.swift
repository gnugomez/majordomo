// The sync engine: owns the store and the provider clients, and is the one
// writer of everything the app knows. An actor, so every mutation is
// serialized. A mutation does its own work and records what it touched
// (EngineChange); `settle`, once per actor turn however many mutations
// that turn gathered, looks the changes up in the reaction table
// (EngineChange.swift) — the sweep to run, the background passes to start —
// and publishes the slices of the state they moved, in one push.
// Subscribers read the pushes and the domain events as streams: `states()`
// for the latest state, `events()` for what happened.
//
// The work is split by concern across the extensions: +Accounts, +Fetch
// (syncing and the banners' arrivals), +Sweep (labels, rules, boards, and
// the sidebar), +Inbox (read state and the user's hand on items),
// +Intelligence (the model's passes and switches), +Composer, +Targets,
// and +Images. Accounts are plural per provider — every stored account
// syncs through its provider's client.

import Foundation

actor SyncEngine {
  let store: Store
  /// One client per provider implementation, shared by its accounts.
  let clients: [ProviderId: any ProviderClient]
  /// Fixtures only (demo mode): nothing ever touches the network.
  let offline: Bool
  /// How long the store holds a change before writing it, gathering what
  /// follows meanwhile into the same write.
  private let saveDelay: Duration

  /// The on-device model, when one can run here; the null provider
  /// otherwise, which simply says so.
  var intelligence: any IntelligenceProvider = NoIntelligence(
    reason: "Apple Intelligence isn't set up on this Mac."
  )

  // Accounts and syncing.

  /// Sync/validation errors per account, each with the exchange behind
  /// it; the rest of an account's state reads straight from the store.
  var errors: [AccountId: AccountTrouble] = [:]
  var lastSyncAt: Date?
  var lastFullSyncAt: Date?
  var syncing = false
  var inFlight: Task<Void, Never>?
  private var timer: Task<Void, Never>?
  private var started = false
  /// Items the last sync brought from accounts that already had some,
  /// waiting for the sweep to label them before they are announced.
  var arrivals: [String] = []

  // The on-device model.

  /// The master switch over every on-device feature.
  var intelligenceEnabled = true
  /// Whether to look for patterns at all; the user's call, pushed from
  /// settings.
  var suggestionsEnabled = true
  /// Whether the model writes the rows' summaries. The app model folds the
  /// row layout into this: with the excerpt line hidden there is nowhere to
  /// show one, and nothing is generated.
  var summariesEnabled = true
  /// Each background job's bookkeeping (see ModelPass).
  var passes: [ModelJob: ModelPass] = [:]
  /// When the last suggestion pass ran, so the next one waits its turn.
  var lastSuggestionSweepAt: Date?

  // Sweeps and targets.

  /// What the last sweep worked out (see SweepResult).
  var swept = SweepResult()
  /// True while a board refresh is out with the providers.
  var refreshingTargets = false

  // Reactions and publishing.

  /// What the mutations since the last settle touched.
  private var pending: Set<EngineChange> = []
  private var settleScheduled = false
  /// The state as last pushed; a push rebuilds only the slices that moved.
  private var published = AppState()
  private var stateSubscribers = Broadcast<AppState>(replaysLatest: true)
  private var eventSubscribers = Broadcast<DomainEvent>(replaysLatest: false)
  private var flushTask: Task<Void, Never>?

  /// The app's engine: the user's store, or the fixtures in demo mode.
  init() {
    if isDemo {
      let fixture = DemoData.storeFile()
      self.init(
        store: Store(fixture: fixture, conversations: DemoData.conversations(in: fixture)),
        clients: SyncEngine.providerClients(),
        offline: true
      )
    } else {
      self.init(store: Store(), clients: SyncEngine.providerClients(), offline: false)
    }
  }

  init(
    store: sending Store,
    clients: [ProviderId: any ProviderClient],
    offline: Bool,
    saveDelay: Duration = .seconds(1)
  ) {
    self.store = store
    self.clients = clients
    self.offline = offline
    self.saveDelay = saveDelay
    store.builtinLabelIds = LabelCatalog.current(user: [], userRules: []).builtinIds
    // The starter label and rule, once per store (see StarterSetup): the
    // feature arrives configured, and stays deleted if the user deletes it.
    store.seed(labels: StarterSetup.labels, rules: StarterSetup.rules)
    store.seedBoards(GitForgeBoards.starters, firstSet: GitForgeBoards.firstSet)
    for account in store.accounts() where account.config == nil {
      errors[account.id] = AccountTrouble(message: "The stored token can't be read — remove and re-add the account.")
    }
  }

  /// One client per registered provider.
  static func providerClients() -> [ProviderId: any ProviderClient] {
    Dictionary(uniqueKeysWithValues: providerSpecs.map { ($0.id, $0.makeClient()) })
  }

  // MARK: Streams

  /// The state as it changes: the latest push at once (when there has been
  /// one), then every push after it. A reader that falls behind skips to
  /// the newest — each push carries every slice whole.
  func states(
    buffering policy: AsyncStream<AppState>.Continuation.BufferingPolicy = .bufferingNewest(1)
  ) -> AsyncStream<AppState> {
    stateSubscribers.subscribe(buffering: policy)
  }

  /// What happens from now on, every event in order.
  func events() -> AsyncStream<DomainEvent> {
    eventSubscribers.subscribe(buffering: .unbounded)
  }

  /// Tells every subscriber.
  func emit(_ event: DomainEvent) {
    eventSubscribers.yield(event)
  }

  /// The state as last pushed.
  func currentState() -> AppState {
    published
  }

  // MARK: Changes

  /// Notes what a mutation touched. What follows is settled once, after
  /// the current actor turn, for every change it gathered.
  func record(_ changes: Set<EngineChange>) {
    pending.formUnion(changes)
    guard !settleScheduled else {
      return
    }
    settleScheduled = true
    Task {
      self.settle()
    }
  }

  func record(_ change: EngineChange) {
    record([change])
  }

  /// Does what the recorded changes call for (EngineChange.reactions), in
  /// an order that lets each step see the last: answers forgotten before
  /// the sweep, the sweep before the announcements (so banners carry the
  /// labels) and before the push, the background passes after it.
  func settle() {
    settleScheduled = false
    guard !pending.isEmpty else {
      return
    }
    let changes = pending
    pending = []
    let reactions = changes.reactions
    var slices = changes.slices

    if reactions.contains(.forgetAnswers) {
      forgetAnswers()
      slices.insert(.items)
    }
    if reactions.contains(.relabel) || reactions.contains(.place) {
      if sweep(relabel: reactions.contains(.relabel)) {
        slices.insert(.items)
      }
      slices.insert(.placements)
    }
    if reactions.contains(.reconcileSidebar) {
      reconcileSidebar()
    }
    if reactions.contains(.announce) {
      announceArrivals()
    }
    if reactions.contains(.prune) {
      store.prune()
    }
    publish(slices, echoing: changes.echoes)
    startBackgroundWork(reactions)
    flushSoon()
  }

  /// The passes that run on their own requests, in the order they matter.
  private func startBackgroundWork(_ reactions: Reactions) {
    if reactions.contains(.refreshTargets) {
      Task {
        await self.refreshTargets()
      }
    }
    if reactions.contains(.summarize) {
      requestPass(.summaries)
    }
    if reactions.contains(.askQuestions) {
      requestPass(.verdicts)
    }
    if reactions.contains(.lookForPatterns), suggestionSweepIsDue() {
      requestPass(.suggestions)
    }
  }

  // MARK: Publishing

  /// Rebuilds the slices that may have moved, moves the revisions of those
  /// that did (and of `echoes`, whatever they hold), and pushes the result.
  /// Every settle pushes, moved or not: a reader that applied an edit of
  /// its own ahead of the engine waits on the push that confirms it.
  private func publish(_ slices: Set<StateSlice>, echoing echoes: Set<StateSlice>) {
    var state = published
    for slice in slices.union(echoes) where rebuild(slice, in: &state) || echoes.contains(slice) {
      state.revisions.bump(slice)
    }
    published = state
    stateSubscribers.yield(state)
  }

  /// Reads one slice afresh into `state`; true when its value changed.
  private func rebuild(_ slice: StateSlice, in state: inout AppState) -> Bool {
    switch slice {
    case .items:
      // Items ship unordered — every list sorts for display via inboxOrder.
      return replace(&state.items, with: store.inboxItems())
    case .accounts:
      return replace(&state.accounts, with: accountStates())
    case .status:
      let syncingMoved = replace(&state.syncing, with: syncing)
      let lastSyncMoved = replace(&state.lastSyncAt, with: lastSyncAt)
      return syncingMoved || lastSyncMoved
    case .labels:
      return replace(&state.labels, with: store.labels())
    case .rules:
      return replace(&state.rules, with: store.rules())
    case .sidebar:
      return replace(&state.sidebar, with: sidebarLayout())
    case .suggestions:
      return replace(&state.suggestions, with: store.suggestions().filter { !$0.dismissed })
    case .boards:
      return replace(&state.boards, with: store.boards())
    case .targets:
      return replace(&state.targets, with: store.targets())
    case .placements:
      return replace(&state.placements, with: swept.placements)
    }
  }

  private func replace<Value: Equatable>(_ value: inout Value, with new: Value) -> Bool {
    guard value != new else {
      return false
    }
    value = new
    return true
  }

  // MARK: Saving

  /// Has the store write what changed a moment from now — at most once a
  /// delay, and within one of the first change — gathering everything
  /// that changes meanwhile into the same write.
  private func flushSoon() {
    guard store.hasUnsavedChanges, flushTask == nil else {
      return
    }
    flushTask = Task {
      try? await Task.sleep(for: saveDelay)
      guard !Task.isCancelled else {
        return
      }
      self.flushTask = nil
      self.store.flush()
    }
  }

  // MARK: Lifecycle

  /// Kicks off the first sync and the 60s interval.
  func start() {
    guard !started else {
      return
    }
    started = true
    // The stored state first — profile refresh and sync both hit the
    // network, and the UI must not sit empty while they run. Rules run
    // over it before it ships, so folders are right from the first frame
    // (and the fixtures never need hand-computed assignments). The model's
    // summaries and answers are local work on text already in the store,
    // so they start with it — in demo mode too, which never fetches.
    record(.launch)
    // Demo mode is fixtures only: never touch the network.
    guard !offline else {
      return
    }
    timer = Task {
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

  /// Stops syncing, settles what is pending, and writes the store out —
  /// for quitting. Returns once it is on disk; the streams end.
  func stop() async {
    timer?.cancel()
    timer = nil
    settle()
    flushTask?.cancel()
    flushTask = nil
    store.flush()
    await store.writer?.drain()
    stateSubscribers.finish()
    eventSubscribers.finish()
  }
}

/// A failure as the UI shows it, verbatim.
func displayMessage(for error: Error) -> String {
  if let provider = error as? ProviderError {
    return provider.message
  }
  return error.localizedDescription
}

/// An error as an account shows it: the message, and the exchange behind
/// it when the provider's client kept one.
func accountTrouble(for error: Error) -> AccountTrouble {
  AccountTrouble(message: displayMessage(for: error), details: (error as? ProviderError)?.details)
}
