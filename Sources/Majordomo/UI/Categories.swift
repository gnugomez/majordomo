// How the inbox splits into named buckets: the catch-all, then one folder
// per label — the providers' built-in ones and the user's own. The core
// defines only the catch-all, how labels list per section, and what the
// sidebar selects.

import Foundation

/// The core's catch-all bucket: everything. Always present, always first,
/// never hideable.
let recentCategory = CategorySpec(id: catchAllInboxId, label: "Recent", symbol: "tray.full", order: 0) { _ in
  true
}

/// A bucket filled with the items that match it.
struct Category: Identifiable, Sendable {
  let spec: CategorySpec
  var items: [InboxItem]

  var id: String { spec.id }
  var label: String { spec.label }
  var symbol: String { spec.symbol }
}

/// The sidebar's buckets for a label list: the catch-all first, then one
/// folder per label holding the items that carry it. A folder's id is its
/// label's id, so the hidden-inbox setting addresses either. The accent
/// tint is the sidebar's own glyph color and draws as such.
func categories(for labels: [InboxLabel]) -> [CategorySpec] {
  [recentCategory] + labels.enumerated().map { index, label in
    let id = label.id
    return CategorySpec(
      id: id,
      label: label.name,
      symbol: label.symbol,
      order: index + 1,
      tint: label.tint == .accent ? nil : label.tint,
      labelId: id
    ) { $0.labels.contains(id) }
  }
}

/// Every list and badge in the app comes through here, so this is where a
/// moved item is kept out: a rule that moves rather than copies records
/// the inboxes it hid the item from, and those inboxes skip it — the
/// catch-all included.
func categorize(_ items: [InboxItem], into specs: [CategorySpec]) -> [Category] {
  specs.map { spec in
    Category(spec: spec, items: items.filter { spec.matches($0) && !$0.hiddenFrom.contains(spec.id) })
  }
}

/// One drawn row of a sidebar section: an inbox with its items, or a
/// folder with the rows inside it.
enum SidebarRow: Identifiable, Sendable {
  case inbox(Category)
  case folder(SidebarFolder, rows: [SidebarRow])

  var id: String {
    switch self {
    case .inbox(let category): category.id
    case .folder(let folder, _): folder.id
    }
  }

  /// Every inbox in the row, folders flattened, in display order.
  var inboxes: [Category] {
    switch self {
    case .inbox(let category): [category]
    case .folder(_, let rows): rows.flatMap(\.inboxes)
    }
  }
}

/// A section's rows in layout order: each inbox node resolved to its
/// bucket, hidden and unknown inboxes dropped (the catch-all never is), and
/// folders with nothing visible inside dropped with them. The sidebar draws
/// this; the scope resolution selects from its flattening.
func sidebarRows(layout: SidebarLayout, categories: [Category]) -> [SidebarRow] {
  let byId = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
  func rows(for nodes: [SidebarNode]) -> [SidebarRow] {
    nodes.compactMap { node in
      switch node {
      case .inbox(let id):
        guard id == catchAllInboxId || layout.isVisible(id), let category = byId[id] else {
          return nil
        }
        return .inbox(category)
      case .folder(let folder):
        let inside = rows(for: folder.children)
        return inside.isEmpty ? nil : .folder(folder, rows: inside)
      }
    }
  }
  return rows(for: layout.nodes)
}

/// The inboxes a section lets the user select, in layout order.
func visibleCategories(layout: SidebarLayout, categories: [Category]) -> [Category] {
  sidebarRows(layout: layout, categories: categories).flatMap(\.inboxes)
}

/// Unread threads across these rows' inboxes — an item in two of them
/// counts once, so a folder's badge never exceeds what opening its
/// inboxes would show.
func unreadThreadCount(in rows: [SidebarRow]) -> Int {
  var seen = Set<String>()
  let items = rows.flatMap(\.inboxes).flatMap(\.items).filter { seen.insert($0.id).inserted }
  return groupIntoThreads(items).count { !$0.read }
}

/// Newest activity first — the order every list in the app shows items in.
/// Read state never enters the ordering: a row keeps its place when it is
/// read, so nothing shifts under the pointer; the unread dot, the bold
/// title, and the sidebar badges carry the signal instead. Equal times fall
/// back to the id so ties don't reshuffle between syncs.
func inboxOrder(_ items: [InboxItem]) -> [InboxItem] {
  items.sorted { a, b in
    if a.updatedAt != b.updatedAt {
      return a.updatedAt > b.updatedAt
    }
    return a.id < b.id
  }
}

/// Live search over what the inbox shows: every whitespace-separated term
/// must match the title, repo, author, or body, case- and diacritic-
/// insensitively. An empty query passes everything through.
func matchingSearch(_ items: [InboxItem], _ query: String) -> [InboxItem] {
  let terms = searchTerms(query)
  guard !terms.isEmpty else { return items }
  return items.filter { item in
    let fields = [item.title, item.repo, item.author ?? "", item.body ?? ""]
    return terms.allSatisfy { term in
      fields.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
  }
}

/// The toolbar's date filter: a rolling window over an item's last
/// activity. Absent (nil) means any time.
enum ActivityWindow: String, CaseIterable, Identifiable, Sendable {
  case twoDays
  case fiveDays
  case week
  case twoWeeks
  case month

  var id: String { rawValue }

  var label: String {
    switch self {
    case .twoDays: "Last 2 days"
    case .fiveDays: "Last 5 days"
    case .week: "Last week"
    case .twoWeeks: "Last 2 weeks"
    case .month: "Last month"
    }
  }

  /// Rolling, in days — "last month" is 30 of them.
  var days: Int {
    switch self {
    case .twoDays: 2
    case .fiveDays: 5
    case .week: 7
    case .twoWeeks: 14
    case .month: 30
    }
  }
}

/// Items whose last activity falls inside the window; a nil window passes
/// everything through. Stacks with matchingSearch — both narrow the list,
/// neither touches the sidebar badges.
func matchingWindow(_ items: [InboxItem], _ window: ActivityWindow?, now: Date) -> [InboxItem] {
  guard let window else { return items }
  let cutoff = now.addingTimeInterval(-TimeInterval(window.days) * 24 * 60 * 60)
  return items.filter { $0.updatedAt >= cutoff }
}

/// The toolbar's unread filter over threads: the unread ones, plus any
/// holding an item in `kept` — read while the filter showed it, and left
/// where it was rather than taken out from under the pointer. Works on
/// threads, not items, so an unread thread keeps its read members.
func matchingUnread(_ threads: [InboxThread], kept: Set<String>) -> [InboxThread] {
  threads.filter { thread in
    !thread.read || thread.items.contains { kept.contains($0.id) }
  }
}

/// What the sidebar selects: a category id, optionally scoped to one
/// account — nil is the aggregated "All Inboxes" section.
struct SidebarSelection: Hashable, Sendable {
  var account: AccountId?
  var category: String
}
