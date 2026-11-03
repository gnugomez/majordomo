// Groups and filters: all/any at both levels, what an empty one means, and
// Apple Intelligence checks — how a stored answer counts, and which
// questions a sweep finds worth asking.

import Testing
@testable import Majordomo

private let urgent = "Is this urgent?"
private let urgentKey = RuleEngine.questionKey(urgent)
private let security = "Is this a security problem?"
private let securityKey = RuleEngine.questionKey(security)

private func outcome(_ filter: RuleFilter, _ subject: some RuleSubject) -> FilterOutcome {
  CompiledFilter(filter).evaluate(subject)
}

@Suite("Groups and filters")
struct FilterTests {
  private let infraMention = item(repo: "acme/infra", reason: "mentioned", mention: true)

  @Test func groupMatchesAllOrAny() {
    let both = group(.all, condition(.repo, .is, "acme/infra"), condition(.reason, .is, "assigned"))
    let either = group(.any, condition(.repo, .is, "acme/infra"), condition(.reason, .is, "assigned"))
    #expect(!RuleEngine.matches(filter(.any, both), infraMention))
    #expect(RuleEngine.matches(filter(.any, either), infraMention))
  }

  @Test func filterJoinsGroupsByItsOwnMatch() {
    let infra = group(.all, condition(.repo, .is, "acme/infra"))
    let assigned = group(.all, condition(.reason, .is, "assigned"))
    #expect(RuleEngine.matches(filter(.any, infra, assigned), infraMention))
    #expect(!RuleEngine.matches(filter(.all, infra, assigned), infraMention))
    #expect(RuleEngine.matches(filter(.all, infra, group(.all, condition(.mention))), infraMention))
  }

  @Test func emptyGroupsAndFiltersMatchNothing() {
    #expect(!RuleEngine.matches(RuleFilter(), infraMention))
    #expect(!RuleEngine.matches(filter(.any, RuleGroup()), infraMention))
    #expect(!RuleEngine.matches(filter(.all, RuleGroup()), infraMention))
    // A draft group sinks an all-filter, and adds nothing to an any-filter.
    let infra = group(.all, condition(.repo, .is, "acme/infra"))
    #expect(!RuleEngine.matches(filter(.all, infra, RuleGroup()), infraMention))
    #expect(RuleEngine.matches(filter(.any, infra, RuleGroup()), infraMention))
    #expect(RuleFilter().isEmpty)
    #expect(filter(.any, RuleGroup(), RuleGroup()).isEmpty)
  }

  @Test func oneGroupFilterFromConditions() {
    let single = RuleFilter(conditions: [condition(.repo, .is, "acme/infra")], match: .any)
    #expect(single.groups == [RuleGroup(match: .any, conditions: [condition(.repo, .is, "acme/infra")])])
    #expect(RuleFilter(conditions: []).groups.isEmpty)
  }

  @Test func questionHoldsOnTheAnswerItWants() {
    let asks = filter(.any, group(.all, .question(urgent)))
    let refuses = filter(.any, group(.all, .question(urgent, negated: true)))
    let yes = item(verdicts: [urgentKey: true])
    let no = item(verdicts: [urgentKey: false])
    #expect(RuleEngine.matches(asks, yes))
    #expect(!RuleEngine.matches(asks, no))
    #expect(RuleEngine.matches(refuses, no))
    #expect(!RuleEngine.matches(refuses, yes))
  }

  @Test func anUnansweredQuestionHoldsNeitherWay() {
    let unasked = item()
    #expect(!RuleEngine.matches(filter(.any, group(.all, .question(urgent))), unasked))
    #expect(!RuleEngine.matches(filter(.any, group(.all, .question(urgent, negated: true))), unasked))
  }

  @Test func aBlankQuestionIsADraft() {
    let blank = filter(.any, group(.all, .question("   ")))
    #expect(!RuleEngine.matches(blank, item(verdicts: [RuleEngine.questionKey(""): true])))
    #expect(outcome(blank, item()).open.isEmpty)
  }

  @Test func questionKeysIgnoreSurroundingSpace() {
    #expect(RuleEngine.questionKey("  \(urgent)\n") == urgentKey)
    #expect(RuleEngine.questionKey(security) != urgentKey)
  }

  @Test func questionsCombineWithCheapConditions() {
    let issuesThatMatter = filter(.any, group(.all, condition(.kind, .is, "issue"), .question(urgent)))
    #expect(RuleEngine.matches(issuesThatMatter, item(kind: "issue", verdicts: [urgentKey: true])))
    #expect(!RuleEngine.matches(issuesThatMatter, item(kind: "pull", verdicts: [urgentKey: true])))
  }

  @Test func cheapConditionsThatSettleAGroupAskNothing() {
    let allGroup = filter(.any, group(.all, condition(.kind, .is, "issue"), .question(urgent)))
    #expect(outcome(allGroup, item(kind: "pull")).open.isEmpty)
    #expect(outcome(allGroup, item(kind: "issue")).open == [urgentKey])
    let anyGroup = filter(.any, group(.any, condition(.kind, .is, "issue"), .question(urgent)))
    #expect(outcome(anyGroup, item(kind: "issue")).open.isEmpty)
    #expect(outcome(anyGroup, item(kind: "pull")).open == [urgentKey])
  }

  @Test func aSettledGroupDecidesTheFilter() {
    let issues = group(.all, condition(.kind, .is, "issue"))
    let asked = group(.all, .question(urgent))
    let either = outcome(filter(.any, issues, asked), item(kind: "issue"))
    #expect(either.holds && either.open.isEmpty)
    let both = outcome(filter(.all, issues, asked), item(kind: "pull"))
    #expect(!both.holds && both.open.isEmpty)
    #expect(outcome(filter(.all, issues, asked), item(kind: "issue")).open == [urgentKey])
  }

  @Test func anAnswerThatDecidesAGroupLeavesTheOtherQuestionsAlone() {
    let both = filter(.any, group(.all, .question(urgent), .question(security)))
    let refused = outcome(both, item(verdicts: [urgentKey: false]))
    #expect(!refused.holds)
    // The answer that decided stays open — changed text asks it again —
    // and the question that can't matter is left unasked.
    #expect(refused.open == [urgentKey])
    let either = filter(.any, group(.any, .question(urgent), .question(security)))
    #expect(outcome(either, item(verdicts: [securityKey: true])).open == [securityKey])
  }

  @Test func awaitingCountsOnlyWhatTheModelHasYetToAnswer() {
    let issuesThatMatter = filter(.any, group(.all, condition(.kind, .is, "issue"), .question(urgent)))
    let items = [
      item("a:1", kind: "issue"),
      item("a:2", kind: "issue", verdicts: [urgentKey: false]),
      item("a:3", kind: "pull"),
    ]
    #expect(RuleEngine.awaitingModel(issuesThatMatter, among: items) == 1)
    #expect(RuleEngine.awaitingModel(filter(.any, group(.all, condition(.kind, .is, "issue"))), among: items) == 0)
  }

  @Test func assignLabelsMovesAndOpenQuestions() {
    let rules = [
      LabelRule(
        id: "infra", name: "Infra", filter: RuleFilter(conditions: [condition(.repo, .is, "acme/infra")]),
        labelIds: ["infra-label"], movesItems: true
      ),
      LabelRule(
        id: "urgent", name: "Urgent", filter: RuleFilter(conditions: [.question(urgent)]), labelIds: ["urgent-label"]
      ),
      LabelRule(
        id: "off", name: "Off", enabled: false, filter: RuleFilter(conditions: [condition(.mention)]),
        labelIds: ["infra-label"]
      ),
    ]
    let compiled = RuleEngine.compile(rules: rules, boards: [], everyInbox: ["recent", "infra-label", "urgent-label"])
    let labeled = RuleEngine.assign(
      [item("a:1", repo: "acme/infra"), item("a:2", repo: "acme/app", mention: true)],
      rules: compiled.rules,
      existing: ["infra-label", "urgent-label"]
    )
    #expect(labeled.assignments["a:1"] == RuleEngine.Assignment(labels: ["infra-label"], hiddenFrom: ["recent", "urgent-label"]))
    #expect(labeled.assignments["a:2"] == RuleEngine.Assignment())
    #expect(labeled.open == ["a:1": [urgentKey], "a:2": [urgentKey]])
    #expect(compiled.questions == [urgentKey: urgent])
  }

  @Test func anInboxAnItemLandsInAlwaysShowsIt() {
    let rules = [
      LabelRule(
        id: "move", name: "Move", filter: RuleFilter(conditions: [condition(.repo, .is, "acme/infra")]),
        labelIds: ["infra-label"], movesItems: true
      ),
      LabelRule(
        id: "copy", name: "Copy", filter: RuleFilter(conditions: [condition(.reason, .is, "mentioned")]),
        labelIds: ["mentions"]
      ),
    ]
    let compiled = RuleEngine.compile(rules: rules, boards: [], everyInbox: ["recent", "infra-label", "mentions"])
    let labeled = RuleEngine.assign([infraMention], rules: compiled.rules, existing: ["infra-label", "mentions"])
    #expect(labeled.assignments[infraMention.id] == RuleEngine.Assignment(
      labels: ["infra-label", "mentions"], hiddenFrom: ["recent"]
    ))
  }

  @Test func questionKeysCoverRulesAndBoards() {
    let rule = LabelRule(id: "r", name: "R", filter: RuleFilter(conditions: [.question(urgent)]), labelIds: [])
    var board = Board(id: "b", name: "B", symbol: "eye", columns: [
      BoardColumn(id: "c", name: "C", filter: RuleFilter(conditions: [.question(security)])),
    ])
    board.scope = RuleFilter(conditions: [condition(.kind, .is, "pull")])
    #expect(RuleEngine.questionKeys(rules: [rule], boards: [board]) == [urgentKey, securityKey])
  }
}
