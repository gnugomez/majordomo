// Everything GitLab-specific that isn't API traffic: naming, the tanuki
// mark, glyphs and colors for its tokens, and its sidebar buckets as
// built-in labels and rules — worded GitLab's way ("Merge requests"), which
// shows in per-account sections while the aggregated view merges labels by
// id.

import SwiftUI

struct GitLabSpec: GitForgeSpec {
  let id = ProviderId.gitlab
  let displayName = "GitLab"
  let needsBaseUrl = true
  let tokenHint = "A personal access token with the read_api scope."

  /// Simplified GitLab tanuki, 16×16 viewBox.
  let markSVGPath = "M8 14.7 1.6 10a1 1 0 0 1-.36-1.1l1.07-3.28 1.2-3.7a.36.36 0 0 1 .68 0l1.29 3.95h5.04l1.29-3.95a.36.36 0 0 1 .68 0l1.2 3.7 1.07 3.28a1 1 0 0 1-.36 1.1Z"

  func makeClient() -> any ProviderClient {
    GitLabClient()
  }

  func fallbackAvatarURL(username: String) -> URL? {
    nil
  }

  /// Mentions and comments carry the triggering comment itself in the body —
  /// frame it as the quotation it is. Everything else reads as a plain
  /// description via the shared helper.
  func bodyView(for item: InboxItem) -> AnyView? {
    guard let body = item.body else {
      return nil
    }
    if item.reason == "mentioned" || item.reason == "commented" {
      return AnyView(QuotedComment(author: item.author, text: body))
    }
    return AnyView(MarkdownBody(text: body))
  }

  // Both review-request todos fill the review bucket: a rule each.
  let builtinLabels = GitForgeBuckets.labels(pullsName: "Merge requests")
  let builtinRules = GitForgeBuckets.rules(
    provider: .gitlab, reviewReasons: ["review_requested", "approval_required"], pullKind: "merge",
    pullsName: "Merge requests"
  )
}

/// A comment framed as a quotation: accent bar, attribution, then the text —
/// this provider's own take on its richest content (and proof the bodyView
/// hook means "any view", not "markdown string").
private struct QuotedComment: View {
  let author: String?
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(Color.accentColor.opacity(0.6))
        .frame(width: 3)
      VStack(alignment: .leading, spacing: 4) {
        if let author {
          Text("@\(author) commented")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        MarkdownBody(text: text)
      }
    }
  }
}
