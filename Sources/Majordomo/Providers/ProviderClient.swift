// The provider contract. A provider turns one account's remote inbox into
// the app's uniform item shape; the sync engine consumes nothing else.

import Foundation

/// What a provider fetches: an InboxItem before the engine stamps account
/// identity and before local read-state is applied. Kind, state, and reason
/// are the provider's own tokens — the matching spec knows how to render
/// them; the core never interprets them.
struct FetchedItem: Sendable {
  /// Unique and stable within this account (the dedup and read-state key);
  /// the engine prefixes it with the account id.
  let externalId: String
  var kind: String
  var title: String
  var repo: String
  var url: String
  var reason: String
  var isMention: Bool
  var updatedAt: Date
  var state: String?
  var author: String?
  /// Preview text; the provider decides what a "body" is for it and how its
  /// spec renders it.
  var body: String?
  /// True when the provider reports the user already handled this upstream
  /// (read notification thread, done todo). Consumed at upsert time to mark
  /// the local item read; never stored. nil means "unknown/unread".
  var upstreamRead: Bool?
}

/// What fetchItems returns.
struct FetchResult: Sendable {
  var items: [FetchedItem]
  /// True when no page cap truncated the authoritative list — an item's
  /// absence from a complete fetch proves the user handled it upstream, so
  /// the sync engine marks it read. A capped fetch proves nothing.
  var complete: Bool
}

/// What validate() learns about the account's owner.
struct ProviderProfile: Sendable {
  var username: String
  var name: String?
  var avatarUrl: String?
}

/// Implemented once per provider; one instance serves every account of it.
///
/// Rules every implementation must follow:
/// - `validate` and `fetchItems` throw `ProviderError`s with human-readable
///   messages — the strings surface verbatim in the UI's Accounts pane.
/// - One malformed remote entry must never fail the whole fetch: skip it.
/// - No sorting — ordering is the sync engine's concern.
/// - `externalId` is unique and stable within the account across fetches;
///   the engine composes the global id as `"\(accountId):\(externalId)"`
///   (it is the dedup and read-state key).
protocol ProviderClient: Sendable {
  var id: ProviderId { get }
  /// Checks the credentials; returns the account owner's profile on success.
  func validate(_ config: AccountConfig) async throws -> ProviderProfile
  /// Returns the account's current inbox.
  func fetchItems(_ config: AccountConfig) async throws -> FetchResult
}

/// Caps provider-supplied body text at fetch time — a description can carry
/// whole build logs, and the store keeps every byte it is given.
func truncatedBody(_ text: String?, limit: Int = 1200) -> String? {
  guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
    return nil
  }
  guard trimmed.count > limit else {
    return trimmed
  }
  let cut = String(trimmed.prefix(limit))
  // A cut that lands inside a fenced code block leaves a dangling fence —
  // close it so the renderer doesn't swallow the ellipsis into code.
  let fences = cut.components(separatedBy: "```").count - 1
  return fences % 2 == 1 ? cut + "…\n```" : cut + "…"
}

/// A provider failure whose message is fit for the UI, verbatim.
struct ProviderError: LocalizedError, Sendable {
  let message: String
  var errorDescription: String? { message }
}

/// Decodes to nil instead of failing the containing array: one malformed
/// remote entry must never kill the whole fetch.
struct Failable<T: Decodable>: Decodable {
  let value: T?
  init(from decoder: Decoder) throws {
    value = try? T(from: decoder)
  }
}
