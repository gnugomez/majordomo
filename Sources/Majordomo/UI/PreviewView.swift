// Right pane of the main window: everything AppModel already knows about
// the selected thread. Deliberately no provider fetches — bodies and
// comments need extra token scopes, so the browser is one click away
// instead. A multi-member thread stacks its messages as cards under the
// shared header.

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
            Image(systemName: providerSpec.symbol(for: item))
              .font(.system(size: 16, weight: .medium))
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
          }
          .font(.system(size: 12))

          if thread.items.count > 1 {
            ForEach(thread.items) { member in
              messageCard(member, providerSpec: providerSpec)
            }
          } else if let bodyView = providerSpec.bodyView(for: item) {
            Divider()
            bodyView
          }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
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

  private func fieldLabel(_ text: String) -> some View {
    Text(text)
      .foregroundStyle(.secondary)
      .gridColumnAlignment(.leading)
  }
}
