// The little capsules: an item's state (colored) or reason (muted;
// accent-tinted for the "needs you" tier), and the user's labels in their
// own tints.

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

/// A label's pill: its glyph and name in its tint. Rows show a couple at
/// most, the preview shows them all.
struct LabelCapsule: View {
  let label: InboxLabel
  var selected = false

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: label.symbol)
        .font(.system(size: 9, weight: .medium))
      Text(label.name)
        .font(.system(size: 10, weight: .medium))
    }
    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(label.tint.color))
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(
      selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(label.tint.color.opacity(0.14)),
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
