// Builds the boards' cards and places them. Pure functions, run in the
// sync engine's sweep with the filters RuleEngine compiled for it: the
// notifications grouped into one card per target, then each card into the
// first column whose filter holds — unless the user put it somewhere by
// hand, or the target is finished.

import Foundation

/// Cards no column takes show under Other only while this fresh. The
/// inbox keeps every notification for good, and years of watched threads
/// would bury the board.
private let otherWindow: TimeInterval = 30 * 24 * 60 * 60

/// A board with its scope and columns compiled for one sweep.
struct CompiledBoard {
  let board: Board
  let scope: CompiledFilter
  let columns: [(id: String, filter: CompiledFilter)]

  init(_ board: Board) {
    self.board = board
    scope = CompiledFilter(board.scope)
    columns = board.columns.map { ($0.id, CompiledFilter($0.filter)) }
  }

  /// The scope and every column's filter.
  var filters: [CompiledFilter] {
    [scope] + columns.map(\.filter)
  }
}

enum BoardEngine {
  /// One card per target the items point at — only items whose provider
  /// can name a target make one — newest activity first. Each card's
  /// notifications run newest first, `@me` stands for the logins of the
  /// accounts they came through, the model's answers about the target
  /// come from `verdicts`, by target key, and a due day stands against
  /// `now`.
  static func cards(
    items: [InboxItem], targets: [String: TrackedTarget], logins: [AccountId: String],
    verdicts: [String: [String: Bool]] = [:], now: Date = Date()
  ) -> [BoardCard] {
    var grouped: [String: [InboxItem]] = [:]
    for item in items {
      if let key = spec(for: item.provider).boardKey(for: item) {
        grouped[key, default: []].append(item)
      }
    }
    return grouped
      .map { key, members in
        let sorted = members.sorted { $0.updatedAt > $1.updatedAt }
        let own = Set(sorted.compactMap { logins[$0.accountId] })
        return BoardCard(
          id: key, items: sorted, target: targets[key], ownLogins: own.sorted(), verdicts: verdicts[key] ?? [:],
          now: now
        )
      }
      .sorted { $0.activityAt > $1.activityAt }
  }

  /// One board's placement, and the questions about its cards worth
  /// asking, by card id.
  struct Placing {
    var placement = BoardPlacement()
    var open: RuleEngine.OpenQuestions = [:]
  }

  /// Places the cards the board's scope takes. A pin wins while the
  /// target's state is what it was when pinned (one pinned before its
  /// state was known holds until it finishes); a finished target goes to
  /// Done while it is recent and leaves the board after; anything else
  /// takes the first column, left to right, whose filter holds. Questions
  /// are only worth asking about cards in scope, and of the columns only
  /// those tried before one took the card.
  static func place(
    _ cards: [BoardCard], on compiled: CompiledBoard, now: Date, isFinished: (BoardCard) -> Bool
  ) -> Placing {
    let board = compiled.board
    let columnIds = Set(board.columns.map(\.id))
    let doneCutoff = now.addingTimeInterval(-Double(board.doneDays) * 24 * 60 * 60)
    let otherCutoff = now.addingTimeInterval(-otherWindow)
    var placing = Placing()
    func note(_ open: [String], for card: BoardCard) {
      if !open.isEmpty {
        placing.open[card.id, default: []].formUnion(open)
      }
    }
    for card in cards {
      // An empty scope takes everything, where an empty filter matches
      // nothing.
      if !compiled.scope.isEmpty {
        let scope = compiled.scope.evaluate(card)
        note(scope.open, for: card)
        guard scope.holds else {
          continue
        }
      }
      if let pin = board.pins[card.id], columnIds.contains(pin.column), holds(pin, for: card, isFinished: isFinished) {
        placing.placement.columns[pin.column, default: []].append(card)
        placing.placement.pinned.insert(card.id)
      } else if isFinished(card) {
        guard card.activityAt >= doneCutoff else {
          continue
        }
        placing.placement.done.append(card)
      } else if let column = firstColumn(taking: card, on: compiled, noting: note) {
        placing.placement.columns[column, default: []].append(card)
      } else if card.activityAt >= otherCutoff {
        placing.placement.other.append(card)
      } else {
        continue
      }
      placing.placement.record(card)
    }
    return placing
  }

  /// The same for a board compiled on the spot — for tests and one-offs.
  static func place(
    _ cards: [BoardCard], on board: Board, now: Date, isFinished: (BoardCard) -> Bool
  ) -> Placing {
    place(cards, on: CompiledBoard(board), now: now, isFinished: isFinished)
  }

  /// The first column, left to right, whose filter holds for the card.
  private static func firstColumn(
    taking card: BoardCard, on compiled: CompiledBoard, noting note: ([String], BoardCard) -> Void
  ) -> String? {
    for column in compiled.columns {
      let outcome = column.filter.evaluate(card)
      note(outcome.open, card)
      if outcome.holds {
        return column.id
      }
    }
    return nil
  }

  private static func holds(_ pin: BoardPin, for card: BoardCard, isFinished: (BoardCard) -> Bool) -> Bool {
    guard let pinned = pin.state else {
      return !isFinished(card)
    }
    return pinned == card.state
  }

  /// Whether a provider counts the card's target as finished.
  static func isFinished(_ card: BoardCard) -> Bool {
    card.state.map { spec(for: card.lead.provider).isFinished(state: $0) } ?? false
  }
}
