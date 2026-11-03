// The fields the toolbar's filter narrows the inbox — or a board — by: one
// author, provider, or repository at a time. Like the search they narrow
// what shows and leave the sidebar badges alone.

import Foundation

/// One field the inbox can be narrowed by, picked from the filter's menu.
enum Facet: String, CaseIterable, Identifiable, Sendable {
  case author
  case provider
  case repository

  var id: String { rawValue }

  /// The facet's submenu while nothing is picked.
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

  /// How a value reads in the filter's menu and the window's subtitle.
  func display(_ value: String) -> String {
    switch self {
    case .author: "@\(value)"
    case .provider: ProviderId(rawValue: value)?.displayName ?? value
    case .repository: value
    }
  }
}

/// What the filter narrows: a notification, or a board's card.
protocol FacetSubject {
  /// The value for this facet; nil when there is none.
  func facetValue(_ facet: Facet) -> String?
}

extension InboxItem: FacetSubject {
  func facetValue(_ facet: Facet) -> String? {
    facet.value(of: self)
  }
}

extension BoardCard: FacetSubject {
  /// A card's values are its target's, as the card shows them.
  func facetValue(_ facet: Facet) -> String? {
    facet.value(of: presentedItem)
  }
}

/// A row the filter's menu counts: a thread in the inbox, a card on a
/// board.
protocol FacetRow {
  /// Every value the row carries for this facet. A thread's notifications
  /// can come from more than one author.
  func carriedValues(_ facet: Facet) -> Set<String>
}

extension InboxThread: FacetRow {
  func carriedValues(_ facet: Facet) -> Set<String> {
    Set(items.compactMap { $0.facetValue(facet) })
  }
}

extension BoardCard: FacetRow {
  func carriedValues(_ facet: Facet) -> Set<String> {
    facetValue(facet).map { [$0] } ?? []
  }
}

/// One value a facet's menu offers, with how many of the rows in view
/// carry it.
struct FacetValue: Equatable, Identifiable, Sendable {
  let value: String
  let count: Int

  var id: String { value }
}

/// The facets the filter's menu offers, given the providers the accounts
/// are on. Provider narrows only across more than one: it is offered while
/// the accounts span several, or while it holds a pick, which must stay
/// clearable. It is the one way to narrow an inbox to one provider's items
/// — every inbox holds every account's.
func offeredFacets(providers: Set<ProviderId>, picks: [Facet: String]) -> [Facet] {
  Facet.allCases.filter { facet in
    facet != .provider || providers.count > 1 || picks[facet] != nil
  }
}

/// Subjects matching every pick except `except`'s — the facet whose own
/// menu is being filled, so it lists what the other picks leave.
func matchingFacets<Subject: FacetSubject>(
  _ subjects: [Subject], _ picks: [Facet: String], except: Facet? = nil
) -> [Subject] {
  let active = picks.filter { $0.key != except }
  guard !active.isEmpty else { return subjects }
  return subjects.filter { subject in
    active.allSatisfy { facet, value in subject.facetValue(facet) == value }
  }
}

/// The values a facet takes across these rows, distinct and sorted for the
/// facet's menu, each counting the rows that carry it. The pick is always
/// among them, at no rows once nothing carries it any more, so the menu
/// still shows it checked and it can be cleared.
func facetValues(_ facet: Facet, in rows: [some FacetRow], picked: String?) -> [FacetValue] {
  var counts: [String: Int] = [:]
  for row in rows {
    for value in row.carriedValues(facet) {
      counts[value, default: 0] += 1
    }
  }
  if let picked, counts[picked] == nil {
    counts[picked] = 0
  }
  return counts
    .map { FacetValue(value: $0.key, count: $0.value) }
    .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
}
