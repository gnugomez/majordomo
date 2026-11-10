// Accounts: connecting one (or the same one again), swapping its token,
// removing it, and keeping its profile fresh. A token taken or forgotten
// goes to disk at once rather than with the next batch of changes: what
// the store holds of credentials never hinges on the app living another
// second.

import Foundation

extension SyncEngine {
  /// The accounts as the state publishes them, each with its error.
  func accountStates() -> [AccountState] {
    store.accounts().map { stored in
      AccountState(
        id: stored.id,
        provider: stored.provider,
        username: stored.username,
        name: stored.name,
        avatarUrl: stored.avatarUrl,
        baseUrl: stored.baseUrl,
        error: errors[stored.id],
        note: stored.note
      )
    }
  }

  /// Validates and stores an account (any number per provider). Returns
  /// nil on success, or the human-readable failure. The same user on the
  /// same instance is the same account: connecting one already connected
  /// swaps in the new token, and connecting one removed earlier revives its
  /// record — items and read state included — instead of starting a
  /// duplicate.
  func connectAccount(_ provider: ProviderId, config: AccountConfig) async -> String? {
    guard let client = clients[provider] else {
      return "Unknown provider."
    }
    do {
      let profile = try await client.validate(config)
      let identity = AccountIdentity(provider: provider, baseUrl: config.baseUrl, username: profile.username)
      let id = store.findAccount(identity) ?? UUID().uuidString
      store.setAccount(id, provider: provider, config: config, profile: profile)
      tokenAccepted(id)
      // Deep from the start: a new account seeds its whole backlog (and
      // silently — see doSync's seeding rule); a revived one catches up on
      // whatever arrived while it was away.
      Task {
        await self.syncNow(depth: .full)
      }
      return nil
    } catch {
      return displayMessage(for: error)
    }
  }

  /// Swaps a connected account's token — the remedy for one that expired
  /// or was revoked. The new token must belong to the same user; the
  /// account's id, items, and read state are untouched. Returns nil on
  /// success, or the human-readable failure.
  func updateToken(_ id: AccountId, token: String) async -> String? {
    guard let account = store.getAccount(id), let client = clients[account.provider] else {
      return "That account is no longer connected."
    }
    let config = AccountConfig(token: token, baseUrl: account.baseUrl)
    do {
      let profile = try await client.validate(config)
      let stored = account.username.map {
        AccountIdentity(provider: account.provider, baseUrl: account.baseUrl, username: $0)
      }
      let offered = AccountIdentity(provider: account.provider, baseUrl: account.baseUrl, username: profile.username)
      if let stored, stored != offered {
        return "That token belongs to @\(profile.username), not @\(account.username ?? "")."
      }
      store.setAccount(id, provider: account.provider, config: config, profile: profile)
      tokenAccepted(id)
      // A dead token may have kept this account from syncing for days:
      // catch up everywhere, not just the recent pages.
      Task {
        await self.syncNow(depth: .full)
      }
      return nil
    } catch {
      return displayMessage(for: error)
    }
  }

  /// A token stored for the account: the targets it couldn't read get
  /// another chance (a new token may reach what the old one couldn't),
  /// and the account's items — a revived account's back in the live set —
  /// are labeled like any fetched ones.
  private func tokenAccepted(_ id: AccountId) {
    store.clearUnreadableTargets()
    store.flush()
    accountWorks(id)
    record([.accounts, .itemContent, .targets])
  }

  /// Removes an account from the app: the token is forgotten now; the
  /// record and its items park in the store (see Store.removeAccount) in
  /// case the same account is added back.
  func disconnectAccount(_ id: AccountId) {
    store.removeAccount(id)
    store.flush()
    errors[id] = nil
    record(.accounts)
  }

  /// Re-reads each account's profile once per launch, backfilling names and
  /// avatars for accounts stored before those existed (and keeping them
  /// fresh after). Failures leave the stored profile untouched.
  func refreshProfiles() async {
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
      record(.accounts)
    }
  }
}
