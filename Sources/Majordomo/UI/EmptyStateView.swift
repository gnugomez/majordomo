// Centered icon + title + caption, with what can be done from there under
// them, and the same filling a detail pane.

import SwiftUI

struct EmptyStateView<Actions: View>: View {
  let symbol: String
  let title: String
  let caption: String
  /// Buttons under the caption; none unless given.
  @ViewBuilder let actions: Actions

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
      actions
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension EmptyStateView where Actions == EmptyView {
  init(symbol: String, title: String, caption: String) {
    self.init(symbol: symbol, title: title, caption: caption) { EmptyView() }
  }
}

/// An empty state filling a detail pane — the preview's, a board's, a
/// multiple selection's. Scroll-backed, sized to the pane: plain
/// (non-scrolling) content makes the toolbar draw a hard edge line across
/// the pane.
struct PaneEmptyState<Actions: View>: View {
  let symbol: String
  let title: String
  let caption: String
  @ViewBuilder let actions: Actions

  var body: some View {
    ScrollView {
      EmptyStateView(symbol: symbol, title: title, caption: caption) { actions }
        .containerRelativeFrame(.vertical)
    }
  }
}

extension PaneEmptyState where Actions == EmptyView {
  init(symbol: String, title: String, caption: String) {
    self.init(symbol: symbol, title: title, caption: caption) { EmptyView() }
  }
}
