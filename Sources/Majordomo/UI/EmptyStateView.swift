// Centered icon + title + caption, and the same filling a detail pane.

import SwiftUI

struct EmptyStateView: View {
  let symbol: String
  let title: String
  let caption: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 28, weight: .light))
        .foregroundStyle(.tertiary)
        .padding(.bottom, 4)
      Text(title)
        .font(.app(.body, weight: .semibold))
      Text(caption)
        .font(.app(.callout))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// An empty state filling a detail pane — the preview's, a board's, a
/// multiple selection's. Scroll-backed, sized to the pane: plain
/// (non-scrolling) content makes the toolbar draw a hard edge line across
/// the pane.
struct PaneEmptyState: View {
  let symbol: String
  let title: String
  let caption: String

  var body: some View {
    ScrollView {
      EmptyStateView(symbol: symbol, title: title, caption: caption)
        .containerRelativeFrame(.vertical)
    }
  }
}
