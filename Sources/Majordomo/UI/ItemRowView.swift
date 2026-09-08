// One inbox row, ported from src/ui/inbox/ItemRow.tsx: Mail-style unread
// dot, title line with the kind glyph, meta line with the provider hint and
// the capsule. Selected rows swap every fixed color for hierarchical styles,
// which AppKit flips to white on an emphasized (accent) selection and keeps
// dark on an unfocused gray one — explicit colors would do neither.

import SwiftUI

struct ItemRowView: View {
  let item: InboxItem
  let now: Date
  var selected = false

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      // Mail's unread gutter: a leading accent dot, with the space reserved
      // on read rows so everything stays aligned.
      Circle()
        .fill(item.read ? AnyShapeStyle(.clear) : (selected ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor)))
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Image(systemName: spec(for: item.provider).symbol(for: item))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(
              selected ? AnyShapeStyle(.primary) : AnyShapeStyle(spec(for: item.provider).color(for: item))
            )
          Text(item.title)
            .font(.system(size: 13, weight: item.read ? .regular : .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
        }
        HStack(spacing: 4) {
          Text(metaLine(for: item, now: now))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
          // A subtle whose-item-is-this hint, riding along after the time.
          ProviderMark(provider: item.provider)
            .foregroundStyle(.tertiary)
            .frame(width: 10, height: 10)
          Spacer(minLength: 6)
          ItemCapsule(item: item, selected: selected)
        }
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .help(item.title)
  }
}
