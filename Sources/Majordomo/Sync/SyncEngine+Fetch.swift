// Syncing: every account's inbox fetched at once, reconciled into the
// collection one account at a time, and what the sync brought announced
// once the sweep has labeled it.

import Foundation

let syncInterval: Duration = .seconds(60)
/// The timer syncs at .recent depth; a .full pass — every page — runs on
/// manual refresh and at least this often, so items beyond the recent
/// window surface instead of hiding until the window happens to shift.
private let fullSyncInterval: TimeInterval = 60 * 60
/// New unread items only post a banner while their activity is this fresh.
/// A deep sync can surface months-old backlog in one go — that belongs in
/// the inbox as unread, not in Notification Center as a flood.
private let notifyFreshnessWindow: TimeInterval = 24 * 60 * 60

extension SyncEngine {
  /// Runs a sync, or waits out the one already running.
  func syncNow(depth: FetchDepth) async {
    // Demo mode is fixtures only: a refresh confirms there is nothing to
    // fetch, so the spinner the app showed ahead of it stops.
    guard !offline else {
      record(.syncStatus)
      return
    }
    if let inFlight {
      await inFlight.value
      return
    }
    let task = Task {
      await self.doSync(depth: depth)
    }
    inFlight = task
    await task.value
    inFlight = nil
  }

  /// What the timer owes: .full once fullSyncInterval has elapsed (or never
  /// ran), .recent otherwise.
  func dueDepth() -> FetchDepth {
    guard let lastFullSyncAt else {
      return .full
    }
    return Date().timeIntervalSince(lastFullSyncAt) >= fullSyncInterval ? .full : .recent
  }

  private func doSync(depth: FetchDepth) async {
    syncing = true
    record(.syncStatus)

    // Accounts syncing for the first time seed silently: their entire
    // backlog is standing state, not news. Only accounts that already have
    // items can produce notification-worthy arrivals.
    let seededAccounts = Set(store.getItems().map(\.accountId))
    var changes: Set<EngineChange> = [.syncStatus, .accounts, .synced]

    for (accountId, provider, result) in await fetchAll(depth: depth) {
      // Removed while the fetch was in flight: the account is parked now,
      // and a stale fetch has no business adding to (or bumping) what it
      // parked.
      guard store.getAccount(accountId) != nil else {
        continue
      }
      switch result {
      case let .success(fetch):
        accountWorks(accountId)

        // Reconcile, never replace: the collection is the app's own.
        let added = store.upsertItems(fetch.items, accountId: accountId, provider: provider)
        if !fetch.items.isEmpty {
          changes.insert(.itemContent)
        }
        if seededAccounts.contains(accountId), !added.isEmpty {
          arrivals.append(contentsOf: added)
          changes.insert(.arrivals)
        }

        // Items upstream stopped returning (GitHub's /notifications only
        // lists unread threads, for one) were handled there: mark them read
        // locally. Only a complete fetch proves absence — a capped one
        // can't say whether an item is gone or just beyond the cap.
        if fetch.complete {
          let fetchedIds = Set(fetch.items.map { "\(accountId):\($0.externalId)" })
          let absent = store.getItems()
            .filter { item in
              item.accountId == accountId && !item.read && !fetchedIds.contains(item.id)
            }
            .map(\.id)
          if !absent.isEmpty {
            store.markRead(absent)
            changes.insert(.readState)
          }
        }
      case let .failure(error):
        // Keep this account's items untouched; just surface the error.
        accountFailed(accountId, error)
      }
    }

    lastSyncAt = Date()
    if depth == .full {
      lastFullSyncAt = lastSyncAt
    }
    syncing = false
    // Rules run over the refreshed items before the push and before any
    // banner, so both carry their labels (see EngineChange.synced for what
    // follows every pass).
    record(changes)
  }

  /// Every connected account's inbox, fetched concurrently; the results
  /// are applied serially on the actor.
  private func fetchAll(depth: FetchDepth) async -> [(AccountId, ProviderId, Result<FetchResult, Error>)] {
    await withTaskGroup(of: (AccountId, ProviderId, Result<FetchResult, Error>)?.self) { group in
      for account in store.accounts() {
        guard let client = clients[account.provider], let config = account.config else {
          continue
        }
        let id = account.id
        let provider = account.provider
        group.addTask {
          do {
            return (id, provider, .success(try await client.fetchItems(config, depth: depth)))
          } catch {
            return (id, provider, .failure(error))
          }
        }
      }
      var collected: [(AccountId, ProviderId, Result<FetchResult, Error>)] = []
      for await result in group {
        if let result {
          collected.append(result)
        }
      }
      return collected
    }
  }

  /// The account synced, or took a new token: its error clears, and one
  /// that was failing is announced as working again.
  func accountWorks(_ id: AccountId) {
    guard errors[id] != nil else {
      return
    }
    errors[id] = nil
    emit(.accountRecovered(id))
  }

  /// The account's sync failed: the error shows on it, and is announced
  /// when it is news — the account was working, or failed differently.
  private func accountFailed(_ id: AccountId, _ error: Error) {
    let reason = displayMessage(for: error)
    guard errors[id] != reason else {
      return
    }
    errors[id] = reason
    if (error as? ProviderError)?.rejectsToken == true {
      emit(.tokenRejected(id, reason: reason))
    } else {
      emit(.syncFailed(id, reason: reason))
    }
  }

  /// Announces the fresh unread threads the last sync brought, labeled.
  func announceArrivals() {
    let newIds = arrivals
    arrivals = []
    guard !newIds.isEmpty else {
      return
    }
    let byId = Dictionary(uniqueKeysWithValues: store.inboxItems().map { ($0.id, $0) })
    // Items that arrive already handled upstream don't deserve a ping —
    // nor does old backlog a deep fetch surfaced (it shows up unread in
    // the inbox instead). Which fresh unread ones do is the notification
    // scope setting's call, applied by the app shell.
    let freshCutoff = Date().addingTimeInterval(-notifyFreshnessWindow)
    let fresh = newIds.compactMap { byId[$0] }
      .filter { !$0.read && $0.updatedAt > freshCutoff }
    // One banner per thread: a target arriving as several notifications at
    // once (a GitLab MR mentioning, assigning, and requesting review) pings
    // once. The mention member fronts it so the scope setting sees it.
    let fronts = groupIntoThreads(fresh).map { thread in
      thread.items.first { $0.isMention } ?? thread.lead
    }
    if !fronts.isEmpty {
      emit(.threadsArrived(fronts))
    }
  }
}
