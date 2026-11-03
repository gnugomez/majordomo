// Right pane of the main window: everything AppModel knows about the
// selected thread — where its target stands now, who it is assigned to and
// who is still asked to review it — then its target in full: who opened it
// and what it says, the latest comments and reviews, as the background
// refresh stored it, read from disk, as a timeline of cards on a gray
// pane. A target the refresh hasn't reached yet is asked for ahead of it.
// A multi-member thread stacks its messages as cards of the same kind
// under the shared header. The images the bodies show come through the
// item's own account (AppModel.bodyImages), handed down in the environment.

import SwiftUI

struct PreviewView: View {
  let model: AppModel
  let thread: InboxThread?

  /// The comment just jumped to, lit up for a moment.
  @State private var flashedCommentId: String?
  /// Where the pane is scrolled: to a comment jumped to, or back to the
  /// title for another thread.
  @State private var scrollPosition = ScrollPosition()
  /// Where the comments the notifications point at sit in the pane.
  @State private var commentOffsets = CommentOffsets()

  var body: some View {
    if let thread {
      let item = thread.lead
      let providerSpec = spec(for: item.provider)
      let load = model.conversation(for: item)
      let conversation = loadedConversation(load)
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          PreviewHeader(
            model: model,
            thread: thread,
            status: model.targetStatus(for: thread),
            snapshot: snapshot(of: item),
            conversation: conversation
          )

          if thread.items.count > 1 {
            ForEach(thread.items) { member in
              let comment = triggerComment(of: member, in: conversation, providerSpec: providerSpec)
              let author = comment?.author ?? member.author
              MessageCard(
                member: member,
                comment: comment,
                avatarUrl: comment?.avatarUrl ?? author.flatMap { conversation?.avatarUrl(of: $0) },
                selected: model.selectedMemberId == member.id,
                now: model.now,
                onSelect: { model.selectedMemberId = member.id },
                onJump: jump(to:)
              )
            }
          } else if let trigger = triggerComment(of: item, in: conversation, providerSpec: providerSpec) {
            TriggerJump(
              comment: trigger, reason: providerSpec.reasonLabel(item.reason), provider: item.provider,
              now: model.now
            ) {
              jump(to: trigger.id)
            }
          } else if conversation == nil, let bodyView = providerSpec.bodyView(for: item) {
            // The notification's own excerpt stands in until the target
            // is in, or when it can't be.
            Divider()
            bodyView
          }
          ConversationStatusRow(load: load)
          if let conversation {
            Divider()
            ConversationTimeline(
              conversation: conversation, item: item, triggers: triggers(of: thread, providerSpec: providerSpec),
              flashedId: flashedCommentId, now: model.now,
              placed: commentOffsets.note
            )
          }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(.named(CommentOffsets.space))
        // Another thread's content replaces this one rather than growing
        // out of it: kept, its pieces would morph from one thread's layout
        // into the next's.
        .id(thread.id)
      }
      .scrollPosition($scrollPosition)
      // Another thread reads from its title down.
      .onChange(of: thread.id) {
        commentOffsets.forget()
        scrollPosition.scrollTo(edge: .top)
      }
      // A switch arriving inside an animation — the card click that also
      // slides the inspector in — shows the new thread at once.
      .transaction(value: thread.id) { transaction in
        transaction.animation = nil
      }
      // The stored conversation, read at once; one not in yet is asked for
      // once the selection settles, so arrowing down the list doesn't send
      // a request per row it passes. A refresh bringing a newer one reads
      // that in turn.
      .task(id: model.conversationVersion(for: item)) {
        if case .fetching = model.conversation(for: item) {
          try? await Task.sleep(for: .milliseconds(250))
        }
        guard !Task.isCancelled else {
          return
        }
        await model.loadConversation(for: item)
      }
      // The pane goes slightly gray so the white cards read as cards.
      .background(Palette.pane)
      .environment(\.bodyImages, model.bodyImages(for: item))
    } else {
      PaneEmptyState(
        symbol: "tray",
        title: "Nothing selected",
        caption: "Select an item from the list to see its details."
      )
    }
  }

  /// What the latest refresh said about the item's target; nil when it
  /// points at nothing tracked, or no refresh has described it yet.
  private func snapshot(of item: InboxItem) -> TargetSnapshot? {
    spec(for: item.provider).boardKey(for: item).flatMap { model.targets[$0]?.snapshot }
  }

  private func loadedConversation(_ load: AppModel.ConversationLoad?) -> TargetConversation? {
    if case .loaded(let conversation) = load {
      return conversation
    }
    return nil
  }

  /// The comment a notification points at, when the stored conversation
  /// still holds it.
  private func triggerComment(
    of item: InboxItem, in conversation: TargetConversation?, providerSpec: any ProviderSpec
  ) -> DetailComment? {
    providerSpec.triggerCommentId(for: item).flatMap { id in
      conversation?.comments.first { $0.id == id }
    }
  }

  /// The comments the thread's notifications point at, with why each
  /// arrived — the first member's reason where two point at one comment.
  private func triggers(of thread: InboxThread, providerSpec: any ProviderSpec) -> [String: String] {
    var triggers: [String: String] = [:]
    for member in thread.items {
      if let id = providerSpec.triggerCommentId(for: member), triggers[id] == nil {
        triggers[id] = providerSpec.reasonLabel(member.reason)
      }
    }
    return triggers
  }

  /// Scrolls the timeline to a comment and lights it up for a moment.
  private func jump(to commentId: String) {
    if let offset = commentOffsets.offset(of: commentId) {
      withAnimation(.smooth) {
        // A little of what it answers stays in view above it.
        scrollPosition.scrollTo(y: max(offset - 12, 0))
      }
    }
    flashedCommentId = commentId
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      if flashedCommentId == commentId {
        flashedCommentId = nil
      }
    }
  }
}

/// The title; the state and reason capsules with where the target's
/// review, checks, and merging stand under them; then the facts. The
/// target reads as it stands now: a pull request merged since its
/// notification came reads merged.
private struct PreviewHeader: View {
  let model: AppModel
  let thread: InboxThread
  let status: TargetStatus?
  let snapshot: TargetSnapshot?
  /// For the faces of the people the facts name.
  let conversation: TargetConversation?

  @Environment(\.searchHighlightTerms) private var highlightTerms

  var body: some View {
    let item = status?.presenting(thread.lead) ?? thread.lead
    let providerSpec = spec(for: item.provider)
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      GlyphImage(glyph: providerSpec.glyph(for: item), size: 16)
        .foregroundStyle(providerSpec.color(for: item))
      Text(highlighted(item.title, terms: highlightTerms))
        .font(.app(.title, weight: .semibold))
        .textSelection(.enabled)
    }

    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        if let capsule = providerSpec.stateCapsule(for: item) {
          CapsuleTag(text: capsule.label, tint: capsule.color)
        }
        if thread.items.count == 1 {
          // A single notification's reason belongs to the header; a
          // thread's reasons ride on its messages below.
          ReasonCapsule(item: item)
        }
        if !thread.read {
          CapsuleTag(text: "unread", tint: Color.accentColor)
        }
      }
      if let status, !status.marks.isEmpty {
        // Glyph and word each, wrapping as the pane narrows.
        FlowLayout(spacing: 10, lineSpacing: 4) {
          TargetBadges(status: status, density: .regular)
        }
      }
    }

    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
      GridRow {
        fieldLabel("Provider")
        HStack(spacing: 5) {
          ProviderMark(provider: item.provider)
            .foregroundStyle(.secondary)
            .frame(width: 13, height: 13)
          Text(item.provider.displayName)
        }
      }
      GridRow {
        fieldLabel("Repository")
        Text(highlighted(item.repo, terms: highlightTerms)).textSelection(.enabled)
      }
      if let author = item.author {
        GridRow {
          fieldLabel("Author")
          Text(highlighted(author, terms: highlightTerms)).textSelection(.enabled)
        }
      }
      if let assignees = snapshot?.assignees, !assignees.isEmpty {
        GridRow {
          fieldLabel(assignees.count == 1 ? "Assignee" : "Assignees")
          PeopleLine(logins: assignees, provider: item.provider, snapshot: snapshot, conversation: conversation)
        }
      }
      if let reviewers = snapshot?.reviewers, !reviewers.isEmpty {
        GridRow {
          fieldLabel(reviewers.count == 1 ? "Reviewer" : "Reviewers")
            .help("Asked for a review and yet to give one")
          PeopleLine(logins: reviewers, provider: item.provider, snapshot: snapshot, conversation: conversation)
        }
      }
      GridRow {
        fieldLabel("Updated")
        Text("\(absoluteTime(item.updatedAt)) · \(relativeTime(item.updatedAt, now: model.now))")
      }
      GridRow {
        fieldLabel("Labels")
        labelsRow
      }
      if !item.upstreamLabels.isEmpty {
        GridRow {
          fieldLabel("Upstream")
            .help("Labels the target carries at \(item.provider.displayName)")
          Text(item.upstreamLabels.joined(separator: ", "))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
    }
    .font(.app(.callout))
  }

  /// The thread's labels as pills, and the menu that edits them by hand:
  /// one toggle per label (checked when every member carries it), applied
  /// to every member, plus a way back to what the rules decide.
  private var labelsRow: some View {
    let carried = carriedLabels(model.userLabels, on: thread.items)
    return HStack(spacing: 6) {
      ForEach(carried) { label in
        LabelCapsule(label: label)
      }
      if carried.isEmpty {
        Text("None")
          .foregroundStyle(.tertiary)
      }
      Menu {
        LabelToggles(model: model, items: thread.items)
        Divider()
        Button("Reset to Rules") {
          for member in thread.items {
            for label in model.userLabels {
              model.setItemLabel(member.id, label.id, on: nil)
            }
          }
        }
        Button("Edit Labels…") {
          model.openSettings?()
        }
      } label: {
        Image(systemName: "plus")
          .font(.app(.badge, weight: .semibold))
      }
      .menuIndicator(.hidden)
      .controlSize(.small)
      .fixedSize()
      .help("Add or remove labels by hand")
    }
  }

  private func fieldLabel(_ text: String) -> some View {
    Text(text)
      .foregroundStyle(.secondary)
      .gridColumnAlignment(.leading)
  }
}

/// People the facts name, each by face and login, on one line.
private struct PeopleLine: View {
  let logins: [String]
  let provider: ProviderId
  /// Where a face is found: the snapshot names the pictures of everyone
  /// it lists, and the conversation those of whoever wrote in it.
  let snapshot: TargetSnapshot?
  let conversation: TargetConversation?

  @Environment(\.searchHighlightTerms) private var highlightTerms

  var body: some View {
    HStack(spacing: 10) {
      ForEach(logins, id: \.self) { login in
        HStack(spacing: 5) {
          PersonAvatar(
            login: login,
            avatarUrl: snapshot?.avatarUrl(of: login) ?? conversation?.avatarUrl(of: login),
            provider: provider,
            size: 16
          )
          Text(highlighted(login, terms: highlightTerms))
            .lineLimit(1)
            .textSelection(.enabled)
        }
      }
    }
  }
}

/// One thread member as a message card, drawn like the timeline's: who,
/// why it arrived, when — then the comment it points at, named with a way
/// down to it, or the notification's own body. Clicking selects the message
/// (accent outline) and the toolbar's mark-read/open narrow to it.
private struct MessageCard: View {
  let member: InboxItem
  /// The comment it points at, while the stored conversation holds it.
  let comment: DetailComment?
  /// The author's picture, when the conversation names one.
  let avatarUrl: String?
  let selected: Bool
  let now: Date
  let onSelect: () -> Void
  let onJump: (String) -> Void

  @State private var hovered = false

  var body: some View {
    let providerSpec = spec(for: member.provider)
    let author = comment?.author ?? member.author
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        if !member.read {
          UnreadDot()
            .help("Unread")
        }
        PersonAvatar(login: author, avatarUrl: avatarUrl, provider: member.provider, size: 24)
        Byline(
          name: author,
          reason: providerSpec.reasonLabel(member.reason),
          reasonTint: member.isMention ? Color.accentColor : nil,
          date: member.updatedAt, now: now
        )
      }
      if let comment {
        Text(excerpt(of: comment.body))
          .font(.app(.body))
          .foregroundStyle(.secondary)
          .lineLimit(3)
        Button("Show in Conversation") {
          onJump(comment.id)
        }
        .buttonStyle(.link)
        .font(.app(.callout))
      } else if let bodyView = providerSpec.bodyView(for: member) {
        bodyView
      }
    }
    .conversationCard(
      outline: selected ? AnyShapeStyle(Color.accentColor) : (hovered ? AnyShapeStyle(.tertiary) : nil),
      lineWidth: selected ? 2 : 1
    )
    .contentShape(RoundedRectangle(cornerRadius: 10))
    .onHover { inside in
      hovered = inside
    }
    // A simultaneous gesture, not onTapGesture: clicks landing on the card's
    // selectable text are consumed by text selection and would never reach a
    // plain tap gesture on the container.
    .simultaneousGesture(TapGesture().onEnded(onSelect))
    .help("Select this notification — the toolbar actions apply to just it")
  }
}
