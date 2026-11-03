// Builds a board's cards and places them. Pure functions, like LabelEngine,
// whose compiled conditions they share: the notifications grouped into one
// card per target, then each card into the first column whose rules hold —
// unless the user put it somewhere by hand, or the target is finished.

import Foundation

/// Cards no column takes show under Other only while this fresh. The
/// inbox keeps every notification for good, and years of watched threads
/// would bury the board.
private let otherWindow: TimeInterval = 30 * 24 * 60 * 60

enum BoardEngine {
  /// Where one board's cards go, each list in the order the cards came.
  struct Placement: Sendable {
    /// Each column's cards, by column id.
    var columns: [String: [BoardCard]] = [:]
    /// Open cards no column took.
    var other: [BoardCard] = []
    /// Finished cards, while they are recent.
    var done: [BoardCard] = []
    /// The cards sitting where the user put them.
    var pinned: Set<String> = []
    /// Every placed card by id, for lookups that shouldn't walk the board.
    var byId: [String: BoardCard] = [:]
    /// Placed cards carrying unread notifications.
    var unread = 0

    var count: Int {
      byId.count
    }

    /// Every placed card, columns first.
    var allCards: [BoardCard] {
      columns.values.flatMap { $0 } + other + done
    }

    fileprivate mutating func record(_ card: BoardCard) {
      byId[card.id] = card
      if card.unread {
        unread += 1
      }
    }
  }

  /// One card per target the items point at — only items whose provider
  /// can name a target make one — newest activity first. Each card's
  /// notifications run newest first, and `@me` stands for the logins of
  /// the accounts they came through.
  static func cards(
    items: [InboxItem], targets: [String: TrackedTarget], accounts: [AccountState]
  ) -> [BoardCard] {
    var logins: [AccountId: String] = [:]
    for account in accounts {
      logins[account.id] = account.username
    }
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
        return BoardCard(id: key, items: sorted, target: targets[key], ownLogins: own.sorted())
      }
      .sorted { $0.activityAt > $1.activityAt }
  }

  /// Places the cards the board's scope takes. A pin wins while the
  /// target's state is what it was when pinned (one pinned before its
  /// state was known holds until it finishes); a finished target goes to
  /// Done while it is recent and leaves the board after; anything else
  /// takes the first column, left to right, with a rule that holds.
  static func place(
    _ cards: [BoardCard], on board: Board, now: Date, isFinished: (BoardCard) -> Bool
  ) -> Placement {
    let scope = CompiledBoardRule(board.scope)
    let columns = board.columns.map { column in
      (id: column.id, rules: column.rules.map(CompiledBoardRule.init))
    }
    let columnIds = Set(board.columns.map(\.id))
    let doneCutoff = now.addingTimeInterval(-Double(board.doneDays) * 24 * 60 * 60)
    let otherCutoff = now.addingTimeInterval(-otherWindow)
    var placement = Placement()
    // An empty scope takes everything, where an empty rule matches nothing.
    for card in cards where board.scope.conditions.isEmpty || scope.matches(card) {
      if let pin = board.pins[card.id], columnIds.contains(pin.column), holds(pin, for: card, isFinished: isFinished) {
        placement.columns[pin.column, default: []].append(card)
        placement.pinned.insert(card.id)
      } else if isFinished(card) {
        guard card.activityAt >= doneCutoff else {
          continue
        }
        placement.done.append(card)
      } else if let column = columns.first(where: { $0.rules.contains { $0.matches(card) } }) {
        placement.columns[column.id, default: []].append(card)
      } else if card.activityAt >= otherCutoff {
        placement.other.append(card)
      } else {
        continue
      }
      placement.record(card)
    }
    return placement
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

/// A board rule with its conditions compiled. As with a label rule, no
/// conditions matches nothing: an empty rule is a draft, not a catch-all.
private struct CompiledBoardRule {
  let match: RuleMatch
  let conditions: [CompiledCondition]

  init(_ rule: BoardRule) {
    match = rule.match
    conditions = rule.conditions.map(CompiledCondition.init)
  }

  func matches(_ card: BoardCard) -> Bool {
    guard !conditions.isEmpty else {
      return false
    }
    switch match {
    case .all: return conditions.allSatisfy { $0.holds(for: card) }
    case .any: return conditions.contains { $0.holds(for: card) }
    }
  }
}
