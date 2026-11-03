// The board a store starts with, in the git forges' shared tokens: a
// maintainer's whose-move-is-it view. Seeded once, like the starter label;
// from then on it is the user's to edit or delete. Its columns are read
// left to right and a card takes the first that holds, so the specific
// signals ("a review is waiting on you") come before the broad ones
// ("assigned to you"). Each column's groups are its ways in: any one of
// them holding takes the card.

import Foundation

enum GitForgeBoards {
  static let myWorkId: BoardId = "starter-my-work"

  static let myWork = Board(
    id: myWorkId,
    name: "My Work",
    symbol: "rectangle.split.3x1",
    columns: [
      BoardColumn(id: "starter-triage", name: "Needs Triage", filter: ways(
        group(
          condition(.kind, "issue"),
          RuleCondition(field: .assignee, op: .exists, negated: true),
          RuleCondition(field: .upstreamLabel, op: .exists, negated: true),
          condition(.author, "@me", negated: true)
        )
      )),
      BoardColumn(id: "starter-your-move", name: "Your Move", filter: ways(
        group(condition(.reviewer, "@me")),
        group(condition(.author, "@me"), condition(.review, "changes_requested")),
        group(condition(.author, "@me"), condition(.checks, "failure")),
        group(RuleCondition(field: .unread), RuleCondition(field: .mention)),
        group(
          RuleCondition(field: .unread),
          condition(.assignee, "@me"),
          condition(.lastCommenter, "@me", negated: true)
        ),
        group(
          RuleCondition(field: .unread),
          condition(.author, "@me"),
          RuleCondition(field: .lastCommenter, op: .exists),
          condition(.lastCommenter, "@me", negated: true)
        )
      )),
      BoardColumn(id: "starter-waiting", name: "Waiting on Others", filter: ways(
        group(condition(.author, "@me"), condition(.review, "review_required")),
        group(condition(.lastCommenter, "@me"))
      )),
      BoardColumn(id: "starter-in-progress", name: "In Progress", filter: ways(
        group(condition(.assignee, "@me")),
        group(condition(.author, "@me"))
      )),
    ],
    lanes: .repository
  )

  /// A column's filter: any one of the groups holding takes the card.
  private static func ways(_ groups: RuleGroup...) -> RuleFilter {
    RuleFilter(match: .any, groups: groups)
  }

  private static func group(_ conditions: RuleCondition...) -> RuleGroup {
    RuleGroup(match: .all, conditions: conditions)
  }

  private static func condition(_ field: RuleField, _ value: String, negated: Bool = false) -> RuleCondition {
    RuleCondition(field: field, op: .is, value: value, negated: negated)
  }
}
