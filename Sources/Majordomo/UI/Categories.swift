// How the inbox splits into named buckets. The buckets themselves come from
// the provider specs — the core defines only the catch-all, the merging
// rules, and what the sidebar selects.

import Foundation

/// The core's catch-all bucket: everything. Always present, always first,
/// never hideable.
let recentCategory = CategorySpec(id: "recent", label: "Recent", symbol: "tray.full", order: 0) { _ in
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

/// The aggregated bucket list ("All Inboxes"): every provider's categories
/// merged by id — the first registration's wording wins — with the catch-all
/// in front.
let aggregatedCategories: [CategorySpec] = {
  var seen: Set<String> = [recentCategory.id]
  var merged = [recentCategory]
  for spec in providerSpecs {
    for category in spec.categories where !seen.contains(category.id) {
      seen.insert(category.id)
      merged.append(category)
    }
  }
  return merged.sorted { $0.order < $1.order }
}()

/// One account's bucket list, in the provider's own wording.
func accountCategories(for provider: ProviderId) -> [CategorySpec] {
  ([recentCategory] + spec(for: provider).categories).sorted { $0.order < $1.order }
}

func categorize(_ items: [InboxItem], into specs: [CategorySpec]) -> [Category] {
  specs.map { spec in
    Category(spec: spec, items: items.filter(spec.matches))
  }
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

/// What the sidebar selects: a category id, optionally scoped to one
/// account — nil is the aggregated "All Inboxes" section.
struct SidebarSelection: Hashable, Sendable {
  var account: AccountId?
  var category: String
}
