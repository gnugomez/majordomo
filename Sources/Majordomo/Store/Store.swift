// JSON persistence for accounts and the app's own persistent item collection
// (upstream disappearance is a read signal, never a delete — see SyncEngine).
// Tokens are stored in the JSON too, AES-GCM-encrypted (see TokenCipher).
// Accounts are keyed by AccountId, any number per provider. A removed
// account is parked, not erased: its token goes at once, but its record and
// items linger for a while so adding the same account back resumes with the
// read state intact — nothing upstream holds a copy of that. The user's
// labels and rules live here too, next to the per-item assignments they
// govern, as do the summaries the on-device model writes and its answers to
// the rules' questions — kept with the text they were made from, so they
// survive relaunches and go stale only when that text changes. Boards live
// here as well, with the targets they are built from: what each issue or
// pull request looked like at its last refresh, and what the model
// answered about it. The targets' conversations sit beside the store, a
// file each (ConversationFiles): together they outweigh everything else
// here.

import CryptoKit
import Foundation
import os

private let log = Logger(subsystem: "dev.majordomo.app", category: "store")

/// A removed account's record and items stay parked this long, so adding
/// it back resumes where it left off; past it, everything of its is dropped.
private let retainRemovedSeconds: TimeInterval = 90 * 24 * 60 * 60

/// The model's answer to one question about one item or target, kept under
/// the question's key (RuleEngine.questionKey) — which `question` repeats,
/// so the answers re-key themselves on reading. The two fingerprints go
/// stale differently: a reworded question is a different key, and its
/// answers go once no rule or board asks it (pruneVerdicts), while changed
/// text only queues a fresh answer — the last one keeps standing until the
/// model has given a new one.
struct RuleVerdict: Codable, Sendable, Hashable {
  var matched: Bool
  /// Fingerprint of the question that was asked.
  var question: String
  /// Fingerprint of the text it was asked about.
  var text: String
}

/// Answers keyed by their own question fingerprint: what a stored map
/// reads as, whatever it was keyed by when written.
private func keyedByQuestion(_ verdicts: [String: RuleVerdict]) -> [String: RuleVerdict] {
  Dictionary(verdicts.values.map { ($0.question, $0) }) { first, _ in first }
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
  /// What the model answered about the item, by question key.
  var verdicts: [String: RuleVerdict] = [:]

  /// What the model's answers about the item are given for: the title and
  /// the body together, so a comment arriving on a known item is judged
  /// afresh.
  var judgedText: String {
    "\(title)\n\(body ?? "")"
  }

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
  /// with empty assignments instead of failing the whole store. Answers
  /// stored by the id of the rule that asked come back by question key.
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
    verdicts = keyedByQuestion(try container.decodeIfPresent([String: RuleVerdict].self, forKey: .verdicts) ?? [:])
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
  /// The targets boards are built from, by key.
  var targets: [String: TrackedTarget] = [:]
  /// What the model answered about each target, by target key and then
  /// question key — a board's questions are put to a card, not to the
  /// notifications on it.
  var targetVerdicts: [String: [String: RuleVerdict]] = [:]
  /// The user's boards, in sidebar order.
  var boards: [Board] = []
  /// Whether the starter board was ever added — the same once-only rule.
  var boardsSeeded: Bool = false
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
    targets = try container.decodeIfPresent([String: TrackedTarget].self, forKey: .targets) ?? [:]
    targetVerdicts = try container.decodeIfPresent(
      [String: [String: RuleVerdict]].self, forKey: .targetVerdicts
    ) ?? [:]
    boards = try container.decodeIfPresent([Board].self, forKey: .boards) ?? []
    boardsSeeded = try container.decodeIfPresent(Bool.self, forKey: .boardsSeeded) ?? false
  }
}

/// What a stored summary or answer was made from, and the key a question's
/// answers are kept under. Truncated: it only ever has to tell the same
/// text from different text, and the store is a file the app rewrites
/// whole.
func textFingerprint(_ text: String) -> String {
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
  private let conversations: ConversationFiles
  /// Whether this run has cleared out the conversations of targets the
  /// store no longer holds — once, then as targets drop.
  private var conversationsSwept = false
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
  init(fixture: StoreFile, conversations seed: [String: TargetConversation] = [:]) {
    fileURL = URL(fileURLWithPath: "/dev/null")
    persistent = false
    data = fixture
    conversations = ConversationFiles(directory: nil, seed: seed)
  }

  init(directory: URL? = nil) {
    persistent = true
    let base = directory ?? FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "Majordomo")
    fileURL = base.appending(path: "majordomo.json")
    conversations = ConversationFiles(directory: base.appending(path: "Conversations"))
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

  /// One live item as stored.
  func item(_ id: String) -> StoredItem? {
    data.items[id].flatMap { isConnected($0.accountId) ? $0 : nil }
  }

  /// Whether the item lacks a current answer to the question: never asked,
  /// or asked about text that has changed since — the standing answer
  /// keeps showing until a new one comes.
  func itemNeedsVerdict(_ id: String, question key: String) -> Bool {
    guard let item = item(id) else {
      return false
    }
    guard let verdict = item.verdicts[key] else {
      return true
    }
    return verdict.text != textFingerprint(item.judgedText)
  }

  /// The same for a target, judged on `text` (see SyncEngine's judgedText).
  func targetNeedsVerdict(_ key: String, question: String, text: String) -> Bool {
    guard let verdict = data.targetVerdicts[key]?[question] else {
      return true
    }
    return verdict.text != textFingerprint(text)
  }

  /// Every target's answers, by target key and question key.
  func targetVerdicts() -> [String: [String: Bool]] {
    data.targetVerdicts.mapValues { $0.mapValues(\.matched) }
  }

  /// Files a sweep's answers, items' and targets' alike, against the
  /// question asked and the text each was asked about, in one write — see
  /// setSummaries. Items pruned or parked meanwhile are dropped.
  func setVerdicts(
    items: [(id: String, question: String, matched: Bool, text: String)],
    targets: [(key: String, question: String, matched: Bool, text: String)]
  ) {
    var changed = false
    for answer in items where data.items[answer.id] != nil {
      data.items[answer.id]?.verdicts[answer.question] = RuleVerdict(
        matched: answer.matched, question: answer.question, text: textFingerprint(answer.text)
      )
      changed = true
    }
    // A target's answers go with the target (pruneTargets).
    for answer in targets {
      data.targetVerdicts[answer.key, default: [:]][answer.question] = RuleVerdict(
        matched: answer.matched, question: answer.question, text: textFingerprint(answer.text)
      )
      changed = true
    }
    if changed {
      save()
    }
  }

  /// Lets go of the answers to questions nothing asks any more: an answer
  /// belongs to the question it was given for, and a reworded one is
  /// another question.
  func pruneVerdicts(keeping asked: Set<String>) {
    var changed = false
    for (id, item) in data.items {
      let kept = item.verdicts.filter { asked.contains($0.key) }
      if kept.count != item.verdicts.count {
        data.items[id]?.verdicts = kept
        changed = true
      }
    }
    for (key, verdicts) in data.targetVerdicts {
      let kept = verdicts.filter { asked.contains($0.key) }
      if kept.count != verdicts.count {
        data.targetVerdicts[key] = kept.isEmpty ? nil : kept
        changed = true
      }
    }
    if changed {
      save()
    }
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

  /// Replaces the rule set. The answers its questions were given stay
  /// until nothing asks them (pruneVerdicts).
  func setRules(_ rules: [LabelRule]) {
    data.rules = rules
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

  // MARK: Boards

  func boards() -> [Board] {
    data.boards
  }

  func setBoards(_ boards: [Board]) {
    guard data.boards != boards else {
      return
    }
    data.boards = boards
    save()
  }

  /// Adds the starter boards, once — the same rule as the starter labels.
  func seedBoards(_ boards: [Board]) {
    guard !data.boardsSeeded else {
      return
    }
    data.boardsSeeded = true
    let known = Set(data.boards.map(\.id))
    data.boards.append(contentsOf: boards.filter { !known.contains($0.id) })
    save()
  }

  /// Puts a card in a column by hand; nil hands it back to the rules.
  func setPin(board: BoardId, card: String, pin: BoardPin?) {
    guard let index = data.boards.firstIndex(where: { $0.id == board }), data.boards[index].pins[card] != pin else {
      return
    }
    data.boards[index].pins[card] = pin
    save()
  }

  // MARK: Targets

  func targets() -> [String: TrackedTarget] {
    data.targets
  }

  /// A target's stored conversation.
  func conversation(for key: String) -> TargetConversation? {
    conversations.read(key)
  }

  /// Records a refresh round. The snapshots and conversations that came
  /// back replace the old ones, and a target the provider wouldn't show
  /// keeps the last of each with the reason why; both are stamped, so a
  /// target out of reach waits for new activity before it is asked again.
  /// What went unanswered is left as it was, first in line next round.
  func applyTargetRefresh(_ round: TargetRound, providers: [String: ProviderId], at date: Date) {
    guard !round.refreshed.isEmpty || !round.unreadable.isEmpty else {
      return
    }
    func target(_ key: String) -> TrackedTarget? {
      data.targets[key] ?? providers[key].map { TrackedTarget(key: key, provider: $0) }
    }
    for (key, refresh) in round.refreshed {
      guard var target = target(key) else { continue }
      target.snapshot = refresh.snapshot
      target.fetchedAt = date
      target.unreadable = nil
      if let conversation = refresh.conversation {
        conversations.write(conversation, for: key)
        target.conversationAt = refresh.snapshot.updatedAt
      }
      data.targets[key] = target
    }
    for (key, reason) in round.unreadable {
      guard var target = target(key) else { continue }
      target.fetchedAt = date
      target.unreadable = reason
      data.targets[key] = target
    }
    save()
  }

  /// Notes that a target's conversation is no longer held; false when it
  /// wasn't noted as held anyway.
  func forgetConversation(_ key: String) -> Bool {
    guard data.targets[key]?.conversationAt != nil else {
      return false
    }
    data.targets[key]?.conversationAt = nil
    save()
    return true
  }

  /// Forgets why targets couldn't be read, so the next rounds ask after
  /// them again: a new token may reach what the old one couldn't.
  func clearUnreadableTargets() {
    var changed = false
    for (key, target) in data.targets where target.unreadable != nil {
      data.targets[key]?.unreadable = nil
      changed = true
    }
    if changed {
      save()
    }
  }

  /// Notes that the user had the card open: what is new counts from here.
  func markTargetSeen(_ key: String, provider: ProviderId, at date: Date) {
    var target = data.targets[key] ?? TrackedTarget(key: key, provider: provider)
    target.seenAt = date
    target.seenComments = target.snapshot?.commentCount
    data.targets[key] = target
    save()
  }

  /// Drops the targets no live notification points at any more, with
  /// their conversations, the model's answers about them, and the pins of
  /// the cards that went with them.
  func pruneTargets(keeping keys: Set<String>) {
    var changed = false
    for key in data.targets.keys where !keys.contains(key) {
      data.targets.removeValue(forKey: key)
      changed = true
    }
    for key in data.targetVerdicts.keys where !keys.contains(key) {
      data.targetVerdicts.removeValue(forKey: key)
      changed = true
    }
    if changed || !conversationsSwept {
      conversations.keep(only: Set(data.targets.keys))
      conversationsSwept = true
    }
    for index in data.boards.indices {
      let pins = data.boards[index].pins.filter { keys.contains($0.key) }
      if pins.count != data.boards[index].pins.count {
        data.boards[index].pins = pins
        changed = true
      }
    }
    if changed {
      save()
    }
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

  /// Retention covers removed accounts only: parked ones past
  /// retainRemovedSeconds go with everything of theirs, as do items whose
  /// account record is gone. A connected account's items are kept for
  /// good, read or not, so search and the date filter reach its whole
  /// history.
  func prune() {
    var changed = false
    let removedCutoff = Date().addingTimeInterval(-retainRemovedSeconds)
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
    if changed {
      save()
    }
  }
}
