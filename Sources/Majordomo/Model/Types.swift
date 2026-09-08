// Shared domain types. The core is a generic notification manager: an item's
// kind, state, and reason are opaque provider tokens — what they mean, how
// they're labeled, and how they paint lives in the provider's spec
// (Providers/ProviderSpec.swift). Nothing in this file may import AppKit or
// SwiftUI, and nothing in it may assume issues, pull requests, or any other
// provider-specific vocabulary.

import Foundation

/// Which provider implementation an account speaks through.
enum ProviderId: String, Codable, CaseIterable, Sendable {
  case github
  case gitlab
}

/// One connected account. Multiple accounts may share a ProviderId (two
/// GitLab instances, two GitHub users); the id is stable across launches and
/// keys the account's items, sidebar section, and stored credentials.
typealias AccountId = String

/// One row in the unified inbox.
struct InboxItem: Identifiable, Codable, Hashable, Sendable {
  /// Globally unique: `"\(accountId):\(externalId)"`.
  let id: String
  let accountId: AccountId
  let provider: ProviderId
  /// Provider-defined kind token (e.g. "issue", "pull"); rendered via the
  /// provider's spec, opaque to the core.
  var kind: String
  var title: String
  /// e.g. "eclipse/jetty" — the project/repo the item belongs to.
  var repo: String
  /// Web URL opened in the browser when the row is clicked.
  var url: String
  /// Provider-defined reason token; opaque to the core.
  var reason: String
  /// True for the "needs you" tier — the provider decides which reasons
  /// qualify. Drives the tray dot and notification scoping.
  var isMention: Bool
  /// The last activity the provider reported.
  var updatedAt: Date
  /// Provider-defined state token, when the provider can tell.
  var state: String?
  /// Login of whoever wrote the item, when the provider knows it.
  var author: String?
  var read: Bool
}

/// What the user supplies to connect an account.
struct AccountConfig: Sendable {
  var token: String
  /// Instance origin for self-hosted providers (e.g.
  /// "https://gitlab.example.com"); nil when the provider has a fixed host.
  var baseUrl: String?
}

/// A connected account, as shown in the Accounts pane and sidebar.
struct AccountState: Identifiable, Sendable, Hashable {
  let id: AccountId
  let provider: ProviderId
  var username: String?
  /// The account owner's full display name, when the provider knows it.
  var name: String?
  var avatarUrl: String?
  var baseUrl: String?
  /// Human-readable error from the last validation or sync attempt.
  var error: String?
}

/// The full app state the sync engine publishes to the UI.
struct AppState: Sendable {
  var items: [InboxItem] = []
  var accounts: [AccountState] = []
  var lastSyncAt: Date?
  var syncing: Bool = false
}
