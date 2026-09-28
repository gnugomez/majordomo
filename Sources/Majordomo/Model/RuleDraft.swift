// What a model proposes, before the app trusts any of it. A draft is plain
// strings in the app's own vocabulary; `validated(against:)` turns one into
// a real rule or says why it can't. Nothing generated ever reaches the
// store unvalidated: an unknown field, a bad operator, or an uncompilable
// regex is a rejection, not a silently broken rule. Foundation only — the
// model plumbing lives in Sync.

import Foundation

/// One proposed condition, field/operator/value as the model named them.
struct ConditionDraft: Hashable, Sendable {
  var field: String
  var op: String
  var value: String
  var negated: Bool = false
}

/// A proposed rule, and what it should apply to: an existing label or
/// inbox by name, or a new one to create alongside it.
struct RuleDraft: Hashable, Sendable {
  var name: String
  /// "all" or "any"; anything else falls back to all.
  var match: String = "all"
  var conditions: [ConditionDraft] = []
  /// The label or inbox this rule fills, by name.
  var targetName: String = ""
  /// True when no such target exists yet and one should be created.
  var createTarget: Bool = false
  /// For a new target: "label" (a tag) or "inbox" (a sidebar bucket).
  var targetKind: String = "label"
  var targetSymbol: String = "tag"
  var targetTint: String = "blue"
  /// One short sentence for the user, explaining what the rule does.
  var rationale: String = ""
}

/// A draft the app has checked: the rule it becomes, plus the target to
/// create first when there is one.
struct ValidatedRule: Hashable, Sendable {
  var rule: LabelRule
  /// Non-nil when the rule needs a label or inbox that doesn't exist yet;
  /// the caller stores it before the rule.
  var newTarget: InboxLabel?
}

enum RuleDraftError: LocalizedError, Equatable, Sendable {
  case noConditions
  case unknownField(String)
  case unknownOperator(String)
  case emptyValue(String)
  case invalidRegex(String)
  case noTarget

  var errorDescription: String? {
    switch self {
    case .noConditions:
      "That didn't describe anything to match on — try naming a repo, an author, or words in the title."
    case .unknownField(let field):
      "“\(field)” isn't something an item can be matched on."
    case .unknownOperator(let op):
      "“\(op)” isn't a comparison this app can make."
    case .emptyValue(let field):
      "The test on \(field) has nothing to compare against."
    case .invalidRegex(let pattern):
      "“\(pattern)” isn't a valid regular expression."
    case .noTarget:
      "That didn't say which inbox or label to apply."
    }
  }
}

extension RuleDraft {
  /// The draft as a real rule, or the reason it can't be one. Existing
  /// targets are matched by name, case-insensitively; a target the model
  /// asked to create becomes `newTarget`.
  func validated(against labels: [InboxLabel], now: Date = Date()) -> Result<ValidatedRule, RuleDraftError> {
    guard !conditions.isEmpty else {
      return .failure(.noConditions)
    }
    var checked: [RuleCondition] = []
    for draft in conditions {
      switch draft.condition() {
      case .success(let condition):
        checked.append(condition)
      case .failure(let error):
        return .failure(error)
      }
    }

    let wanted = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !wanted.isEmpty else {
      return .failure(.noTarget)
    }
    // An existing target wins over creating a duplicate, whatever the
    // model asked for.
    let existing = labels.first { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
    var newTarget: InboxLabel?
    let targetId: LabelId
    if let existing {
      targetId = existing.id
    } else {
      let kind: LabelKind = targetKind.lowercased() == "inbox" ? .inbox : .label
      let target = InboxLabel(
        id: UUID().uuidString,
        name: wanted,
        symbol: NSSymbolName.known(targetSymbol) ?? (kind == .inbox ? "tray" : "tag"),
        tint: LabelTint(rawValue: targetTint.lowercased()) ?? .blue,
        notify: .follow,
        order: labels.count,
        kind: kind
      )
      newTarget = target
      targetId = target.id
    }

    let rule = LabelRule(
      id: UUID().uuidString,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? wanted : name,
      match: match.lowercased() == "any" ? .any : .all,
      conditions: checked,
      labelIds: [targetId]
    )
    return .success(ValidatedRule(rule: rule, newTarget: newTarget))
  }
}

extension ConditionDraft {
  /// The draft as a real condition, or why it isn't one.
  func condition() -> Result<RuleCondition, RuleDraftError> {
    guard let field = RuleField(rawValue: field.lowercased()) else {
      return .failure(.unknownField(field))
    }
    guard let op = RuleOperator(rawValue: op.lowercased()) else {
      return .failure(.unknownOperator(op))
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    // The mention field is the one test that needs no value.
    if field != .mention {
      guard !trimmed.isEmpty else {
        return .failure(.emptyValue(field.rawValue))
      }
      if op == .matches, (try? NSRegularExpression(pattern: trimmed)) == nil {
        return .failure(.invalidRegex(trimmed))
      }
    }
    return .success(RuleCondition(field: field, op: op, value: trimmed, negated: negated))
  }
}

/// Symbol names a proposal may use. A model can invent an SF Symbol that
/// doesn't exist, and an unknown name draws as a blank square, so only
/// names from this list survive — the icon picker offers the rest.
enum NSSymbolName {
  static let suggestable: [String] = [
    "tag", "tray", "flag", "flame", "bolt", "star", "bell", "clock", "calendar",
    "person", "person.2", "building.2", "globe", "network", "cloud", "server.rack",
    "shippingbox", "wrench", "hammer", "ladybug", "shield", "lock", "key", "doc",
    "folder", "envelope", "bubble", "terminal", "gearshape", "chart.bar", "book",
    "lightbulb", "moon.zzz", "leaf", "cpu", "creditcard", "cart", "heart", "eye",
    "pin", "exclamationmark.triangle", "arrow.triangle.branch", "checkmark.seal",
  ]

  /// The name when it is one the app offers, else nil.
  static func known(_ name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return suggestable.first { $0 == trimmed }
  }
}
