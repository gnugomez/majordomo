// The provider contract beyond the API client: naming, brand mark, colors,
// glyphs, labels, and sidebar buckets. The core renders opaque item tokens
// entirely through this — presentation belongs to the provider
// implementation, never to the API or the core.

import SwiftUI

/// One sidebar bucket a provider contributes. Buckets sharing an id merge in
/// the aggregated "All Inboxes" section (the first registration's wording
/// wins there); inside an account's own section the provider's own wording
/// shows — GitLab may call the same bucket "Merge requests" that GitHub
/// calls "Pulls".
struct CategorySpec: Identifiable, Sendable {
  let id: String
  let label: String
  /// Sidebar/source-list glyph.
  let symbol: String
  /// Position among buckets; the core's catch-all sits at 0.
  let order: Int
  let matches: @Sendable (InboxItem) -> Bool
}

/// What a state capsule shows when the state supersedes the reason.
struct StateCapsule: Sendable {
  let label: String
  let color: Color
}

protocol ProviderSpec: Sendable {
  var id: ProviderId { get }
  var displayName: String { get }
  /// The brand mark as a 16×16-viewBox SVG path.
  var markSVGPath: String { get }
  /// Whether connecting needs an instance URL alongside the token.
  var needsBaseUrl: Bool { get }
  /// One-line hint under the token field in the add-account sheet.
  var tokenHint: String { get }
  func makeClient() -> any ProviderClient
  /// Best-effort avatar for a username when the API's URL is unknown.
  func fallbackAvatarURL(username: String) -> URL?
  /// SF Symbol for an item's kind/state glyph.
  func symbol(for item: InboxItem) -> String
  /// Color for that glyph.
  func color(for item: InboxItem) -> Color
  /// The capsule when an item's state supersedes its reason, else nil.
  func stateCapsule(for item: InboxItem) -> StateCapsule?
  /// Human label for a reason token.
  func reasonLabel(_ reason: String) -> String
  /// The sidebar buckets this provider's items sort into.
  var categories: [CategorySpec] { get }
}

/// Every provider implementation the app ships. Adding a provider means
/// adding a spec (plus its client) here.
let providerSpecs: [any ProviderSpec] = [GitHubSpec(), GitLabSpec()]

func spec(for id: ProviderId) -> any ProviderSpec {
  providerSpecs.first { $0.id == id }!
}

extension ProviderId {
  /// Convenience for the spec's display name.
  var displayName: String {
    spec(for: self).displayName
  }
}

/// A light/dark pair resolved against the current appearance — shared by
/// specs that define fixed palettes.
func dynamicColor(light: Int, dark: Int) -> Color {
  func component(_ hex: Int, _ shift: Int) -> Double {
    Double((hex >> shift) & 0xFF) / 255
  }
  return Color(
    NSColor(name: nil) { appearance in
      let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
      return NSColor(
        srgbRed: component(hex, 16), green: component(hex, 8), blue: component(hex, 0), alpha: 1
      )
    }
  )
}
