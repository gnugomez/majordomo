// What the provider clients share for the images a target's bodies show:
// resolving the address a body writes, and fetching the bytes — with no
// credentials at all unless a client builds the request itself for its own
// origin. A token never goes to an image host; `RedirectGuard` keeps one
// from following a redirect there.

import Foundation

/// The most an image may weigh; anything heavier stays a link.
let imageByteLimit = 20 * 1024 * 1024

/// A reference a body makes — a link or an image source, as written —
/// resolved against the target page it appears on. nil when it names
/// nothing on the web.
func resolveBodyReference(_ reference: String, page: String) -> URL? {
  let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
  let base = URL(string: page)
  let parsed = URL(string: trimmed, relativeTo: base)
    ?? trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap { URL(string: $0, relativeTo: base) }
  guard let url = parsed?.absoluteURL, url.scheme == "https" || url.scheme == "http", url.host() != nil else {
    return nil
  }
  return url
}

/// Fetches an image anonymously: a public image, or an address that
/// carries its own signature. https only — the app makes no plain-http
/// requests.
func fetchPublicImage(_ url: URL) async throws -> Data {
  guard url.scheme == "https", let host = url.host() else {
    throw ProviderError(message: "Only images served over https are shown.")
  }
  var request = URLRequest(url: url)
  request.setValue("image/*", forHTTPHeaderField: "Accept")
  let ctx = RequestContext(service: host, origin: "https://\(host)", originIsUserSupplied: false)
  return try await imageData(for: request, ctx: ctx)
}

/// A request's answer as image bytes: a success whose body is an image and
/// within `imageByteLimit`. A sign-in page answered in an image's place
/// doesn't count.
func imageData(for request: URLRequest, ctx: RequestContext) async throws -> Data {
  let (data, http) = try await send(request, ctx: ctx)
  guard (200 ..< 300).contains(http.statusCode) else {
    throw statusError(http, data, ctx)
  }
  guard isImage(http), data.count <= imageByteLimit else {
    throw ProviderError(message: "\(ctx.service) didn't answer with an image.")
  }
  return data
}

/// Image types, and the generic binary types object storage labels
/// uploads with; the decoder has the last word on the bytes.
private func isImage(_ http: HTTPURLResponse) -> Bool {
  let type = http.mimeType?.lowercased() ?? ""
  return type.hasPrefix("image/") || type == "application/octet-stream" || type == "binary/octet-stream"
}
