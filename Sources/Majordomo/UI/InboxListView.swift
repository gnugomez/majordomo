// Middle pane of the main window: the selected category's threads, newest
// activity first — selecting feeds the preview, double-click or ⏎ opens the
// browser.

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
          caption: "Nothing here matches \u{201C}\(model.searchText)\u{201D}."
        )
      } else if let window = model.activityWindow {
        EmptyStateView(
          symbol: "calendar",
          title: "Nothing in the \(window.label.lowercased())",
          caption: "Widen the date filter in the toolbar to see the rest of your inbox."
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
      let pinned = categoryId == recentCategory.id ? pinnedBoxes(model: model, threads: threads) : []
      // The spotlight sits above the list rather than in it. A SwiftUI List
      // row is measured once, when it arrives, and keeps that height — and
      // this box arrives, grows and shrinks long after the list was built,
      // as the model answers and as notifications are read. Every way of
      // making a row re-measure was tried and none held: fixedSize, an
      // explicit height (the table clamps it anyway), a section header (and
      // it brings a separator the design doesn't want), keying the list,
      // keying the row, nudging the width, and AppKit's own
      // noteHeightOfRows, which SwiftUI answers out of its own cache. Above
      // the list the box measures itself every time and the list takes the
      // room that is left; the cost is that it doesn't scroll away.
      VStack(spacing: 0) {
        if !pinned.isEmpty {
          PinnedLabelBox(model: model, boxes: pinned)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
        ScrollViewReader { scroll in
          List(selection: Binding(
            get: { model.selectedThreadIds },
            set: { model.selectedThreadIds = $0 }
          )) {
            ForEach(threads) { thread in
              ItemRowView(
                thread: thread,
                now: model.now,
                labels: labels(on: thread.items),
                layout: model.rowLayout,
                selected: model.selectedThreadIds.contains(thread.id),
                expanded: expandedThreadIds.contains(thread.id)
              ) {
                toggleExpanded(thread.id)
              }
              .tag(thread.id)
              // An unfolded thread: its members as their own selectable
              // rows, right beneath the summary.
              if expandedThreadIds.contains(thread.id) {
                ForEach(thread.items) { member in
                  MemberRowView(
                    member: member,
                    now: model.now,
                    layout: model.rowLayout,
                    selected: model.selectedThreadIds.contains(member.id)
                  )
                  .tag(member.id)
                }
              }
            }
          }
          .listStyle(.inset)
          // Arrows walk the inbox from the first keystroke; without this the
          // sidebar holds the keyboard until a row is clicked.
          .claimsInitialKeyboardFocus()
          // Selection stays the list's own (a tap gesture on row content
          // would swallow the clicks NSTableView needs), so ⇧/⌘-click and
          // ⌘A come for free; double-click and the context menu arrive
          // through the selection-typed API.
          .contextMenu(forSelectionType: String.self) { ids in
            let picked = resolveSelection(in: threads, ids: ids)
            Button(picked.count > 1 ? "Open \(picked.count) in Browser" : "Open in Browser") {
              open(picked)
            }
            Button("Mark as Read") {
              model.markRead(Set(picked.flatMap(\.itemIds)))
            }
            .disabled(!picked.contains { !$0.read })
            labelsMenu(for: picked.flatMap(\.items))
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
          // Picking a notification anywhere — the spotlight above, the tray,
          // a banner — brings it into view here. A nil anchor scrolls the
          // least it can, so one already on screen stays where it is.
          .onChange(of: model.selectedThreadIds) { _, ids in
            guard ids.count == 1, let id = ids.first else {
              return
            }
            withAnimation(.snappy(duration: 0.2)) {
              scroll.scrollTo(id, anchor: nil)
            }
          }
        }
      }
    }
  }

  /// The labels any of these items carries — tags only, never an inbox.
  private func labels(on items: [InboxItem]) -> [InboxLabel] {
    model.userLabels.filter { label in items.contains { $0.labels.contains(label.id) } }
  }

  /// "Labels ▸": one toggle per label, applied to every selected item — a
  /// checkmark means every one of them carries it.
  private func labelsMenu(for items: [InboxItem]) -> some View {
    Menu("Labels") {
      ForEach(model.userLabels) { label in
        let on = !items.isEmpty && items.allSatisfy { $0.labels.contains(label.id) }
        Toggle(isOn: Binding(
          get: { on },
          set: { wanted in
            for item in items {
              model.setItemLabel(item.id, label.id, on: wanted)
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
      Button("Edit Labels…") {
        model.openSettings?()
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
