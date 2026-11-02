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

/// The fields the preview reads off an issue or merge request.
private struct GLIssuable: Decodable {
  let description: String?
  /// Comments by people, GitLab's own system notes left out.
  let user_notes_count: Int?
}

private struct GLNote: Decodable {
  let id: Int
  let body: String?
  let author: GLTodo.GLAuthor?
  let created_at: String
  /// GitLab's own entries ("added 1 commit", "changed the description").
  let system: Bool?
}

/// Notes a detail fetch reads to find the latest comments: system notes
/// crowd a busy merge request, so it reads past them.
private let detailNotePage = 50

/// Where an item's target sits in the API, read off its web url
/// (`{origin}/{project}/-/issues/{iid}#note_{id}`): the project, the
/// collection and number, and the note the todo pointed at, if any.
private struct GLTargetRef {
  let project: String
  let collection: String
  let iid: String
  let noteId: String?

  /// The target's API url under the instance origin. GitLab addresses a
  /// project by its whole path, slashes encoded.
  func apiUrl(origin: String) -> String {
    let project = project.replacingOccurrences(of: "/", with: "%2F")
    return "\(origin)/api/v4/projects/\(project)/\(collection)/\(iid)"
  }
}

private func detailTarget(_ url: String, origin: String) -> GLTargetRef? {
  guard url.hasPrefix(origin + "/"),
        let match = url.dropFirst(origin.count + 1).firstMatch(
          of: #/^(.+?)/-/(issues|merge_requests)/(\d+)(?:#note_(\d+))?$/#
        ) else {
    return nil
  }
  return GLTargetRef(
    project: String(match.1), collection: String(match.2), iid: String(match.3), noteId: match.4.map(String.init)
  )
}

private func toDetailComment(_ note: GLNote) -> DetailComment? {
  guard let createdAt = ISODate.parse(note.created_at) else { return nil }
  return DetailComment(
    id: String(note.id),
    author: note.author?.username,
    createdAt: createdAt,
    body: truncatedBody(note.body, limit: detailTextLimit) ?? ""
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
  switch target.state {
  case "opened":
    // An open MR that is still a draft reads better as "draft". The title
    // prefix backstops older instances that omit the boolean fields.
    if todo.target_type == "MergeRequest",
       target.draft == true
       || target.work_in_progress == true
       || (target.title ?? "").range(of: "^Draft:", options: [.regularExpression, .caseInsensitive]) != nil {
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

  func fetchDetail(_ config: AccountConfig, item: InboxItem) async throws -> ItemDetail? {
    let baseUrl = try resolveBaseUrl(config)
    let ctx = context(baseUrl)
    guard let target = detailTarget(item.url, origin: baseUrl),
          let targetUrl = URL(string: target.apiUrl(origin: baseUrl)) else {
      return nil
    }
    let issuable: GLIssuable = try await getDetail(targetUrl, token: config.token, ctx: ctx)
    let comments = await latestComments(of: targetUrl, token: config.token, ctx: ctx)
    var trigger = target.noteId.flatMap { id in comments.first { $0.id == id } }
    if trigger == nil, let id = target.noteId {
      let note: GLNote? = try? await getDetail(targetUrl.appending(path: "notes/\(id)"), token: config.token, ctx: ctx)
      trigger = note.flatMap(toDetailComment)
    }
    return ItemDetail(
      description: truncatedBody(issuable.description, limit: detailTextLimit),
      trigger: trigger,
      comments: comments,
      commentCount: issuable.user_notes_count
    )
  }

  /// The latest comments by people, oldest first; a failure leaves the
  /// conversation out rather than failing the whole preview.
  private func latestComments(of targetUrl: URL, token: String, ctx: RequestContext) async -> [DetailComment] {
    var components = URLComponents(url: targetUrl.appending(path: "notes"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "sort", value: "desc"),
      URLQueryItem(name: "order_by", value: "created_at"),
      URLQueryItem(name: "per_page", value: String(detailNotePage)),
    ]
    guard let url = components?.url,
          let notes: [Failable<GLNote>] = try? await getDetail(url, token: token, ctx: ctx) else {
      return []
    }
    let people = notes.compactMap(\.value).filter { $0.system != true }
    return people.prefix(detailCommentLimit).reversed().compactMap(toDetailComment)
  }

  /// One GET for the preview, decoded. `read_api` reads everything the
  /// preview shows, so a 404 here means the target is gone or out of the
  /// account's reach — not a missing scope.
  private func getDetail<T: Decodable>(_ url: URL, token: String, ctx: RequestContext) async throws -> T {
    let (data, http) = try await send(request(url, token: token), ctx: ctx)
    if http.statusCode == 404 {
      throw ProviderError(message: "GitLab couldn't find this one — it may have been deleted, or your account no longer has access.")
    }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ProviderError(message: statusMessage(http.statusCode, ctx))
    }
    guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
      throw ProviderError(message: invalidJsonMessage(ctx))
    }
    return decoded
  }
}
