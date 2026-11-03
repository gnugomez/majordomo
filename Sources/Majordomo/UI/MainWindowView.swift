// Main-window shell: a NavigationSplitView of the source list and what it
// selects — the inbox list or a board — with the selection's preview in
// an inspector at the trailing edge. The column dividers, the sidebar's and
// the inspector's glass and slide, the content scrolling on beneath them,
// keyboard navigation, and the toolbar are all the system's. Settings open
// in their own window.

import AppKit
import SwiftUI

struct MainWindowView: View {
  let model: AppModel

  /// How tall the floating filter pills stand; the list's rows start below.
  @State private var pillBarHeight: CGFloat = 0
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
    /// The pills under the toolbar, each with what its menu offers.
    var facets: [FacetChoices]
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
    // never hidden). The search, date, and unread filters apply to every
    // category alike; the sidebar's badges stay unfiltered (SidebarView
    // counts on its own).
    let narrowed = matchingWindow(matchingSearch(items, model.searchText), model.activityWindow, now: model.now)
    let categories = categorize(inboxOrder(narrowed), into: specs)
    let selectable = visibleCategories(layout: model.sidebarLayout, categories: categories)
    let category = selectable.first { $0.id == sidebar.category } ?? categories[0]
    // The pills narrow the category last. Each pill's menu lists what the
    // other pills and filters leave, so every value it offers shows rows.
    let picks = model.facetPicks
    let facets = offeredFacets(for: account).map { facet in
      let pool = listedThreads(matchingFacets(category.items, picks, except: facet)).flatMap(\.items)
      return facetChoices(facet, in: pool, picked: picks[facet])
    }
    return Scope(
      account: account,
      category: category,
      threads: listedThreads(matchingFacets(category.items, picks)),
      facets: facets
    )
  }

  /// Items as the list shows them: one row per thread, and while the unread
  /// filter is on, only the unread ones and those read in place.
  private func listedThreads(_ items: [InboxItem]) -> [InboxThread] {
    let threads = groupIntoThreads(items)
    return model.unreadOnly ? matchingUnread(threads, kept: model.keptReadIds) : threads
  }

  /// The pills a scope offers. Provider can only narrow a scope spanning
  /// accounts on more than one provider, so it shows just then — or while
  /// it holds a pick, which must stay clearable.
  private func offeredFacets(for account: AccountState?) -> [Facet] {
    let providers = Set((account.map { [$0] } ?? model.accounts).map(\.provider))
    return Facet.allCases.filter { facet in
      facet != .provider || providers.count > 1 || model.facetPicks[.provider] != nil
    }
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
    .sheet(item: Binding(get: { model.editingBoard }, set: { model.editingBoard = $0 })) { board in
      BoardEditorSheet(model: model, board: board)
    }
  }

  private var sidebarColumn: some View {
    SidebarView(
      model: model,
      selection: Binding(
        get: { model.sidebarSelection },
        set: { model.sidebarSelection = $0 }
      )
    )
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
    .navigationSubtitle(model.selectedBoard.map { cardCount(boardPlacement($0).count) } ?? itemCount(scope.threads.count))
  }

  /// The inbox list, the filter pills and the suggestion panel floating
  /// over it.
  private func inboxList(_ scope: Scope) -> some View {
    let pillRoom = model.hasAccounts ? pillBarHeight : 0
    return InboxListView(model: model, threads: scope.threads, categoryId: scope.category.id, topInset: pillRoom)
      // The filter pills float over the list, just under the toolbar.
      // An overlay rather than a safe-area inset or bar: either of those
      // extends the toolbar's edge effect down over the pills, fading the
      // rows out beneath them, where floating they sit on the rows
      // themselves, seen through the glass. The list leaves room their
      // height above its first row. They stay up when the filters empty
      // the list, so they can be undone.
      .overlay(alignment: .top) {
        if model.hasAccounts {
          FilterPillBar(model: model, facets: scope.facets)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pillBarHeight = $0 }
        }
      }
      // The suggestion panel floats over the foot of the list, and only
      // while the model has something to offer.
      .overlay(alignment: .bottom) {
        SuggestionPanel(model: model)
      }
  }

  // MARK: Board

  /// The board's cards, narrowed by the search and the pills.
  private func boardPlacement(_ board: Board) -> BoardPlacement {
    model.placement(of: board, search: model.searchText, picks: model.facetPicks)
  }

  /// The card the board has selected, while it is on the board.
  private func selectedCard(on board: Board) -> BoardCard? {
    model.selectedCardId.flatMap { boardPlacement(board).byId[$0] }
  }

  /// A board, the filter pills floating over it as over the inbox.
  private func boardContent(_ board: Board) -> some View {
    let placement = boardPlacement(board)
    // The inbox's pills, over the board: each menu lists what the search
    // and the other pills leave on it. A board spans every account, so the
    // provider pill shows whenever more than one provider is connected.
    let facets = offeredFacets(for: nil).map { facet in
      let pool = model.placement(of: board, search: model.searchText, picks: model.facetPicks, except: facet).byId
      return facetChoices(facet, in: Array(pool.values), picked: model.facetPicks[facet])
    }
    let selected = selectedCard(on: board)
    return boardPane(board, placement: placement)
      // The board leaves their height above its column headers.
      .overlay(alignment: .top) {
        if model.hasAccounts {
          FilterPillBar(model: model, facets: facets)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pillBarHeight = $0 }
        }
      }
      .onChange(of: selected?.id, initial: true) {
        if let selected {
          model.markSeen(selected)
        }
      }
  }

  @ViewBuilder
  private func boardPane(_ board: Board, placement: BoardPlacement) -> some View {
    if !model.hasAccounts {
      boardEmptyState(
        symbol: "tray",
        title: "No accounts connected",
        caption: "Add an account in Settings to fill your boards."
      )
    } else if placement.count == 0 {
      if !model.searchText.isEmpty {
        boardEmptyState(
          symbol: "magnifyingglass",
          title: "No results",
          caption: "Nothing on this board matches \u{201C}\(model.searchText)\u{201D}."
        )
      } else if !model.facetPicks.isEmpty {
        boardEmptyState(
          symbol: "line.3.horizontal.decrease",
          title: "No matches",
          caption: "Nothing on this board matches the filters above. Set one back to Any to see the rest."
        )
      } else {
        boardEmptyState(
          symbol: board.symbol,
          title: "Nothing on this board yet",
          caption: "Cards turn up as notifications arrive about the issues and pull requests this board takes."
        )
      }
    } else {
      BoardView(model: model, board: board, placement: placement, topInset: pillBarHeight)
    }
  }

  /// Scroll-backed for the same reason as PreviewView's empty state: plain
  /// content makes the toolbar draw a hard edge over the pane.
  private func boardEmptyState(symbol: String, title: String, caption: String) -> some View {
    ScrollView {
      EmptyStateView(symbol: symbol, title: title, caption: caption)
        .containerRelativeFrame(.vertical)
    }
  }

  /// The filter glyph as an NSImage. The toolbar draws its items' images
  /// itself, as templates, so no SwiftUI color modifier ever reaches them;
  /// a non-template image already painted in the accent color is how the
  /// active state shows.
  private static func filterGlyph(active: Bool) -> NSImage {
    let glyph = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Filter")!
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
      multiSelectionPlaceholder(count: selectedThreads.count)
    } else {
      PreviewView(model: model, thread: selected)
    }
  }

  // MARK: Toolbar

  /// In groups, as fixed spacers part them: Refresh; the selection's
  /// actions; the filter; the preview toggle. Mark-read and Open are always
  /// present over the inbox, disabled while nothing is selected, so the
  /// toolbar keeps one shape. Over a board they go — opening and marking
  /// read live on the cards there (a double-click, the context menu), and
  /// a board is for looking across — and the board's menu stands in for
  /// the filter.
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
      ToolbarSpacer(.fixed)
    }
    ToolbarItem {
      if model.selectedBoard != nil {
        BoardToolbarControls(model: model)
      } else {
        filterMenu
      }
    }
    ToolbarSpacer(.fixed)
    ToolbarItem {
      PreviewToggle(model: model)
    }
  }

  /// The filter: Unread Only, then a pull-down of rolling date windows,
  /// behind the plain filter glyph (no menu chevron), accent-colored while
  /// either narrows the list.
  private var filterMenu: some View {
    let active = model.unreadOnly || model.activityWindow != nil
    return Menu {
      Toggle(
        "Unread Only",
        isOn: Binding(
          get: { model.unreadOnly },
          set: { model.setUnreadOnly($0) }
        )
      )
      Divider()
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
        .accessibilityLabel("Filter")
    }
    .menuIndicator(.hidden)
    .help(filterHelp)
  }

  /// The filter's tooltip: what the list is narrowed to right now.
  private var filterHelp: String {
    let window = model.activityWindow?.label.lowercased()
    switch (model.unreadOnly, window) {
    case (false, nil): return "Filter by unread or date"
    case (true, nil): return "Showing unread"
    case (false, let window?): return "Showing the \(window)"
    case (true, let window?): return "Showing unread from the \(window)"
    }
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
      Label("Preview", systemImage: "info.circle")
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
