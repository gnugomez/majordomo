// One condition at a time: each operator, negation, the repo glob, `@me`,
// the flag fields, and fields that hold several values.

import Testing
@testable import Majordomo

@Suite("Conditions")
struct ConditionTests {
  @Test func isMatchesWholeValueIgnoringCase() {
    let subject = item(repo: "Acme/App")
    #expect(holds(condition(.repo, .is, "acme/app"), for: subject))
    #expect(!holds(condition(.repo, .is, "acme"), for: subject))
  }

  @Test func emptyValueIsAnUnsetCondition() {
    let subject = item(author: nil)
    #expect(!holds(condition(.author, .is, ""), for: subject))
    #expect(!holds(condition(.title, .contains, "  "), for: subject))
  }

  @Test func containsIgnoresCaseAndDiacritics() {
    let subject = item(title: "Café crashes on start")
    #expect(holds(condition(.title, .contains, "CAFE"), for: subject))
    #expect(!holds(condition(.title, .contains, "tea"), for: subject))
  }

  @Test func matchesIsARegularExpressionAnywhere() {
    let subject = item(title: "fix: retry webhook deliveries")
    #expect(holds(condition(.title, .matches, "^FIX:"), for: subject))
    #expect(holds(condition(.title, .matches, "web.ook"), for: subject))
    #expect(!holds(condition(.title, .matches, "^feat:"), for: subject))
  }

  @Test func invalidRegexNeverHolds() {
    #expect(!holds(condition(.title, .matches, "(unclosed"), for: item()))
  }

  @Test func existsAsksForAnyValue() {
    #expect(holds(condition(.author, .exists), for: item(author: "kim")))
    #expect(!holds(condition(.author, .exists), for: item(author: nil)))
    #expect(holds(condition(.author, .exists, negated: true), for: item(author: "  ")))
  }

  @Test func repoGlobIsAnchoredWithWildcards() {
    let glob = condition(.repo, .is, "acme/*")
    #expect(holds(glob, for: item(repo: "acme/app")))
    #expect(holds(glob, for: item(repo: "ACME/infra")))
    #expect(!holds(glob, for: item(repo: "other/acme/app")))
    #expect(holds(condition(.repo, .is, "*/app"), for: item(repo: "acme/app")))
  }

  @Test func globIsOnlyForRepositories() {
    #expect(!holds(condition(.title, .is, "Importer*"), for: item()))
  }

  @Test func meStandsForTheSubjectsOwnLogins() {
    let mine = card(assignees: ["Octocat"], ownLogins: ["octocat"])
    let theirs = card(assignees: ["mona"], ownLogins: ["octocat"])
    #expect(holds(condition(.assignee, .is, "@me"), for: mine))
    #expect(!holds(condition(.assignee, .is, "@me"), for: theirs))
    // A notification can't tell whose it is.
    #expect(!holds(condition(.author, .is, "@me"), for: item(author: "octocat")))
  }

  @Test func negationInvertsTheOutcome() {
    let subject = item(repo: "acme/app")
    #expect(!holds(condition(.repo, .is, "acme/app", negated: true), for: subject))
    #expect(holds(condition(.repo, .is, "acme/web", negated: true), for: subject))
    #expect(holds(condition(.title, .contains, "tea", negated: true), for: subject))
  }

  @Test func flagsIgnoreOperatorAndValue() {
    #expect(holds(condition(.mention, .contains, "anything"), for: item(mention: true)))
    #expect(!holds(condition(.mention), for: item(mention: false)))
    #expect(holds(condition(.mention, negated: true), for: item(mention: false)))
    #expect(holds(condition(.unread), for: item(read: false)))
    #expect(!holds(condition(.unread), for: card(items: [item(read: true)])))
  }

  @Test func severalValuesHoldWhenAnyOneDoes() {
    let subject = item(upstreamLabels: ["backend", "urgent"])
    #expect(holds(condition(.upstreamLabel, .is, "urgent"), for: subject))
    #expect(!holds(condition(.upstreamLabel, .is, "frontend"), for: subject))
    #expect(holds(condition(.reviewer, .is, "kim"), for: card(reviewers: ["mona", "kim"])))
  }

  @Test func statusHoldsOnItsStageOrItsOwnName() {
    let reviewing = card(status: WorkStatus(name: "In review", stage: "in_progress"))
    #expect(holds(condition(.status, .is, "in_progress"), for: reviewing))
    #expect(holds(condition(.status, .is, "in review"), for: reviewing))
    #expect(holds(condition(.status, .contains, "review"), for: reviewing))
    #expect(!holds(condition(.status, .is, "todo"), for: reviewing))
    // A status whose stage the provider left unsaid still answers to its name.
    let custom = card(status: WorkStatus(name: "QA", stage: nil))
    #expect(holds(condition(.status, .is, "qa"), for: custom))
    #expect(!holds(condition(.status, .is, "in_progress"), for: custom))
    #expect(!holds(condition(.status, .exists), for: card()))
  }

  @Test func dueDateHoldsOnTheDayOrHowItStands() {
    let now = referenceDate
    let today = card(dueDate: isoDay(0, from: now), now: now)
    #expect(holds(condition(.dueDate, .exists), for: today))
    #expect(holds(condition(.dueDate, .is, "today"), for: today))
    #expect(holds(condition(.dueDate, .is, isoDay(0, from: now)), for: today))
    #expect(!holds(condition(.dueDate, .is, "overdue"), for: today))
    #expect(holds(condition(.dueDate, .is, "overdue"), for: card(dueDate: isoDay(-3, from: now), now: now)))
    #expect(!holds(condition(.dueDate, .exists), for: card()))
  }

  @Test func cardFieldsReadNothingOnANotification() {
    #expect(!holds(condition(.assignee, .exists), for: item()))
  }
}
