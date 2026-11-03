// The preview's sections for a notification's target in full: the comment
// that raised the notification, the target's description, and the latest
// of its conversation — as the background refresh stored them (see
// AppModel.loadConversation).

import SwiftUI

/// The description shows this tall at most until it is expanded.
private let collapsedDescriptionHeight: CGFloat = 220

/// Why the notification arrived: the comment that raised it, set apart at
/// the top of the preview. The header above already names the reason.
struct TriggerCard: View {
  let comment: DetailComment
  let now: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CommentByline(comment: comment, now: now)
      MarkdownBody(text: comment.body)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
    )
  }
}

/// The target's own description, cut to a few lines' height when it runs
/// long, with a way to read the rest.
struct DescriptionSection: View {
  let text: String

  @State private var expanded = false
  @State private var fullHeight: CGFloat = 0

  var body: some View {
    // A little over the cut isn't worth a "Show more" of its own.
    let overflows = fullHeight > collapsedDescriptionHeight + 40
    let collapsed = overflows && !expanded
    VStack(alignment: .leading, spacing: 8) {
      SectionHeading(title: "Description")
      MarkdownBody(text: text)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
        .frame(maxHeight: collapsed ? collapsedDescriptionHeight : nil, alignment: .top)
        .clipped()
        .mask {
          if collapsed {
            LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
          } else {
            Rectangle()
          }
        }
      if overflows {
        Button(expanded ? "Show Less" : "Show More") {
          expanded.toggle()
        }
        .buttonStyle(.link)
        .font(.system(size: 12))
      }
    }
  }
}

/// The latest comments, oldest first. The one that raised the notification
/// is marked where it sits; when the card above already shows it, its text
/// isn't repeated.
struct ConversationSection: View {
  let comments: [DetailComment]
  /// The comment the card above shows, marked where it sits rather than
  /// repeated; nil when no card shows one.
  let triggerId: String?
  /// The notification's reason, worded by its provider, for that mark.
  let reason: String
  /// How many the target holds in all, when known.
  let commentCount: Int?
  let providerName: String
  let url: URL?
  let now: Date

  var body: some View {
    let earlier = max((commentCount ?? 0) - comments.count, 0)
    VStack(alignment: .leading, spacing: 12) {
      SectionHeading(title: earlier > 0 ? "Latest Comments" : "Comments")
      ForEach(comments) { comment in
        commentRow(comment, isTrigger: comment.id == triggerId)
      }
      if earlier > 0 {
        HStack(spacing: 4) {
          Text(earlier == 1 ? "1 earlier comment" : "\(earlier) earlier comments")
            .foregroundStyle(.tertiary)
          if let url {
            Link("Read on \(providerName)", destination: url)
          }
        }
        .font(.system(size: 12))
      }
    }
  }

  private func commentRow(_ comment: DetailComment, isTrigger: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        CommentByline(comment: comment, now: now)
        if isTrigger {
          CapsuleTag(text: reason, tint: Color.accentColor)
        }
      }
      if isTrigger {
        Text("Shown above")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
      } else {
        MarkdownBody(text: comment.body)
      }
    }
    .padding(.leading, 10)
    .overlay(alignment: .leading) {
      RoundedRectangle(cornerRadius: 1)
        .fill(isTrigger ? AnyShapeStyle(Color.accentColor.opacity(0.6)) : AnyShapeStyle(.quaternary))
        .frame(width: 2)
    }
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
      .font(.system(size: 12))
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
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled)
  }
}

/// Who wrote a comment, and how long ago.
private struct CommentByline: View {
  let comment: DetailComment
  let now: Date

  var body: some View {
    HStack(spacing: 6) {
      Text(comment.author.map { "@\($0)" } ?? "Someone")
        .font(.system(size: 12, weight: .semibold))
      Text(relativeTime(comment.createdAt, now: now))
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
    }
  }
}

private struct SectionHeading: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.secondary)
  }
}
