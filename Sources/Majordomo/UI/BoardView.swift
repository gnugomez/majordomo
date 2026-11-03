// The board pane: a board's columns side by side, its cards placed by the
// board's rules (BoardEngine), split into lanes by repository or owner
// when the board asks for them. One scroll view carries the grid both ways,
// filling the pane, so its scrollers sit on the pane's edges and the cards
// pass under the sidebar, the toolbar, and the column headers — glass
// labels in a band under the toolbar that follow the grid sideways and
// stay put as it scrolls down; lane titles hold to the leading edge as it
// scrolls sideways. Dragging the board's empty space pans it. Clicking a card
// opens its preview in the window's inspector and clicking it again puts
// it away, double-clicking opens it in the browser, and dragging it
// onto a column puts it there by hand — locally, like every label; nothing
// is written upstream.

import SwiftUI

private let columnWidth: CGFloat = 256
/// Cards one slot draws before it offers the rest behind a button: a
/// maintainer's In Progress can run to hundreds, and every card drawn is
/// layout the board pays for on each redraw.
private let slotCardLimit = 40
private let columnGap: CGFloat = 10
/// The grid's leading margin, which the first column's label keeps too.
private let gridInset: CGFloat = 8
/// The band the column headers take at the board's top, under the
/// toolbar; the grid rests below it. The labels sit at its foot,
/// `headerGap` above its edge, leaving the rest as air under the toolbar.
private let headerBand: CGFloat = 44
private let headerGap: CGFloat = 8

struct BoardView: View {
  let model: AppModel
  let board: Board
  let placement: BoardPlacement

  /// Lanes the user folded away this session.
  @State private var collapsedLanes: Set<String> = []
  /// Slots ("lane|column") showing every card rather than the first
  /// `slotCardLimit`.
  @State private var expandedSlots: Set<String> = []
  /// The cell a drag is hovering, as "lane|column".
  @State private var dropTarget: String?
  /// The visible height under the headers; a board without lanes stretches
  /// its one row of cells to it, so a column reads as a column.
  @State private var laneViewport: CGFloat = 0
  /// How far the grid has scrolled sideways, for the headers to follow.
  /// A reference the board's own body never reads, so scrolling redraws
  /// the header row alone.
  @State private var scroll = BoardScroll()

  /// One column as drawn: one of the board's own, Other, or Done.
  private struct DrawnColumn: Identifiable {
    enum Kind {
      case column
      case other
      case done
    }

    let id: String
    let name: String
    let kind: Kind
    let cards: [BoardCard]
  }

  /// One row of the grid: the cards of one repository or owner, or every
  /// card when the board has no lanes, already split by column.
  private struct Lane: Identifiable {
    let id: String
    var slots: [String: [BoardCard]] = [:]
    var count = 0
    var latest = Date.distantPast
  }

  var body: some View {
    let columns = drawnColumns
    let lanes = lanes(of: columns)
    let scroll = scroll
    ScrollView([.horizontal, .vertical]) {
      // Lazy, so a board with dozens of repositories builds the lanes in
      // view and the rest as they scroll in.
      LazyVStack(alignment: .leading, spacing: 10) {
        ForEach(lanes) { lane in
          laneView(lane, columns: columns)
        }
      }
      .padding(.horizontal, gridInset)
      .padding(.bottom, 16)
      // A click on the board around the cards puts the selection down.
      .background {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            model.selectedCardId = nil
          }
      }
      .background {
        EnclosingScrollViewReader { scroll.view = $0 }
      }
      // Grabbing the board anywhere but a card moves it, both ways, the
      // way a board or canvas pans on the Mac; a card's own drag, which
      // moves it to a column, comes first. Measured in the window, which
      // holds still while the content moves under the pointer.
      .gesture(
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
          .onChanged { drag in
            scroll.pan(by: drag.translation)
          }
          .onEnded { _ in
            scroll.endPan()
          }
      )
    }
    // A board shorter or narrower than the pane sits at its top leading
    // corner, where the headers are, rather than centered.
    .defaultScrollAnchor(.topLeading)
    // Hard rather than soft: once the preview has slid in, the toolbar
    // draws a backdrop of its own that ends at its foot, and a soft edge
    // then leaves the cards legible under the header band, the labels
    // floating over them; a hard one keeps the whole band covered either
    // way.
    .scrollEdgeEffectStyle(.hard, for: .top)
    // The headers ride in a bar at the top: the grid rests below it and
    // scrolls on beneath it, and the scroll edge effect stretches over the
    // whole band, so cards pass out of sight under the labels instead of
    // crowding them.
    .safeAreaBar(edge: .top, spacing: 0) {
      ColumnHeaderRow(columns: columns.map(header), leading: gridInset, scroll: scroll)
    }
    .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in
      scroll.track(geometry)
    }

    // The container leaves out the insets already — the toolbar and the
    // header bar above, the sidebar's width beside. Taken once a resize
    // settles: every slot stretches to it, so following it frame by frame
    // would lay the whole grid out again on each step of the drag.
    .onScrollGeometryChange(for: CGFloat.self) { geometry in
      geometry.containerSize.height
    } action: { _, height in
      scroll.settle(height) { laneViewport = $0 }
    }
  }

  // MARK: Layout

  private var drawnColumns: [DrawnColumn] {
    var columns = board.columns.map { column in
      DrawnColumn(id: column.id, name: column.name, kind: .column, cards: placement.columns[column.id] ?? [])
    }
    if !placement.other.isEmpty {
      columns.append(DrawnColumn(id: "board-other", name: "Other", kind: .other, cards: placement.other))
    }
    columns.append(DrawnColumn(id: "board-done", name: "Done", kind: .done, cards: placement.done))
    return columns
  }

  /// The lanes, busiest-lately first: a lane sorts by its newest card.
  /// One pass over the cards, so each slot is a lookup when drawn.
  private func lanes(of columns: [DrawnColumn]) -> [Lane] {
    var lanes: [String: Lane] = [:]
    for column in columns {
      for card in column.cards {
        let key = laneKey(card)
        var lane = lanes[key] ?? Lane(id: key)
        lane.slots[column.id, default: []].append(card)
        lane.count += 1
        lane.latest = max(lane.latest, card.activityAt)
        lanes[key] = lane
      }
    }
    if board.lanes == .none {
      return [lanes[""] ?? Lane(id: "")]
    }
    return lanes.values.sorted { $0.latest > $1.latest }
  }

  private func laneKey(_ card: BoardCard) -> String {
    let repo = card.lead.repo
    switch board.lanes {
    case .none:
      return ""
    case .repository:
      return repo
    case .owner:
      // GitLab nests groups: the owner is everything above the project.
      let parts = repo.split(separator: "/")
      return parts.count > 1 ? parts.dropLast().joined(separator: "/") : repo
    }
  }

  // MARK: Pieces

  private func header(_ column: DrawnColumn) -> ColumnHeaderRow.Header {
    ColumnHeaderRow.Header(
      id: column.id,
      name: column.name,
      count: column.cards.count,
      quiet: column.kind != .column,
      help: headerHelp(column)
    )
  }

  private func headerHelp(_ column: DrawnColumn) -> String {
    switch column.kind {
    case .column:
      board.columns.first { $0.id == column.id }?.filter.isEmpty == true
        ? "Filled by hand: drag cards here"
        : "Cards the rules place here, and any you drag here"
    case .other:
      "Recent cards no column takes"
    case .done:
      "Closed and merged in the last \(board.doneDays) days"
    }
  }

  @ViewBuilder
  private func laneView(_ lane: Lane, columns: [DrawnColumn]) -> some View {
    let collapsed = collapsedLanes.contains(lane.id)
    VStack(alignment: .leading, spacing: 6) {
      if board.lanes != .none {
        Button {
          withAnimation(.snappy(duration: 0.2)) {
            if collapsed {
              collapsedLanes.remove(lane.id)
            } else {
              collapsedLanes.insert(lane.id)
            }
          }
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "chevron.right")
              .font(.system(size: 9, weight: .semibold))
              .rotationEffect(.degrees(collapsed ? 0 : 90))
              .foregroundStyle(.secondary)
            Text(lane.id.isEmpty ? "No repository" : lane.id)
              .font(.app(.callout, weight: .medium))
            Text("\(lane.count)")
              .font(.app(.caption))
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
        .modifier(StickToLeadingEdge(scroll: scroll))
      }
      if !collapsed {
        // Sized to the row's tallest slot, which every filled slot then
        // stretches to: a row reads as a row, and without lanes every
        // column runs as long as the longest.
        HStack(alignment: .top, spacing: columnGap) {
          ForEach(columns) { column in
            cell(column, cards: lane.slots[column.id] ?? [], lane: lane.id)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func cell(_ column: DrawnColumn, cards: [BoardCard], lane: String) -> some View {
    let key = "\(lane)|\(column.id)"
    let droppable = column.kind == .column
    // Without lanes the one row of slots runs at least the pane's height,
    // so a column reads as a column and a drop lands anywhere in it; with
    // lanes every slot of a row takes the row's height, empty ones too.
    let stretch = board.lanes == .none ? max(0, laneViewport - 16) : 0
    let expanded = expandedSlots.contains(key)
    let shown = expanded ? cards : Array(cards.prefix(slotCardLimit))
    return VStack(spacing: 8) {
      ForEach(shown) { card in
        cardView(card)
      }
      if cards.count > slotCardLimit {
        Button(expanded ? "Show Fewer" : "Show All \(cards.count)") {
          if expanded {
            expandedSlots.remove(key)
          } else {
            expandedSlots.insert(key)
          }
        }
        .buttonStyle(.link)
        .font(.app(.caption, weight: .medium))
        .padding(.vertical, 4)
      }
    }
    .padding(6)
    .frame(width: columnWidth, alignment: .top)
    .frame(minHeight: max(44, stretch), maxHeight: .infinity, alignment: .top)
    .background(Palette.boardColumn, in: RoundedRectangle(cornerRadius: 12))
    .contentShape(Rectangle())
    .overlay {
      if dropTarget == key {
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(Color.accentColor, lineWidth: 2)
      }
    }
    .dropDestination(for: String.self) { ids, _ in
      guard droppable else {
        return false
      }
      for id in ids {
        if let card = placement.byId[id] {
          model.pin(card, to: column.id, on: board.id)
        }
      }
      return true
    } isTargeted: { hovering in
      if hovering, droppable {
        dropTarget = key
      } else if dropTarget == key {
        dropTarget = nil
      }
    }
  }

  private func cardView(_ card: BoardCard) -> some View {
    // The faces come the way a preview's do, through the account the
    // card's lead notification came through.
    let faces = model.bodyImages(for: card.lead)
    return BoardCardView(
      card: card,
      now: model.now,
      selected: model.selectedCardId == card.id,
      pinned: placement.pinned.contains(card.id),
      showsRepo: board.lanes != .repository
    )
    .equatable()
    .environment(\.bodyImages, faces)
    .contentShape(RoundedRectangle(cornerRadius: 9))
    .onTapGesture {
      // The second click of a double-click is the browser's, not a toggle.
      guard (NSApp.currentEvent?.clickCount ?? 1) < 2 else {
        return
      }
      // Clicking the card already open puts its preview away. The
      // inspector slides, as it does from its toolbar toggle.
      withAnimation {
        if model.selectedCardId == card.id, model.cardPreviewShown {
          model.cardPreviewShown = false
        } else {
          model.selectedCardId = card.id
          model.cardPreviewShown = true
        }
      }
    }
    // Alongside the single click, so selecting never waits out the
    // double-click interval.
    .simultaneousGesture(TapGesture(count: 2).onEnded {
      model.openThread(card.items.map(\.id))
    })
    .draggable(card.id) {
      BoardCardView(card: card, now: model.now, selected: false, pinned: false, showsRepo: true)
        .environment(\.bodyImages, faces)
        .frame(width: columnWidth - 12)
    }
    .contextMenu {
      cardMenu(card)
    }
  }

  @ViewBuilder
  private func cardMenu(_ card: BoardCard) -> some View {
    Button("Open in \(card.lead.provider.displayName)") {
      model.openThread(card.items.map(\.id))
    }
    Button("Mark as Read") {
      model.markRead(Set(card.items.map(\.id)))
    }
    .disabled(!card.unread)
    Divider()
    Menu("Move To") {
      ForEach(board.columns) { column in
        Button(column.name) {
          model.pin(card, to: column.id, on: board.id)
        }
      }
    }
    if placement.pinned.contains(card.id) {
      Button("Let the Rules Place It") {
        model.pin(card, to: nil, on: board.id)
      }
    }
  }
}

/// Where the grid is scrolled, shared with the views that follow it. Only
/// the sideways offset is observed — the header row and lane titles move
/// with it — so scrolling redraws them and nothing else.
@MainActor
@Observable
private final class BoardScroll {
  /// How far the grid has scrolled sideways from rest.
  var offset: CGFloat = 0
  /// The AppKit scroll view behind the board's ScrollView. A pan moves its
  /// clip view directly, as the scroll wheel does: going through SwiftUI's
  /// scroll position redraws the whole board on every step of the drag.
  @ObservationIgnored weak var view: NSScrollView?
  /// Where the clip view stood when the pan began, while one is under way.
  @ObservationIgnored private var panStart: NSPoint?
  /// A viewport height waiting for a resize to settle.
  @ObservationIgnored private var pendingViewport: Task<Void, Never>?
  @ObservationIgnored private var viewportKnown = false

  func track(_ geometry: ScrollGeometry) {
    let sideways = geometry.contentOffset.x + geometry.contentInsets.leading
    if offset != sideways {
      offset = sideways
    }
  }

  /// Moves the grid with the pointer, `translation` from where it went down.
  func pan(by translation: CGSize) {
    guard let view, let document = view.documentView else {
      return
    }
    let clip = view.contentView
    if panStart == nil {
      panStart = clip.bounds.origin
      NSCursor.closedHand.push()
    }
    guard let start = panStart else {
      return
    }
    let dy = document.isFlipped ? -translation.height : translation.height
    let target = NSRect(origin: NSPoint(x: start.x - translation.width, y: start.y + dy), size: clip.bounds.size)
    clip.setBoundsOrigin(clip.constrainBoundsRect(target).origin)
    view.reflectScrolledClipView(clip)
  }

  /// Hands the height on at once the first time, then only after it holds
  /// still for a moment.
  func settle(_ height: CGFloat, apply: @escaping @MainActor (CGFloat) -> Void) {
    pendingViewport?.cancel()
    guard viewportKnown else {
      viewportKnown = true
      apply(height)
      return
    }
    pendingViewport = Task {
      try? await Task.sleep(for: .milliseconds(150))
      if !Task.isCancelled {
        apply(height)
      }
    }
  }

  func endPan() {
    if panStart != nil {
      panStart = nil
      NSCursor.pop()
    }
  }
}

/// Hands back the NSScrollView its content sits in, once it is in one.
private struct EnclosingScrollViewReader: NSViewRepresentable {
  let found: (NSScrollView) -> Void

  func makeNSView(context: Context) -> NSView {
    ReaderView(found: found)
  }

  func updateNSView(_ view: NSView, context: Context) {}

  private final class ReaderView: NSView {
    let found: (NSScrollView) -> Void

    init(found: @escaping (NSScrollView) -> Void) {
      self.found = found
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("not used")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window != nil, let scrollView = enclosingScrollView {
        found(scrollView)
      }
    }

    // Draws nothing and takes no clicks: the board's own views do.
    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
    }
  }
}

/// Holds a lane's title at the visible leading edge while the grid scrolls
/// sideways, so a row never loses its name.
private struct StickToLeadingEdge: ViewModifier {
  let scroll: BoardScroll

  func body(content: Content) -> some View {
    content.offset(x: max(0, scroll.offset))
  }
}

/// The column headers, floating over the grid in glass: lined up with
/// their columns at the grid's sideways offset, and clipped to the pane —
/// which runs on under the sidebar, so they pass beneath it with the cards.
private struct ColumnHeaderRow: View {
  struct Header: Identifiable {
    let id: String
    let name: String
    let count: Int
    /// Other and Done: the board's catch-alls, set apart from its columns.
    let quiet: Bool
    let help: String
  }

  let columns: [Header]
  /// Where the first label rests, from the row's leading edge.
  let leading: CGFloat
  let scroll: BoardScroll

  var body: some View {
    // A clear band of the bar's width holds the labels as an overlay: the
    // row runs as wide as the grid, and laid out directly it would widen
    // the bar — and the pane — to match. Unclipped: the bar ends at the
    // sidebar's and the inspector's edges, and the labels pass on under
    // them with the cards.
    Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: headerBand)
      .overlay(alignment: .bottomLeading) {
        labels
          .fixedSize()
          .offset(x: leading - scroll.offset)
          .padding(.bottom, headerGap)
      }
  }

  private var labels: some View {
    GlassEffectContainer(spacing: columnGap) {
      HStack(spacing: columnGap) {
        ForEach(columns) { column in
          HStack(spacing: 6) {
            Text(column.name)
              .font(.app(.callout, weight: .semibold))
              .foregroundStyle(column.quiet ? .secondary : .primary)
            Text("\(column.count)")
              .font(.app(.caption, weight: .medium))
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .glassEffect(.regular, in: .capsule)
          .help(column.help)
          .frame(width: columnWidth, alignment: .leading)
        }
      }
    }
  }
}
