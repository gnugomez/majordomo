// Main-window shell: a mail-style three-column NavigationSplitView (source
// list, inbox, preview). The column dividers, their drag behavior, the
// sidebar material, keyboard navigation, and the toolbar are all the
// system's. Settings open in their own window.

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
  }

  private func resolveScope() -> Scope {
    let sidebar = model.sidebarSelection
    let account = sidebar.account.flatMap { id in model.accounts.first { $0.id == id } }
    let items = account.map { scoped in model.items.filter { $0.accountId == scoped.id } }
      ?? model.items
    let specs = account.map { accountCategories(for: $0.provider) } ?? aggregatedCategories
    // Hidden inboxes fall back to Recent (always visible, always first).
    let categories = categorize(byNewest(items), into: specs)
      .filter { !model.hiddenCategories.contains($0.id) }
    let category = categories.first { $0.id == sidebar.category } ?? categories[0]
    return Scope(account: account, category: category)
  }

  var body: some View {
    let scope = resolveScope()
    // Selection is by id, so it survives sync updates; ids from other
    // scopes stay in the set but must not count here.
    let selectedItems = scope.category.items.filter { model.selectedItemIds.contains($0.id) }
    let selected = selectedItems.count == 1 ? selectedItems.first : nil

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
      // toggle, so supply Mail's, with the standard shortcut. Declared on
      // the sidebar column but placed .navigation, so it survives (leading)
      // while the sidebar is hidden.
      .toolbar {
        ToolbarItem(placement: .navigation) {
          sidebarToggleButton
        }
      }
    } content: {
      InboxListView(model: model, items: scope.category.items, categoryId: scope.category.id)
        .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 560)
        // Declared on the column so it lands in the list's own toolbar
        // section, Mail-style. The one toolbar button: refresh, over the
        // inbox column. Marking read is the rows' right-click menu's job.
        .toolbar {
          ToolbarItem {
            refreshButton
          }
        }
    } detail: {
      detailPane(selectedItems: selectedItems, selected: selected)
    }
    .navigationTitle(windowTitle(for: scope))
    .navigationSubtitle(itemCount(scope.category.items.count))
    // The columns carry their own minimum widths; the window's minimum
    // height lives here (hosting sizingOptions [.minSize] enforces both).
    .frame(minHeight: 420)
    .onChange(of: columnVisibility) {
      UserDefaults.standard.set(columnVisibility == .doubleColumn, forKey: "sidebarHidden")
    }
  }

  private func windowTitle(for scope: Scope) -> String {
    guard let account = scope.account else {
      return scope.category.label
    }
    return "\(scope.category.label) – @\(account.username ?? account.provider.displayName)"
  }

  // MARK: Detail column

  private func detailPane(selectedItems: [InboxItem], selected: InboxItem?) -> some View {
    Group {
      if selectedItems.count > 1 {
        multiSelectionPlaceholder(count: selectedItems.count)
      } else {
        PreviewView(model: model, item: selected)
      }
    }
    .frame(minWidth: 360)
    // Open lives at the trailing edge and only while something is selected;
    // the invisible item covers the empty case so the detail section (which
    // anchors the list column's items) never disappears.
    .toolbar {
      if selectedItems.isEmpty {
        ToolbarItem {
          Color.clear.frame(width: 1, height: 1)
        }
        .sharedBackgroundVisibility(.hidden)
      } else {
        ToolbarSpacer(.flexible)
        ToolbarItem {
          openButton(for: selectedItems)
        }
      }
    }
  }

  /// Scroll-backed for the same reason as PreviewView's empty state: plain
  /// content makes the toolbar draw a hard edge over the pane.
  private func multiSelectionPlaceholder(count: Int) -> some View {
    ScrollView {
      EmptyStateView(
        symbol: "square.stack",
        title: "\(count) items selected",
        caption: "Open them all with a double-click, or mark them read from the context menu."
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

  private func openButton(for selectedItems: [InboxItem]) -> some View {
    Button {
      for item in selectedItems {
        model.openItem(item.id)
      }
    } label: {
      // The count rides along in the glyph once the action spans more than
      // one item.
      HStack(spacing: 3) {
        Image(systemName: "arrow.up.forward")
        if selectedItems.count > 1 {
          Text("+\(selectedItems.count)")
            .font(.system(size: 11, weight: .semibold))
        }
      }
    }
    .keyboardShortcut("o")
    .help("\(openLabel(selectedItems)) — opens in your browser and marks read")
  }

  private func openLabel(_ items: [InboxItem]) -> String {
    items.count == 1
      ? "Open in \(items[0].provider.displayName)"
      : "Open \(items.count) in Browser"
  }
}

private func itemCount(_ count: Int) -> String {
  count == 1 ? "1 item" : "\(count) items"
}
