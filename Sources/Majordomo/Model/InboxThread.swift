// Thread grouping: notifications pointing at the same target collapse
// into one entry. A provider can hand back several items for one
// issue or MR (GitLab creates a todo per mention, review request, and
// assignment); the target — not the notification — is what the user thinks
// of as "the thing".

import Foundation

/// One inbox entry: every item on one target, in the order they were given
/// (callers pass display-ordered items, so the lead is the top-ranked one).
struct InboxThread: Identifiable, Sendable {
  /// The shared target key — see `threadId(for:)`.
  let id: String
  var items: [InboxItem]

  /// The member the entry is presented as (title, capsule, meta).
  var lead: InboxItem { items[0] }
  /// Read only when every member is.
  var read: Bool { items.allSatisfy(\.read) }
  /// Unread and in play: a member that is (`InboxItem.pending`).
  var pending: Bool { items.contains(where: \.pending) }
  var itemIds: [String] { items.map(\.id) }
  /// Quiet as a whole: every member snoozed.
  var snoozed: Bool { items.allSatisfy { $0.snoozedUntil != nil } }
  /// When the thread comes back, if it is put away: the latest of its
  /// members' times.
  var snoozedUntil: Date? { snoozed ? items.compactMap(\.snoozedUntil).max() : nil }
}

/// The target an item points at: its url with the fragment stripped (a
/// GitLab mention todo anchors "#note_…", GitHub appends "#issuecomment-…" —
/// both address the same page), scoped to the account. The title joins the
/// key because items without a subject page fall back to a repo-level url
/// (GitHub discussions, security alerts) — the title keeps unrelated ones
/// apart.
func threadId(for item: InboxItem) -> String {
  threadId(accountId: item.accountId, url: item.url, title: item.title)
}

/// The same key from an item's parts, for the store's own records.
func threadId(accountId: AccountId, url: String, title: String) -> String {
  let target = url.prefix { $0 != "#" }
  return "\(accountId):\(target):\(title)"
}

/// Resolves selected row ids against the visible threads: a thread id
/// selects the whole thread; a member's item id (an expanded row) selects
/// just that member, wrapped as a single-item thread — unless its thread is
/// itself selected, which covers it already.
func resolveSelection(in threads: [InboxThread], ids: Set<String>) -> [InboxThread] {
  threads.flatMap { thread -> [InboxThread] in
    if ids.contains(thread.id) {
      return [thread]
    }
    return thread.items
      .filter { ids.contains($0.id) }
      .map { InboxThread(id: $0.id, items: [$0]) }
  }
}

/// Groups items into threads, preserving the given order: a thread sits
/// where its first (best-ranked) member sat, and keeps its members in the
/// order they arrived.
func groupIntoThreads(_ items: [InboxItem]) -> [InboxThread] {
  var order: [String] = []
  var members: [String: [InboxItem]] = [:]
  for item in items {
    let id = threadId(for: item)
    if members[id] == nil {
      order.append(id)
    }
    members[id, default: []].append(item)
  }
  return order.map { InboxThread(id: $0, items: members[$0]!) }
}
