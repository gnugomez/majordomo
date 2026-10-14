// Middle pane of the main window: the selected category's threads, newest
// activity first — selecting feeds the preview, double-click or ⏎ opens the
// browser.

import SwiftUI

/// What the spotlight's row measures when it has nothing to show. The
/// table refuses a row of no height at all, so it rests at a hairline.
private let spotlightRestHeight: CGFloat = 1

struct InboxListView: View {
  let model: AppModel
  let threads: [InboxThread]
  let categoryId: String

  /// Threads unfolded into their member rows (the count button toggles).
  @State private var expandedThreadIds: Set<String> = []
  /// Which pinned label the spotlight shows, and the top item its light
  /// has already greeted. They live here because the spotlight's row is
  /// remade whenever its shape changes (see `spotlightKey`), which would
  /// reset anything the box held itself.
  @State private var spotlightIndex = 0
  @State private var spotlightGreeted = ""

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
      } else if model.unreadOnly {
        EmptyStateView(
          symbol: "checkmark.circle",
          title: "You're all caught up",
          caption: "Nothing here is unread. Turn off Unread Only in the toolbar's filter to see the rest."
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
      ScrollViewReader { scroll in
        List(selection: Binding(
          get: { model.selectedThreadIds },
          set: { model.selectedThreadIds = $0 }
        )) {
          // The spotlight rides in a row of the list, so it scrolls away
          // with the notifications. A list row is measured once, when it
          // arrives, and keeps that height however its content changes
          // afterwards — so the row is given an identity that spells out
          // everything deciding how tall the box draws, and the table
          // replaces the row, measuring the new one, whenever that
          // changes. The row is always in the list, resting at a hairline
          // when there is nothing to spotlight: a box arriving is then a
          // replacement too, and a replaced row is the one case the table
          // measures right — a plain insertion draws as a header strip
          // with the rows cut off.
          ForEach([spotlightKey(pinned)], id: \.self) { key in
            if key.isEmpty {
              // Nothing to spotlight. A row of no height at all is refused
              // outright, so it rests as thin as the table will take.
              Color.clear
                .frame(height: spotlightRestHeight)
                .listRowInsets(EdgeInsets())
            } else {
              PinnedLabelBox(
                model: model,
                boxes: pinned,
                index: $spotlightIndex,
                greeted: $spotlightGreeted
              )
              .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 2, trailing: 10))
            }
          }
          // The spotlight is not one of the inbox's rows: it takes no
          // selection, and no separator draws around it.
          .listRowSeparator(.hidden)
          .selectionDisabled()
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
        // The standard floor under a row would hold the resting spotlight
        // open as a band of blank space over the first notification. The
        // inbox's own rows stand taller than any minimum, so lowering it
        // costs them nothing.
        .environment(\.defaultMinListRowHeight, spotlightRestHeight)
        // That floor is also the table's row height, which sets how far a
        // wheel notch scrolls; this keeps the notch at a row.
        .wheelScrollsByRow()
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
        // Picking a notification anywhere — the spotlight, the tray, a
        // banner — brings it into view here. A nil anchor scrolls the
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

  /// The spotlight's row identity: everything that decides how tall the
  /// box draws — which label is showing, how many rows it has, and which
  /// of them carry a summary line. The empty string means there is nothing
  /// to spotlight.
  private func spotlightKey(_ pinned: [PinnedBox]) -> String {
    guard !pinned.isEmpty else {
      return ""
    }
    let box = pinned[min(spotlightIndex, pinned.count - 1)]
    let rows = box.threads.map { thread in
      "\(thread.id)#\(thread.lead.summary?.isEmpty == false ? 1 : 0)"
    }
    return "\(box.id)|\(pinned.count)|\(box.unread)|" + rows.joined(separator: ",")
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
