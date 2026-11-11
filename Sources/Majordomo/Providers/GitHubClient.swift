// GitHub provider client. Talks to api.github.com on URLSession + Codable;
// config.baseUrl is unused.

import Foundation

/// Pages per depth: .recent skims the newest threads; .full follows the
/// pagination to the end, bounded by a safety ceiling (20 × 50 = 1,000).
private let recentPages = 2
private let fullPages = 20
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

  struct Label: Decodable {
    let name: String?
  }

  let state: String?
  let merged: Bool?
  let merged_at: String?
  let draft: Bool?
  let user: User?
  let body: String?
  let labels: [Label]?
}

/// A classic token's scopes, which GitHub reports on every response,
/// failures included; nil without the header.
private func grantedScopes(_ http: HTTPURLResponse) -> Set<String>? {
  guard let scopes = http.value(forHTTPHeaderField: "X-OAuth-Scopes") else {
    return nil
  }
  return Set(scopes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
}

/// True when the token can read private repositories.
private func grantsPrivateRepos(_ http: HTTPURLResponse) -> Bool {
  grantedScopes(http)?.contains("repo") == true
}

/// What the token's scopes leave out of reach: projects, whose statuses
/// and due dates take read:project. nil when they reach them, or nothing
/// can be told.
private func scopeNote(_ http: HTTPURLResponse) -> String? {
  guard let granted = grantedScopes(http), granted.isDisjoint(with: ["read:project", "project"]) else {
    return nil
  }
  return "Statuses and due dates from GitHub projects need the token's read:project scope: add it to the token on GitHub, then relaunch, or paste the token again."
}

/// Targets one GraphQL request asks about. GitHub prices a query by the
/// nodes it could return, and fifty targets with their assignees, labels
/// and reviewers stay far inside one request's share of the hourly budget.
private let targetsPerQuery = 50
/// Targets per request when their conversations come along: each brings
/// its description and latest comments whole, and a request that heavy is
/// slow to answer and more likely to time out.
private let conversationsPerQuery = 20

/// What a target query asks of each issue or pull request; the pull-only
/// fields come back nil on an issue.
private let targetFragments = """
  fragment Issue on Issue { title state stateReason updatedAt author { login avatarUrl } \
  assignees(first: 10) { nodes { login avatarUrl } } labels(first: 20) { nodes { name } } milestone { title } \
  comments(last: 1) { totalCount nodes { author { login } createdAt } } }
  fragment Pull on PullRequest { title state isDraft updatedAt author { login avatarUrl } \
  assignees(first: 10) { nodes { login avatarUrl } } labels(first: 20) { nodes { name } } milestone { title } \
  comments(last: 1) { totalCount nodes { author { login } createdAt } } \
  reviews(last: 1) { nodes { author { login } submittedAt } } reviewDecision mergeable mergeStateStatus \
  reviewRequests(first: 10) { nodes { requestedReviewer { ... on User { login avatarUrl } } } } \
  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }
  """

/// What a query asks of each target whose conversation it wants as well:
/// who opened it and when, its description, the latest comments, and on a
/// pull request the latest reviews. GraphQL refuses a fragment the query
/// never spreads, so these go only into the queries that do.
private let conversationFragments = """
  fragment IssueTalk on Issue { body createdAt opener: author { ...Person } \
  talk: comments(last: \(detailCommentLimit)) { totalCount nodes { databaseId author { ...Person } createdAt body } } }
  fragment PullTalk on PullRequest { body createdAt opener: author { ...Person } \
  talk: comments(last: \(detailCommentLimit)) { totalCount nodes { databaseId author { ...Person } createdAt body } } \
  verdicts: reviews(last: \(detailCommentLimit)) { nodes { databaseId author { ...Person } state submittedAt body } } }
  fragment Person on Actor { login avatarUrl(size: 80) }
  """

/// What a query asks of each target about its projects: the status each
/// gives it, a project's Status being a single-select field of its own
/// that goes by that name, and the day it is due, which has no name of
/// its own — a project names its date fields as it likes, Due Date or
/// Target date, in whatever case — so the item's set values come with
/// their fields' names, and the due date is picked by name among them. A
/// card archived in a project is left out: its status is history.
/// Reading projects takes a scope of its own (read:project), and GitHub
/// answers a query that asks without it with an error for the query, so
/// these go only into the queries of a round that may.
private let projectFragments = """
  fragment IssueProject on Issue { projectItems(first: 5, includeArchived: false) { nodes { ...ItemFacts } } }
  fragment PullProject on PullRequest { projectItems(first: 5, includeArchived: false) { nodes { ...ItemFacts } } }
  fragment ItemFacts on ProjectV2Item { status: fieldValueByName(name: "Status") \
  { ... on ProjectV2ItemFieldSingleSelectValue { name } } \
  fieldValues(first: \(projectValuesPerItem)) { nodes { ... on ProjectV2ItemFieldDateValue { date \
  field { ... on ProjectV2FieldCommon { name } } } } } }
  """

/// Field values a project item is asked for: only the fields set on it
/// come, and a dozen covers a project's fields with room, at a cost the
/// query carries for every item asked.
private let projectValuesPerItem = 12

private struct GQLLogin: Decodable {
  let login: String?
  /// Asked for where the snapshot names the person.
  let avatarUrl: String?
}

/// Someone in a conversation, with their picture.
private struct GQLPerson: Decodable {
  let login: String?
  let avatarUrl: String?
}

private struct GQLNodes<Node: Decodable>: Decodable {
  let totalCount: Int?
  let nodes: [Failable<Node>]?

  var values: [Node] { (nodes ?? []).compactMap(\.value) }
}

private struct GQLTarget: Decodable {
  struct Name: Decodable {
    let name: String?
  }

  struct Milestone: Decodable {
    let title: String?
  }

  struct Comment: Decodable {
    let author: GQLLogin?
    let createdAt: String?
  }

  struct Review: Decodable {
    let author: GQLLogin?
    let submittedAt: String?
  }

  struct ReviewRequest: Decodable {
    let requestedReviewer: GQLLogin?
  }

  struct TalkComment: Decodable {
    /// The REST id, which the comment's links and anchors use.
    let databaseId: Int?
    let author: GQLPerson?
    let createdAt: String?
    let body: String?
  }

  struct TalkReview: Decodable {
    let databaseId: Int?
    let author: GQLPerson?
    /// "APPROVED", "CHANGES_REQUESTED", "COMMENTED", "DISMISSED", "PENDING".
    let state: String?
    let submittedAt: String?
    let body: String?
  }

  struct CommitNode: Decodable {
    struct Commit: Decodable {
      struct Rollup: Decodable {
        let state: String?
      }

      let statusCheckRollup: Rollup?
    }

    let commit: Commit?
  }

  struct ProjectItem: Decodable {
    struct Value: Decodable {
      let name: String?
    }

    /// One of the item's field values; a date field's carries its day
    /// ("2026-11-12") and its field's name, any other nothing.
    struct FieldValue: Decodable {
      let date: String?
      let field: Name?
    }

    let status: Value?
    let fieldValues: GQLNodes<FieldValue>?
  }

  let __typename: String
  let title: String
  let state: String
  /// Why an issue is closed: "COMPLETED", "NOT_PLANNED", or "DUPLICATE";
  /// "REOPENED" on one open again.
  let stateReason: String?
  let isDraft: Bool?
  let updatedAt: String
  let author: GQLLogin?
  let assignees: GQLNodes<GQLLogin>?
  let labels: GQLNodes<Name>?
  let milestone: Milestone?
  let comments: GQLNodes<Comment>?
  let reviews: GQLNodes<Review>?
  let reviewDecision: String?
  /// "MERGEABLE", "CONFLICTING", or "UNKNOWN" while GitHub works it out.
  let mergeable: String?
  /// What stands between the pull request and a merge: "CLEAN",
  /// "BEHIND", "BLOCKED", "DIRTY"…
  let mergeStateStatus: String?
  let reviewRequests: GQLNodes<ReviewRequest>?
  let commits: GQLNodes<CommitNode>?
  /// Its place in each project it is in, when the query asked.
  let projectItems: GQLNodes<ProjectItem>?
  /// The opening post, latest comments, and latest reviews, when the
  /// query asked for them.
  let body: String?
  let createdAt: String?
  let opener: GQLPerson?
  let talk: GQLNodes<TalkComment>?
  let verdicts: GQLNodes<TalkReview>?
}

private struct GQLRepository: Decodable {
  let issueOrPullRequest: GQLTarget?
}

/// One alias per target; an alias the token can't see comes back null,
/// with an error whose path starts at it.
private struct GQLTargetsResponse: Decodable {
  struct Failure: Decodable {
    /// "NOT_FOUND", "FORBIDDEN", "RATE_LIMITED"…
    let type: String?
    let message: String?
    let path: [GQLPathStep]?
  }

  let data: [String: Failable<GQLRepository>]?
  let errors: [Failure]?
}

/// The token's scopes don't reach projects: GitHub refused the query
/// whole for asking about them.
private struct ProjectsUnreadable: Error {}

/// Whether an error says the token's scopes fall short of the query.
private func lacksScopes(_ failure: GQLTargetsResponse.Failure) -> Bool {
  failure.type == "INSUFFICIENT_SCOPES" || failure.message?.contains("required scopes") == true
}

/// One step of an error's path: a field or alias name, or a list index.
private struct GQLPathStep: Decodable {
  let name: String?

  init(from decoder: Decoder) throws {
    name = try? decoder.singleValueContainer().decode(String.self)
  }
}

/// A target key as the query addresses it. Owner and name are checked
/// against GitHub's own alphabet before they go into the query text.
private typealias QueryTarget = (owner: String, name: String, number: String)

private func queryTarget(_ key: String) -> QueryTarget? {
  guard let match = key.firstMatch(
    of: #/^https://github\.com/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)/(?:issues|pull)/(\d+)$/#
  ) else {
    return nil
  }
  return (String(match.1), String(match.2), String(match.3))
}

private func toSnapshot(_ target: GQLTarget) -> TargetSnapshot? {
  guard let updatedAt = ISODate.parse(target.updatedAt) else { return nil }
  let pull = target.__typename == "PullRequest"
  let state: String? = switch target.state {
  case "MERGED": "merged"
  case "CLOSED": "closed"
  case "OPEN": pull && target.isDraft == true ? "draft" : "open"
  default: nil
  }
  let review: String? = switch target.reviewDecision {
  case "APPROVED": "approved"
  case "CHANGES_REQUESTED": "changes_requested"
  case "REVIEW_REQUIRED": "review_required"
  default: nil
  }
  let checks: String? = switch target.commits?.values.last?.commit?.statusCheckRollup?.state {
  case "SUCCESS": "success"
  case "FAILURE", "ERROR": "failure"
  case "PENDING", "EXPECTED": "pending"
  default: nil
  }
  // The latest word is a comment or a review, whichever came later.
  let comment = target.comments?.values.last
  let reviewed = target.reviews?.values.last
  let commentAt = ISODate.parse(comment?.createdAt) ?? .distantPast
  let reviewAt = ISODate.parse(reviewed?.submittedAt) ?? .distantPast
  let lastCommenter = reviewAt > commentAt ? reviewed?.author?.login : comment?.author?.login
  return TargetSnapshot(
    title: target.title,
    state: state,
    author: target.author?.login,
    assignees: target.assignees?.values.compactMap(\.login) ?? [],
    reviewers: target.reviewRequests?.values.compactMap(\.requestedReviewer?.login) ?? [],
    labels: target.labels?.values.compactMap(\.name) ?? [],
    milestone: target.milestone?.title,
    review: review,
    checks: checks,
    merge: state == "open" ? mergeToken(target) : nil,
    status: workStatus(target),
    dueDate: projectDueDate(target),
    commentCount: target.comments?.totalCount,
    lastCommenter: lastCommenter,
    updatedAt: updatedAt,
    avatars: TargetSnapshot.avatars(
      ([target.author] + (target.assignees?.values ?? []) + (target.reviewRequests?.values.map(\.requestedReviewer) ?? []))
        .map { (login: $0?.login, url: $0?.avatarUrl) }
    )
  )
}

/// Where an open pull request stands for merging, as a merge token.
/// Conflicts win however the rest reads; "UNKNOWN" — GitHub works
/// mergeability out after it is first asked, and the next refresh has it
/// — shows none, and so does the draft state, which the kind glyph shows.
private func mergeToken(_ target: GQLTarget) -> String? {
  if target.mergeable == "CONFLICTING" {
    return "conflicts"
  }
  return switch target.mergeStateStatus {
  case "DIRTY": "conflicts"
  case "BEHIND": "behind"
  case "BLOCKED": "blocked"
  case "UNSTABLE": "unstable"
  case "CLEAN", "HAS_HOOKS": "ready"
  default: nil
  }
}

/// Where the target stands in its workflow: the status the first of its
/// projects gives it, when the token could read them; else, on a closed
/// issue, why it was closed — done with, or not to be done — which the
/// issue carries itself.
private func workStatus(_ target: GQLTarget) -> WorkStatus? {
  if let name = target.projectItems?.values.compactMap(\.status?.name).first(where: { !$0.isEmpty }) {
    return WorkStatus(name: name, stage: projectStatusStage(name))
  }
  return switch target.stateReason {
  case "COMPLETED": WorkStatus(name: "Completed", stage: "done")
  case "NOT_PLANNED": WorkStatus(name: "Not planned", stage: "canceled")
  case "DUPLICATE": WorkStatus(name: "Duplicate", stage: "canceled")
  default: nil
  }
}

/// The day the target's projects say it is due: the first date field
/// among their items' values named for a due date or deadline, or
/// failing one, a target date.
private func projectDueDate(_ target: GQLTarget) -> String? {
  let days = (target.projectItems?.values ?? []).flatMap { $0.fieldValues?.values ?? [] }
    .compactMap { value -> (name: String, date: String)? in
      guard let date = value.date, !date.isEmpty, let name = value.field?.name?.lowercased() else { return nil }
      return (name, date)
    }
  return days.first { $0.name.contains("due") || $0.name.contains("deadline") }?.date
    ?? days.first { $0.name.contains("target") }?.date
}

/// The stage a project's status stands for, read off its name: a
/// project's own are Todo, In Progress, and Done, and the names people
/// give the statuses they add tend to say which step they mean — In
/// review, Backlog, Won't fix. A name that says nothing leaves the stage
/// unsaid, and the status answers to its name alone.
func projectStatusStage(_ name: String) -> String? {
  let name = name.lowercased()
  let words = Set(name.split { !$0.isLetter }.map(String.init))
  func says(_ phrases: String...) -> Bool {
    phrases.contains { $0.contains(" ") ? name.contains($0) : words.contains($0) }
  }
  if name.contains("won't") || name.contains("wont")
      || says("not planned", "canceled", "cancelled", "duplicate", "declined", "rejected", "abandoned") {
    return "canceled"
  }
  if says("progress", "review", "doing", "development", "testing", "active", "started", "wip") {
    return "in_progress"
  }
  if says("done", "complete", "completed", "shipped", "released", "closed", "finished", "merged") {
    return "done"
  }
  if says("triage", "untriaged", "new", "inbox", "discussion") {
    return "triage"
  }
  if says("to do", "todo", "backlog", "ready", "planned", "scheduled", "open", "next") {
    return "todo"
  }
  return nil
}

private func toConversation(_ target: GQLTarget) -> TargetConversation? {
  guard let talk = target.talk else { return nil }
  let comments = talk.values.compactMap { comment -> DetailComment? in
    guard let id = comment.databaseId, let createdAt = ISODate.parse(comment.createdAt) else { return nil }
    return DetailComment(
      id: String(id),
      author: comment.author?.login,
      avatarUrl: comment.author?.avatarUrl,
      createdAt: createdAt,
      body: truncatedBody(comment.body, limit: detailTextLimit) ?? ""
    )
  }
  var reviews = (target.verdicts?.values ?? []).compactMap(toReviewEntry)
  // When older comments stayed at GitHub, so do the reviews from that
  // stretch: the timeline starts where the comments it holds start.
  if let oldest = comments.first?.createdAt, (talk.totalCount ?? 0) > comments.count {
    reviews.removeAll { $0.createdAt < oldest }
  }
  return TargetConversation(
    description: truncatedBody(target.body, limit: detailTextLimit),
    author: target.opener?.login,
    authorAvatarUrl: target.opener?.avatarUrl,
    createdAt: ISODate.parse(target.createdAt),
    comments: (comments + reviews).sorted { $0.createdAt < $1.createdAt },
    commentCount: talk.totalCount
  )
}

/// A submitted review as a conversation entry: its verdict as the event
/// token, its summary as the body. A review that only comments and says
/// nothing in its summary left its words on the diff, where the preview
/// doesn't reach — it has nothing to show.
private func toReviewEntry(_ review: GQLTarget.TalkReview) -> DetailComment? {
  guard let id = review.databaseId, let submittedAt = ISODate.parse(review.submittedAt) else { return nil }
  let body = truncatedBody(review.body, limit: detailTextLimit) ?? ""
  let event: String
  switch review.state {
  case "APPROVED": event = "approved"
  case "CHANGES_REQUESTED": event = "changes_requested"
  case "DISMISSED": event = "dismissed"
  case "COMMENTED" where !body.isEmpty: event = "reviewed"
  default: return nil
  }
  return DetailComment(
    // Reviews number apart from comments; the prefix keeps the two apart.
    id: "review-\(id)",
    author: review.author?.login,
    avatarUrl: review.author?.avatarUrl,
    createdAt: submittedAt,
    body: body,
    event: event
  )
}

/// Why GitHub left a target out, as the preview says it. GitHub answers
/// "not found" both for what is gone and for a private repository the
/// token can't see, so the token's scopes on the response decide which;
/// an organization enforcing single sign-on refuses until the token is
/// authorized for it.
private func unreadableMessage(_ failure: GQLTargetsResponse.Failure, _ http: HTTPURLResponse) -> String {
  if failure.type == "FORBIDDEN", failure.message?.contains("SAML") == true {
    return "This repository's organization uses single sign-on — authorize the token for it on GitHub (Settings → Developer settings → Personal access tokens)."
  }
  return grantsPrivateRepos(http)
    ? "GitHub couldn't find this one — it may have been deleted or moved."
    : "GitHub didn't share this one. Previews from private repositories need the token's repo scope: add it on GitHub, then paste the token again in Settings → Accounts."
}

/// A list in runs of at most `size`.
private func chunked<Element>(_ list: [Element], by size: Int) -> [[Element]] {
  stride(from: 0, to: list.count, by: size).map { Array(list[$0 ..< min($0 + size, list.count)]) }
}

/// What one subject lookup teaches us; cached per thread id + updated_at.
private struct Enrichment: Sendable {
  var state: String?
  var author: String?
  var body: String?
  var upstreamLabels: [String]?
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
    let (data, http) = try await send(request(url, token: config.token), ctx: githubContext)
    guard (200 ..< 300).contains(http.statusCode) else {
      throw statusError(http, data, githubContext)
    }
    guard let user = try? JSONDecoder().decode(GHUser.self, from: data), let login = user.login else {
      throw ProviderError(
        message: "GitHub accepted the token but returned no username — try again later.",
        details: transcript(of: http, body: data)
      )
    }
    return ProviderProfile(username: login, name: user.name, avatarUrl: user.avatar_url, note: scopeNote(http))
  }

  func fetchItems(_ config: AccountConfig, depth: FetchDepth) async throws -> FetchResult {
    var entries: [(item: FetchedItem, thread: GHNotification)] = []
    // Set once the last page is consumed. Hitting the page cap with pages
    // left — or bailing on a 304/malformed body — leaves the fetch
    // incomplete, so absence proves nothing this round (see SyncEngine).
    var complete = false

    let maxPages = depth == .full ? fullPages : recentPages
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
        throw statusError(http, data, githubContext)
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

  nonisolated var targetBatchLimit: Int { targetsPerQuery * 2 }

  func fetchTargets(_ config: AccountConfig, keys: [String], conversations: Set<String>) async throws -> TargetRound {
    var round = TargetRound()
    var talking: [(key: String, target: QueryTarget)] = []
    var quiet: [(key: String, target: QueryTarget)] = []
    for key in keys {
      guard let target = queryTarget(key) else {
        round.unreadable[key] = "Majordomo can't ask GitHub about this one."
        continue
      }
      if conversations.contains(key) {
        talking.append((key, target))
      } else {
        quiet.append((key, target))
      }
    }
    let queries = chunked(talking, by: conversationsPerQuery).map { (batch: $0, conversations: true) }
      + chunked(quiet, by: targetsPerQuery).map { (batch: $0, conversations: false) }
    // Projects are asked about until the token proves unable to read
    // them, once per round: the rest of the round asks without.
    var projects = true
    for query in queries {
      do {
        let answer: TargetRound
        do {
          answer = try await askTargets(
            query.batch, conversations: query.conversations, projects: projects, token: config.token
          )
        } catch is ProjectsUnreadable {
          projects = false
          answer = try await askTargets(
            query.batch, conversations: query.conversations, projects: false, token: config.token
          )
        }
        round.refreshed.merge(answer.refreshed) { $1 }
        round.unreadable.merge(answer.unreadable) { $1 }
      } catch {
        // What this query and the ones after it asked waits for the next
        // round; what earlier ones learned stands.
        guard !round.refreshed.isEmpty || !round.unreadable.isEmpty else {
          throw error
        }
        break
      }
    }
    return round
  }

  /// One GraphQL request for a batch of targets, an alias each. Throws
  /// `ProjectsUnreadable` when the query asked about projects and the
  /// token's scopes don't reach them.
  private func askTargets(
    _ batch: [(key: String, target: QueryTarget)], conversations: Bool, projects: Bool, token: String
  ) async throws -> TargetRound {
    var shape = "__typename ...Issue ...Pull"
    var fragments = targetFragments
    if conversations {
      shape += " ...IssueTalk ...PullTalk"
      fragments += "\n\(conversationFragments)"
    }
    if projects {
      shape += " ...IssueProject ...PullProject"
      fragments += "\n\(projectFragments)"
    }
    let aliases = batch.enumerated().map { index, entry in
      "t\(index): repository(owner: \"\(entry.target.owner)\", name: \"\(entry.target.name)\") "
        + "{ issueOrPullRequest(number: \(entry.target.number)) { \(shape) } }"
    }
    let query = "query { \(aliases.joined(separator: " ")) }\n\(fragments)"
    var request = request(URL(string: "https://api.github.com/graphql")!, token: token)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
    let (data, http) = try await send(request, ctx: githubContext)
    guard (200 ..< 300).contains(http.statusCode) else {
      throw statusError(http, data, githubContext)
    }
    let response = try? JSONDecoder().decode(GQLTargetsResponse.self, from: data)
    // A query about projects the token can't read fails as a whole, with
    // the scopes it lacks named; a query that failed whole for any other
    // reason is given the one more try without them too, since asking
    // about them is the one thing that sets it apart.
    if projects, response?.data == nil || response?.errors?.contains(where: lacksScopes) == true {
      throw ProjectsUnreadable()
    }
    guard let response, let answers = response.data else {
      let limited = response?.errors?.contains { $0.type == "RATE_LIMITED" } == true
      throw ProviderError(
        message: limited
          ? "GitHub's hourly limit for this token is used up; the refresh picks up again once it resets."
          : "GitHub couldn't answer the refresh just now.",
        details: transcript(of: http, body: data)
      )
    }
    var round = TargetRound()
    for (index, entry) in batch.enumerated() {
      let alias = "t\(index)"
      if let target = answers[alias]?.value?.issueOrPullRequest, let snapshot = toSnapshot(target) {
        round.refreshed[entry.key] = TargetRefresh(
          snapshot: snapshot,
          conversation: conversations ? toConversation(target) : nil
        )
      } else if let failure = response.errors?.first(where: { $0.path?.first?.name == alias }) {
        round.unreadable[entry.key] = unreadableMessage(failure, http)
      }
    }
    return round
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
          item.upstreamLabels = known.upstreamLabels
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
              known.upstreamLabels = subject.labels?.compactMap(\.name)
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
      items[lookup.index].upstreamLabels = lookup.known.upstreamLabels
    }

    stateCache = nextCache
    return items
  }

  // MARK: Images

  /// The signed addresses of the private images a target's bodies show, by
  /// target key, as GitHub rendered them for this token — one lookup per
  /// target however many images it shows, kept while the signatures hold.
  private var signedImages: [String: (at: Date, lookup: Task<[String: URL], any Error>)] = [:]

  /// A public image loads anonymously. One uploaded to a private
  /// repository answers only a signed-in browser — but GitHub's own
  /// rendering of the target, asked for through the API, points at a copy
  /// signed for a few minutes, which loads anonymously in turn. The token
  /// only ever goes to the API.
  func fetchImage(_ config: AccountConfig, url: URL, page: String) async throws -> Data {
    let anonymous: Error
    do {
      return try await fetchPublicImage(url)
    } catch {
      anonymous = error
    }
    guard let asset = attachmentAsset(url), let key = GitForgeVisuals.targetUrl(page)?.key else {
      throw anonymous
    }
    let signed = try await signedImageAddresses(for: key, token: config.token)
    guard let address = signed[asset] else {
      throw ProviderError(message: "GitHub didn't share this image.")
    }
    return try await fetchPublicImage(address)
  }

  private func signedImageAddresses(for key: String, token: String) async throws -> [String: URL] {
    let now = Date()
    signedImages = signedImages.filter { now.timeIntervalSince($0.value.at) < signedImageLifetime }
    if let held = signedImages[key] {
      return try await held.lookup.value
    }
    let lookup = Task {
      try await renderedImageAddresses(of: key, token: token)
    }
    signedImages[key] = (now, lookup)
    return try await lookup.value
  }
}

/// How long a signed image address is used for. GitHub signs them for five
/// minutes; a lookup older than this is asked again.
private let signedImageLifetime: TimeInterval = 4 * 60

/// The uploaded asset an image address names, by the id GitHub keeps in
/// every form of it: "github.com/user-attachments/assets/<id>",
/// "github.com/<owner>/<repo>/assets/<n>/<id>", or an already-signed
/// "private-user-images.githubusercontent.com/…-<id>.png". nil for any
/// other address.
private func attachmentAsset(_ url: URL) -> String? {
  let path = url.path()
  switch url.host()?.lowercased() {
  case "github.com":
    if let match = path.wholeMatch(of: #/(?i)/user-attachments/assets/([0-9a-f-]{36})/?/#) {
      return match.1.lowercased()
    }
    if let match = path.wholeMatch(of: #/(?i)/[^/]+/[^/]+/assets/\d+/([0-9a-f-]{36})/?/#) {
      return match.1.lowercased()
    }
    return nil
  case "private-user-images.githubusercontent.com":
    return assetId(in: path)
  default:
    return nil
  }
}

private func assetId(in text: String) -> String? {
  text.firstMatch(of: #/(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/#)
    .map { String($0.output).lowercased() }
}

/// What GitHub's rendering of a target is read for: the HTML of its
/// description, latest comments, and latest reviews — the bodies a preview
/// shows.
private struct GQLRenderedResponse: Decodable {
  struct Rendered: Decodable {
    let bodyHTML: String?
  }

  struct Target: Decodable {
    let bodyHTML: String?
    let comments: GQLNodes<Rendered>?
    let reviews: GQLNodes<Rendered>?
  }

  struct Repository: Decodable {
    let issueOrPullRequest: Target?
  }

  struct Payload: Decodable {
    let repository: Repository?
  }

  let data: Payload?
}

/// Asks GitHub to render the target's bodies and collects the signed
/// address of every private image in them, by asset id.
private func renderedImageAddresses(of key: String, token: String) async throws -> [String: URL] {
  guard let target = queryTarget(key) else {
    return [:]
  }
  let html = "bodyHTML comments(last: \(detailCommentLimit)) { nodes { bodyHTML } }"
  let query = "query { repository(owner: \"\(target.owner)\", name: \"\(target.name)\") { "
    + "issueOrPullRequest(number: \(target.number)) { ... on Issue { \(html) } "
    + "... on PullRequest { \(html) reviews(last: \(detailCommentLimit)) { nodes { bodyHTML } } } } } }"
  var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
  request.httpMethod = "POST"
  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
  let data = try await sendExpectingSuccess(request, ctx: githubContext)
  guard let rendered = try? JSONDecoder().decode(GQLRenderedResponse.self, from: data).data?.repository?
    .issueOrPullRequest else {
    return [:]
  }
  let bodies = [rendered.bodyHTML] + (rendered.comments?.values ?? []).map(\.bodyHTML)
    + (rendered.reviews?.values ?? []).map(\.bodyHTML)
  var addresses: [String: URL] = [:]
  for body in bodies.compactMap(\.self) {
    for match in body.matches(of: #/https://private-user-images\.githubusercontent\.com/[^"'\s<>]+/#) {
      let address = String(match.output).replacingOccurrences(of: "&amp;", with: "&")
      if let url = URL(string: address), let asset = assetId(in: url.path()), addresses[asset] == nil {
        addresses[asset] = url
      }
    }
  }
  return addresses
}
