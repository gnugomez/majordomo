// The label tint tokens resolved to colors. System colors, so folders and
// capsules follow the appearance and accessibility settings like every
// other tinted control.

import SwiftUI

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
