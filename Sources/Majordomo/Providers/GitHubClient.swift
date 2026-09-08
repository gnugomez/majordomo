// GitHub provider client, ported from src/providers/github.ts. Talks to
// api.github.com on URLSession + Codable; config.baseUrl is unused.

import Foundation

private let maxPages = 2
private let perPage = 50

// The notifications payload carries no issue/PR state, so it is fetched per
// item from subject.url. stateBudget caps the uncached lookups per sync
// (items over budget just omit state this round and catch up on later syncs
// as the cache fills); stateConcurrency bounds how many run at once.
private let stateBudget = 20
private let stateConcurrency = 5

private let githubContext = RequestContext(
  service: "GitHub",
  origin: "https://api.github.com",
  originIsUserSupplied: false
)

// Minimal shapes: only the fields we read. Every field the API might omit is
// optional; entries missing what we require are skipped one by one.

private struct GHUser: Decodable {
  let login: String?
  let name: String?
  let avatar_url: String?
}

private struct GHNotification: Decodable {
  struct Subject: Decodable {
    let title: String
    let url: String?
    let latest_comment_url: String?
    let type: String
  }

  struct Repository: Decodable {
    let full_name: String
    let html_url: String
  }

  let id: String
  let reason: String
  let unread: Bool?
  let updated_at: String
  let subject: Subject
  let repository: Repository
}

/// The fields read off a subject.url (issue or pull) response.
private struct GHSubject: Decodable {
  struct User: Decodable {
    let login: String?
  }

  let state: String?
  let merged: Bool?
  let merged_at: String?
  let draft: Bool?
  let user: User?
  let body: String?
}

/// What one subject lookup teaches us; cached per thread id + updated_at.
private struct Enrichment: Sendable {
  var state: String?
  var author: String?
  var body: String?
}

/// True when a Link header advertises a rel="next" page.
private func hasNextLink(_ linkHeader: String?) -> Bool {
  guard let linkHeader else { return false }
  for part in linkHeader.split(separator: ",") {
    if part.range(of: #"<[^>]+>\s*;\s*rel="next""#, options: .regularExpression) != nil {
      return true
    }
  }
  return false
}

/// Derives the html URL for a notification without extra API calls.
private func htmlUrl(_ thread: GHNotification) -> String {
  guard let subjectUrl = thread.subject.url else {
    // Discussions, security alerts, etc. carry no subject URL.
    return thread.repository.html_url
  }
  var url = subjectUrl
  if let range = url.range(of: "https://api.github.com/repos/") {
    url.replaceSubrange(range, with: "https://github.com/")
  }
  if let range = url.range(of: "/pulls/") {
    url.replaceSubrange(range, with: "/pull/")
  }
  if let commentUrl = thread.subject.latest_comment_url,
     let match = commentUrl.firstMatch(of: #//issues/comments/(\d+)$/#) {
    url += "#issuecomment-\(match.1)"
  }
  return url
}

/// GitHub notification `reason` values → this provider's reason tokens.
/// Anything unmapped (or new the API starts sending) lands on "activity".
private let githubReasons: [String: String] = [
  "mention": "mentioned",
  "team_mention": "mentioned",
  "review_requested": "review_requested",
  "approval_requested": "approval_required",
  "assign": "assigned",
  "author": "author",
  "comment": "commented",
  "subscribed": "subscribed",
  "manual": "subscribed",
]

private func githubReason(_ raw: String) -> String {
  githubReasons[raw] ?? "activity"
}

private func toFetchedItem(_ thread: GHNotification) -> FetchedItem? {
  guard let updatedAt = ISODate.parse(thread.updated_at) else { return nil }
  let reason = githubReason(thread.reason)
  return FetchedItem(
    externalId: thread.id,
    kind: thread.subject.type == "PullRequest" ? "pull" : "issue",
    title: thread.subject.title,
    repo: thread.repository.full_name,
    url: htmlUrl(thread),
    reason: reason,
    isMention: GitForgeVisuals.isMention(reason),
    updatedAt: updatedAt,
    upstreamRead: thread.unread == false
  )
}

/// Maps a subject payload to the item's lifecycle state token, if
/// determinable.
private func toItemState(subjectType: String, subject: GHSubject) -> String? {
  if subjectType == "PullRequest" {
    if subject.merged == true || subject.merged_at != nil {
      return "merged"
    }
    if subject.draft == true {
      return "draft"
    }
  }
  if subject.state == "open" {
    return "open"
  }
  if subject.state == "closed" {
    return "closed"
  }
  return nil
}

/// An actor so the enrichment cache lives as long as the client (the app's
/// lifetime) without locking by hand.
actor GitHubClient: ProviderClient {
  nonisolated let id: ProviderId = .github

  /// Cached subject lookups, keyed `threadId:updated_at`; see enrichStates.
  private var stateCache: [String: Enrichment] = [:]

  private func request(_ url: URL, token: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    return request
  }

  func validate(_ config: AccountConfig) async throws -> ProviderProfile {
    let url = URL(string: "https://api.github.com/user")!
    let data = try await sendExpectingSuccess(request(url, token: config.token), ctx: githubContext)
    guard let user = try? JSONDecoder().decode(GHUser.self, from: data), let login = user.login else {
      throw ProviderError(message: "GitHub accepted the token but returned no username — try again later.")
    }
    return ProviderProfile(username: login, name: user.name, avatarUrl: user.avatar_url)
  }

  func fetchItems(_ config: AccountConfig) async throws -> FetchResult {
    var entries: [(item: FetchedItem, thread: GHNotification)] = []
    // Set once the last page is consumed. Hitting maxPages with pages left —
    // or bailing on a 304/malformed body — leaves the fetch incomplete, so
    // absence proves nothing this round (see SyncEngine).
    var complete = false

    for page in 1 ... maxPages {
      var components = URLComponents(string: "https://api.github.com/notifications")!
      components.queryItems = [
        // Read threads too: items handled on the web while the app was
        // closed still arrive (as already-read) instead of never showing.
        URLQueryItem(name: "all", value: "true"),
        URLQueryItem(name: "per_page", value: String(perPage)),
        URLQueryItem(name: "page", value: String(page)),
      ]
      let (data, http) = try await send(request(components.url!, token: config.token), ctx: githubContext)
      // 304 means "nothing new", not a failure.
      if http.statusCode == 304 {
        break
      }
      guard (200 ..< 300).contains(http.statusCode) else {
        throw ProviderError(message: statusMessage(http.statusCode, githubContext))
      }
      guard let body = try? JSONDecoder().decode([Failable<GHNotification>].self, from: data) else {
        break
      }
      for thread in body.compactMap(\.value) {
        // One malformed thread must not kill the whole fetch.
        if let item = toFetchedItem(thread) {
          entries.append((item, thread))
        }
      }
      if !hasNextLink(http.value(forHTTPHeaderField: "Link")) {
        complete = true
        break
      }
    }

    let items = await enrichStates(config: config, entries: entries)
    return FetchResult(items: items, complete: complete)
  }

  /// Fills in `state`/`author`/`body` on the fetched items by looking up
  /// each thread's subject.url, at most stateBudget uncached lookups per call
  /// (newest first). Results — including "couldn't determine" — are cached
  /// per thread id + updated_at, so unchanged items never refetch across the
  /// sync loop and failed lookups don't retry every minute. Lookup failures
  /// are per-item and silent: the item just ships without a state.
  private func enrichStates(
    config: AccountConfig,
    entries: [(item: FetchedItem, thread: GHNotification)]
  ) async -> [FetchedItem] {
    // Rebuilt from this round's threads so the cache never outgrows the inbox.
    var nextCache: [String: Enrichment] = [:]
    var items: [FetchedItem] = []
    var pending: [(index: Int, thread: GHNotification, key: String)] = []

    for (item, thread) in entries {
      var item = item
      // Discussions, security alerts, etc. carry no subject URL — no state.
      if thread.subject.url != nil {
        let key = "\(thread.id):\(thread.updated_at)"
        if let known = stateCache[key] {
          nextCache[key] = known
          item.state = known.state
          item.author = known.author
          item.body = known.body
        } else {
          pending.append((items.count, thread, key))
        }
      }
      items.append(item)
    }

    pending.sort { $0.thread.updated_at > $1.thread.updated_at }
    let batch = pending.prefix(stateBudget)

    // Bounded concurrency: waves of stateConcurrency lookups at a time.
    let token = config.token
    var lookups: [(index: Int, key: String, known: Enrichment)] = []
    for wave in stride(from: 0, to: batch.count, by: stateConcurrency) {
      let jobs = Array(batch[batch.startIndex + wave ..< min(batch.startIndex + wave + stateConcurrency, batch.endIndex)])
      let results = await withTaskGroup(of: (Int, String, Enrichment).self) { group in
        for job in jobs {
          guard let subjectUrlString = job.thread.subject.url, let subjectUrl = URL(string: subjectUrlString) else {
            continue
          }
          let subjectType = job.thread.subject.type
          let request = self.request(subjectUrl, token: token)
          group.addTask {
            var known = Enrichment()
            if let data = try? await sendExpectingSuccess(request, ctx: githubContext),
               let subject = try? JSONDecoder().decode(GHSubject.self, from: data) {
              known.state = toItemState(subjectType: subjectType, subject: subject)
              known.author = subject.user?.login
              known.body = truncatedBody(subject.body)
            }
            return (job.index, job.key, known)
          }
        }
        var collected: [(Int, String, Enrichment)] = []
        for await result in group {
          collected.append(result)
        }
        return collected
      }
      lookups.append(contentsOf: results.map { (index: $0.0, key: $0.1, known: $0.2) })
    }

    for lookup in lookups {
      nextCache[lookup.key] = lookup.known
      items[lookup.index].state = lookup.known.state
      items[lookup.index].author = lookup.known.author
      items[lookup.index].body = lookup.known.body
    }

    stateCache = nextCache
    return items
  }
}
