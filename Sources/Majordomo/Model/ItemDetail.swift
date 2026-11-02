// What a provider can tell about a notification's target beyond the inbox
// entry: its whole description and the conversation under it. Fetched on
// demand for the preview and held in memory only — the store keeps the
// inbox, not every target's discussion.

import Foundation

/// One comment in a target's conversation. Bodies are Markdown, the
/// forges' common tongue; a provider whose text isn't converts it.
struct DetailComment: Identifiable, Sendable {
  /// Unique within the target.
  let id: String
  var author: String?
  var createdAt: Date
  var body: String
}

/// A notification's target in full, as the provider reported it.
struct ItemDetail: Sendable {
  /// The target's own description, in Markdown; nil when it has none.
  var description: String?
  /// The comment that raised the notification, when the provider can tell
  /// which one did.
  var trigger: DetailComment?
  /// The latest comments, oldest first.
  var comments: [DetailComment] = []
  /// How many comments the target has in all, when known. More than
  /// `comments` holds means the older ones stayed at the provider.
  var commentCount: Int?
}
