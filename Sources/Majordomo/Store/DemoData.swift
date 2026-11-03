// Fixture data for MAJORDOMO_DEMO=1: the app runs against an in-memory
// store full of fictional items and never syncs — for screenshots and UI
// work without real accounts or personal notifications on screen.

import Foundation

/// Demo mode: fixtures instead of the real store, no network, no Keychain.
let isDemo = ProcessInfo.processInfo.environment["MAJORDOMO_DEMO"] != nil

enum DemoData {
  private static let github: AccountId = "demo-github"
  private static let gitlab: AccountId = "demo-gitlab"

  private static let urgentLabel: LabelId = "demo-label-urgent"
  private static let infraLabel: LabelId = "demo-label-infra"
  private static let laterLabel: LabelId = "demo-label-later"
  private static let teamInbox: LabelId = "demo-inbox-team"

  static func storeFile() -> StoreFile {
    let now = Date()

    func item(
      minutesAgo: Double, account: AccountId, provider: ProviderId, kind: String,
      title: String, repo: String, reason: String, mention: Bool = false,
      state: String? = nil, author: String? = nil, body: String? = nil, read: Bool = true,
      url: String? = nil, upstreamLabels: [String]? = nil,
      labelOverrides: LabelOverrides = [:]
    ) -> StoredItem {
      let date = now.addingTimeInterval(-minutesAgo * 60)
      return StoredItem(
        id: "\(account):\(Int(minutesAgo))", accountId: account, provider: provider,
        kind: kind, title: title, repo: repo,
        url: url ?? targetUrl(provider: provider, repo: repo, kind: kind, number: Int(minutesAgo) % 1000),
        reason: reason, isMention: mention, updatedAt: date, state: state,
        author: author, body: body, read: read, firstSeenAt: date, lastSeenUpstreamAt: now,
        labelOverrides: labelOverrides, upstreamLabels: upstreamLabels
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
        read: false,
        url: "https://github.com/acme/vector-kit/issues/26#issuecomment-4"
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
        read: false,
        url: "https://gitlab.acme.dev/acme/metrics/-/merge_requests/49#note_7"
      ),
      // One MR that arrived as three GitLab todos — they thread into a
      // single row (same target, fragments stripped).
      item(
        minutesAgo: 8, account: gitlab, provider: .gitlab, kind: "merge",
        title: "feat: canary deploys for the edge tier", repo: "acme/deploy",
        reason: "review_requested", mention: true, state: "open", author: "priya",
        body: """
        Rolls out to **5% of edge nodes** first; the gate promotes when error \
        rate and p99 stay inside the thresholds for 15 minutes.
        """,
        read: false,
        url: "https://gitlab.acme.dev/acme/deploy/-/merge_requests/58"
      ),
      item(
        minutesAgo: 9, account: gitlab, provider: .gitlab, kind: "merge",
        title: "feat: canary deploys for the edge tier", repo: "acme/deploy",
        reason: "mentioned", mention: true, state: "open", author: "priya",
        body: "@octocat the rollout gate config moved to `deploy/gates.yml` — can you sanity-check the thresholds?",
        read: false,
        url: "https://gitlab.acme.dev/acme/deploy/-/merge_requests/58#note_881"
      ),
      item(
        minutesAgo: 30, account: gitlab, provider: .gitlab, kind: "merge",
        title: "feat: canary deploys for the edge tier", repo: "acme/deploy",
        reason: "assigned", state: "open", author: "priya",
        url: "https://gitlab.acme.dev/acme/deploy/-/merge_requests/58"
      ),
      item(
        minutesAgo: 65, account: github, provider: .github, kind: "issue",
        title: "Rate-limit the public search endpoint", repo: "acme/atlas",
        reason: "assigned", state: "open", author: "mona",
        body: "Anonymous search should cap at **60 req/min** per IP — the crawler traffic from last week made `search/v2` the top CPU consumer.",
        read: false,
        // Carries the tracker's own "urgent" label — a rule picks it up.
        upstreamLabels: ["urgent", "backend"]
      ),
      item(
        minutesAgo: 3 * 60, account: github, provider: .github, kind: "pull",
        title: "chore(deps): bump tokio from 1.39 to 1.40", repo: "acme/atlas",
        reason: "subscribed", state: "merged", author: "dependabot[bot]",
        // Filed under Later by hand — no rule says so.
        labelOverrides: [laterLabel: true]
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
      // Watched-repository traffic: new issues nobody has picked up yet,
      // a teammate's pull request, and an assignment gone quiet — what a
      // board's triage, Other and faded cards are for.
      item(
        minutesAgo: 95, account: github, provider: .github, kind: "issue",
        title: "Export to PDF drops embedded fonts", repo: "acme/vector-kit",
        reason: "subscribed", state: "open", author: "lin", read: false
      ),
      item(
        minutesAgo: 3 * 60, account: gitlab, provider: .gitlab, kind: "issue",
        title: "Document the canary thresholds", repo: "acme/deploy",
        reason: "subscribed", state: "open", author: "priya"
      ),
      item(
        minutesAgo: 4 * 60, account: github, provider: .github, kind: "pull",
        title: "feat: keyboard shortcuts for the command palette", repo: "acme/console",
        reason: "subscribed", state: "open", author: "kim"
      ),
      item(
        minutesAgo: 20 * 24 * 60, account: github, provider: .github, kind: "issue",
        title: "Search results ignore the user's locale", repo: "acme/atlas",
        reason: "assigned", state: "open", author: "mona"
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

    // Labels, a user inbox, and the rules that fill them; assignments are
    // computed at launch by the sync engine's sweep, like the real store's.
    let labels = [
      InboxLabel(id: urgentLabel, name: "Urgent", symbol: "flame", tint: .red, notify: .urgent, order: 0),
      InboxLabel(id: infraLabel, name: "Infra", symbol: "server.rack", tint: .blue, notify: .follow, order: 1),
      InboxLabel(id: laterLabel, name: "Later", symbol: "moon.zzz", tint: .gray, notify: .never, order: 2),
      InboxLabel(
        id: teamInbox, name: "Team", symbol: "person.2", tint: .blue, notify: .follow, order: 3, kind: .inbox
      ),
    ]
    let rules = [
      LabelRule(
        id: "demo-rule-team", name: "Teammates",
        filter: RuleFilter(conditions: [
          RuleCondition(field: .author, op: .is, value: "mona"),
          RuleCondition(field: .author, op: .is, value: "sasha"),
        ], match: .any),
        labelIds: [teamInbox]
      ),
      LabelRule(
        id: "demo-rule-crash", name: "Crashes are urgent",
        filter: RuleFilter(conditions: [
          RuleCondition(field: .title, op: .contains, value: "crash"),
          RuleCondition(field: .body, op: .contains, value: "crash"),
        ], match: .any),
        labelIds: [urgentLabel]
      ),
      LabelRule(
        id: "demo-rule-upstream", name: "Upstream urgent",
        filter: RuleFilter(conditions: [RuleCondition(field: .upstreamLabel, op: .is, value: "urgent")]),
        labelIds: [urgentLabel]
      ),
      LabelRule(
        id: "demo-rule-infra", name: "Infra repos",
        filter: RuleFilter(conditions: [RuleCondition(field: .repo, op: .is, value: "acme/infra")]),
        labelIds: [infraLabel]
      ),
      // Groups joined by "and", each an "or" of its own: ops work, asked
      // of me.
      LabelRule(
        id: "demo-rule-ops", name: "Ops work on me",
        filter: RuleFilter(match: .all, groups: [
          RuleGroup(match: .any, conditions: [
            RuleCondition(field: .repo, op: .is, value: "acme/infra"),
            RuleCondition(field: .repo, op: .is, value: "acme/deploy"),
          ]),
          RuleGroup(match: .any, conditions: [
            RuleCondition(field: .reason, op: .is, value: "review_requested"),
            RuleCondition(field: .reason, op: .is, value: "assigned"),
          ]),
        ]),
        labelIds: [infraLabel]
      ),
      // A cheap condition and an Apple Intelligence check in one group:
      // the model is only asked about issues.
      LabelRule(
        id: "demo-rule-user-bugs", name: "Bugs users hit",
        filter: RuleFilter(conditions: [
          RuleCondition(field: .kind, op: .is, value: "issue"),
          .question("Is this a bug that people are running into right now, rather than an idea or a chore?"),
        ]),
        labelIds: [urgentLabel]
      ),
      LabelRule(
        id: "demo-rule-bots", name: "Bot chores can wait",
        filter: RuleFilter(conditions: [
          RuleCondition(field: .author, op: .contains, value: "[bot]"),
          RuleCondition(field: .mention, negated: true),
        ]),
        labelIds: [laterLabel],
        // Moving, with nothing chosen: the bot's pull request shows in
        // Later and nowhere else.
        movesItems: true
      ),
    ]

    // A second board beside the starter one: every pull and merge request
    // (two groups, either one), sorted by what a review needs — the first
    // column asks Apple Intelligence about the change.
    let reviews = Board(
      id: "demo-board-reviews",
      name: "Reviews",
      symbol: "eye",
      scope: RuleFilter(match: .any, groups: [
        RuleGroup(conditions: [RuleCondition(field: .kind, op: .is, value: "pull")]),
        RuleGroup(conditions: [RuleCondition(field: .kind, op: .is, value: "merge")]),
      ]),
      columns: [
        BoardColumn(id: "demo-reviews-careful", name: "Careful Look", filter: RuleFilter(conditions: [
          RuleCondition(field: .reviewer, op: .is, value: "@me"),
          .question("Could this change break production — storage, billing, or how things are deployed?"),
        ])),
        BoardColumn(id: "demo-reviews-mine", name: "Mine to Review", filter: RuleFilter(conditions: [
          RuleCondition(field: .reviewer, op: .is, value: "@me"),
        ])),
        BoardColumn(id: "demo-reviews-ready", name: "Ready", filter: RuleFilter(conditions: [
          RuleCondition(field: .review, op: .is, value: "approved"),
        ])),
      ]
    )

    // Two patterns the model would have noticed, waiting on an answer:
    // neither signature is covered by the rules above, so they behave
    // exactly like freshly mined ones.
    let suggestions = [
      Suggestion(
        id: "demo-suggestion-vector",
        signature: "repo=acme/vector-kit|",
        name: "Vector Kit",
        targetName: "Vector Kit",
        targetKind: .inbox,
        targetSymbol: "shippingbox",
        targetTint: .teal,
        rationale: "Vector Kit keeps coming up — its own inbox would keep it out of Recent.",
        conditions: [RuleCondition(field: .repo, op: .is, value: "acme/vector-kit")],
        matchCount: 7,
        createdAt: now.addingTimeInterval(-3600)
      ),
      Suggestion(
        id: "demo-suggestion-bots",
        signature: "author=dependabot[bot]|",
        name: "Dependabot",
        targetName: "Dependabot",
        targetKind: .label,
        targetSymbol: "shippingbox",
        targetTint: .gray,
        rationale: "Dependency bumps arrive steadily and rarely need you — a label would mark them at a glance.",
        conditions: [RuleCondition(field: .author, op: .is, value: "dependabot[bot]")],
        matchCount: 6,
        createdAt: now.addingTimeInterval(-7200)
      ),
    ]

    // What the boards know about each target, as a refresh would have
    // left it: enough to put a card in every column of the starter board,
    // and to show every review, checks, and merge mark on the rows — the
    // user's own review awaited, conflicts, and a draft marked ready since
    // its notification came, which the row reads as open.
    func target(
      _ item: StoredItem, state: String? = nil, assignees: [String] = [], reviewers: [String] = [],
      labels: [String] = [], milestone: String? = nil, review: String? = nil, checks: String? = nil,
      merge: String? = nil, comments: Int = 0, lastCommenter: String? = nil, seenComments: Int? = nil
    ) -> TrackedTarget {
      let key = String(item.url.prefix { $0 != "#" })
      return TrackedTarget(
        key: key,
        provider: item.provider,
        snapshot: TargetSnapshot(
          title: item.title, state: state ?? item.state, author: item.author, assignees: assignees,
          reviewers: reviewers, labels: labels, milestone: milestone, review: review, checks: checks, merge: merge,
          commentCount: comments, lastCommenter: lastCommenter, updatedAt: item.updatedAt
        ),
        fetchedAt: now,
        seenAt: seenComments.map { _ in now.addingTimeInterval(-3600) },
        seenComments: seenComments,
        conversationAt: item.updatedAt
      )
    }
    let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    func on(_ account: AccountId, _ minutesAgo: Double) -> StoredItem {
      byId["\(account):\(Int(minutesAgo))"]!
    }
    let targets = [
      target(
        on(github, 4), assignees: ["mona"], reviewers: ["octocat"], labels: ["storage"],
        review: "review_required", checks: "success", merge: "blocked", comments: 3, lastCommenter: "mona"
      ),
      target(on(github, 26), labels: ["bug", "crash"], comments: 7, lastCommenter: "hubot", seenComments: 5),
      target(
        on(gitlab, 12), assignees: ["sasha"], reviewers: ["octocat"],
        review: "review_required", checks: "pending", comments: 2, lastCommenter: "sasha"
      ),
      target(
        on(gitlab, 49), assignees: ["kim"], checks: "failure", merge: "conflicts", comments: 4, lastCommenter: "kim"
      ),
      target(
        on(gitlab, 8), assignees: ["octocat", "priya"], reviewers: ["octocat"], milestone: "Q4 rollout",
        review: "review_required", checks: "success", merge: "unresolved", comments: 6, lastCommenter: "priya",
        seenComments: 4
      ),
      target(
        on(github, 65), assignees: ["octocat"], labels: ["urgent", "backend"], milestone: "v2.4",
        comments: 2, lastCommenter: "octocat"
      ),
      target(on(github, 3 * 60), labels: ["dependencies"], checks: "success"),
      target(
        on(github, 5 * 60), assignees: ["hubot"], review: "changes_requested", checks: "success", merge: "behind",
        comments: 5, lastCommenter: "octocat"
      ),
      target(on(gitlab, 2 * 60), assignees: ["mona"], review: "approved", checks: "success", comments: 1),
      target(
        on(gitlab, 8 * 60), assignees: ["octocat"], milestone: "17.4 upgrade", comments: 1, lastCommenter: "sasha"
      ),
      target(on(github, 26 * 60), labels: ["design"], comments: 3, lastCommenter: "kim"),
      target(on(gitlab, 49 * 60), labels: ["flaky"], comments: 1),
      target(on(github, 52 * 60), state: "open", checks: "failure", merge: "unstable"),
      target(on(github, 95)),
      target(on(gitlab, 3 * 60), comments: 1, lastCommenter: "priya"),
      target(
        on(github, 4 * 60), assignees: ["kim"], labels: ["enhancement"], review: "approved", checks: "success",
        merge: "ready", comments: 2, lastCommenter: "mona"
      ),
      target(on(github, 20 * 24 * 60), assignees: ["octocat"], labels: ["i18n"], comments: 4, lastCommenter: "mona"),
    ]

    // The rest of the targets have their conversations in too, as the
    // background refresh would have left them.
    var tracked = Dictionary(uniqueKeysWithValues: targets.map { ($0.key, $0) })
    for item in items {
      if let key = GitForgeVisuals.targetUrl(item.url)?.key, tracked[key] == nil {
        tracked[key] = TrackedTarget(key: key, provider: item.provider, fetchedAt: now, conversationAt: item.updatedAt)
      }
    }

    return StoreFile(
      accounts: accounts,
      items: byId,
      labels: labels,
      rules: rules,
      suggestions: suggestions,
      targets: tracked,
      boards: [GitForgeBoards.myWork, reviews],
      boardsSeeded: true
    )
  }

  /// A fixture item's page, shaped like the real forge's so boards can key
  /// it: GitHub's issues and pulls, the demo GitLab instance's issues and
  /// merge requests.
  private static func targetUrl(provider: ProviderId, repo: String, kind: String, number: Int) -> String {
    switch provider {
    case .github:
      "https://github.com/\(repo)/\(kind == "pull" ? "pull" : "issues")/\(number)"
    case .gitlab:
      "https://gitlab.acme.dev/\(repo)/-/\(kind == "merge" ? "merge_requests" : "issues")/\(number)"
    }
  }

  /// The fixture targets' conversations: written out for a few of them — a
  /// mention with its comment, a review with a conversation, reviews and
  /// approvals, a screenshot — and for the rest just the description their
  /// newest item carries.
  static func conversations(in file: StoreFile) -> [String: TargetConversation] {
    let now = Date()
    func ago(_ minutes: Double) -> Date {
      now.addingTimeInterval(-minutes * 60)
    }
    func comment(
      _ id: String, _ author: String, minutesAgo: Double, _ body: String, event: String? = nil,
      provider: ProviderId = .github
    ) -> DetailComment {
      DetailComment(
        id: id, author: author, avatarUrl: provider == .gitlab ? gitlabAvatar(author) : nil,
        createdAt: ago(minutesAgo), body: body, event: event
      )
    }

    var conversations: [String: TargetConversation] = [:]
    for item in file.items.values.sorted(by: { $0.updatedAt < $1.updatedAt }) {
      if let key = GitForgeVisuals.targetUrl(item.url)?.key {
        conversations[key] = TargetConversation(
          description: item.body, author: item.author,
          authorAvatarUrl: item.provider == .gitlab ? item.author.map(gitlabAvatar) : nil,
          createdAt: item.updatedAt.addingTimeInterval(-2 * 24 * 60 * 60), commentCount: 0
        )
      }
    }
    func write(_ itemId: String, _ conversation: (StoredItem) -> TargetConversation) {
      if let item = file.items[itemId], let key = GitForgeVisuals.targetUrl(item.url)?.key {
        conversations[key] = conversation(item)
      }
    }

    write("\(github):26") { item in
      TargetConversation(
        description: item.body,
        author: item.author,
        createdAt: ago(4 * 24 * 60),
        comments: [
          comment("1", "kim", minutesAgo: 3 * 24 * 60, "Same here with a 2.4 GB export from Figma."),
          comment("2", "mona", minutesAgo: 2 * 24 * 60, """
            Confirmed on main. Peak memory tracks file size exactly:

            | File | Peak |
            | --- | --- |
            | 800 MB | 1.1 GB |
            | 2.3 GB | crash |
            """),
          comment("3", "sasha", minutesAgo: 90, "- [x] repro on macOS\n- [ ] repro on Linux"),
          comment("4", "hubot", minutesAgo: 26, """
            @octocat this is the file from your report — it dies the moment the \
            mapping starts. Could you check whether the streaming branch fixes it \
            on your machine?
            """),
        ],
        commentCount: 7
      )
    }
    write("\(github):4") { item in
      TargetConversation(
        description: """
          <!-- Describe the change and link the issue it closes. -->
          ## Summary

          \(item.body ?? "")

          ## Checklist

          - [x] Tests for the retry path
          - [x] Benchmarks against the multipart path
          - [ ] Remove the old code path
          """,
        author: item.author,
        createdAt: ago(2 * 24 * 60),
        comments: [
          comment("1", "hubot", minutesAgo: 3 * 60, """
            Benchmarks look great — **3× less memory** on the 1 GB fixture, and \
            flat no matter the file size:

            <img width="520" alt="Peak memory, multipart against streaming" src="\(chartImage)" />
            """),
          comment("review-11", "kim", minutesAgo: 95, """
            The retry path still re-reads the part from disk — with streaming \
            there is no file to go back to. Can it replay from the buffered \
            chunk instead?

            <details>
            <summary>Where it happens</summary>

            ```swift
            let part = try Data(contentsOf: partURL)   // gone after streaming
            try await upload(part, attempt: attempt + 1)
            ```

            </details>
            """, event: "changes_requested"),
          comment("2", "mona", minutesAgo: 40, """
            Good catch — retries now replay the in-memory chunk, capped at \
            `maxChunkSize`. Pushed in `8c1f2e4`.
            """),
          comment("review-12", "sasha", minutesAgo: 12, "", event: "approved"),
        ],
        commentCount: 2
      )
    }
    write("\(gitlab):49") { item in
      TargetConversation(
        description: """
          Exports request, error, and latency counters on `/stats`, one \
          series per provider.

          ![Grafana panel for /stats](/uploads/5f3a9c1e7b2d4e6f8a0b1c2d3e4f5a6b/stats-panel.png)

          Closes #212.
          """,
        author: item.author,
        authorAvatarUrl: item.author.map(gitlabAvatar),
        createdAt: ago(26 * 60),
        comments: [
          comment("7", "kim", minutesAgo: 49, item.body ?? "", provider: .gitlab),
          comment("8", "priya", minutesAgo: 30, "", event: "approved", provider: .gitlab),
        ],
        commentCount: 1
      )
    }
    return conversations
  }

  // MARK: Images

  /// Where the fixtures' screenshot is written: an upload's address, as
  /// GitHub would give it.
  private static let chartImage = "https://github.com/user-attachments/assets/6f1c2a9e-4b7d-4c3e-9a51-2d8e0b7f3c14"

  /// The people the fixtures name, each with a face among the resources.
  private static let people = ["mona", "hubot", "kim", "sasha", "priya", "octocat", "lin"]

  /// A person's face on the demo GitLab instance.
  private static func gitlabAvatar(_ login: String) -> String {
    "https://gitlab.acme.dev/uploads/-/system/user/avatar/\(login)/avatar.png"
  }

  /// A fixture image by its address — the screenshot, or a person's face
  /// wherever a provider would serve it — read from the app's resources.
  /// nil for anything else, which the preview shows as a link.
  static func image(_ url: URL) -> Data? {
    let name: String
    if url.absoluteString == chartImage {
      name = "demo-chart"
    } else if let login = people.first(where: { login in
      url.pathComponents.contains { $0 == login || $0 == "\(login).png" }
    }) {
      name = "demo-avatar-\(login)"
    } else {
      return nil
    }
    return resources?.url(forResource: name, withExtension: "png").flatMap { try? Data(contentsOf: $0) }
  }

  /// The SwiftPM resource bundle: in Contents/Resources in the packaged
  /// app, where Bundle.module doesn't look; Bundle.module under `swift run`.
  private static var resources: Bundle? {
    if let url = Bundle.main.resourceURL?.appending(path: "Majordomo_Majordomo.bundle"), let bundle = Bundle(url: url) {
      return bundle
    }
    return .module
  }
}
