// The shades conversations are drawn in: a quiet gray pane with white
// cards in light mode, a near-black pane with lifted gray cards in dark
// mode. Neither is a plain system color — windowBackgroundColor sits
// LIGHTER than textBackgroundColor in dark mode, which would invert the
// scheme.

import SwiftUI

enum ConversationShades {
  /// Behind the cards.
  static let pane = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(white: 0.12, alpha: 1)
      : NSColor(white: 0.95, alpha: 1)
  })

  /// A card: a comment, a message, a board's card.
  static let card = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(white: 0.2, alpha: 1)
      : .white
  })

  /// Behind inline code and code blocks, on a card or the pane.
  static let code = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(white: 1, alpha: 0.08)
      : NSColor(white: 0, alpha: 0.05)
  })
}
