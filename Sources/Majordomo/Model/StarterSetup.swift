// What a store starts with: a Priority label and the intelligence rule
// that fills it, seeded once so the feature arrives configured rather than
// described. Nothing here is privileged afterwards — the prompt, the name,
// the icon, the top box and the rule itself are the user's to edit or
// delete, and nothing puts them back.

import Foundation

enum StarterSetup {
  /// Stable ids: the rule points at the label, and a store that already
  /// holds them is never seeded twice.
  static let priorityLabelId: LabelId = "starter-priority"
  private static let priorityRuleId = "starter-priority-rule"

  static let labels: [InboxLabel] = [
    InboxLabel(
      id: priorityLabelId,
      name: "Priority",
      symbol: "exclamationmark.circle",
      tint: .red,
      notify: .follow,
      order: 0
    ),
  ]

  /// The question is written the way the user would write one, because it
  /// is the example they will edit: a sentence about what matters, not a
  /// specification.
  static let rules: [LabelRule] = [
    LabelRule(
      id: priorityRuleId,
      name: "Priority",
      judge: .intelligence,
      conditions: [],
      prompt: """
      Needs my attention today: someone is blocked on me, I am asked \
      directly for a review, an answer or a decision, or something is \
      broken for users right now.
      """,
      labelIds: [priorityLabelId],
      pinsToTop: true
    ),
  ]
}
