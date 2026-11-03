// Centered icon + title + caption.

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
