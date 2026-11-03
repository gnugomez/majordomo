// Where one board's cards go, as the sync engine's sweep placed them (see
// BoardEngine) — published with the state, so the views only narrow it by
// the search and the pills.

import Foundation

struct BoardPlacement: Sendable {
  /// Each column's cards, by column id.
  var columns: [String: [BoardCard]] = [:]
  /// Open cards no column took.
  var other: [BoardCard] = []
  /// Finished cards, while they are recent.
  var done: [BoardCard] = []
  /// The cards sitting where the user put them.
  var pinned: Set<String> = []
  /// Every placed card by id, for lookups that shouldn't walk the board.
  private(set) var byId: [String: BoardCard] = [:]
  /// Placed cards carrying unread notifications.
  private(set) var unread = 0

  var count: Int {
    byId.count
  }

  /// Every placed card, columns first.
  var allCards: [BoardCard] {
    columns.values.flatMap { $0 } + other + done
  }

  /// Notes a card the lists now hold, for the lookups and the count.
  mutating func record(_ card: BoardCard) {
    byId[card.id] = card
    if card.unread {
      unread += 1
    }
  }

  /// The same placement holding only the cards `keep` lets through, each
  /// list in its order.
  func narrowed(to keep: Set<String>) -> BoardPlacement {
    var narrowed = BoardPlacement()
    func kept(_ cards: [BoardCard]) -> [BoardCard] {
      let survivors = cards.filter { keep.contains($0.id) }
      survivors.forEach { narrowed.record($0) }
      return survivors
    }
    narrowed.columns = columns.mapValues(kept)
    narrowed.other = kept(other)
    narrowed.done = kept(done)
    narrowed.pinned = pinned.intersection(keep)
    return narrowed
  }

  /// The placement with one card moved into a column by hand, ahead of the
  /// sweep that confirms it.
  func pinning(_ card: BoardCard, to column: String) -> BoardPlacement {
    var moved = BoardPlacement()
    func without(_ cards: [BoardCard]) -> [BoardCard] {
      let rest = cards.filter { $0.id != card.id }
      rest.forEach { moved.record($0) }
      return rest
    }
    moved.columns = columns.mapValues(without)
    moved.other = without(other)
    moved.done = without(done)
    // In activity order, newest first, where the sweep will put it too.
    var cards = moved.columns[column] ?? []
    cards.insert(card, at: cards.firstIndex { $0.activityAt < card.activityAt } ?? cards.endIndex)
    moved.columns[column] = cards
    moved.record(card)
    moved.pinned = pinned.union([card.id])
    return moved
  }
}

extension BoardPlacement: Equatable {
  /// The lists decide; the lookups and the count follow from them.
  static func == (lhs: BoardPlacement, rhs: BoardPlacement) -> Bool {
    lhs.columns == rhs.columns && lhs.other == rhs.other && lhs.done == rhs.done && lhs.pinned == rhs.pinned
  }
}
