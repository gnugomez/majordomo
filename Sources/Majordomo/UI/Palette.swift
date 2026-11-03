// The app's own colors, in one place. The shades conversations and boards
// are drawn in: a quiet gray pane with white cards in light mode, a
// near-black pane with lifted gray cards in dark mode. Neither is a plain
// system color — windowBackgroundColor sits LIGHTER than
// textBackgroundColor in dark mode, which would invert the scheme. Then
// the label tint tokens, resolved to system colors so folders and capsules
// follow the appearance and accessibility settings like every other tinted
// control; the steady tints behind people's initials; and the on-device
// model's colors. A provider's own colors live in its spec.

import AppKit
import SwiftUI

enum Palette {
  /// Behind a conversation's cards.
  static let pane = appearanceColor(light: NSColor(white: 0.95, alpha: 1), dark: NSColor(white: 0.12, alpha: 1))

  /// A card: a comment, a message, a board's card.
  static let card = appearanceColor(light: .white, dark: NSColor(white: 0.2, alpha: 1))

  /// Behind inline code and code blocks, on a card or the pane.
  static let code = appearanceColor(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.08))

  /// A board column's strip, behind its cards.
  static let boardColumn = appearanceColor(light: NSColor(white: 0, alpha: 0.04), dark: NSColor(white: 1, alpha: 0.05))

  /// The model's own colors, for the light that marks what it chose. The
  /// system vends no style for them, so they are named here.
  static let intelligence: [Color] = [
    Color(red: 1.00, green: 0.18, blue: 0.33),
    Color(red: 0.69, green: 0.32, blue: 0.87),
    Color(red: 0.00, green: 0.48, blue: 1.00),
    Color(red: 0.20, green: 0.78, blue: 0.95),
    Color(red: 1.00, green: 0.58, blue: 0.00),
  ]

  /// The tints a face's initial sits on.
  private static let faceTints: [LabelTint] = [.red, .orange, .green, .teal, .blue, .indigo, .purple, .pink, .brown]

  /// One color per login, the same on every launch (String's own hash is
  /// seeded per run).
  static func face(for login: String?) -> Color {
    let sum = (login ?? "").unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return faceTints[sum % faceTints.count].color.opacity(0.85)
  }

  /// A color that follows the appearance: `dark` under Dark Mode, `light`
  /// otherwise.
  private static func appearanceColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    })
  }
}

extension LabelTint {
  var color: Color {
    switch self {
    case .accent: .accentColor
    case .gray: .gray
    case .red: .red
    case .orange: .orange
    case .yellow: .yellow
    case .green: .green
    case .teal: .teal
    case .blue: .blue
    case .indigo: .indigo
    case .purple: .purple
    case .pink: .pink
    case .brown: .brown
    }
  }
}
