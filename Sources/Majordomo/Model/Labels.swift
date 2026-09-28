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
}

enum RuleOperator: String, Codable, CaseIterable, Sendable {
  /// Whole-value match, case-insensitive; on `repo` a `*` wildcard is
  /// allowed ("eclipse/*").
  case `is`
  /// Case-insensitive substring.
  case contains
  /// Case-insensitive regular expression, anywhere in the value.
  case matches
}

/// One test inside a rule; a rule holds when every condition holds.
struct RuleCondition: Codable, Hashable, Sendable {
  var field: RuleField
  var op: RuleOperator = .is
  var value: String = ""
  /// Inverts the test ("repo is not …").
  var negated: Bool = false
}

/// How a rule combines its conditions.
enum RuleMatch: String, Codable, CaseIterable, Sendable {
  /// Every condition must hold.
  case all
  /// One condition holding is enough.
  case any
}

/// A logical rule: when its conditions hold for an item — all of them, or
/// any one with `match: .any` — the rule's labels are added to it. Rules
/// are independent — each matching rule contributes, and the item ends up
/// with the union.
struct LabelRule: Identifiable, Codable, Hashable, Sendable {
  var id: String
  var name: String
  var enabled: Bool = true
  var match: RuleMatch = .all
  var conditions: [RuleCondition]
  var labelIds: [LabelId]
  /// Whether a matching item is MOVED rather than copied: it shows only
  /// in what this rule applies, and nowhere else — the catch-all
  /// included.
  var movesItems: Bool = false
}

extension LabelRule {
  private enum CodingKeys: String, CodingKey {
    case id, name, enabled, match, conditions, labelIds, movesItems
  }

  /// Rules stored before `match` or the move fields existed require every
  /// condition and move nothing.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    match = try container.decodeIfPresent(RuleMatch.self, forKey: .match) ?? .all
    conditions = try container.decode([RuleCondition].self, forKey: .conditions)
    labelIds = try container.decode([LabelId].self, forKey: .labelIds)
    movesItems = try container.decodeIfPresent(Bool.self, forKey: .movesItems) ?? false
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
