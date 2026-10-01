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
  /// True for the one frame that nudges the list's width, so the table
  /// measures its rows again.
  @State private var remeasuring = false

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
      // What the spotlight takes up — down to whether each row carries a
      // summary, since that is a line of height and the summaries arrive
      // on their own sweep, long after the row they belong to. Counting
      // only the rows left the box a line short of its content.
      let spotlightShape = pinned
        .map { box in
          let rows = box.threads
            .map { "\($0.id)\($0.lead.summary == nil ? "" : "+")" }
            .joined(separator: ",")
          return "\(box.id):\(rows)"
        }
        .joined(separator: "|")
      List(selection: Binding(
        get: { model.selectedThreadIds },
        set: { model.selectedThreadIds = $0 }
      )) {
        // The pinned labels ride at the top of the catch-all only, inside
        // the list so they scroll away with everything else. Unselectable:
        // the arrows and ⌘A belong to the notifications, not to a spotlight.
        if !pinned.isEmpty {
          PinnedLabelBox(model: model, boxes: pinned)
            .listRowSeparator(.hidden)
            // The half point that makes the table measure this row again
            // rides on the row's own insets, not on the list's width: one
            // row to re-measure instead of the column.
            .listRowInsets(
              EdgeInsets(top: 6, leading: 6, bottom: 10, trailing: remeasuring ? 6.5 : 6)
            )
            .selectionDisabled()
        }
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
          // An unfolded thread: its members as their own selectable rows,
          // right beneath the summary.
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
      .onChange(of: spotlightShape) {
        // Nothing to measure when there is no box, and never from inside
        // the pass that noticed the change: setting this synchronously
        // re-enters the table's own layout (AppKit says so out loud), and
        // the pass it forces costs as much again as the one it interrupts.
        guard !spotlightShape.isEmpty else {
          return
        }
        Task { @MainActor in
          remeasuring = true
          try? await Task.sleep(for: .milliseconds(20))
          remeasuring = false
        }
      }
      // The spotlight arrives above everything else, and a list that kept
      // its place in the content would show it already half scrolled past.
      .defaultScrollAnchor(.top)
      // Arrows walk the inbox from the first keystroke; without this the
      // sidebar holds the keyboard until a row is clicked.
      .claimsInitialKeyboardFocus()
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
