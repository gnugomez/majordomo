// The toolbar's filter, as Mail has it: one split control, the filter
// glyph and a chevron. A click on the glyph switches the filter off or back
// on, keeping what it is set to; the chevron opens its menu — the switch
// again, Unread Only, a date window, a pick per facet, and Clear Filters.
// What the filter holds shows in the window's subtitle while it is on, not
// as tokens in the search field: Escape and a fresh search clear those,
// and they can't show a set that is switched off.

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
    .help("Turn the filter on or off, or set what it shows")
    .accessibilityValue(active ? "On: \(summary)" : "Off")
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

/// The filter's menu. Its own view, so what it reads — the set, the scope,
/// the values in view — is read only where the menu is built, and the
/// control's label never reads it.
private struct FilterMenuItems: View {
  let model: AppModel
  let values: FacetValues

  var body: some View {
    // The glyph's click, here too: the toolbar's overflow menu lists this
    // menu but not the click, and VoiceOver names no chevron.
    Toggle("Filter", isOn: Binding(get: { model.filterActive }, set: { _ in model.toggleFilter() }))
    Divider()
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
    ForEach(offeredFacets, id: \.facet) { offered in
      FacetSubmenu(model: model, facet: offered.facet, enabled: offered.enabled, values: values)
    }
    Divider()
    Button("Clear Filters") {
      model.clearFilters()
    }
    .disabled(model.filter.isEmpty)
  }

  /// The facets the menu offers, and whether each can narrow anything
  /// here. Provider narrows only across accounts on more than one
  /// provider: it is offered while the accounts span them — or while it
  /// holds a pick, which must stay clearable — and in one account's inbox
  /// it stays, disabled, so the menu keeps one shape from inbox to inbox.
  private var offeredFacets: [(facet: Facet, enabled: Bool)] {
    let picks = model.facetPicks
    let spansProviders = Set(model.accounts.map(\.provider)).count > 1
    let oneAccount = model.selectedBoard == nil && model.sidebarSelection.account != nil
    return Facet.allCases.compactMap { facet in
      guard facet == .provider else {
        return (facet, true)
      }
      guard spansProviders || picks[facet] != nil else {
        return nil
      }
      return (facet, (spansProviders && !oneAccount) || picks[facet] != nil)
    }
  }
}

/// One facet's submenu, titled with its pick: Any, then every value in
/// view with how many rows it would leave.
private struct FacetSubmenu: View {
  let model: AppModel
  let facet: Facet
  let enabled: Bool
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
    .disabled(!enabled)
  }
}
