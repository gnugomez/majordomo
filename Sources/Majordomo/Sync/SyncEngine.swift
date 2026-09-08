// The sync engine: owns the store and the provider clients, reconciles
// fetches into the collection, and publishes AppState snapshots to the UI.
// An actor, so every mutation is serialized. Accounts are plural per
// provider — every stored account syncs through its provider's client.

import AppKit
import Foundation

private let syncInterval: Duration = .seconds(60)

actor SyncEngine {
  private let store: Store
  /// One client per provider implementation, shared by its accounts.
  private let clients: [ProviderId: any ProviderClient]
  /// Pushes a fresh snapshot to the UI (hops to the main actor).
  private let emit: @Sendable (AppState) -> Void
  /// Posts a user notification for a newly arrived unread item.
  private let notify: @Sendable (InboxItem) -> Void

  /// Sync/validation errors per account; the rest of an account's state
  /// reads straight from the store.
  private var errors: [AccountId: String] = [:]
  private var lastSyncAt: Date?
  private var syncing = false
  private var inFlight: Task<Void, Never>?
  private var timer: Task<Void, Never>?

  init(
    emit: @escaping @Sendable (AppState) -> Void,
    notify: @escaping @Sendable (InboxItem) -> Void
  ) {
    self.emit = emit
    self.notify = notify
    store = isDemo ? Store(fixture: DemoData.storeFile()) : Store()
    clients = Dictionary(uniqueKeysWithValues: providerSpecs.map { ($0.id, $0.makeClient()) })
    for account in store.accounts() where account.config == nil {
      errors[account.id] = "The stored token can't be read — remove and re-add the account."
    }
  }

  func getState() -> AppState {
    var items = store.getItems().map(\.inboxItem)
    items.sort { a, b in
      if a.isMention != b.isMention {
        return a.isMention
      }
      return a.updatedAt > b.updatedAt
    }
    let accounts = store.accounts().map { stored in
      AccountState(
        id: stored.id,
        provider: stored.provider,
        username: stored.username,
        name: stored.name,
        avatarUrl: stored.avatarUrl,
        baseUrl: stored.baseUrl,
        error: errors[stored.id]
      )
    }
    return AppState(items: items, accounts: accounts, lastSyncAt: lastSyncAt, syncing: syncing)
  }

  private func emitState() {
    emit(getState())
  }

  private func doSync() async {
    syncing = true
    emitState()

    // Very first sync ever (empty collection): seed without notifying.
    let firstRun = store.getItems().isEmpty
    var newIds: [String] = []

    // Fetches run concurrently; results are applied serially on the actor.
    let results = await withTaskGroup(
      of: (AccountId, ProviderId, Result<FetchResult, Error>)?.self
    ) { group in
      for account in store.accounts() {
        guard let client = clients[account.provider], let config = account.config else {
          continue
        }
        let id = account.id
        let provider = account.provider
        group.addTask {
          do {
            return (id, provider, .success(try await client.fetchItems(config)))
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

    for (accountId, provider, result) in results {
      // Removed while the fetch was in flight: upserting now would
      // resurrect the items deleteAccountItems just removed — as unread
      // orphans nothing would ever prune.
      guard store.getAccount(accountId) != nil else {
        continue
      }
      switch result {
      case let .success(fetch):
        errors[accountId] = nil

        // Reconcile, never replace: the collection is the app's own.
        newIds.append(contentsOf: store.upsertItems(
          fetch.items, accountId: accountId, provider: provider
        ))

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
          }
        }
      case let .failure(error):
        // Keep this account's items untouched; just surface the error.
        errors[accountId] = errorMessage(error)
      }
    }

    if !firstRun, !newIds.isEmpty {
      let byId = Dictionary(uniqueKeysWithValues: store.getItems().map { ($0.id, $0) })
      for id in newIds {
        // Items that arrive already handled upstream don't deserve a ping;
        // which unread ones do is the notification scope setting's call,
        // applied by the app shell.
        if let item = byId[id], !item.read {
          notify(item.inboxItem)
        }
      }
    }

    store.prune()

    lastSyncAt = Date()
    syncing = false
    emitState()
  }

  func syncNow() async {
    if let inFlight {
      await inFlight.value
      return
    }
    let task = Task {
      await self.doSync()
    }
    inFlight = task
    await task.value
    inFlight = nil
  }

  /// Validates and stores a NEW account (multiple per provider are fine).
  /// Returns nil on success, or the human-readable failure.
  func connectAccount(_ provider: ProviderId, config: AccountConfig) async -> String? {
    guard let client = clients[provider] else {
      return "Unknown provider."
    }
    do {
      let profile = try await client.validate(config)
      let id = UUID().uuidString
      store.setAccount(id, provider: provider, config: config, profile: profile)
      emitState()
      Task {
        await self.syncNow()
      }
      return nil
    } catch {
      return errorMessage(error)
    }
  }

  func disconnectAccount(_ id: AccountId) {
    store.deleteAccount(id)
    store.deleteAccountItems(id)
    errors[id] = nil
    emitState()
  }

  /// Opens the item in the browser and marks it read.
  func openItem(id: String) async {
    guard let item = store.getItems().first(where: { $0.id == id }) else {
      return
    }
    if let url = URL(string: item.url) {
      await MainActor.run {
        _ = NSWorkspaceOpener.open(url)
      }
    }
    store.markRead([id])
    emitState()
  }

  func markRead(ids: [String]) {
    store.markRead(ids)
    emitState()
  }

  func markAllRead() {
    store.markAllRead()
    emitState()
  }

  /// Kicks off the first sync and the 60s interval.
  func start() {
    guard timer == nil else { return }
    timer = Task {
      // The stored state first — profile refresh and sync both hit the
      // network, and the UI must not sit empty while they run.
      self.emitState()
      // Demo mode is fixtures only: never touch the network.
      guard !isDemo else { return }
      await self.refreshProfiles()
      await self.syncNow()
      while !Task.isCancelled {
        try? await Task.sleep(for: syncInterval)
        await self.syncNow()
      }
    }
  }

  /// Re-reads each account's profile once per launch, backfilling names and
  /// avatars for accounts stored before those existed (and keeping them
  /// fresh after). Failures leave the stored profile untouched.
  private func refreshProfiles() async {
    var changed = false
    for account in store.accounts() {
      guard let client = clients[account.provider], let config = account.config,
            let profile = try? await client.validate(config) else {
        continue
      }
      store.updateProfile(account.id, profile: profile)
      changed = true
    }
    if changed {
      emitState()
    }
  }
}

private func errorMessage(_ error: Error) -> String {
  if let provider = error as? ProviderError {
    return provider.message
  }
  return error.localizedDescription
}

// AppKit is only touched here, isolated so the engine stays testable.
@MainActor
private enum NSWorkspaceOpener {
  static func open(_ url: URL) -> Bool {
    NSWorkspace.shared.open(url)
  }
}
