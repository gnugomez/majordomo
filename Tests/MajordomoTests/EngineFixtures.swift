// What the engine tests run against: a store of fixtures, a provider
// client that answers from a script, and an on-device model that answers
// every question yes and counts them.

import Foundation
import Synchronization
@testable import Majordomo

let fixtureAccount: AccountId = "acct"

/// A stored item on the fixture account, its target an issue of acme/app.
func storedItem(
  _ number: Int,
  title: String = "Importer crashes on large files",
  repo: String = "acme/app",
  mention: Bool = false,
  read: Bool = false,
  updatedAt: Date = Date()
) -> StoredItem {
  StoredItem(
    id: "\(fixtureAccount):\(number)", accountId: fixtureAccount, provider: .github, kind: "issue", title: title,
    repo: repo, url: "https://github.com/\(repo)/issues/\(number)", reason: "subscribed", isMention: mention,
    updatedAt: updatedAt, state: "open", author: "mona", body: "Body \(number)", read: read,
    firstSeenAt: updatedAt, lastSeenUpstreamAt: updatedAt
  )
}

/// The same item as a provider hands it over.
func fetched(_ item: StoredItem) -> FetchedItem {
  FetchedItem(
    externalId: String(item.id.dropFirst(fixtureAccount.count + 1)), kind: item.kind, title: item.title,
    repo: item.repo, url: item.url, reason: item.reason, isMention: item.isMention, updatedAt: item.updatedAt,
    state: item.state, author: item.author, body: item.body
  )
}

/// A fixture store holding one GitHub account and `items`, without the
/// starter label, rule, and board — the tests set up their own.
func fixtureStore(
  items: [StoredItem] = [], labels: [InboxLabel] = [], rules: [LabelRule] = [], boards: [Board] = []
) -> Store {
  var file = StoreFile()
  file.accounts[fixtureAccount] = StoredAccount(
    provider: .github, token: "token", tokenEncrypted: false, username: "octocat", createdAt: Date()
  )
  file.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
  file.labels = labels
  file.rules = rules
  file.boards = boards
  file.seeded = true
  file.boardsSeeded = true
  return Store(fixture: file)
}

func userLabel(_ id: LabelId) -> InboxLabel {
  InboxLabel(id: id, name: id, symbol: "tag", tint: .blue, notify: .follow, order: 0)
}

/// A provider client whose fetches answer from a script, in order; past
/// its end, an empty capped fetch.
final class ScriptedClient: ProviderClient {
  let id: ProviderId = .github
  let targetBatchLimit = 10
  private let script: Mutex<[Result<FetchResult, ProviderError>]>

  init(_ script: [Result<FetchResult, ProviderError>]) {
    self.script = Mutex(script)
  }

  func validate(_ config: AccountConfig) async throws -> ProviderProfile {
    ProviderProfile(username: "octocat")
  }

  func fetchItems(_ config: AccountConfig, depth: FetchDepth) async throws -> FetchResult {
    let next = script.withLock { $0.isEmpty ? nil : $0.removeFirst() }
    return try (next ?? .success(FetchResult(items: [], complete: false))).get()
  }

  func fetchTargets(_ config: AccountConfig, keys: [String], conversations: Set<String>) async throws -> TargetRound {
    TargetRound()
  }
}

/// An on-device model that answers every question yes, counting them, and
/// writes no summaries.
final class YesModel: IntelligenceProvider {
  private let asked = Mutex(0)

  var questionsAsked: Int {
    asked.withLock { $0 }
  }

  func availability() -> IntelligenceAvailability {
    .available
  }

  func composeRule(from text: String, labels: [InboxLabel]) async throws -> RuleDraft {
    throw IntelligenceError(message: "Not in the tests.")
  }

  func judge(_ candidate: SuggestionCandidate, labels: [InboxLabel]) async throws -> RuleDraft? {
    nil
  }

  func summarize(_ request: SummaryRequest) async throws -> String {
    throw IntelligenceError(message: "Not in the tests.")
  }

  func evaluate(_ request: VerdictRequest) async throws -> Bool {
    asked.withLock { $0 += 1 }
    return true
  }
}

/// Polls until `condition` holds, for up to `timeout`; whether it did.
func eventually(timeout: Duration = .seconds(3), _ condition: () async -> Bool) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if await condition() {
      return true
    }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return await condition()
}

/// Everything a stream yields until it ends.
func collect<Element>(_ stream: AsyncStream<Element>) async -> [Element] {
  var elements: [Element] = []
  for await element in stream {
    elements.append(element)
  }
  return elements
}

extension SyncEngine {
  /// Several reads in one actor turn, each its own mutation.
  func markEachRead(_ ids: [String]) {
    for id in ids {
      markRead(ids: [id])
    }
  }
}
