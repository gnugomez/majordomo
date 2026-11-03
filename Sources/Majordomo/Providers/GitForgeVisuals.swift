// Shared presentation for git-forge providers (GitHub, GitLab): both speak
// the same kind/state token families, so the glyph, palette, and capsule
// rules live once here and each spec delegates. A future non-forge provider
// simply doesn't use this.

import SwiftUI

/// A spec whose tokens follow the shared git-forge families. Presentation
/// defaults delegate to GitForgeVisuals, so each forge spec declares only
/// what actually differs; a non-forge provider simply doesn't conform.
protocol GitForgeSpec: ProviderSpec {}

extension GitForgeSpec {
  func glyph(for item: InboxItem) -> Glyph {
    GitForgeVisuals.glyph(for: item)
  }

  func color(for item: InboxItem) -> Color {
    GitForgeVisuals.color(for: item)
  }

  func stateCapsule(for item: InboxItem) -> StateCapsule? {
    GitForgeVisuals.stateCapsule(for: item)
  }

  func reasonLabel(_ reason: String) -> String {
    GitForgeVisuals.reasonLabel(reason)
  }

  func boardKey(for item: InboxItem) -> String? {
    GitForgeVisuals.targetUrl(item.url).map(\.key)
  }

  func shortReference(for item: InboxItem) -> String? {
    GitForgeVisuals.targetUrl(item.url).map(\.reference)
  }

  func triggerCommentId(for item: InboxItem) -> String? {
    GitForgeVisuals.commentAnchor(item.url)
  }

  func isFinished(state: String) -> Bool {
    state == "closed" || state == "merged"
  }

  func reviewBadge(_ review: String) -> CardBadge? {
    GitForgeVisuals.reviewBadge(review)
  }

  func checksBadge(_ checks: String) -> CardBadge? {
    GitForgeVisuals.checksBadge(checks)
  }

  func mergeBadge(_ merge: String) -> CardBadge? {
    GitForgeVisuals.mergeBadge(merge)
  }

  func tokens(for field: RuleField) -> [String] {
    GitForgeVisuals.tokens(for: field)
  }
}

enum GitForgeVisuals {
  /// The "needs you" tier — deliberately excludes "assigned": an assignment
  /// is a task, not an interruption.
  static func isMention(_ reason: String) -> Bool {
    reason == "mentioned" || reason == "review_requested"
  }

  /// Item states, GitHub's palette (light / dark).
  static func stateColor(_ state: String) -> Color {
    switch state {
    case "open": dynamicColor(light: 0x1F883D, dark: 0x3FB950)
    case "merged": dynamicColor(light: 0x8250DF, dark: 0xA371F7)
    case "closed": dynamicColor(light: 0xCF222E, dark: 0xF85149)
    default: dynamicColor(light: 0x59636E, dark: 0x9198A1)
    }
  }

  private static func isPullLike(_ item: InboxItem) -> Bool {
    item.kind == "pull" || item.kind == "merge"
  }

  /// The kind glyph, the Octicon the forges themselves show for the
  /// state: a draft and an unmerged close each have their own.
  static func glyph(for item: InboxItem) -> Glyph {
    if item.kind == "issue" {
      return item.state == "closed" ? Octicon.issueClosed : Octicon.issueOpened
    }
    switch item.state {
    case "merged": return Octicon.merge
    case "closed": return Octicon.pullRequestClosed
    case "draft": return Octicon.pullRequestDraft
    default: return Octicon.pullRequest
    }
  }

  /// State color for the kind glyph; no state keeps the muted look. GitHub
  /// renders completed issues purple, not red — only closed PRs/MRs are red.
  static func color(for item: InboxItem) -> Color {
    guard let state = item.state else {
      return .secondary
    }
    if state == "closed", item.kind == "issue" {
      return stateColor("merged")
    }
    return stateColor(state)
  }

  /// A merged/closed/draft PR or MR shows its STATE in the capsule — the
  /// stored reason ("review requested" on a merged PR) would be stale. Open
  /// or unknown state keeps the reason capsule; issues always keep it.
  static func stateCapsule(for item: InboxItem) -> StateCapsule? {
    guard isPullLike(item), let state = item.state, state != "open" else {
      return nil
    }
    return StateCapsule(label: state, color: stateColor(state))
  }

  /// An issue, pull or merge request url, as the key its notifications
  /// share (anchors stripped) and the reference it reads as: "#" for
  /// issues and pull requests, "!" for merge requests.
  ///
  /// Plain string work rather than a regex: boards key every notification
  /// the app has ever kept, and this runs once for each.
  static func targetUrl(_ url: String) -> (key: String, reference: String)? {
    let page = url.utf8.firstIndex(of: UInt8(ascii: "#")).map { url[..<$0] } ?? url[...]
    guard page.hasPrefix("https://") || page.hasPrefix("http://"),
          let lastSlash = page.utf8.lastIndex(of: UInt8(ascii: "/")) else {
      return nil
    }
    let number = page[page.index(after: lastSlash)...]
    guard !number.isEmpty, number.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else {
      return nil
    }
    let head = page[..<lastSlash]
    let marker: String
    if head.hasSuffix("/issues") || head.hasSuffix("/pull") {
      marker = "#"
    } else if head.hasSuffix("/merge_requests") {
      marker = "!"
    } else {
      return nil
    }
    return (key: String(page), reference: marker + number)
  }

  /// The comment a url's anchor points at, by its number: GitHub's
  /// `#issuecomment-123`, GitLab's `#note_123`.
  static func commentAnchor(_ url: String) -> String? {
    guard let hash = url.utf8.lastIndex(of: UInt8(ascii: "#")) else {
      return nil
    }
    let anchor = url[url.index(after: hash)...]
    for prefix in ["issuecomment-", "note_"] where anchor.hasPrefix(prefix) {
      let number = anchor.dropFirst(prefix.count)
      return !number.isEmpty && number.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") })
        ? String(number) : nil
    }
    return nil
  }

  /// What asks for a hand without being a failure: changes asked for, a
  /// branch to update.
  private static let attentionColor = dynamicColor(light: 0xBC4C00, dark: 0xDB6D28)
  /// What is still settling, or holds without failing.
  private static let pendingColor = dynamicColor(light: 0x9A6700, dark: 0xD29922)

  /// Review tokens, both forges: "approved", "changes_requested",
  /// "review_required".
  static func reviewBadge(_ review: String) -> CardBadge? {
    switch review {
    case "approved":
      CardBadge(glyph: Octicon.checkCircle, label: "Approved", color: stateColor("open"))
    case "changes_requested":
      CardBadge(glyph: Octicon.fileDiff, label: "Changes requested", color: attentionColor, needsAction: true)
    case "review_required":
      CardBadge(glyph: Octicon.eye, label: "Review required", color: stateColor(""))
    default:
      nil
    }
  }

  /// Checks tokens, both forges: "success", "failure", "pending".
  static func checksBadge(_ checks: String) -> CardBadge? {
    switch checks {
    case "success":
      CardBadge(glyph: Octicon.check, label: "Checks passed", color: stateColor("open"))
    case "failure":
      CardBadge(glyph: Octicon.x, label: "Checks failed", color: stateColor("closed"), needsAction: true)
    case "pending":
      CardBadge(glyph: Octicon.dotFill, label: "Checks running", color: pendingColor)
    default:
      nil
    }
  }

  /// Merge tokens, both forges: "conflicts"; "behind", a branch to update
  /// from its base first; "unresolved", discussion threads still open
  /// (GitLab); "blocked", held by something else — a required review or
  /// check, a branch rule; "unstable", mergeable though checks that aren't
  /// required failed (GitHub); and "ready".
  static func mergeBadge(_ merge: String) -> CardBadge? {
    switch merge {
    case "conflicts":
      CardBadge(glyph: Octicon.alert, label: "Merge conflicts", color: stateColor("closed"), needsAction: true)
    case "behind":
      CardBadge(glyph: Octicon.sync, label: "Branch out of date", color: attentionColor, needsAction: true)
    case "unresolved":
      CardBadge(glyph: Octicon.commentDiscussion, label: "Unresolved threads", color: pendingColor, needsAction: true)
    case "blocked":
      CardBadge(glyph: Octicon.blocked, label: "Merge blocked", color: stateColor(""))
    case "unstable":
      CardBadge(glyph: Octicon.merge, label: "Mergeable, checks failing", color: pendingColor)
    case "ready":
      CardBadge(glyph: Octicon.merge, label: "Ready to merge", color: stateColor("open"))
    default:
      nil
    }
  }

  /// The vocabulary of the token fields, as both forges speak it.
  static func tokens(for field: RuleField) -> [String] {
    switch field {
    case .kind: ["issue", "pull", "merge"]
    case .state: ["open", "draft", "closed", "merged"]
    case .reason: ["mentioned", "review_requested", "approval_required", "assigned", "author", "commented", "subscribed", "activity"]
    case .review: ["approved", "changes_requested", "review_required"]
    case .checks: ["success", "failure", "pending"]
    default: []
    }
  }

  /// How each reason token reads in a capsule.
  static func reasonLabel(_ reason: String) -> String {
    switch reason {
    case "mentioned": "mentioned"
    case "review_requested": "review requested"
    case "approval_required": "approval required"
    case "assigned": "assigned"
    case "author": "author"
    case "commented": "commented"
    case "subscribed": "subscribed"
    default: "activity"
    }
  }
}
