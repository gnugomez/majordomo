// Main-window shell: a three-column NavigationSplitView (source list,
// inbox, preview). The column dividers, their drag behavior, the
// sidebar material, keyboard navigation, and the toolbar are all the
// system's. Settings open in their own window.

import AppKit
import SwiftUI

struct MainWindowView: View {
  let model: AppModel

  @State private var columnVisibility: NavigationSplitViewVisibility =
    UserDefaults.standard.bool(forKey: "sidebarHidden") ? .doubleColumn : .all

  /// Everything the sidebar selection resolves to for one render pass.
  private struct Scope {
    /// nil when the aggregated "All Inboxes" section is selected — or when
    /// the selected account was removed (the view falls back to aggregate).
    var account: AccountState?
    var category: Category
    /// The category's items grouped into threads: one row per target.
    var threads: [InboxThread]
  }

  private func resolveScope() -> Scope {
    let sidebar = model.sidebarSelection
    let account = sidebar.account.flatMap { id in model.accounts.first { $0.id == id } }
    let items = account.map { scoped in model.items.filter { $0.accountId == scoped.id } }
      ?? model.items
    let labels = account.map { accountLabels(for: $0.provider, user: model.labels) }
      ?? aggregatedLabels(user: model.labels)
    let specs = categories(for: labels)
    // The sidebar layout decides what is selectable: an inbox hidden there
    // or gone from the tree falls back to Recent (always first in specs,
    // never hidden). The search and date filters apply to every category
    // alike; the sidebar's badges stay unfiltered (SidebarView counts on
    // its own).
    let narrowed = matchingWindow(matchingSearch(items, model.searchText), model.activityWindow, now: model.now)
    let categories = categorize(inboxOrder(narrowed), into: specs)
    let selectable = visibleCategories(layout: model.sidebarLayout, categories: categories)
    let category = selectable.first { $0.id == sidebar.category } ?? categories[0]
    return Scope(account: account, category: category, threads: groupIntoThreads(category.items))
  }

  var body: some View {
    let scope = resolveScope()
    // Selection survives sync updates (ids from other scopes stay in the
    // set but must not count here); a selected id is a thread row or an
    // unfolded member row — resolveSelection tells them apart.
    let selectedThreads = resolveSelection(in: scope.threads, ids: model.selectedThreadIds)
    let selected = selectedThreads.count == 1 ? selectedThreads.first : nil
    // A message card picked inside the preview narrows the toolbar actions
    // to just that message; a stale pick (another thread's member) counts
    // for nothing.
    let pickedMember = selected?.items.first { $0.id == model.selectedMemberId }
    let actionTargets = pickedMember.map { [InboxThread(id: $0.id, items: [$0])] } ?? selectedThreads

    NavigationSplitView(columnVisibility: $columnVisibility) {
      SidebarView(
        model: model,
        selection: Binding(
          get: { model.sidebarSelection },
          set: { model.sidebarSelection = $0 }
        )
      )
      .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 320)
      // The bridged toolbar drops NavigationSplitView's automatic sidebar
      // toggle, so supply one, with the standard shortcut. Declared on
      // the sidebar column but placed .navigation, so it survives (leading)
      // while the sidebar is hidden.
      .toolbar {
        ToolbarItem(placement: .navigation) {
          sidebarToggleButton
        }
      }
    } content: {
      InboxListView(model: model, threads: scope.threads, categoryId: scope.category.id)
        .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 560)
        // Declared on the column so it lands in the list's own toolbar
        // section: refresh sits over the inbox column, the selection's
        // actions over the detail column.
        .toolbar {
          ToolbarItem {
            refreshButton
          }
        }
    } detail: {
      detailPane(selectedThreads: selectedThreads, selected: selected, actionTargets: actionTargets)
    }
    .navigationTitle(windowTitle(for: scope))
    .navigationSubtitle(itemCount(scope.threads.count))
    // The search field sits at the toolbar's trailing edge, filtering the
    // list live. State lives on the model so ⌘F (AppDelegate's Edit menu)
    // can focus the field from outside the view tree.
    .searchable(
      text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
      isPresented: Binding(get: { model.searchPresented }, set: { model.searchPresented = $0 }),
      placement: .toolbar,
      prompt: "Search"
    )
    // Rows, preview, and bodies paint the query's matches from this.
    .environment(\.searchHighlightTerms, searchTerms(model.searchText))
    // The columns carry their own minimum widths; the window's minimum
    // height lives here (hosting sizingOptions [.minSize] enforces both).
    .frame(minHeight: 420)
    .onChange(of: columnVisibility) {
      UserDefaults.standard.set(columnVisibility == .doubleColumn, forKey: "sidebarHidden")
    }
  }

  /// The filter glyph as an NSImage. The toolbar draws its items' images
  /// itself, as templates, so no SwiftUI color modifier ever reaches them;
  /// a non-template image already painted in the accent color is how the
  /// active state shows.
  private static func filterGlyph(active: Bool) -> NSImage {
    let glyph = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Filter by date")!
    guard active,
          let painted = glyph.withSymbolConfiguration(.init(paletteColors: [.controlAccentColor])) else {
      return glyph
    }
    painted.isTemplate = false
    return painted
  }

  private func windowTitle(for scope: Scope) -> String {
    guard let account = scope.account else {
      return scope.category.label
    }
    return "\(scope.category.label) – @\(account.username ?? account.provider.displayName)"
  }

  // MARK: Detail column

  private func detailPane(
    selectedThreads: [InboxThread], selected: InboxThread?, actionTargets: [InboxThread]
  ) -> some View {
    Group {
      if selectedThreads.count > 1 {
        multiSelectionPlaceholder(count: selectedThreads.count)
      } else {
        PreviewView(model: model, thread: selected)
      }
    }
    .frame(minWidth: 360)
    // Mark-read and Open sit at the leading edge of the detail section
    // (the search field owns the trailing edge) and only while something
    // is selected; the invisible item covers the empty case so the detail
    // section (which anchors the list column's items) never disappears.
    // The date filter is declared last so it is the item nearest the
    // search field; MainWindowController then moves the toolbar's trailing
    // spacer ahead of it, which SwiftUI offers no placement for.
    .toolbar {
      if selectedThreads.isEmpty {
        ToolbarItem {
          Color.clear.frame(width: 1, height: 1)
        }
        .sharedBackgroundVisibility(.hidden)
      } else {
        ToolbarItem {
          markReadButton(for: actionTargets)
        }
        ToolbarItem {
          openButton(for: actionTargets)
        }
      }
      ToolbarItem {
        activityFilterMenu
      }
    }
  }

  /// The date filter: a pull-down of rolling windows behind the plain
  /// filter glyph (no menu chevron), accent-colored while one is active.
  private var activityFilterMenu: some View {
    let active = model.activityWindow != nil
    return Menu {
      Picker(
        "Show",
        selection: Binding(
          get: { model.activityWindow },
          set: { model.setActivityWindow($0) }
        )
      ) {
        Text("Any time").tag(ActivityWindow?.none)
        Divider()
        ForEach(ActivityWindow.allCases) { window in
          Text(window.label).tag(Optional(window))
        }
      }
      .pickerStyle(.inline)
    } label: {
      Image(nsImage: Self.filterGlyph(active: active))
        .accessibilityLabel("Filter by date")
    }
    .menuIndicator(.hidden)
    .help(model.activityWindow.map { "Showing the \($0.label.lowercased()) — filter by date" } ?? "Filter by date")
  }

  private func markReadButton(for selectedThreads: [InboxThread]) -> some View {
    Button {
      model.markRead(Set(selectedThreads.flatMap(\.itemIds)))
    } label: {
      HStack(spacing: 3) {
        Image(systemName: "envelope.open")
        if selectedThreads.count > 1 {
          Text("+\(selectedThreads.count)")
            .font(.system(size: 11, weight: .semibold))
        }
      }
    }
    .keyboardShortcut("u", modifiers: [.shift, .command])
    .disabled(!selectedThreads.contains { !$0.read })
    .help(selectedThreads.count > 1 ? "Mark \(selectedThreads.count) as read" : "Mark as read")
  }

  /// Scroll-backed for the same reason as PreviewView's empty state: plain
  /// content makes the toolbar draw a hard edge over the pane.
  private func multiSelectionPlaceholder(count: Int) -> some View {
    ScrollView {
      EmptyStateView(
        symbol: "square.stack",
        title: "\(count) items selected",
        caption: "Open them all with a double-click, or mark them read from the toolbar."
      )
      .containerRelativeFrame(.vertical)
    }
  }

  // MARK: Toolbar buttons

  private var sidebarToggleButton: some View {
    Button {
      withAnimation {
        columnVisibility = columnVisibility == .all ? .doubleColumn : .all
      }
    } label: {
      Label("Toggle Sidebar", systemImage: "sidebar.leading")
    }
    .keyboardShortcut("s", modifiers: [.control, .command])
    .help("Hide or show the sidebar")
  }

  private var refreshButton: some View {
    Button {
      model.refresh()
    } label: {
      Label("Refresh now", systemImage: "arrow.clockwise")
    }
    .keyboardShortcut("r")
    .disabled(model.syncing)
    .help("Refresh now")
  }

  private func openButton(for selectedThreads: [InboxThread]) -> some View {
    Button {
      for thread in selectedThreads {
        model.openThread(thread.itemIds)
      }
    } label: {
      // The count rides along in the glyph once the action spans more than
      // one thread.
      HStack(spacing: 3) {
        Image(systemName: "arrow.up.forward")
        if selectedThreads.count > 1 {
          Text("+\(selectedThreads.count)")
            .font(.system(size: 11, weight: .semibold))
        }
      }
    }
    .keyboardShortcut("o")
    .help("\(openLabel(selectedThreads)) — opens in your browser and marks read")
  }

  private func openLabel(_ threads: [InboxThread]) -> String {
    threads.count == 1
      ? "Open in \(threads[0].lead.provider.displayName)"
      : "Open \(threads.count) in Browser"
  }
}

private func itemCount(_ count: Int) -> String {
  count == 1 ? "1 item" : "\(count) items"
}
