// What depends on what. Every mutation the engine makes records what it
// touched as an EngineChange and nothing more; `SyncEngine.settle` looks
// the turn's changes up here — which sweeps run, which background passes
// start, which slices of the state go out — and does it once for all of
// them. A new kind of change, or a new follow-up, is an entry here, not a
// call threaded through every mutation that might need it.

/// What a mutation touched.
enum EngineChange: Hashable, Sendable, CaseIterable {
  /// The stored state, first thing at launch: everything is new to the
  /// readers.
  case launch
  /// What label rules read about items: a fetch's new items and new text
  /// on known ones, or an account's items rejoining the live set.
  case itemContent
  /// New items a sync brought from an account that already had some —
  /// the ones a banner may be worth.
  case arrivals
  case readState
  /// Items put away or brought back (Snooze).
  case snoozes
  /// The user's hand on an item's label.
  case labelOverrides
  case summaries
  /// The model's answers about items, which label rules read.
  case itemVerdicts
  /// The model's answers about targets, which board columns read.
  case targetVerdicts
  /// The user's labels; a deleted one leaves every item and rule.
  case labels
  case rules
  case sidebar
  case boards
  case pins
  /// What is known about the targets: snapshots, conversations, seen
  /// marks, and which targets are tracked at all.
  case targets
  /// Accounts connected, revived, re-tokened, renamed, removed, or
  /// failing.
  case accounts
  case suggestions
  /// A sync started or finished.
  case syncStatus
  /// A sync pass finished, whatever it brought.
  case synced
  /// The on-device model switched on as a whole.
  case intelligenceOn
  /// The row summaries switched on.
  case summariesOn
}

/// What follows a change, besides publishing what it moved.
struct Reactions: OptionSet, Sendable {
  let rawValue: Int

  /// Run every label rule over the live items.
  static let relabel = Reactions(rawValue: 1 << 0)
  /// Build the cards and place them on every board, and note the questions
  /// worth putting to the model.
  static let place = Reactions(rawValue: 1 << 1)
  /// Store the sidebar layout reconciled with the labels that exist.
  static let reconcileSidebar = Reactions(rawValue: 1 << 2)
  /// Let go of the answers to questions nothing asks any more, and of the
  /// questions the model refused this run: the asking changed.
  static let forgetAnswers = Reactions(rawValue: 1 << 3)
  /// Tell the subscribers which fresh threads arrived (labeled first, so a
  /// label's banner policy can speak).
  static let announce = Reactions(rawValue: 1 << 4)
  /// Drop what removed accounts left behind past their retention.
  static let prune = Reactions(rawValue: 1 << 5)
  /// A round of target refreshes for the boards and previews.
  static let refreshTargets = Reactions(rawValue: 1 << 6)
  /// A summary pass of the model.
  static let summarize = Reactions(rawValue: 1 << 7)
  /// A verdict pass of the model, over the questions the sweep found.
  static let askQuestions = Reactions(rawValue: 1 << 8)
  /// A suggestion pass of the model, when one is due.
  static let lookForPatterns = Reactions(rawValue: 1 << 9)
}

extension EngineChange {
  /// The reaction table. A sweep runs at most once per settle: `relabel`
  /// for what label rules read, `place` alone for what only the boards
  /// read, so a click on a card waits on the cards alone.
  var reactions: Reactions {
    switch self {
    case .launch:
      [.relabel, .place, .reconcileSidebar, .summarize, .askQuestions]
    case .itemContent, .itemVerdicts:
      [.relabel, .place]
    case .arrivals:
      [.announce]
    case .readState, .labelOverrides, .summaries, .targetVerdicts, .pins, .targets, .accounts:
      [.place]
    case .labels:
      [.relabel, .place, .reconcileSidebar]
    case .rules:
      // A reworded question is a new one: the answers to the old wording
      // go, the labels they fed empty, and the model hears the new one.
      [.relabel, .place, .forgetAnswers, .askQuestions]
    case .boards:
      [.place, .forgetAnswers, .askQuestions]
    case .sidebar, .suggestions, .syncStatus, .snoozes:
      []
    case .synced:
      // Placement reads the clock (a board's Done and Other windows), so
      // every pass places again. Then the boards and previews catch up,
      // and the model on what the sync brought — summaries first: they are
      // what the rows are missing right now, while patterns build over
      // days.
      [.place, .prune, .refreshTargets, .summarize, .askQuestions, .lookForPatterns]
    case .intelligenceOn:
      [.summarize, .askQuestions]
    case .summariesOn:
      [.summarize]
    }
  }

  /// The slices the change itself can move. A sweep adds what it moved:
  /// the placements whenever it runs, the items when it relabels.
  var slices: Set<StateSlice> {
    switch self {
    case .launch:
      Set(StateSlice.allCases)
    case .itemContent, .readState, .snoozes, .labelOverrides, .summaries, .itemVerdicts:
      [.items]
    case .arrivals, .targetVerdicts, .synced, .intelligenceOn, .summariesOn:
      []
    case .labels:
      // A deleted label is scrubbed from every item and rule.
      [.labels, .rules, .items, .sidebar]
    case .rules:
      [.rules]
    case .sidebar:
      [.sidebar]
    case .boards, .pins:
      [.boards]
    case .targets:
      // Targets that go take their cards' pins with them.
      [.targets, .boards]
    case .accounts:
      // The live items are the connected accounts'.
      [.accounts, .items]
    case .suggestions:
      [.suggestions]
    case .syncStatus:
      [.status]
    }
  }

  /// The slices the app model changes ahead of the engine — an edit
  /// applies there at once, then reaches here. A change to them always
  /// moves their revision, even to a value equal to the last one
  /// published, so the model takes the engine's word over its own guess
  /// (a layout reconciled back, a pin that moved nothing).
  var echoes: Set<StateSlice> {
    switch self {
    case .launch:
      Set(StateSlice.allCases)
    case .labels:
      [.labels]
    case .rules:
      [.rules]
    case .sidebar:
      [.sidebar]
    case .boards:
      [.boards]
    case .pins:
      [.boards, .placements]
    case .syncStatus:
      [.status]
    default:
      []
    }
  }
}

extension Set<EngineChange> {
  var reactions: Reactions {
    reduce(into: Reactions()) { $0.formUnion($1.reactions) }
  }

  var slices: Set<StateSlice> {
    reduce(into: Set<StateSlice>()) { $0.formUnion($1.slices) }
  }

  var echoes: Set<StateSlice> {
    reduce(into: Set<StateSlice>()) { $0.formUnion($1.echoes) }
  }
}
