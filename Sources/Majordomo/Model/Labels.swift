// User-defined labels: the vocabulary the inbox is organized and notified
// by. A label is a named, iconed folder in the sidebar with a notification
// policy of its own. Items acquire labels from logical rules (below), from
// the user's hand, and later from on-device triage — every assigner speaks
// this vocabulary, and everything downstream (folders, badges, banners)
// reads only the item's effective label set. Nothing here imports UI.

import Foundation

typealias LabelId = String

/// How items carrying the label reach Notification Center. When an item
/// carries several labels the strongest policy wins, in the order the
/// cases are declared: urgent over always over never over follow.
enum LabelNotifyPolicy: String, Codable, CaseIterable, Sendable {
  /// The global notification scope decides, as for unlabeled items.
  case follow
  /// A banner regardless of the scope.
  case always
  /// A banner regardless of the scope, delivered time-sensitive so it
  /// breaks through Focus.
  case urgent
  /// No banner, whatever the scope.
  case never

  /// Precedence rank; higher wins when policies conflict.
  var rank: Int {
    switch self {
    case .follow: 0
    case .never: 1
    case .always: 2
    case .urgent: 3
    }
  }

  /// The policy that decides for an item carrying these labels: the
  /// strongest one, or `.follow` when it carries none.
  static func effective(_ policies: some Sequence<LabelNotifyPolicy>) -> LabelNotifyPolicy {
    policies.max { $0.rank < $1.rank } ?? .follow
  }
}

/// A named tint token; the UI maps it to a color per appearance. `accent`
/// follows the system accent — what provider-defined labels use, so their
/// folders keep drawing like the rest of the sidebar.
enum LabelTint: String, Codable, CaseIterable, Sendable {
  case accent, gray, red, orange, yellow, green, teal, blue, indigo, purple, pink, brown
}

/// What a rule target is to the user. Both kinds collect the items rules
/// (and the on-device triage, later) assign them, and both can be inboxes
/// in the sidebar; they differ in presentation.
enum LabelKind: String, Codable, CaseIterable, Sendable {
  /// A tag: a pill on the row, a line in the preview, applied by hand too.
  case label
  /// A bucket: only ever seen as an inbox — the built-in Mentions and
  /// Issues, or one the user creates and feeds with rules.
  case inbox
}

/// One rule target — a label or an inbox, per `kind`. `InboxLabel`, not
/// `Label`: SwiftUI owns that name in every view file. User-defined ones
/// live in the store; a provider's built-in inboxes (Mentions, Issues…)
/// are defined in code by its spec and only differ by `isBuiltin`.
struct InboxLabel: Identifiable, Codable, Hashable, Sendable {
  var id: LabelId
  var name: String
  /// SF Symbol name for the sidebar folder and capsules.
  var symbol: String
  var tint: LabelTint
  var notify: LabelNotifyPolicy
  /// Creation order; the sidebar's own order lives in its layout.
  var order: Int
  /// Defined by a provider spec, not the user: hidable and movable like
  /// any inbox, but never edited.
  var isBuiltin: Bool = false
  var kind: LabelKind = .label
}

extension InboxLabel {
  private enum CodingKeys: String, CodingKey {
    case id, name, symbol, tint, notify, order, isBuiltin, kind
  }

  /// Stored before `isBuiltin` or `kind` existed: a user label.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(LabelId.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    symbol = try container.decode(String.self, forKey: .symbol)
    tint = try container.decode(LabelTint.self, forKey: .tint)
    notify = try container.decode(LabelNotifyPolicy.self, forKey: .notify)
    order = try container.decode(Int.self, forKey: .order)
    isBuiltin = try container.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
    kind = try container.decodeIfPresent(LabelKind.self, forKey: .kind) ?? .label
  }
}

/// The item field a rule condition reads. Token-valued fields (kind,
/// reason, state) compare opaque provider strings the user picked from the
/// provider's own vocabulary; the core never interprets them.
enum RuleField: String, Codable, CaseIterable, Sendable {
  case repo
  case title
  case body
  /// Whoever opened the target.
  case author
  /// The provider token ("issue", "pull", "merge"…).
  case kind
  /// The provider token ("mentioned", "assigned"…).
  case reason
  /// The provider token ("open", "merged"…), when known.
  case state
  case provider
  case account
  /// A label the target carries upstream (an issue's own labels).
  case upstreamLabel
  /// The provider's "needs you" tier; the operator and value are ignored.
  case mention
  // What a board knows about the target itself (TrackedTarget): only its
  // columns test these, since a notification carries none of them.
  /// Someone the target is assigned to.
  case assignee
  /// Someone asked for a review who hasn't given it yet.
  case reviewer
  /// The provider token for where review stands ("approved"…).
  case review
  /// The provider token for where the target's checks stand ("failure"…).
  case checks
  /// The provider token for whether the target can merge ("conflicts"…).
  case merge
  /// Where a work item stands in its workflow: the stage token ("todo",
  /// "in_progress"…) or the status's own name, either holds.
  case status
  case milestone
  /// Whoever wrote the target's latest comment.
  case lastCommenter
  /// Whether any notification on the target is unread; the operator and
  /// value are ignored.
  case unread
  /// A yes-or-no question put to the on-device model: the value is the
  /// question, in the user's words, and the operator is ignored. The
  /// answers are the model's, kept per subject; the condition only reads
  /// them.
  case question
}

extension RuleField {
  /// The fields a notification carries itself — what a label or inbox
  /// rule's condition rows offer.
  static let itemFields: [RuleField] = [
    .repo, .title, .body, .author, .kind, .reason, .state, .provider, .account, .upstreamLabel, .mention,
  ]

  /// Every field a board's card answers — what a board's condition rows
  /// offer. A question comes in through a row of its own, never as a
  /// field to pick.
  static let cardFields: [RuleField] = allCases.filter { $0 != .question }

  /// A yes-or-no test of its own: the operator and value are ignored.
  var isFlag: Bool {
    self == .mention || self == .unread
  }
}

enum RuleOperator: String, Codable, CaseIterable, Sendable {
  /// Whole-value match, case-insensitive; on `repo` a `*` wildcard is
  /// allowed ("eclipse/*"), and `@me` stands for the subject's own login
  /// where it knows one (a board's card does).
  case `is`
  /// Case-insensitive substring.
  case contains
  /// Case-insensitive regular expression, anywhere in the value.
  case matches
  /// The field has any value at all; the value is ignored.
  case exists

  /// What the rule composer may propose: `exists` needs no value, and a
  /// proposal without one reads as a mistake.
  static let composable: [RuleOperator] = [.is, .contains, .matches]
}

/// One test inside a filter's group (RuleFilter).
struct RuleCondition: Codable, Hashable, Sendable {
  var field: RuleField
  var op: RuleOperator = .is
  var value: String = ""
  /// Inverts the test ("repo is not …"); on a question, holds when the
  /// model answered no.
  var negated: Bool = false
}

/// How a group combines its conditions, and a filter its groups.
enum RuleMatch: String, Codable, CaseIterable, Sendable {
  /// Every one must hold.
  case all
  /// One holding is enough.
  case any
}

/// A rule: when its filter holds for an item, its labels are added to it.
/// Rules are independent — each matching rule contributes, and the item
/// ends up with the union.
struct LabelRule: Identifiable, Codable, Hashable, Sendable {
  var id: String
  var name: String
  var enabled: Bool = true
  /// What an item must satisfy. An empty filter matches nothing: a rule
  /// without conditions is a draft, not a catch-all.
  var filter: RuleFilter
  var labelIds: [LabelId]
  /// Whether a matching item is MOVED rather than copied: it shows only
  /// in what this rule applies, and nowhere else — the catch-all
  /// included.
  var movesItems: Bool = false
  /// Whether the labels this rule fills ride at the top of the catch-all,
  /// in a box of their own.
  var pinsToTop: Bool = false
}

extension LabelRule {
  private enum CodingKeys: String, CodingKey {
    case id, name, enabled, filter, labelIds, movesItems, pinsToTop
  }

  /// A rule stored flat: one list of conditions with its match, or — a
  /// rule the model decided — a prompt.
  private enum FlatKeys: String, CodingKey {
    case judge, match, conditions, prompt
  }

  /// Rules stored before the move fields existed move nothing and stay
  /// out of the top box. A rule stored flat becomes a filter of one group:
  /// its conditions, every one required unless it said any — or, when the
  /// model decided it, its prompt as the group's one Apple Intelligence
  /// check.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    if container.contains(.filter) {
      filter = try container.decode(RuleFilter.self, forKey: .filter)
    } else {
      filter = try Self.flatFilter(decoder.container(keyedBy: FlatKeys.self))
    }
    labelIds = try container.decode([LabelId].self, forKey: .labelIds)
    movesItems = try container.decodeIfPresent(Bool.self, forKey: .movesItems) ?? false
    pinsToTop = try container.decodeIfPresent(Bool.self, forKey: .pinsToTop) ?? false
  }

  private static func flatFilter(_ flat: KeyedDecodingContainer<FlatKeys>) throws -> RuleFilter {
    if try flat.decodeIfPresent(String.self, forKey: .judge) == "intelligence" {
      let prompt = try flat.decodeIfPresent(String.self, forKey: .prompt) ?? ""
      return RuleFilter(conditions: [.question(prompt)])
    }
    let match = try flat.decodeIfPresent(RuleMatch.self, forKey: .match) ?? .all
    let conditions = try flat.decodeIfPresent([RuleCondition].self, forKey: .conditions) ?? []
    return RuleFilter(conditions: conditions, match: match)
  }

  /// The inboxes this rule hides a matching item from, given every inbox
  /// that exists: all of them but the ones it fills.
  func hidden(among everyInbox: [LabelId]) -> Set<LabelId> {
    guard movesItems else {
      return []
    }
    return Set(everyInbox).subtracting(labelIds)
  }
}

/// The user's hand on one item's labels, kept apart from what rules
/// compute so re-running rules never undoes it: `true` forces a label on,
/// `false` forces it off, absence defers to the rules.
typealias LabelOverrides = [LabelId: Bool]

/// The label set an item actually carries: what rules assigned, plus the
/// forced-on overrides, minus the forced-off ones — restricted to labels
/// that still exist.
func effectiveLabels(auto: Set<LabelId>, overrides: LabelOverrides, existing: Set<LabelId>) -> Set<LabelId> {
  var labels = auto
  for (id, on) in overrides {
    if on {
      labels.insert(id)
    } else {
      labels.remove(id)
    }
  }
  return labels.intersection(existing)
}
