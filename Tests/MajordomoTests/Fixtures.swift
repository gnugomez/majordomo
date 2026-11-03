// Small builders for the tests: an item, a card, and the conditions and
// filters they are tested against, with everything not under test left at
// a neutral default; and preferences kept in memory.

import Foundation
@testable import Majordomo

let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

/// Preferences kept in memory, so nothing reaches the user's defaults.
final class MemoryDefaults: PreferenceStore {
  private(set) var values: [String: Any] = [:]

  func object(forKey key: String) -> Any? {
    values[key]
  }

  func set(_ value: Any?, forKey key: String) {
    values[key] = value
  }
}

func days(_ count: Double) -> TimeInterval {
  count * 24 * 60 * 60
}

func item(
  _ id: String = "acct:1",
  kind: String = "issue",
  title: String = "Importer crashes on large files",
  repo: String = "acme/app",
  reason: String = "subscribed",
  mention: Bool = false,
  state: String? = "open",
  author: String? = "mona",
  body: String? = nil,
  read: Bool = false,
  updatedAt: Date = referenceDate,
  verdicts: [String: Bool] = [:],
  upstreamLabels: [String] = []
) -> InboxItem {
  InboxItem(
    id: id, accountId: "acct", provider: .github, kind: kind, title: title, repo: repo,
    url: "https://github.com/\(repo)/issues/1", reason: reason, isMention: mention, updatedAt: updatedAt,
    state: state, author: author, body: body, read: read, verdicts: verdicts, upstreamLabels: upstreamLabels
  )
}

func card(
  _ id: String = "card-1",
  items: [InboxItem]? = nil,
  state: String? = "open",
  assignees: [String] = [],
  reviewers: [String] = [],
  review: String? = nil,
  updatedAt: Date = referenceDate,
  ownLogins: [String] = ["octocat"],
  verdicts: [String: Bool] = [:]
) -> BoardCard {
  let members = items ?? [item("\(id):1", state: state, updatedAt: updatedAt)]
  let snapshot = TargetSnapshot(
    title: members[0].title, state: state, author: members[0].author, assignees: assignees,
    reviewers: reviewers, review: review, updatedAt: updatedAt
  )
  let target = TrackedTarget(key: id, provider: .github, snapshot: snapshot)
  return BoardCard(id: id, items: members, target: target, ownLogins: ownLogins, verdicts: verdicts)
}

func condition(
  _ field: RuleField, _ op: RuleOperator = .is, _ value: String = "", negated: Bool = false
) -> RuleCondition {
  RuleCondition(field: field, op: op, value: value, negated: negated)
}

func group(_ match: RuleMatch = .all, _ conditions: RuleCondition...) -> RuleGroup {
  RuleGroup(match: match, conditions: conditions)
}

func filter(_ match: RuleMatch = .any, _ groups: RuleGroup...) -> RuleFilter {
  RuleFilter(match: match, groups: groups)
}

/// Whether a lone condition holds, through the engine's own compilation.
func holds(_ condition: RuleCondition, for subject: some RuleSubject) -> Bool {
  RuleEngine.holds(condition, for: subject)
}

func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
  try JSONDecoder().decode(type, from: Data(json.utf8))
}
