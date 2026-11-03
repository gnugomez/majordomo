// Right pane of the main window: everything AppModel knows about the
// selected thread, then its target in full — who opened it and what it
// says, the latest comments and reviews — as the background refresh stored
// it, read from disk, as a timeline of cards on a gray pane. A target the
// refresh hasn't reached yet is asked for ahead of it. A multi-member
// thread stacks its messages as cards of the same kind under the shared
// header. The images the bodies show come through the item's own account
// (AppModel.bodyImages), handed down in the environment.

import SwiftUI

struct PreviewView: View {
  let model: AppModel
  let thread: InboxThread?

  @Environment(\.searchHighlightTerms) private var highlightTerms
  /// The message card under the pointer, for the hover affordance.
  @State private var hoveredMemberId: String?
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
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          header(thread, providerSpec: providerSpec)

          let load = model.conversation(for: item)
          let conversation = loadedConversation(load)
          if thread.items.count > 1 {
            ForEach(thread.items) { member in
              messageCard(member, providerSpec: providerSpec, conversation: conversation)
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
      }
      .scrollPosition($scrollPosition)
      // Another thread reads from its title down.
      .onChange(of: thread.id) {
        commentOffsets.forget()
        scrollPosition.scrollTo(edge: .top)
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
      .background(ConversationShades.pane)
      .environment(\.bodyImages, model.bodyImages(for: item))
    } else {
      // Scroll-backed like the populated branch: plain (non-scrolling)
      // content makes the toolbar draw a hard edge line over this pane.
      ScrollView {
        EmptyStateView(
          symbol: "tray",
          title: "Nothing selected",
          caption: "Select an item from the list to see its details."
        )
        .containerRelativeFrame(.vertical)
      }
    }
  }

  /// The title, the state and reason capsules, and the facts.
  @ViewBuilder
  private func header(_ thread: InboxThread, providerSpec: any ProviderSpec) -> some View {
    let item = thread.lead
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      GlyphImage(glyph: providerSpec.glyph(for: item), size: 16)
        .foregroundStyle(providerSpec.color(for: item))
      Text(highlighted(item.title, terms: highlightTerms))
        .font(.system(size: 17, weight: .semibold))
        .textSelection(.enabled)
    }

    HStack(spacing: 6) {
      if let capsule = providerSpec.stateCapsule(for: item) {
        CapsuleTag(text: capsule.label, tint: capsule.color)
      }
      if thread.items.count == 1 {
        // A single notification's reason belongs to the header; a
        // thread's reasons ride on its messages below.
        CapsuleTag(
          text: providerSpec.reasonLabel(item.reason),
          tint: item.isMention ? Color.accentColor : nil
        )
      }
      if !thread.read {
        CapsuleTag(text: "unread", tint: Color.accentColor)
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
      GridRow {
        fieldLabel("Updated")
        Text("\(absoluteTime(item.updatedAt)) · \(relativeTime(item.updatedAt, now: model.now))")
      }
      GridRow {
        fieldLabel("Labels")
        labelsRow(thread)
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
    .font(.system(size: 12))
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

  /// One thread member as a message card, drawn like the timeline's: who,
  /// why it arrived, when — then the comment it points at, named with a
  /// way down to it, or the notification's own body. Clicking selects the
  /// message (accent outline) and the toolbar's mark-read/open narrow to it.
  private func messageCard(
    _ member: InboxItem, providerSpec: any ProviderSpec, conversation: TargetConversation?
  ) -> some View {
    let selected = model.selectedMemberId == member.id
    let comment = triggerComment(of: member, in: conversation, providerSpec: providerSpec)
    let author = comment?.author ?? member.author
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        if !member.read {
          Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
            .help("Unread")
        }
        PersonAvatar(
          login: author,
          avatarUrl: comment?.avatarUrl ?? author.flatMap { conversation?.avatarUrl(of: $0) },
          provider: member.provider, size: 24
        )
        if let author {
          Text(highlighted(author, terms: highlightTerms))
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
        }
        CapsuleTag(
          text: providerSpec.reasonLabel(member.reason),
          tint: member.isMention ? Color.accentColor : nil
        )
        Spacer(minLength: 4)
        EntryTime(date: member.updatedAt, now: model.now)
      }
      if let comment {
        Text(excerpt(of: comment.body))
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .lineLimit(3)
        Button("Show in Conversation") {
          jump(to: comment.id)
        }
        .buttonStyle(.link)
        .font(.system(size: 12))
      } else if let bodyView = providerSpec.bodyView(for: member) {
        bodyView
      }
    }
    .conversationCard(
      outline: selected
        ? AnyShapeStyle(Color.accentColor)
        : (hoveredMemberId == member.id ? AnyShapeStyle(.tertiary) : nil),
      lineWidth: selected ? 2 : 1
    )
    .contentShape(RoundedRectangle(cornerRadius: 10))
    .onHover { inside in
      hoveredMemberId = inside ? member.id : nil
    }
    // A simultaneous gesture, not onTapGesture: clicks landing on the card's
    // selectable text are consumed by text selection and would never reach a
    // plain tap gesture on the container.
    .simultaneousGesture(TapGesture().onEnded {
      model.selectedMemberId = member.id
    })
    .help("Select this notification — the toolbar actions apply to just it")
  }

  /// The thread's labels as pills, and the menu that edits them by hand:
  /// one toggle per label (checked when every member carries it), applied
  /// to every member, plus a way back to what the rules decide. Tags only:
  /// an inbox is never shown here nor applied by hand.
  private func labelsRow(_ thread: InboxThread) -> some View {
    let carried = model.userLabels.filter { label in thread.items.contains { $0.labels.contains(label.id) } }
    return HStack(spacing: 6) {
      ForEach(carried) { label in
        LabelCapsule(label: label)
      }
      if carried.isEmpty {
        Text("None")
          .foregroundStyle(.tertiary)
      }
      Menu {
        ForEach(model.userLabels) { label in
          let on = thread.items.allSatisfy { $0.labels.contains(label.id) }
          Toggle(isOn: Binding(
            get: { on },
            set: { wanted in
              for member in thread.items {
                model.setItemLabel(member.id, label.id, on: wanted)
              }
            }
          )) {
            Label(label.name, systemImage: label.symbol)
          }
        }
        if model.userLabels.isEmpty {
          Text("No labels yet")
        }
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
          .font(.system(size: 10, weight: .semibold))
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
