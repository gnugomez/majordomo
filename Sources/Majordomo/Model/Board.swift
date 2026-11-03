// Boards: the user's kanban views over the targets the inbox knows about.
// A column is filled by a filter — the same groups of conditions labels
// use — but where a notification takes every label that matches, a card
// sits in exactly one column: the first, left to right, whose filter holds.
// A card can also be put in a column by hand; that stays local, like every
// label, and lets go once the target's state moves on (closed, merged).
// Finished targets gather in a Done column of their own for a while, and
// whatever no column takes shows under Other.

import Foundation

typealias BoardId = String

struct BoardColumn: Identifiable, Hashable, Sendable {
  var id: String
  var name: String
  /// A card lands here when this holds and no column to the left took it
  /// first. An empty filter makes a column filled by hand only.
  var filter = RuleFilter()
}

extension BoardColumn: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, name, filter
  }

  /// A column stored as a list of ways in, any one of which took a card.
  private enum WaysKeys: String, CodingKey {
    case rules
  }

  /// Reads a column, or one stored as ways in: each way becomes a group,
  /// any one of them holding.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    if container.contains(.filter) {
      filter = try container.decode(RuleFilter.self, forKey: .filter)
    } else {
      let ways = try decoder.container(keyedBy: WaysKeys.self)
      filter = RuleFilter(match: .any, groups: try ways.decodeIfPresent([RuleGroup].self, forKey: .rules) ?? [])
    }
  }
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
  /// pin, and the filters place the card again. A pin made before the
  /// state was known lets go once the target finishes.
  var state: String?
}

struct Board: Identifiable, Codable, Hashable, Sendable {
  var id: BoardId
  var name: String
  var symbol: String
  /// The cards the board takes; an empty filter takes every card.
  var scope = RuleFilter()
  var columns: [BoardColumn]
  var lanes: BoardLanes = .none
  /// Days a finished target stays in Done after its last activity.
  var doneDays = 7
  /// Cards placed by hand, by card id.
  var pins: [String: BoardPin] = [:]
}
