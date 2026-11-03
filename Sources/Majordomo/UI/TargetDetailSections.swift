// The preview's sections for a notification's target in full, as the
// background refresh stored it (see AppModel.loadConversation): the
// conversation as a timeline — the description as the opening post, then
// the latest comments and reviews, each a card with its author's face —
// and, at the top, the comment the notification points at, named with a
// way down to it.
//
// The comment a notification points at reads once, in its place in the
// timeline, outlined and marked with why it arrived: what it answers is
// right above it. The top of the preview only names it — who, why, how it
// starts — and a click scrolls there. Scrolling to it on its own would
// carry the title and facts out of view on every selection, which is
// what the user triages by while arrowing down the list.

import SwiftUI

/// Where the comments a notification points at sit in the preview's
/// content, so a jump can scroll to one. The pane scrolls to an offset
/// rather than to a view's id: the inspector's scroll view finds no id
/// nested this deep. A plain class, out of observation: offsets move as
/// images load, and only a jump reads them.
@MainActor
final class CommentOffsets {
  /// The coordinate space offsets are measured in: the pane's content.
  nonisolated static let space = "preview-content"

  private var byId: [String: CGFloat] = [:]

  func note(_ id: String, _ offset: CGFloat) {
    byId[id] = offset
  }

  func offset(of id: String) -> CGFloat? {
    byId[id]
  }

  func forget() {
    byId = [:]
  }
}

/// Comments show this tall at most until expanded; a description a little
/// less, being further from what changed.
private let collapsedCommentHeight: CGFloat = 320
private let collapsedDescriptionHeight: CGFloat = 240

/// The target's conversation as a timeline: the opening post, how many
/// earlier comments stayed at the provider, then the latest comments and
/// events, oldest first, along a thread line. Comments a previewed
/// notification points at are outlined and marked with why.
struct ConversationTimeline: View {
  let conversation: TargetConversation
  /// The previewed notification, for its provider, target, and wording.
  let item: InboxItem
  /// Comments the previewed notifications point at, by id, with the reason
  /// each arrived for, as the provider words it.
  let triggers: [String: String]
  /// The comment just jumped to, lit up for a moment.
  let flashedId: String?
  let now: Date
  /// Told where each comment a notification points at sits, in the
  /// `CommentOffsets.space` coordinate space, as it moves.
  let placed: (String, CGFloat) -> Void

  var body: some View {
    let providerSpec = spec(for: item.provider)
    let opener = conversation.author ?? item.author
    let earlier = max((conversation.commentCount ?? 0) - conversation.plainCommentCount, 0)
    VStack(alignment: .leading, spacing: 10) {
      heading
      VStack(alignment: .leading, spacing: 12) {
        TimelineCard(
          author: opener, avatarUrl: conversation.authorAvatarUrl, provider: item.provider,
          action: "opened \(providerSpec.shortReference(for: item) ?? "this")",
          date: conversation.createdAt, now: now, isTargetAuthor: false,
          collapsedHeight: collapsedDescriptionHeight,
          text: conversation.description, emptyText: "No description provided."
        )
        // Another target's opening post starts cut again.
        .id(item.url)
        if earlier > 0 {
          EarlierEntriesRow(count: earlier, providerName: item.provider.displayName, url: URL(string: item.url))
        }
        ForEach(conversation.comments) { comment in
          if triggers[comment.id] != nil {
            entry(comment, providerSpec: providerSpec, opener: opener)
              .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(CommentOffsets.space)).minY
              } action: { offset in
                placed(comment.id, offset)
              }
          } else {
            entry(comment, providerSpec: providerSpec, opener: opener)
          }
        }
      }
      .background(alignment: .leading) {
        // The thread line, through the faces; the cards cover it, so it
        // shows between them and through the events.
        Rectangle()
          .fill(.separator)
          .frame(width: 1)
          .padding(.leading, 23.5)
          .padding(.vertical, 18)
      }
    }
  }

  private var heading: some View {
    HStack {
      Text("Conversation")
        .font(.app(.caption, weight: .semibold))
        .foregroundStyle(.secondary)
      Spacer()
      if let count = conversation.commentCount, count > 0 {
        Text(count == 1 ? "1 comment" : "\(count) comments")
          .font(.app(.caption))
          .foregroundStyle(.tertiary)
      }
    }
  }

  @ViewBuilder
  private func entry(_ comment: DetailComment, providerSpec: any ProviderSpec, opener: String?) -> some View {
    let badge = comment.event.flatMap(providerSpec.eventBadge)
    let byOpener = opener != nil && comment.author?.lowercased() == opener?.lowercased()
    let reason = triggers[comment.id]
    if let badge, comment.body.isEmpty {
      TimelineEventRow(
        comment: comment, badge: badge, provider: item.provider, isTargetAuthor: byOpener,
        reason: reason, now: now
      )
    } else {
      TimelineCard(
        author: comment.author, avatarUrl: comment.avatarUrl, provider: item.provider,
        action: badge?.label, badge: badge, date: comment.createdAt, now: now, isTargetAuthor: byOpener,
        reason: reason, flashed: flashedId == comment.id,
        // What the notification points at reads whole.
        collapsedHeight: reason == nil ? collapsedCommentHeight : nil,
        text: comment.body
      )
    }
  }
}

/// One entry as a card: the author's face and name, what they did when it
/// isn't a plain comment, the marks, the time — then the body.
private struct TimelineCard: View {
  let author: String?
  let avatarUrl: String?
  let provider: ProviderId
  /// What the author did, after their name ("approved", "opened #12");
  /// nil for a plain comment.
  var action: String?
  /// An event's mark, worn on the face.
  var badge: CardBadge?
  let date: Date?
  let now: Date
  let isTargetAuthor: Bool
  /// Why a previewed notification points here, as the provider words it.
  var reason: String?
  var flashed = false
  /// The tallest it shows until expanded; nil shows it whole.
  let collapsedHeight: CGFloat?
  let text: String?
  /// What stands in for a missing body.
  var emptyText: String?

  @Environment(\.searchHighlightTerms) private var highlightTerms

  var body: some View {
    let marked = reason != nil
    VStack(alignment: .leading, spacing: 10) {
      header
      if let text, !text.isEmpty {
        CollapsibleBody(limit: collapsedHeight) {
          MarkdownBody(text: text)
        }
      } else if let emptyText {
        Text(emptyText)
          .font(.app(.body))
          .italic()
          .foregroundStyle(.tertiary)
      }
    }
    .conversationCard(
      outline: marked ? AnyShapeStyle(Color.accentColor.opacity(flashed ? 1 : 0.65)) : nil,
      lineWidth: flashed ? 2.5 : 1.5,
      tint: marked ? Color.accentColor.opacity(flashed ? 0.12 : 0.04) : nil
    )
    .animation(.easeOut(duration: 0.4), value: flashed)
  }

  private var header: some View {
    HStack(spacing: 8) {
      PersonAvatar(login: author, avatarUrl: avatarUrl, provider: provider, size: 24)
        .overlay(alignment: .bottomTrailing) {
          if let badge {
            EventGlyph(badge: badge, size: 13)
              .offset(x: 5, y: 5)
          }
        }
      Text(highlighted(author ?? "Someone", terms: highlightTerms))
        .font(.app(.body, weight: .semibold))
        .lineLimit(1)
        .layoutPriority(1)
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
        CapsuleTag(text: reason, tint: Color.accentColor)
      }
      Spacer(minLength: 4)
      if let date {
        EntryTime(date: date, now: now)
      }
    }
  }
}

/// An event that came without words, on the thread line: its glyph, who,
/// what, when.
private struct TimelineEventRow: View {
  let comment: DetailComment
  let badge: CardBadge
  let provider: ProviderId
  let isTargetAuthor: Bool
  let reason: String?
  let now: Date

  @Environment(\.searchHighlightTerms) private var highlightTerms

  var body: some View {
    HStack(spacing: 8) {
      EventGlyph(badge: badge, size: 22, ring: Palette.pane)
      PersonAvatar(login: comment.author, avatarUrl: comment.avatarUrl, provider: provider, size: 18)
      Text(highlighted(comment.author ?? "Someone", terms: highlightTerms))
        .font(.app(.body, weight: .semibold))
        .lineLimit(1)
        .layoutPriority(1)
      Text(badge.label)
        .font(.app(.body))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      if isTargetAuthor {
        AuthorMark()
      }
      if let reason {
        CapsuleTag(text: reason, tint: Color.accentColor)
      }
      Spacer(minLength: 4)
      EntryTime(date: comment.createdAt, now: now)
    }
    .padding(.leading, 11)
    .padding(.trailing, 12)
  }
}

/// Where the timeline skips the comments that stayed at the provider.
private struct EarlierEntriesRow: View {
  let count: Int
  let providerName: String
  let url: URL?

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "ellipsis")
        .font(.app(.badge, weight: .bold))
        .foregroundStyle(.secondary)
        .frame(width: 22, height: 22)
        .background(Palette.card, in: Circle())
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        .padding(2)
        .background(Palette.pane, in: Circle())
      Text(count == 1 ? "1 earlier comment" : "\(count) earlier comments")
        .foregroundStyle(.secondary)
      if let url {
        Link("Read on \(providerName)", destination: url)
      }
    }
    .font(.app(.callout))
    .padding(.leading, 11)
  }
}

/// The comment a single notification points at, named at the top of the
/// preview: who wrote it, why it arrived, how it starts. A click scrolls
/// the timeline down to it.
struct TriggerJump: View {
  let comment: DetailComment
  /// Why it arrived, as the provider words it.
  let reason: String
  let provider: ProviderId
  let now: Date
  let jump: () -> Void

  var body: some View {
    Button(action: jump) {
      HStack(alignment: .center, spacing: 10) {
        PersonAvatar(login: comment.author, avatarUrl: comment.avatarUrl, provider: provider, size: 28)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(comment.author ?? "Someone")
              .font(.app(.body, weight: .semibold))
              .lineLimit(1)
            CapsuleTag(text: reason, tint: Color.accentColor)
            Spacer(minLength: 4)
            EntryTime(date: comment.createdAt, now: now)
          }
          Text(excerpt(of: comment.body))
            .font(.app(.callout))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 17))
          .foregroundStyle(Color.accentColor)
      }
      .padding(10)
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.tint(Color.accentColor.opacity(0.1)).interactive(), in: RoundedRectangle(cornerRadius: 12))
    .help("Show this comment in the conversation")
  }
}

/// While the conversation is on its way, or why it isn't in.
struct ConversationStatusRow: View {
  let load: AppModel.ConversationLoad?

  var body: some View {
    switch load {
    case .fetching:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Loading the conversation…")
          .foregroundStyle(.secondary)
      }
      .font(.app(.callout))
    case .unreadable(let message):
      notice(message)
    case .waiting(let message):
      notice("\(message) Majordomo asks again with the next refresh.")
    case .loaded, nil:
      EmptyView()
    }
  }

  private func notice(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle")
      .font(.app(.callout))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled)
  }
}
