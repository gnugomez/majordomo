// JSON persistence for accounts and the app's own persistent item collection
// (upstream disappearance is a read signal, never a delete — see SyncEngine).
// Tokens are stored in the JSON too, AES-GCM-encrypted (see TokenCipher).
// Accounts are keyed by AccountId, any number per provider.

import Foundation
import os

private let log = Logger(subsystem: "dev.majordomo.app", category: "store")

/// Read items vanish this long after upstream last mentioned them.
private let retainReadSeconds: TimeInterval = 30 * 24 * 60 * 60
/// Hard cap on the collection; oldest (read first) beyond it are dropped.
private let itemsCap = 500

/// A FetchedItem the app has adopted into its own collection. The transient
/// upstreamRead signal is consumed at upsert and never persisted.
struct StoredItem: Codable, Sendable {
  var id: String
  var accountId: AccountId
  var provider: ProviderId
  var kind: String
  var title: String
  var repo: String
  var url: String
  var reason: String
  var isMention: Bool
  var updatedAt: Date
  var state: String?
  var author: String?
  var body: String?
  var read: Bool
  /// When this item first entered the collection.
  var firstSeenAt: Date
  /// The last sync in which upstream still returned the item.
  var lastSeenUpstreamAt: Date

  var inboxItem: InboxItem {
    InboxItem(
      id: id, accountId: accountId, provider: provider, kind: kind,
      title: title, repo: repo, url: url, reason: reason, isMention: isMention,
      updatedAt: updatedAt, state: state, author: author, body: body, read: read
    )
  }
}

struct StoredAccount: Codable {
  var provider: ProviderId
  /// Base64 of the AES-GCM-sealed token, or the plaintext token.
  var token: String?
  var tokenEncrypted: Bool?
  var baseUrl: String?
  var username: String?
  var name: String?
  var avatarUrl: String?
  /// Orders the accounts list.
  var createdAt: Date?
}

struct StoreFile: Codable {
  var accounts: [String: StoredAccount] = [:]
  var items: [String: StoredItem] = [:]
}

struct StoredAccountInfo {
  let id: AccountId
  let provider: ProviderId
  /// nil when the stored token can't be read (Keychain denied) — the
  /// account still lists, but can't sync until reconnected.
  var config: AccountConfig?
  var username: String?
  var name: String?
  var avatarUrl: String?
  var baseUrl: String?
}

/// Not Sendable by design: owned and accessed exclusively by the SyncEngine
/// actor.
final class Store {
  private let fileURL: URL
  /// False for the in-memory fixture store (MAJORDOMO_DEMO) — nothing is
  /// ever written.
  private let persistent: Bool
  private var data = StoreFile()
  /// Lazy so a demo run (plaintext fixture tokens) never touches the
  /// Keychain at all.
  private lazy var key = TokenCipher.loadOrCreateKey()
  /// Decoded tokens, memoized so decryption runs once per account per run.
  private var tokenCache: [AccountId: String] = [:]

  /// ISO 8601 both ways; decoding tolerates fractional seconds.
  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let raw = try decoder.singleValueContainer().decode(String.self)
      guard let date = ISODate.parse(raw) else {
        throw DecodingError.dataCorrupted(.init(
          codingPath: decoder.codingPath,
          debugDescription: "unparseable date: \(raw)"
        ))
      }
      return date
    }
    return decoder
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(ISODate.format(date))
    }
    return encoder
  }

  /// An in-memory store seeded with fixtures; nothing persists.
  init(fixture: StoreFile) {
    fileURL = URL(fileURLWithPath: "/dev/null")
    persistent = false
    data = fixture
  }

  init(directory: URL? = nil) {
    persistent = true
    let base = directory ?? FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "Majordomo")
    fileURL = base.appending(path: "majordomo.json")
    if let raw = try? Data(contentsOf: fileURL) {
      if let parsed = try? Self.decoder().decode(StoreFile.self, from: raw) {
        data = parsed
      } else {
        // An unreadable store must never be silently clobbered by the next
        // save — park a copy for recovery, then start fresh.
        let parked = fileURL.appendingPathExtension("corrupt")
        try? raw.write(to: parked, options: .atomic)
        log.error("store unreadable; original preserved as \(parked.lastPathComponent, privacy: .public)")
      }
    }
    // Missing file — start fresh.
  }

  private func save() {
    guard persistent else {
      return
    }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Self.encoder().encode(data).write(to: fileURL, options: .atomic)
    } catch {
      log.error("failed to save store: \(error)")
    }
  }

  private func decodeToken(_ stored: StoredAccount) -> String? {
    guard let token = stored.token else { return nil }
    guard stored.tokenEncrypted == true else { return token }
    guard let key else { return nil }
    return TokenCipher.decrypt(token, key: key)
  }

  // MARK: Accounts

  private func info(id: AccountId, _ stored: StoredAccount) -> StoredAccountInfo {
    var config: AccountConfig?
    if let cached = tokenCache[id] {
      config = AccountConfig(token: cached, baseUrl: stored.baseUrl)
    } else if let decoded = decodeToken(stored) {
      tokenCache[id] = decoded
      config = AccountConfig(token: decoded, baseUrl: stored.baseUrl)
    }
    return StoredAccountInfo(
      id: id,
      provider: stored.provider,
      config: config,
      username: stored.username,
      name: stored.name,
      avatarUrl: stored.avatarUrl,
      baseUrl: stored.baseUrl
    )
  }

  /// Every stored account, oldest first.
  func accounts() -> [StoredAccountInfo] {
    data.accounts
      .sorted { a, b in
        let left = a.value.createdAt ?? .distantPast
        let right = b.value.createdAt ?? .distantPast
        if left != right {
          return left < right
        }
        return a.key < b.key
      }
      .map { info(id: $0.key, $0.value) }
  }

  func getAccount(_ id: AccountId) -> StoredAccountInfo? {
    guard let stored = data.accounts[id] else { return nil }
    return info(id: id, stored)
  }

  func setAccount(
    _ id: AccountId, provider: ProviderId, config: AccountConfig, profile: ProviderProfile
  ) {
    var account = StoredAccount(
      provider: provider,
      baseUrl: config.baseUrl,
      username: profile.username,
      name: profile.name,
      avatarUrl: profile.avatarUrl,
      createdAt: data.accounts[id]?.createdAt ?? Date()
    )
    if let key, let sealed = TokenCipher.encrypt(config.token, key: key) {
      account.token = sealed
      account.tokenEncrypted = true
    } else {
      account.token = config.token
      account.tokenEncrypted = false
    }
    tokenCache[id] = config.token
    data.accounts[id] = account
    save()
  }

  /// Refreshes the owner's profile fields without touching the token.
  func updateProfile(_ id: AccountId, profile: ProviderProfile) {
    guard var account = data.accounts[id] else {
      return
    }
    account.username = profile.username
    account.name = profile.name
    account.avatarUrl = profile.avatarUrl
    data.accounts[id] = account
    save()
  }

  func deleteAccount(_ id: AccountId) {
    tokenCache.removeValue(forKey: id)
    data.accounts.removeValue(forKey: id)
    save()
  }

  // MARK: Items

  func getItems() -> [StoredItem] {
    Array(data.items.values)
  }

  /// Adopts new items (unread) and refreshes known ones (fields updated,
  /// lastSeenUpstreamAt bumped, local read preserved). Item ids compose as
  /// "\(accountId):\(externalId)". Returns the ids new to the collection.
  func upsertItems(
    _ items: [FetchedItem], accountId: AccountId, provider: ProviderId
  ) -> [String] {
    guard !items.isEmpty else { return [] }
    let now = Date()
    var newIds: [String] = []
    for fetched in items {
      let id = "\(accountId):\(fetched.externalId)"
      let existing = data.items[id]
      if existing == nil {
        newIds.append(id)
      }
      data.items[id] = StoredItem(
        id: id,
        accountId: accountId,
        provider: provider,
        kind: fetched.kind,
        title: fetched.title,
        repo: fetched.repo,
        url: fetched.url,
        reason: fetched.reason,
        isMention: fetched.isMention,
        updatedAt: fetched.updatedAt,
        // Enriched fields can be absent on rounds where the provider
        // skipped the lookup — never forget what a prior sync learned.
        state: fetched.state ?? existing?.state,
        author: fetched.author ?? existing?.author,
        body: fetched.body ?? existing?.body,
        // Local read state only ever moves toward read: the user reading it
        // here or upstream both count, and nothing un-reads an item.
        read: (existing?.read ?? false) || fetched.upstreamRead == true,
        firstSeenAt: existing?.firstSeenAt ?? now,
        lastSeenUpstreamAt: now
      )
    }
    save()
    return newIds
  }

  func markRead(_ ids: [String]) {
    var changed = false
    for id in ids {
      if let item = data.items[id], !item.read {
        data.items[id]?.read = true
        changed = true
      }
    }
    if changed {
      save()
    }
  }

  func markAllRead() {
    var changed = false
    for (id, item) in data.items where !item.read {
      data.items[id]?.read = true
      changed = true
    }
    if changed {
      save()
    }
  }

  /// Removes a disconnected account's items immediately.
  func deleteAccountItems(_ accountId: AccountId) {
    let before = data.items.count
    data.items = data.items.filter { $0.value.accountId != accountId }
    if data.items.count != before {
      save()
    }
  }

  /// Retention: drops read items unseen upstream for 30 days, then enforces
  /// the 500-item cap (oldest by updatedAt go first, read before unread).
  func prune() {
    var changed = false
    let cutoff = Date().addingTimeInterval(-retainReadSeconds)
    for (id, item) in data.items where item.read && item.lastSeenUpstreamAt < cutoff {
      data.items.removeValue(forKey: id)
      changed = true
    }
    let excess = data.items.count - itemsCap
    if excess > 0 {
      let victims = data.items.values
        .sorted { a, b in
          if a.read != b.read {
            return a.read
          }
          return a.updatedAt < b.updatedAt
        }
        .prefix(excess)
      for victim in victims {
        data.items.removeValue(forKey: victim.id)
      }
      changed = true
    }
    if changed {
      save()
    }
  }
}
