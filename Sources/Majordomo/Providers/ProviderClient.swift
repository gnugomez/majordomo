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
  /// Labels the target carries upstream (an issue's own labels), when the
  /// provider fetched them this round; nil means "didn't look", not "none",
  /// so a prior sync's answer survives.
  var upstreamLabels: [String]?
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

/// How far a fetch reaches. `.recent` covers the latest pages — the sync
/// timer's cheap default. `.full` walks every page (up to the client's
/// safety ceiling) so items beyond the recent window can't hide forever;
/// the engine asks for it on manual refresh and about once an hour.
enum FetchDepth: Sendable {
  case recent
  case full
}

/// One target as a refresh found it, with its conversation when the
/// round asked for that too.
struct TargetRefresh: Sendable {
  var snapshot: TargetSnapshot
  var conversation: TargetConversation?
}

/// What fetchTargets learned. A key in neither map went unanswered — its
/// share of the round failed — and is asked again next round.
struct TargetRound: Sendable {
  var refreshed: [String: TargetRefresh] = [:]
  /// Targets the provider wouldn't show — gone, or out of the token's
  /// reach — with why, in words fit to show.
  var unreadable: [String: String] = [:]
}

/// What validate() learns about the account's owner.
struct ProviderProfile: Sendable {
  var username: String
  var name: String?
  var avatarUrl: String?
}

/// Comments a conversation keeps at most: the latest ones, enough to see
/// where it stands. The rest are a click away.
let detailCommentLimit = 10
/// Characters a description or comment keeps at most — whole
/// descriptions, but not whole build logs.
let detailTextLimit = 20_000

/// Implemented once per provider; one instance serves every account of it.
///
/// Rules every implementation must follow:
/// - `validate`, `fetchItems`, and `fetchTargets` throw
///   `ProviderError`s with human-readable messages — the strings surface
///   verbatim in the UI.
/// - One malformed remote entry must never fail the whole fetch: skip it.
/// - No sorting — the UI orders items for display.
/// - `externalId` is unique and stable within the account across fetches;
///   the engine composes the global id as `"\(accountId):\(externalId)"`
///   (it is the dedup and read-state key).
protocol ProviderClient: Sendable {
  var id: ProviderId { get }
  /// Checks the credentials; returns the account owner's profile on success.
  func validate(_ config: AccountConfig) async throws -> ProviderProfile
  /// Returns the account's current inbox, reaching as deep as `depth` asks.
  func fetchItems(_ config: AccountConfig, depth: FetchDepth) async throws -> FetchResult
  /// How many targets one `fetchTargets` call may ask about — what a
  /// round of the sync timer can afford against the provider's limits.
  var targetBatchLimit: Int { get }
  /// Where these targets stand now, by key (the spec's `boardKey`), and
  /// for the keys in `conversations` their description and latest
  /// comments too — what the preview shows. A target the provider won't
  /// show is unreadable, with a message that says what would fix it, a
  /// missing token scope above all. A share of the round that fails
  /// leaves its keys out of the answer, to be asked again; a throw means
  /// the round failed as a whole.
  func fetchTargets(_ config: AccountConfig, keys: [String], conversations: Set<String>) async throws -> TargetRound
  /// The bytes of an image a target's body shows: `url` as the spec's
  /// `bodyURL` resolved it, `page` the target's url, for a provider whose
  /// private images need its API's help to find. The account's token goes
  /// only to the provider's own API origin over https; every other request
  /// carries no credentials. Throws when the image can't be had — the
  /// preview shows a link in its place.
  func fetchImage(_ config: AccountConfig, url: URL, page: String) async throws -> Data
}

extension ProviderClient {
  /// Public images only.
  func fetchImage(_ config: AccountConfig, url: URL, page: String) async throws -> Data {
    try await fetchPublicImage(url)
  }
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
  /// The provider refused the token itself (HTTP 401): expired, revoked,
  /// or never valid — what a new token fixes.
  var rejectsToken = false
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
