// The boards a store starts with, in the git forges' shared tokens: a
// maintainer's whose-move-is-it view, and the pull and merge requests up
// for review. Each is seeded once, like the starter label; from then on it
// is the user's to edit or delete. Columns are read left to right and a
// card takes the first that holds, so the specific signals ("a review is
// waiting on you") come before the broad ones ("assigned to you"). Each
// column's groups are its ways in: any one of them holding takes the card.

import Foundation

enum GitForgeBoards {
  /// Every starter board, in the order a new store lists them.
  static let starters = [myWork, reviews]

  /// What a store that seeded its boards all at once received: the boards
  /// that existed then (see Store.seedBoards).
  static let firstSet: Set<BoardId> = [myWorkId]

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

  static let reviewsId: BoardId = "starter-reviews"

  /// Every pull and merge request, sorted by what its review needs. The
  /// first column puts a question to Apple Intelligence, and asks it only
  /// about the reviews waiting on the user; without the model it takes
  /// nothing, and those cards fall through to Mine to Review.
  static let reviews = Board(
    id: reviewsId,
    name: "Reviews",
    symbol: "eye",
    scope: ways(group(condition(.kind, "pull")), group(condition(.kind, "merge"))),
    columns: [
      BoardColumn(id: "starter-reviews-careful", name: "Careful Look", filter: ways(
        group(
          condition(.reviewer, "@me"),
          .question("Could this change break production — storage, billing, or how things are deployed?")
        )
      )),
      BoardColumn(id: "starter-reviews-mine", name: "Mine to Review", filter: ways(
        group(condition(.reviewer, "@me"))
      )),
      BoardColumn(id: "starter-reviews-ready", name: "Ready", filter: ways(
        group(condition(.review, "approved"))
      )),
    ]
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
