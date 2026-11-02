// The fields the pills under the toolbar narrow the inbox by: one author,
// provider, or repository at a time. Like the search and date filters they
// narrow the list and leave the sidebar badges alone.

import Foundation

/// One field the inbox can be narrowed by, picked from a pill's menu.
enum Facet: String, CaseIterable, Identifiable, Sendable {
  case author
  case provider
  case repository

  var id: String { rawValue }

  /// The pill's label while nothing is picked.
  var title: String {
    switch self {
    case .author: "Author"
    case .provider: "Provider"
    case .repository: "Repository"
    }
  }

  /// The item's value for this facet; nil when it has none (an item whose
  /// provider never reported an author).
  func value(of item: InboxItem) -> String? {
    let value = switch self {
    case .author: item.author
    case .provider: item.provider.rawValue
    case .repository: item.repo
    }
    return value?.isEmpty == false ? value : nil
  }
}

/// Items matching every pick except `except`'s — the facet whose own menu
/// is being filled, so it lists what the other pills leave.
func matchingFacets(_ items: [InboxItem], _ picks: [Facet: String], except: Facet? = nil) -> [InboxItem] {
  let active = picks.filter { $0.key != except }
  guard !active.isEmpty else { return items }
  return items.filter { item in
    active.allSatisfy { facet, value in facet.value(of: item) == value }
  }
}

/// One pill's menu: the values on offer, and the one picked.
struct FacetChoices: Identifiable, Sendable {
  let facet: Facet
  /// Distinct, in menu order.
  let values: [String]
  let picked: String?

  var id: Facet { facet }
}

/// The values a facet takes across these items, sorted for a menu. The
/// pick is always among them, even once nothing carries it any more, so
/// the menu still shows it checked and it can be cleared.
func facetChoices(_ facet: Facet, in items: [InboxItem], picked: String?) -> FacetChoices {
  var values = Set(items.compactMap(facet.value(of:)))
  if let picked {
    values.insert(picked)
  }
  let sorted = values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  return FacetChoices(facet: facet, values: sorted, picked: picked)
}
