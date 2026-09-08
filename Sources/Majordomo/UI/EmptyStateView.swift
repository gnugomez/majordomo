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
        .font(.system(size: 13, weight: .semibold))
      Text(caption)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
