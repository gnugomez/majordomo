// Middle pane of the main window, ported from
// src/ui/main-window/InboxList.tsx: the selected category's items, newest
// first — selecting feeds the preview, double-click or ⏎ opens the browser.

import SwiftUI

struct InboxListView: View {
  let model: AppModel
  let items: [InboxItem]
  let categoryId: String

  var body: some View {
    // Existing items always show, even with no account connected — the
    // collection is the app's own, and it outlives a disconnect (or a token
    // that failed to decrypt on this launch).
    if items.isEmpty {
      if !model.hasAccounts {
        EmptyStateView(
          symbol: "tray",
          title: "No accounts connected",
          caption: "Add an account in Settings to see your inbox here."
        )
      } else if categoryId == recentCategory.id {
        EmptyStateView(
          symbol: "checkmark.circle",
          title: "You're all caught up",
          caption: "Nothing needs your attention right now."
        )
      } else {
        EmptyStateView(
          symbol: "tray",
          title: "Nothing here",
          caption: "Pick another category in the sidebar to see the rest of your inbox."
        )
      }
    } else {
      List(selection: Binding(
        get: { model.selectedItemIds },
        set: { model.selectedItemIds = $0 }
      )) {
        ForEach(items) { item in
          ItemRowView(item: item, now: model.now, selected: model.selectedItemIds.contains(item.id))
            .tag(item.id)
        }
      }
      .listStyle(.inset)
      // Selection stays the list's own (a tap gesture on row content would
      // swallow the clicks NSTableView needs), so ⇧/⌘-click and ⌘A come for
      // free; double-click and the Mail-style context menu arrive through
      // the selection-typed API.
      .contextMenu(forSelectionType: String.self) { ids in
        Button(ids.count > 1 ? "Open \(ids.count) in Browser" : "Open in Browser") {
          for id in ids {
            model.openItem(id)
          }
        }
        Button("Mark as Read") {
          model.markRead(ids)
        }
        .disabled(!items.contains { ids.contains($0.id) && !$0.read })
      } primaryAction: { ids in
        for id in ids {
          model.openItem(id)
        }
      }
      .onKeyPress(.return) {
        let ids = model.selectedItemIds.filter { id in items.contains { $0.id == id } }
        guard !ids.isEmpty else {
          return .ignored
        }
        for id in ids {
          model.openItem(id)
        }
        return .handled
      }
    }
  }
}
