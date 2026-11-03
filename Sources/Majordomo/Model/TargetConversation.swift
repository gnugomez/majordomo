// What a provider can tell about a notification's target beyond the inbox
// entry: its whole description and the latest of the conversation under it.
// Fetched in the background with the target's refresh, so a preview reads
// it from disk, and kept a file per target beside the store (see
// ConversationFiles) — together they run far larger than the store itself.

import Foundation

/// One comment in a target's conversation. Bodies are Markdown, the
/// forges' common tongue; a provider whose text isn't converts it.
struct DetailComment: Identifiable, Codable, Hashable, Sendable {
  /// Unique within the target; what the provider's comment links name it
  /// by, so a notification can point at it (ProviderSpec.triggerCommentId).
  let id: String
  var author: String?
  var createdAt: Date
  var body: String
}

/// A target's description and latest comments, as of one refresh.
struct TargetConversation: Codable, Hashable, Sendable {
  /// The target's own description, in Markdown; nil when it has none.
  var description: String?
  /// The latest comments, oldest first.
  var comments: [DetailComment] = []
  /// How many comments the target has in all, when known. More than
  /// `comments` holds means the older ones stayed at the provider.
  var commentCount: Int?
}
