// The toolbar's filter, as Mail draws it: one split control, the filter
// glyph and a chevron. A click on the glyph filters to unread when nothing
// is picked and clears the filter when anything is; the chevron opens its
// menu — Unread Only, a date window, a pick per facet, and Clear Filters.
// Whatever is picked applies; it shows in the window's subtitle, not as
// tokens in the search field, which Escape and a fresh search would clear.

import AppKit
import SwiftUI

/// What a facet's menu offers once it opens: each value in view with its
/// count, worked out from what the search and the rest of the filter
/// leave of the inbox's category or the board.
typealias FacetValues = @MainActor (Facet) -> [FacetValue]

/// The filter's toolbar item. A toolbar item redraws with a fade whenever
/// it updates, so the control is Equatable over what decides how it looks
/// — whether it narrows, and what it narrows by, for VoiceOver — and never
/// over what its menu offers, which the menu asks for as it is built. The
/// tooltip holds still for the same reason.
struct FilterToolbarControl: View, Equatable {
  let model: AppModel
  /// Whether the filter narrows anything: on, with something set.
  let active: Bool
  /// What it narrows by, in words (`InboxFilter.summary`).
  let summary: String
  let values: FacetValues

  nonisolated static func == (lhs: FilterToolbarControl, rhs: FilterToolbarControl) -> Bool {
    lhs.active == rhs.active && lhs.summary == rhs.summary
  }

  var body: some View {
    // A primary action and the menu's own indicator make the item the
    // split glyph-and-chevron control.
    Menu {
      FilterMenuItems(model: model, values: values)
    } label: {
      Image(nsImage: Self.glyph(active: active))
        .accessibilityLabel("Filter")
    } primaryAction: {
      model.toggleFilter()
    }
    .help("Show only unread, or clear the filter; the arrow sets what it shows")
    // The toolbar builds the menu once and keeps it, ticks and titles as
    // they were; keyed by what the filter holds, any pick makes a fresh
    // one. The summary spells out the whole set.
    .id(summary)
    .accessibilityValue(active ? "Filtering by \(summary)" : "No filter")
  }

  /// The filter glyph as an NSImage. The toolbar draws its items' images
  /// itself, as templates, so no SwiftUI color modifier ever reaches them;
  /// a non-template image already painted in the accent color is how the
  /// active state shows.
  private static func glyph(active: Bool) -> NSImage {
    let glyph = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Filter")!
    guard active,
          let painted = glyph.withSymbolConfiguration(.init(paletteColors: [.controlAccentColor])) else {
      return glyph
    }
    painted.isTemplate = false
    return painted
  }
}

/// The filter's menu. Its own view, so what it reads — the set, the accounts,
/// the values in view — is read only where the menu is built, and the
/// control's label never reads it.
private struct FilterMenuItems: View {
  let model: AppModel
  let values: FacetValues

  var body: some View {
    Toggle("Unread Only", isOn: Binding(get: { model.unreadOnly }, set: { model.setUnreadOnly($0) }))
    Divider()
    Picker("Date", selection: Binding(get: { model.activityWindow }, set: { model.setActivityWindow($0) })) {
      Text("Any time").tag(ActivityWindow?.none)
      Divider()
      ForEach(ActivityWindow.allCases) { window in
        Text(window.label).tag(Optional(window))
      }
    }
    .pickerStyle(.inline)
    // The windows read for themselves; a header would only crowd them.
    .labelsHidden()
    Divider()
    let facets = offeredFacets(providers: Set(model.accounts.map(\.provider)), picks: model.facetPicks)
    ForEach(facets) { facet in
      FacetSubmenu(model: model, facet: facet, values: values)
    }
    Divider()
    Button("Clear Filters") {
      model.clearFilters()
    }
    .disabled(model.filter.isEmpty)
  }
}

/// One facet's submenu, titled with its pick: Any, then every value in
/// view with how many rows it would leave.
private struct FacetSubmenu: View {
  let model: AppModel
  let facet: Facet
  let values: FacetValues

  var body: some View {
    let picked = model.facetPicks[facet]
    Menu(picked.map { "\(facet.title): \(facet.display($0))" } ?? facet.title) {
      Picker(facet.title, selection: Binding(get: { picked }, set: { model.setFacet(facet, to: $0) })) {
        Text("Any \(facet.title)").tag(String?.none)
        Divider()
        ForEach(values(facet)) { offered in
          Text(facet.display(offered.value))
            .badge(offered.count)
            .tag(Optional(offered.value))
        }
      }
      .pickerStyle(.inline)
      // The submenu's own title already names the facet.
      .labelsHidden()
    }
  }
}
