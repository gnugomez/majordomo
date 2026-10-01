// Assigns labels from the user's rules. Pure functions over an item and the
// rule set — no state, no I/O — run by the sync engine after every upsert
// and whenever the labels or rules change. An intelligence rule is no
// different here: the model's answer is already on the item, cached by the
// store, and this only reads it.

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
    assign(items, rules: rules, labels: labels, everyInbox: []).mapValues(\.labels)
  }

  /// What one item gets from the rules: the labels assigned to it, and
  /// the inboxes it is kept out of because a rule moved it.
  struct Assignment: Hashable, Sendable {
    var labels: Set<LabelId> = []
    var hiddenFrom: Set<LabelId> = []
  }

  /// Runs every enabled rule over a batch. `everyInbox` is what "hide
  /// from everywhere" resolves against — every inbox in the sidebar,
  /// catch-all included; pass it empty when only labels matter.
  static func assign(
    _ items: [InboxItem], rules: [LabelRule], labels: [InboxLabel], everyInbox: [LabelId]
  ) -> [String: Assignment] {
    let existing = Set(labels.map(\.id))
    let enabled = rules.filter(\.enabled)
    let compiled = enabled.map(CompiledRule.init)
    // Resolved once per sweep rather than per item.
    let hidden = enabled.map { $0.hidden(among: everyInbox) }
    var assigned: [String: Assignment] = [:]
    for item in items {
      var result = Assignment()
      for (index, rule) in compiled.enumerated() where rule.matches(item) {
        result.labels.formUnion(rule.labelIds)
        result.hiddenFrom.formUnion(hidden[index])
      }
      result.labels.formIntersection(existing)
      // An inbox this item actually lands in always shows it, whatever
      // another rule wanted to hide.
      result.hiddenFrom.subtract(result.labels)
      assigned[item.id] = result
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

/// A conditions rule holds when its conditions hold — every one, or any
/// one with `match: .any`. An intelligence rule holds when the model
/// answered yes to its question. Either way an empty rule matches nothing:
/// no conditions, or no question, is a draft, not a catch-all.
private struct CompiledRule {
  let id: String
  let labelIds: [LabelId]
  let judge: RuleJudge
  let asksAnything: Bool
  let match: RuleMatch
  let conditions: [CompiledCondition]

  init(_ rule: LabelRule) {
    id = rule.id
    labelIds = rule.labelIds
    judge = rule.judge
    asksAnything = rule.question != nil
    match = rule.match
    conditions = rule.conditions.map(CompiledCondition.init)
  }

  func matches(_ item: InboxItem) -> Bool {
    switch judge {
    case .intelligence:
      // An item the model hasn't been asked about yet carries no answer,
      // and no answer is not a match.
      return asksAnything && item.verdicts[id] == true
    case .conditions:
      guard !conditions.isEmpty else {
        return false
      }
      switch match {
      case .all: return conditions.allSatisfy { $0.holds(for: item) }
      case .any: return conditions.contains { $0.holds(for: item) }
      }
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
