// How a list row's colored marks draw. On a selected row every fixed color
// steps aside for the row's hierarchical primary style, which AppKit flips
// to white on an emphasized (accent) selection and keeps dark on an
// unfocused gray one — an explicit color would do neither, and an accent
// mark would vanish into an accent selection.

import SwiftUI

extension Color {
  /// This color on a row: itself, or the row's primary style while the
  /// row is selected.
  func onRow(selected: Bool) -> AnyShapeStyle {
    selected ? AnyShapeStyle(.primary) : AnyShapeStyle(self)
  }
}

/// The unread mark: an accent dot. A row keeps the dot's room when there is
/// nothing unread (`unread` false draws it clear), so every row's title
/// starts at the same place.
struct UnreadDot: View {
  var unread = true
  var size: CGFloat = 7
  var selected = false

  var body: some View {
    Circle()
      .fill(unread ? Color.accentColor.onRow(selected: selected) : AnyShapeStyle(.clear))
      .frame(width: size, height: size)
  }
}
