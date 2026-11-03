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

/// An icon from a provider's own set, as SVG path data on a 16×16 grid
/// — for what SF Symbols has no faithful stand-in for. GlyphImage draws it.
struct Glyph: Hashable, Sendable {
  let svg: String
}

/// A small glyph-and-word mark on a board card: where review or checks
/// stand.
struct CardBadge: Sendable {
  let glyph: Glyph
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
  /// What the token needs beyond `tokenHint` for previews to show
  /// everything, said plainly when that grants more than reading. nil when
  /// the hint's scope covers previews too.
  var previewScopeNote: String? { get }
  func makeClient() -> any ProviderClient
  /// Best-effort avatar for a username when the API's URL is unknown.
  func fallbackAvatarURL(username: String) -> URL?
  /// An item's kind/state glyph.
  func glyph(for item: InboxItem) -> Glyph
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
  /// The target an item is about, as a key boards group cards by and the
  /// client refreshes by; nil for items that point at nothing a card can
  /// track (a repository-level alert).
  func boardKey(for item: InboxItem) -> String?
  /// How the provider names the target in a line of text ("#12", "!58").
  func shortReference(for item: InboxItem) -> String?
  /// The comment the notification points at, by the id its target's
  /// conversation gives it (DetailComment.id); nil when it points at none.
  func triggerCommentId(for item: InboxItem) -> String?
  /// A conversation entry's mark for an event token (DetailComment.event,
  /// a review's verdict): its glyph and color, and the words that follow
  /// the author's name ("approved"). nil reads as a plain comment.
  func eventBadge(_ event: String) -> CardBadge?
  /// Where a link or image a target's body names points, resolved the way
  /// the provider renders the body for the item's target — a forge's own
  /// uploads sit under the project. nil when it names nothing on the web.
  func bodyURL(_ reference: String, for item: InboxItem) -> URL?
  /// Whether a state token means the target is done with — Done on a
  /// board, and no more refreshes until new activity.
  func isFinished(state: String) -> Bool
  /// A card's review mark for a review token; nil shows none.
  func reviewBadge(_ review: String) -> CardBadge?
  /// A card's checks mark for a checks token; nil shows none.
  func checksBadge(_ checks: String) -> CardBadge?
  /// Values a board column's condition can pick from for a token field
  /// (kind, state, review, checks…), in the provider's own vocabulary.
  func tokens(for field: RuleField) -> [String]
}

extension ProviderSpec {
  var previewScopeNote: String? { nil }

  func bodyView(for item: InboxItem) -> AnyView? {
    item.body.map { AnyView(MarkdownBody(text: $0)) }
  }

  func eventBadge(_ event: String) -> CardBadge? {
    nil
  }

  func bodyURL(_ reference: String, for item: InboxItem) -> URL? {
    resolveBodyReference(reference, page: item.url)
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

extension LabelCatalog {
  /// The catalog as the app has it: every registered provider's built-ins
  /// plus the user's own. The one place the full set is assembled — it
  /// lives here because the provider registry does, and the Model layer
  /// that defines the catalog must not reach into it.
  static func current(user: [InboxLabel], userRules: [LabelRule]) -> LabelCatalog {
    LabelCatalog(
      builtinLabels: aggregatedBuiltinLabels,
      builtinRules: allBuiltinRules,
      user: user,
      userRules: userRules
    )
  }

  /// The labels one sidebar section lists. "All Inboxes" (nil) merges every
  /// provider's built-ins by id, the first registration's wording winning;
  /// an account's own section shows that provider's wording instead —
  /// GitLab calls "Merge requests" what GitHub calls "Pull requests". The
  /// user's own follow either way, since labels belong to the user and not
  /// to an account.
  func sectionLabels(for provider: ProviderId?) -> [InboxLabel] {
    guard let provider else {
      return labels
    }
    return spec(for: provider).builtinLabels + user
  }
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
