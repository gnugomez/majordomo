// The app's type scale: every size the views set text in, named for the
// part it plays, so one role reads the same on every pane and changes in
// one place. It is the system face at fixed sizes: a dense Mac list and
// its panes are laid out in points, the way the system's own sidebars and
// inspectors are. A symbol set beside text takes the text's size.

import SwiftUI

enum TextSize: CGFloat {
  /// Capsules, a card's marks, the smallest counts.
  case badge = 10
  /// A row's meta line and excerpt, captions, hints.
  case caption = 11
  /// Secondary text: the preview's facts, notices, link buttons, a board's
  /// lane and column names.
  case callout = 12
  /// The reading size: a row's title, a comment, a settings label.
  case body = 13
  /// A sheet's title, a body's second-level heading.
  case heading = 15
  /// The preview's title, a body's first-level heading.
  case title = 17
}

extension Font {
  /// The system face at a size of the app's scale.
  static func app(_ size: TextSize, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
    .system(size: size.rawValue, weight: weight, design: design)
  }
}
