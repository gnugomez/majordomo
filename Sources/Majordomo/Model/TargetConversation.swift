// What a provider can tell about a notification's target beyond the inbox
// entry: who opened it, its whole description, and the latest of the
// conversation under it. Fetched in the background with the target's
// refresh, so a preview reads it from disk, and kept a file per target
// beside the store (see ConversationFiles) — together they run far larger
// than the store itself. Every field a refresh may not have filled in is
// optional, so a file written before it existed still reads.

import Foundation

/// One entry in a target's conversation: a comment, or an event that may
/// carry words of its own — a review's verdict. Bodies are Markdown, the
/// forges' common tongue; a provider whose text isn't converts it.
struct DetailComment: Identifiable, Codable, Hashable, Sendable {
  /// Unique within the target; what the provider's comment links name it
  /// by, so a notification can point at it (ProviderSpec.triggerCommentId).
  let id: String
  var author: String?
  /// The author's picture, as the provider links it; nil when it gave
  /// none (the spec's fallbackAvatarURL may still find one).
  var avatarUrl: String?
  var createdAt: Date
  /// Empty for an event that came without words.
  var body: String
  /// What the entry records beyond its words, as a provider token the
  /// spec presents (ProviderSpec.eventBadge) — "approved" on a review;
  /// nil for a plain comment.
  var event: String?
}

/// A target's opening post and latest entries, as of one refresh.
struct TargetConversation: Codable, Hashable, Sendable {
  /// The target's own description, in Markdown; nil when it has none.
  var description: String?
  /// Who opened the target, and their picture — the description reads as
  /// their opening post.
  var author: String?
  var authorAvatarUrl: String?
  /// When the target was opened.
  var createdAt: Date?
  /// The latest comments and events, oldest first.
  var comments: [DetailComment] = []
  /// How many comments the target has in all, events not counted, when
  /// known. More than `comments` holds means the older ones stayed at the
  /// provider.
  var commentCount: Int?

  /// How many of `comments` are comments rather than events — what
  /// `commentCount` is measured against.
  var plainCommentCount: Int {
    comments.count { $0.event == nil }
  }

  /// The picture the conversation gives someone, from the opening post or
  /// their latest entry; nil when it gives none.
  func avatarUrl(of login: String) -> String? {
    if author == login, let authorAvatarUrl {
      return authorAvatarUrl
    }
    return comments.last { $0.author == login && $0.avatarUrl != nil }?.avatarUrl
  }
}
