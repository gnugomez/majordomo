// Rules in words. The settings page, the composer's confirmation, and a
// suggestion card all describe the same conditions, so the wording lives
// here once: a field's name, a test read as a sentence fragment, a group
// of conditions joined by its own conjunction, and a filter's groups
// joined by the filter's.

import Foundation

/// Operator and negation as one choice, worded the way a condition row
/// reads: "is", "is not", "doesn't contain".
struct ConditionTest: Hashable {
  let op: RuleOperator
  let negated: Bool

  /// The test as a condition on `field` reads it; a flag field's test
  /// stands for the whole condition.
  func label(for field: RuleField) -> String {
    switch field {
    case .mention:
      return negated ? "is not a mention" : "is a mention"
    case .unread:
      return negated ? "is all read" : "is unread"
    default:
      break
    }
    switch (op, negated) {
    case (.is, false): return "is"
    case (.is, true): return "is not"
    case (.contains, false): return "contains"
    case (.contains, true): return "doesn't contain"
    case (.matches, false): return "matches"
    case (.matches, true): return "doesn't match"
    case (.exists, false): return "is set"
    case (.exists, true): return "is not set"
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
  case .assignee: "Assignee"
  case .reviewer: "Reviewer"
  case .review: "Review"
  case .checks: "Checks"
  case .merge: "Merge"
  case .milestone: "Milestone"
  case .lastCommenter: "Last commenter"
  case .unread: "Activity"
  case .question: "Apple Intelligence"
  }
}

/// One condition as a fragment: "Repository is acme/infra", "Apple
/// Intelligence says yes to “…”". A flag or an "is set" test has no value
/// to name.
func describe(_ condition: RuleCondition) -> String {
  if condition.field == .question {
    let answer = condition.negated ? "no" : "yes"
    return "\(fieldLabel(.question)) says \(answer) to \u{201C}\(condition.value)\u{201D}"
  }
  let test = ConditionTest(op: condition.op, negated: condition.negated).label(for: condition.field)
  return condition.field.isFlag || condition.op == .exists
    ? "\(fieldLabel(condition.field)) \(test)"
    : "\(fieldLabel(condition.field)) \(test) \(condition.value)"
}

/// A group's conditions as one sentence, joined by what the group asks
/// for — "and" when every condition must hold, "or" when any will do.
func describeConditions(_ conditions: [RuleCondition], match: RuleMatch) -> String {
  conditions.map(describe).joined(separator: conjunction(match))
}

/// A whole filter in words: its one group as a sentence, or each group in
/// parentheses, joined by the filter's own and/or.
func describe(_ filter: RuleFilter) -> String {
  let groups = filter.groups.filter { !$0.conditions.isEmpty }
  guard groups.count > 1 else {
    return groups.first.map { describeConditions($0.conditions, match: $0.match) } ?? "nothing yet"
  }
  return groups
    .map { group in
      let sentence = describeConditions(group.conditions, match: group.match)
      return group.conditions.count > 1 ? "(\(sentence))" : sentence
    }
    .joined(separator: conjunction(filter.match))
}

/// The same for a whole rule.
func describe(_ rule: LabelRule) -> String {
  let conditions = describe(rule.filter)
  return rule.movesItems ? "\(conditions) · moved" : conditions
}

/// A filter's shape in a few words, for a list row: "2 conditions", "any
/// of 3 groups", "a question" — and whether the model has a say.
func summarize(_ filter: RuleFilter) -> String {
  let groups = filter.groups.filter { !$0.conditions.isEmpty }
  let questions = filter.conditions.count { $0.field == .question }
  guard let only = groups.first else {
    return "no conditions yet"
  }
  let shape: String
  if groups.count > 1 {
    shape = "\(filter.match == .any ? "any" : "all") of \(groups.count) groups"
  } else if only.conditions.count == 1 {
    return questions == 1 ? "a question" : "1 condition"
  } else {
    let counted = "\(only.conditions.count) conditions"
    shape = only.match == .any ? "any of \(counted)" : counted
  }
  switch questions {
  case 0: return shape
  case 1: return "\(shape), one a question"
  default: return "\(shape), \(questions) of them questions"
  }
}

private func conjunction(_ match: RuleMatch) -> String {
  match == .any ? " or " : " and "
}
