// How the inbox splits into named buckets. The buckets themselves come from
// the provider specs — the core defines only the catch-all, the merging
// rules, and what the sidebar selects.

import Foundation

/// The core's catch-all bucket: everything, newest first. Always present,
/// always first, never hideable.
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
func byNewest(_ items: [InboxItem]) -> [InboxItem] {
  items.sorted { $0.updatedAt > $1.updatedAt }
}

/// What the sidebar selects: a category id, optionally scoped to one
/// account — nil is the aggregated "All Inboxes" section.
struct SidebarSelection: Hashable, Sendable {
  var account: AccountId?
  var category: String
}
