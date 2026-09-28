// The Inboxes page's tree editor: the sidebar layout as an NSOutlineView
// with drag and drop. AppKit's outline view, not a SwiftUI List, because a
// List only reorders within one level — moving an inbox into or out of a
// folder needs the outline view's drop validation (target folder, child
// index, "never into itself"), which SwiftUI offers no equivalent for on
// macOS. Rows host SwiftUI content; every drop, rename, and switch flip is
// handed back as one layout edit.

import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
  /// A dragged node, by id.
  static let sidebarNode = NSPasteboard.PasteboardType("dev.majordomo.sidebar-node")
}

/// What one row shows: a node of the layout with its presentation resolved.
struct SidebarOutlineEntry: Identifiable, Hashable {
  enum Kind: Hashable {
    case inbox
    case folder
  }

  let id: String
  let kind: Kind
  let name: String
  let symbol: String
  /// The glyph's tint; folders draw a plain symbol instead.
  let tint: LabelTint
  let hidden: Bool
  /// The catch-all: neither dragged nor hidden.
  let isCatchAll: Bool
  var children: [SidebarOutlineEntry] = []
}

struct SidebarOutlineView: NSViewRepresentable {
  let entries: [SidebarOutlineEntry]
  @Binding var selection: String?
  /// A folder id to start editing the name of — the one just created.
  let editingFolder: String?
  let onMove: (_ id: String, _ parent: String?, _ index: Int) -> Void
  let onRename: (_ id: String, _ name: String) -> Void
  let onSetVisible: (_ id: String, _ visible: Bool) -> Void

  func makeNSView(context: Context) -> NSScrollView {
    let outline = NSOutlineView()
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("node"))
    column.resizingMask = .autoresizingMask
    outline.addTableColumn(column)
    outline.outlineTableColumn = column
    outline.headerView = nil
    outline.rowHeight = 24
    // .inset would add a wide margin of its own; .plain plus a modest
    // indent keeps a row's glyph near the card's edge.
    outline.style = .plain
    outline.indentationPerLevel = 10
    outline.allowsEmptySelection = true
    outline.allowsMultipleSelection = false
    // The outline follows the clip view's width and its one column follows
    // the outline, so a row's trailing switch stays inside the visible
    // area instead of under the scroller.
    outline.autoresizingMask = [.width, .height]
    outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    outline.registerForDraggedTypes([.sidebarNode])
    outline.setDraggingSourceOperationMask(.move, forLocal: true)
    outline.dataSource = context.coordinator
    outline.delegate = context.coordinator
    context.coordinator.outline = outline

    let scroll = NSScrollView()
    scroll.documentView = outline
    scroll.hasVerticalScroller = true
    // An overlay scroller floats over the rows instead of reserving a
    // column of its own, so the switches sit near the card's edge.
    scroll.scrollerStyle = .overlay
    scroll.borderType = .bezelBorder
    scroll.drawsBackground = true
    // No automatic margin: the rows carry their own, so the list starts
    // where the card does.
    scroll.automaticallyAdjustsContentInsets = false
    scroll.contentInsets = NSEdgeInsetsZero
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.apply(self)
    (scroll.documentView as? NSOutlineView)?.sizeLastColumnToFit()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  /// One node as the outline view holds it: a class, since the outline
  /// view tracks items by identity across reloads.
  final class Item {
    let entry: SidebarOutlineEntry
    weak var parent: Item?
    var children: [Item] = []

    init(_ entry: SidebarOutlineEntry, parent: Item?) {
      self.entry = entry
      self.parent = parent
      children = entry.children.map { Item($0, parent: self) }
    }

    var id: String { entry.id }
    var isFolder: Bool { entry.kind == .folder }

    /// Whether `other` is this item or sits somewhere inside it.
    func contains(_ other: Item) -> Bool {
      other === self || children.contains { $0.contains(other) }
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var outline: NSOutlineView?
    private var view: SidebarOutlineView?
    private var roots: [Item] = []
    /// Items by id, so a reload can re-expand and re-select what was.
    private var byId: [String: Item] = [:]
    /// Folder ids the user collapsed; everything else stays expanded.
    private var collapsed: Set<String> = []
    /// True while a reload re-applies the selection, so the outline's
    /// selection callback doesn't feed it back as a user change.
    private var reloading = false

    /// Rebuilds the item tree from the view's entries and reloads,
    /// keeping expansion and selection. Same entries: no reload.
    func apply(_ view: SidebarOutlineView) {
      let previous = self.view
      self.view = view
      guard let outline else {
        return
      }
      if previous?.entries != view.entries {
        roots = view.entries.map { Item($0, parent: nil) }
        byId = [:]
        index(roots)
        reloading = true
        outline.reloadData()
        expandAll(roots)
        reloading = false
      }
      syncSelection()
    }

    private func index(_ items: [Item]) {
      for item in items {
        byId[item.id] = item
        index(item.children)
      }
    }

    private func expandAll(_ items: [Item]) {
      for item in items where item.isFolder {
        if !collapsed.contains(item.id) {
          outline?.expandItem(item)
        }
        expandAll(item.children)
      }
    }

    private func syncSelection() {
      guard let outline, let view else {
        return
      }
      let wanted = view.selection.flatMap { byId[$0] }.map { outline.row(forItem: $0) } ?? -1
      guard wanted != outline.selectedRow else {
        return
      }
      reloading = true
      if wanted >= 0 {
        outline.selectRowIndexes(IndexSet(integer: wanted), byExtendingSelection: false)
      } else {
        outline.deselectAll(nil)
      }
      reloading = false
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
      ((item as? Item)?.children ?? roots).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
      ((item as? Item)?.children ?? roots)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
      (item as? Item)?.isFolder == true
    }

    // MARK: Rows

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
      guard let item = item as? Item, let view else {
        return nil
      }
      let row = SidebarOutlineRow(
        entry: item.entry,
        startsEditing: item.isFolder && view.editingFolder == item.id,
        onRename: { name in view.onRename(item.id, name) },
        onSetVisible: { visible in view.onSetVisible(item.id, visible) }
      )
      // Table cells are placed by frame; the hosting view must fill the
      // cell rather than size itself to its content.
      let host = NSHostingView(rootView: row)
      host.autoresizingMask = [.width, .height]
      return host
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
      guard !reloading, let outline else {
        return
      }
      let selected = (outline.item(atRow: outline.selectedRow) as? Item)?.id
      // The binding is SwiftUI state; write it outside the outline view's
      // own selection pass.
      DispatchQueue.main.async { [weak self] in
        self?.view?.selection = selected
      }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
      if let item = notification.userInfo?["NSObject"] as? Item {
        collapsed.insert(item.id)
      }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
      if let item = notification.userInfo?["NSObject"] as? Item {
        collapsed.remove(item.id)
      }
    }

    // MARK: Drag and drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
      guard let item = item as? Item, !item.entry.isCatchAll else {
        return nil
      }
      let pasteboard = NSPasteboardItem()
      pasteboard.setString(item.id, forType: .sidebarNode)
      return pasteboard
    }

    private func draggedItem(_ info: NSDraggingInfo) -> Item? {
      info.draggingPasteboard.string(forType: .sidebarNode).flatMap { byId[$0] }
    }

    /// Where a drop lands: a folder's children (or the top level) at an
    /// index. Dropping onto an inbox row means "after it, at its level";
    /// onto a folder means "inside, at the end". Nothing lands above the
    /// catch-all, and a folder never lands inside itself.
    func outlineView(
      _ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
      proposedChildIndex index: Int
    ) -> NSDragOperation {
      guard let dragged = draggedItem(info) else {
        return []
      }
      var target = item as? Item
      var childIndex = index
      if let onto = target, index == NSOutlineViewDropOnItemIndex {
        if onto.isFolder {
          childIndex = onto.children.count
        } else {
          let siblings = onto.parent?.children ?? roots
          childIndex = (siblings.firstIndex { $0 === onto } ?? -1) + 1
          target = onto.parent
        }
      }
      if target == nil, childIndex == 0 {
        childIndex = 1
      }
      if let target, dragged.contains(target) {
        return []
      }
      outlineView.setDropItem(target, dropChildIndex: childIndex)
      return .move
    }

    func outlineView(
      _ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int
    ) -> Bool {
      guard let dragged = draggedItem(info), let view else {
        return false
      }
      let target = item as? Item
      // The layout indexes the tree AFTER the node is taken out; a move
      // downward within the same parent shifts by one.
      var childIndex = index
      let siblings = target?.children ?? roots
      if dragged.parent === target, let from = siblings.firstIndex(where: { $0 === dragged }), from < index {
        childIndex -= 1
      }
      view.onMove(dragged.id, target?.id, childIndex)
      return true
    }
  }
}

/// One row: the node's glyph and name — a folder's name edits in place —
/// and, for an inbox, its visibility switch.
private struct SidebarOutlineRow: View {
  let entry: SidebarOutlineEntry
  let startsEditing: Bool
  let onRename: (String) -> Void
  let onSetVisible: (Bool) -> Void

  @FocusState private var editing: Bool

  var body: some View {
    HStack(spacing: 7) {
      if entry.kind == .folder {
        Image(systemName: entry.symbol)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(width: 18)
        CommitTextField("Folder name", text: entry.name) { name in
          onRename(name.isEmpty ? "Folder" : name)
        }
        .textFieldStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .focused($editing)
        .onAppear {
          if startsEditing {
            editing = true
          }
        }
      } else {
        LabelGlyph(symbol: entry.symbol, tint: entry.tint, size: 18)
        Text(entry.name)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(entry.hidden ? .secondary : .primary)
        Spacer()
        Toggle("Shown", isOn: Binding(get: { !entry.hidden }, set: { onSetVisible($0) }))
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .disabled(entry.isCatchAll)
          .help(entry.isCatchAll ? "Recent is the catch-all and always shows" : "Show in the sidebar")
      }
    }
    .padding(.leading, 2)
    // Enough that an overlay scroller never lands on the switch.
    .padding(.trailing, 4)
    .frame(height: 24)
  }
}
