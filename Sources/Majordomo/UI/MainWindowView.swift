// Main-window shell: a NavigationSplitView of the source list and what it
// selects — the inbox list or a board — with the selection's preview in
// an inspector at the trailing edge, or for a board, if the user puts it
// there, in a pane under it (BottomPreviewSplit). The column dividers, the
// sidebar's and the inspector's glass and slide, the content scrolling on
// beneath them, the lists' keyboard navigation, and the toolbar are all
// the system's; a board reads its keys itself (BoardKeyboard). Settings
// open in their own window.

import SwiftUI

struct MainWindowView: View {
  @Bindable var model: AppModel

  /// The widths the sidebar and the preview open at: where the user last
  /// left them. Read once, as the window opens.
  @State private var sidebarWidth = rememberedWidth(sidebarWidthKey, or: 200)
  @State private var previewWidth = rememberedWidth(previewWidthKey, or: previewIdealWidth)

  /// Everything the sidebar selection resolves to for one render pass.
  private struct Scope {
    /// The selected inbox, holding every account's items.
    var category: Category
    /// The category's items grouped into threads: one row per target.
    var threads: [InboxThread]
  }

  private func resolveScope() -> Scope {
    let specs = categories(for: model.catalog.labels)
    // The sidebar layout decides what is selectable: an inbox hidden there
    // or gone from the tree falls back to Recent (always first in specs,
    // never hidden). The search and the filter apply to every category
    // alike — the filter's Provider pick is what narrows to one
    // provider's items; the sidebar's badges stay unfiltered (SidebarView
    // counts on its own).
    let filter = model.filter
    let narrowed = matchingWindow(matchingSearch(model.items, model.searchText), filter.window, now: model.now)
    let categories = categorize(inboxOrder(narrowed), into: specs)
    let selectable = visibleCategories(layout: model.sidebarLayout, categories: categories)
    let category = selectable.first { $0.id == model.sidebarSelection.category } ?? categories[0]
    // The filter's picks narrow the category last.
    return Scope(
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
        contentToolbar
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
    .navigationTitle(model.selectedBoard?.name ?? scope.category.label)
    .navigationSubtitle(subtitle(for: scope))
  }

  /// What the window's subtitle says: how many rows or cards show, and
  /// while the filter narrows them, what it narrows by.
  private func subtitle(for scope: Scope) -> String {
    let count = itemCount(model.selectedBoard.map { boardPlacement($0).count } ?? scope.threads.count)
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

  /// A board, marking the card it has selected seen, over the card's
  /// preview while the preview stands under the board.
  private func boardContent(_ board: Board) -> some View {
    let placement = boardPlacement(board)
    let selected = selectedCard(on: board)
    let below = model.boardPreviewPlacement == .bottom && model.cardPreviewShown && selected != nil
    return BottomPreviewSplit(shown: below) {
      boardPane(board, placement: placement)
    } preview: {
      cardPreview(selected, placement: .bottom)
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
          caption: "Items turn up here as notifications arrive about what this board takes."
        )
      }
    } else {
      BoardView(model: model, board: board, placement: placement)
    }
  }

  // MARK: Preview

  /// Whether the inspector shows: the inbox's preview as the user leaves
  /// it, a board's while a card is picked, its preview not put away, and
  /// the preview stands beside the board rather than under it.
  private var previewPresented: Binding<Bool> {
    Binding(
      get: {
        guard let board = model.selectedBoard else {
          return model.inboxPreviewShown
        }
        return model.boardPreviewPlacement == .trailing && model.cardPreviewShown && selectedCard(on: board) != nil
      },
      set: { shown in
        if model.selectedBoard != nil {
          // Only the inspector's own say: as the preview moves under the
          // board, the inspector closing writes back too.
          if model.boardPreviewPlacement == .trailing {
            model.cardPreviewShown = shown
          }
        } else {
          model.inboxPreviewShown = shown
        }
      }
    )
  }

  @ViewBuilder
  private func previewPane(selectedThreads: [InboxThread], selected: InboxThread?) -> some View {
    if let board = model.selectedBoard {
      cardPreview(selectedCard(on: board), placement: .trailing)
    } else if selectedThreads.count > 1 {
      PaneEmptyState(
        symbol: "square.stack",
        title: "\(selectedThreads.count) items selected",
        caption: "Opening them marks them read too."
      ) {
        SelectionActions(model: model, threads: selectedThreads)
          .padding(.top, 8)
      }
    } else {
      PreviewView(model: model, thread: selected)
    }
  }

  private func cardPreview(_ card: BoardCard?, placement: PreviewPlacement) -> some View {
    PreviewView(model: model, thread: card.map { InboxThread(id: $0.id, items: $0.items) }, placement: placement)
  }

  // MARK: Toolbar

  /// In groups, as fixed spacers part them: Refresh; over a board, the
  /// board's menu; the filter; the preview toggle. Opening and marking
  /// read live beside what they act on — in the preview, and on the rows
  /// and cards (a double-click, Return, the context menu) — not up here.
  /// The filter and the preview toggle stand over both, after the item
  /// that comes and goes: everything past them keeps its width from the
  /// inbox to a board, so switching leaves them where they are. In a
  /// narrow window the system folds the search into a button first, then
  /// the filter and the preview toggle into the overflow menu.
  @ToolbarContentBuilder
  private var contentToolbar: some ToolbarContent {
    ToolbarItem {
      RefreshButton(model: model)
    }
    ToolbarSpacer(.fixed)
    if model.selectedBoard != nil {
      ToolbarItem {
        BoardToolbarControls(model: model)
      }
      ToolbarSpacer(.fixed)
    }
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
/// a board, for the whole board in view without losing the selection. Over
/// a board it is split like the filter, the glyph and a chevron: a click
/// on the glyph shows or puts away the preview, and the chevron's menu sets
/// where it stands — beside the board or under it — which the glyph draws.
/// A view of its own, like Refresh, reading only what decides how it looks.
private struct PreviewToggle: View {
  let model: AppModel

  var body: some View {
    if model.selectedBoard != nil {
      let placement = model.boardPreviewPlacement
      Menu {
        // The glyph's click too, for the toolbar's overflow menu, which
        // lists the menu but not the click.
        Button("Toggle Preview", action: toggleCardPreview)
        Divider()
        Picker(
          "Preview",
          selection: Binding(
            get: { placement },
            set: { placement in
              withAnimation {
                model.boardPreviewPlacement = placement
              }
            }
          )
        ) {
          Text("Preview on Right").tag(PreviewPlacement.trailing)
          Text("Preview at Bottom").tag(PreviewPlacement.bottom)
        }
        .pickerStyle(.inline)
        .labelsHidden()
      } label: {
        Label("Preview", systemImage: placement == .bottom ? "rectangle.bottomthird.inset.filled" : "sidebar.trailing")
      } primaryAction: {
        toggleCardPreview()
      }
      .keyboardShortcut("i", modifiers: [.command, .option])
      .disabled(model.selectedCardId == nil)
      .help("Show or hide the preview; the arrow sets where it stands")
      // The toolbar builds the menu once and keeps it, its tick where it
      // was; keyed by the placement, a pick makes a fresh one.
      .id(placement)
    } else {
      Button {
        withAnimation {
          model.inboxPreviewShown.toggle()
        }
      } label: {
        Label("Preview", systemImage: "sidebar.trailing")
      }
      .keyboardShortcut("i", modifiers: [.command, .option])
      .help("Show or hide the preview")
    }
  }

  private func toggleCardPreview() {
    withAnimation {
      model.cardPreviewShown.toggle()
    }
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
