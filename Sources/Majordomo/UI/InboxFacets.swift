// The fields the toolbar's filter pills narrow the inbox — or a board —
// by: one author, provider, or repository at a time. Like the search and
// date filters they narrow what shows and leave the sidebar badges alone.

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

/// What the pills narrow: a notification, or a board's card.
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

/// Subjects matching every pick except `except`'s — the facet whose own
/// menu is being filled, so it lists what the other pills leave.
func matchingFacets<Subject: FacetSubject>(
  _ subjects: [Subject], _ picks: [Facet: String], except: Facet? = nil
) -> [Subject] {
  let active = picks.filter { $0.key != except }
  guard !active.isEmpty else { return subjects }
  return subjects.filter { subject in
    active.allSatisfy { facet, value in subject.facetValue(facet) == value }
  }
}

/// The values a facet takes across these subjects, distinct and sorted for
/// a pill's menu. The pick is always among them, even once nothing carries
/// it any more, so the menu still shows it checked and it can be cleared.
func facetValues<Subject: FacetSubject>(_ facet: Facet, in subjects: [Subject], picked: String?) -> [String] {
  var values = Set(subjects.compactMap { $0.facetValue(facet) })
  if let picked {
    values.insert(picked)
  }
  return values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}
