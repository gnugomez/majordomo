// The selection's preview in the main window: everything AppModel knows
// about the selected thread — where its target stands now, who it is
// assigned to and who is still asked to review it, and the buttons that
// open it or mark it read — then its target in full: who opened it
// and what it says, the latest comments and reviews, as the background
// refresh stored it, read from disk, as a timeline of cards on a gray
// pane. A target the refresh hasn't reached yet is asked for ahead of it.
// A multi-member thread stacks its messages as cards of the same kind
// under the shared header. The images the bodies show come through the
// item's own account (AppModel.bodyImages), handed down in the environment.
// Beside the list or a board it reads as one column, top to bottom; under
// a board, as wide as the board and a third as tall, the facts and the
// buttons stand beside what the notifications say and the conversation,
// each side scrolling on its own.

import SwiftUI

struct PreviewView: View {
  let model: AppModel
  let thread: InboxThread?
  /// Where the preview stands, which decides its columns.
  var placement: PreviewPlacement = .trailing

  /// The comment just jumped to, lit up for a moment.
  @State private var flashedCommentId: String?
  /// Where the pane is scrolled: to a comment jumped to, or back to the
  /// title for another thread. Side by side, where the conversation is.
  @State private var scrollPosition = ScrollPosition()
  /// Where the facts are scrolled, beside the conversation.
  @State private var factsPosition = ScrollPosition()
  /// Where the comments the notifications point at sit in the pane.
  @State private var commentOffsets = CommentOffsets()

  var body: some View {
    if let thread {
      let item = thread.lead
      columns(thread)
        // Another thread reads from its title down.
        .onChange(of: thread.id) {
          commentOffsets.forget()
          scrollPosition.scrollTo(edge: .top)
          factsPosition.scrollTo(edge: .top)
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
        .environment(\.bodyImages, model.bodyImages(for: item))
    } else {
      PaneEmptyState(
        symbol: "tray",
        title: "Nothing selected",
        caption: "Select an item from the list to see its details."
      )
    }
  }

  /// The facts over the notifications and the conversation in one scroll
  /// view, or the facts beside the other two, narrower, in a scroll view
  /// each.
  @ViewBuilder
  private func columns(_ thread: InboxThread) -> some View {
    let load = model.conversation(for: thread.lead)
    let conversation = loadedConversation(load)
    switch placement {
    case .trailing:
      ScrollView {
        column(thread) {
          facts(thread, conversation: conversation)
          messages(thread, conversation: conversation, ruled: true)
          conversationPart(thread, load: load, conversation: conversation, ruled: true)
        }
        .coordinateSpace(.named(CommentOffsets.space))
      }
      .scrollPosition($scrollPosition)
    case .bottom:
      HStack(spacing: 0) {
        ScrollView {
          column(thread) {
            facts(thread, conversation: conversation)
          }
        }
        .scrollPosition($factsPosition)
        .frame(minWidth: 260, maxWidth: 380)
        Divider()
        ScrollView {
          column(thread) {
            messages(thread, conversation: conversation, ruled: false)
            conversationPart(
              thread, load: load, conversation: conversation,
              ruled: showsMessages(thread, conversation: conversation)
            )
          }
          .coordinateSpace(.named(CommentOffsets.space))
        }
        .scrollPosition($scrollPosition)
      }
    }
  }

  /// One column's content, laid out as the preview's.
  private func column(_ thread: InboxThread, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      content()
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    // Another thread's content replaces this one rather than growing
    // out of it: kept, its pieces would morph from one thread's layout
    // into the next's.
    .id(thread.id)
  }

  /// The header and the buttons.
  @ViewBuilder
  private func facts(_ thread: InboxThread, conversation: TargetConversation?) -> some View {
    PreviewHeader(
      model: model,
      thread: thread,
      status: model.targetStatus(for: thread),
      snapshot: snapshot(of: thread.lead),
      conversation: conversation
    )
    SelectionActions(model: model, threads: [actionTarget(in: thread)])
  }

  /// What the notifications say: a thread's messages as cards, the comment
  /// one notification points at, named with a way down to it, or until
  /// the target is in, the notification's own excerpt — set off from the
  /// facts above it when `ruled`.
  @ViewBuilder
  private func messages(_ thread: InboxThread, conversation: TargetConversation?, ruled: Bool) -> some View {
    let item = thread.lead
    let providerSpec = spec(for: item.provider)
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
      if ruled {
        Divider()
      }
      bodyView
    }
  }

  /// Whether the notifications show as more than the excerpt, which gives
  /// way to the conversation: a thread's messages, or the comment one
  /// notification points at.
  private func showsMessages(_ thread: InboxThread, conversation: TargetConversation?) -> Bool {
    let item = thread.lead
    return thread.items.count > 1
      || triggerComment(of: item, in: conversation, providerSpec: spec(for: item.provider)) != nil
  }

  /// How the conversation's load stands, then the conversation — set off
  /// from what is above it when `ruled`.
  @ViewBuilder
  private func conversationPart(
    _ thread: InboxThread, load: AppModel.ConversationLoad?, conversation: TargetConversation?, ruled: Bool
  ) -> some View {
    ConversationStatusRow(load: load)
    if let conversation {
      if ruled {
        Divider()
      }
      ConversationTimeline(
        conversation: conversation, item: thread.lead,
        triggers: triggers(of: thread, providerSpec: spec(for: thread.lead.provider)),
        flashedId: flashedCommentId, now: model.now,
        placed: commentOffsets.note
      )
    }
  }

  /// What the preview's buttons act on: the message picked in the thread,
  /// or the whole thread.
  private func actionTarget(in thread: InboxThread) -> InboxThread {
    thread.items.first { $0.id == model.selectedMemberId }.map { InboxThread(id: $0.id, items: [$0]) } ?? thread
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
/// review, checks, merging, and workflow status stand under them; then
/// the facts. The target reads as it stands now: a pull request merged
/// since its notification came reads merged.
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
        // Every line it wraps to: under a board, the row is otherwise held
        // to one line and the title cut short.
        .fixedSize(horizontal: false, vertical: true)
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
      if let due = snapshot?.dueDate, let day = DueDate.parse(due) {
        GridRow {
          fieldLabel("Due")
          Text(dueText(day, words: DueDate.words(for: due, now: model.now)))
        }
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
          model.openSettings?("Labels")
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
/// The day in full, and where it stands when that is today, tomorrow, or
/// gone by.
private func dueText(_ day: Date, words: [String]) -> String {
  let date = day.formatted(date: .long, time: .omitted)
  guard let standing = ["overdue", "today", "tomorrow"].first(where: words.contains) else {
    return date
  }
  return "\(date) · \(standing)"
}

private struct PeopleLine: View {
  let logins: [String]
  let provider: ProviderId
  /// Where a face is found: the snapshot names the pictures of everyone
  /// it lists, and the conversation those of whoever wrote in it.
  let snapshot: TargetSnapshot?
  let conversation: TargetConversation?

  @Environment(\.searchHighlightTerms) private var highlightTerms

  var body: some View {
    // Wrapping, each person a piece: a target assigned to a crowd would
    // run past the pane's edge on one line.
    FlowLayout(spacing: 10, lineSpacing: 4) {
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
/// (accent outline), and the preview's Open and Mark as Read narrow to it.
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
    .help("Select this notification — Open and Mark as Read apply to just it")
  }
}
