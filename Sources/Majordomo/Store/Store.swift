// JSON persistence for accounts and the app's own persistent item collection
// (upstream disappearance is a read signal, never a delete — see SyncEngine).
// Tokens are stored in the JSON too, AES-GCM-encrypted (see TokenCipher).
// Accounts are keyed by AccountId, any number per provider. A removed
// account is parked, not erased: its token goes at once, but its record and
// items linger for a while so adding the same account back resumes with the
// read state intact — nothing upstream holds a copy of that. The user's
// labels and rules live here too, next to the per-item assignments they
// govern, as do the summaries the on-device model writes — keyed by the
// text they were made from, so they survive relaunches and go stale only
// when that text changes.

import CryptoKit
import Foundation
import os

private let log = Logger(subsystem: "dev.majordomo.app", category: "store")

/// Read items vanish this long after upstream last mentioned them.
private let retainReadSeconds: TimeInterval = 30 * 24 * 60 * 60
/// Hard cap on the collection; oldest (read first) beyond it are dropped.
private let itemsCap = 500
/// A removed account's record and items stay parked this long, so adding
/// it back resumes where it left off; past it, everything of its is dropped.
private let retainRemovedSeconds: TimeInterval = 90 * 24 * 60 * 60

/// The model's answer for one intelligence rule on one item. Both
/// fingerprints matter and they go stale differently: a rewritten question
/// throws the answer away (it was given to a different question), while
/// changed text only queues a fresh one — the last answer keeps standing
/// until the model has given a new one.
struct RuleVerdict: Codable, Sendable, Hashable {
  var matched: Bool
  /// Fingerprint of the question that was asked.
  var question: String
  /// Fingerprint of the text it was asked about.
  var text: String
}

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
  /// The model's one-line summary of the body, and the fingerprint of the
  /// text it was made from: a body that changes earns a fresh one.
  var summary: String?
  var summaryOf: String?
  /// When this item first entered the collection.
  var firstSeenAt: Date
  /// The last sync in which upstream still returned the item.
  var lastSeenUpstreamAt: Date
  /// What the rules assigned on the last sweep.
  var autoLabels: Set<LabelId> = []
  /// Inboxes the rules moved this item out of.
  var hiddenFrom: Set<LabelId> = []
  /// The user's forced-on/forced-off labels, kept apart from autoLabels so
  /// a sweep never undoes them.
  var labelOverrides: LabelOverrides = [:]
  /// Labels the target carries at the provider, as last reported.
  var upstreamLabels: [String]?
  /// What the model answered for each intelligence rule, by rule id.
  var verdicts: [String: RuleVerdict] = [:]

  /// The published shape, with the effective label set resolved against
  /// the labels that exist.
  func inboxItem(existingLabels: Set<LabelId>) -> InboxItem {
    InboxItem(
      id: id, accountId: accountId, provider: provider, kind: kind,
      title: title, repo: repo, url: url, reason: reason, isMention: isMention,
      updatedAt: updatedAt, state: state, author: author, body: body, summary: summary, read: read,
      verdicts: verdicts.mapValues(\.matched),
      labels: effectiveLabels(auto: autoLabels, overrides: labelOverrides, existing: existingLabels),
      hiddenFrom: hiddenFrom,
      upstreamLabels: upstreamLabels ?? []
    )
  }
}

extension StoredItem {
  /// Items written before labels existed lack the label keys; they decode
  /// with empty assignments instead of failing the whole store.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    accountId = try container.decode(AccountId.self, forKey: .accountId)
    provider = try container.decode(ProviderId.self, forKey: .provider)
    kind = try container.decode(String.self, forKey: .kind)
    title = try container.decode(String.self, forKey: .title)
    repo = try container.decode(String.self, forKey: .repo)
    url = try container.decode(String.self, forKey: .url)
    reason = try container.decode(String.self, forKey: .reason)
    isMention = try container.decode(Bool.self, forKey: .isMention)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    state = try container.decodeIfPresent(String.self, forKey: .state)
    author = try container.decodeIfPresent(String.self, forKey: .author)
    body = try container.decodeIfPresent(String.self, forKey: .body)
    read = try container.decode(Bool.self, forKey: .read)
    summary = try container.decodeIfPresent(String.self, forKey: .summary)
    summaryOf = try container.decodeIfPresent(String.self, forKey: .summaryOf)
    firstSeenAt = try container.decode(Date.self, forKey: .firstSeenAt)
    lastSeenUpstreamAt = try container.decode(Date.self, forKey: .lastSeenUpstreamAt)
    autoLabels = try container.decodeIfPresent(Set<LabelId>.self, forKey: .autoLabels) ?? []
    hiddenFrom = try container.decodeIfPresent(Set<LabelId>.self, forKey: .hiddenFrom) ?? []
    labelOverrides = try container.decodeIfPresent(LabelOverrides.self, forKey: .labelOverrides) ?? [:]
    upstreamLabels = try container.decodeIfPresent([String].self, forKey: .upstreamLabels)
    verdicts = try container.decodeIfPresent([String: RuleVerdict].self, forKey: .verdicts) ?? [:]
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
  /// Set when the user removed the account. The token is gone and nothing
  /// syncs, but the record and its items stay parked until
  /// retainRemovedSeconds pass, in case the same account comes back.
  var removedAt: Date?
}

struct StoreFile: Codable {
  var accounts: [String: StoredAccount] = [:]
  var items: [String: StoredItem] = [:]
  var labels: [InboxLabel] = []
  var rules: [LabelRule] = []
  /// The sidebar layout; nil until the first launch that builds one.
  var sidebar: SidebarLayout?
  /// Suggested labels and rules, pending and dismissed alike — a
  /// dismissal is remembered by signature so the same pattern isn't
  /// offered twice.
  var suggestions: [Suggestion] = []
  /// Whether the starter label and rule were ever added. Set the once,
  /// kept forever: deleting what they seeded is final.
  var seeded: Bool = false
}

extension StoreFile {
  /// Stores written before labels existed lack these keys; they decode as
  /// empty rather than failing the whole file.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    accounts = try container.decodeIfPresent([String: StoredAccount].self, forKey: .accounts) ?? [:]
    items = try container.decodeIfPresent([String: StoredItem].self, forKey: .items) ?? [:]
    labels = try container.decodeIfPresent([InboxLabel].self, forKey: .labels) ?? []
    rules = try container.decodeIfPresent([LabelRule].self, forKey: .rules) ?? []
    sidebar = try container.decodeIfPresent(SidebarLayout.self, forKey: .sidebar)
    suggestions = try container.decodeIfPresent([Suggestion].self, forKey: .suggestions) ?? []
    seeded = try container.decodeIfPresent(Bool.self, forKey: .seeded) ?? false
  }
}

/// What a stored summary was made from. Truncated: it only ever has to
/// tell the same text from different text, and the store is a file the app
/// rewrites whole.
private func textFingerprint(_ text: String) -> String {
  let digest = SHA256.hash(data: Data(text.utf8))
  return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
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
  /// Ids of labels defined outside the store — the providers' built-in
  /// ones. The engine sets them so effective label sets keep those
  /// assignments and a user-label edit never scrubs them.
  var builtinLabelIds: Set<LabelId> = []

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

  /// Every connected account, oldest first. Parked (removed) accounts are
  /// nobody's business until they are added back.
  func accounts() -> [StoredAccountInfo] {
    data.accounts
      .filter { $0.value.removedAt == nil }
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

  /// A connected account by id; nil for unknown and parked ones alike.
  func getAccount(_ id: AccountId) -> StoredAccountInfo? {
    guard let stored = data.accounts[id], stored.removedAt == nil else { return nil }
    return info(id: id, stored)
  }

  /// The record for an identity — connected, or removed and still parked —
  /// so a reconnect lands on it instead of starting over. A connected match
  /// wins over a parked one.
  func findAccount(_ identity: AccountIdentity) -> AccountId? {
    let matches = data.accounts.filter { entry in
      guard let username = entry.value.username else {
        return false
      }
      return AccountIdentity(provider: entry.value.provider, baseUrl: entry.value.baseUrl, username: username)
        == identity
    }
    if let connected = matches.first(where: { $0.value.removedAt == nil }) {
      return connected.key
    }
    return matches.max { a, b in
      (a.value.removedAt ?? .distantPast) < (b.value.removedAt ?? .distantPast)
    }?.key
  }

  private func isConnected(_ id: AccountId) -> Bool {
    guard let account = data.accounts[id] else {
      return false
    }
    return account.removedAt == nil
  }

  /// Stores an account's credentials and profile under the id — a new
  /// record, a token swap on a connected one, or the revival of a parked
  /// one (removedAt clears; createdAt and the items carry over).
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

  /// Parks a removed account: the token is forgotten on the spot and it
  /// stops syncing, but the record and its items stay for
  /// retainRemovedSeconds. Read state lives only here — upstream never
  /// learns what was read in the app — so adding the same account back must
  /// find it rather than re-import a year of backlog as unread.
  func removeAccount(_ id: AccountId) {
    tokenCache.removeValue(forKey: id)
    guard var account = data.accounts[id] else {
      return
    }
    account.token = nil
    account.tokenEncrypted = nil
    account.removedAt = Date()
    data.accounts[id] = account
    save()
  }

  // MARK: Items

  /// The live collection: items of connected accounts. A parked account's
  /// items stay in the file but out of sight.
  func getItems() -> [StoredItem] {
    data.items.values.filter { isConnected($0.accountId) }
  }

  /// The live collection in its published shape, effective labels resolved.
  func inboxItems() -> [InboxItem] {
    let existing = labelIds
    return getItems().map { $0.inboxItem(existingLabels: existing) }
  }

  /// One stored item in its published shape.
  func inboxItem(_ stored: StoredItem) -> InboxItem {
    stored.inboxItem(existingLabels: labelIds)
  }

  /// Every label that exists: the user's plus the built-ins.
  private var labelIds: Set<LabelId> {
    Set(data.labels.map(\.id)).union(builtinLabelIds)
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
        // The summary rides along: a text that came back unchanged keeps
        // the line the model already wrote for it, and one that changed is
        // picked up by the next sweep (its fingerprint no longer matches).
        summary: existing?.summary,
        summaryOf: existing?.summaryOf,
        firstSeenAt: existing?.firstSeenAt ?? now,
        lastSeenUpstreamAt: now,
        // Assignments are the rules' and the user's, not the fetch's: they
        // ride along untouched (the sweep right after refreshes autoLabels).
        autoLabels: existing?.autoLabels ?? [],
        hiddenFrom: existing?.hiddenFrom ?? [],
        labelOverrides: existing?.labelOverrides ?? [:],
        upstreamLabels: fetched.upstreamLabels ?? existing?.upstreamLabels,
        // Answers ride along; the text fingerprint inside each one is what
        // decides whether the sweep asks again.
        verdicts: existing?.verdicts ?? [:]
      )
    }
    save()
    return newIds
  }

  // MARK: Summaries

  /// Items whose text has no current summary, worst-missed first: unread
  /// before read, newest before oldest — the order the user reads in, so a
  /// budgeted sweep spends itself on the rows in front of them.
  func itemsNeedingSummary(limit: Int) -> [StoredItem] {
    let queue = getItems()
      .filter { item in
        guard let body = item.body, !body.isEmpty else {
          return false
        }
        return item.summary == nil || item.summaryOf != textFingerprint(body)
      }
      .sorted { a, b in
        if a.read != b.read {
          return b.read
        }
        return a.updatedAt > b.updatedAt
      }
    return Array(queue.prefix(limit))
  }

  /// Files a sweep's summaries against the text each was made from; a
  /// later edit of that text no longer matches, and the next sweep
  /// rewrites it. A batch, because every save rewrites the whole file —
  /// saving per answer rewrote it once for each.
  func setSummaries(_ updates: [(itemId: String, summary: String, text: String)]) {
    var changed = false
    for update in updates where data.items[update.itemId] != nil {
      data.items[update.itemId]?.summary = update.summary
      data.items[update.itemId]?.summaryOf = textFingerprint(update.text)
      changed = true
    }
    if changed {
      save()
    }
  }

  // MARK: Verdicts

  /// Items this rule has no current answer for, worst-missed first: unread
  /// before read, newest before oldest. An item whose text changed since
  /// the answer comes back here too — the standing answer keeps showing
  /// until this returns a new one.
  func itemsNeedingVerdict(rule: String, question: String, limit: Int) -> [StoredItem] {
    let asked = textFingerprint(question)
    let queue = getItems()
      .filter { item in
        guard let verdict = item.verdicts[rule] else {
          return true
        }
        return verdict.question != asked || verdict.text != textFingerprint(itemText(item))
      }
      .sorted { a, b in
        if a.read != b.read {
          return b.read
        }
        return a.updatedAt > b.updatedAt
      }
    return Array(queue.prefix(limit))
  }

  /// Files a sweep's answers against the question asked and the text each
  /// was asked about, in one write — see setSummaries.
  func setVerdicts(_ updates: [(itemId: String, rule: String, matched: Bool, question: String)]) {
    var changed = false
    for update in updates {
      guard let item = data.items[update.itemId] else {
        continue
      }
      data.items[update.itemId]?.verdicts[update.rule] = RuleVerdict(
        matched: update.matched,
        question: textFingerprint(update.question),
        text: textFingerprint(itemText(item))
      )
      changed = true
    }
    if changed {
      save()
    }
  }

  /// What a rule is asked about: the title and the body together, so a
  /// comment arriving on a known item is judged afresh.
  private func itemText(_ item: StoredItem) -> String {
    "\(item.title)\n\(item.body ?? "")"
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

  // MARK: Labels

  /// The user's labels, in folder order.
  func labels() -> [InboxLabel] {
    data.labels.sorted { $0.order < $1.order }
  }

  /// Replaces the user's label set. A label that disappears is scrubbed
  /// from every item's assignments and overrides (parked ones included) and
  /// from every rule, so nothing keeps pointing at it; built-ins stay.
  func setLabels(_ labels: [InboxLabel]) {
    let kept = Set(labels.map(\.id)).union(builtinLabelIds)
    data.labels = labels
    for (id, item) in data.items {
      let auto = item.autoLabels.intersection(kept)
      let overrides = item.labelOverrides.filter { kept.contains($0.key) }
      if auto != item.autoLabels || overrides.count != item.labelOverrides.count {
        data.items[id]?.autoLabels = auto
        data.items[id]?.labelOverrides = overrides
      }
    }
    data.rules = data.rules.map { rule in
      var scrubbed = rule
      scrubbed.labelIds = rule.labelIds.filter { kept.contains($0) }
      return scrubbed
    }
    save()
  }

  /// The user's rules, in evaluation order.
  func rules() -> [LabelRule] {
    data.rules
  }

  /// Replaces the rule set. An answer belongs to the question it was
  /// given for: a rule that is gone, or one whose question was rewritten,
  /// leaves its answers behind rather than carrying a verdict on wording
  /// nobody asked.
  func setRules(_ rules: [LabelRule]) {
    data.rules = rules
    let asked = rules.reduce(into: [String: String]()) { asked, rule in
      if let question = rule.question {
        asked[rule.id] = textFingerprint(question)
      }
    }
    for (id, item) in data.items {
      let kept = item.verdicts.filter { asked[$0.key] == $0.value.question }
      if kept.count != item.verdicts.count {
        data.items[id]?.verdicts = kept
      }
    }
    save()
  }

  // MARK: Starter setup

  /// Adds the app's starting labels and rules, once. A store that has been
  /// seeded is never seeded again, so deleting them is final.
  func seed(labels: [InboxLabel], rules: [LabelRule]) {
    guard !data.seeded else {
      return
    }
    data.seeded = true
    let existing = Set(data.labels.map(\.id))
    let offset = data.labels.count
    for (index, label) in labels.enumerated() where !existing.contains(label.id) {
      var seeded = label
      seeded.order = offset + index
      data.labels.append(seeded)
    }
    let known = Set(data.rules.map(\.id))
    data.rules.append(contentsOf: rules.filter { !known.contains($0.id) })
    save()
  }

  // MARK: Sidebar

  /// The stored sidebar layout, nil before one was ever built.
  func sidebarLayout() -> SidebarLayout? {
    data.sidebar
  }

  func setSidebarLayout(_ layout: SidebarLayout) {
    guard data.sidebar != layout else {
      return
    }
    data.sidebar = layout
    save()
  }

  // MARK: Suggestions

  func suggestions() -> [Suggestion] {
    data.suggestions
  }

  /// Every pattern the user has said no to.
  func dismissedSignatures() -> Set<String> {
    Set(data.suggestions.filter(\.dismissed).map(\.signature))
  }

  /// Adds suggestions whose signature isn't already known, pending or
  /// dismissed — the same pattern is never offered twice.
  func addSuggestions(_ new: [Suggestion]) {
    let known = Set(data.suggestions.map(\.signature))
    let fresh = new.filter { !known.contains($0.signature) }
    guard !fresh.isEmpty else {
      return
    }
    data.suggestions.append(contentsOf: fresh)
    save()
  }

  /// Marks one dismissed; it stays in the file so the pattern behind it
  /// stays quiet.
  func dismissSuggestion(_ id: String) {
    guard let index = data.suggestions.firstIndex(where: { $0.id == id }), !data.suggestions[index].dismissed else {
      return
    }
    data.suggestions[index].dismissed = true
    save()
  }

  /// Drops one outright — what accepting it does, since it becomes a real
  /// rule and has nothing left to say.
  func removeSuggestion(_ id: String) {
    let before = data.suggestions.count
    data.suggestions.removeAll { $0.id == id }
    if data.suggestions.count != before {
      save()
    }
  }

  /// The user's hand on one item: `true` forces the label on, `false` off,
  /// nil hands it back to the rules.
  func setLabelOverride(itemId: String, labelId: LabelId, on: Bool?) {
    guard var item = data.items[itemId] else {
      return
    }
    if let on {
      item.labelOverrides[labelId] = on
    } else {
      item.labelOverrides.removeValue(forKey: labelId)
    }
    data.items[itemId] = item
    save()
  }

  /// A sweep's worth of rule assignments in a single save — the store
  /// writes the whole file each time. Unchanged sets cost nothing.
  func applyAutoLabels(_ updates: [(id: String, labels: Set<LabelId>, hiddenFrom: Set<LabelId>)]) {
    var changed = false
    for update in updates {
      guard let item = data.items[update.id],
            item.autoLabels != update.labels || item.hiddenFrom != update.hiddenFrom else {
        continue
      }
      data.items[update.id]?.autoLabels = update.labels
      data.items[update.id]?.hiddenFrom = update.hiddenFrom
      changed = true
    }
    if changed {
      save()
    }
  }

  func markAllRead() {
    var changed = false
    for (id, item) in data.items where !item.read && isConnected(item.accountId) {
      data.items[id]?.read = true
      changed = true
    }
    if changed {
      save()
    }
  }

  /// Retention, in three passes. Parked accounts past retainRemovedSeconds
  /// go with everything of theirs (as do items whose account record is
  /// gone). Read live items go 30 days after upstream last mentioned them.
  /// Then the cap trims the live collection (oldest by updatedAt first, read
  /// before unread). Parked items sit out the last two passes — they are
  /// being kept precisely for their read state.
  func prune() {
    var changed = false
    let now = Date()
    let removedCutoff = now.addingTimeInterval(-retainRemovedSeconds)
    for (id, account) in data.accounts {
      if let removedAt = account.removedAt, removedAt < removedCutoff {
        data.accounts.removeValue(forKey: id)
        changed = true
      }
    }
    for (id, item) in data.items where data.accounts[item.accountId] == nil {
      data.items.removeValue(forKey: id)
      changed = true
    }
    let readCutoff = now.addingTimeInterval(-retainReadSeconds)
    for (id, item) in data.items
    where isConnected(item.accountId) && item.read && item.lastSeenUpstreamAt < readCutoff {
      data.items.removeValue(forKey: id)
      changed = true
    }
    let live = getItems()
    let excess = live.count - itemsCap
    if excess > 0 {
      let victims = live
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
