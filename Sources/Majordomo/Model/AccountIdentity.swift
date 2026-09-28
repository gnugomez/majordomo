// What makes two connections the same account. The app never writes read
// state upstream, so the local collection is its only copy — and the
// collection is keyed by account. Recognizing "the same user on the same
// instance" is what lets a new token, or an account removed and added back,
// land on the existing record instead of starting a fresh one.

import Foundation

/// The provider, the instance host, and the user — compared case-
/// insensitively, as both GitHub and GitLab treat logins.
struct AccountIdentity: Hashable, Sendable {
  let provider: ProviderId
  let host: String
  let username: String

  /// `baseUrl` is the instance origin for self-hosted providers; nil (a
  /// fixed-host provider) leaves the host empty, which is fine — the
  /// provider still keys it.
  init(provider: ProviderId, baseUrl: String?, username: String) {
    self.provider = provider
    host = baseUrl.flatMap { URL(string: $0)?.host()?.lowercased() } ?? ""
    self.username = username.lowercased()
  }
}
