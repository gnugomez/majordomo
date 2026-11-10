// The rules engine: filters (RuleFilter) compiled once per sweep and tested
// against notifications and board cards alike. Pure functions — no state,
// no I/O. The sync engine runs them in one sweep whenever anything a filter
// reads changes: every enabled label rule over the live items here, and
// every board's scope and columns over the cards in BoardEngine, both from
// the same compiled set. A question condition only reads the model's stored
// answer; where that answer could still change an outcome, the sweep names
// the question so the sync engine can ask it.

import Foundation

enum RuleEngine {
  /// What one item gets from the rules: the labels assigned to it, and
  /// the inboxes it is kept out of because a rule moved it.
  struct Assignment: Hashable, Sendable {
    var labels: Set<LabelId> = []
    var hiddenFrom: Set<LabelId> = []
  }

  /// The questions a sweep wants answered, by subject id (an item's id, a
  /// card's target key): the keys whose answers could change where the
  /// subject ends up — unasked, or asked about text that has changed since.
  typealias OpenQuestions = [String: Set<String>]

  /// Every enabled label rule and every board, compiled for one sweep.
  struct Compiled {
    let rules: [CompiledRule]
    let boards: [CompiledBoard]
    /// Each question asked anywhere, by key.
    let questions: [String: String]
  }

  /// Compiles what a sweep runs. `everyInbox` is what a rule's "show only
  /// here" resolves against — every inbox in the sidebar, catch-all
  /// included; empty when only labels matter.
  static func compile(rules: [LabelRule], boards: [Board], everyInbox: [LabelId] = []) -> Compiled {
    let enabled = rules.filter(\.enabled).map { CompiledRule($0, everyInbox: everyInbox) }
    let compiledBoards = boards.map(CompiledBoard.init)
    var questions: [String: String] = [:]
    for filter in enabled.map(\.filter) + compiledBoards.flatMap(\.filters) {
      for question in filter.questions {
        questions[question.key] = question.text
      }
    }
    return Compiled(rules: enabled, boards: compiledBoards, questions: questions)
  }

  /// What the label rules make of a batch of items.
  struct Labeling: Sendable {
    /// By item id; an item no rule matched gets an empty assignment.
    var assignments: [String: Assignment] = [:]
    var open: OpenQuestions = [:]
  }

  /// Runs the compiled label rules over a batch: each matching rule
  /// contributes its labels (restricted to `existing`) and the inboxes it
  /// hides the item from.
  static func assign(_ items: [InboxItem], rules: [CompiledRule], existing: Set<LabelId>) -> Labeling {
    var labeling = Labeling()
    for item in items {
      var result = Assignment()
      for rule in rules {
        let outcome = rule.filter.evaluate(item)
        if !outcome.open.isEmpty {
          labeling.open[item.id, default: []].formUnion(outcome.open)
        }
        if outcome.holds {
          result.labels.formUnion(rule.labelIds)
          result.hiddenFrom.formUnion(rule.hidden)
        }
      }
      result.labels.formIntersection(existing)
      // An inbox this item actually lands in always shows it, whatever
      // another rule wanted to hide.
      result.hiddenFrom.subtract(result.labels)
      labeling.assignments[item.id] = result
    }
    return labeling
  }

  /// One condition against one subject — for previews and tests; a sweep
  /// compiles its patterns once instead.
  static func holds(_ condition: RuleCondition, for subject: some RuleSubject) -> Bool {
    CompiledCondition(condition).holds(for: subject)
  }

  /// One filter against one subject, as a rule or a column would test it.
  static func matches(_ filter: RuleFilter, _ subject: some RuleSubject) -> Bool {
    CompiledFilter(filter).evaluate(subject).holds
  }

  /// The subjects a filter holds for, compiled once for the lot — what the
  /// settings previews show a rule would label, whatever its enabled
  /// state.
  static func matching<Subject: RuleSubject>(_ filter: RuleFilter, among subjects: [Subject]) -> [Subject] {
    let compiled = CompiledFilter(filter)
    return subjects.filter { compiled.evaluate($0).holds }
  }

  /// How many of the subjects the filter can't place yet: their outcome
  /// waits on a question the model hasn't answered.
  static func awaitingModel(_ filter: RuleFilter, among subjects: [some RuleSubject]) -> Int {
    let compiled = CompiledFilter(filter)
    guard compiled.asksModel else {
      return 0
    }
    return subjects.count { subject in
      compiled.evaluate(subject).open.contains { subject.verdict(for: $0) == nil }
    }
  }

  /// The key a question's answers are kept under: its wording, trimmed
  /// and fingerprinted, so the same question asked by a rule and by a
  /// board column shares its answers, and a reworded one starts afresh.
  static func questionKey(_ question: String) -> String {
    textFingerprint(question.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// Every question the rules and boards ask, switched on or not — the
  /// answers worth keeping.
  static func questionKeys(rules: [LabelRule], boards: [Board]) -> Set<String> {
    let filters = rules.map(\.filter) + boards.flatMap { [$0.scope] + $0.columns.map(\.filter) }
    return Set(filters.flatMap(\.conditions).compactMap(\.question).map(questionKey))
  }
}

/// An enabled label rule, compiled.
struct CompiledRule {
  let labelIds: [LabelId]
  /// The inboxes a match is hidden from, resolved once per sweep.
  let hidden: Set<LabelId>
  let filter: CompiledFilter

  init(_ rule: LabelRule, everyInbox: [LabelId]) {
    labelIds = rule.labelIds
    hidden = rule.hidden(among: everyInbox)
    filter = CompiledFilter(rule.filter)
  }
}

/// Whether a filter holds for a subject, and the questions that could
/// still change that.
struct FilterOutcome: Sendable {
  var holds: Bool
  /// Question keys worth asking — or asking again, should the subject's
  /// text change. Empty when the cheap conditions settle it.
  var open: [String] = []
}

/// A filter with its conditions compiled. Groups join by the filter's
/// match, conditions by their group's; an empty group, and a filter with
/// no groups, hold for nothing.
struct CompiledFilter {
  let match: RuleMatch
  let groups: [CompiledGroup]
  /// No conditions anywhere: what a board's scope reads as "every card".
  let isEmpty: Bool

  init(_ filter: RuleFilter) {
    match = filter.match
    groups = filter.groups.map(CompiledGroup.init)
    isEmpty = filter.isEmpty
  }

  /// Every question the filter asks, by key, with its wording.
  var questions: [(key: String, text: String)] {
    groups.flatMap(\.questions).compactMap { compiled in
      guard let key = compiled.questionKey, let text = compiled.condition.question else {
        return nil
      }
      return (key, text)
    }
  }

  var asksModel: Bool {
    groups.contains { !$0.questions.isEmpty }
  }

  /// Unanswered questions count as not holding. A group the cheap
  /// conditions settle asks nothing; of the rest, only the groups that
  /// decide the outcome name their questions.
  func evaluate(_ subject: some RuleSubject) -> FilterOutcome {
    guard !groups.isEmpty else {
      return FilterOutcome(holds: false)
    }
    var judged: [CompiledGroup.Judged] = []
    for group in groups {
      switch group.evaluate(subject) {
      case .settled(let holds):
        // One settled group decides the filter outright.
        if holds == (match == .any) {
          return FilterOutcome(holds: holds)
        }
      case .judged(let outcome):
        judged.append(outcome)
      }
    }
    switch match {
    case .any:
      let holding = judged.filter(\.holds)
      let deciding = holding.isEmpty ? judged : holding
      return FilterOutcome(holds: !holding.isEmpty, open: deciding.flatMap(\.open))
    case .all:
      let failing = judged.filter { !$0.holds && !$0.pending }
      let deciding = failing.isEmpty ? judged : failing
      return FilterOutcome(holds: judged.allSatisfy(\.holds), open: deciding.flatMap(\.open))
    }
  }
}

/// A group with its conditions compiled, the cheap tests apart from the
/// questions: the tests run first, and a question is only read when they
/// leave the group open.
struct CompiledGroup {
  let match: RuleMatch
  let tests: [CompiledCondition]
  let questions: [CompiledCondition]

  init(_ group: RuleGroup) {
    match = group.match
    let compiled = group.conditions.map(CompiledCondition.init)
    tests = compiled.filter { $0.questionKey == nil }
    questions = compiled.filter { $0.questionKey != nil }
  }

  /// A group the model's answers decide.
  struct Judged {
    var holds: Bool
    /// Whether the outcome waits on a question not answered yet.
    var pending: Bool
    /// The questions that decide it.
    var open: [String]
  }

  enum Result {
    /// Decided by the tests alone.
    case settled(Bool)
    case judged(Judged)
  }

  func evaluate(_ subject: some RuleSubject) -> Result {
    guard !tests.isEmpty || !questions.isEmpty else {
      return .settled(false)
    }
    switch match {
    case .all:
      if tests.contains(where: { !$0.holds(for: subject) }) {
        return .settled(false)
      }
    case .any:
      if tests.contains(where: { $0.holds(for: subject) }) {
        return .settled(true)
      }
    }
    guard !questions.isEmpty else {
      return .settled(match == .all)
    }
    let answers = questions.map { (key: $0.questionKey ?? "", holds: $0.answer(for: subject)) }
    // One answer that decides the group on its own is all that matters;
    // otherwise every question does.
    let decisive = answers.filter { $0.holds == (match == .any) }
    if !decisive.isEmpty {
      return .judged(Judged(holds: match == .any, pending: false, open: decisive.map(\.key)))
    }
    let pending = answers.contains { $0.holds == nil }
    return .judged(Judged(holds: match == .all && !pending, pending: pending, open: answers.map(\.key)))
  }
}

/// One condition with its pattern prepared: a `*` glob (repo only) and a
/// `matches` regex compile to NSRegularExpression up front; an invalid
/// pattern compiles to nothing and never holds. A question compiles to
/// its key, and a blank one to a test that never holds.
struct CompiledCondition {
  let condition: RuleCondition
  let regex: NSRegularExpression?
  /// The day a `before` or `after` sets the field's day against; nil
  /// when the value names none, and the condition never holds.
  let dayReference: DayReference?
  /// The key the answers to a question are kept under; nil for any other
  /// condition.
  let questionKey: String?

  init(_ condition: RuleCondition) {
    self.condition = condition
    questionKey = condition.question.map(RuleEngine.questionKey)
    let pattern = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
    dayReference = condition.op.comparesDays ? DueDate.reference(pattern) : nil
    switch condition.op {
    case _ where condition.field == .question:
      regex = nil
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

  /// A question's outcome: whether the model's answer satisfies it — yes,
  /// or no when negated — and nil while there is no answer.
  func answer(for subject: some RuleSubject) -> Bool? {
    guard let questionKey, let verdict = subject.verdict(for: questionKey) else {
      return nil
    }
    return condition.negated ? !verdict : verdict
  }

  /// A flag field ignores operator and value; a question holds on the
  /// answer it wants and never without one; a day set before or after
  /// another holds on the days alone, and never without both; any other
  /// holds when one of the subject's values for it passes (an issue's
  /// labels, its assignees). `negated` inverts the outcome.
  func holds(for subject: some RuleSubject) -> Bool {
    if condition.field == .question {
      return answer(for: subject) == true
    }
    let outcome: Bool
    if condition.field.isFlag {
      outcome = subject.flag(condition.field)
    } else if condition.op.comparesDays {
      if let day = subject.day(of: condition.field), let dayReference {
        let distance = DueDate.distance(of: day, from: dayReference)
        outcome = condition.op == .before ? distance < 0 : distance > 0
      } else {
        outcome = false
      }
    } else {
      let values = subject.values(of: condition.field)
      let own = subject.ownLogins
      outcome = values.contains { test($0, own: own) }
    }
    return condition.negated ? !outcome : outcome
  }

  private func test(_ value: String, own: [String]) -> Bool {
    let pattern = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
    switch condition.op {
    case .exists:
      return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    // An empty value is an unset condition, never a match: `contains ""`
    // would hold for everything and `is ""` for every item missing the
    // field.
    case .is:
      if let regex {
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
      }
      if pattern.caseInsensitiveCompare("@me") == .orderedSame {
        return own.contains { value.caseInsensitiveCompare($0) == .orderedSame }
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
    case .before, .after:
      // Days are set against each other in `holds`, never as text.
      return false
    }
  }
}
