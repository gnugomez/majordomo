// Middle pane of the main window: the selected category's threads, unread
// first — selecting feeds the preview, double-click or ⏎ opens the browser.

import SwiftUI

struct InboxListView: View {
  let model: AppModel
  let threads: [InboxThread]
  let categoryId: String

  /// Threads unfolded into their member rows (the count button toggles).
  @State private var expandedThreadIds: Set<String> = []

  var body: some View {
    // Items keep showing while their account is connected, even when it
    // can't sync right now (a token that failed to decrypt on this launch)
    // — the collection is the app's own, not a mirror of the last fetch.
    if threads.isEmpty {
      if !model.hasAccounts {
        EmptyStateView(
          symbol: "tray",
          title: "No accounts connected",
          caption: "Add an account in Settings to see your inbox here."
        )
      } else if !model.searchText.isEmpty {
        EmptyStateView(
          symbol: "magnifyingglass",
          title: "No results",
          caption: "Nothing here matches “\(model.searchText)”."
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
        get: { model.selectedThreadIds },
        set: { model.selectedThreadIds = $0 }
      )) {
        ForEach(threads) { thread in
          ItemRowView(
            thread: thread,
            now: model.now,
            selected: model.selectedThreadIds.contains(thread.id),
            expanded: expandedThreadIds.contains(thread.id)
          ) {
            toggleExpanded(thread.id)
          }
          .tag(thread.id)
          // An unfolded thread: its members as their own selectable rows,
          // right beneath the summary.
          if expandedThreadIds.contains(thread.id) {
            ForEach(thread.items) { member in
              MemberRowView(member: member, now: model.now, selected: model.selectedThreadIds.contains(member.id))
                .tag(member.id)
            }
          }
        }
      }
      .listStyle(.inset)
      // Selection stays the list's own (a tap gesture on row content would
      // swallow the clicks NSTableView needs), so ⇧/⌘-click and ⌘A come for
      // free; double-click and the context menu arrive through the
      // selection-typed API.
      .contextMenu(forSelectionType: String.self) { ids in
        let picked = resolveSelection(in: threads, ids: ids)
        Button(picked.count > 1 ? "Open \(picked.count) in Browser" : "Open in Browser") {
          open(picked)
        }
        Button("Mark as Read") {
          model.markRead(Set(picked.flatMap(\.itemIds)))
        }
        .disabled(!picked.contains { !$0.read })
      } primaryAction: { ids in
        open(resolveSelection(in: threads, ids: ids))
      }
      .onKeyPress(.return) {
        let picked = resolveSelection(in: threads, ids: model.selectedThreadIds)
        guard !picked.isEmpty else {
          return .ignored
        }
        open(picked)
        return .handled
      }
    }
  }

  private func open(_ picked: [InboxThread]) {
    for thread in picked {
      model.openThread(thread.itemIds)
    }
  }

  private func toggleExpanded(_ id: String) {
    if expandedThreadIds.contains(id) {
      expandedThreadIds.remove(id)
    } else {
      expandedThreadIds.insert(id)
    }
  }
}
