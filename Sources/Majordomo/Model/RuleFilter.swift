// Filters: what a label rule, a board's scope, and a board's columns test.
// A filter is groups of conditions: each group holds when all — or any — of
// its conditions do, and the filter holds when any — or all — of its groups
// do, so "(repo is acme/* and reason is mentioned) or author is kim" is one
// filter of two groups. A condition can be a question the on-device model
// answers in the user's own words, which makes an Apple Intelligence check
// one more condition to combine with the cheap ones. Foundation only.

import Foundation

/// Conditions that hold together: every one, or any one with `match: .any`.
/// No conditions holds for nothing — an empty group is a draft, not a
/// catch-all.
struct RuleGroup: Codable, Hashable, Sendable {
  var match: RuleMatch = .all
  var conditions: [RuleCondition] = []
}

/// Groups joined by `match`. With the default `.any` each group is one way
/// for a subject to get in; `.all` asks every group to hold at once. No
/// groups holds for nothing, except where an empty filter is defined to
/// take everything (a board's scope).
struct RuleFilter: Hashable, Sendable {
  var match: RuleMatch = .any
  var groups: [RuleGroup] = []
}

extension RuleFilter {
  /// A filter of one group, or of none when there are no conditions.
  init(conditions: [RuleCondition], match: RuleMatch = .all) {
    self.init(groups: conditions.isEmpty ? [] : [RuleGroup(match: match, conditions: conditions)])
  }

  /// True when no group holds a single condition.
  var isEmpty: Bool {
    groups.allSatisfy(\.conditions.isEmpty)
  }

  /// Every condition, group by group.
  var conditions: [RuleCondition] {
    groups.flatMap(\.conditions)
  }

  /// Whether any condition puts a question to the on-device model.
  var asksModel: Bool {
    conditions.contains { $0.question != nil }
  }
}

extension RuleFilter: Codable {
  private enum CodingKeys: String, CodingKey {
    case match, groups
  }

  /// A lone group's keys: what a board's scope was stored as before it
  /// could hold several.
  private enum GroupKeys: String, CodingKey {
    case conditions
  }

  /// Reads a filter, or a lone group stored where a filter now goes — one
  /// group of the same conditions, or none when it had no conditions.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.groups) {
      self.init(
        match: try container.decodeIfPresent(RuleMatch.self, forKey: .match) ?? .any,
        groups: try container.decode([RuleGroup].self, forKey: .groups)
      )
      return
    }
    let group = try decoder.container(keyedBy: GroupKeys.self)
    let conditions = try group.decodeIfPresent([RuleCondition].self, forKey: .conditions) ?? []
    let groupMatch = try container.decodeIfPresent(RuleMatch.self, forKey: .match) ?? .all
    self.init(conditions: conditions, match: groupMatch)
  }
}

extension RuleCondition {
  /// An Apple Intelligence check: holds when the model answers yes to the
  /// question — or no, when negated.
  static func question(_ text: String, negated: Bool = false) -> RuleCondition {
    RuleCondition(field: .question, op: .is, value: text, negated: negated)
  }

  /// The question this condition puts to the model, trimmed; nil for any
  /// other condition, and for a question still blank.
  var question: String? {
    guard field == .question else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
