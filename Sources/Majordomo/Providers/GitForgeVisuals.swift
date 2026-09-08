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
  func symbol(for item: InboxItem) -> String {
    GitForgeVisuals.symbol(for: item)
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
}

enum GitForgeVisuals {
  /// Reasons that get their own sidebar bucket, and so never fall through
  /// to a kind bucket.
  static let claimedReasons: Set<String> = ["assigned", "mentioned", "review_requested"]

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

  /// The kind glyph: SF Symbols standing in for the Octicons.
  static func symbol(for item: InboxItem) -> String {
    if item.kind == "issue" {
      return item.state == "closed" ? "checkmark.circle" : "smallcircle.filled.circle"
    }
    switch item.state {
    case "merged": return "arrow.triangle.merge"
    case "closed": return "xmark.circle"
    default: return "arrow.triangle.branch"
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
