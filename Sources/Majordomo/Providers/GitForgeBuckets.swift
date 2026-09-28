// The sidebar buckets every git-forge provider ships — Assigned, Mentions,
// Review requests, Issues, Pull/Merge requests — as built-in labels and the
// rules that fill them. Both forge specs build theirs here so the two stay
// in step; only the wording and the kind/reason tokens differ. Foundation
// only, so the rule sets can be checked outside the app.

import Foundation

enum GitForgeBuckets {
  /// Reasons with a bucket of their own; an item carrying one never falls
  /// through to a kind bucket.
  static let claimedReasons: [String] = ["assigned", "mentioned", "review_requested"]

  /// The five buckets as built-in labels, in sidebar order. Ids are shared
  /// across forges so "All Inboxes" merges them; `pullsName` is the one
  /// wording that differs ("Pull requests" / "Merge requests").
  static func labels(pullsName: String) -> [InboxLabel] {
    [
      builtin("assigned", name: "Assigned", symbol: "person.crop.circle", order: 1),
      builtin("mentions", name: "Mentions", symbol: "at", order: 2),
      builtin("reviews", name: "Review requests", symbol: "eye", order: 3),
      builtin("issues", name: "Issues", symbol: "smallcircle.filled.circle", order: 4),
      builtin("pulls", name: pullsName, symbol: "arrow.triangle.branch", order: 5),
    ]
  }

  /// The rules behind the buckets: one per reason (a bucket fed by several
  /// reasons gets a rule each — rules union), and one per kind bucket that
  /// also excludes every claimed reason. `reviewReasons` and `pullKind` are
  /// the provider's own tokens.
  static func rules(
    provider: ProviderId, reviewReasons: [String], pullKind: String, pullsName: String
  ) -> [LabelRule] {
    let prefix = provider.rawValue
    var rules = [
      rule("\(prefix):assigned", name: "Assigned", [reason("assigned")], label: "assigned"),
      rule("\(prefix):mentions", name: "Mentions", [reason("mentioned")], label: "mentions"),
    ]
    for token in reviewReasons {
      rules.append(rule("\(prefix):reviews:\(token)", name: "Review requests", [reason(token)], label: "reviews"))
    }
    rules.append(rule("\(prefix):issues", name: "Issues", [kind("issue")] + unclaimed, label: "issues"))
    rules.append(rule("\(prefix):pulls", name: pullsName, [kind(pullKind)] + unclaimed, label: "pulls"))
    return rules
  }

  private static func builtin(_ id: LabelId, name: String, symbol: String, order: Int) -> InboxLabel {
    InboxLabel(
      id: id, name: name, symbol: symbol, tint: .accent, notify: .follow, order: order, isBuiltin: true, kind: .inbox
    )
  }

  private static func rule(_ id: String, name: String, _ conditions: [RuleCondition], label: LabelId) -> LabelRule {
    LabelRule(id: id, name: name, conditions: conditions, labelIds: [label])
  }

  private static func reason(_ token: String) -> RuleCondition {
    RuleCondition(field: .reason, op: .is, value: token)
  }

  private static func kind(_ token: String) -> RuleCondition {
    RuleCondition(field: .kind, op: .is, value: token)
  }

  /// "reason is not …" for every claimed reason.
  private static var unclaimed: [RuleCondition] {
    claimedReasons.map { RuleCondition(field: .reason, op: .is, value: $0, negated: true) }
  }
}
