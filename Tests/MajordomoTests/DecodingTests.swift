// Every stored shape still reads: rules stored flat (conditions with a
// match, or a prompt the model answered), columns stored as ways in, a
// board scope stored as one group, and answers stored by the id of the
// rule that asked — and the new shapes round-trip.

import Foundation
import Testing
@testable import Majordomo

@Suite("Stored shapes")
struct DecodingTests {
  private let repoCondition = #"{"field":"repo","op":"is","value":"acme/infra","negated":false}"#
  private let reasonCondition = #"{"field":"reason","op":"is","value":"mentioned","negated":true}"#

  @Test func flatRuleBecomesOneGroup() throws {
    let rule = try decode(LabelRule.self, """
      {"id":"r","name":"Infra","match":"any","conditions":[\(repoCondition),\(reasonCondition)],"labelIds":["l"]}
      """)
    #expect(rule.filter == RuleFilter(match: .any, groups: [
      RuleGroup(match: .any, conditions: [
        condition(.repo, .is, "acme/infra"), condition(.reason, .is, "mentioned", negated: true),
      ]),
    ]))
    #expect(rule.labelIds == ["l"])
    #expect(rule.enabled && !rule.movesItems && !rule.pinsToTop)
  }

  @Test func flatRuleWithoutMatchRequiresEveryCondition() throws {
    let rule = try decode(LabelRule.self, """
      {"id":"r","name":"Infra","conditions":[\(repoCondition)],"labelIds":[]}
      """)
    #expect(rule.filter.groups.map(\.match) == [.all])
    let empty = try decode(LabelRule.self, #"{"id":"r","name":"Draft","conditions":[],"labelIds":[]}"#)
    #expect(empty.filter.isEmpty)
  }

  @Test func ruleTheModelDecidedBecomesAQuestion() throws {
    let rule = try decode(LabelRule.self, """
      {"id":"r","name":"Priority","judge":"intelligence","match":"all","conditions":[\(repoCondition)],
       "prompt":"  Needs me today? ","labelIds":["p"],"pinsToTop":true}
      """)
    #expect(rule.filter.conditions == [.question("  Needs me today? ")])
    #expect(rule.filter.conditions.first?.question == "Needs me today?")
    #expect(rule.pinsToTop)
  }

  @Test func ruleDecidedByConditionsDropsItsUnusedPrompt() throws {
    let rule = try decode(LabelRule.self, """
      {"id":"r","name":"R","judge":"conditions","conditions":[\(repoCondition)],"prompt":"unused","labelIds":[]}
      """)
    #expect(!rule.filter.asksModel)
    #expect(rule.filter.conditions == [condition(.repo, .is, "acme/infra")])
  }

  @Test func ruleRoundTripsInItsNewShape() throws {
    let rule = LabelRule(
      id: "r", name: "Ops",
      filter: filter(.all, group(.any, condition(.repo, .is, "acme/*")), group(.all, .question("Urgent?"))),
      labelIds: ["l"], movesItems: true
    )
    let data = try JSONEncoder().encode(rule)
    let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
    #expect(Set(keys) == ["id", "name", "enabled", "filter", "labelIds", "movesItems", "pinsToTop"])
    #expect(try JSONDecoder().decode(LabelRule.self, from: data) == rule)
  }

  @Test func columnStoredAsWaysInBecomesGroups() throws {
    let column = try decode(BoardColumn.self, """
      {"id":"c","name":"Your Move","rules":[
        {"match":"all","conditions":[\(repoCondition)]},
        {"match":"any","conditions":[\(reasonCondition)]}
      ]}
      """)
    #expect(column.filter == RuleFilter(match: .any, groups: [
      RuleGroup(match: .all, conditions: [condition(.repo, .is, "acme/infra")]),
      RuleGroup(match: .any, conditions: [condition(.reason, .is, "mentioned", negated: true)]),
    ]))
    let byHand = try decode(BoardColumn.self, #"{"id":"c","name":"Parked","rules":[]}"#)
    #expect(byHand.filter.isEmpty)
  }

  @Test func boardStoredWithAOneGroupScope() throws {
    let board = try decode(Board.self, """
      {"id":"b","name":"Work","symbol":"eye","lanes":"repository","doneDays":3,"pins":{},
       "scope":{"match":"all","conditions":[\(repoCondition)]},
       "columns":[{"id":"c","name":"C","rules":[{"match":"all","conditions":[\(reasonCondition)]}]}]}
      """)
    #expect(board.scope == RuleFilter(match: .any, groups: [
      RuleGroup(match: .all, conditions: [condition(.repo, .is, "acme/infra")]),
    ]))
    #expect(board.columns.map(\.filter.groups.count) == [1])
    #expect(board.lanes == .repository && board.doneDays == 3)
    // Stored before boards could gather the unread.
    #expect(!board.unreadLane)
    let everything = try decode(Board.self, """
      {"id":"b","name":"All","symbol":"eye","lanes":"none","doneDays":7,"pins":{},
       "scope":{"match":"all","conditions":[]},"columns":[]}
      """)
    #expect(everything.scope.isEmpty)
  }

  @Test func boardRoundTripsInItsNewShape() throws {
    var board = GitForgeBoards.myWork
    board.scope = filter(.any, group(.all, condition(.kind, .is, "pull")), group(.all, .question("Risky?")))
    board.unreadLane = true
    let decoded = try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board))
    #expect(decoded == board)
  }

  /// An item stored when answers were kept by rule id, with the answer the
  /// starter rule's prompt was given.
  private func legacyItem(prompt: String, matched: Bool) -> String {
    let fingerprint = textFingerprint(prompt)
    return """
      {"id":"acct:1","accountId":"acct","provider":"github","kind":"issue","title":"Crash","repo":"acme/app",
       "url":"https://github.com/acme/app/issues/1","reason":"mentioned","isMention":true,
       "updatedAt":0,"read":false,"firstSeenAt":0,"lastSeenUpstreamAt":0,
       "verdicts":{"starter-priority-rule":{"matched":\(matched),"question":"\(fingerprint)","text":"abc"}}}
      """
  }

  @Test func answersStoredByRuleIdComeBackByQuestion() throws {
    let prompt = "Needs my attention today?"
    let stored = try decode(StoredItem.self, legacyItem(prompt: prompt, matched: true))
    #expect(Array(stored.verdicts.keys) == [RuleEngine.questionKey(prompt)])
    // Re-keying is idempotent: the new shape reads back the same.
    let again = try JSONDecoder().decode(StoredItem.self, from: JSONEncoder().encode(stored))
    #expect(again.verdicts == stored.verdicts)
  }

  @Test func aMigratedRuleReadsItsMigratedAnswer() throws {
    let prompt = "Needs my attention today?"
    let rule = try decode(LabelRule.self, """
      {"id":"starter-priority-rule","name":"Priority","judge":"intelligence","conditions":[],
       "prompt":"\(prompt)","labelIds":["starter-priority"]}
      """)
    let yes = try decode(StoredItem.self, legacyItem(prompt: prompt, matched: true)).inboxItem(existingLabels: [])
    let no = try decode(StoredItem.self, legacyItem(prompt: prompt, matched: false)).inboxItem(existingLabels: [])
    #expect(RuleEngine.matches(rule.filter, yes))
    #expect(!RuleEngine.matches(rule.filter, no))
  }

  @Test func aDayComparisonRoundTrips() throws {
    let stored = try decode(RuleCondition.self, #"{"field":"dueDate","op":"before","value":"in 7 days","negated":false}"#)
    #expect(stored == condition(.dueDate, .before, "in 7 days"))
  }

  @Test func snapshotFromBeforeStatusesStillReads() throws {
    let snapshot = try decode(TargetSnapshot.self, """
      {"title":"Importer","state":"open","assignees":[],"reviewers":[],"labels":[],"updatedAt":0}
      """)
    #expect(snapshot.status == nil)
    let status = WorkStatus(name: "In review", stage: "in_progress")
    let stored = try JSONEncoder().encode(TargetSnapshot(title: "Importer", status: status, updatedAt: referenceDate))
    #expect(try decode(TargetSnapshot.self, String(decoding: stored, as: UTF8.self)).status == status)
  }
}
