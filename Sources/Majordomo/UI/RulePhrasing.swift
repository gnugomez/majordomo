// Rules in words. The settings page, the composer's confirmation, and a
// suggestion card all describe the same conditions, so the wording lives
// here once: a field's name, a test read as a sentence fragment, and a
// whole set of conditions joined by the rule's own conjunction.

import Foundation

/// Operator and negation as one choice, worded the way a condition row
/// reads: "is", "is not", "doesn't contain".
struct ConditionTest: Hashable {
  let op: RuleOperator
  let negated: Bool

  func label(mention: Bool) -> String {
    if mention {
      return negated ? "is not a mention" : "is a mention"
    }
    switch (op, negated) {
    case (.is, false): return "is"
    case (.is, true): return "is not"
    case (.contains, false): return "contains"
    case (.contains, true): return "doesn't contain"
    case (.matches, false): return "matches"
    case (.matches, true): return "doesn't match"
    }
  }
}

/// The field's name as the UI says it.
func fieldLabel(_ field: RuleField) -> String {
  switch field {
  case .repo: "Repository"
  case .title: "Title"
  case .body: "Body"
  case .author: "Author"
  case .kind: "Kind"
  case .reason: "Reason"
  case .state: "State"
  case .provider: "Provider"
  case .account: "Account"
  case .upstreamLabel: "Upstream label"
  case .mention: "Mention"
  }
}

/// One condition as a fragment: "Repository is acme/infra".
func describe(_ condition: RuleCondition) -> String {
  let test = ConditionTest(op: condition.op, negated: condition.negated)
    .label(mention: condition.field == .mention)
  return condition.field == .mention
    ? "\(fieldLabel(condition.field)) \(test)"
    : "\(fieldLabel(condition.field)) \(test) \(condition.value)"
}

/// A rule's conditions as one sentence, joined by what the rule asks for —
/// "and" when every condition must hold, "or" when any will do.
func describeConditions(_ conditions: [RuleCondition], match: RuleMatch) -> String {
  conditions.map(describe).joined(separator: match == .any ? " or " : " and ")
}

/// The same for a whole rule.
func describe(_ rule: LabelRule) -> String {
  describeConditions(rule.conditions, match: rule.match)
}
