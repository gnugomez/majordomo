// Right pane of the main window: everything AppModel knows about the
// selected thread, then its target in full — the comment that raised the
// notification, the description, the latest comments — as the background
// refresh stored it, read from disk. A target the refresh hasn't reached
// yet is asked for ahead of it. A multi-member thread stacks its messages
// as cards under the shared header.

import SwiftUI

/// The conversation shades: a quiet gray pane with white message cards in
/// light mode, a near-black pane with lifted gray cards in dark mode.
/// Neither is a plain system color — windowBackgroundColor sits LIGHTER
/// than textBackgroundColor in dark mode, which would invert the scheme.
private let conversationPane = Color(nsColor: NSColor(name: nil) { appearance in
  appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    ? NSColor(white: 0.12, alpha: 1)
    : NSColor(white: 0.95, alpha: 1)
})
private let messageCardBackground = Color(nsColor: NSColor(name: nil) { appearance in
  appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    ? NSColor(white: 0.2, alpha: 1)
    : .white
})

struct PreviewView: View {
  let model: AppModel
  let thread: InboxThread?

  @Environment(\.searchHighlightTerms) private var highlightTerms
  /// The message card under the pointer, for the hover affordance.
  @State private var hoveredMemberId: String?

  var body: some View {
    if let thread {
      let item = thread.lead
      let providerSpec = spec(for: item.provider)
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
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

          let load = model.conversation(for: item)
          let conversation = loadedConversation(load)
          // The comment the notification points at, when the stored
          // conversation still holds it.
          let trigger = providerSpec.triggerCommentId(for: item).flatMap { id in
            conversation?.comments.first { $0.id == id }
          }
          if thread.items.count > 1 {
            ForEach(thread.items) { member in
              messageCard(member, providerSpec: providerSpec)
            }
          } else if let trigger {
            TriggerCard(comment: trigger, now: model.now)
          } else if conversation == nil, let bodyView = providerSpec.bodyView(for: item) {
            // The notification's own excerpt stands in until the target
            // is in, or when it can't be.
            Divider()
            bodyView
          }
          ConversationStatusRow(load: load)
          if let conversation {
            targetSections(conversation, triggerId: trigger?.id, of: thread, providerSpec: providerSpec)
          }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
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
      // The pane goes slightly gray so the white message cards read as
      // cards. Single notifications keep the plain page look — there's no
      // card to set off.
      .background(
        thread.items.count > 1 ? AnyShapeStyle(conversationPane) : AnyShapeStyle(.clear)
      )
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

  /// The target's description and latest comments, under what the
  /// notification itself says.
  @ViewBuilder
  private func targetSections(
    _ conversation: TargetConversation, triggerId: String?, of thread: InboxThread, providerSpec: any ProviderSpec
  ) -> some View {
    let item = thread.lead
    if conversation.description != nil || !conversation.comments.isEmpty {
      Divider()
    }
    if let description = conversation.description {
      // A fresh look at another target starts collapsed again.
      DescriptionSection(text: description)
        .id(item.id)
    }
    if !conversation.comments.isEmpty {
      ConversationSection(
        comments: conversation.comments,
        // Only a single notification's card shows the comment it came from.
        triggerId: thread.items.count == 1 ? triggerId : nil,
        reason: providerSpec.reasonLabel(item.reason),
        commentCount: conversation.commentCount,
        providerName: item.provider.displayName,
        url: URL(string: item.url),
        now: model.now
      )
    }
  }

  private func loadedConversation(_ load: AppModel.ConversationLoad?) -> TargetConversation? {
    if case .loaded(let conversation) = load {
      return conversation
    }
    return nil
  }

  /// One thread member as a message card: why it arrived, from whom, when
  /// — then its body. Clicking selects the message (accent outline) and the
  /// toolbar's mark-read/open narrow to it.
  private func messageCard(_ member: InboxItem, providerSpec: any ProviderSpec) -> some View {
    let selected = model.selectedMemberId == member.id
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        if !member.read {
          Circle()
            .fill(Color.accentColor)
            .frame(width: 6, height: 6)
        }
        CapsuleTag(
          text: providerSpec.reasonLabel(member.reason),
          tint: member.isMention ? Color.accentColor : nil
        )
        if let author = member.author {
          Text(highlighted(author, terms: highlightTerms))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        Text(relativeTime(member.updatedAt, now: model.now))
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
      }
      if let bodyView = providerSpec.bodyView(for: member) {
        bodyView
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(messageCardBackground, in: RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(
          selected
            ? AnyShapeStyle(Color.accentColor)
            : (hoveredMemberId == member.id ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary)),
          lineWidth: selected ? 2 : 1
        )
    )
    .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
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
