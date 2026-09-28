// The provider contract beyond the API client: naming, brand mark, colors,
// glyphs, capsule labels, and the sidebar buckets — built-in labels plus
// the rules that fill them, run by the same engine as the user's. The core
// renders opaque item tokens entirely through this — presentation belongs
// to the provider implementation, never to the API or the core.

import SwiftUI

/// One sidebar bucket: the catch-all, or a label's folder.
struct CategorySpec: Identifiable, Sendable {
  let id: String
  let label: String
  /// Sidebar/source-list glyph.
  let symbol: String
  /// Position in the sidebar; the core's catch-all sits at 0, built-in
  /// labels follow, and the user's folders come after every built-in.
  let order: Int
  /// The glyph's tint; nil draws it like every other sidebar glyph.
  var tint: LabelTint? = nil
  /// Set on a label's folder — the label it stands for.
  var labelId: LabelId? = nil
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
  /// The preview pane's body section for an item, or nil for none. Providers
  /// build whatever SwiftUI fits their content from the item's data;
  /// MarkdownBody is available as a rendering helper, and the default uses
  /// it on the item's body text.
  func bodyView(for item: InboxItem) -> AnyView?
  /// The buckets this provider's items sort into, as built-in labels:
  /// listed and hidable like the user's, folders in the sidebar, read-only
  /// in settings. Buckets sharing an id merge in "All Inboxes" (the first
  /// registration's wording wins there); an account's own section shows the
  /// provider's wording — GitLab may call "Merge requests" what GitHub calls
  /// "Pull requests".
  var builtinLabels: [InboxLabel] { get }
  /// The rules that fill them, run by the same engine as the user's rules.
  /// Every provider's rules see every item; they test the provider's own
  /// tokens, so another provider's items simply never match.
  var builtinRules: [LabelRule] { get }
}

extension ProviderSpec {
  func bodyView(for item: InboxItem) -> AnyView? {
    item.body.map { AnyView(MarkdownBody(text: $0)) }
  }
}

/// Every provider implementation the app ships. Adding a provider means
/// adding a spec (plus its client) here.
let providerSpecs: [any ProviderSpec] = [GitHubSpec(), GitLabSpec()]

func spec(for id: ProviderId) -> any ProviderSpec {
  providerSpecs.first { $0.id == id }!
}

/// Every provider's built-in labels merged by id — the first registration's
/// wording wins, as "All Inboxes" lists them.
let aggregatedBuiltinLabels: [InboxLabel] = {
  var seen: Set<LabelId> = []
  var merged: [InboxLabel] = []
  for spec in providerSpecs {
    for label in spec.builtinLabels where !seen.contains(label.id) {
      seen.insert(label.id)
      merged.append(label)
    }
  }
  return merged.sorted { $0.order < $1.order }
}()

/// Every provider's built-in rules, in registration order.
let allBuiltinRules: [LabelRule] = providerSpecs.flatMap(\.builtinRules)

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
