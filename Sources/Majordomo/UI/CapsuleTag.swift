// The little capsule at a row's trailing edge: an item state (colored) or
// its reason (muted; accent-tinted for the "needs you" tier).

import SwiftUI

struct CapsuleTag: View {
  let text: String
  var tint: Color?
  /// On a selected row the tint would vanish into the accent background —
  /// hierarchical styles adapt to both emphasized and gray selections.
  var selected = false

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(tint ?? Color.secondary))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle((tint ?? Color.secondary).opacity(0.14)),
        in: Capsule()
      )
      .lineLimit(1)
      .fixedSize()
  }
}

/// The capsule an item shows: state wins for pull-likes, reason otherwise.
struct ItemCapsule: View {
  let item: InboxItem
  var selected = false

  var body: some View {
    let providerSpec = spec(for: item.provider)
    if let capsule = providerSpec.stateCapsule(for: item) {
      CapsuleTag(text: capsule.label, tint: capsule.color, selected: selected)
    } else {
      CapsuleTag(
        text: providerSpec.reasonLabel(item.reason),
        tint: item.isMention ? Color.accentColor : nil,
        selected: selected
      )
    }
  }
}
