// What a model proposes, before the app trusts any of it. A draft is plain
// strings in the app's own vocabulary; `validated(against:)` turns one into
// a real rule or says why it can't. Nothing generated ever reaches the
// store unvalidated: an unknown field, a bad operator, an uncompilable
// regex, a blank or rambling Apple Intelligence check, or a filter too big
// to be what one sentence meant is a rejection, not a silently broken
// rule. Foundation only — the model plumbing lives in Sync.

import Foundation

/// One proposed condition, field/operator/value as the model named them.
/// The field "question" makes it an Apple Intelligence check: the value is
/// the question, the operator is ignored, and `negated` wants the model's
/// no rather than its yes.
struct ConditionDraft: Hashable, Sendable {
  var field: String
  var op: String = "is"
  var value: String = ""
  var negated: Bool = false
}

/// Proposed conditions that hold together: "all" of them, or "any" one.
struct GroupDraft: Hashable, Sendable {
  var match: String = "all"
  var conditions: [ConditionDraft] = []
}

/// A proposed filter, RuleFilter's shape in the model's strings: groups
/// joined by `match`, "any" or "all".
struct FilterDraft: Hashable, Sendable {
  var match: String = "any"
  var groups: [GroupDraft] = []
}

/// A proposed rule — its filter — and what it should apply to: an existing
/// label or inbox by name, or a new one to create alongside it.
struct RuleDraft: Hashable, Sendable {
  var name: String
  var filter = FilterDraft()
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
  case boardOnlyField(String)
  case unknownOperator(String)
  case unknownMatch(String)
  case emptyValue(String)
  case invalidRegex(String)
  case emptyQuestion
  case questionTooLong
  case tooManyGroups
  case tooManyConditions
  case tooManyQuestions
  case noTarget

  var errorDescription: String? {
    switch self {
    case .noConditions:
      "That didn't describe anything to match on — try naming a repo, an author, or words in the title."
    case .unknownField(let field):
      "“\(field)” isn't something an item can be matched on."
    case .boardOnlyField(let field):
      "“\(field)” is only known on a board, so a rule can't test a notification on it."
    case .unknownOperator(let op):
      "“\(op)” isn't a comparison this app can make."
    case .unknownMatch(let match):
      "“\(match)” isn't a way to combine conditions — it's all or any."
    case .emptyValue(let field):
      "The test on \(field) has nothing to compare against."
    case .invalidRegex(let pattern):
      "“\(pattern)” isn't a valid regular expression."
    case .emptyQuestion:
      "The Apple Intelligence check has no question to ask."
    case .questionTooLong:
      "The Apple Intelligence check runs past \(FilterDraft.maxQuestionLength) characters — it should be one short question."
    case .tooManyGroups:
      "That came out as more than \(FilterDraft.maxGroups) groups of conditions — try a simpler sentence, or build the rule by hand."
    case .tooManyConditions:
      "That came out as more than \(FilterDraft.maxConditions) conditions — try a simpler sentence, or build the rule by hand."
    case .tooManyQuestions:
      "That would put more than \(FilterDraft.maxQuestions) questions to Apple Intelligence about every notification — try a simpler sentence."
    case .noTarget:
      "That didn't say which inbox or label to apply."
    }
  }
}

extension FilterDraft {
  /// The most groups a draft may hold: a sentence describes a rule a
  /// person reads at a glance.
  static let maxGroups = 4
  /// The most conditions across every group, for the same reason.
  static let maxConditions = 8
  /// The most Apple Intelligence checks: each one is a model call per
  /// subject the cheap conditions let through.
  static let maxQuestions = 2
  /// A check's question at its longest — one question, not a paragraph.
  static let maxQuestionLength = 200

  /// A filter from tests listed the way a sentence lists them. Tests on
  /// one field are alternatives ("from mona or sasha"): its plain tests
  /// form a group of their own, any one enough, while a negated one ("not
  /// from kim") must hold all the same. Tests on different fields must all
  /// hold — unless `match` is "any", which makes every plain test an
  /// alternative. An Apple Intelligence check always narrows what the
  /// plain tests let through rather than widening it, so the model is
  /// asked about as few subjects as the sentence allows.
  init(listing tests: [ConditionDraft], match: String) {
    let checks = tests.filter(\.isQuestion)
    let plain = tests.filter { !$0.isQuestion }
    var required: [ConditionDraft] = []
    var alternatives: [GroupDraft] = []
    if Self.normalized(match) == "any" {
      if plain.count > 1 {
        alternatives.append(GroupDraft(match: "any", conditions: plain))
      } else {
        required = plain
      }
    } else {
      for field in Self.fieldsInOrder(plain) {
        let onField = plain.filter { Self.normalized($0.field) == field }
        let wanted = onField.filter { !$0.negated }
        if wanted.count > 1 {
          alternatives.append(GroupDraft(match: "any", conditions: wanted))
          required += onField.filter(\.negated)
        } else {
          required += onField
        }
      }
    }
    required += checks
    let groups = (required.isEmpty ? [] : [GroupDraft(match: "all", conditions: required)]) + alternatives
    // Several groups are requirements on top of each other; a lone one
    // takes the default join, as a filter built by hand does.
    self.init(match: groups.count > 1 ? "all" : "any", groups: groups)
  }

  /// The draft as a real filter whose conditions test only `fields` —
  /// what a notification carries, for a label rule — or the reason it
  /// can't be one. Groups the model left empty are dropped: they carry no
  /// condition to check.
  func validated(fields: [RuleField]) -> Result<RuleFilter, RuleDraftError> {
    let drafted = groups.filter { !$0.conditions.isEmpty }
    guard !drafted.isEmpty else {
      return .failure(.noConditions)
    }
    guard drafted.count <= Self.maxGroups else {
      return .failure(.tooManyGroups)
    }
    let conditions = drafted.flatMap(\.conditions)
    guard conditions.count <= Self.maxConditions else {
      return .failure(.tooManyConditions)
    }
    guard conditions.count(where: \.isQuestion) <= Self.maxQuestions else {
      return .failure(.tooManyQuestions)
    }
    let filterMatch: RuleMatch
    switch Self.match(match, defaultingTo: .any) {
    case .success(let parsed):
      filterMatch = parsed
    case .failure(let error):
      return .failure(error)
    }
    var checked: [RuleGroup] = []
    for group in drafted {
      switch group.validated(fields: fields) {
      case .success(let valid):
        checked.append(valid)
      case .failure(let error):
        return .failure(error)
      }
    }
    return .success(RuleFilter(match: filterMatch, groups: checked))
  }

  /// "all" or "any", whatever the case; blank takes the level's default.
  fileprivate static func match(_ text: String, defaultingTo fallback: RuleMatch) -> Result<RuleMatch, RuleDraftError> {
    let trimmed = normalized(text)
    guard !trimmed.isEmpty else {
      return .success(fallback)
    }
    guard let match = RuleMatch(rawValue: trimmed) else {
      return .failure(.unknownMatch(text))
    }
    return .success(match)
  }

  private static func normalized(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// Each field the tests name, once, in the order they first name it.
  private static func fieldsInOrder(_ tests: [ConditionDraft]) -> [String] {
    var seen: Set<String> = []
    return tests.map { normalized($0.field) }.filter { seen.insert($0).inserted }
  }
}

extension GroupDraft {
  fileprivate func validated(fields: [RuleField]) -> Result<RuleGroup, RuleDraftError> {
    let groupMatch: RuleMatch
    switch FilterDraft.match(match, defaultingTo: .all) {
    case .success(let parsed):
      groupMatch = parsed
    case .failure(let error):
      return .failure(error)
    }
    var checked: [RuleCondition] = []
    for draft in conditions {
      switch draft.condition(fields: fields) {
      case .success(let condition):
        checked.append(condition)
      case .failure(let error):
        return .failure(error)
      }
    }
    return .success(RuleGroup(match: groupMatch, conditions: checked))
  }
}

extension RuleDraft {
  /// The draft as a real rule, or the reason it can't be one. Its filter
  /// tests only what a notification carries; existing targets are matched
  /// by name, case-insensitively, and a target the model asked to create
  /// becomes `newTarget`.
  func validated(against labels: [InboxLabel], now: Date = Date()) -> Result<ValidatedRule, RuleDraftError> {
    let checked: RuleFilter
    switch filter.validated(fields: RuleField.itemFields) {
    case .success(let valid):
      checked = valid
    case .failure(let error):
      return .failure(error)
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

    let readable = Self.readableName(name)
    let rule = LabelRule(
      id: UUID().uuidString,
      name: readable.isEmpty ? wanted : readable,
      filter: checked,
      labelIds: [targetId]
    )
    return .success(ValidatedRule(rule: rule, newTarget: newTarget))
  }

  /// A name as a person writes one. A model sometimes answers with an
  /// identifier ("dependabot_wait", "RiskyPRs"), which reads as words once
  /// its underscores and hyphens are spaces, its humps are split, and it
  /// opens on a capital. A name that already has spaces is left as it is.
  static func readableName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains(" ") else {
      return trimmed
    }
    var spaced = ""
    var previous: Character?
    for character in trimmed {
      if character == "_" || character == "-" {
        spaced.append(" ")
      } else {
        if character.isUppercase, previous?.isLowercase == true {
          spaced.append(" ")
        }
        spaced.append(character)
      }
      previous = character
    }
    let words = spaced.split(separator: " ").joined(separator: " ")
    return words.prefix(1).uppercased() + words.dropFirst()
  }
}

extension ConditionDraft {
  /// An Apple Intelligence check rather than a test on a field.
  var isQuestion: Bool {
    field.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(RuleField.question.rawValue) == .orderedSame
  }

  /// The draft as a real condition testing one of `fields` — or an Apple
  /// Intelligence check, whatever the fields — or why it isn't one. A
  /// field only a board's card carries is named as such, so the message
  /// says why it can't be used rather than that it doesn't exist.
  func condition(fields: [RuleField]) -> Result<RuleCondition, RuleDraftError> {
    let name = field.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let field = RuleField.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }) else {
      return .failure(.unknownField(name))
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if field == .question {
      return question(trimmed)
    }
    guard fields.contains(field) else {
      return .failure(RuleField.cardFields.contains(field) ? .boardOnlyField(field.rawValue) : .unknownField(field.rawValue))
    }
    guard let op = RuleOperator(rawValue: op.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
          field.isDay || !op.comparesDays else {
      return .failure(.unknownOperator(op))
    }
    // A flag field is a test of its own: whatever value came with it would
    // only show as nonsense in the editor.
    if field.isFlag {
      return .success(RuleCondition(field: field, op: .is, value: "", negated: negated))
    }
    if op != .exists {
      guard !trimmed.isEmpty else {
        return .failure(.emptyValue(field.rawValue))
      }
      if op == .matches, (try? NSRegularExpression(pattern: trimmed)) == nil {
        return .failure(.invalidRegex(trimmed))
      }
    }
    return .success(RuleCondition(field: field, op: op, value: trimmed, negated: negated))
  }

  private func question(_ text: String) -> Result<RuleCondition, RuleDraftError> {
    guard !text.isEmpty else {
      return .failure(.emptyQuestion)
    }
    guard text.count <= FilterDraft.maxQuestionLength else {
      return .failure(.questionTooLong)
    }
    return .success(.question(text, negated: negated))
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
