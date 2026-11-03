// Shared HTTP plumbing for the provider clients: a 15-second-capped
// URLSession that keeps tokens on their own origin, and the error phrasing
// helpers. The strings surface directly in the Accounts pane, so they must
// be helpful.

import Foundation

/// Time cap applied to every request either provider makes.
let requestTimeout: TimeInterval = 15

/// Context used to phrase error messages for a given provider.
struct RequestContext: Sendable {
  /// Display name used in messages, e.g. "GitHub" or "GitLab".
  let service: String
  /// Origin shown in reachability errors, e.g. "https://gitlab.example.com".
  let origin: String
  /// True when the origin was typed by the user (self-hosted GitLab).
  let originIsUserSupplied: Bool
}

/// The request hit the 15-second cap.
func timeoutMessage(_ ctx: RequestContext) -> String {
  "\(ctx.service) did not respond within 15 seconds — \(ctx.origin) may be slow or unreachable."
}

/// The host could not be reached at all (DNS, refused connection, offline).
func unreachableMessage(_ ctx: RequestContext) -> String {
  ctx.originIsUserSupplied
    ? "Could not reach \(ctx.origin) — is the URL right?"
    : "Could not reach \(ctx.service) — check your network connection."
}

/// The host answered, but with a body that was not JSON.
func invalidJsonMessage(_ ctx: RequestContext) -> String {
  "\(ctx.service) returned a response that was not valid JSON — "
    + (ctx.originIsUserSupplied
      ? "is \(ctx.origin) really a \(ctx.service) instance?"
      : "try again later.")
}

/// The host answered with a non-success HTTP status.
func statusMessage(_ status: Int, _ ctx: RequestContext) -> String {
  switch status {
  case 401:
    return "\(ctx.service) token was rejected (401) — check the token and its scopes."
  case 403:
    return "\(ctx.service) refused the request (403) — the token may be missing scopes, or you may be rate-limited."
  case 404:
    return ctx.originIsUserSupplied
      ? "\(ctx.origin) answered with 404 — is the base URL pointing at a \(ctx.service) instance?"
      : "\(ctx.service) returned an unexpected 404 — try again later."
  default:
    if status >= 500 {
      return "\(ctx.service) is having trouble right now (HTTP \(status)) — try again later."
    }
    return "\(ctx.service) request failed (HTTP \(status))."
  }
}

/// The error a non-success HTTP status throws: its message, and whether
/// the token itself was refused.
func statusError(_ status: Int, _ ctx: RequestContext) -> ProviderError {
  ProviderError(message: statusMessage(status, ctx), rejectsToken: status == 401)
}

/// Normalizes a user-typed instance origin: trims whitespace and trailing
/// slashes, then requires an http(s) URL with a host. nil when it isn't
/// one. Shared by the add-account form (fast feedback) and the GitLab
/// client (authoritative).
func normalizeInstanceOrigin(_ raw: String) -> String? {
  var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  while trimmed.hasSuffix("/") {
    trimmed.removeLast()
  }
  guard !trimmed.isEmpty, let parsed = URL(string: trimmed),
        parsed.scheme == "http" || parsed.scheme == "https",
        parsed.host() != nil else {
    return nil
  }
  return trimmed
}

/// One shared session; both timeouts capped so no request outlives 15s.
/// Redirects pass through `RedirectGuard`, so a token never follows one
/// off the origin it was sent to.
let providerSession: URLSession = {
  let config = URLSessionConfiguration.ephemeral
  config.timeoutIntervalForRequest = requestTimeout
  config.timeoutIntervalForResource = requestTimeout
  config.httpAdditionalHeaders = ["User-Agent": "majordomo"]
  return URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
}()

/// The headers a provider client puts its token in.
private let credentialHeaders = ["Authorization", "PRIVATE-TOKEN"]

/// Keeps credentials on the origin they were sent to. An API may hand a
/// download to object storage or a CDN by redirect, and whatever answers
/// there must never see the token: a redirect off the request's origin
/// loses the credential headers before it is followed. A redirect from
/// https down to plain http isn't followed at all. Moving from http to
/// https on the same host keeps them — that is the same server, made safer.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    guard let origin = task.originalRequest?.url ?? response.url, let next = request.url else {
      return nil
    }
    if origin.scheme == "https", next.scheme != "https" {
      return nil
    }
    guard !sameServer(origin, next) else {
      return request
    }
    var stripped = request
    for header in credentialHeaders {
      stripped.setValue(nil, forHTTPHeaderField: header)
    }
    return stripped
  }

  /// Same host and port, or the same host moved from http to https on the
  /// default ports.
  private func sameServer(_ from: URL, _ to: URL) -> Bool {
    guard let fromHost = from.host()?.lowercased(), fromHost == to.host()?.lowercased() else {
      return false
    }
    let fromPort = from.port ?? defaultPort(from.scheme)
    let toPort = to.port ?? defaultPort(to.scheme)
    if from.scheme == to.scheme {
      return fromPort == toPort
    }
    return from.scheme == "http" && to.scheme == "https" && fromPort == 80 && toPort == 443
  }

  private func defaultPort(_ scheme: String?) -> Int? {
    switch scheme {
    case "https": 443
    case "http": 80
    default: nil
    }
  }
}

/// Performs a request, mapping transport failures to UI-ready messages.
/// Status handling is the caller's (GitHub needs 304 passed through).
func send(_ request: URLRequest, ctx: RequestContext) async throws -> (Data, HTTPURLResponse) {
  do {
    let (data, response) = try await providerSession.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ProviderError(message: unreachableMessage(ctx))
    }
    return (data, http)
  } catch let error as ProviderError {
    throw error
  } catch let error as URLError where error.code == .timedOut {
    throw ProviderError(message: timeoutMessage(ctx))
  } catch is CancellationError {
    throw CancellationError()
  } catch {
    throw ProviderError(message: unreachableMessage(ctx))
  }
}

/// Requires a 2xx answer; anything else becomes a status message.
func sendExpectingSuccess(_ request: URLRequest, ctx: RequestContext) async throws -> Data {
  let (data, http) = try await send(request, ctx: ctx)
  guard (200 ..< 300).contains(http.statusCode) else {
    throw statusError(http.statusCode, ctx)
  }
  return data
}

/// ISO 8601 parsing tolerant of both fractional (GitLab) and whole-second
/// (GitHub) timestamps.
enum ISODate {
  private static let whole = Date.ISO8601FormatStyle()
  private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

  static func parse(_ raw: String?) -> Date? {
    guard let raw else { return nil }
    return (try? whole.parse(raw)) ?? (try? fractional.parse(raw))
  }

  static func format(_ date: Date) -> String {
    whole.format(date)
  }
}
