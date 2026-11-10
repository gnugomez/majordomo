// GitLab provider client for self-hosted instances. config.baseUrl is the
// instance origin (e.g. "https://gitlab.example.com") and is required.

import Foundation

/// Pending pages per depth: .recent skims the newest todos; .full walks the
/// whole backlog, bounded by a safety ceiling (20 × 50 = 1,000 todos).
private let recentPendingPages = 2
private let fullPendingPages = 20
private let perPage = 50

// Minimal shapes: only the fields we read, all optional so entries missing
// what we require are skipped one by one.

private struct GLUser: Decodable {
  let username: String?
  let name: String?
  let avatar_url: String?
}

private struct GLTodo: Decodable {
  struct Target: Decodable {
    let title: String?
    let description: String?
    /// Last activity on the issue/MR itself — comments, merges, closes.
    let updated_at: String?
    /// "opened" | "merged" | "closed" (also "locked" on some instances).
    let state: String?
    /// Present on MergeRequest targets; older instances only send work_in_progress.
    let draft: Bool?
    let work_in_progress: Bool?
    /// Whoever opened the issue/MR.
    let author: GLAuthor?
    /// The issue/MR's own labels, by name.
    let labels: [String]?
  }

  struct GLAuthor: Decodable {
    let username: String?
    let avatar_url: String?
  }

  let id: Int
  let action_name: String
  let created_at: String
  /// Bumped when GitLab refreshes the todo (re-mention, re-assignment).
  let updated_at: String?
  let target_type: String
  let target_url: String
  let target: Target?
  let project: GLProject?
  /// Whoever triggered the todo (fallback author when the target lacks one).
  let author: GLAuthor?
  let body: String?

  struct GLProject: Decodable {
    let path_with_namespace: String?
  }
}

private struct GLNote: Decodable {
  let id: Int
  let body: String?
  let author: GLTodo.GLAuthor?
  let created_at: String
  /// GitLab's own entries ("added 1 commit", "changed the description").
  let system: Bool?
}

/// What a board refresh reads off an issue or merge request; the
/// merge-request-only fields come back nil on an issue.
private struct GLTargetState: Decodable {
  struct Milestone: Decodable {
    let title: String?
  }

  struct Pipeline: Decodable {
    let status: String?
  }

  let title: String?
  let description: String?
  let state: String?
  let draft: Bool?
  let work_in_progress: Bool?
  let updated_at: String?
  /// When it was opened — its description's date in a preview.
  let created_at: String?
  let author: GLTodo.GLAuthor?
  let assignees: [GLTodo.GLAuthor]?
  let reviewers: [GLTodo.GLAuthor]?
  let labels: [String]?
  let milestone: Milestone?
  /// The day an issue is due ("2026-11-12").
  let due_date: String?
  /// Comments by people, GitLab's own system notes left out.
  let user_notes_count: Int?
  let head_pipeline: Pipeline?
  /// What stands between the merge request and a merge ("mergeable",
  /// "conflict", "not_approved"…; "requested_changes" on newer instances
  /// once a reviewer asks for changes).
  let detailed_merge_status: String?
}

private struct GLApprovals: Decodable {
  struct Approver: Decodable {
    let user: GLTodo.GLAuthor?
  }

  let approved: Bool?
  let approved_by: [Approver]?
}

/// What the status query asks of each work item: its status widget's
/// name and category. Statuses are GraphQL's alone; the issues API
/// doesn't carry them.
private let statusWidget = "widgets { ... on WorkItemWidgetStatus { status { name category } } }"

/// The status query's answer: a project per alias, its work items each
/// with the widgets asked for, of which only the status widget has a
/// status.
private struct GLStatusResponse: Decodable {
  struct Project: Decodable {
    struct Items: Decodable {
      let nodes: [Failable<WorkItem>]?
    }

    let workItems: Items?
  }

  struct WorkItem: Decodable {
    struct Widget: Decodable {
      let status: Status?
    }

    struct Status: Decodable {
      let name: String?
      /// "TRIAGE", "TO_DO", "IN_PROGRESS", "DONE", or "CANCELED", in
      /// either case.
      let category: String?
    }

    let iid: String?
    let widgets: [Failable<Widget>]?

    var status: Status? {
      widgets?.compactMap(\.value?.status).first
    }
  }

  let data: [String: Failable<Project>]?
}

/// Targets one refresh round reads at most. GitLab answers one target per
/// request — its notes take another, a merge request's approvals a third
/// — so a round stays small and the rest wait for the next.
private let targetsPerRound = 15
/// Requests in flight at once during a refresh.
private let targetConcurrency = 4

/// A pipeline status as a checks token; statuses that settle nothing
/// (skipped, manual, canceled) show none.
private func checksToken(_ status: String?) -> String? {
  switch status {
  case "success": "success"
  case "failed": "failure"
  case "created", "waiting_for_resource", "preparing", "pending", "running", "scheduled": "pending"
  default: nil
  }
}

/// A detailed merge status as a merge token. The statuses GitLab is still
/// working out show none, as does the draft status, which the kind glyph
/// shows; any other status that isn't mergeable holds the merge, and the
/// review and checks marks say why.
private func mergeToken(_ status: String?) -> String? {
  switch status {
  case nil, "unchecked", "checking", "preparing", "approvals_syncing", "draft_status", "not_open": nil
  case "mergeable": "ready"
  case "conflict", "broken_status": "conflicts"
  case "need_rebase": "behind"
  case "discussions_not_resolved": "unresolved"
  default: "blocked"
  }
}

/// A status category as a stage token. The reference spells the
/// categories in capitals; gitlab.com answers them in lower case.
private func stageToken(_ category: String?) -> String? {
  switch category?.uppercased() {
  case "TRIAGE": "triage"
  case "TO_DO": "todo"
  case "IN_PROGRESS": "in_progress"
  case "DONE": "done"
  case "CANCELED": "canceled"
  default: nil
  }
}

/// Notes a refresh reads to find the latest comments: system notes crowd
/// a busy merge request, so it reads past them.
private let notePage = 50

/// Where a target sits in the API, read off its key
/// (`{origin}/{project}/-/issues/{iid}`): the project, and the collection
/// and number.
private struct GLTargetRef {
  let project: String
  let collection: String
  let iid: String

  /// The target's API url under the instance origin. GitLab addresses a
  /// project by its whole path, slashes encoded.
  func apiUrl(origin: String) -> String {
    let project = project.replacingOccurrences(of: "/", with: "%2F")
    return "\(origin)/api/v4/projects/\(project)/\(collection)/\(iid)"
  }

  /// Whether the project's path is one GitLab could have given — letters,
  /// digits, and a few marks — and so safe to write into a query.
  var hasPlainProject: Bool {
    project.wholeMatch(of: #/[A-Za-z0-9_.\-/]+/#) != nil
  }
}

private func targetRef(_ key: String, origin: String) -> GLTargetRef? {
  guard key.hasPrefix(origin + "/"),
        let match = key.dropFirst(origin.count + 1).firstMatch(of: #/^(.+?)/-/(issues|merge_requests)/(\d+)$/#) else {
    return nil
  }
  return GLTargetRef(project: String(match.1), collection: String(match.2), iid: String(match.3))
}

/// One GET's answer.
private enum Fetched<T> {
  case found(T)
  /// 404: gone, or out of the account's reach.
  case missing
  /// Any other failure, or an answer that wouldn't decode.
  case failed
}

/// What one target's refresh came to.
private enum TargetAnswer {
  case refreshed(TargetRefresh)
  /// GitLab won't show it; the reason, fit to show.
  case unreadable(String)
  /// The request failed in a way that says nothing of the target.
  case unanswered
}

private func toDetailComment(_ note: GLNote) -> DetailComment? {
  guard let createdAt = ISODate.parse(note.created_at) else { return nil }
  return DetailComment(
    id: String(note.id),
    author: note.author?.username,
    avatarUrl: note.author?.avatar_url,
    createdAt: createdAt,
    body: truncatedBody(note.body, limit: detailTextLimit) ?? ""
  )
}

/// A system note worth a place in the conversation, as an event: a merge
/// request's approval given, taken back, or changes asked for. GitLab
/// words these the same on every instance; its other system notes
/// (commits pushed, labels changed…) stay out.
private func toReviewEvent(_ note: GLNote) -> DetailComment? {
  let body = note.body ?? ""
  let event: String
  if body.hasPrefix("approved this merge request") {
    event = "approved"
  } else if body.hasPrefix("unapproved this merge request") {
    event = "unapproved"
  } else if body.hasPrefix("requested changes") {
    event = "changes_requested"
  } else {
    return nil
  }
  guard var entry = toDetailComment(note) else { return nil }
  entry.body = ""
  entry.event = event
  return entry
}

/// The conversation as a refresh found it: the latest comments by people,
/// and the review events among the notes since the oldest of them, oldest
/// first. `notes` come newest first.
private func toConversation(_ target: GLTargetState, notes: [GLNote]) -> TargetConversation {
  let people = notes.filter { $0.system != true }.prefix(detailCommentLimit)
  let comments = people.compactMap(toDetailComment)
  let oldest = comments.last?.createdAt ?? .distantPast
  let truncated = (target.user_notes_count ?? 0) > comments.count
  let events = notes.filter { $0.system == true }.compactMap(toReviewEvent)
    .filter { !truncated || $0.createdAt >= oldest }
  return TargetConversation(
    description: truncatedBody(target.description, limit: detailTextLimit),
    author: target.author?.username,
    authorAvatarUrl: target.author?.avatar_url,
    createdAt: ISODate.parse(target.created_at),
    comments: (comments + events).sorted { $0.createdAt < $1.createdAt },
    commentCount: target.user_notes_count
  )
}

/// Normalizes and validates the user-supplied base URL. Throws a UI-ready message.
private func resolveBaseUrl(_ config: AccountConfig) throws -> String {
  let raw = (config.baseUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  if raw.isEmpty {
    throw ProviderError(
      message: "GitLab needs the URL of your instance (e.g. https://gitlab.example.com) — add it in the Accounts pane."
    )
  }
  guard let origin = normalizeInstanceOrigin(raw) else {
    throw ProviderError(
      message: "\"\(raw)\" does not look like a URL — expected something like https://gitlab.example.com."
    )
  }
  return origin
}

private func context(_ baseUrl: String) -> RequestContext {
  RequestContext(service: "GitLab", origin: baseUrl, originIsUserSupplied: true)
}

/// GitLab todo `action_name` values → this provider's reason tokens.
/// Anything unmapped (or new the API starts sending) lands on "activity".
private let gitlabReasons: [String: String] = [
  "mentioned": "mentioned",
  "directly_addressed": "mentioned",
  "review_requested": "review_requested",
  "approval_required": "approval_required",
  "assigned": "assigned",
  "marked": "subscribed",
]

private func gitlabReason(_ raw: String) -> String {
  gitlabReasons[raw] ?? "activity"
}

/// Upstream lifecycle state token, when the todo's target carries it.
private func toItemState(_ todo: GLTodo) -> String? {
  guard let target = todo.target else { return nil }
  return stateToken(
    target.state, mergeRequest: todo.target_type == "MergeRequest",
    draft: target.draft == true || target.work_in_progress == true, title: target.title
  )
}

/// GitLab's state as this provider's token. An open MR that is still a
/// draft reads better as "draft"; the title prefix backstops older
/// instances that omit the boolean fields.
private func stateToken(_ state: String?, mergeRequest: Bool, draft: Bool, title: String?) -> String? {
  switch state {
  case "opened":
    if mergeRequest,
       draft || (title ?? "").range(of: "^Draft:", options: [.regularExpression, .caseInsensitive]) != nil {
      return "draft"
    }
    return "open"
  case "merged":
    return "merged"
  case "closed":
    return "closed"
  default:
    return nil
  }
}

/// The todo's `body` carries the comment that triggered a mention — the most
/// useful preview there is — but assigned/marked todos just repeat the
/// target's title in it; those fall through to the target's own description.
private func bodyText(_ todo: GLTodo) -> String? {
  if let body = todo.body, !body.isEmpty, body != todo.target?.title {
    return body
  }
  return todo.target?.description
}

private func toFetchedItem(_ todo: GLTodo) -> FetchedItem? {
  // Last activity on the target, like GitHub's thread.updated_at — the
  // todo's own dates only move on todo actions, so a plain comment or a
  // merge would never re-sort the item.
  guard let updatedAt = ISODate.parse(todo.target?.updated_at)
    ?? ISODate.parse(todo.updated_at)
    ?? ISODate.parse(todo.created_at) else {
    return nil
  }
  let reason = gitlabReason(todo.action_name)
  return FetchedItem(
    externalId: String(todo.id),
    kind: todo.target_type == "MergeRequest" ? "merge" : "issue",
    title: todo.target?.title ?? todo.body ?? "(untitled)",
    repo: todo.project?.path_with_namespace ?? "",
    url: todo.target_url,
    reason: reason,
    isMention: GitForgeVisuals.isMention(reason),
    updatedAt: updatedAt,
    state: toItemState(todo),
    author: todo.target?.author?.username ?? todo.author?.username,
    body: truncatedBody(bodyText(todo)),
    upstreamLabels: todo.target?.labels
  )
}

struct GitLabClient: ProviderClient {
  let id: ProviderId = .gitlab

  private func request(_ url: URL, token: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
    return request
  }

  func validate(_ config: AccountConfig) async throws -> ProviderProfile {
    let baseUrl = try resolveBaseUrl(config)
    let ctx = context(baseUrl)
    guard let url = URL(string: "\(baseUrl)/api/v4/user") else {
      throw ProviderError(message: unreachableMessage(ctx))
    }
    let data = try await sendExpectingSuccess(request(url, token: config.token), ctx: ctx)
    guard let user = try? JSONDecoder().decode(GLUser.self, from: data), let username = user.username else {
      if (try? JSONSerialization.jsonObject(with: data)) == nil {
        throw ProviderError(message: invalidJsonMessage(ctx))
      }
      throw ProviderError(
        message: "\(baseUrl) accepted the token but returned no username — is it really a GitLab instance?"
      )
    }
    return ProviderProfile(username: username, name: user.name, avatarUrl: user.avatar_url)
  }

  func fetchItems(_ config: AccountConfig, depth: FetchDepth) async throws -> FetchResult {
    let baseUrl = try resolveBaseUrl(config)
    let ctx = context(baseUrl)
    // Pending todos are the inbox; one page of recently-done todos rides
    // along so items handled on the web while the app was closed still
    // arrive (as already-read). Done stays at one page even on a full
    // fetch — walking the done archive would only import ancient history.
    let pendingPages = depth == .full ? fullPendingPages : recentPendingPages
    let lists: [(state: String, maxPages: Int, read: Bool)] = [
      (state: "pending", maxPages: pendingPages, read: false),
      (state: "done", maxPages: 1, read: true),
    ]
    var items: [FetchedItem] = []
    // Only the pending list decides completeness: it is the authoritative
    // inbox, and a pending item beyond its page cap must not be treated as
    // absent (see SyncEngine). The done list is a bonus feed of items
    // already handled upstream — truncating it loses nothing.
    var complete = true
    for list in lists {
      var todos: [GLTodo] = []
      var decodedOk = true
      for page in 1 ... list.maxPages {
        var components = URLComponents(string: "\(baseUrl)/api/v4/todos")!
        components.queryItems = [
          URLQueryItem(name: "state", value: list.state),
          URLQueryItem(name: "per_page", value: String(perPage)),
          URLQueryItem(name: "page", value: String(page)),
        ]
        guard let url = components.url else {
          throw ProviderError(message: unreachableMessage(ctx))
        }
        let data = try await sendExpectingSuccess(request(url, token: config.token), ctx: ctx)
        guard let body = try? JSONDecoder().decode([Failable<GLTodo>].self, from: data) else {
          decodedOk = false
          break
        }
        todos.append(contentsOf: body.compactMap(\.value))
        if body.count < perPage {
          break
        }
      }
      if !decodedOk {
        if list.state == "pending" {
          complete = false
        }
        continue
      }
      if list.state == "pending", todos.count >= list.maxPages * perPage {
        complete = false
      }
      for todo in todos {
        // One malformed todo must not kill the whole fetch.
        if var item = toFetchedItem(todo) {
          item.upstreamRead = list.read
          items.append(item)
        }
      }
    }
    return FetchResult(items: items, complete: complete)
  }

  var targetBatchLimit: Int { targetsPerRound }

  func fetchTargets(_ config: AccountConfig, keys: [String], conversations: Set<String>) async throws -> TargetRound {
    let baseUrl = try resolveBaseUrl(config)
    let ctx = context(baseUrl)
    let token = config.token
    var round = TargetRound()
    // The round's issues' statuses first, in one request: a work item's
    // status is GraphQL's alone, and a round's issues fit one query. An
    // instance without statuses answers none, and the targets go on
    // without.
    let issues = keys.compactMap { key -> (key: String, ref: GLTargetRef)? in
      guard let ref = targetRef(key, origin: baseUrl), ref.collection == "issues" else { return nil }
      return (key, ref)
    }
    let statuses = await fetchStatuses(issues, token: token, origin: baseUrl, ctx: ctx)
    for start in stride(from: 0, to: keys.count, by: targetConcurrency) {
      let wave = keys[start ..< min(start + targetConcurrency, keys.count)]
      do {
        try await withThrowingTaskGroup(of: (String, TargetAnswer).self) { group in
          for key in wave {
            guard let ref = targetRef(key, origin: baseUrl), let url = URL(string: ref.apiUrl(origin: baseUrl)) else {
              round.unreadable[key] = "Majordomo can't ask GitLab about this one."
              continue
            }
            let conversation = conversations.contains(key)
            group.addTask {
              let answer = try await self.refreshTarget(
                url, mergeRequest: ref.collection == "merge_requests", conversation: conversation,
                status: statuses[key], token: token, ctx: ctx
              )
              return (key, answer)
            }
          }
          for try await (key, answer) in group {
            switch answer {
            case .refreshed(let refresh): round.refreshed[key] = refresh
            case .unreadable(let reason): round.unreadable[key] = reason
            case .unanswered: break
            }
          }
        }
      } catch {
        // A refused token or a rate limit would fail the rest alike: they
        // wait for the next round, and what earlier waves learned stands.
        guard !round.refreshed.isEmpty || !round.unreadable.isEmpty else {
          throw error
        }
        break
      }
    }
    return round
  }

  /// One target: the issue or merge request itself, its approvals for a
  /// merge request, and its latest notes — for the latest comment's
  /// author, and the conversation when one is wanted. An issue's status
  /// came ahead of the round (`fetchStatuses`). A rejected token or a
  /// refusal of the target itself throws, since every other target would
  /// fail the same way.
  private func refreshTarget(
    _ url: URL, mergeRequest: Bool, conversation: Bool, status: WorkStatus?, token: String, ctx: RequestContext
  ) async throws -> TargetAnswer {
    let target: GLTargetState
    switch try await getTarget(url, token: token, ctx: ctx) as Fetched<GLTargetState> {
    case .found(let found): target = found
    case .missing:
      return .unreadable("GitLab couldn't find this one — it may have been deleted, or your account no longer has access.")
    case .failed: return .unanswered
    }
    guard let updatedAt = ISODate.parse(target.updated_at) else {
      return .unanswered
    }
    // Approvals and notes are extras: an instance or tier that refuses
    // them still leaves the target itself.
    var approvals: GLApprovals?
    if mergeRequest,
       case .found(let found)? = try? await getTarget(url.appending(path: "approvals"), token: token, ctx: ctx)
         as Fetched<GLApprovals> {
      approvals = found
    }
    let approvers = Set((approvals?.approved_by ?? []).compactMap(\.user?.username))
    let reviewers = (target.reviewers ?? []).compactMap(\.username)
    let review: String? = if !mergeRequest {
      nil
    } else if target.detailed_merge_status == "requested_changes" {
      "changes_requested"
    } else if approvals?.approved == true, !approvers.isEmpty {
      "approved"
    } else if !reviewers.isEmpty {
      "review_required"
    } else {
      nil
    }
    // The latest notes, newest first; none to read when the count says
    // there are none — unless a merge request's conversation is wanted,
    // since its approvals are notes of GitLab's own — and nil when the
    // read failed.
    var notes: [GLNote]? = []
    if (target.user_notes_count ?? 0) > 0 || (conversation && mergeRequest) {
      notes = await latestNotes(of: url, token: token, ctx: ctx)
    }
    let state = stateToken(
      target.state, mergeRequest: mergeRequest,
      draft: target.draft == true || target.work_in_progress == true, title: target.title
    )
    let people = notes?.filter { $0.system != true }
    let snapshot = TargetSnapshot(
      title: target.title ?? "",
      state: state,
      author: target.author?.username,
      assignees: (target.assignees ?? []).compactMap(\.username),
      reviewers: reviewers.filter { !approvers.contains($0) },
      labels: target.labels ?? [],
      milestone: target.milestone?.title,
      review: review,
      checks: checksToken(target.head_pipeline?.status),
      merge: mergeRequest && state == "open" ? mergeToken(target.detailed_merge_status) : nil,
      status: status,
      dueDate: target.due_date,
      commentCount: target.user_notes_count,
      lastCommenter: people?.first?.author?.username,
      updatedAt: updatedAt,
      avatars: TargetSnapshot.avatars(
        ([target.author] + (target.assignees ?? []) + (target.reviewers ?? []))
          .map { (login: $0?.username, url: $0?.avatar_url) }
      )
    )
    // A conversation whose notes didn't come is left for the next round.
    let talk = conversation ? notes.map { toConversation(target, notes: $0) } : nil
    return .refreshed(TargetRefresh(snapshot: snapshot, conversation: talk))
  }

  /// A target's latest notes, GitLab's own among them, newest first; nil
  /// when they couldn't be read.
  private func latestNotes(of url: URL, token: String, ctx: RequestContext) async -> [GLNote]? {
    var components = URLComponents(url: url.appending(path: "notes"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "sort", value: "desc"),
      URLQueryItem(name: "order_by", value: "created_at"),
      URLQueryItem(name: "per_page", value: String(notePage)),
    ]
    guard let notesUrl = components?.url,
          case .found(let notes)? = try? await getTarget(notesUrl, token: token, ctx: ctx) as Fetched<[Failable<GLNote>]> else {
      return nil
    }
    return notes.compactMap(\.value)
  }

  /// One GET for a refresh, decoded. `read_api` reads everything a
  /// refresh asks for, so a 404 means the target is gone or out of the
  /// account's reach, not a missing scope. A rejected token and a refusal
  /// throw.
  private func getTarget<T: Decodable>(_ url: URL, token: String, ctx: RequestContext) async throws -> Fetched<T> {
    let (data, http) = try await send(request(url, token: token), ctx: ctx)
    if http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 429 {
      throw statusError(http.statusCode, ctx)
    }
    if http.statusCode == 404 {
      return .missing
    }
    guard (200 ..< 300).contains(http.statusCode), let decoded = try? JSONDecoder().decode(T.self, from: data) else {
      return .failed
    }
    return .found(decoded)
  }

  /// The workflow statuses of a round's issues, by key: one GraphQL
  /// request, an alias per project, each asking its work items by iid.
  /// Statuses are an extra: an instance too old to have them refuses the
  /// query whole, a tier without them (they are Premium's and Ultimate's)
  /// lists no status widget, and either leaves the issues without one.
  private func fetchStatuses(
    _ issues: [(key: String, ref: GLTargetRef)], token: String, origin: String, ctx: RequestContext
  ) async -> [String: WorkStatus] {
    let projects = Dictionary(grouping: issues.filter(\.ref.hasPlainProject), by: \.ref.project)
    let paths = projects.keys.sorted()
    guard !paths.isEmpty, let url = URL(string: "\(origin)/api/graphql") else {
      return [:]
    }
    // Each alias asks for a page the size of its list: GitLab prices a
    // query by the page it might return, a page of a hundred costs more
    // than a request may, and five projects' worth refused the round.
    let aliases = paths.enumerated().map { index, path in
      let refs = projects[path] ?? []
      let iids = refs.map { "\"\($0.ref.iid)\"" }.joined(separator: ", ")
      return "p\(index): project(fullPath: \"\(path)\") "
        + "{ workItems(iids: [\(iids)], first: \(refs.count)) { nodes { iid \(statusWidget) } } }"
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": "query { \(aliases.joined(separator: " ")) }"])
    guard let (data, http) = try? await send(request, ctx: ctx), (200 ..< 300).contains(http.statusCode),
          let answers = (try? JSONDecoder().decode(GLStatusResponse.self, from: data))?.data else {
      return [:]
    }
    var statuses: [String: WorkStatus] = [:]
    for (index, path) in paths.enumerated() {
      let items = answers["p\(index)"]?.value?.workItems?.nodes?.compactMap(\.value) ?? []
      let byIid = Dictionary(items.compactMap { item in item.iid.map { ($0, item) } }) { first, _ in first }
      for issue in projects[path] ?? [] {
        if let status = byIid[issue.ref.iid]?.status, let name = status.name, !name.isEmpty {
          statuses[issue.key] = WorkStatus(name: name, stage: stageToken(status.category))
        }
      }
    }
    return statuses
  }

  // MARK: Images

  /// A file uploaded to a project on this instance comes through the API
  /// with the token — the only way into a project that keeps its uploads
  /// private (GitLab 17.4 and later) — and only over https. Anything else,
  /// and an instance whose API doesn't have the file, loads anonymously.
  func fetchImage(_ config: AccountConfig, url: URL, page: String) async throws -> Data {
    let baseUrl = try resolveBaseUrl(config)
    if baseUrl.hasPrefix("https://"), let upload = projectUpload(url, origin: baseUrl),
       let apiUrl = URL(string: upload.apiUrl(origin: baseUrl)),
       let data = try? await imageData(for: request(apiUrl, token: config.token), ctx: context(baseUrl)) {
      return data
    }
    return try await fetchPublicImage(url)
  }
}

/// A file uploaded to a project, as its web address names it:
/// `{origin}/{project}/uploads/{secret}/{file}`, or GitLab's own
/// `{origin}/-/project/{id}/uploads/{secret}/{file}`.
private struct GLProjectUpload {
  /// The project's path or numeric id.
  let project: String
  let secret: String
  /// The file name, percent-encoded as in the address.
  let file: String

  func apiUrl(origin: String) -> String {
    let project = project.replacingOccurrences(of: "/", with: "%2F")
    return "\(origin)/api/v4/projects/\(project)/uploads/\(secret)/\(file)"
  }
}

/// The upload an address names, when it is one on this instance — the
/// only addresses the token is ever sent for.
private func projectUpload(_ url: URL, origin: String) -> GLProjectUpload? {
  let address = url.absoluteString
  guard url.query() == nil, url.fragment() == nil, address.hasPrefix(origin + "/") else {
    return nil
  }
  let path = address.dropFirst(origin.count + 1)
  if let match = path.wholeMatch(of: #/-/project/(\d+)/uploads/([0-9a-f]{32})/([^/]+)/#) {
    return GLProjectUpload(project: String(match.1), secret: String(match.2), file: String(match.3))
  }
  guard let match = path.wholeMatch(of: #/([A-Za-z0-9_.\-/]+?)/uploads/([0-9a-f]{32})/([^/]+)/#),
        !match.1.split(separator: "/").contains(where: { $0 == "." || $0 == ".." || $0 == "-" }) else {
    return nil
  }
  return GLProjectUpload(project: String(match.1), secret: String(match.2), file: String(match.3))
}
