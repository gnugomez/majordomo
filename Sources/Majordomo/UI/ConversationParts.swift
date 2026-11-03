// The pieces a conversation is drawn with, shared by the timeline and a
// thread's message cards: the card itself, a body that folds when it runs
// long, the "Author" mark, an event's glyph, the byline, and an entry's
// time.

import SwiftUI

extension View {
  /// The card a conversation entry or a thread's message sits on: a light
  /// wash over the inspector's material, a hairline edge, a soft shadow. An accent `outline` marks one a notification points at or
  /// the user picked; `tint` washes it in that color too.
  func conversationCard(
    outline: AnyShapeStyle? = nil, lineWidth: CGFloat = 1.5, tint: Color? = nil
  ) -> some View {
    padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 10)
          .fill(Palette.paneCard)
          .overlay {
            if let tint {
              RoundedRectangle(cornerRadius: 10).fill(tint)
            }
          }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(outline ?? AnyShapeStyle(.separator), lineWidth: outline == nil ? 0.5 : lineWidth)
      }
      .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
  }
}

/// A body shown up to `limit` tall, fading out at the cut, with a way to
/// read the rest. A little over the limit isn't worth a cut of its own;
/// nil never cuts.
struct CollapsibleBody<Content: View>: View {
  let limit: CGFloat?
  @ViewBuilder let content: Content

  @State private var expanded = false
  @State private var fullHeight: CGFloat = 0

  var body: some View {
    let overflows = limit.map { fullHeight > $0 + 60 } ?? false
    let collapsed = overflows && !expanded
    VStack(alignment: .leading, spacing: 6) {
      content
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
        .frame(maxHeight: collapsed ? limit : nil, alignment: .top)
        .clipped()
        .mask {
          if collapsed {
            LinearGradient(colors: [.black, .black, .black, .clear], startPoint: .top, endPoint: .bottom)
          } else {
            Rectangle()
          }
        }
      if overflows {
        Button(expanded ? "Show Less" : "Show More") {
          expanded.toggle()
        }
        .buttonStyle(.link)
        .font(.app(.callout))
      }
    }
  }
}

/// Marks an entry by whoever opened the target.
struct AuthorMark: View {
  var body: some View {
    Text("Author")
      .font(.app(.badge, weight: .medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 1.5)
      .overlay(Capsule().strokeBorder(.tertiary, lineWidth: 1))
      .fixedSize()
      .help("Opened this conversation")
  }
}

/// An event's glyph, white on its color in a circle; `ring` sets it off
/// from what it sits on.
struct EventGlyph: View {
  let badge: CardBadge
  var size: CGFloat = 24
  var ring: Color = Palette.card

  var body: some View {
    Circle()
      .fill(badge.color)
      .overlay {
        GlyphImage(glyph: badge.glyph, size: size * 0.55)
          .foregroundStyle(.white)
      }
      .frame(width: size, height: size)
      .padding(size > 16 ? 2 : 1.5)
      .background(ring, in: Circle())
  }
}

/// Who wrote an entry and when, after their face: the name, what they did
/// when it isn't a plain comment, the Author mark, why a notification
/// points here, then the time at the far end. Pieces of the caller's row,
/// so they space the way the row does.
struct Byline: View {
  let name: String?
  /// What they did, after the name ("approved", "opened #12").
  var action: String?
  var isTargetAuthor = false
  /// Why a previewed notification points here, as the provider words it.
  var reason: String?
  var reasonTint: Color? = .accentColor
  let date: Date?
  let now: Date

  @Environment(\.searchHighlightTerms) private var highlightTerms

  var body: some View {
    if let name {
      Text(highlighted(name, terms: highlightTerms))
        .font(.app(.body, weight: .semibold))
        .lineLimit(1)
        .layoutPriority(1)
    }
    if let action {
      Text(action)
        .font(.app(.body))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    if isTargetAuthor {
      AuthorMark()
    }
    if let reason {
      CapsuleTag(text: reason, tint: reasonTint)
    }
    Spacer(minLength: 4)
    if let date {
      EntryTime(date: date, now: now)
    }
  }
}

/// How long ago, the date in full on hover.
struct EntryTime: View {
  let date: Date
  let now: Date

  var body: some View {
    Text(relativeTime(date, now: now))
      .font(.app(.callout))
      .foregroundStyle(.secondary)
      .monospacedDigit()
      .lineLimit(1)
      .fixedSize()
      .help(absoluteTime(date))
  }
}

/// A body's opening words on one or a few lines, Markdown set aside.
@MainActor
func excerpt(of body: String, limit: Int = 280) -> String {
  let words = MarkdownDocument.parsed(body).plainText
  return words.count > limit ? String(words.prefix(limit)) + "…" : words
}
