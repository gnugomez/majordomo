// Main-window shell: a NavigationSplitView of the source list and what it
// selects — the inbox list or a board — with the selection's preview in
// an inspector at the trailing edge. The column dividers, the sidebar's and
// the inspector's glass and slide, the content scrolling on beneath them,
// the lists' keyboard navigation, and the toolbar are all the system's; a
// board reads its keys itself (BoardKeyboard). Settings open in their own
// window.

import SwiftUI

struct MainWindowView: View {
  @Bindable var model: AppModel

  /// The widths the sidebar and the preview open at: where the user last
  /// left them. Read once, as the window opens.
  @State private var sidebarWidth = rememberedWidth(sidebarWidthKey, or: 200)
  @State private var previewWidth = rememberedWidth(previewWidthKey, or: previewIdealWidth)

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
    let labels = model.catalog.sectionLabels(for: account?.provider)
    let specs = categories(for: labels)
    // The sidebar layout decides what is selectable: an inbox hidden there
    // or gone from the tree falls back to Recent (always first in specs,
    // never hidden). The search and the filter apply to every category
    // alike; the sidebar's badges stay unfiltered (SidebarView counts on
    // its own).
    let filter = model.filter
    let narrowed = matchingWindow(matchingSearch(items, model.searchText), filter.window, now: model.now)
    let categories = categorize(inboxOrder(narrowed), into: specs)
    let selectable = visibleCategories(layout: model.sidebarLayout, categories: categories)
    let category = selectable.first { $0.id == sidebar.category } ?? categories[0]
    // The filter's picks narrow the category last.
    return Scope(
      account: account,
      category: category,
      threads: listedThreads(matchingFacets(category.items, filter.picks), filter)
    )
  }

  /// Items as the list shows them: one row per thread, and while the
  /// filter narrows to unread, only the unread ones and those read in
  /// place.
  private func listedThreads(_ items: [InboxItem], _ filter: InboxFilter) -> [InboxThread] {
    let threads = groupIntoThreads(items)
    return filter.unreadOnly ? matchingUnread(threads, kept: model.keptReadIds) : threads
  }

  /// What a facet's menu offers once it opens: the facet's values across
  /// what the search and the rest of the filter leave of the board or the
  /// inbox's category, each counting the rows picking it would leave. The
  /// pick is the filter's own, checked even while the filter is off.
  private func offeredValues(for facet: Facet) -> [FacetValue] {
    let filter = model.filter
    let picked = model.facetPicks[facet]
    if let board = model.selectedBoard {
      let pool = model.placement(of: board, search: model.searchText, filter: filter, except: facet).allCards
      return facetValues(facet, in: pool, picked: picked)
    }
    let category = resolveScope().category
    let pool = listedThreads(matchingFacets(category.items, filter.picks, except: facet), filter)
    return facetValues(facet, in: pool, picked: picked)
  }

  var body: some View {
    split
      // Between the inbox and a board the window changes at once: the
      // toolbar's items are rebuilt either way, and animated they fade
      // and morph through a few frames.
      .transaction(value: model.selectedBoard?.id) { transaction in
        transaction.disablesAnimations = true
      }
    // The search field sits at the toolbar's trailing edge, filtering the
    // list (or the board) live. State lives on the model so ⌘F
    // (AppDelegate's Edit menu) can focus the field from outside the view
    // tree.
    .searchable(
      text: $model.searchText,
      isPresented: $model.searchPresented,
      placement: .toolbar,
      prompt: "Search"
    )
    // Rows, preview, and bodies paint the query's matches from this.
    .environment(\.searchHighlightTerms, searchTerms(model.searchText))
    // The columns carry their own minimum widths; the window's minimum
    // height lives here (hosting sizingOptions [.minSize] enforces both).
    .frame(minHeight: 420)
    .sheet(item: $model.editingBoard) { board in
      BoardEditorSheet(model: model, board: board)
    }
  }

  private var sidebarColumn: some View {
    SidebarView(model: model, selection: $model.sidebarSelection)
    // The widths go outside the note of the width: wrapped in its
    // onGeometryChange, the split no longer finds them.
    .remembersWidth(sidebarWidthKey)
    .navigationSplitViewColumnWidth(min: 170, ideal: sidebarWidth, max: 320)
    // In the sidebar's own stretch of the toolbar, at its trailing end, and
    // beside the window's buttons while the sidebar is away. SwiftUI's own
    // toggle comes and goes with how the window was set up, so the split
    // view drops it (`.toolbar(removing: .sidebarToggle)`) for this one.
    .toolbar {
      ToolbarSpacer(.flexible)
      ToolbarItem {
        SidebarToggle(model: model)
      }
    }
  }

  /// The sidebar, what it selects, and the preview of what that selects.
  private var split: some View {
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

    let columnVisibility = Binding<NavigationSplitViewVisibility>(
      get: { model.sidebarShown ? .all : .detailOnly },
      set: { model.sidebarShown = $0 != .detailOnly }
    )
    return NavigationSplitView(columnVisibility: columnVisibility) {
      sidebarColumn
    } detail: {
      // Under a clear layer that stays put: the inspector beside the
      // column shrinks to its narrowest whenever the column's view is
      // swapped for another — the list for a board, or the list's empty
      // state for its rows — unless something in the column holds still.
      // On top, out of hit testing, rather than beneath: beneath, it is
      // what the toolbar finds at the top of the pane, and with the
      // inspector open the toolbar draws a hard line under itself instead
      // of fading the content out beneath it.
      ZStack {
        if let board = model.selectedBoard {
          boardContent(board)
        } else {
          inboxList(scope)
        }
        Color.clear.allowsHitTesting(false)
      }
      .toolbar {
        contentToolbar(actionTargets: actionTargets)
      }
      // The preview of what the list or the board selects: details about
      // the selection, at the trailing edge, as an inspector. In the
      // detail column rather than on the split: there SwiftUI counts it
      // twice in the window's minimum width, once as a column and again
      // as the room it covers over the content, and AppKit gives up on the
      // layout whenever it opens in a window narrower than that.
      .inspector(isPresented: previewPresented) {
        previewPane(selectedThreads: selectedThreads, selected: selected)
          .remembersWidth(previewWidthKey)
          .inspectorColumnWidth(min: previewMinWidth, ideal: previewWidth, max: previewMaxWidth)
      }
    }
    .toolbar(removing: .sidebarToggle)
    .navigationTitle(model.selectedBoard?.name ?? windowTitle(for: scope))
    .navigationSubtitle(subtitle(for: scope))
  }

  /// What the window's subtitle says: how many rows or cards show, and
  /// while the filter narrows them, what it narrows by.
  private func subtitle(for scope: Scope) -> String {
    let count = model.selectedBoard.map { cardCount(boardPlacement($0).count) } ?? itemCount(scope.threads.count)
    let filter = model.filter
    return filter.isEmpty ? count : "\(count) · \(filter.summary)"
  }

  /// The inbox list, and the suggestion panel floating over it.
  private func inboxList(_ scope: Scope) -> some View {
    InboxListView(model: model, threads: scope.threads, categoryId: scope.category.id)
      // The suggestion panel floats over the foot of the list, and only
      // while the model has something to offer.
      .overlay(alignment: .bottom) {
        SuggestionPanel(model: model)
      }
  }

  // MARK: Board

  /// The board's cards, narrowed by the search and the filter.
  private func boardPlacement(_ board: Board) -> BoardPlacement {
    model.placement(of: board, search: model.searchText, filter: model.filter)
  }

  /// The card the board has selected, while it is on the board.
  private func selectedCard(on board: Board) -> BoardCard? {
    model.selectedCardId.flatMap { boardPlacement(board).byId[$0] }
  }

  /// A board, marking the card it has selected seen.
  private func boardContent(_ board: Board) -> some View {
    let placement = boardPlacement(board)
    let selected = selectedCard(on: board)
    return boardPane(board, placement: placement)
      .onChange(of: selected?.id, initial: true) {
        if let selected {
          model.markSeen(selected)
        }
      }
  }

  @ViewBuilder
  private func boardPane(_ board: Board, placement: BoardPlacement) -> some View {
    if !model.hasAccounts {
      PaneEmptyState(
        symbol: "tray",
        title: "No accounts connected",
        caption: "Add an account in Settings to fill your boards."
      )
    } else if placement.count == 0 {
      if !model.searchText.isEmpty {
        PaneEmptyState(
          symbol: "magnifyingglass",
          title: "No results",
          caption: "Nothing on this board matches \u{201C}\(model.searchText)\u{201D}."
        )
      } else if model.filterActive {
        PaneEmptyState(
          symbol: "line.3.horizontal.decrease",
          title: "No matches",
          caption: "Nothing on this board matches the filter. Turn it off with ⌘L, or choose Clear Filters, to see the rest."
        )
      } else {
        PaneEmptyState(
          symbol: board.symbol,
          title: "Nothing on this board yet",
          caption: "Cards turn up as notifications arrive about the issues and pull requests this board takes."
        )
      }
    } else {
      BoardView(model: model, board: board, placement: placement)
    }
  }

  private func windowTitle(for scope: Scope) -> String {
    guard let account = scope.account else {
      return scope.category.label
    }
    return "\(scope.category.label) – @\(account.username ?? account.provider.displayName)"
  }

  // MARK: Preview

  /// Whether the inspector shows: the inbox's preview as the user leaves
  /// it, a board's while a card is picked and its preview not put away.
  private var previewPresented: Binding<Bool> {
    Binding(
      get: {
        guard let board = model.selectedBoard else {
          return model.inboxPreviewShown
        }
        return model.cardPreviewShown && selectedCard(on: board) != nil
      },
      set: { shown in
        if model.selectedBoard != nil {
          model.cardPreviewShown = shown
        } else {
          model.inboxPreviewShown = shown
        }
      }
    )
  }

  @ViewBuilder
  private func previewPane(selectedThreads: [InboxThread], selected: InboxThread?) -> some View {
    if let board = model.selectedBoard {
      PreviewView(model: model, thread: selectedCard(on: board).map { InboxThread(id: $0.id, items: $0.items) })
    } else if selectedThreads.count > 1 {
      PaneEmptyState(
        symbol: "square.stack",
        title: "\(selectedThreads.count) items selected",
        caption: "Open them all with a double-click, or mark them read from the toolbar."
      )
    } else {
      PreviewView(model: model, thread: selected)
    }
  }

  // MARK: Toolbar

  /// In groups, as fixed spacers part them: Refresh; the selection's
  /// actions; the filter; the preview toggle. Mark-read and Open are
  /// always present over the inbox, disabled while nothing is selected, so
  /// the toolbar keeps one shape. Over a board they go — opening and
  /// marking read live on the cards there (a double-click, the context
  /// menu), and a board is for looking across — and the board's menu takes
  /// their place. The filter and the preview toggle stand over both, after
  /// the items that come and go: everything past them keeps its width from
  /// the inbox to a board, so switching leaves them where they are. In a
  /// narrow window the system folds the search into a button first, then
  /// the filter and the preview toggle into the overflow menu.
  @ToolbarContentBuilder
  private func contentToolbar(actionTargets: [InboxThread]) -> some ToolbarContent {
    ToolbarItem {
      RefreshButton(model: model)
    }
    ToolbarSpacer(.fixed)
    if model.selectedBoard == nil {
      ToolbarItem {
        markReadButton(for: actionTargets)
      }
      ToolbarItem {
        openButton(for: actionTargets)
      }
    } else {
      ToolbarItem {
        BoardToolbarControls(model: model)
      }
    }
    ToolbarSpacer(.fixed)
    ToolbarItem {
      FilterToolbarControl(
        model: model,
        active: model.filterActive,
        summary: model.filter.summary,
        values: offeredValues
      )
      .equatable()
    }
    ToolbarSpacer(.fixed)
    ToolbarItem {
      PreviewToggle(model: model)
    }
  }

  private func markReadButton(for selectedThreads: [InboxThread]) -> some View {
    Button {
      model.markRead(Set(selectedThreads.flatMap(\.itemIds)))
    } label: {
      CountedGlyph(symbol: "envelope.open", count: selectedThreads.count)
    }
    .keyboardShortcut("u", modifiers: [.shift, .command])
    .disabled(!selectedThreads.contains { !$0.read })
    .help(selectedThreads.count > 1 ? "Mark \(selectedThreads.count) as read" : "Mark as read")
  }

  // MARK: Toolbar buttons

  private func openButton(for selectedThreads: [InboxThread]) -> some View {
    Button {
      for thread in selectedThreads {
        model.openThread(thread.itemIds)
      }
    } label: {
      CountedGlyph(symbol: "arrow.up.forward", count: selectedThreads.count)
    }
    .keyboardShortcut("o")
    .disabled(selectedThreads.isEmpty)
    .help("\(openLabel(selectedThreads)) — opens in your browser and marks read")
  }

  private func openLabel(_ threads: [InboxThread]) -> String {
    switch threads.count {
    case 0: "Open"
    case 1: "Open in \(threads[0].lead.provider.displayName)"
    default: "Open \(threads.count) in Browser"
    }
  }
}

private func itemCount(_ count: Int) -> String {
  count == 1 ? "1 item" : "\(count) items"
}

/// A selection action's glyph, the count riding along once the action
/// spans more than one thread.
private struct CountedGlyph: View {
  let symbol: String
  let count: Int

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: symbol)
      if count > 1 {
        Text("+\(count)")
          .font(.app(.caption, weight: .semibold))
      }
    }
  }
}

/// Refresh, in a view of its own so it redraws when a sync starts or ends
/// and at no other update of the window: a toolbar item redraws with a
/// fade.
private struct RefreshButton: View {
  let model: AppModel

  var body: some View {
    Button {
      model.refresh()
    } label: {
      Label("Refresh now", systemImage: "arrow.clockwise")
    }
    .keyboardShortcut("r")
    .disabled(model.syncing)
    .help("Refresh now")
  }
}

/// Slides the sidebar away or back. A view of its own, like Refresh: it
/// reads nothing that changes, so nothing redraws it.
private struct SidebarToggle: View {
  let model: AppModel

  var body: some View {
    Button {
      withAnimation {
        model.sidebarShown.toggle()
      }
    } label: {
      Label("Toggle Sidebar", systemImage: "sidebar.leading")
    }
    .help("Hide or show the sidebar")
  }
}

/// Shows or puts away the preview: the inbox's, or the selected card's on
/// a board, for the whole board in view without losing the selection. A
/// view of its own, like Refresh, reading only what decides how it looks.
private struct PreviewToggle: View {
  let model: AppModel

  var body: some View {
    let onBoard = model.selectedBoard != nil
    Button {
      withAnimation {
        if onBoard {
          model.cardPreviewShown.toggle()
        } else {
          model.inboxPreviewShown.toggle()
        }
      }
    } label: {
      Label("Preview", systemImage: "sidebar.trailing")
    }
    .keyboardShortcut("i", modifiers: [.command, .option])
    .disabled(onBoard && model.selectedCardId == nil)
    .help("Show or hide the preview")
  }
}

/// How wide the preview stands: the narrowest, at first, and the widest.
private let previewMinWidth: CGFloat = 360
private let previewIdealWidth: CGFloat = 420
private let previewMaxWidth: CGFloat = 900

private let sidebarWidthKey = "sidebarWidth"
private let previewWidthKey = "previewWidth"

/// The width a column was last left at, or `standard` the first time.
private func rememberedWidth(_ key: String, or standard: CGFloat) -> CGFloat {
  let saved = UserDefaults.standard.double(forKey: key)
  return saved > 0 ? saved : standard
}

private func cardCount(_ count: Int) -> String {
  count == 1 ? "1 card" : "\(count) cards"
}

private extension View {
  /// Notes the width the column this view fills is left at, for the window
  /// to open at next time. Straight into the defaults rather than into
  /// state: nothing on screen changes with it, and a state change would
  /// have the toolbar redraw on every step of a drag.
  func remembersWidth(_ key: String) -> some View {
    onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
      if width > 0 {
        UserDefaults.standard.set(Double(width), forKey: key)
      }
    }
  }
}
