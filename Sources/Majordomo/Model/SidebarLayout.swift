// The sidebar's layout: an ordered tree of inboxes and folders, edited on
// the Inboxes settings page. One layout serves All Inboxes and every
// account section — labels are the user's and built-in buckets only differ
// in wording per provider. Position and visibility are separate: every
// inbox keeps its place in the tree, and hiding one just skips it when the
// sidebar is drawn, so nothing is lost when it is shown again.

import Foundation

/// One row of the tree: an inbox (the catch-all, a built-in label, or a
/// user label, by id) or a folder of rows.
enum SidebarNode: Hashable, Sendable, Identifiable {
  case inbox(String)
  case folder(SidebarFolder)

  var id: String {
    switch self {
    case .inbox(let id): id
    case .folder(let folder): folder.id
    }
  }
}

/// A collapsible group in the sidebar. Not an inbox itself — selecting it
/// selects nothing — just a place to put inboxes.
struct SidebarFolder: Hashable, Sendable, Identifiable {
  var id: String
  var name: String
  var symbol: String = "folder"
  var children: [SidebarNode] = []
}

/// The catch-all inbox ("Recent") — always first, never hidden.
let catchAllInboxId = "recent"

struct SidebarLayout: Codable, Hashable, Sendable {
  var nodes: [SidebarNode] = []
  /// Inboxes that keep their place in the tree but are not drawn.
  var hidden: Set<String> = []

  /// The folder new labels land in until the user moves them.
  static let labelsFolderId = "labels"

  /// The layout a fresh store starts from: the catch-all, the built-in
  /// buckets in their order, and a "Labels" folder holding the user's.
  static func standard(catchAll: String, builtins: [String], labels: [String]) -> SidebarLayout {
    var nodes: [SidebarNode] = [.inbox(catchAll)] + builtins.map(SidebarNode.inbox)
    nodes.append(.folder(SidebarFolder(id: labelsFolderId, name: "Labels", symbol: "tag", children: labels.map(SidebarNode.inbox))))
    return SidebarLayout(nodes: nodes)
  }

  // MARK: Reading

  /// Every inbox id in the tree, in display order, folders flattened.
  var inboxIds: [String] {
    Self.inboxIds(in: nodes)
  }

  private static func inboxIds(in nodes: [SidebarNode]) -> [String] {
    nodes.flatMap { node -> [String] in
      switch node {
      case .inbox(let id): [id]
      case .folder(let folder): inboxIds(in: folder.children)
      }
    }
  }

  func contains(inbox id: String) -> Bool {
    inboxIds.contains(id)
  }

  func isVisible(_ id: String) -> Bool {
    !hidden.contains(id)
  }

  /// The folder ids, in display order.
  var folderIds: [String] {
    Self.folders(in: nodes).map(\.id)
  }

  private static func folders(in nodes: [SidebarNode]) -> [SidebarFolder] {
    nodes.flatMap { node -> [SidebarFolder] in
      guard case .folder(let folder) = node else {
        return []
      }
      return [folder] + folders(in: folder.children)
    }
  }

  // MARK: Editing

  mutating func setHidden(_ id: String, _ isHidden: Bool) {
    if isHidden {
      hidden.insert(id)
    } else {
      hidden.remove(id)
    }
  }

  /// Puts an inbox at the end of a folder (nil: the top level). An inbox
  /// already in the tree moves there.
  mutating func append(inbox id: String, toFolder folderId: String?) {
    remove(node: id)
    insert(.inbox(id), into: folderId, at: nil)
  }

  /// Puts an inbox at the end of the "Labels" folder when there is one,
  /// else at the top level — where a new label lands.
  mutating func appendLabel(_ id: String) {
    append(inbox: id, toFolder: folderIds.contains(Self.labelsFolderId) ? Self.labelsFolderId : nil)
  }

  /// Adds an empty folder at the end of the top level.
  mutating func addFolder(_ folder: SidebarFolder) {
    nodes.append(.folder(folder))
  }

  mutating func rename(folder id: String, to name: String) {
    update(folder: id) { $0.name = name }
  }

  mutating func setSymbol(folder id: String, _ symbol: String) {
    update(folder: id) { $0.symbol = symbol }
  }

  /// Removes a folder; its children take its place, so no inbox is lost.
  mutating func dissolve(folder id: String) {
    nodes = Self.dissolving(id, in: nodes)
  }

  private static func dissolving(_ id: String, in nodes: [SidebarNode]) -> [SidebarNode] {
    nodes.flatMap { node -> [SidebarNode] in
      guard case .folder(var folder) = node else {
        return [node]
      }
      if folder.id == id {
        return folder.children
      }
      folder.children = dissolving(id, in: folder.children)
      return [.folder(folder)]
    }
  }

  /// Moves a node (inbox or folder) to `index` among the children of
  /// `parent` (nil: the top level); an index past the end appends. A folder
  /// never moves into itself or its own descendants — such a move is
  /// ignored. Indices refer to the tree AFTER the node is taken out.
  mutating func move(node id: String, toFolder parent: String?, at index: Int?) {
    guard let node = self.node(id) else {
      return
    }
    if case .folder(let folder) = node, let parent,
       parent == folder.id || Self.folders(in: folder.children).contains(where: { $0.id == parent }) {
      return
    }
    remove(node: id)
    insert(node, into: parent, at: index)
  }

  /// Drops an inbox or folder (with its contents) from the tree.
  mutating func remove(node id: String) {
    nodes = Self.removing(id, from: nodes)
  }

  private static func removing(_ id: String, from nodes: [SidebarNode]) -> [SidebarNode] {
    nodes.compactMap { node in
      guard node.id != id else {
        return nil
      }
      guard case .folder(var folder) = node else {
        return node
      }
      folder.children = removing(id, from: folder.children)
      return .folder(folder)
    }
  }

  func node(_ id: String) -> SidebarNode? {
    Self.node(id, in: nodes)
  }

  private static func node(_ id: String, in nodes: [SidebarNode]) -> SidebarNode? {
    for node in nodes {
      if node.id == id {
        return node
      }
      if case .folder(let folder) = node, let found = self.node(id, in: folder.children) {
        return found
      }
    }
    return nil
  }

  private mutating func insert(_ node: SidebarNode, into parent: String?, at index: Int?) {
    guard let parent else {
      nodes.insert(node, at: min(index ?? nodes.count, nodes.count))
      return
    }
    update(folder: parent) { folder in
      folder.children.insert(node, at: min(index ?? folder.children.count, folder.children.count))
    }
  }

  private mutating func update(folder id: String, _ change: (inout SidebarFolder) -> Void) {
    nodes = Self.updating(id, in: nodes, change)
  }

  private static func updating(
    _ id: String, in nodes: [SidebarNode], _ change: (inout SidebarFolder) -> Void
  ) -> [SidebarNode] {
    nodes.map { node in
      guard case .folder(var folder) = node else {
        return node
      }
      if folder.id == id {
        change(&folder)
      } else {
        folder.children = updating(id, in: folder.children, change)
      }
      return .folder(folder)
    }
  }

  // MARK: Keeping up with the labels

  /// The layout with inboxes that no longer exist dropped and ones new
  /// since it was made added: built-ins and the user's own inboxes at the
  /// end of the top level, labels in the "Labels" folder. Hidden ids that
  /// vanished are forgotten.
  func reconciled(catchAll: String, builtins: [String], inboxes: [String] = [], labels: [String]) -> SidebarLayout {
    var layout = self
    let existing = Set([catchAll] + builtins + inboxes + labels)
    for id in layout.inboxIds where !existing.contains(id) {
      layout.remove(node: id)
    }
    layout.hidden = layout.hidden.intersection(existing)
    let present = Set(layout.inboxIds)
    if !present.contains(catchAll) {
      layout.nodes.insert(.inbox(catchAll), at: 0)
    }
    for id in builtins + inboxes where !present.contains(id) {
      layout.append(inbox: id, toFolder: nil)
    }
    for id in labels where !present.contains(id) {
      layout.appendLabel(id)
    }
    return layout
  }
}

// MARK: - JSON shape

// Nodes encode as {"inbox": "<id>"} or {"folder": {…}} — readable in the
// store file and stable if either case grows fields.
extension SidebarNode: Codable {
  private enum CodingKeys: String, CodingKey {
    case inbox, folder
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let id = try container.decodeIfPresent(String.self, forKey: .inbox) {
      self = .inbox(id)
    } else {
      self = .folder(try container.decode(SidebarFolder.self, forKey: .folder))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .inbox(let id): try container.encode(id, forKey: .inbox)
    case .folder(let folder): try container.encode(folder, forKey: .folder)
    }
  }
}

extension SidebarFolder: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, name, symbol, children
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "folder"
    children = try container.decodeIfPresent([SidebarNode].self, forKey: .children) ?? []
  }
}
