// GitLab provider client for self-hosted instances, ported from
// src/providers/gitlab.ts. config.baseUrl is the instance origin (e.g.
// "https://gitlab.example.com") and is required.

import Foundation

private let maxPages = 2
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
    /// Last activity on the issue/MR itself — comments, merges, closes.
    let updated_at: String?
    /// "opened" | "merged" | "closed" (also "locked" on some instances).
    let state: String?
    /// Present on MergeRequest targets; older instances only send work_in_progress.
    let draft: Bool?
    let work_in_progress: Bool?
    /// Whoever opened the issue/MR.
    let author: GLAuthor?
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
    author: todo.target?.author?.username ?? todo.author?.username
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

  func fetchItems(_ config: AccountConfig) async throws -> FetchResult {
    let baseUrl = try resolveBaseUrl(config)
    let ctx = context(baseUrl)
    // Pending todos are the inbox; one page of recently-done todos rides
    // along so items handled on the web while the app was closed still
    // arrive (as already-read).
    let lists: [(state: String, maxPages: Int, read: Bool)] = [
      (state: "pending", maxPages: maxPages, read: false),
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
}
