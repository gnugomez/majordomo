// How the git forges' conversations read in a preview: the event tokens
// both clients put on a conversation's entries — a review's verdict — and
// where GitLab's project-relative uploads live.

import SwiftUI

extension GitForgeSpec {
  func eventBadge(_ event: String) -> CardBadge? {
    GitForgeVisuals.eventBadge(event)
  }
}

extension GitForgeVisuals {
  /// Event tokens, both forges: "approved", "changes_requested",
  /// "reviewed" (a review that only comments), "dismissed" (a review set
  /// aside), "unapproved" (an approval taken back).
  static func eventBadge(_ event: String) -> CardBadge? {
    switch event {
    case "approved":
      CardBadge(glyph: Octicon.check, label: "approved", color: stateColor("open"))
    case "changes_requested":
      CardBadge(glyph: Octicon.fileDiff, label: "requested changes", color: dynamicColor(light: 0xBC4C00, dark: 0xDB6D28))
    case "reviewed":
      CardBadge(glyph: Octicon.eye, label: "reviewed", color: stateColor(""))
    case "dismissed":
      CardBadge(glyph: Octicon.x, label: "reviewed · dismissed", color: stateColor(""))
    case "unapproved":
      CardBadge(glyph: Octicon.x, label: "removed their approval", color: stateColor(""))
    default:
      nil
    }
  }
}

extension GitLabSpec {
  /// GitLab writes an upload as "/uploads/<secret>/<file>", relative to the
  /// project rather than the instance; everything else resolves as on any
  /// page.
  func bodyURL(_ reference: String, for item: InboxItem) -> URL? {
    let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("/uploads/"), let projectEnd = item.url.range(of: "/-/") {
      return resolveBodyReference(String(item.url[..<projectEnd.lowerBound]) + trimmed, page: item.url)
    }
    return resolveBodyReference(trimmed, page: item.url)
  }
}
