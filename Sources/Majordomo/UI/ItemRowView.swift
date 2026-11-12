// The inbox rows. ItemRowView is a thread's summary row: an unread dot,
// title line with the kind glyph, then a meta line assembled from whichever
// fields the user's RowLayout shows, in the order it puts them — where and
// who, when, the provider hint, the label pills, the capsule, and the marks
// for where the target's review, checks, and merging stand — plus a
// tappable member count that unfolds the thread, and an optional excerpt of
// the item's text under the rest.
// Once its target has been refreshed, the row reads the target's current
// state rather than the one the notification carried: the kind glyph and
// the capsule show a pull request merged since as merged.
// The excerpt line is the model's one-line summary when it has written
// one, marked with the glyph that stands for a generated line; the item's
// own text stands in until then.
// MemberRowView is one unfolded member, indented beneath its summary; the
// excerpt switch governs its snippet too, so turning excerpts off quiets
// the whole list.
// Selected rows swap every fixed color for the row's own styles (RowStyle).
// Both rows are Equatable over what they draw, so a list redrawn for one
// row's sake — a selection, a read — leaves the others alone.

import SwiftUI

/// Label pills a row shows before folding the rest into "+N".
private let rowLabelCap = 2

/// The mark on a line the on-device model wrote: the system's own summary
/// glyph, so what it means reads at a glance.
let summaryGlyph = "text.line.2.summary"

/// One element of a row's meta line, ready to draw.
private enum MetaPiece {
  /// Inline text; `truncates` marks what a narrow column may cut — the
  /// time never is, so it keeps its full size while the repo loses its
  /// tail.
  case text(String, truncates: Bool)
  case mark(ProviderId)
  case labels([InboxLabel])
  case status(InboxItem)
  case target(TargetStatus)

  var isText: Bool {
    if case .text = self {
      return true
    }
    return false
  }

  var isBadge: Bool {
    switch self {
    case .labels, .status, .target: true
    case .text, .mark: false
    }
  }
}

struct ItemRowView: View, Equatable {
  let thread: InboxThread
  let now: Date
  /// The labels any member of the thread carries, in folder order.
  var labels: [InboxLabel] = []
  /// What the row shows, and in what order.
  var layout: RowLayout = .default
  /// Where the thread's target stands; nil until a refresh has described
  /// it, or when it points at nothing tracked.
  var targetStatus: TargetStatus?
  var selected = false
  var expanded = false
  var onToggleExpand: (() -> Void)?

  @Environment(\.searchHighlightTerms) private var highlightTerms

  /// Everything but the expand action, which only ever toggles this
  /// thread; the clock counts only as the time it reads.
  nonisolated static func == (lhs: ItemRowView, rhs: ItemRowView) -> Bool {
    lhs.thread.id == rhs.thread.id && lhs.thread.items == rhs.thread.items
      && lhs.time == rhs.time && lhs.labels == rhs.labels && lhs.layout == rhs.layout
      && lhs.targetStatus == rhs.targetStatus && lhs.selected == rhs.selected && lhs.expanded == rhs.expanded
  }

  /// How long ago the thread last moved, as the row says it.
  private nonisolated var time: String {
    relativeTime(thread.lead.updatedAt, now: now)
  }

  var body: some View {
    let item = targetStatus?.presenting(thread.lead) ?? thread.lead
    let pieces = metaPieces(for: item)
    let excerpt = excerptLine(for: item, layout: layout, terms: highlightTerms)
    // Two lines center against the dot; with an excerpt the row runs to
    // three, and the dot rides at the top the way the member rows' does.
    HStack(alignment: excerpt == nil ? .center : .top, spacing: 8) {
      // The unread gutter: a leading accent dot, with the space reserved
      // on read rows so everything stays aligned.
      UnreadDot(unread: !thread.read, size: 8, selected: selected)
        .padding(.top, excerpt == nil ? 0 : 4)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          GlyphImage(glyph: spec(for: item.provider).glyph(for: item))
            .foregroundStyle(spec(for: item.provider).color(for: item).onRow(selected: selected))
          Text(highlighted(item.title, terms: highlightTerms))
            .font(.app(.body, weight: thread.read ? .regular : .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
        }
        // A layout showing the target's marks keeps the line even while
        // they have yet to come, so the row's height never waits on them.
        if !pieces.isEmpty || thread.items.count > 1 || layout.shows(.target) {
          metaLine(pieces)
        }
        if let excerpt {
          excerpt
            .font(.app(.caption))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .help(item.title)
  }

  /// The meta line: the inline fields, then the flexible gap that pins the
  /// badges — and the thread count — to the trailing end. A field dragged
  /// behind the badges lands there with them.
  private func metaLine(_ pieces: [MetaPiece]) -> some View {
    let badges = pieces.firstIndex(where: \.isBadge) ?? pieces.count
    // The hidden line of text holds the line at a text line's height
    // whatever is on it: the target's marks come and go with refreshes,
    // and a list row keeps the height it was first measured at.
    return ZStack(alignment: .leading) {
      Text(verbatim: " ")
        .font(.app(.caption))
        .hidden()
      HStack(spacing: 4) {
        metaRun(Array(pieces[..<badges]))
        Spacer(minLength: 6)
        metaRun(Array(pieces[badges...]))
        if thread.items.count > 1 {
          memberCount
        }
      }
    }
  }

  private func metaRun(_ run: [MetaPiece]) -> some View {
    ForEach(Array(run.enumerated()), id: \.offset) { index, piece in
      // The dot joins two text fields — "acme/atlas · mona · 3h"; nothing
      // else on the line takes one.
      metaView(piece, separated: index > 0 && run[index - 1].isText && piece.isText)
    }
  }

  @ViewBuilder
  private func metaView(_ piece: MetaPiece, separated: Bool) -> some View {
    switch piece {
    case .text(let text, let truncates):
      let line = Text(highlighted(separated ? "· \(text)" : text, terms: highlightTerms))
        .font(.app(.caption))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
      if truncates {
        line
      } else {
        line.fixedSize()
      }
    case .mark(let provider):
      // A subtle whose-item-is-this hint.
      ProviderMark(provider: provider)
        .foregroundStyle(.tertiary)
        .frame(width: 10, height: 10)
    case .labels(let labels):
      // A couple at most so the row stays one line; the rest fold into a
      // count.
      ForEach(labels.prefix(rowLabelCap)) { label in
        LabelCapsule(label: label, selected: selected)
      }
      if labels.count > rowLabelCap {
        CapsuleTag(text: "+\(labels.count - rowLabelCap)", selected: selected)
      }
    case .status(let item):
      ItemCapsule(item: item, selected: selected)
    case .target(let status):
      // Glyphs only, fewer when the line runs short; their words are in
      // the tooltips.
      TargetBadges(status: status, density: .compact, selected: selected)
    }
  }

  /// The meta line's elements in the layout's order, skipping the fields
  /// this item has nothing to say for. Neighboring text fields fuse into
  /// one run, so a narrow column truncates "repo · author" as a unit.
  private func metaPieces(for item: InboxItem) -> [MetaPiece] {
    var pieces: [MetaPiece] = []
    for field in layout.visible {
      switch field {
      case .repo:
        if !item.repo.isEmpty {
          add(.text(item.repo, truncates: true), to: &pieces)
        }
      case .author:
        if let author = item.author {
          add(.text(author, truncates: true), to: &pieces)
        }
      case .time:
        add(.text(time, truncates: false), to: &pieces)
        if let until = thread.snoozedUntil {
          add(.text(snoozeWording(until: until, now: now), truncates: false), to: &pieces)
        }
      case .provider:
        pieces.append(.mark(item.provider))
      case .labels:
        if !labels.isEmpty {
          pieces.append(.labels(labels))
        }
      case .status:
        pieces.append(.status(item))
      case .target:
        if let targetStatus, !targetStatus.rowMarks.isEmpty {
          pieces.append(.target(targetStatus))
        }
      case .excerpt:
        // A line of its own, under the rest.
        break
      }
    }
    return pieces
  }

  /// Appends a piece, fusing it into the one before when both are text
  /// that truncates the same way.
  private func add(_ piece: MetaPiece, to pieces: inout [MetaPiece]) {
    guard case .text(let text, let truncates) = piece,
          case .text(let previous, truncates)? = pieces.last else {
      pieces.append(piece)
      return
    }
    pieces[pieces.count - 1] = .text("\(previous) · \(text)", truncates: truncates)
  }

  /// The thread count at the row's far end — "3 ›", a button that
  /// unfolds the members into the list ("3 ⌄" while open).
  private var memberCount: some View {
    Button {
      onToggleExpand?()
    } label: {
      HStack(spacing: 2) {
        Text("\(thread.items.count)")
          .font(.app(.caption, weight: .medium))
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
          .font(.system(size: 8, weight: .semibold))
      }
      .foregroundStyle(Color.accentColor.onRow(selected: selected))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(expanded ? "Collapse the thread" : "Show the \(thread.items.count) notifications")
  }
}

/// One unfolded thread member: indented under the summary row, with its
/// own unread dot, reason, author, time, and a body snippet.
struct MemberRowView: View, Equatable {
  let member: InboxItem
  let now: Date
  var layout: RowLayout = .default
  var selected = false

  @Environment(\.searchHighlightTerms) private var highlightTerms

  nonisolated static func == (lhs: MemberRowView, rhs: MemberRowView) -> Bool {
    lhs.member == rhs.member && lhs.time == rhs.time && lhs.layout == rhs.layout && lhs.selected == rhs.selected
  }

  /// How long ago the member arrived, as the row says it.
  private nonisolated var time: String {
    relativeTime(member.updatedAt, now: now)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      UnreadDot(unread: !member.read, size: 8, selected: selected)
        .padding(.top, 4)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 4) {
          ReasonCapsule(item: member, selected: selected)
          if let author = member.author {
            Text(highlighted(author, terms: highlightTerms))
              .font(.app(.caption))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 6)
          Text(time)
            .font(.app(.caption))
            .foregroundStyle(.secondary)
        }
        if let excerpt = excerptLine(for: member, layout: layout, terms: highlightTerms) {
          excerpt
            .font(.app(.caption))
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
}

/// What goes under a row: the model's summary when it has written one, led
/// by the glyph that says so and wrapping under it; otherwise the item's
/// own text. nil when the layout hides the line, or when there is nothing
/// to show.
@MainActor
private func excerptLine(for item: InboxItem, layout: RowLayout, terms: [String]) -> Text? {
  guard layout.shows(.excerpt) else {
    return nil
  }
  if let summary = item.summary, !summary.isEmpty {
    return Text("\(Image(systemName: summaryGlyph)) \(highlighted(summary, terms: terms))")
  }
  return bodySnippet(item.body, terms: terms).map(Text.init)
}

/// A body flattened to preview text — inline markdown only, so code fences
/// and quote markers don't render as syntax noise.
@MainActor
private func bodySnippet(_ body: String?, terms: [String]) -> AttributedString? {
  guard let body else {
    return nil
  }
  return highlighted(InlineSnippets.parsed(body), terms: terms)
}

/// Bodies parsed for a row's excerpt, by their text: a list redraws its
/// rows far more often than their bodies change.
@MainActor
private enum InlineSnippets {
  private final class Parsed {
    let text: AttributedString

    init(_ text: AttributedString) {
      self.text = text
    }
  }

  private static let held: NSCache<NSString, Parsed> = {
    let cache = NSCache<NSString, Parsed>()
    cache.countLimit = 1000
    return cache
  }()

  static func parsed(_ body: String) -> AttributedString {
    if let parsed = held.object(forKey: body as NSString) {
      return parsed.text
    }
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let inline = (try? AttributedString(markdown: body, options: options)) ?? AttributedString(body)
    held.setObject(Parsed(inline), forKey: body as NSString)
    return inline
  }
}
