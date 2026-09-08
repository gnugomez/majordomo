// Fixture data for MAJORDOMO_DEMO=1: the app runs against an in-memory
// store full of fictional items and never syncs — for screenshots and UI
// work without real accounts or personal notifications on screen.

import Foundation

/// Demo mode: fixtures instead of the real store, no network, no Keychain.
let isDemo = ProcessInfo.processInfo.environment["MAJORDOMO_DEMO"] != nil

enum DemoData {
  private static let github: AccountId = "demo-github"
  private static let gitlab: AccountId = "demo-gitlab"

  static func storeFile() -> StoreFile {
    let now = Date()

    func item(
      minutesAgo: Double, account: AccountId, provider: ProviderId, kind: String,
      title: String, repo: String, reason: String, mention: Bool = false,
      state: String? = nil, author: String? = nil, body: String? = nil, read: Bool = true
    ) -> StoredItem {
      let date = now.addingTimeInterval(-minutesAgo * 60)
      return StoredItem(
        id: "\(account):\(Int(minutesAgo))", accountId: account, provider: provider,
        kind: kind, title: title, repo: repo, url: "https://example.com",
        reason: reason, isMention: mention, updatedAt: date, state: state,
        author: author, body: body, read: read, firstSeenAt: date, lastSeenUpstreamAt: now
      )
    }

    let items = [
      item(
        minutesAgo: 4, account: github, provider: .github, kind: "pull",
        title: "feat: stream uploads straight to object storage", repo: "acme/atlas",
        reason: "review_requested", mention: true, state: "open", author: "mona",
        body: """
        Uploads no longer buffer to disk — the multipart path is gone and \
        everything streams through `S3TransferManager` directly.

        @octocat mind taking a look at the **retry semantics** before I \
        remove the old code path?
        """,
        read: false
      ),
      item(
        minutesAgo: 26, account: github, provider: .github, kind: "issue",
        title: "Importer crashes on SVG files over 2 GB", repo: "acme/vector-kit",
        reason: "mentioned", mention: true, state: "open", author: "hubot",
        body: """
        Reproduces with the file @octocat shared: `SVGImporter` maps the \
        whole document up front, so anything over ~2 GB dies in \
        `Data(contentsOf:)`.

        ```swift
        let data = try Data(contentsOf: url)   // 💥 whole file in memory
        let doc = try SVGDocument(data: data)
        ```

        > Streaming the parse keeps peak memory flat regardless of file size.

        Plan:
        - swap `Data(contentsOf:)` for `InputStream`
        - parse incrementally with `XMLParser`
        """,
        read: false
      ),
      item(
        minutesAgo: 12, account: gitlab, provider: .gitlab, kind: "merge",
        title: "Draft: refactor: split the billing worker", repo: "acme/billing",
        reason: "review_requested", mention: true, state: "draft", author: "sasha",
        body: """
        Splits `BillingWorker` into two stages:

        - `IngestWorker` consumes the queue and validates events
        - `SettleWorker` posts the ledger entries

        Migration notes in [the design doc](https://example.com/design). \
        Still draft while the backfill runs.
        """,
        read: false
      ),
      item(
        minutesAgo: 49, account: gitlab, provider: .gitlab, kind: "merge",
        title: "feat: expose usage metrics over /stats", repo: "acme/metrics",
        reason: "mentioned", mention: true, state: "open", author: "kim",
        body: """
        cc @octocat — counters now export on `/stats` in **Prometheus** \
        format, one series per provider. Names follow the *rate/errors/duration* \
        convention.
        """,
        read: false
      ),
      item(
        minutesAgo: 65, account: github, provider: .github, kind: "issue",
        title: "Rate-limit the public search endpoint", repo: "acme/atlas",
        reason: "assigned", state: "open", author: "mona",
        body: "Anonymous search should cap at **60 req/min** per IP — the crawler traffic from last week made `search/v2` the top CPU consumer.",
        read: false
      ),
      item(
        minutesAgo: 3 * 60, account: github, provider: .github, kind: "pull",
        title: "chore(deps): bump tokio from 1.39 to 1.40", repo: "acme/atlas",
        reason: "subscribed", state: "merged", author: "dependabot[bot]"
      ),
      item(
        minutesAgo: 5 * 60, account: github, provider: .github, kind: "pull",
        title: "fix: retry webhook deliveries with backoff", repo: "acme/hooks",
        reason: "review_requested", state: "open", author: "hubot"
      ),
      item(
        minutesAgo: 2 * 60, account: gitlab, provider: .gitlab, kind: "merge",
        title: "Add smoke tests for the export pipeline", repo: "acme/exports",
        reason: "author", state: "merged", author: "mona"
      ),
      item(
        minutesAgo: 8 * 60, account: gitlab, provider: .gitlab, kind: "issue",
        title: "Upgrade the runner fleet to 17.4", repo: "acme/infra",
        reason: "assigned", state: "open", author: "sasha"
      ),
      item(
        minutesAgo: 26 * 60, account: github, provider: .github, kind: "issue",
        title: "Dark-mode colors wash out on external displays", repo: "acme/console",
        reason: "commented", state: "closed", author: "kim"
      ),
      item(
        minutesAgo: 49 * 60, account: gitlab, provider: .gitlab, kind: "issue",
        title: "Flaky spec: billing_worker_spec.rb:118", repo: "acme/billing",
        reason: "subscribed", state: "closed", author: "hubot"
      ),
      item(
        minutesAgo: 52 * 60, account: github, provider: .github, kind: "pull",
        title: "Draft: experiment with HTTP/3 for the edge tier", repo: "acme/edge",
        reason: "author", state: "draft", author: "octocat"
      ),
    ]

    let accounts: [String: StoredAccount] = [
      github: StoredAccount(
        provider: .github,
        token: "demo",
        tokenEncrypted: false,
        username: "octocat",
        name: "The Octocat",
        avatarUrl: "https://avatars.githubusercontent.com/u/583231?v=4",
        createdAt: now.addingTimeInterval(-86400)
      ),
      gitlab: StoredAccount(
        provider: .gitlab,
        token: "demo",
        tokenEncrypted: false,
        baseUrl: "https://gitlab.acme.dev",
        username: "octocat",
        name: "The Octocat",
        createdAt: now
      ),
    ]

    return StoreFile(
      accounts: accounts,
      items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    )
  }
}
