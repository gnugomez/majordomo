// Targets: what boards and previews are built from — each issue or pull
// request as its last refresh described it, and its conversation —
// refreshed in rounds after every sync, or ahead of them for a preview.

import Foundation

/// An open target is refreshed again this long after its last refresh; a
/// finished one only when new activity arrives.
private let openTargetRefreshInterval: TimeInterval = 15 * 60

extension SyncEngine {
  /// The user had the card open: what is new on it counts from now.
  func markTargetSeen(_ key: String, provider: ProviderId) {
    store.markTargetSeen(key, provider: provider, at: Date())
    record(.targets)
  }

  /// Refreshes the targets that are due, most pressing first: those with
  /// activity since their last refresh (or none yet), newest first; then
  /// those whose conversation is missing or behind their last activity —
  /// the backfill, newest first; then open ones gone stale, longest
  /// waiting first. The first two bring their conversations along. What a
  /// round leaves unanswered — a failure, a limit — is first in line the
  /// next time.
  func refreshTargets() async {
    guard !offline, !refreshingTargets else {
      return
    }
    refreshingTargets = true
    defer { refreshingTargets = false }

    let newest = newestItemsByTarget()
    if store.pruneTargets(keeping: Set(newest.keys)) {
      record(.targets)
    }

    let now = Date()
    let known = store.targets()
    var active: [(key: String, item: InboxItem)] = []
    var behind: [(key: String, item: InboxItem)] = []
    var stale: [(key: String, item: InboxItem, fetchedAt: Date)] = []
    for (key, item) in newest {
      guard let target = known[key], let fetchedAt = target.fetchedAt, fetchedAt >= item.updatedAt else {
        active.append((key, item))
        continue
      }
      if target.wantsConversation {
        behind.append((key, item))
        continue
      }
      let finished = (target.snapshot?.state ?? item.state).map {
        spec(for: item.provider).isFinished(state: $0)
      } ?? false
      if !finished, now.timeIntervalSince(fetchedAt) >= openTargetRefreshInterval {
        stale.append((key, item, fetchedAt))
      }
    }
    active.sort { $0.item.updatedAt > $1.item.updatedAt }
    behind.sort { $0.item.updatedAt > $1.item.updatedAt }
    stale.sort { $0.fetchedAt < $1.fetchedAt }

    let talking = active + behind
    await refresh(talking + stale.map { ($0.key, $0.item) }, conversations: Set(talking.map(\.key)), at: now)
  }

  /// Fetches one target's conversation now, ahead of the rounds — for a
  /// preview opened before they reached it. Returns why it didn't come,
  /// if it didn't; the rounds go on asking either way.
  func refreshConversation(_ key: String) async -> String? {
    guard !offline, let item = newestItemsByTarget()[key] else {
      return nil
    }
    let failure = await refresh([(key, item)], conversations: [key], at: Date())
    guard let target = store.targets()[key], target.conversationAt == nil, target.unreadable == nil else {
      return nil
    }
    return failure ?? "The conversation didn't come through just now."
  }

  /// A target's stored conversation, for the preview. One gone from disk
  /// is forgotten, so the rounds fetch it again.
  func conversation(for key: String) -> TargetConversation? {
    if let conversation = store.conversation(for: key) {
      return conversation
    }
    if store.forgetConversation(key) {
      record(.targets)
    }
    return nil
  }

  /// Each target's newest notification, by key.
  private func newestItemsByTarget() -> [String: InboxItem] {
    var newest: [String: InboxItem] = [:]
    for item in store.inboxItems() {
      guard let key = spec(for: item.provider).boardKey(for: item) else {
        continue
      }
      if let held = newest[key], held.updatedAt >= item.updatedAt {
        continue
      }
      newest[key] = item
    }
    return newest
  }

  /// Asks after `due` in order, each target through the account of its
  /// newest notification and as many as that account's client affords —
  /// the rest wait — with the conversations of those in `conversations`,
  /// and records what came back. Returns why an account's round failed
  /// outright, if one did.
  @discardableResult
  private func refresh(
    _ due: [(key: String, item: InboxItem)], conversations: Set<String>, at date: Date
  ) async -> String? {
    var batches: [AccountId: [String]] = [:]
    var providers: [String: ProviderId] = [:]
    for (key, item) in due {
      guard let client = clients[item.provider],
            batches[item.accountId, default: []].count < client.targetBatchLimit else {
        continue
      }
      batches[item.accountId, default: []].append(key)
      providers[key] = item.provider
    }

    let rounds = await withTaskGroup(of: Result<TargetRound, any Error>.self) { group in
      for (accountId, keys) in batches {
        guard let account = store.getAccount(accountId), let config = account.config,
              let client = clients[account.provider] else {
          continue
        }
        let wanted = conversations.intersection(keys)
        group.addTask {
          do {
            return .success(try await client.fetchTargets(config, keys: keys, conversations: wanted))
          } catch {
            return .failure(error)
          }
        }
      }
      var collected: [Result<TargetRound, any Error>] = []
      for await round in group {
        collected.append(round)
      }
      return collected
    }

    var answer = TargetRound()
    var failure: String?
    for round in rounds {
      switch round {
      case .success(let round):
        answer.refreshed.merge(round.refreshed) { $1 }
        answer.unreadable.merge(round.unreadable) { $1 }
      case .failure(let error):
        failure = failure ?? displayMessage(for: error)
      }
    }
    store.applyTargetRefresh(answer, providers: providers, at: date)
    if !answer.refreshed.isEmpty || !answer.unreadable.isEmpty {
      record(.targets)
    }
    return failure
  }
}
