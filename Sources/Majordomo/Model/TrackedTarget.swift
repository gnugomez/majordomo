// Targets the app keeps track of beyond its notifications: the issue or
// pull request itself, as its provider last described it. Boards are built
// from these — one card per target, however many notifications point at
// it — and the sync engine refreshes them on a schedule of their own. The
// record holds the facts a card shows and a column tests; the target's
// conversation, which the preview shows, comes with the same refresh and
// is kept apart (TargetConversation).

import Foundation

/// What a provider says about a target right now. Review, checks, and
/// merge are provider tokens like kind and state: the spec renders them,
/// and the core only compares them.
struct TargetSnapshot: Codable, Hashable, Sendable {
  var title: String
  var state: String?
  var author: String?
  var assignees: [String] = []
  /// Reviewers asked who haven't answered yet.
  var reviewers: [String] = []
  /// The target's own labels.
  var labels: [String] = []
  var milestone: String?
  /// Where review stands ("approved", "changes_requested"…).
  var review: String?
  /// Where the latest checks stand ("success", "failure", "pending").
  var checks: String?
  /// Whether it could be merged right now ("conflicts", "ready"…); nil
  /// for what isn't open for merging, or while the provider can't tell.
  var merge: String? = nil
  /// Comments by people, when the provider counts them.
  var commentCount: Int?
  /// Whoever wrote the latest comment or review.
  var lastCommenter: String?
  /// The target's own last activity.
  var updatedAt: Date
}

/// One target the app tracks, keyed by the url its notifications share
/// (fragment stripped) — one record across every account that reaches it.
struct TrackedTarget: Codable, Hashable, Sendable {
  let key: String
  var provider: ProviderId
  /// The latest refresh's answer; nil until one lands, and kept when a
  /// later one fails.
  var snapshot: TargetSnapshot?
  /// When a refresh last asked about the target, answered or not.
  var fetchedAt: Date?
  /// When the user last had the card open, and how many comments it held
  /// then — what "new since you looked" counts from.
  var seenAt: Date?
  var seenComments: Int?
  /// The target's activity the stored conversation is current as of (the
  /// snapshot's `updatedAt` when it came); nil until one has come.
  var conversationAt: Date?
  /// Why the provider wouldn't show the target at its last refresh —
  /// gone, or out of the token's reach — in words fit to show; nil once
  /// it does.
  var unreadable: String?

  /// Whether the conversation is missing, or older than the target's
  /// last known activity. A target the provider won't show waits for new
  /// activity before it is asked again.
  var wantsConversation: Bool {
    guard unreadable == nil else {
      return false
    }
    guard let conversationAt else {
      return true
    }
    return conversationAt < (snapshot?.updatedAt ?? .distantPast)
  }
}

/// A board's card: one target and every notification pointing at it.
/// What sorting and placing read over and over is worked out once, when
/// the card is made: a board sorts and places thousands of them.
struct BoardCard: Identifiable, Sendable {
  /// The target's key.
  let id: String
  /// The notifications on it, newest first; the lead fronts the card.
  let items: [InboxItem]
  let target: TrackedTarget?
  /// The logins of the accounts its notifications came through.
  let ownLogins: [String]
  /// The latest activity anyone reported: the target's own, or a
  /// notification's when that came later.
  let activityAt: Date
  /// Whether any of its notifications is unread.
  let unread: Bool

  init(id: String, items: [InboxItem], target: TrackedTarget?, ownLogins: [String]) {
    self.id = id
    self.items = items
    self.target = target
    self.ownLogins = ownLogins
    activityAt = max(target?.snapshot?.updatedAt ?? .distantPast, items[0].updatedAt)
    unread = items.contains { !$0.read }
  }

  var lead: InboxItem { items[0] }
  var snapshot: TargetSnapshot? { target?.snapshot }

  var title: String { snapshot?.title ?? lead.title }
  var state: String? { snapshot?.state ?? lead.state }

  /// Comments added since the user last had the card open; nil when they
  /// never did, or nothing is counted.
  var newComments: Int? {
    guard let count = snapshot?.commentCount, let seen = target?.seenComments, count > seen else {
      return nil
    }
    return count - seen
  }

  /// The lead, as the provider's presentation reads it: the target's
  /// current state, title, and author in place of what the notification
  /// carried.
  var presentedItem: InboxItem {
    var item = lead
    item.state = state
    item.title = title
    item.author = snapshot?.author ?? lead.author
    return item
  }
}

extension BoardCard: RuleSubject {
  func values(of field: RuleField) -> [String] {
    let snapshot = snapshot
    switch field {
    case .repo: return [lead.repo]
    case .title: return [title]
    case .body: return [lead.body ?? ""]
    case .author: return [snapshot?.author ?? lead.author ?? ""]
    case .kind: return [lead.kind]
    case .reason: return items.map(\.reason)
    case .state: return [state ?? ""]
    case .provider: return [lead.provider.rawValue]
    case .account: return Array(Set(items.map(\.accountId)))
    case .upstreamLabel: return snapshot?.labels ?? lead.upstreamLabels
    case .assignee: return snapshot?.assignees ?? []
    case .reviewer: return snapshot?.reviewers ?? []
    case .review: return [snapshot?.review ?? ""]
    case .checks: return [snapshot?.checks ?? ""]
    case .milestone: return [snapshot?.milestone ?? ""]
    case .lastCommenter: return [snapshot?.lastCommenter ?? ""]
    case .mention, .unread: return []
    }
  }

  func flag(_ field: RuleField) -> Bool {
    switch field {
    case .mention: items.contains(where: \.isMention)
    case .unread: unread
    default: false
    }
  }
}
