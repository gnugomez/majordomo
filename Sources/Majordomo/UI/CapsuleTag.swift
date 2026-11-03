// The little capsules: an item's state (colored) or reason (muted;
// accent-tinted for the "needs you" tier), and the user's labels in their
// own tints. Every one is the same pill: its tint over a wash of itself,
// or on a selected row the row's own styles (RowStyle).

import SwiftUI

struct CapsuleTag: View {
  let text: String
  var tint: Color?
  var selected = false

  var body: some View {
    Text(text)
      .font(.app(.badge, weight: .medium))
      .capsule(tint: tint ?? .secondary, selected: selected)
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
        .font(.app(.badge, weight: .medium))
    }
    .capsule(tint: label.tint.color, selected: selected)
  }
}

/// Why a notification arrived, as its provider words it — accent-tinted
/// when it is the user being mentioned.
struct ReasonCapsule: View {
  let item: InboxItem
  var selected = false

  var body: some View {
    CapsuleTag(
      text: spec(for: item.provider).reasonLabel(item.reason),
      tint: item.isMention ? Color.accentColor : nil,
      selected: selected
    )
  }
}

/// The capsule an item shows: state wins for pull-likes, reason otherwise.
struct ItemCapsule: View {
  let item: InboxItem
  var selected = false

  var body: some View {
    if let capsule = spec(for: item.provider).stateCapsule(for: item) {
      CapsuleTag(text: capsule.label, tint: capsule.color, selected: selected)
    } else {
      ReasonCapsule(item: item, selected: selected)
    }
  }
}

private extension View {
  /// The pill itself: content in `tint` over a wash of it — on a selected
  /// row, the row's primary style over a quaternary fill, which the
  /// selection's own color can't swallow.
  func capsule(tint: Color, selected: Bool) -> some View {
    foregroundStyle(tint.onRow(selected: selected))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(tint.opacity(0.14)),
        in: Capsule()
      )
      .lineLimit(1)
      .fixedSize()
  }
}
