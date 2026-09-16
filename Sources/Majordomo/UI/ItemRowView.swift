// The inbox rows. ItemRowView is a thread's summary row: an unread dot,
// title line with the kind glyph, meta line with the provider hint, a
// tappable member count that unfolds the thread, and the capsule.
// MemberRowView is one unfolded member, indented beneath its summary.
// Selected rows swap every fixed color for hierarchical styles, which AppKit
// flips to white on an emphasized (accent) selection and keeps dark on an
// unfocused gray one — explicit colors would do neither.

import SwiftUI

struct ItemRowView: View {
  let thread: InboxThread
  let now: Date
  var selected = false
  var expanded = false
  var onToggleExpand: (() -> Void)?

  @Environment(\.searchHighlightTerms) private var highlightTerms

  var body: some View {
    let item = thread.lead
    HStack(alignment: .center, spacing: 8) {
      // The unread gutter: a leading accent dot, with the space reserved
      // on read rows so everything stays aligned.
      Circle()
        .fill(thread.read ? AnyShapeStyle(.clear) : (selected ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor)))
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Image(systemName: spec(for: item.provider).symbol(for: item))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(
              selected ? AnyShapeStyle(.primary) : AnyShapeStyle(spec(for: item.provider).color(for: item))
            )
          Text(highlighted(item.title, terms: highlightTerms))
            .font(.system(size: 13, weight: thread.read ? .regular : .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
        }
        HStack(spacing: 4) {
          Text(highlighted(metaLine(for: item, now: now), terms: highlightTerms))
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
          if thread.items.count > 1 {
            memberCount
          }
        }
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .help(item.title)
  }

  /// The thread count at the row's far end — "3 ›", a button that
  /// unfolds the members into the list ("3 ⌄" while open).
  private var memberCount: some View {
    Button {
      onToggleExpand?()
    } label: {
      HStack(spacing: 2) {
        Text("\(thread.items.count)")
          .font(.system(size: 11, weight: .medium))
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
          .font(.system(size: 8, weight: .semibold))
      }
      .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(expanded ? "Collapse the thread" : "Show the \(thread.items.count) notifications")
  }
}

/// One unfolded thread member: indented under the summary row, with its
/// own unread dot, reason, author, time, and a body snippet.
struct MemberRowView: View {
  let member: InboxItem
  let now: Date
  var selected = false

  @Environment(\.searchHighlightTerms) private var highlightTerms

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Circle()
        .fill(member.read ? AnyShapeStyle(.clear) : (selected ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor)))
        .frame(width: 8, height: 8)
        .padding(.top, 4)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 4) {
          CapsuleTag(
            text: spec(for: member.provider).reasonLabel(member.reason),
            tint: member.isMention ? Color.accentColor : nil,
            selected: selected
          )
          if let author = member.author {
            Text(highlighted(author, terms: highlightTerms))
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 6)
          Text(relativeTime(member.updatedAt, now: now))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        if let snippet {
          Text(snippet)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
    }
    .padding(.vertical, 3)
    // The indent that reads as "part of the row above".
    .padding(.leading, 16)
    .contentShape(Rectangle())
  }

  /// The body flattened to preview text — inline markdown only, so code
  /// fences and quote markers don't render as syntax noise.
  private var snippet: AttributedString? {
    guard let body = member.body else {
      return nil
    }
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let inline = (try? AttributedString(markdown: body, options: options)) ?? AttributedString(body)
    return highlighted(inline, terms: highlightTerms)
  }
}
