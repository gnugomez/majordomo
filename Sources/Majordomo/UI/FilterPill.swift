// The filter pills in the toolbar, beside the filter: one menu per facet,
// narrowing the inbox or a board to an author, provider, or repository. A
// pill names its facet until something is picked, then shows the pick,
// accent-tinted. Where the toolbar runs short they fold into one Filters
// menu holding a submenu per facet.

import SwiftUI

/// What a pill's menu offers for a facet, worked out when the menu is
/// built from what the search and the other pills leave in view.
typealias FacetValues = @MainActor (Facet) -> [String]

/// What decides how a pill draws: its facet, the pick, and whether it can
/// narrow anything.
struct PillState: Equatable, Identifiable, Sendable {
  let facet: Facet
  let picked: String?
  /// False while the scope can't be narrowed by this facet (the provider,
  /// in one account's inbox). A pick stays clearable regardless.
  let narrows: Bool

  var id: Facet { facet }
  var enabled: Bool { narrows || picked != nil }
}

/// One facet's pill. Equatable over what it draws and not over what its
/// menu offers: a toolbar item redraws with a fade whenever it updates, so
/// a pill handed the values would flicker on every push that touched the
/// inbox. The menu asks for them itself.
struct FilterPill: View, Equatable {
  let model: AppModel
  let pill: PillState
  let values: FacetValues

  nonisolated static func == (lhs: FilterPill, rhs: FilterPill) -> Bool {
    lhs.pill == rhs.pill
  }

  var body: some View {
    let facet = pill.facet
    Menu {
      FacetMenuItems(model: model, pill: pill, values: values)
    } label: {
      PillLabel(title: pill.picked.map(facet.display) ?? facet.title, active: pill.picked != nil)
    }
    .pillMenuStyle()
    .disabled(!pill.enabled)
    .help(help)
    .accessibilityLabel(pill.picked.map { "\(facet.title): \(facet.display($0))" } ?? facet.title)
  }

  private var help: String {
    guard let picked = pill.picked else {
      return "Filter by \(pill.facet.title.lowercased())"
    }
    return "Showing \(pill.facet.display(picked)) only"
  }
}

/// The pills folded into one menu, a submenu per facet, for a toolbar too
/// narrow to hold them side by side. Equatable for the pills' reason.
struct FilterPillMenu: View, Equatable {
  let model: AppModel
  let pills: [PillState]
  let values: FacetValues

  nonisolated static func == (lhs: FilterPillMenu, rhs: FilterPillMenu) -> Bool {
    lhs.pills == rhs.pills
  }

  var body: some View {
    let picked = pills.filter { $0.picked != nil }
    Menu {
      ForEach(pills) { pill in
        Menu(submenuTitle(pill)) {
          FacetMenuItems(model: model, pill: pill, values: values)
            // The submenu's own title already names the facet.
            .labelsHidden()
        }
        .disabled(!pill.enabled)
      }
    } label: {
      PillLabel(title: "Filters", active: !picked.isEmpty)
    }
    .pillMenuStyle()
    .help(picked.isEmpty ? "Filter by author, provider, or repository" : "Showing " + picked.map(pickPhrase).joined(separator: ", "))
  }

  private func submenuTitle(_ pill: PillState) -> String {
    pill.picked.map { "\(pill.facet.title): \(pill.facet.display($0))" } ?? pill.facet.title
  }

  private func pickPhrase(_ pill: PillState) -> String {
    pill.picked.map(pill.facet.display) ?? pill.facet.title
  }
}

/// A pill's menu: Any, then every value in view. Its own view, so the
/// values are asked for only where the menu is built, and the pill's label
/// never reads them.
private struct FacetMenuItems: View {
  let model: AppModel
  let pill: PillState
  let values: FacetValues

  var body: some View {
    let facet = pill.facet
    Picker(facet.title, selection: Binding(get: { pill.picked }, set: { model.setFacet(facet, to: $0) })) {
      Text("Any \(facet.title)").tag(String?.none)
      Divider()
      ForEach(values(facet), id: \.self) { value in
        Text(facet.display(value)).tag(Optional(value))
      }
    }
    .pickerStyle(.inline)
  }
}

/// A pill's face: the facet or its pick, then the chevron, filling the
/// toolbar item so its whole glass capsule takes the click.
private struct PillLabel: View {
  let title: String
  let active: Bool

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
        .lineLimit(1)
        // A long repository path keeps both ends.
        .truncationMode(.middle)
        .frame(maxWidth: 160)
      Image(systemName: "chevron.down")
        .imageScale(.small)
        .fontWeight(.semibold)
        .accessibilityHidden(true)
    }
    .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
    .padding(.horizontal, 10)
    .frame(maxHeight: .infinity)
    .contentShape(.rect)
  }
}

private extension View {
  /// A toolbar draws a `Menu` itself, from its label's image alone, and a
  /// text label shows as nothing but the menu's indicator; a plain-styled
  /// menu leaves the label SwiftUI's to draw, inside the item's own glass.
  func pillMenuStyle() -> some View {
    menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
  }
}

private extension Facet {
  /// How a value reads in the pill and its menu.
  func display(_ value: String) -> String {
    switch self {
    case .author: "@\(value)"
    case .provider: ProviderId(rawValue: value)?.displayName ?? value
    case .repository: value
    }
  }
}
