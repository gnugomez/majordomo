// Assigns labels from the user's logical rules. Pure functions over an item
// and the rule set — no state, no I/O — run by the sync engine after every
// upsert and whenever the labels or rules change.

import Foundation

enum LabelEngine {
  /// The labels every enabled, matching rule contributes to one item,
  /// restricted to labels that exist.
  static func autoLabels(for item: InboxItem, rules: [LabelRule], labels: [InboxLabel]) -> Set<LabelId> {
    autoLabels(for: [item], rules: rules, labels: labels)[item.id] ?? []
  }

  /// The same for a batch, keyed by item id; each rule's patterns compile
  /// once for the whole batch.
  static func autoLabels(
    for items: [InboxItem], rules: [LabelRule], labels: [InboxLabel]
  ) -> [String: Set<LabelId>] {
    let existing = Set(labels.map(\.id))
    let compiled = rules.filter(\.enabled).map(CompiledRule.init)
    var assigned: [String: Set<LabelId>] = [:]
    for item in items {
      var labels = Set<LabelId>()
      for rule in compiled where rule.matches(item) {
        labels.formUnion(rule.labelIds)
      }
      assigned[item.id] = labels.intersection(existing)
    }
    return assigned
  }

  /// One condition against one item — for previews and tests; the batch
  /// path above compiles patterns once instead.
  static func holds(_ condition: RuleCondition, for item: InboxItem) -> Bool {
    CompiledCondition(condition).holds(for: item)
  }

  /// One rule against one item, whatever its enabled state — the settings
  /// preview uses it to show what a rule would label.
  static func matches(_ rule: LabelRule, _ item: InboxItem) -> Bool {
    CompiledRule(rule).matches(item)
  }
}

/// A rule holds when its conditions hold — every one, or any one with
/// `match: .any`. A rule with no conditions matches nothing either way: an
/// empty rule is a draft, not a catch-all.
private struct CompiledRule {
  let labelIds: [LabelId]
  let match: RuleMatch
  let conditions: [CompiledCondition]

  init(_ rule: LabelRule) {
    labelIds = rule.labelIds
    match = rule.match
    conditions = rule.conditions.map(CompiledCondition.init)
  }

  func matches(_ item: InboxItem) -> Bool {
    guard !conditions.isEmpty else {
      return false
    }
    switch match {
    case .all: return conditions.allSatisfy { $0.holds(for: item) }
    case .any: return conditions.contains { $0.holds(for: item) }
    }
  }
}

/// One condition with its pattern prepared: a `*` glob (repo only) and a
/// `matches` regex compile to NSRegularExpression up front; an invalid
/// pattern compiles to nothing and never holds.
private struct CompiledCondition {
  let condition: RuleCondition
  let regex: NSRegularExpression?

  init(_ condition: RuleCondition) {
    self.condition = condition
    let pattern = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
    switch condition.op {
    case .matches:
      regex = pattern.isEmpty ? nil : try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    case .is where condition.field == .repo && pattern.contains("*"):
      // Anchored glob: every literal run escaped, each `*` a wildcard.
      let escaped = pattern.split(separator: "*", omittingEmptySubsequences: false)
        .map { NSRegularExpression.escapedPattern(for: String($0)) }
        .joined(separator: ".*")
      regex = try? NSRegularExpression(pattern: "^\(escaped)$", options: [.caseInsensitive])
    default:
      regex = nil
    }
  }

  /// `mention` ignores operator and value; `upstreamLabel` holds when any
  /// upstream label satisfies the test; `negated` inverts the outcome.
  func holds(for item: InboxItem) -> Bool {
    let outcome: Bool
    switch condition.field {
    case .mention:
      outcome = item.isMention
    case .upstreamLabel:
      outcome = item.upstreamLabels.contains { test($0) }
    case .repo:
      outcome = test(item.repo)
    case .title:
      outcome = test(item.title)
    case .body:
      outcome = test(item.body ?? "")
    case .author:
      outcome = test(item.author ?? "")
    case .kind:
      outcome = test(item.kind)
    case .reason:
      outcome = test(item.reason)
    case .state:
      outcome = test(item.state ?? "")
    case .provider:
      outcome = test(item.provider.rawValue)
    case .account:
      outcome = test(item.accountId)
    }
    return condition.negated ? !outcome : outcome
  }

  private func test(_ value: String) -> Bool {
    let pattern = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
    switch condition.op {
    // An empty value is an unset condition, never a match: `contains ""`
    // would hold for everything and `is ""` for every item missing the
    // field.
    case .is:
      if let regex {
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
      }
      return !pattern.isEmpty && value.caseInsensitiveCompare(pattern) == .orderedSame
    case .contains:
      return !pattern.isEmpty
        && value.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    case .matches:
      guard let regex else {
        return false
      }
      return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
  }
}
