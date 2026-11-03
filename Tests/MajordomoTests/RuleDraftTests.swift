// What the composer drafts and what the app lets through: a sentence's
// tests grouped into a filter, Apple Intelligence checks among them, and
// every shape validation turns away before it could reach the store.

import Testing
@testable import Majordomo

private func test(_ field: String, _ op: String, _ value: String, negated: Bool = false) -> ConditionDraft {
  ConditionDraft(field: field, op: op, value: value, negated: negated)
}

/// An "is" test.
private func test(_ field: String, _ value: String, negated: Bool = false) -> ConditionDraft {
  test(field, "is", value, negated: negated)
}

private func check(_ question: String, negated: Bool = false) -> ConditionDraft {
  ConditionDraft(field: "question", value: question, negated: negated)
}

private func draft(_ match: String = "any", _ groups: GroupDraft...) -> FilterDraft {
  FilterDraft(match: match, groups: groups)
}

private func all(_ conditions: ConditionDraft...) -> GroupDraft {
  GroupDraft(match: "all", conditions: conditions)
}

private func any(_ conditions: ConditionDraft...) -> GroupDraft {
  GroupDraft(match: "any", conditions: conditions)
}

/// The filter a draft validates to for a label rule, or nil.
private func ruleFilter(_ draft: FilterDraft) -> RuleFilter? {
  try? draft.validated(fields: RuleField.itemFields).get()
}

/// Why a draft is turned away for a label rule, or nil when it isn't.
private func rejection(_ draft: FilterDraft) -> RuleDraftError? {
  if case .failure(let error) = draft.validated(fields: RuleField.itemFields) {
    return error
  }
  return nil
}

private let risky = "Does this look risky?"

@Suite("Rule drafts")
struct RuleDraftTests {
  // MARK: Validation

  @Test func acceptsGroupsWithTheirOwnMatch() {
    let drafted = draft("all", any(test("author", "mona"), test("author", "sasha")), all(test("kind", "pull")))
    #expect(ruleFilter(drafted) == filter(
      .all,
      group(.any, condition(.author, .is, "mona"), condition(.author, .is, "sasha")),
      group(.all, condition(.kind, .is, "pull"))
    ))
  }

  @Test func acceptsAppleIntelligenceChecks() {
    let drafted = draft("any", all(test("reason", "review_requested"), check("  \(risky) ", negated: true)))
    #expect(ruleFilter(drafted) == filter(
      .any,
      group(.all, condition(.reason, .is, "review_requested"), .question(risky, negated: true))
    ))
  }

  @Test func readsFieldsOperatorsAndMatchesInAnyCase() {
    let drafted = draft("ALL", GroupDraft(match: "Any", conditions: [test("UpstreamLabel", "Contains", "bug")]))
    #expect(ruleFilter(drafted) == filter(.all, group(.any, condition(.upstreamLabel, .contains, "bug"))))
  }

  @Test func blankMatchesTakeEachLevelsDefault() {
    let drafted = draft("", GroupDraft(match: " ", conditions: [test("repo", "acme/*")]))
    #expect(ruleFilter(drafted) == filter(.any, group(.all, condition(.repo, .is, "acme/*"))))
  }

  @Test func aFlagFieldDropsItsValue() {
    let drafted = draft("any", all(test("mention", "urgent")))
    #expect(ruleFilter(drafted) == filter(.any, group(.all, condition(.mention))))
  }

  @Test func emptyGroupsAreDroppedAndNothingAtAllIsRejected() {
    #expect(ruleFilter(draft("all", GroupDraft(), all(test("author", "kim")))) == filter(.all, group(.all, condition(.author, .is, "kim"))))
    #expect(rejection(draft("any")) == .noConditions)
    #expect(rejection(draft("any", GroupDraft(), GroupDraft())) == .noConditions)
  }

  @Test func rejectsWhatNoFieldOrOperatorIs() {
    #expect(rejection(draft("any", all(test("colour", "red")))) == .unknownField("colour"))
    #expect(rejection(draft("any", all(test("title", "startsWith", "fix")))) == .unknownOperator("startsWith"))
    #expect(rejection(draft("some", all(test("title", "contains", "fix")))) == .unknownMatch("some"))
    #expect(rejection(draft("any", GroupDraft(match: "most", conditions: [test("title", "contains", "fix")]))) == .unknownMatch("most"))
  }

  @Test func rejectsEmptyValuesAndBrokenPatterns() {
    #expect(rejection(draft("any", all(test("author", "  ")))) == .emptyValue("author"))
    #expect(rejection(draft("any", all(test("title", "matches", "crash(")))) == .invalidRegex("crash("))
  }

  @Test func boardOnlyFieldsStayOutOfLabelRules() throws {
    let assigned = draft("any", all(test("assignee", "@me")))
    #expect(rejection(assigned) == .boardOnlyField("assignee"))
    #expect(rejection(draft("any", all(test("lastcommenter", "kim")))) == .boardOnlyField("lastCommenter"))
    // A board's column reads them.
    #expect(try assigned.validated(fields: RuleField.cardFields).get() == filter(.any, group(.all, condition(.assignee, .is, "@me"))))
  }

  @Test func rejectsBlankAndRamblingQuestions() {
    #expect(rejection(draft("any", all(check("   ")))) == .emptyQuestion)
    let rambling = String(repeating: "Is this about the deploy pipeline? ", count: 7)
    #expect(rambling.count > FilterDraft.maxQuestionLength)
    #expect(rejection(draft("any", all(check(rambling)))) == .questionTooLong)
  }

  @Test func rejectsFiltersTooBigForASentence() {
    let groups = (0 ... FilterDraft.maxGroups).map { all(test("author", "user\($0)")) }
    #expect(rejection(FilterDraft(match: "any", groups: groups)) == .tooManyGroups)
    let conditions = (0 ... FilterDraft.maxConditions).map { test("author", "user\($0)") }
    #expect(rejection(draft("any", GroupDraft(match: "any", conditions: conditions))) == .tooManyConditions)
    let questions = (0 ... FilterDraft.maxQuestions).map { check("Is this about topic \($0)?") }
    #expect(rejection(draft("any", GroupDraft(match: "all", conditions: questions))) == .tooManyQuestions)
  }

  /// The messages render verbatim in the composer.
  @Test func everyRejectionReadsAsASentence() {
    let errors: [RuleDraftError] = [
      .noConditions, .unknownField("colour"), .boardOnlyField("assignee"), .unknownOperator("near"),
      .unknownMatch("some"), .emptyValue("author"), .invalidRegex("("), .emptyQuestion, .questionTooLong,
      .tooManyGroups, .tooManyConditions, .tooManyQuestions, .noTarget,
    ]
    for error in errors {
      #expect(error.errorDescription?.hasSuffix(".") == true)
    }
  }

  // MARK: A sentence's tests into groups

  @Test func aLoneTestIsALoneGroup() {
    let listed = FilterDraft(listing: [test("author", "contains", "dependabot")], match: "all")
    #expect(listed == draft("any", all(test("author", "contains", "dependabot"))))
  }

  @Test func testsOnOneFieldAreAlternatives() {
    let listed = FilterDraft(
      listing: [test("kind", "pull"), test("author", "mona"), test("repo", "acme/app"), test("author", "sasha")],
      match: "all"
    )
    #expect(listed == draft(
      "all",
      all(test("kind", "pull"), test("repo", "acme/app")),
      any(test("author", "mona"), test("author", "sasha"))
    ))
    let rule = try? listed.validated(fields: RuleField.itemFields).get()
    #expect(rule.map { RuleEngine.matches($0, item(kind: "pull", repo: "acme/app", author: "sasha")) } == true)
    #expect(rule.map { RuleEngine.matches($0, item(kind: "pull", repo: "acme/app", author: "kim")) } == false)
    #expect(rule.map { RuleEngine.matches($0, item(kind: "issue", repo: "acme/app", author: "mona")) } == false)
  }

  @Test func negatedTestsOnOneFieldMustAllHold() {
    let listed = FilterDraft(
      listing: [test("author", "mona", negated: true), test("author", "sasha", negated: true), test("repo", "acme/*"),
                test("repo", "acme/legacy", negated: true), test("repo", "beta/*")],
      match: "all"
    )
    #expect(listed == draft(
      "all",
      all(test("author", "mona", negated: true), test("author", "sasha", negated: true), test("repo", "acme/legacy", negated: true)),
      any(test("repo", "acme/*"), test("repo", "beta/*"))
    ))
    let rule = try? listed.validated(fields: RuleField.itemFields).get()
    #expect(rule.map { RuleEngine.matches($0, item(repo: "acme/app", author: "kim")) } == true)
    #expect(rule.map { RuleEngine.matches($0, item(repo: "acme/legacy", author: "kim")) } == false)
    #expect(rule.map { RuleEngine.matches($0, item(repo: "acme/app", author: "sasha")) } == false)
  }

  @Test func matchAnyMakesEveryTestAnAlternative() {
    let listed = FilterDraft(listing: [test("repo", "acme/infra"), test("author", "kim")], match: "any")
    #expect(listed == draft("any", any(test("repo", "acme/infra"), test("author", "kim"))))
  }

  @Test func aCheckNarrowsWhatTheTestsLetThrough() {
    let narrowed = FilterDraft(listing: [test("reason", "review_requested"), check(risky)], match: "all")
    #expect(narrowed == draft("any", all(test("reason", "review_requested"), check(risky))))

    // Alternatives across fields, and still the check narrows them all.
    let alternatives = FilterDraft(listing: [test("repo", "acme/infra"), test("author", "kim"), check(risky)], match: "any")
    #expect(alternatives == draft("all", all(check(risky)), any(test("repo", "acme/infra"), test("author", "kim"))))

    // Two checks stay two requirements, never alternatives.
    let both = FilterDraft(listing: [check(risky), check("Is it about billing?")], match: "all")
    #expect(both == draft("any", all(check(risky), check("Is it about billing?"))))
  }

  @Test func aCheckAsksOnlyAboutWhatTheTestsLetThrough() throws {
    let listed = FilterDraft(listing: [test("reason", "review_requested"), check(risky)], match: "all")
    let rule = try listed.validated(fields: RuleField.itemFields).get()
    let key = RuleEngine.questionKey(risky)
    let review = item("acct:1", reason: "review_requested")
    let other = item("acct:2", reason: "subscribed")
    #expect(RuleEngine.awaitingModel(rule, among: [review, other]) == 1)
    #expect(RuleEngine.matches(rule, item(reason: "review_requested", verdicts: [key: true])))
    #expect(!RuleEngine.matches(rule, item(reason: "review_requested", verdicts: [key: false])))
    #expect(!RuleEngine.matches(rule, item(reason: "subscribed", verdicts: [key: true])))
  }

  // MARK: Whole rules

  @Test func aDraftBecomesARuleForAnExistingTarget() throws {
    let later = InboxLabel(id: "later", name: "Later", symbol: "moon.zzz", tint: .gray, notify: .never, order: 0)
    let drafted = RuleDraft(
      name: "dependabot_wait",
      filter: FilterDraft(listing: [test("author", "contains", "dependabot")], match: "all"),
      targetName: "later",
      createTarget: true
    )
    let validated = try drafted.validated(against: [later]).get()
    #expect(validated.newTarget == nil)
    #expect(validated.rule.labelIds == ["later"])
    #expect(validated.rule.name == "Dependabot wait")
    #expect(validated.rule.filter == filter(.any, group(.all, condition(.author, .contains, "dependabot"))))
  }

  @Test func aDraftCanAskForANewTarget() throws {
    let drafted = RuleDraft(
      name: "",
      filter: draft("any", all(test("kind", "pull"), check(risky))),
      targetName: " Risky ",
      createTarget: true,
      targetKind: "Inbox",
      targetSymbol: "made.up.symbol",
      targetTint: "RED"
    )
    let validated = try drafted.validated(against: []).get()
    let target = try #require(validated.newTarget)
    #expect(target.name == "Risky")
    #expect(target.kind == .inbox)
    #expect(target.symbol == "tray")
    #expect(target.tint == .red)
    #expect(validated.rule.name == "Risky")
    #expect(validated.rule.labelIds == [target.id])
    #expect(validated.rule.filter.asksModel)
  }

  @Test func aDraftWithoutATargetOrAValidFilterIsRejected() {
    let noTarget = RuleDraft(name: "Kim", filter: draft("any", all(test("author", "kim"))), targetName: "  ")
    #expect(noTarget.validated(against: []) == .failure(.noTarget))
    let boardOnly = RuleDraft(name: "Mine", filter: draft("any", all(test("reviewer", "@me"))), targetName: "Mine")
    #expect(boardOnly.validated(against: []) == .failure(.boardOnlyField("reviewer")))
  }

  @Test func identifierNamesReadAsWords() {
    #expect(RuleDraft.readableName("dependabot_wait") == "Dependabot wait")
    #expect(RuleDraft.readableName("RiskyPRs") == "Risky PRs")
    #expect(RuleDraft.readableName("sdk-breaking-change") == "Sdk breaking change")
    #expect(RuleDraft.readableName(" Urgent Mentions ") == "Urgent Mentions")
    #expect(RuleDraft.readableName("Later") == "Later")
    #expect(RuleDraft.readableName("__") == "")
  }

  // MARK: The model's question, and the filter in words

  @Test func aQuestionMustAskAboutTheSentence() {
    #expect(isGrounded("Does this sound like a production incident?", in: "anything that sounds like a production incident is urgent"))
    #expect(isGrounded("Does this change look risky?", in: "PRs that look risky"))
    #expect(isGrounded("Is this a risk to the release?", in: "anything risky that's waiting on my review"))
    // An example from the instructions, copied over a sentence it has nothing to do with.
    #expect(!isGrounded("Does this read like a security hole?", in: "PRs that look risky"))
    #expect(!isGrounded("Does this look like that?", in: "does this look like that"))
  }

  @Test func aFilterOutlinesLineByLine() {
    let lone = filter(.any, group(.all, condition(.kind, .is, "pull"), .question(risky)))
    #expect(outline(lone) == FilterOutline(match: .all, lines: [
      "Kind is pull", "Apple Intelligence says yes to \u{201C}\(risky)\u{201D}",
    ]))
    let grouped = filter(
      .all,
      group(.all, condition(.kind, .is, "pull")),
      group(.any, condition(.author, .is, "mona"), condition(.author, .is, "sasha", negated: true))
    )
    #expect(outline(grouped) == FilterOutline(match: .all, lines: [
      "Kind is pull", "Author is mona or Author is not sasha",
    ]))
  }
}
