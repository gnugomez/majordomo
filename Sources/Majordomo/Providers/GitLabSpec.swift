// Everything GitLab-specific that isn't API traffic: naming, the tanuki
// mark, glyphs and colors for its tokens, and its sidebar buckets — worded
// GitLab's way ("Merge requests"), which shows in per-account sections while
// the aggregated view merges buckets by id.

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

  let categories: [CategorySpec] = [
    CategorySpec(id: "assigned", label: "Assigned", symbol: "person.crop.circle", order: 1) {
      $0.reason == "assigned"
    },
    CategorySpec(id: "mentions", label: "Mentions", symbol: "at", order: 2) {
      $0.reason == "mentioned"
    },
    CategorySpec(id: "reviews", label: "Review requests", symbol: "eye", order: 3) {
      $0.reason == "review_requested" || $0.reason == "approval_required"
    },
    CategorySpec(id: "issues", label: "Issues", symbol: "smallcircle.filled.circle", order: 4) {
      $0.kind == "issue" && !GitForgeVisuals.claimedReasons.contains($0.reason)
    },
    CategorySpec(id: "pulls", label: "Merge requests", symbol: "arrow.triangle.branch", order: 5) {
      $0.kind == "merge" && !GitForgeVisuals.claimedReasons.contains($0.reason)
    },
  ]
}
