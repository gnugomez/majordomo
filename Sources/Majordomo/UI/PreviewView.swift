// Right pane of the main window: everything AppModel already knows about
// the selected item. Deliberately no provider fetches — bodies and
// comments need extra token scopes, so the browser is one click away
// instead.

import SwiftUI

struct PreviewView: View {
  let model: AppModel
  let item: InboxItem?

  var body: some View {
    if let item {
      let providerSpec = spec(for: item.provider)
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: providerSpec.symbol(for: item))
              .font(.system(size: 16, weight: .medium))
              .foregroundStyle(providerSpec.color(for: item))
            Text(item.title)
              .font(.system(size: 17, weight: .semibold))
              .textSelection(.enabled)
          }

          HStack(spacing: 6) {
            if let capsule = providerSpec.stateCapsule(for: item) {
              CapsuleTag(text: capsule.label, tint: capsule.color)
            }
            CapsuleTag(
              text: providerSpec.reasonLabel(item.reason),
              tint: item.isMention ? Color.accentColor : nil
            )
            if !item.read {
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
              Text(item.repo).textSelection(.enabled)
            }
            if let author = item.author {
              GridRow {
                fieldLabel("Author")
                Text(author).textSelection(.enabled)
              }
            }
            GridRow {
              fieldLabel("Updated")
              Text("\(absoluteTime(item.updatedAt)) · \(relativeTime(item.updatedAt, now: model.now))")
            }
          }
          .font(.system(size: 12))

          if let bodyView = providerSpec.bodyView(for: item) {
            Divider()
            bodyView
          }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
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

  private func fieldLabel(_ text: String) -> some View {
    Text(text)
      .foregroundStyle(.secondary)
      .gridColumnAlignment(.leading)
  }
}
