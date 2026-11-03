// Boards: the user's kanban views over the targets the inbox knows about.
// A column is filled by rules — the same conditions labels use — but where
// a notification takes every label that matches, a card sits in exactly
// one column: the first, left to right, whose rules hold. A card can also
// be put in a column by hand; that stays local, like every label, and lets
// go once the target's state moves on (closed, merged). Finished targets
// gather in a Done column of their own for a while, and whatever no column
// takes shows under Other.

import Foundation

typealias BoardId = String

/// One way into a column: conditions over a card, every one or any one.
struct BoardRule: Codable, Hashable, Sendable {
  var match: RuleMatch = .all
  var conditions: [RuleCondition] = []
}

struct BoardColumn: Identifiable, Codable, Hashable, Sendable {
  var id: String
  var name: String
  /// A card lands here when any of these holds and no column to the left
  /// took it first. None at all makes a column filled by hand only.
  var rules: [BoardRule] = []
}

/// What splits a board into rows.
enum BoardLanes: String, Codable, CaseIterable, Sendable {
  case none
  /// A row per repository.
  case repository
  /// A row per owner: the organization or group the repositories sit in.
  case owner
}

/// A card put in a column by hand, and the target's state at the time.
struct BoardPin: Codable, Hashable, Sendable {
  var column: String
  /// Any other state later — closed, merged, reopened — lets go of the
  /// pin, and the rules place the card again. A pin made before the state
  /// was known lets go once the target finishes.
  var state: String?
}

struct Board: Identifiable, Codable, Hashable, Sendable {
  var id: BoardId
  var name: String
  var symbol: String
  /// The cards the board takes; no conditions takes every card.
  var scope = BoardRule()
  var columns: [BoardColumn]
  var lanes: BoardLanes = .none
  /// Days a finished target stays in Done after its last activity.
  var doneDays = 7
  /// Cards placed by hand, by card id.
  var pins: [String: BoardPin] = [:]
}
