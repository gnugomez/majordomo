// The row of pills under the toolbar: one small glass menu per facet,
// narrowing the inbox or a board to an author, provider, or repository. A
// pill names its facet until something is picked, then shows the pick,
// accent-tinted.

import SwiftUI

struct FilterPillBar: View {
  let model: AppModel
  let facets: [FacetChoices]

  var body: some View {
    GlassEffectContainer(spacing: 6) {
      HStack(spacing: 6) {
        ForEach(facets) { choices in
          FilterPill(choices: choices) { value in
            model.setFacet(choices.facet, to: value)
          }
        }
      }
    }
    // Lined up under the toolbar's own glass.
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// One facet's pill: the chevron leads, then the facet or its pick.
private struct FilterPill: View {
  let choices: FacetChoices
  let pick: (String?) -> Void

  var body: some View {
    let facet = choices.facet
    Menu {
      Picker(facet.title, selection: Binding(get: { choices.picked }, set: { pick($0) })) {
        Text("Any \(facet.title)").tag(String?.none)
        Divider()
        ForEach(choices.values, id: \.self) { value in
          Text(facet.display(value)).tag(Optional(value))
        }
      }
      .pickerStyle(.inline)
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "chevron.down")
          .imageScale(.small)
          .fontWeight(.semibold)
        Text(choices.picked.map(facet.display) ?? facet.title)
          .lineLimit(1)
          // A facet's name keeps its start; a picked path keeps both ends.
          .truncationMode(choices.picked == nil ? .tail : .middle)
      }
      .font(.subheadline.weight(.medium))
      .foregroundStyle(choices.picked == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
      // Padded inside the label so the whole capsule takes the click.
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .contentShape(.capsule)
    }
    // The glass is the pill's own rather than the .glass button style, which
    // a menu draws as a flat gray fill. A plain button leaves the label
    // SwiftUI's to draw.
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .glassEffect(.regular.interactive(), in: .capsule)
    // Squeezed for width, the facet names give way before a pick does.
    .layoutPriority(choices.picked == nil ? 0 : 1)
    // A single value can't narrow anything; a pick stays clearable.
    .disabled(choices.picked == nil && choices.values.count < 2)
    .help(help)
  }

  private var help: String {
    guard let picked = choices.picked else {
      return "Filter by \(choices.facet.title.lowercased())"
    }
    return "Showing \(choices.facet.display(picked)) only"
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
